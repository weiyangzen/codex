# tags.rs 深度研究文档

## 场景与职责

`tags.rs` 定义了 Codex 指标系统中使用的标签键常量，以及会话级别的标签值构建器。它是指标标签系统的核心，负责：

1. **标签键标准化**：统一标签键名称，避免拼写错误
2. **会话标签构建**：`SessionMetricTagValues` 结构体将会话元数据转换为指标标签
3. **标签验证**：在构建标签时验证 key 和 value 的合法性
4. **可选标签支持**：支持某些标签为可选（如 `auth_mode`, `service_name`）

该模块被 `events/session_telemetry.rs` 使用，为所有指标自动附加会话级别的标签。

## 功能点目的

### 1. 标签键常量

```rust
pub const APP_VERSION_TAG: &str = "app.version";
pub const AUTH_MODE_TAG: &str = "auth_mode";
pub const MODEL_TAG: &str = "model";
pub const ORIGINATOR_TAG: &str = "originator";
pub const SERVICE_NAME_TAG: &str = "service_name";
pub const SESSION_SOURCE_TAG: &str = "session_source";
```

所有标签键遵循小写 + 下划线命名规范。

### 2. SessionMetricTagValues - 会话标签构建器

```rust
pub struct SessionMetricTagValues<'a> {
    pub auth_mode: Option<&'a str>,      // 认证模式（可选）
    pub session_source: &'a str,         // 会话来源（如 "cli", "exec"）
    pub originator: &'a str,             // 发起者（如 "codex_cli"）
    pub service_name: Option<&'a str>,   // 服务名（可选）
    pub model: &'a str,                  // 模型名
    pub app_version: &'a str,            // 应用版本
}
```

### 3. 标签构建流程

```rust
impl<'a> SessionMetricTagValues<'a> {
    pub fn into_tags(self) -> Result<Vec<(&'static str, &'a str)>> {
        let mut tags = Vec::with_capacity(6);
        // 按固定顺序添加标签
        Self::push_optional_tag(&mut tags, AUTH_MODE_TAG, self.auth_mode)?;
        Self::push_optional_tag(&mut tags, SESSION_SOURCE_TAG, Some(self.session_source))?;
        Self::push_optional_tag(&mut tags, ORIGINATOR_TAG, Some(self.originator))?;
        Self::push_optional_tag(&mut tags, SERVICE_NAME_TAG, self.service_name)?;
        Self::push_optional_tag(&mut tags, MODEL_TAG, Some(self.model))?;
        Self::push_optional_tag(&mut tags, APP_VERSION_TAG, Some(self.app_version))?;
        Ok(tags)
    }
}
```

## 具体技术实现

### 标签构建实现

```rust
impl<'a> SessionMetricTagValues<'a> {
    pub fn into_tags(self) -> Result<Vec<(&'static str, &'a str)>> {
        // 预分配容量（最大可能的标签数）
        let mut tags = Vec::with_capacity(6);
        
        // 按固定顺序添加标签
        Self::push_optional_tag(&mut tags, AUTH_MODE_TAG, self.auth_mode)?;
        Self::push_optional_tag(&mut tags, SESSION_SOURCE_TAG, Some(self.session_source))?;
        Self::push_optional_tag(&mut tags, ORIGINATOR_TAG, Some(self.originator))?;
        Self::push_optional_tag(&mut tags, SERVICE_NAME_TAG, self.service_name)?;
        Self::push_optional_tag(&mut tags, MODEL_TAG, Some(self.model))?;
        Self::push_optional_tag(&mut tags, APP_VERSION_TAG, Some(self.app_version))?;
        
        Ok(tags)
    }

    fn push_optional_tag(
        tags: &mut Vec<(&'static str, &'a str)>,
        key: &'static str,
        value: Option<&'a str>,
    ) -> Result<()> {
        let Some(value) = value else {
            return Ok(());  // 可选标签为 None 时跳过
        };
        // 验证 key 和 value
        validate_tag_key(key)?;
        validate_tag_value(value)?;
        tags.push((key, value));
        Ok(())
    }
}
```

### 使用示例

```rust
// session_telemetry.rs
fn metadata_tag_refs(&self) -> MetricsResult<Vec<(&str, &str)>> {
    if !self.metrics_use_metadata_tags {
        return Ok(Vec::new());
    }
    SessionMetricTagValues {
        auth_mode: self.metadata.auth_mode.as_deref(),
        session_source: self.metadata.session_source.as_str(),
        originator: self.metadata.originator.as_str(),
        service_name: self.metadata.service_name.as_deref(),
        model: self.metadata.model.as_str(),
        app_version: self.metadata.app_version,
    }
    .into_tags()
}

// 使用标签
let tags = self.tags_with_metadata(&[("tool", "shell"), ("success", "true")])?;
metrics.counter(TOOL_CALL_COUNT_METRIC, 1, &tags)?;
```

