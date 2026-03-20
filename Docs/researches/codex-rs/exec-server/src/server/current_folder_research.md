# DIR `codex-rs/exec-server/src/server` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/exec-server/src/server`（DIR）
- 研究日期：2026-03-21
- 研究范围：exec-server 的服务器端核心实现，包括 JSON-RPC 协议处理、连接生命周期管理、初始化握手流程、传输层抽象及错误处理机制。

## 场景与职责

`exec-server/src/server` 是 Codex 执行服务器的核心服务器端实现模块，承担以下关键职责：

1. **JSON-RPC 2.0 协议处理**
   - 实现自定义的 JSON-RPC 消息解析与响应生成（`jsonrpc.rs`）
   - 支持 Request/Notification/Response/Error 四种消息类型（`processor.rs:67-81`）
   - 遵循与 `codex_app_server_protocol` 共享的协议定义

2. **连接生命周期管理**
   - 通过 `run_connection` 函数管理单个 WebSocket 连接的完整生命周期（`processor.rs:18-61`）
   - 处理连接事件：消息接收、格式错误、断开连接（`processor.rs:22-58`）
   - 优雅关闭与资源清理（`processor.rs:60`）

3. **初始化握手协议**
   - 实现 LSP 风格的 initialize/initialized 握手流程（`handler.rs:24-39`）
   - 确保每个连接只能初始化一次（`handler.rs:25-29`）
   - 强制要求先收到 `initialize` 请求才能处理 `initialized` 通知（`handler.rs:34-36`）

4. **传输层抽象**
   - 支持 WebSocket 传输（`transport.rs`）
   - 默认监听地址 `ws://127.0.0.1:0`（`transport.rs:10`）
   - 可扩展的 URL 解析机制（`transport.rs:35-47`）

5. **Stub 阶段的占位实现**
   - 当前仅实现 `initialize` 方法，其他方法返回 "not implement yet" 错误（`processor.rs:104-109`）
   - 为后续 process/start、command/exec 等功能预留扩展点

## 功能点目的

### 1. JSON-RPC 错误处理标准化

`jsonrpc.rs` 提供标准 JSON-RPC 2.0 错误码：
- `-32600`: Invalid Request（无效请求）
- `-32601`: Method Not Found（方法未找到）
- `-32602`: Invalid Params（无效参数）

这些错误码与 `codex_app_server_protocol::JSONRPCErrorError` 兼容，确保客户端能正确解析。

### 2. 连接事件驱动架构

`processor.rs` 采用事件驱动模型处理连接：
- `JsonRpcConnectionEvent::Message`: 正常消息处理
- `JsonRpcConnectionEvent::MalformedMessage`: 格式错误消息，返回错误但不中断连接
- `JsonRpcConnectionEvent::Disconnected`: 连接断开，清理资源

### 3. 请求分发机制

`dispatch_request` 函数实现方法路由（`processor.rs:84-111`）：
- 根据 `method` 字段匹配处理函数
- 当前仅支持 `initialize` 方法
- 其他方法返回 `method_not_found` 错误

### 4. 通知处理机制

`handle_notification` 处理无需响应的通知消息（`processor.rs:113-121`）：
- 当前仅支持 `initialized` 通知
- 用于完成初始化握手流程

### 5. WebSocket 传输层

`transport.rs` 实现基于 `tokio-tungstenite` 的 WebSocket 服务器：
- 异步监听指定地址
- 每个连接独立 spawn 任务处理
- 支持并发多连接

## 具体技术实现

### 关键数据结构

#### ExecServerHandler
```rust
pub(crate) struct ExecServerHandler {
    initialize_requested: AtomicBool,
    initialized: AtomicBool,
}
```
- 使用原子布尔值跟踪初始化状态
- 确保线程安全的并发访问（`handler.rs:9-12`）

