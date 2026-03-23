# validation.rs 深度研究文档

## 场景与职责

`validation.rs` 实现了 Codex 指标系统的数据验证功能。它是指标数据质量的守门人，负责：

1. **指标名验证**：确保指标名符合命名规范
2. **标签验证**：确保标签 key 和 value 符合规范
3. **批量验证**：支持批量验证标签映射
4. **早期失败**：在数据产生前验证，避免无效数据进入系统

该模块被 `client.rs`, `config.rs`, `tags.rs` 调用，是指标系统的验证权威源。

## 功能点目的

### 1. 验证函数

| 函数 | 用途 | 验证规则 |
|------|------|----------|
| `validate_tags()` | 批量验证标签映射 | 遍历验证每个 key/value |
| `validate_metric_name()` | 验证指标名 | 非空 + 合法字符 |
| `validate_tag_key()` | 验证标签 key | 非空 + 合法字符 |
| `validate_tag_value()` | 验证标签 value | 非空 + 合法字符 |

### 2. 合法字符定义

```rust
// 指标名合法字符
fn is_metric_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-')
}

// 标签合法字符（比指标名多允许 '/'）
fn is_tag_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-' | '/')
}
```

### 3. 验证规则差异

| 规则 | 指标名 | 标签 key | 标签 value |
|------|--------|----------|------------|
| 非空 | ✓ | ✓ | ✓ |
| 字母数字 | ✓ | ✓ | ✓ |
| `.` | ✓ | ✓ | ✓ |
| `_` | ✓ | ✓ | ✓ |
| `-` | ✓ | ✓ | ✓ |
| `/` | ✗ | ✓ | ✓ |

## 具体技术实现

### 批量标签验证

```rust
pub(crate) fn validate_tags(tags: &BTreeMap<String, String>) -> Result<()> {
    for (key, value) in tags {
        validate_tag_key(key)?;
        validate_tag_value(value)?;
    }
    Ok(())
}
```

在 `MetricsConfig` 构建时调用，确保默认标签合法。

### 指标名验证

```rust
pub(crate) fn validate_metric_name(name: &str) -> Result<()> {
    // 1. 检查非空
    if name.is_empty() {
        return Err(MetricsError::EmptyMetricName);
    }
    // 2. 检查字符合法性
    if !name.chars().all(is_metric_char) {
        return Err(MetricsError::InvalidMetricName {
            name: name.to_string(),
        });
    }
    Ok(())
}
```

### 标签组件验证

```rust
pub(crate) fn validate_tag_key(key: &str) -> Result<()> {
    validate_tag_component(key, "tag key")
}

pub(crate) fn validate_tag_value(value: &str) -> Result<()> {
    validate_tag_component(value, "tag value")
}

fn validate_tag_component(value: &str, label: &str) -> Result<()> {
    // 1. 检查非空
    if value.is_empty() {
        return Err(MetricsError::EmptyTagComponent {
            label: label.to_string(),
        });
    }
    // 2. 检查字符合法性
    if !value.chars().all(is_tag_char) {
        return Err(MetricsError::InvalidTagComponent {
            label: label.to_string(),
            value: value.to_string(),
        });
    }
    Ok(())
}
```

### 字符检查函数

```rust
fn is_metric_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-')
}

fn is_tag_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-' | '/')
}
```

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `error.rs` | `MetricsError`, `Result` |

### 调用方

| 文件 | 使用场景 |
|------|----------|
| `client.rs` | `counter()`, `histogram()`, `duration_histogram()` 验证指标名；`attributes()` 验证标签 |
| `config.rs` | `with_tag()` 验证默认标签；`new()` 验证所有默认标签 |
| `tags.rs` | `push_optional_tag()` 验证会话标签 |

### 验证调用链

```
MetricsClient::counter(name, ...)
    ↓
validate_metric_name(name)?
    ↓
self.attributes(tags)?
    ↓
validate_tag_key(key)?
validate_tag_value(value)?
```

## 依赖与外部交互

### 验证时机

```
配置阶段（config.rs）
    ├─ MetricsConfig::with_tag(key, value)
    │   └─ validate_tag_key(key)?
    │   └─ validate_tag_value(value)?
    └─ MetricsConfig::new() 隐式调用
        └─ validate_tags(&default_tags)?

运行时阶段（client.rs）
    ├─ MetricsClient::counter(name, ...)
    │   └─ validate_metric_name(name)?
    │   └─ attributes(tags)?
    │       └─ validate_tag_key(key)?
    │       └─ validate_tag_value(value)?
    ├─ MetricsClient::histogram(name, ...)
    │   └─ 同上
    └─ MetricsClient::record_duration(name, ...)
        └─ 同上
```

### 错误传播

```rust
// 验证失败时返回具体错误
Err(MetricsError::InvalidMetricName { name: "bad name".to_string() })
Err(MetricsError::InvalidTagComponent { label: "tag key", value: "bad key" })
Err(MetricsError::EmptyTagComponent { label: "tag value" })
```

## 风险、边界与改进建议

### 当前风险

1. **重复验证**: 每次指标操作都验证，可能影响性能
2. **字符集限制**: 标签允许 `/` 但指标名不允许，规则不一致
3. **长度限制**: 没有最大长度限制，可能导致超长指标名
4. **大小写敏感**: 未规范大小写，可能导致 `MyMetric` 和 `mymetric` 被视为不同

### 边界情况

1. **Unicode 字符**: `is_ascii_alphanumeric()` 拒绝所有非 ASCII 字符
2. **空字符串**: 明确检查并返回 `Empty*` 错误
3. **全非法字符**: 每个字符都检查，返回 `Invalid*` 错误
4. **首尾非法字符**: 与中间非法字符同等处理

### 改进建议

1. **性能优化**:
   ```rust
   // 对已知合法的常量跳过验证
   pub(crate) fn validate_metric_name_maybe(name: &str, is_known: bool) -> Result<()> {
       if is_known { return Ok(()); }
       validate_metric_name(name)
   }
   ```

2. **长度限制**:
   ```rust
   const MAX_METRIC_NAME_LEN: usize = 255;
   const MAX_TAG_KEY_LEN: usize = 128;
   const MAX_TAG_VALUE_LEN: usize = 256;
   
   if name.len() > MAX_METRIC_NAME_LEN {
       return Err(MetricsError::MetricNameTooLong { name: name.to_string(), max: MAX_METRIC_NAME_LEN });
   }
   ```

3. **规范化**:
   ```rust
   // 强制小写
   pub(crate) fn normalize_metric_name(name: &str) -> String {
       name.to_lowercase()
   }
   ```

4. **预编译正则**:
   ```rust
   use once_cell::sync::Lazy;
   use regex::Regex;
   
   static METRIC_NAME_RE: Lazy<Regex> = Lazy::new(|| {
       Regex::new(r"^[a-zA-Z0-9._-]+$").unwrap()
   });
   ```

5. **更详细的错误**:
   ```rust
   #[error("metric name contains invalid character '{invalid_char}' at position {pos}")]
   InvalidMetricName {
       name: String,
       invalid_char: char,
       pos: usize,
   },
   ```

6. **白名单模式**:
   ```rust
   // 对特定已知指标名使用白名单，跳过验证
   const KNOWN_METRICS: &[&str] = &["codex.tool.call", "codex.api_request", ...];
   ```

7. **配置化规则**:
   ```rust
   pub struct ValidationRules {
       pub allow_unicode: bool,
       pub max_name_len: usize,
       pub max_tag_key_len: usize,
       pub max_tag_value_len: usize,
   }
   ```
