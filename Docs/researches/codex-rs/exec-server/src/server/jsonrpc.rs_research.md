# JSON-RPC 工具模块研究文档

## 场景与职责

`jsonrpc.rs` 是 codex-exec-server 的 JSON-RPC 协议工具模块，提供标准化的错误构造和响应封装函数。该模块遵循 JSON-RPC 2.0 规范，为 exec-server 的请求处理流程提供统一的错误码和响应格式。

该模块位于 `codex-rs/exec-server/src/server/jsonrpc.rs`，是一个纯工具模块，不包含状态管理，仅提供静态辅助函数。

## 功能点目的

### 1. 标准化错误构造
- **目的**: 提供符合 JSON-RPC 2.0 规范的错误构造器
- **实现**: 定义了三种标准错误类型：
  - `invalid_request` (-32600): 无效请求
  - `invalid_params` (-32602): 无效参数
  - `method_not_found` (-32601): 方法未找到

### 2. 响应消息封装
- **目的**: 统一处理成功响应和错误响应的构造
- **实现**: `response_message` 函数根据 `Result` 类型自动构造正确的 JSON-RPC 消息

### 3. 无效请求消息快捷构造
- **目的**: 当无法解析请求 ID 时，提供默认的错误响应
- **实现**: `invalid_request_message` 使用 `-1` 作为默认请求 ID

## 具体技术实现

### 错误码定义（JSON-RPC 2.0 标准）

| 错误码 | 常量 | 含义 |
|--------|------|------|
| -32600 | `INVALID_REQUEST` | 发送的 JSON 不是有效的请求对象 |
| -32601 | `METHOD_NOT_FOUND` | 方法不存在或不可用 |
| -32602 | `INVALID_PARAMS` | 无效的方法参数 |
| -32603 | `INTERNAL_ERROR` | 内部 JSON-RPC 错误（本模块未使用） |
| -32000 ~ -32099 | `SERVER_ERROR` | 保留给服务器实现特定错误 |

### 数据结构

```rust
// 来自 codex_app_server_protocol
pub struct JSONRPCErrorError {
    pub code: i64,       // 错误码
    pub data: Option<Value>,  // 附加数据
    pub message: String, // 错误描述
}

pub struct JSONRPCResponse {
    pub id: RequestId,   // 请求 ID（与请求对应）
    pub result: Value,   // 结果数据
}

pub enum JSONRPCMessage {
    Request(JSONRPCRequest),
    Response(JSONRPCResponse),
    Notification(JSONRPCNotification),
    Error(JSONRPCError),
}
```

### 关键函数实现

#### 1. 无效请求错误
```rust
pub(crate) fn invalid_request(message: String) -> JSONRPCErrorError {
    JSONRPCErrorError {
        code: -32600,
        data: None,
        message,
    }
}
```
- 用途：协议级别错误，如重复初始化
- 调用方：`handler.rs` 中的 `initialize` 方法

#### 2. 无效参数错误
```rust
pub(crate) fn invalid_params(message: String) -> JSONRPCErrorError {
    JSONRPCErrorError {
        code: -32602,
        data: None,
        message,
    }
}
```
- 用途：参数解析失败或验证失败
- 调用方：`processor.rs` 中的 `dispatch_request`

#### 3. 方法未找到错误
```rust
pub(crate) fn method_not_found(message: String) -> JSONRPCErrorError {
    JSONRPCErrorError {
        code: -32601,
        data: None,
        message,
    }
}
```
- 用途：请求的方法未实现
- 调用方：`processor.rs` 中的 `dispatch_request`（默认分支）

#### 4. 响应消息构造
```rust
pub(crate) fn response_message(
    request_id: RequestId,
    result: Result<Value, JSONRPCErrorError>,
) -> JSONRPCMessage {
    match result {
        Ok(result) => JSONRPCMessage::Response(JSONRPCResponse {
            id: request_id,
            result,
        }),
        Err(error) => JSONRPCMessage::Error(JSONRPCError {
            id: request_id,
            error,
        }),
    }
}
```
- 核心功能：统一封装成功/失败响应
- 设计：使用 `Result` 类型作为输入，符合 Rust 惯用法

