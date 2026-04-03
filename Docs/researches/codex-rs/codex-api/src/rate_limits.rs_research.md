# rate_limits.rs 研究文档

## 场景与职责

`rate_limits.rs` 是 `codex-api` crate 的速率限制解析模块，负责从 HTTP 响应头中提取和解析速率限制信息。该模块是 Codex 服务配额管理的关键组件：

1. **响应头解析**: 解析 `x-codex-*` 系列速率限制头
2. **多限制族支持**: 支持主限制（codex）和次要限制（codex_other 等）
3. **事件解析**: 解析 WebSocket 中的 `codex.rate_limits` 事件
4. **促销消息提取**: 解析 `x-codex-promo-message` 头

在架构中，该模块将底层的 HTTP 头转换为结构化的 `RateLimitSnapshot`，供上层（UI、遥测、重试逻辑）使用。

## 功能点目的

### 1. 速率限制头解析
解析以下格式的头：
- `x-codex-primary-used-percent`: 主窗口使用百分比
- `x-codex-primary-window-minutes`: 主窗口时长（分钟）
- `x-codex-primary-reset-at`: 主窗口重置时间戳
- `x-codex-secondary-*`: 次要窗口（通常用于周限制）
- `x-codex-credits-*`: 积分相关信息
- `x-codex-limit-name`: 限制名称（如 "gpt-5.2-codex-sonic"）

### 2. 多限制族支持
支持动态限制 ID：
- 默认族：`codex`
- 扩展族：`codex_other`, `codex_bengalfox` 等
- 自动发现：扫描所有头，识别 `-primary-used-percent` 后缀的模式

### 3. 速率限制事件解析
解析 WebSocket 中的 JSON 事件：
```json
{
  "type": "codex.rate_limits",
  "plan_type": "pro",
  "rate_limits": {
    "primary": {"used_percent": 50.0, "window_minutes": 60, "reset_at": 1704069000},
    "secondary": {...}
  },
  "credits": {"has_credits": true, "unlimited": false, "balance": "100.00"}
}
```

### 4. 促销消息提取
解析 `x-codex-promo-message` 头，用于显示账户相关的促销或通知信息。

## 具体技术实现

### 关键数据结构

```rust
/// 速率限制错误（简单字符串包装）
pub struct RateLimitError {
    pub message: String,
}

/// 解析用的内部结构（匹配 JSON 事件格式）
#[derive(Debug, Deserialize)]
struct RateLimitEvent {
    #[serde(rename = "type")]
    kind: String,
    plan_type: Option<PlanType>,
    rate_limits: Option<RateLimitEventDetails>,
    credits: Option<RateLimitEventCredits>,
    metered_limit_name: Option<String>,
    limit_name: Option<String>,
}
```

### 核心解析算法

#### 单限制族解析
```rust
pub fn parse_rate_limit_for_limit(
    headers: &HeaderMap,
    limit_id: Option<&str>,
) -> Option<RateLimitSnapshot> {
    // 1. 规范化 limit_id（默认 "codex"，下划线转连字符）
    let normalized_limit = limit_id
        .map(str::trim)
        .filter(|name| !name.is_empty())
        .unwrap_or("codex")
        .to_ascii_lowercase()
        .replace('_', "-");
    let prefix = format!("x-{normalized_limit}");
    
    // 2. 解析主窗口
    let primary = parse_rate_limit_window(
        headers,
        &format!("{prefix}-primary-used-percent"),
        &format!("{prefix}-primary-window-minutes"),
        &format!("{prefix}-primary-reset-at"),
    );
    
    // 3. 解析次要窗口
    let secondary = parse_rate_limit_window(...);
    
    // 4. 解析积分信息
    let credits = parse_credits_snapshot(headers);
    
    // 5. 解析限制名称
    let limit_name = parse_header_str(headers, &format!("{prefix}-limit-name"))
        .map(...);
    
    Some(RateLimitSnapshot { ... })
}
```

