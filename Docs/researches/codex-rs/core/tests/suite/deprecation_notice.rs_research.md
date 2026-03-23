# deprecation_notice.rs 深度研究文档

## 场景与职责

`deprecation_notice.rs` 是 Codex 核心测试套件中负责验证**配置弃用警告机制**的测试文件。其核心职责是确保：

1. 当用户使用已弃用的配置项时，系统能够正确检测到并发出警告
2. 弃用警告包含清晰的摘要信息和详细的迁移指导
3. 新旧配置项的映射关系正确维护

该测试文件体现了 Codex 对**向后兼容性**的重视，在演进配置系统的同时，确保现有用户能够平滑迁移。

## 功能点目的

### 1. 特性标志弃用检测
- **目的**：检测 `[features]` 配置段中已弃用的特性开关
- **示例**：`use_experimental_unified_exec_tool` → `unified_exec`

### 2. 顶层配置项弃用检测
- **目的**：检测已移除或重命名的顶层配置项
- **示例**：`experimental_instructions_file` → `model_instructions_file`

### 3. 布尔值特性标志弃用
- **目的**：处理从布尔值变为枚举类型的配置项
- **示例**：`web_search_request = true/false` → `web_search = "live"/"cached"/"disabled"`

## 具体技术实现

### 弃用检测架构

```rust
// codex-rs/core/src/features.rs
pub enum Stage {
    UnderDevelopment,    // 开发中
    Experimental { ... }, // 实验性功能
    Stable,              // 稳定功能
    Deprecated,          // 已弃用（本测试关注）
    Removed,             // 已移除
}

pub struct FeatureSpec {
    pub id: Feature,
    pub key: &'static str,
    pub stage: Stage,
    pub default_enabled: bool,
}
```

### 弃用警告生成流程

1. **配置解析阶段** (`Features::from_config`):
```rust
pub fn from_config(cfg: &ConfigToml, config_profile: &ConfigProfile, overrides: FeatureOverrides) -> Self {
    // 应用旧版特性开关
    let base_legacy = LegacyFeatureToggles { ... };
    base_legacy.apply(&mut features);
    
    // 应用新特性配置
    if let Some(base_features) = cfg.features.as_ref() {
        features.apply_map(&base_features.entries);
    }
    
    features.normalize_dependencies();
    features
}
```

2. **旧版用法记录** (`record_legacy_usage`):
```rust
pub fn record_legacy_usage(&mut self, alias: &str, feature: Feature) {
    if alias == feature.key() {
        return;  // 非别名，不记录
    }
    self.record_legacy_usage_force(alias, feature);
}

pub fn record_legacy_usage_force(&mut self, alias: &str, feature: Feature) {
    let (summary, details) = legacy_usage_notice(alias, feature);
    self.legacy_usages.insert(LegacyFeatureUsage {
        alias: alias.to_string(),
        feature,
        summary,
        details,
    });
}
```

3. **警告消息生成** (`legacy_usage_notice`):
```rust
fn legacy_usage_notice(alias: &str, feature: Feature) -> (String, Option<String>) {
    let canonical = feature.key();
    match feature {
        Feature::WebSearchRequest | Feature::WebSearchCached => {
            // 特殊处理 web_search 相关弃用
            let summary = format!("`{label}` is deprecated because web search is enabled by default.");
            (summary, Some(web_search_details().to_string()))
        }
        _ => {
            let summary = format!("`{label}` is deprecated. Use `[features].{canonical}` instead.");
            let details = Some(format!(
                "Enable it with `--enable {canonical}` or `[features].{canonical}` in config.toml."
            ));
            (summary, details)
        }
    }
}
```

4. **事件发射** (codex.rs):
```rust
// 在 SessionConfigured 后发射弃用警告
for usage in features.legacy_feature_usages() {
    post_session_configured_events.push(Event {
        id: "".to_owned(),
        msg: EventMsg::DeprecationNotice(DeprecationNoticeEvent {
            summary: usage.summary.clone(),
            details: usage.details.clone(),
        }),
    });
}
```

### 协议定义