### 测试覆盖

```rust
#[test]
fn session_metric_tags_include_expected_tags_in_order() {
    let tags = SessionMetricTagValues {
        auth_mode: Some("api_key"),
        session_source: "cli",
        originator: "codex_cli",
        service_name: Some("desktop_app"),
        model: "gpt-5.1",
        app_version: "1.2.3",
    }
    .into_tags()
    .expect("tags");

    assert_eq!(tags, vec![
        (AUTH_MODE_TAG, "api_key"),
        (SESSION_SOURCE_TAG, "cli"),
        (ORIGINATOR_TAG, "codex_cli"),
        (SERVICE_NAME_TAG, "desktop_app"),
        (MODEL_TAG, "gpt-5.1"),
        (APP_VERSION_TAG, "1.2.3"),
    ]);
}

#[test]
fn session_metric_tags_skip_missing_optional_tags() {
    let tags = SessionMetricTagValues {
        auth_mode: None,           // 可选，跳过
        session_source: "exec",
        originator: "codex_exec",
        service_name: None,        // 可选，跳过
        model: "gpt-5.1",
        app_version: "1.2.3",
    }
    .into_tags()
    .expect("tags");

    assert_eq!(tags, vec![
        (SESSION_SOURCE_TAG, "exec"),
        (ORIGINATOR_TAG, "codex_exec"),
        (MODEL_TAG, "gpt-5.1"),
        (APP_VERSION_TAG, "1.2.3"),
    ]);
}
```

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `validation.rs` | `validate_tag_key`, `validate_tag_value` |
| `error.rs` | `Result` 类型 |

### 调用方

| 文件 | 使用场景 |
|------|----------|
| `events/session_telemetry.rs` | `metadata_tag_refs()` 方法构建会话标签 |
| `lib.rs` | 重新导出标签常量 |

### 外部导出

```rust
// lib.rs
pub use crate::metrics::tags;  // 公开导出 tags 模块
```

## 依赖与外部交互

### 标签流向

```
SessionTelemetryMetadata (session_telemetry.rs)
    ├─ auth_mode: Option<String>
    ├─ session_source: String
    ├─ originator: String
    ├─ service_name: Option<String>
    ├─ model: String
    └─ app_version: &'static str
           ↓
    SessionMetricTagValues::into_tags() (tags.rs)
           ↓
    Vec<(&'static str, &'a str)> 标签列表
           ↓
    与调用方标签合并
           ↓
    MetricsClient::counter/histogram/record_duration
```

### 标签示例

```
codex.tool.call{
    auth_mode="api_key",
    session_source="cli",
    originator="codex_cli",
    service_name="desktop_app",
    model="gpt-5.1",
    app_version="1.2.3",
    tool="shell",
    success="true"
} 1
```

## 风险、边界与改进建议

### 当前风险

1. **生命周期依赖**: `SessionMetricTagValues` 依赖外部引用的生命周期 `'a`
2. **验证开销**: 每次构建标签都进行验证，可能影响性能
3. **顺序硬编码**: 标签顺序在代码中固定，修改可能影响下游依赖
4. **容量预分配**: 预分配容量 6 是硬编码，新增字段需同步更新

### 边界情况

1. **空可选标签**: `auth_mode: None` 和 `service_name: None` 被正确跳过
2. **空字符串值**: 验证器会拒绝空字符串标签值
3. **非法字符**: 验证器会拒绝包含非法字符的 key/value
4. **全 None 可选**: 如果所有可选字段都是 None，最少只有 4 个标签

### 改进建议

1. **缓存验证结果**:
   ```rust
   // 对已知合法的常量 key 跳过验证
   const KNOWN_KEYS: &[&str] = &[APP_VERSION_TAG, AUTH_MODE_TAG, ...];
   ```

2. **构建器模式**:
   ```rust
   let tags = SessionMetricTags::builder()
       .auth_mode("api_key")
       .session_source("cli")
       .build()?;
   ```

3. **宏简化**:
   ```rust
   define_tags! {
       optional: [auth_mode, service_name],
       required: [session_source, originator, model, app_version],
   }
   ```

4. **静态标签**:
   ```rust
   // 对不会变化的标签（如 app_version）使用 &'static str
   pub struct StaticSessionTags {
       pub app_version: &'static str,
   }
   ```

5. **标签分组**:
   ```rust
   pub mod session {
       pub const AUTH_MODE: &str = "auth_mode";
       pub const SOURCE: &str = "session_source";
       // ...
   }
   ```

6. **文档增强**:
   ```rust
   /// Authentication mode used for the session.
   /// 
   /// Examples: "api_key", "chatgpt"
   pub const AUTH_MODE_TAG: &str = "auth_mode";
   ```
