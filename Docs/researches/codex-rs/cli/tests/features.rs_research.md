# features.rs 研究文档

## 场景与职责

`features.rs` 是 Codex CLI 的集成测试文件，负责测试 `codex features` 命令组的功能。该命令组用于管理 Codex 的功能标志（Feature Flags），允许用户启用、禁用和查看各种实验性功能。

**主要测试场景：**
- 验证 `features enable` 命令正确写入配置
- 验证 `features disable` 命令正确更新配置
- 验证开发中功能启用时显示警告
- 验证 `features list` 按字母顺序排序输出

## 功能点目的

### 1. 功能标志管理

Codex 使用功能标志系统来控制实验性、开发中和稳定功能的可用性：

- **开发中功能（Under Development）**：不稳定，可能行为异常
- **实验性功能（Experimental）**：可通过 `/experimental` 菜单访问
- **稳定功能（Stable）**：默认启用，可手动开关
- **已弃用功能（Deprecated）**：即将移除
- **已移除功能（Removed）**：保留标志位以兼容旧配置

### 2. 配置持久化

功能标志的变更会持久化到 `~/.codex/config.toml`：

```toml
[features]
unified_exec = true
shell_tool = false
```

### 3. 用户警告

启用开发中功能时，系统会显示警告：
```
Under-development features enabled: runtime_metrics. 
Under-development features are incomplete and may behave unpredictably.
```

## 具体技术实现

### 测试结构

```rust
#[tokio::test]
async fn features_enable_writes_feature_flag_to_config() -> Result<()>

#[tokio::test]
async fn features_disable_writes_feature_flag_to_config() -> Result<()>

#[tokio::test]
async fn features_enable_under_development_feature_prints_warning() -> Result<()>

#[tokio::test]
async fn features_list_is_sorted_alphabetically_by_feature_name() -> Result<()>
```

### 关键流程

#### 测试 1：启用功能

```rust
let mut cmd = codex_command(codex_home.path())?;
cmd.args(["features", "enable", "unified_exec"])
    .assert()
    .success()
    .stdout(contains("Enabled feature `unified_exec` in config.toml."));

let config = std::fs::read_to_string(codex_home.path().join("config.toml"))?;
assert!(config.contains("[features]"));
assert!(config.contains("unified_exec = true"));
```

#### 测试 2：禁用功能

```rust
cmd.args(["features", "disable", "shell_tool"])
    .assert()
    .success()
    .stdout(contains("Disabled feature `shell_tool` in config.toml."));

assert!(config.contains("shell_tool = false"));
```

#### 测试 3：开发中功能警告

```rust
cmd.args(["features", "enable", "runtime_metrics"])
    .assert()
    .success()
    .stderr(contains("Under-development features enabled: runtime_metrics."));
```

#### 测试 4：列表排序

```rust
let output = cmd.args(["features", "list"]).output()?;
let stdout = String::from_utf8(output.stdout)?;

let actual_names: Vec<_> = stdout.lines()
    .map(|line| line.split_once("  ").map(|(name, _)| name.trim_end().to_string()))
    .collect();
let mut expected_names = actual_names.clone();
expected_names.sort();

assert_eq!(actual_names, expected_names);
```

### 功能标志定义

**核心数据结构（`codex-rs/core/src/features.rs`）：**

```rust
/// 功能标志生命周期阶段
pub enum Stage {
    UnderDevelopment,
    Experimental { name: &'static str, menu_description: &'static str, announcement: &'static str },
    Stable,
    Deprecated,
    Removed,
}

/// 功能标志枚举
pub enum Feature {
    GhostCommit,      // undo
    ShellTool,        // shell_tool
    UnifiedExec,      // unified_exec
    JsRepl,           // js_repl
    CodeMode,         // code_mode
    // ... 更多功能
}

/// 功能规格定义
pub struct FeatureSpec {
    pub id: Feature,
    pub key: &'static str,
    pub stage: Stage,
    pub default_enabled: bool,
}

/// 功能标志注册表
pub const FEATURES: &[FeatureSpec] = &[
    FeatureSpec {
        id: Feature::ShellTool,
        key: "shell_tool",
        stage: Stage::Stable,
        default_enabled: true,
    },
    FeatureSpec {
        id: Feature::UnifiedExec,
        key: "unified_exec",
        stage: Stage::Stable,
        default_enabled: !cfg!(windows),
    },
    // ...
];
```

### 配置编辑

**配置编辑流程（`codex-rs/core/src/config/edit.rs`）：**

```rust
pub async fn enable_feature_in_config(interactive: &TuiCli, feature: &str) -> anyhow::Result<()> {
    FeatureToggles::validate_feature(feature)?;
    let codex_home = find_codex_home()?;
    ConfigEditsBuilder::new(&codex_home)
        .with_profile(interactive.config_profile.as_deref())
        .set_feature_enabled(feature, /*enabled*/ true)
        .apply()
        .await?;
    println!("Enabled feature `{feature}` in config.toml.");
    maybe_print_under_development_feature_warning(&codex_home, interactive, feature);
    Ok(())
}
```

**功能启用编辑（`ConfigEditsBuilder`）：**

