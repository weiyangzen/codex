# responses.rs 深度研究文档

## 场景与职责

`responses.rs` 是 Codex 网络代理的 HTTP 响应生成模块，负责：

1. **策略拒绝响应**：生成标准化的策略拒绝 HTTP 响应
2. **错误消息映射**：将内部拒绝原因转换为用户友好的错误消息
3. **响应格式支持**：支持纯文本和 JSON 格式的响应
4. **HTTP 头管理**：设置适当的 HTTP 状态码和错误标识头

该模块是网络代理与用户（或调用方）交互的界面层，确保策略决策以清晰、一致的方式传达。

## 功能点目的

### 1. 策略决策详情 (`PolicyDecisionDetails`)

封装策略决策的完整信息，用于响应生成：
- `decision`：决策类型（Deny/Ask）
- `reason`：拒绝原因（来自 `reasons.rs`）
- `source`：决策来源
- `protocol`：网络协议
- `host` / `port`：目标地址

### 2. 响应生成函数

**基础响应**：
- `text_response()`：生成纯文本响应
- `json_response()`：生成 JSON 响应

**策略拒绝响应**：
- `blocked_text_response()`：纯文本拒绝响应
- `blocked_text_response_with_policy()`：带策略详情的拒绝响应
- `blocked_message_with_policy()`：生成带策略详情的错误消息

### 3. 错误消息映射

将内部拒绝原因映射为用户友好的消息：

| 原因 | 用户消息 |
|------|----------|
| `not_allowed` | "domain not in allowlist (this is not a denylist block)" |
| `not_allowed_local` | "local/private addresses not allowed" |
| `denied` | "domain denied by policy" |
| `method_not_allowed` | "method not allowed in limited mode" |
| `mitm_required` | "MITM required for limited HTTPS" |

### 4. HTTP 错误头映射

将拒绝原因映射为机器可读的 HTTP 头值：

| 原因 | X-Proxy-Error 头值 |
|------|-------------------|
| `not_allowed` / `not_allowed_local` | `blocked-by-allowlist` |
| `denied` | `blocked-by-denylist` |
| `method_not_allowed` | `blocked-by-method-policy` |
| `mitm_required` | `blocked-by-mitm-required` |
| 其他 | `blocked-by-policy` |

## 具体技术实现

### 纯文本响应生成

```rust
pub fn text_response(status: StatusCode, body: &str) -> Response {
    Response::builder()
        .status(status)
        .header("content-type", "text/plain")
        .body(Body::from(body.to_string()))
        .unwrap_or_else(|_| Response::new(Body::from(body.to_string())))
}
```

### JSON 响应生成

```rust
pub fn json_response<T: Serialize>(value: &T) -> Response {
    let body = match serde_json::to_string(value) {
        Ok(body) => body,
        Err(err) => {
            error!("failed to serialize JSON response: {err}");
            "{}".to_string()
        }
    };
    Response::builder()
        .status(StatusCode::OK)
        .header("content-type", "application/json")
        .body(Body::from(body))
        .unwrap_or_else(|err| {
            error!("failed to build JSON response: {err}");
            Response::new(Body::from("{}"))
        })
}
```

### 策略拒绝响应生成

```rust
pub fn blocked_text_response_with_policy(
    reason: &str,
    details: &PolicyDecisionDetails<'_>,
) -> Response {
    Response::builder()
        .status(StatusCode::FORBIDDEN)
        .header("content-type", "text/plain")
        .header("x-proxy-error", blocked_header_value(reason))
        .body(Body::from(blocked_message_with_policy(reason, details)))
        .unwrap_or_else(|_| Response::new(Body::from("blocked")))
}
```

### 错误消息映射实现

```rust
pub fn blocked_message(reason: &str) -> &'static str {
    match reason {
        REASON_NOT_ALLOWED => {
            "Codex blocked this request: domain not in allowlist (this is not a denylist block)."
        }
        REASON_NOT_ALLOWED_LOCAL => {
            "Codex blocked this request: local/private addresses not allowed."
        }
        REASON_DENIED => "Codex blocked this request: domain denied by policy.",
        REASON_METHOD_NOT_ALLOWED => {
            "Codex blocked this request: method not allowed in limited mode."
        }
        REASON_MITM_REQUIRED => "Codex blocked this request: MITM required for limited HTTPS.",
        _ => "Codex blocked this request by network policy.",
    }
}
```

### HTTP 头值映射

```rust
pub fn blocked_header_value(reason: &str) -> &'static str {
    match reason {
        REASON_NOT_ALLOWED | REASON_NOT_ALLOWED_LOCAL => "blocked-by-allowlist",
        REASON_DENIED => "blocked-by-denylist",
        REASON_METHOD_NOT_ALLOWED => "blocked-by-method-policy",
        REASON_MITM_REQUIRED => "blocked-by-mitm-required",
        _ => "blocked-by-policy",
    }
}
```

## 关键代码路径与文件引用

### 核心类型定义

