# api_bridge.rs 深度研究文档

## 场景与职责

`api_bridge.rs` 是 Codex CLI 与底层 `codex_api` crate 之间的**错误转换与认证桥接层**。该模块负责将底层 API 错误映射为高层业务错误，并处理认证令牌的传递。

### 核心职责
1. **错误映射**：将 `codex_api::ApiError` 转换为 `CodexErr`
2. **HTTP 响应解析**：从响应头中提取错误详情、限流信息
3. **认证适配**：将 Codex 认证信息转换为 API 认证提供者
4. **使用限制处理**：解析用量限制错误，提取重置时间、计划类型等信息

---

## 功能点目的

### 1. 错误类型映射体系

| ApiError 类型 | CodexErr 类型 | 触发场景 |
|-------------|--------------|---------|
| `ContextWindowExceeded` | `ContextWindowExceeded` | 上下文窗口溢出 |
| `QuotaExceeded` | `QuotaExceeded` | 配额耗尽 |
| `UsageNotIncluded` | `UsageNotIncluded` | 计划不包含 Codex 功能 |
| `ServerOverloaded` | `ServerOverloaded` | 服务器过载 |
| `Retryable { delay }` | `Stream(msg, delay)` | 可重试错误，带延迟 |
| `RateLimit(msg)` | `Stream(msg, None)` | 速率限制 |
| `Transport(Http { status, body })` | 多种类型 | 根据 HTTP 状态码细分 |

### 2. HTTP 状态码细分处理

```rust
// 503 Service Unavailable
if status == SERVICE_UNAVAILABLE && body.code == "server_is_overloaded" {
    return CodexErr::ServerOverloaded;
}

// 400 Bad Request
if status == BAD_REQUEST {
    if body.contains("invalid image") {
        CodexErr::InvalidImageRequest()
    } else {
        CodexErr::InvalidRequest(body_text)
    }
}

// 429 Too Many Requests
if status == TOO_MANY_REQUESTS {
    if error_type == "usage_limit_reached" {
        CodexErr::UsageLimitReached(...)  // 提取限流详情
    } else if error_type == "usage_not_included" {
        CodexErr::UsageNotIncluded
    } else {
        CodexErr::RetryLimit(...)  // 重试次数耗尽
    }
}

// 500 Internal Server Error
if status == INTERNAL_SERVER_ERROR {
    CodexErr::InternalServerError
}
```

### 3. 响应头提取

| Header | 用途 |
|-------|------|
| `x-codex-active-limit` | 当前生效的限流名称 |
| `x-request-id` / `x-oai-request-id` | 请求追踪 ID |
| `cf-ray` | Cloudflare 追踪 ID |
| `x-openai-authorization-error` | 认证错误详情 |
| `x-error-json` (base64) | 额外的错误 JSON |

---

## 具体技术实现

### 核心错误转换函数

```rust
pub(crate) fn map_api_error(err: ApiError) -> CodexErr {
    match err {
        ApiError::ContextWindowExceeded => CodexErr::ContextWindowExceeded,
        ApiError::QuotaExceeded => CodexErr::QuotaExceeded,
        ApiError::UsageNotIncluded => CodexErr::UsageNotIncluded,
        ApiError::Retryable { message, delay } => CodexErr::Stream(message, delay),
        ApiError::ServerOverloaded => CodexErr::ServerOverloaded,
        
        // 复杂的 Transport 错误处理
        ApiError::Transport(TransportError::Http { status, url, headers, body }) => {
            handle_http_error(status, url, headers, body)
        }
        
        // ... 其他映射
    }
}
```

### 使用限制错误解析

```rust
#[derive(Debug, Deserialize)]
struct UsageErrorResponse {
    error: UsageErrorBody,
}

#[derive(Debug, Deserialize)]
struct UsageErrorBody {
    #[serde(rename = "type")]
    error_type: Option<String>,
    plan_type: Option<PlanType>,
    resets_at: Option<i64>,  // Unix 时间戳
}

// 解析限流信息
let rate_limits = headers.as_ref().and_then(|map| {
    parse_rate_limit_for_limit(map, limit_id.as_deref())
});
let promo_message = headers.as_ref().and_then(parse_promo_message);
let resets_at = err.error.resets_at
    .and_then(|seconds| DateTime::<Utc>::from_timestamp(seconds, 0));
```

### 认证提供者实现

```rust
#[derive(Clone, Default)]
pub(crate) struct CoreAuthProvider {
    token: Option<String>,
    account_id: Option<String>,
}

impl ApiAuthProvider for CoreAuthProvider {
    fn bearer_token(&self) -> Option<String> {
        self.token.clone()
    }

    fn account_id(&self) -> Option<String> {
        self.account_id.clone()
    }
}

// 从 CodexAuth 构建
pub(crate) fn auth_provider_from_auth(
    auth: Option<CodexAuth>,
    provider: &ModelProviderInfo,
) -> Result<CoreAuthProvider> {
    // 优先级：API Key > Experimental Bearer Token > CodexAuth
    if let Some(api_key) = provider.api_key()? {
        return Ok(CoreAuthProvider { token: Some(api_key), account_id: None });
    }
    if let Some(token) = provider.experimental_bearer_token.clone() {
        return Ok(CoreAuthProvider { token: Some(token), account_id: None });
    }
    if let Some(auth) = auth {
        let token = auth.get_token()?;
        Ok(CoreAuthProvider { 
            token: Some(token), 
            account_id: auth.get_account_id() 
        })
    } else {
        Ok(CoreAuthProvider::default())
    }
}
```