```rust
pub fn set_feature_enabled(mut self, key: &str, enabled: bool) -> Self {
    let profile_scoped = self.profile.is_some();
    let segments = if let Some(profile) = self.profile.as_ref() {
        vec!["profiles".to_string(), profile.clone(), "features".to_string(), key.to_string()]
    } else {
        vec!["features".to_string(), key.to_string()]
    };
    
    // 对于默认 false 的功能，禁用时清除配置项而非写入 false
    let is_default_false_feature = FEATURES
        .iter()
        .find(|spec| spec.key == key)
        .is_some_and(|spec| !spec.default_enabled);
        
    if enabled || profile_scoped || !is_default_false_feature {
        self.edits.push(ConfigEdit::SetPath { segments, value: value(enabled) });
    } else {
        self.edits.push(ConfigEdit::ClearPath { segments });
    }
    self
}
```

### 列表输出格式

```rust
// 列表显示格式
for def in codex_core::features::FEATURES.iter() {
    let name = def.key;
    let stage = stage_str(def.stage);
    let enabled = config.features.enabled(def.id);
    rows.push((name, stage, enabled));
}
rows.sort_unstable_by_key(|(name, _, _)| *name);

// 输出格式：name  stage  enabled
// 示例：
// unified_exec   stable   true
// js_repl        experimental  false
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/cli/tests/features.rs` - 本测试文件

### 被测代码

#### CLI 入口
- `codex-rs/cli/src/main.rs`
  - `FeaturesCli` - 命令定义
  - `FeaturesSubcommand` - 子命令枚举
  - `enable_feature_in_config()` - 启用功能
  - `disable_feature_in_config()` - 禁用功能
  - `maybe_print_under_development_feature_warning()` - 警告输出

#### 功能标志核心
- `codex-rs/core/src/features.rs`
  - `Feature` - 功能标志枚举
  - `Stage` - 生命周期阶段
  - `FeatureSpec` - 规格定义
  - `FEATURES` - 注册表
  - `Features::from_config()` - 从配置加载

#### 配置编辑
- `codex-rs/core/src/config/edit.rs`
  - `ConfigEditsBuilder::set_feature_enabled()` - 设置功能状态
  - `ConfigEdit::SetPath` / `ConfigEdit::ClearPath` - 编辑操作

### 配置结构

```toml
# 全局功能配置
[features]
unified_exec = true
shell_tool = false

# 或在 profile 中配置
[profiles.work.features]
unified_exec = false
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `assert_cmd::Command` | 执行 CLI 命令 |
| `predicates::str::contains` | 输出内容匹配 |
| `pretty_assertions::assert_eq` | 美化断言差异 |
| `tempfile::TempDir` | 临时测试环境 |
| `tokio::test` | 异步测试运行时 |

### 内部依赖

| 模块 | 用途 |
|------|------|
| `codex_core::features` | 功能标志定义和检查 |
| `codex_core::config::edit::ConfigEditsBuilder` | 配置编辑 |
| `codex_core::config::Config` | 配置加载 |

### 文件系统交互

- 读取/写入 `~/.codex/config.toml`
- 使用 `TempDir` 隔离测试环境

## 风险、边界与改进建议

### 潜在风险

1. **功能标志变更**
   - 测试硬编码了功能名称（如 `"unified_exec"`）
   - 功能重命名或移除会导致测试失败
   - 建议：使用 `FEATURES` 注册表动态获取有效功能名

2. **配置格式变更**
   - 测试检查特定的 TOML 格式
   - 序列化格式变更可能影响断言

3. **并发测试**
   - 每个测试使用独立的 `TempDir`，无冲突
   - 但 `--enable`/`--disable` 全局标志可能影响其他测试

### 边界情况

当前测试未覆盖：

1. **无效功能名**
   ```rust
   // 未测试：codex features enable invalid_feature
   ```

2. **Profile 特定配置**
   ```rust
   // 未测试：-p profile_name features enable xxx
   ```

3. **配置冲突**
   - 全局启用 vs Profile 禁用

4. **并发编辑**
   - 多进程同时修改配置

### 改进建议

1. **增加测试覆盖**
   ```rust
   // 建议：无效功能名测试
   #[tokio::test]
   async fn features_enable_invalid_feature_fails() { ... }
   
   // 建议：Profile 特定配置测试
   #[tokio::test]
   async fn features_enable_with_profile() { ... }
   
   // 建议：配置持久化验证
   #[tokio::test]
   async fn features_persist_across_restarts() { ... }
   ```

2. **参数化测试**
   ```rust
   // 使用 test_case 或类似工具
   #[test_case("unified_exec", Stage::Stable)]
   #[test_case("runtime_metrics", Stage::UnderDevelopment)]
   #[tokio::test]
   async fn features_enable_by_stage(feature: &str, stage: Stage) { ... }
   ```

3. **配置验证**
   - 验证 TOML 语法正确性
   - 验证配置加载后功能状态正确

4. **边界测试**
   - 空功能名
   - 超长功能名
   - 特殊字符功能名

### 相关功能

- 功能标志与 `--enable`/`--disable` 命令行参数集成
- TUI 中的 `/experimental` 菜单显示实验性功能
- 遥测系统记录功能使用情况

### 配置建议

- 稳定功能变更应立即生效
- 实验性功能启用后可能需要重启
- 开发中功能警告可配置关闭：`suppress_unstable_features_warning = true`