| 类型 | 行号 | 描述 |
|------|------|------|
| `PolicyDecisionDetails` | 15-22 | 策略决策详情结构 |

### 核心函数

| 函数 | 行号 | 描述 |
|------|------|------|
| `text_response` | 24-30 | 纯文本响应生成 |
| `json_response` | 32-48 | JSON 响应生成 |
| `blocked_header_value` | 50-58 | 拒绝原因到 HTTP 头值映射 |
| `blocked_message` | 60-75 | 拒绝原因到用户消息映射 |
| `blocked_text_response` | 77-84 | 纯文本拒绝响应 |
| `blocked_message_with_policy` | 85-88 | 带策略详情的消息生成 |
| `blocked_text_response_with_policy` | 90-100 | 带策略详情的拒绝响应 |

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::network_policy` | `NetworkDecisionSource`、`NetworkPolicyDecision`、`NetworkProtocol` |
| `crate::reasons` | 拒绝原因常量 |

### 外部 crate 依赖

| crate | 用途 |
|-------|------|
| `rama_http` | HTTP 响应类型、状态码、Body |
| `serde` | JSON 序列化 |
| `tracing` | 错误日志记录 |

### 调用方

1. **`http_proxy.rs`**：
   - `blocked_text_with_details()`：CONNECT 拒绝响应
   - `json_blocked()`：普通 HTTP 请求拒绝响应
   - `proxy_disabled_response()`：代理禁用响应

2. **`socks5.rs`**：
   - `policy_denied_error()`：SOCKS5 拒绝错误（内部调用 `blocked_message_with_policy`）

### 响应格式示例

**纯文本拒绝响应**：
```http
HTTP/1.1 403 Forbidden
content-type: text/plain
x-proxy-error: blocked-by-allowlist

Codex blocked this request: domain not in allowlist (this is not a denylist block).
```

**JSON 拒绝响应**：
```http
HTTP/1.1 403 Forbidden
content-type: application/json
x-proxy-error: blocked-by-denylist

{
  "status": "blocked",
  "host": "example.com",
  "reason": "denied",
  "decision": "deny",
  "source": "baseline_policy",
  "protocol": "http",
  "port": 80,
  "message": "Codex blocked this request: domain denied by policy."
}
```

## 风险、边界与改进建议

### 潜在风险

1. **JSON 序列化失败**：
   - `json_response()` 在序列化失败时返回空对象 `{}`
   - 可能导致调用方无法正确解析响应
   - 建议：在序列化失败时返回纯文本错误响应

2. **HTTP 头值注入**：
   - `blocked_header_value()` 返回静态字符串，安全
   - 但 `blocked_message_with_policy()` 可能包含用户输入（host）
   - 建议：验证 host 字段不包含换行符等危险字符

3. **错误消息泄露信息**：
   - 错误消息区分 "allowlist" 和 "denylist"
   - 可能泄露配置信息给攻击者
   - 建议：考虑在敏感环境中统一错误消息

### 边界情况

1. **空原因处理**：
   - `blocked_message()` 和 `blocked_header_value()` 都有默认分支
   - 未知原因映射为通用消息和 `blocked-by-policy`

2. **策略详情未使用**：
   - `blocked_message_with_policy()` 当前忽略 `details` 参数
   - 保留用于未来扩展（如包含主机名在消息中）

3. **响应构建失败**：
   - 使用 `unwrap_or_else()` 确保即使构建失败也返回响应
   - 降级为最简单的响应（如 `Response::new(Body::from("blocked"))`）

### 改进建议

1. **国际化支持**：
   - 当前错误消息仅支持英文
   - 建议：添加多语言支持，根据请求头选择语言

2. **结构化错误响应**：
   - 当前 JSON 响应格式简单
   - 建议：添加错误代码、帮助链接、请求 ID 等字段

3. **错误消息模板**：
   - 当前使用静态字符串
   - 建议：支持模板化，动态插入主机名、端口等信息

4. **安全头**：
   - 考虑添加安全相关的 HTTP 头
   - 如 `X-Content-Type-Options: nosniff`

5. **速率限制响应**：
   - 当前没有专门的速率限制响应
   - 建议：添加 `429 Too Many Requests` 响应支持

6. **日志关联**：
   - 在响应中添加请求 ID 头
   - 便于与审计日志关联

### 测试覆盖

该模块有基本的测试覆盖（约 20 行测试代码）：
- `blocked_message_with_policy_returns_human_message`：验证消息生成

建议添加：
- 各种拒绝原因的响应格式测试
- JSON 序列化失败场景测试
- HTTP 头值验证测试
- 响应状态码验证测试

### 代码示例：改进的 JSON 响应

```rust
#[derive(Serialize)]
struct BlockedResponse<'a> {
    status: &'static str,
    host: &'a str,
    reason: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    decision: Option<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    source: Option<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    protocol: Option<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    port: Option<u16>,
    #[serde(skip_serializing_if = "Option::is_none")]
    message: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    request_id: Option<String>, // 新增：请求 ID
}
```