#### 5. 无效请求消息（无 ID 场景）
```rust
pub(crate) fn invalid_request_message(reason: String) -> JSONRPCMessage {
    JSONRPCMessage::Error(JSONRPCError {
        id: RequestId::Integer(-1),
        error: invalid_request(reason),
    })
}
```
- 特殊场景：当无法解析请求时，使用 `-1` 作为默认 ID
- 调用方：`processor.rs` 中的 `run_connection`（处理 MalformedMessage）

## 依赖与外部交互

### 外部依赖

| 依赖项 | 来源 | 用途 |
|--------|------|------|
| `JSONRPCError` | `codex_app_server_protocol` | 错误消息包装类型 |
| `JSONRPCErrorError` | `codex_app_server_protocol` | 错误详情类型 |
| `JSONRPCMessage` | `codex_app_server_protocol` | 消息枚举类型 |
| `JSONRPCResponse` | `codex_app_server_protocol` | 响应类型 |
| `RequestId` | `codex_app_server_protocol` | 请求 ID 类型 |
| `Value` | `serde_json` | JSON 值类型 |

### 内部调用方

| 调用方 | 文件 | 调用函数 |
|--------|------|----------|
| `ExecServerHandler::initialize` | `handler.rs:24` | `invalid_request` |
| `dispatch_request` | `processor.rs:84` | `invalid_params`, `method_not_found`, `response_message` |
| `run_connection` | `processor.rs:43` | `invalid_request_message` |

## 风险、边界与改进建议

### 当前风险

1. **错误信息无结构化数据**
   - 现状：所有错误的 `data` 字段均为 `None`
   - 风险：客户端无法获取机器可读的错误详情
   - 建议：对于复杂错误，考虑填充 `data` 字段

2. **默认请求 ID 硬编码**
   - 现状：`invalid_request_message` 使用 `-1` 作为默认 ID
   - 风险：如果客户端恰好发送了 ID 为 `-1` 的请求，会造成混淆
   - 建议：使用 `null` 或更特殊的值，或添加文档说明

3. **缺少内部错误类型**
   - 现状：未提供 `internal_error` 构造器
   - 风险：服务器内部错误时无法返回标准错误码
   - 建议：添加 `internal_error` 函数

### 边界情况

1. **空消息字符串**
   - 函数接受任意字符串，包括空字符串
   - 建议：添加 `debug_assert!` 确保非空

2. **非常大的错误消息**
   - 无长度限制，可能导致大响应
   - 建议：考虑截断或限制长度

### 改进建议

1. **添加内部错误构造器**
```rust
pub(crate) fn internal_error(message: String) -> JSONRPCErrorError {
    JSONRPCErrorError {
        code: -32603,
        data: None,
        message,
    }
}
```

2. **支持结构化错误数据**
```rust
pub(crate) fn invalid_params_with_data(
    message: String,
    data: Value,
) -> JSONRPCErrorError {
    JSONRPCErrorError {
        code: -32602,
        data: Some(data),
        message,
    }
}
```

3. **使用常量定义错误码**
```rust
const INVALID_REQUEST_CODE: i64 = -32600;
const METHOD_NOT_FOUND_CODE: i64 = -32601;
const INVALID_PARAMS_CODE: i64 = -32602;
```

4. **添加错误日志辅助**
```rust
pub(crate) fn invalid_request_logged(message: String) -> JSONRPCErrorError {
    tracing::warn!("JSON-RPC invalid request: {}", message);
    invalid_request(message)
}
```

### 相关文件引用

- 本文件：`codex-rs/exec-server/src/server/jsonrpc.rs`
- 协议定义：`codex-rs/exec-server/src/protocol.rs`
- 请求处理：`codex-rs/exec-server/src/server/processor.rs`
- 状态管理：`codex-rs/exec-server/src/server/handler.rs`
- 协议库：通过 `codex-app-server-protocol` crate 引入
