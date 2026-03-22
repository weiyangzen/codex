# JSONRPCError.json 研究文档

## 场景与职责

`JSONRPCError` 是 Codex App-Server 协议中用于**表示 JSON-RPC 错误响应**的结构。当服务器处理请求发生错误时，通过此结构返回错误信息。

该类型是 JSON-RPC 2.0 协议标准错误响应的 Codex 实现，属于 **Server → Client** 的响应流。

### 使用场景

1. **请求处理错误**：服务器无法处理客户端的请求
2. **方法不存在**：请求的 JSON-RPC 方法未实现
3. **参数无效**：请求参数格式错误或缺失
4. **内部服务器错误**：服务器内部发生未预期错误

---

## 功能点目的

### 核心字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `error` | JSONRPCErrorError | ✅ | 错误详情对象 |
| `id` | RequestId | ✅ | 对应请求的标识 |

### 错误详情（JSONRPCErrorError）

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer | ✅ | 错误代码 |
| `message` | string | ✅ | 错误描述 |
| `data` | any | ❌ | 附加错误数据 |

### 标准 JSON-RPC 错误代码

| 代码 | 含义 | 说明 |
|------|------|------|
| `-32700` | Parse error | 无效的 JSON |
| `-32600` | Invalid Request | 无效的 JSON-RPC 请求 |
| `-32601` | Method not found | 方法不存在 |
| `-32602` | Invalid params | 无效参数 |
| `-32603` | Internal error | 内部错误 |
| `-32000` to `-32099` | Server error | 保留给服务器实现定义的错误 |

---

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/jsonrpc_lite.rs
/// A response to a request that indicates an error occurred.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize, JsonSchema, TS)]
pub struct JSONRPCError {
    pub error: JSONRPCErrorError,
    pub id: RequestId,
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize, JsonSchema, TS)]
pub struct JSONRPCErrorError {
    pub code: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub data: Option<serde_json::Value>,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq, PartialOrd, Ord, Deserialize, Serialize, Hash, Eq, JsonSchema, TS)]
#[serde(untagged)]
pub enum RequestId {
    String(String),
    #[ts(type = "number")]
    Integer(i64),
}
```

### JSON-RPC 消息枚举

```rust
pub enum JSONRPCMessage {
    Request(JSONRPCRequest),
    Notification(JSONRPCNotification),
    Response(JSONRPCResponse),
    Error(JSONRPCError),
}
```

---

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/jsonrpc_lite.rs` | 主类型定义（行 74-79） |
| `codex-rs/app-server-protocol/src/jsonrpc_lite.rs` | JSONRPCErrorError 定义（行 81-88） |
| `codex-rs/app-server-protocol/src/jsonrpc_lite.rs` | JSONRPCMessage 定义（行 35-42） |

### Schema 生成

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/export.rs` | JSON Schema 生成（行 203） |

---

## 依赖与外部交互

### 依赖类型

```rust
use serde_json::Value as JsonValue;
```

### 序列化特性

- 使用标准 JSON-RPC 2.0 格式（但不包含 `"jsonrpc": "2.0"` 字段）
- `data` 字段可选，使用 `skip_serializing_if = "Option::is_none"`

### 与标准 JSON-RPC 2.0 的差异

Codex 实现与标准 JSON-RPC 2.0 的主要差异：
- **不包含 `jsonrpc` 版本字段**：简化消息格式
- **灵活的 RequestId**：支持字符串和整数 ID

---

## 风险、边界与改进建议

### 已知风险

1. **缺少版本字段**：不包含 `"jsonrpc": "2.0"` 可能导致与标准 JSON-RPC 客户端的兼容性问题

2. **错误代码范围**：使用 `-32000` 到 `-32099` 范围内的服务器错误代码时，需要确保不与其他组件冲突

### 边界情况

1. **通知错误**：JSON-RPC 通知（无 `id`）不应返回错误响应，但实际实现可能因错误而发送
2. **批量请求**：Codex 协议是否支持 JSON-RPC 批量请求未明确

### 改进建议

1. **添加版本字段**：考虑添加可选的 `jsonrpc` 字段以提高兼容性：
   ```rust
   pub struct JSONRPCError {
       #[serde(rename = "jsonrpc", skip_serializing_if = "Option::is_none")]
       pub jsonrpc_version: Option<String>,
       pub error: JSONRPCErrorError,
       pub id: RequestId,
   }
   ```

2. **标准化错误代码**：定义 Codex 特定的错误代码枚举：
   ```rust
   pub enum CodexErrorCode {
       ThreadNotFound = -32100,
       TurnNotFound = -32101,
       InvalidApprovalDecision = -32102,
       // ...
   }
   ```

3. **错误数据结构化**：为常见错误定义结构化的 `data` 格式：
   ```rust
   pub struct ValidationErrorData {
       pub field: String,
       pub error: String,
   }
   ```

4. **错误日志关联**：在 `data` 中添加错误日志 ID，便于服务端排查：
   ```rust
   pub struct JSONRPCErrorError {
       pub code: i64,
       pub message: String,
       pub data: Option<ErrorData>,
   }
   
   pub struct ErrorData {
       pub log_id: String,  // 用于服务端日志关联
       pub details: Option<JsonValue>,
   }
   ```
