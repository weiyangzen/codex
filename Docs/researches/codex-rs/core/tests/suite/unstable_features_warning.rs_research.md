# unstable_features_warning.rs 研究文档

## 场景与职责

`unstable_features_warning.rs` 是 Codex 核心测试套件中专门测试**不稳定特性警告系统**的集成测试文件。该测试文件验证当用户启用处于 "UnderDevelopment" 阶段的特性标志时，系统能够正确发出警告通知。

该测试文件位于 `codex-rs/core/tests/suite/unstable_features_warning.rs`，代码量约 100 行，包含 2 个核心测试用例。

### 核心职责

1. **验证不稳定特性警告发射**：当通过配置启用开发中特性时，系统应发出警告事件
2. **验证警告抑制功能**：用户可以通过配置禁用不稳定特性警告
3. **确保配置系统正确集成**：验证 TOML 配置与特性系统的联动

---

## 功能点目的

### 测试用例概览

| 测试函数 | 目的 |
|---------|------|
| `emits_warning_when_unstable_features_enabled_via_config` | 验证启用不稳定特性时发出警告 |
| `suppresses_warning_when_configured` | 验证配置 `suppress_unstable_features_warning = true` 可抑制警告 |

### 详细功能说明

#### 1. 警告发射测试 (`emits_warning_when_unstable_features_enabled_via_config`)

**测试场景**：
- 创建一个临时配置目录
- 加载默认测试配置
- 启用 `Feature::ChildAgentsMd`（处于 UnderDevelopment 阶段的特性）
- 构建用户配置层，在 TOML 中设置 `features.child_agents_md = true`
- 创建 ThreadManager 并恢复线程
- 等待并验证警告事件

**验证点**：
- 警告消息包含特性名称 `child_agents_md`
- 警告消息包含 "Under-development features enabled" 提示
- 警告消息包含抑制警告的配置方法 `suppress_unstable_features_warning = true`

#### 2. 警告抑制测试 (`suppresses_warning_when_configured`)

**测试场景**：
- 与第一个测试类似，但额外设置 `config.suppress_unstable_features_warning = true`
- 使用 `tokio::time::timeout` 等待警告事件
- 验证超时（即警告未发出）

**验证点**：
- 设置抑制标志后，警告事件不应被发射
- 使用 150ms 超时验证警告确实被抑制

---

## 具体技术实现

### 关键代码流程

#### 警告发射测试流程

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn emits_warning_when_unstable_features_enabled_via_config() {
    // 1. 创建临时目录作为 codex_home
    let home = TempDir::new().expect("tempdir");
    
    // 2. 加载默认测试配置
    let mut config = load_default_config_for_test(&home).await;
    
    // 3. 启用不稳定特性
    config.features.enable(Feature::ChildAgentsMd).expect(...);
    
    // 4. 构建用户配置层
    let user_config_path = AbsolutePathBuf::from_absolute_path(
        config.codex_home.join(CONFIG_TOML_FILE)
    ).expect("absolute user config path");
    
    config.config_layer_stack = config.config_layer_stack.with_user_config(
        &user_config_path,
        toml! { features = { child_agents_md = true } }.into(),
    );
    
    // 5. 创建 ThreadManager
    let thread_manager = codex_core::test_support::thread_manager_with_models_provider(
        CodexAuth::from_api_key("test"),
        config.model_provider.clone(),
    );
    let auth_manager = codex_core::test_support::auth_manager_from_auth(
        CodexAuth::from_api_key("test")
    );
    
    // 6. 恢复线程
    let NewThread { thread: conversation, .. } = thread_manager
        .resume_thread_with_history(config, InitialHistory::New, auth_manager, false, None)
        .await
        .expect("spawn conversation");
    
    // 7. 等待警告事件
    let warning = wait_for_event(&conversation, |ev| matches!(ev, EventMsg::Warning(_))).await;
    
    // 8. 验证警告内容
    let EventMsg::Warning(WarningEvent { message }) = warning else { panic!(...) };
    assert!(message.contains("child_agents_md"));
    assert!(message.contains("Under-development features enabled"));
    assert!(message.contains("suppress_unstable_features_warning = true"));
}
```

### 警告抑制实现

```rust
// 在配置中设置抑制标志
config.suppress_unstable_features_warning = true;

// 使用超时验证警告未发出
let warning = timeout(
    Duration::from_millis(150),
    wait_for_event(&conversation, |ev| matches!(ev, EventMsg::Warning(_)))
).await;
assert!(warning.is_err());  // 超时表示警告被抑制
```

---

## 关键代码路径与文件引用

### 被测代码路径

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/src/features.rs` | 特性标志定义和警告发射逻辑 |
| `codex-rs/core/src/config/mod.rs` | Config 结构定义，包含 `suppress_unstable_features_warning` |
| `codex-rs/core/src/config/types.rs` | 配置类型定义 |

### 关键函数

#### `maybe_push_unstable_features_warning`

位于 `codex-rs/core/src/features.rs` (行 875-923)：