#### JSON-RPC 消息类型
```rust
pub enum JSONRPCMessage {
    Request(JSONRPCRequest),
    Notification(JSONRPCNotification),
    Response(JSONRPCResponse),
    Error(JSONRPCError),
}
```
- 定义在 `codex_app_server_protocol` crate
- 被 `processor.rs` 和 `connection.rs` 共享使用

#### JsonRpcConnectionEvent
```rust
pub(crate) enum JsonRpcConnectionEvent {
    Message(JSONRPCMessage),
    MalformedMessage { reason: String },
    Disconnected { reason: Option<String> },
}
```
- 连接层向上层传递的事件抽象（`connection.rs:22-26`）

### 关键流程

#### 初始化握手流程
1. 客户端发送 `initialize` Request（带 `InitializeParams`）
2. 服务端检查是否已初始化，若否则标记 `initialize_requested=true`
3. 服务端返回 `InitializeResponse`（当前为空对象）
4. 客户端发送 `initialized` Notification
5. 服务端验证已收到 `initialize`，标记 `initialized=true`
6. 连接进入正常工作状态

#### 消息处理流程
1. `run_connection` 循环接收 `JsonRpcConnectionEvent`
2. 正常消息进入 `handle_connection_message`
3. 根据消息类型分发：
   - `Request` → `dispatch_request` → 方法路由 → 生成 Response
   - `Notification` → `handle_notification` → 无返回
   - `Response`/`Error` → 协议错误（服务端不应收到）
4. 响应通过 `json_outgoing_tx` 发送回客户端

#### 错误处理流程
- 格式错误消息：记录警告，返回 `invalid_request_message`，保持连接
- 协议错误（如收到 Response）：记录警告，中断连接
- 方法未找到：返回标准 JSON-RPC 错误，保持连接

### 协议规范

#### 支持的传输协议
- **WebSocket**: `ws://IP:PORT` 格式（`transport.rs:38-42`）
- **stdio**（测试用）: 通过 `connection.rs` 的 `from_stdio` 方法

#### 当前支持的 JSON-RPC 方法
| 方法 | 类型 | 状态 |
|------|------|------|
| `initialize` | Request | ✅ 已实现 |
| `initialized` | Notification | ✅ 已实现 |
| `process/start` | Request | ❌ Stub 返回错误 |
| `command/exec` | Request | ❌ Stub 返回错误 |
| 其他方法 | - | ❌ 返回 method_not_found |

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 | 关键函数/结构 |
|------|------|---------------|
| `handler.rs` | 业务逻辑处理器 | `ExecServerHandler`, `initialize()`, `initialized()` |
| `processor.rs` | 消息处理与分发 | `run_connection()`, `dispatch_request()`, `handle_notification()` |
| `jsonrpc.rs` | JSON-RPC 工具函数 | `invalid_request()`, `method_not_found()`, `response_message()` |
| `transport.rs` | WebSocket 传输层 | `run_transport()`, `run_websocket_listener()`, `parse_listen_url()` |
| `transport_tests.rs` | URL 解析单元测试 | `parse_listen_url_*` 测试函数 |

### 依赖文件

| 文件 | 依赖关系 |
|------|----------|
| `../connection.rs` | 提供 `JsonRpcConnection`, `JsonRpcConnectionEvent` |
| `../protocol.rs` | 提供 `INITIALIZE_METHOD`, `INITIALIZED_METHOD`, `InitializeParams` |
| `../server.rs` | 模块聚合与公共导出 |
| `../lib.rs` | crate 根，导出 `run_main`, `run_main_with_listen_url` |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `codex_app_server_protocol` | JSON-RPC 消息类型定义（`JSONRPCMessage`, `JSONRPCRequest`, 等） |
| `tokio` | 异步运行时、TCP 监听、spawn 任务 |
| `tokio-tungstenite` | WebSocket 服务器实现 |
| `serde_json` | JSON 序列化/反序列化 |
| `tracing` | 日志记录 |

### 代码调用链

