# api_bridge_tests.rs 深度研究文档

## 场景与职责

`api_bridge_tests.rs` 是 `api_bridge.rs` 的配套单元测试模块，专注于验证 API 错误映射逻辑和认证提供者行为。测试使用 `pretty_assertions` 提供清晰的失败 diff，并覆盖关键的错误转换路径。

### 测试覆盖范围
1. **服务器过载错误映射** - 503 状态码和特定错误码处理
2. **用量限制错误映射** - 429 状态码和限流头解析
3. **认证错误头提取** - 多来源 request-id 和错误详情
4. **认证提供者行为** - Token 附加检测

---

## 功能点目的

### 测试分类

| 测试函数 | 测试目标 | 验证点 |
|---------|---------|-------|
| `map_api_error_maps_server_overloaded` | 直接 ServerOverloaded 错误 | 枚举值直接映射 |
| `map_api_error_maps_server_overloaded_from_503_body` | 503 + server_is_overloaded | 从 body JSON 提取 |
| `map_api_error_maps_usage_limit_limit_name_header` | 429 + usage_limit_reached | 限流名称头解析 |
| `map_api_error_does_not_fallback_limit_name_to_limit_id` | 限流名称回退行为 | 不自动回退到 limit_id |
| `map_api_error_extracts_identity_auth_details_from_headers` | 401 响应头解析 | 多来源 ID 提取 |
| `core_auth_provider_reports_when_auth_header_will_attach` | 认证头附加检测 | Token 有效性检查 |

---

## 具体技术实现

### 服务器过载测试

```rust
#[test]
fn map_api_error_maps_server_overloaded() {
    let err = map_api_error(ApiError::ServerOverloaded);
    assert!(matches!(err, CodexErr::ServerOverloaded));
}

#[test]
fn map_api_error_maps_server_overloaded_from_503_body() {
    let body = serde_json::json!({
        "error": {
            "code": "server_is_overloaded"
        }
    }).to_string();
    
    let err = map_api_error(ApiError::Transport(TransportError::Http {
        status: http::StatusCode::SERVICE_UNAVAILABLE,
        url: Some("http://example.com/v1/responses".to_string()),
        headers: None,
        body: Some(body),
    }));

    assert!(matches!(err, CodexErr::ServerOverloaded));
}
```

### 用量限制测试

```rust
#[test]
fn map_api_error_maps_usage_limit_limit_name_header() {
    let mut headers = HeaderMap::new();
    headers.insert(ACTIVE_LIMIT_HEADER, HeaderValue::from_static("codex_other"));
    headers.insert("x-codex-other-limit-name", HeaderValue::from_static("codex_other"));
    
    let body = serde_json::json!({
        "error": {
            "type": "usage_limit_reached",
            "plan_type": "pro",
        }
    }).to_string();
    
    let err = map_api_error(ApiError::Transport(TransportError::Http {
        status: http::StatusCode::TOO_MANY_REQUESTS,
        url: Some("http://example.com/v1/responses".to_string()),
        headers: Some(headers),
        body: Some(body),
    }));

    let CodexErr::UsageLimitReached(usage_limit) = err else {
        panic!("expected CodexErr::UsageLimitReached, got {err:?}");
    };
    
    // 验证限流名称正确提取
    assert_eq!(
        usage_limit.rate_limits.as_ref()
            .and_then(|s| s.limit_name.as_deref()),
        Some("codex_other")
    );
}
```

### 认证详情提取测试