```rust
pub fn maybe_push_unstable_features_warning(
    config: &Config,
    post_session_configured_events: &mut Vec<Event>,
) {
    // 1. 检查抑制标志
    if config.suppress_unstable_features_warning {
        return;
    }
    
    // 2. 收集启用的开发中特性
    let mut under_development_feature_keys = Vec::new();
    if let Some(table) = config.config_layer_stack.effective_config()
        .get("features")
        .and_then(TomlValue::as_table) {
        for (key, value) in table {
            // 检查特性是否启用且处于 UnderDevelopment 阶段
            if value.as_bool() == Some(true) {
                if let Some(spec) = FEATURES.iter().find(|spec| spec.key == key.as_str()) {
                    if config.features.enabled(spec.id) 
                        && matches!(spec.stage, Stage::UnderDevelopment) {
                        under_development_feature_keys.push(spec.key.to_string());
                    }
                }
            }
        }
    }
    
    // 3. 如果没有开发中特性，直接返回
    if under_development_feature_keys.is_empty() {
        return;
    }
    
    // 4. 构建并推送警告事件
    let message = format!(
        "Under-development features enabled: {}. Under-development features are incomplete...",
        under_development_feature_keys.join(", ")
    );
    post_session_configured_events.push(Event {
        id: "".to_owned(),
        msg: EventMsg::Warning(WarningEvent { message }),
    });
}
```

### Feature 枚举定义

位于 `codex-rs/core/src/features.rs` (行 76-191)：

```rust
pub enum Feature {
    // ... 其他特性 ...
    /// Append additional AGENTS.md guidance to user instructions.
    ChildAgentsMd,  // 测试中使用的特性
    // ...
}
```

### FeatureSpec 和 Stage

```rust
pub struct FeatureSpec {
    pub id: Feature,
    pub key: &'static str,
    pub stage: Stage,
    pub default_enabled: bool,
}

pub enum Stage {
    UnderDevelopment,  // 开发中阶段
    Experimental { name, menu_description, announcement },
    Stable,
    Deprecated,
    Removed,
}
```

### ChildAgentsMd 特性定义

```rust
FeatureSpec {
    id: Feature::ChildAgentsMd,
    key: "child_agents_md",
    stage: Stage::UnderDevelopment,
    default_enabled: false,
},
```

---

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `tempfile::TempDir` | 创建临时配置目录 |
| `tokio::time::timeout` | 超时等待验证警告抑制 |
| `toml::toml!` | TOML 配置内联宏 |

### 内部依赖

| 模块 | 用途 |
|-----|------|
| `codex_config::CONFIG_TOML_FILE` | 配置文件名常量 |
| `codex_core::CodexAuth` | 认证管理 |
| `codex_core::features::Feature` | 特性标志枚举 |
| `codex_core::test_support::*` | 测试支持函数 |
| `codex_protocol::protocol::*` | 协议事件类型 |
| `codex_utils_absolute_path::AbsolutePathBuf` | 绝对路径处理 |
| `core_test_support::*` | 测试支持库 |

### 配置层系统

测试使用了 Codex 的配置层系统（ConfigLayerStack）：

```rust
config.config_layer_stack = config.config_layer_stack.with_user_config(
    &user_config_path,
    toml! { features = { child_agents_md = true } }.into(),
);
```

这允许测试模拟用户通过 `config.toml` 启用特性的场景。

---

## 风险、边界与改进建议

### 已知风险

1. **特性状态变更风险**：`ChildAgentsMd` 特性可能从 `UnderDevelopment` 转移到其他阶段，导致测试失效
2. **硬编码特性名称**：测试中硬编码了 `"child_agents_md"`，如果特性重命名需要同步更新
3. **超时敏感性**：抑制测试使用 150ms 超时，在慢速 CI 环境可能不稳定

### 边界情况

1. **多特性启用**：当前测试仅验证单个特性，未测试多个不稳定特性同时启用的场景
2. **特性依赖关系**：未测试不稳定特性之间的依赖关系（如 `SpawnCsv` 自动启用 `Collab`）
3. **配置层优先级**：未测试不同配置层（全局、用户、项目）中特性启用的优先级

### 改进建议

1. **增加多特性测试**：
   ```rust
   async fn emits_warning_for_multiple_unstable_features() {
       // 同时启用多个不稳定特性，验证警告包含所有特性名称
   }
   ```

2. **增加特性状态变更测试**：
   ```rust
   async fn no_warning_when_feature_becomes_stable() {
       // 验证当特性从 UnderDevelopment 变为 Stable 后不再发出警告
   }
   ```

3. **增加配置层优先级测试**：
   ```rust
   async fn unstable_warning_respects_config_layer_priority() {
       // 验证用户配置层覆盖全局配置层的特性启用状态
   }
   ```

4. **改进超时处理**：
   - 使用更长的超时时间（如 500ms）或
   - 使用事件计数器而非超时来验证警告抑制

5. **文档完善**：
   - 添加注释说明 `ChildAgentsMd` 为何被选择为测试特性
   - 说明测试对特性状态的依赖关系

### 相关配置项

```toml
# config.toml 示例
suppress_unstable_features_warning = true  # 抑制不稳定特性警告

[features]
child_agents_md = true  # 启用开发中特性
```

### 测试执行建议

```bash
# 运行特定测试
cargo test -p codex-core emits_warning_when_unstable_features_enabled_via_config
cargo test -p codex-core suppresses_warning_when_configured

# 运行整个不稳定特性警告测试模块
cargo test -p codex-core unstable_features_warning
```