#### 多限制族发现
```rust
pub fn parse_all_rate_limits(headers: &HeaderMap) -> Vec<RateLimitSnapshot> {
    let mut snapshots = Vec::new();
    
    // 1. 添加默认限制族
    if let Some(snapshot) = parse_default_rate_limit(headers) {
        snapshots.push(snapshot);
    }
    
    // 2. 发现所有限制 ID
    let mut limit_ids: BTreeSet<String> = BTreeSet::new();
    for name in headers.keys() {
        let header_name = name.as_str().to_ascii_lowercase();
        if let Some(limit_id) = header_name_to_limit_id(&header_name) {
            limit_ids.insert(limit_id);
        }
    }
    
    // 3. 解析每个限制族
    snapshots.extend(limit_ids.into_iter().filter_map(|limit_id| {
        let snapshot = parse_rate_limit_for_limit(headers, Some(limit_id.as_str()))?;
        has_rate_limit_data(&snapshot).then_some(snapshot)
    }));
    
    snapshots
}
```

#### 限制 ID 发现算法
```rust
fn header_name_to_limit_id(header_name: &str) -> Option<String> {
    let suffix = "-primary-used-percent";
    let prefix = header_name.strip_suffix(suffix)?;
    let limit = prefix.strip_prefix("x-")?;
    Some(normalize_limit_id(limit.to_string()))
}

fn normalize_limit_id(name: impl Into<String>) -> String {
    name.into().trim().to_ascii_lowercase().replace('-', "_")
}
```

### 辅助解析函数

```rust
fn parse_rate_limit_window(
    headers: &HeaderMap,
    used_percent_header: &str,
    window_minutes_header: &str,
    resets_at_header: &str,
) -> Option<RateLimitWindow> {
    let used_percent: Option<f64> = parse_header_f64(headers, used_percent_header);
    
    used_percent.and_then(|used_percent| {
        let window_minutes = parse_header_i64(headers, window_minutes_header);
        let resets_at = parse_header_i64(headers, resets_at_header);
        
        // 有数据才返回（used_percent != 0 或有其他字段）
        let has_data = used_percent != 0.0
            || window_minutes.is_some_and(|minutes| minutes != 0)
            || resets_at.is_some();
        
        has_data.then_some(RateLimitWindow { ... })
    })
}

fn parse_header_f64(headers: &HeaderMap, name: &str) -> Option<f64> {
    parse_header_str(headers, name)?
        .parse::<f64>()
        .ok()
        .filter(|v| v.is_finite())  // 过滤 NaN/Infinity
}

fn parse_header_bool(headers: &HeaderMap, name: &str) -> Option<bool> {
    let raw = parse_header_str(headers, name)?;
    if raw.eq_ignore_ascii_case("true") || raw == "1" {
        Some(true)
    } else if raw.eq_ignore_ascii_case("false") || raw == "0" {
        Some(false)
    } else {
        None
    }
}
```

## 关键代码路径与文件引用

### 内部调用关系
```
rate_limits.rs
├── parse_default_rate_limit (公开)
├── parse_all_rate_limits (公开，被 sse/responses.rs 使用)
├── parse_rate_limit_for_limit (公开)
├── parse_rate_limit_event (公开，被 responses_websocket.rs 使用)
├── parse_promo_message (公开)
└── 内部辅助函数
    ├── parse_rate_limit_window
    ├── parse_credits_snapshot
    ├── parse_header_f64/i64/bool/str
    ├── has_rate_limit_data
    ├── header_name_to_limit_id
    └── normalize_limit_id
```

### 被调用方
- `codex-rs/codex-api/src/sse/responses.rs`: `parse_all_rate_limits(&stream_response.headers)`
- `codex-rs/codex-api/src/endpoint/responses_websocket.rs`: `parse_rate_limit_event(&text)`
- `codex-rs/codex-api/src/error.rs`: `From<RateLimitError> for ApiError`