```rust
#[test]
fn map_api_error_extracts_identity_auth_details_from_headers() {
    let mut headers = HeaderMap::new();
    headers.insert(REQUEST_ID_HEADER, HeaderValue::from_static("req-401"));
    headers.insert(CF_RAY_HEADER, HeaderValue::from_static("ray-401"));
    headers.insert(
        X_OPENAI_AUTHORIZATION_ERROR_HEADER,
        HeaderValue::from_static("missing_authorization_header"),
    );
    
    // Base64 编码的 JSON: {"error":{"code":"token_expired"}}
    let x_error_json = base64::engine::general_purpose::STANDARD
        .encode(r#"{"error":{"code":"token_expired"}}"#);
    headers.insert(
        X_ERROR_JSON_HEADER,
        HeaderValue::from_str(&x_error_json).expect("valid header"),
    );

    let err = map_api_error(ApiError::Transport(TransportError::Http {
        status: http::StatusCode::UNAUTHORIZED,
        url: Some("https://chatgpt.com/backend-api/codex/models".to_string()),
        headers: Some(headers),
        body: Some(r#"{"detail":"Unauthorized"}"#.to_string()),
    }));

    let CodexErr::UnexpectedStatus(err) = err else {
        panic!("expected CodexErr::UnexpectedStatus, got {err:?}");
    };
    
    assert_eq!(err.request_id.as_deref(), Some("req-401"));
    assert_eq!(err.cf_ray.as_deref(), Some("ray-401"));
    assert_eq!(err.identity_authorization_error.as_deref(), Some("missing_authorization_header"));
    assert_eq!(err.identity_error_code.as_deref(), Some("token_expired"));
}
```

### 认证提供者测试

```rust
#[test]
fn core_auth_provider_reports_when_auth_header_will_attach() {
    let auth = CoreAuthProvider {
        token: Some("access-token".to_string()),
        account_id: None,
    };

    assert!(auth.auth_header_attached());
    assert_eq!(auth.auth_header_name(), Some("authorization"));
}
```

---

## 关键代码路径与文件引用

### 测试模块结构
```rust
#[cfg(test)]
#[path = "api_bridge_tests.rs"]
mod tests;
```

### 依赖项
```rust
use super::*;  // map_api_error, CoreAuthProvider, 常量等
use base64::Engine;
use pretty_assertions::assert_eq;
```

### 被测函数
- `map_api_error()` - 核心错误映射函数
- `CoreAuthProvider::auth_header_attached()` - 认证头检测
- `CoreAuthProvider::auth_header_name()` - 认证头名称

---

## 依赖与外部交互

### 测试数据构造
测试使用 `serde_json::json!` 宏构造请求体，使用 `http::HeaderMap` 构造响应头：

```rust
let body = serde_json::json!({
    "error": {
        "type": "usage_limit_reached",
        "plan_type": "pro",
    }
}).to_string();
```

### 外部依赖
| 依赖 | 用途 |
|-----|------|
| `pretty_assertions` | 测试失败时提供结构化 diff |
| `base64::Engine` | 编码测试用的 x-error-json |
| `http::StatusCode` | HTTP 状态码常量 |
| `http::HeaderMap` | 响应头构造 |

---

## 风险、边界与改进建议

### 测试覆盖缺口

1. **缺失测试：slow_down 错误码**
   - 代码中处理 `"slow_down"` 与 `"server_is_overloaded"` 相同
   - 但测试只覆盖了后者

2. **缺失测试：InvalidImageRequest**
   - 400 响应中图片数据无效的检测逻辑未测试

3. **缺失测试：InternalServerError**
   - 500 状态码映射未测试

4. **缺失测试：RetryLimit**
   - 429 非 usage_limit_reached 场景未测试

5. **缺失测试：认证优先级**
   - `auth_provider_from_auth()` 的多种输入组合未测试

6. **缺失测试：TransportError 变体**
   - `TransportError::RetryLimit` 未测试
   - `TransportError::Timeout` 未测试
   - `TransportError::Network` / `Build` 未测试

### 改进建议

1. **参数化测试**
   ```rust
   #[test_case("server_is_overloaded", CodexErr::ServerOverloaded)]
   #[test_case("slow_down", CodexErr::ServerOverloaded)]
   fn test_503_error_codes(code: &str, expected: CodexErr) { ... }
   ```

2. **使用 insta 快照测试**
   ```rust
   #[test]
   fn usage_limit_error_snapshot() {
       let err = create_usage_limit_error();
       insta::assert_debug_snapshot!(err);
   }
   ```

3. **添加边界测试**
   - 空 header map
   - 非 UTF-8 header 值
   - 超大 body

4. **认证提供者完整测试**
   ```rust
   #[test]
   fn auth_provider_priority_api_key_over_auth() {
       // 验证 API Key 优先级高于 CodexAuth
   }
   ```
