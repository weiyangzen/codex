# websocket.rs 研究文档

## 场景与职责

`websocket.rs` 是 `codex-exec-server` 的集成测试文件，专注于验证 WebSocket 传输层的健壮性和错误恢复能力。该测试确保服务器在面对异常输入时能够保持稳定运行，而不是崩溃或断开连接。

在 Codex 架构中，exec-server 通过 WebSocket 与客户端通信。由于网络环境复杂，服务器必须能够处理各种异常情况，包括格式错误的消息、无效的 JSON 数据等。该测试验证了服务器的容错能力。

## 功能点目的

### 1. 异常输入处理 (`exec_server_reports_malformed_websocket_json_and_keeps_running`)

该测试的核心目的是验证：
- 服务器能够检测并报告格式错误的 WebSocket 消息
- 收到无效输入后，服务器保持运行状态（不崩溃）
- 服务器能够继续处理后续的有效请求
- 错误响应包含足够的信息用于调试

### 2. 连接稳定性验证

测试验证了以下关键行为：
- 无效输入不会导致连接关闭
- 服务器能够从错误中恢复并继续服务
- 错误响应使用特殊的请求 ID (-1) 标识

## 具体技术实现

### 关键流程

```
测试启动
    ↓
启动 exec-server 子进程
    ↓
建立 WebSocket 连接
    ↓
发送原始非 JSON 文本 "not-json"
    ↓
等待错误响应
    │   - 使用 wait_for_event 匹配 Error 类型
    │   - 验证 id == RequestId::Integer(-1)
    │   - 验证 error.code == -32600 (Invalid Request)
    ↓
发送有效的 initialize 请求
    ↓
等待并验证成功响应
    │   - 确认服务器仍在运行
    │   - 验证正常处理后续请求
    ↓
关闭连接并清理
```

### 错误处理机制

#### 1. 消息解析流程
```rust
// connection.rs:from_websocket 中的 reader_task
match websocket_reader.next().await {
    Some(Ok(Message::Text(text))) => {
        match serde_json::from_str::<JSONRPCMessage>(text.as_ref()) {
            Ok(message) => { /* 正常处理 */ }
            Err(err) => {
                send_malformed_message(
                    &incoming_tx_for_reader,
                    Some(format!(
                        "failed to parse websocket JSON-RPC message from {reader_label}: {err}"
                    )),
                ).await;
            }
        }
    }
    // ...
}
```

#### 2. 错误响应生成
```rust
// jsonrpc.rs:invalid_request_message
pub(crate) fn invalid_request_message(reason: String) -> JSONRPCMessage {
    JSONRPCMessage::Error(JSONRPCError {
        id: RequestId::Integer(-1),  // 特殊 ID 表示无法关联到具体请求
        error: invalid_request(reason),
    })
}

// 错误码定义
pub(crate) fn invalid_request(message: String) -> JSONRPCErrorError {
    JSONRPCErrorError {
        code: -32600,  // JSON-RPC 2.0 Invalid Request
        data: None,
        message,
    }
}
```

#### 3. 处理器中的错误处理
```rust
// processor.rs:run_connection
JsonRpcConnectionEvent::MalformedMessage { reason } => {
    warn!("ignoring malformed exec-server message: {reason}");
    if json_outgoing_tx
        .send(invalid_request_message(reason))
        .await
        .is_err()
    {
        break;
    }
}
```

### JSON-RPC 错误码

| 错误码 | 常量名 | 含义 |
|--------|--------|------|
| -32600 | Invalid Request | 发送的 JSON 不是有效的请求对象 |
| -32601 | Method not found | 请求的方法不存在 |
| -32602 | Invalid params | 无效的参数 |
| -32700 | Parse error | 服务端接收到无效的 JSON |

### 特殊请求 ID

当服务器无法将错误关联到特定请求时（如 JSON 解析失败），使用 `RequestId::Integer(-1)` 作为响应 ID。

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/exec-server/tests/websocket.rs` - 本测试文件
- `codex-rs/exec-server/tests/common/exec_server.rs` - 测试辅助工具

### 核心实现文件

#### 1. 连接层 (`codex-rs/exec-server/src/connection.rs`)
- `from_websocket()` - 创建 WebSocket 连接
- `reader_task` - 读取并解析 WebSocket 消息
- `send_malformed_message()` - 发送格式错误事件

#### 2. 处理层 (`codex-rs/exec-server/src/server/processor.rs`)
- `run_connection()` - 主事件循环
- `JsonRpcConnectionEvent::MalformedMessage` 处理分支

#### 3. JSON-RPC 工具 (`codex-rs/exec-server/src/server/jsonrpc.rs`)
- `invalid_request_message()` - 创建无效请求错误响应
- `invalid_request()` - 创建错误详情

### 消息类型定义
```rust
// app-server-protocol/src/jsonrpc_lite.rs
pub enum JSONRPCMessage {
    Request(JSONRPCRequest),
    Notification(JSONRPCNotification),
    Response(JSONRPCResponse),
    Error(JSONRPCError),  // 错误响应
}