### 响应头提取工具函数

```rust
fn extract_header(headers: Option<&HeaderMap>, name: &str) -> Option<String> {
    headers.and_then(|map| {
        map.get(name)
            .and_then(|value| value.to_str().ok())
            .map(str::to_string)
    })
}

fn extract_x_error_json_code(headers: Option<&HeaderMap>) -> Option<String> {
    let encoded = extract_header(headers, X_ERROR_JSON_HEADER)?;
    let decoded = base64::engine::general_purpose::STANDARD
        .decode(encoded)
        .ok()?;
    let parsed = serde_json::from_slice::<Value>(&decoded).ok()?;
    parsed
        .get("error")
        .and_then(|error| error.get("code"))
        .and_then(Value::as_str)
        .map(str::to_string)
}
```

---

## 关键代码路径与文件引用

### 核心文件
| 文件 | 说明 |
|-----|------|
| `codex-rs/core/src/api_bridge.rs` | 主实现文件（246行） |
| `codex-rs/core/src/api_bridge_tests.rs` | 单元测试（143行） |

### 调用方（上游）
- `codex-rs/core/src/client/` - 模型客户端，调用 `map_api_error()`
- `codex-rs/core/src/codex.rs` - 主会话循环，调用 `auth_provider_from_auth()`

### 被调用方（下游）
- `codex_api::rate_limits` - 限流解析函数
  - `parse_promo_message()` - 解析促销信息
  - `parse_rate_limit_for_limit()` - 解析限流详情

### 相关错误定义
- `codex-rs/core/src/error.rs` - `CodexErr` 定义
- `codex_api::error::ApiError` - 底层 API 错误

---

## 依赖与外部交互

### 外部 Crate 依赖
```rust
use codex_api::AuthProvider as ApiAuthProvider;
use codex_api::TransportError;
use codex_api::error::ApiError;
use codex_api::rate_limits::{parse_promo_message, parse_rate_limit_for_limit};
use base64::Engine;  // 用于解码 x-error-json
use chrono::{DateTime, Utc};  // 时间戳解析
```

### HTTP Header 常量
```rust
const ACTIVE_LIMIT_HEADER: &str = "x-codex-active-limit";
const REQUEST_ID_HEADER: &str = "x-request-id";
const OAI_REQUEST_ID_HEADER: &str = "x-oai-request-id";
const CF_RAY_HEADER: &str = "cf-ray";
const X_OPENAI_AUTHORIZATION_ERROR_HEADER: &str = "x-openai-authorization-error";
const X_ERROR_JSON_HEADER: &str = "x-error-json";
```

### 认证优先级
```
1. provider.api_key()          ← 最高优先级
2. provider.experimental_bearer_token
3. auth.get_token()            ← 用户登录态
4. None                        ← 最低优先级（匿名）
```

---

## 风险、边界与改进建议

### 已知风险

1. **Base64 解码失败静默**
   ```rust
   let decoded = base64::engine::general_purpose::STANDARD
       .decode(encoded)
       .ok()?;  // 失败时返回 None，无日志
   ```
   **建议**：添加 debug 日志记录解码失败

2. **Header 解析严格依赖大小写**
   - HTTP/2 要求小写 header，但某些代理可能不规范
   - **建议**：使用 `HeaderMap` 的大小写不敏感查找

3. **时间戳解析可能溢出**
   ```rust
   DateTime::<Utc>::from_timestamp(seconds, 0)  // i64 可能溢出
   ```
   **建议**：添加边界检查

### 边界情况

| 场景 | 当前行为 |
|-----|---------|
| `x-error-json` 非有效 base64 | 静默忽略 |
| `x-error-json` 解码后非有效 JSON | 静默忽略 |
| `resets_at` 为负数或极大值 | 返回 None |
| 多个 request-id header | 优先使用 `x-request-id` |
| 空 body 的 429 响应 | 视为 RetryLimit |

### 改进建议

1. **增强可观测性**
   ```rust
   tracing::debug!(
       status = ?status,
       error_type = ?err.error.error_type,
       "mapping api error"
   );
   ```

2. **规范化 Header 处理**
   ```rust
   // 使用 http crate 的标准方法
   headers.get_unchecked(name)  // 大小写不敏感
   ```

3. **添加错误链保留**
   ```rust
   pub enum CodexErr {
       #[error("api error: {0}")]
       Api(#[source] ApiError),  // 保留原始错误
   }
   ```

4. **测试覆盖增强**
   - 测试各种 HTTP 状态码组合
   - 测试 malformed header 场景
   - 测试认证优先级逻辑