```
codex-exec-server (bin)
    ↓
run_main_with_listen_url (lib)
    ↓
transport::run_transport
    ↓
run_websocket_listener
    ↓ (per connection)
JsonRpcConnection::from_websocket
    ↓
processor::run_connection
    ↓
handle_connection_message
    ↓ (Request)
dispatch_request
    ↓
ExecServerHandler::initialize
```

## 依赖与外部交互

### 上游依赖（调用方）

1. **codex-exec-server 二进制** (`src/bin/codex-exec-server.rs`)
   - CLI 入口，解析 `--listen` 参数
   - 调用 `run_main_with_listen_url`

2. **集成测试** (`tests/`)
   - `initialize.rs`: 测试初始化握手
   - `websocket.rs`: 测试 WebSocket 连接与错误处理
   - `process.rs`: 测试 process/start stub 行为

### 下游依赖（被调用方）

1. **codex_app_server_protocol crate**
   - 共享 JSON-RPC 类型定义
   - 确保与 app-server 协议兼容

2. **connection 模块** (`src/connection.rs`)
   - 提供 WebSocket/stdio 连接抽象
   - 处理底层 I/O 与消息解析

### 横向交互

1. **与 app-server 的关系**
   - exec-server 是独立的执行服务器进程
   - 与 app-server 通过 JSON-RPC 协议通信
   - 共享 `codex_app_server_protocol` 定义的消息格式

2. **与客户端的关系**
   - 支持远程 WebSocket 客户端（如 `ExecServerClient`）
   - 支持进程内本地后端（`LocalBackend`）

## 风险、边界与改进建议

### 已知风险

1. **Stub 实现限制**
   - 当前仅实现初始化握手，业务功能（process/start、command/exec）未实现
   - 客户端调用未实现方法会收到明确的错误响应（`processor.rs:107-108`）

2. **并发安全**
   - `ExecServerHandler` 使用 `AtomicBool` 确保初始化状态线程安全
   - 但当前实现简单，未来扩展需考虑更复杂的状态管理

3. **错误处理边界**
   - 格式错误消息不会中断连接（符合预期）
   - 协议错误（如收到 Response）会中断连接

4. **传输层限制**
   - 仅支持 WebSocket 传输
   - stdio 传输仅在测试中使用

### 边界条件

1. **初始化状态机**
   - 必须严格遵循 `initialize` → `initialized` 顺序
   - 重复调用 `initialize` 返回错误（`-32600`）
   - 先收到 `initialized` 通知返回错误

2. **连接生命周期**
   - 每个连接独立 spawn 任务，无全局连接管理
   - 连接断开时自动清理资源（通过 `Drop`）

3. **消息大小限制**
   - 依赖 `tokio-tungstenite` 的默认配置
   - 无显式消息大小限制

### 改进建议

1. **功能扩展**
   - 实现 `process/start` 方法，支持进程启动
   - 实现 `command/exec` 方法，支持命令执行
   - 添加健康检查/心跳机制

2. **监控与可观测性**
   - 添加连接数指标
   - 添加请求延迟 histogram
   - 添加方法调用计数器

3. **安全增强**
   - 添加连接认证机制
   - 实现速率限制
   - 添加请求大小限制

4. **协议扩展**
   - 考虑支持 Server-Sent Events (SSE) 作为替代传输
   - 添加批量请求支持（JSON-RPC batch）

5. **代码结构优化**
   - 将 `dispatch_request` 中的方法路由提取为宏或 trait 系统
   - 添加中间件机制（认证、日志、metrics）

6. **测试覆盖**
   - 添加并发初始化测试
   - 添加大消息压力测试
   - 添加连接断开边界测试

## 参考文档

- [app-server-protocol JSON-RPC 定义](../../app-server-protocol/src/jsonrpc_lite.rs)
- [app-server 协议文档](../../app-server/README.md)
- [exec-server 集成测试](../../tests/)
- [AGENTS.md 项目规范](../../../../AGENTS.md)
