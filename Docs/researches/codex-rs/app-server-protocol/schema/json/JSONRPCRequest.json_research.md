# JSONRPCRequest.json 研究文档

## 场景与职责

`JSONRPCRequest` 是 Codex App-Server 协议中用于**表示 JSON-RPC 请求**的结构。请求是一种需要响应的消息，用于客户端和服务器之间的双向调用。

该类型是 JSON-RPC 2.0 协议请求消息的 Codex 实现，属于双向通信流（Client ↔ Server）。

### 使用场景

1. **客户端 → 服务器请求**：如 `thread/start`, `turn/start` 等操作
2. **服务器 → 客户端请求**：如 `item/commandExecution/requestApproval` 等审批请求
3. **同步调用**：需要等待响应的同步操作

---

## 功能点目的

### 核心字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | RequestId | ✅ | 请求标识（字符串或整数） |
| `method` | string | ✅ | 请求方法名 |
| `params` | any | ❌ | 请求参数 |
| `trace` | W3cTraceContext \| null | ❌ | W3C 追踪上下文 |

### RequestId 类型

```json
{
  "RequestId": {
    "anyOf": [
      { "type": "string" },
      { "format": "int64", "type": "integer" }
    ]
  }
}
```

### W3cTraceContext 类型

```json
{
  "W3cTraceContext": {
    "properties": {
      "traceparent": { "type": ["string", "null"] },
      "tracestate": { "type": ["string", "null"] }
    },
    "type": "object"
  }
}
```

---

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/jsonrpc_lite.rs
/// A request that expects a response.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize, JsonSchema, TS)]
pub struct JSONRPCRequest {
    pub id: RequestId,
    pub method: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub params: Option<serde_json::Value>,
    /// Optional W3C Trace Context for distributed tracing.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub trace: Option<W3cTraceContext>,
}

#[derive(Debug, Clone, PartialEq, PartialOrd, Ord, Deserialize, Serialize, Hash, Eq, JsonSchema, TS)]
#[serde(untagged)]
pub enum RequestId {
    String(String),
    #[ts(type = "number")]
    Integer(i64),
}
```

### 序列化示例

```json
{
  "id": 42,
  "method": "thread/start",
  "params": {
    "prompt": "Hello, world!"
  },
  "trace": {
    "traceparent": "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01",
    "tracestate": "vendor=value"
  }
}
```

---

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/jsonrpc_lite.rs` | 主类型定义（行 44-56） |
| `codex-rs/app-server-protocol/src/jsonrpc_lite.rs` | RequestId 定义（行 13-21） |

### 使用位置

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/jsonrpc_lite.rs` | JSONRPCMessage 枚举中使用 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ClientRequest/ServerRequest 转换 |

---

## 依赖与外部交互

### 依赖类型

```rust
use serde_json::Value as JsonValue;
use codex_protocol::protocol::W3cTraceContext;
```

### 序列化特性

- `id` 支持字符串和整数两种格式
- `params` 和 `trace` 可选
- 支持 W3C Trace Context 分布式追踪

---

## 风险、边界与改进建议

### 已知风险

1. **ID 冲突**：字符串和整数 ID 可能冲突（如 `"42"` 和 `42`）

2. **追踪上下文开销**：每个请求都包含追踪上下文可能增加传输开销

### 边界情况

1. **空 ID**：`id` 不能为空
2. **大整数 ID**：超过 JavaScript 安全整数范围的 ID 可能丢失精度

### 改进建议

1. **ID 规范化**：考虑统一使用字符串 ID，避免类型冲突

2. **方法名规范**：定义方法名命名规范（如 `resource/action` 格式）

3. **请求超时**：在协议层添加请求超时机制

4. **请求去重**：添加幂等性支持，避免重复处理