```rust
// codex-rs/protocol/src/protocol.rs
pub struct DeprecationNoticeEvent {
    pub summary: String,
    pub details: Option<String>,
}

// codex-rs/app-server-protocol/src/protocol/common.rs
#[derive(ExperimentalApi)]
pub struct DeprecationNoticeNotification {
    pub summary: String,
    pub details: Option<String>,
}
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/core/tests/suite/deprecation_notice.rs` - 本测试文件

### 核心实现
- `codex-rs/core/src/features.rs` - 特性标志和弃用检测核心
  - `legacy_usage_notice` - 生成弃用提示消息
  - `record_legacy_usage` - 记录旧版用法
  - `LegacyFeatureToggles` - 旧版特性开关映射

- `codex-rs/core/src/features/legacy.rs` - 旧版特性处理
  - 定义 `use_experimental_unified_exec_tool` 等旧配置到新特性的映射

- `codex-rs/core/src/codex.rs` - 会话初始化时发射弃用事件

### 协议定义
- `codex-rs/protocol/src/protocol.rs` - `DeprecationNoticeEvent`
- `codex-rs/app-server-protocol/src/protocol/common.rs` - `DeprecationNoticeNotification`
- `codex-rs/app-server-protocol/src/protocol/v2.rs` - v2 API 协议定义

### 配置加载
- `codex-rs/core/src/config_loader.rs` - 配置层栈处理
- `codex-rs/core/src/config.rs` - `Config` 结构定义

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `codex_core::features` | 特性标志和弃用检测 |
| `codex_core::config_loader` | 配置层栈解析 |
| `codex_protocol::protocol::DeprecationNoticeEvent` | 协议事件类型 |
| `core_test_support` | 测试基础设施 |

### 测试工具
```rust
// 测试中使用 TestCodex 构建器注入配置
let mut builder = test_codex().with_config(|config| {
    let mut features = config.features.get().clone();
    features.enable(Feature::UnifiedExec);
    features.record_legacy_usage_force("use_experimental_unified_exec_tool", Feature::UnifiedExec);
    config.features.set(features).expect("...");
    config.use_experimental_unified_exec_tool = true;
});
```

### 配置层栈测试
```rust
// 测试 experimental_instructions_file 弃用
let config_layer = ConfigLayerEntry::new(
    ConfigLayerSource::User { file: test_absolute_path("/tmp/config.toml") },
    TomlValue::Table(table),
);
let config_layer_stack = ConfigLayerStack::new(
    vec![config_layer],
    ConfigRequirements::default(),
    ConfigRequirementsToml::default(),
)?;
config.config_layer_stack = config_layer_stack;
```

## 风险、边界与改进建议

### 已知风险

1. **弃用消息重复**
   - 风险：同一弃用项可能从多个配置层触发重复警告
   - 现状：`LegacyFeatureUsage` 使用 `BTreeSet` 去重

2. **配置层优先级混淆**
   - 风险：用户可能在多个配置层（全局/项目/用户）设置冲突的弃用项
   - 缓解：配置层栈按优先级合并，高优先级覆盖低优先级

3. **弃用与移除的边界**
   - 风险：`Deprecated` 和 `Removed` 阶段的行为不一致
   - 现状：Removed 阶段的特性完全失效，不产生警告

### 边界情况

1. **别名与正式名相同**
   - 处理：`record_legacy_usage` 检查 `alias == feature.key()`，相同则不记录

2. **布尔值到枚举的迁移**
   - 特殊处理：`web_search_request` 需要额外逻辑指导用户设置新的枚举值

3. **空配置层栈**
   - 处理：默认创建空栈，不产生任何弃用警告

### 改进建议

1. **弃用时间表**
   - 为每个弃用项添加计划移除版本
   - 示例：`#[deprecated(since = "1.5.0", note = "Use unified_exec")]`

2. **自动迁移工具**
   - 提供 `codex config migrate` 命令自动重写配置文件
   - 生成迁移前后的 diff 预览

3. **弃用遥测**
   - 收集弃用项使用频率（匿名化）
   - 帮助决策何时可以安全移除旧代码

4. **增强测试**
   - 添加多配置层冲突测试
   - 添加动态配置重载时的弃用检测测试
   - 添加弃用项与正式项同时存在时的优先级测试

5. **文档集成**
   - 弃用详情中直接包含迁移文档链接
   - 支持 Markdown 格式的详细说明