### 依赖类型
- `codex_protocol::protocol::RateLimitSnapshot`: 输出结构
- `codex_protocol::protocol::RateLimitWindow`: 窗口结构
- `codex_protocol::protocol::CreditsSnapshot`: 积分结构
- `codex_protocol::account::PlanType`: 账户类型

## 依赖与外部交互

### 外部依赖
| Crate | 用途 |
|-------|------|
| `codex_protocol` | `RateLimitSnapshot`, `RateLimitWindow`, `CreditsSnapshot`, `PlanType` |
| `http` | `HeaderMap`, `HeaderValue` |
| `serde` | 事件 JSON 反序列化 |
| `std::collections::BTreeSet` | 限制 ID 去重 |

### 协议规范
- **头格式**: `x-{limit_id}-{window_type}-{field}`
- **limit_id 规范化**: 下划线 `_` 和连字符 `-` 等价，内部使用下划线
- **JSON 事件**: `type` 字段必须为 `"codex.rate_limits"`

## 风险、边界与改进建议

### 已知风险

1. **浮点精度问题**
   - `used_percent` 使用 `f64`，可能存在精度问题
   - 过滤了 `NaN` 和 `Infinity`，但 `-0.0` 仍可能通过
   - 建议：考虑使用定点数或百分比整数

2. **头名大小写敏感**
   - HTTP 头名理论上大小写不敏感，但实现中多次 `to_ascii_lowercase()`
   - `HeaderMap::get` 本身大小写不敏感，但自定义解析逻辑可能有问题
   - 建议：统一使用 `http` crate 的大小写不敏感查找

3. **空数据误判**
   - `has_rate_limit_data` 要求 `used_percent != 0.0`
   - 如果服务器返回 `used_percent: 0` 但有其他有效字段，会被过滤
   - 建议：放宽条件，或单独检查每个字段

4. **限制 ID 冲突**
   - `normalize_limit_id` 将 `-` 替换为 `_`
   - `codex-other` 和 `codex_other` 会被视为相同
   - 这可能是预期行为，但需要文档说明

### 边界条件

1. **空 HeaderMap**: 返回默认 `codex` 快照，所有字段为 `None`
2. **部分头缺失**: 缺失的头解析为 `None`，不影响其他字段
3. **非法数值**: 非数字字符串导致该字段为 `None`
4. **超大数值**: `i64` 解析可能溢出（但 HTTP 头通常不会）

### 改进建议

1. **日志增强**
   ```rust
   if let Err(e) = value.parse::<f64>() {
       tracing::debug!("Failed to parse rate limit header {}: {}", name, e);
   }
   ```

2. **常量提取**
   ```rust
   pub const RATE_LIMIT_HEADER_PREFIX: &str = "x-codex";
   pub const PRIMARY_USED_PERCENT_SUFFIX: &str = "primary-used-percent";
   // ...
   ```

3. **验证函数**
   ```rust
   impl RateLimitSnapshot {
       pub fn is_valid(&self) -> bool {
           self.primary.as_ref().map_or(true, |w| {
               (0.0..=100.0).contains(&w.used_percent)
           })
       }
   }
   ```

4. **测试覆盖**
   - 当前测试覆盖主要场景
   - 建议添加：
     - 非法数值处理测试
     - 超大 HeaderMap 性能测试
     - 并发解析测试（如果会被多线程使用）

5. **文档完善**
   ```rust
   /// Parses rate limit headers with the following precedence:
   /// 1. `x-{limit_id}-primary-used-percent` (required for window to be present)
   /// 2. `x-{limit_id}-primary-window-minutes` (optional)
   /// 3. `x-{limit_id}-primary-reset-at` (optional, Unix timestamp)
   /// 
   /// # Normalization
   /// - `limit_id` is case-insensitive
   /// - Hyphens and underscores are equivalent in `limit_id`
   /// - Default `limit_id` is "codex"
   ```

6. **性能优化**
   ```rust
   // 使用 lazy_static 或 once_cell 缓存正则表达式（如果需要复杂匹配）
   // 当前实现是线性扫描，对于大量头可能较慢
   ```