pub struct JSONRPCError {
    pub error: JSONRPCErrorError,
    pub id: RequestId,  // 对应请求的 ID，或 -1
}
```

### 测试辅助方法
```rust
// 发送原始文本（绕过 JSON 序列化）
pub(crate) async fn send_raw_text(&mut self, text: &str) -> anyhow::Result<()> {
    self.websocket
        .send(Message::Text(text.to_string().into()))
        .await?;
    Ok(())
}
```

## 依赖与外部交互

### WebSocket 库
- `tokio-tungstenite` - Tokio 的 WebSocket 实现
- 支持 Text 和 Binary 消息类型
- 自动处理 Ping/Pong 心跳

### 消息处理流程
```
WebSocket Frame
    ↓
Message::Text / Message::Binary
    ↓
serde_json::from_str / from_slice
    ↓
Ok(JSONRPCMessage) → JsonRpcConnectionEvent::Message
Err(err) → JsonRpcConnectionEvent::MalformedMessage
    ↓
processor::run_connection 处理
    ↓
JSONRPCMessage::Error 响应
```

### 条件编译
```rust
#![cfg(unix)]
```

### 断言库
- `pretty_assertions::assert_eq` - 提供清晰的差异输出
- `assert!` - 用于字符串前缀匹配验证

## 风险、边界与改进建议

### 当前风险

1. **DoS 攻击面**: 测试未验证服务器对大量无效消息的处理能力
2. **错误信息泄露**: 当前错误消息包含内部细节，可能泄露敏感信息
3. **资源耗尽**: 未测试持续发送无效消息时的内存使用情况

### 边界情况分析

1. **空消息**: 发送空字符串 `""` 的行为
2. **超大消息**: 超过缓冲区大小的消息处理
3. **二进制垃圾数据**: 非 UTF-8 二进制数据的处理
4. **嵌套错误**: 发送格式正确但语义错误的 JSON-RPC（如缺少必要字段）
5. **快速连续错误**: 短时间内发送多个无效消息

### 建议添加的测试

```rust
// 1. 空消息测试
#[tokio::test]
async fn exec_server_handles_empty_message() { ... }

// 2. 超大消息测试
#[tokio::test]
async fn exec_server_handles_oversized_message() { ... }

// 3. 二进制数据测试
#[tokio::test]
async fn exec_server_handles_binary_garbage() { ... }

// 4. 部分有效 JSON 测试
#[tokio::test]
async fn exec_server_handles_valid_json_invalid_rpc() { 
    // 例如：{"foo": "bar"} - 有效 JSON 但无效 RPC
}

// 5. 并发错误恢复测试
#[tokio::test]
async fn exec_server_recovers_from_rapid_errors() { ... }

// 6. 连接保持测试
#[tokio::test]
async fn exec_server_maintains_connection_after_many_errors() { ... }
```

### 安全改进建议

1. **速率限制**: 对无效消息实施速率限制，防止暴力破解
2. **错误信息脱敏**: 生产环境应减少错误详情暴露
3. **连接限制**: 限制单个连接的无效消息容忍度
4. **日志审计**: 记录异常模式用于安全分析

### 架构改进建议

1. **消息大小限制**: 在 WebSocket 层实现最大消息大小限制
2. **结构化错误**: 定义更详细的错误子类型
3. **指标收集**: 记录错误率指标用于监控
4. **优雅降级**: 考虑在持续错误后主动断开连接

### 相关测试文件
- `initialize.rs` - 正常初始化流程测试
- `process.rs` - 业务方法测试（包括错误响应）

### 相关实现文件
- `codex-rs/exec-server/src/connection.rs` - 连接管理
- `codex-rs/exec-server/src/server/processor.rs` - 请求处理
- `codex-rs/exec-server/src/server/jsonrpc.rs` - JSON-RPC 工具
