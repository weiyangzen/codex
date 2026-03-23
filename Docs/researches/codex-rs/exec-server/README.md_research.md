# codex-rs/exec-server/README.md 研究文档

## 场景与职责

该文档是 `codex-exec-server` crate 的主要说明文档，描述了这是一个独立的 JSON-RPC 服务器，用于通过 `codex-utils-pty` 生成和控制子进程。文档明确指出这是一个**过渡性/存根实现**（stub implementation），exec 和 filesystem 方法在服务器端仅为存根，将在后续 PR 中实现。

## 功能点目的

### 核心定位

1. **独立二进制**：提供 `codex-exec-server` 可执行文件
2. **Rust 客户端**：提供 `ExecServerClient` 库
3. **共享协议**：定义请求/响应类型的小型协议模块
4. **传输层隔离**：故意窄范围，不接入主 Codex CLI 或 unified-exec

### 生命周期管理

定义了严格的连接生命周期：
1. 客户端发送 `initialize` 请求
2. 等待 `initialize` 响应
3. 发送 `initialized` 通知
4. 后续可调用 exec 或 filesystem RPC（待实现）

### 连接清理

- 收到非 `initialized` 的通知 → 返回错误（request id `-1`）
- WebSocket 连接关闭 → 终止该客户端的所有托管进程

## 具体技术实现

### 传输层

#### 支持的传输协议
- **WebSocket**（默认）：`ws://IP:PORT`

#### 消息帧格式
- WebSocket：每个 WebSocket 文本帧包含一个 JSON-RPC 消息

### API 详细规范

#### 1. `initialize` - 初始握手

**请求参数：**
```json
{
  "clientName": "my-client"
}
```

**响应：**
```json
{}
```

**实现代码路径**：
- 协议定义：`src/protocol.rs` - `InitializeParams`, `InitializeResponse`
- 服务器处理：`src/server/handler.rs` - `ExecServerHandler::initialize()`
- 处理器分发：`src/server/processor.rs` - `dispatch_request()`

**状态管理**：
```rust
// src/server/handler.rs
pub(crate) struct ExecServerHandler {
    initialize_requested: AtomicBool,
    initialized: AtomicBool,
}
```

使用原子布尔值确保：
- `initialize` 只能调用一次（否则返回 `-32600` 错误）
- `initialized` 通知必须在 `initialize` 之后（否则返回协议错误）

#### 2. `initialized` - 握手确认

**行为**：
- 参数当前被忽略
- 设置 `initialized = true`
- 发送其他通知方法被视为无效请求

#### 3. `command/exec` - 启动托管进程

**请求参数结构**：
```json
{
  "processId": "proc-1",           // 调用方指定的进程 ID
  "argv": ["bash", "-lc", "cmd"],  // 命令向量，必须非空
  "cwd": "/absolute/path",          // 绝对工作目录
  "env": {"PATH": "/usr/bin"},     // 环境变量
  "tty": true,                      // true=PTY, false=管道
  "outputBytesCap": 16384,          // 输出缓冲区大小上限
  "arg0": null                      // 可选的 argv0 覆盖
}
```

**响应结构**：
```json
{
  "processId": "proc-1",
  "running": true,
  "exitCode": null,
  "stdout": null,
  "stderr": null
}
```

**当前实现状态**：
- 文档中描述完整 API
- 实际代码仅返回存根错误（`-32601` method not found）
- 代码位置：`src/server/processor.rs` 第 104-109 行

```rust
other => response_message(
    id,
    Err(method_not_found(format!(
        "exec-server stub does not implement `{other}` yet"
    ))),
),
```

#### 4. `command/exec/write` - 写入 PTY 进程

**请求参数**：
```json
{
  "processId": "proc-1",
  "chunk": "aGVsbG8K"  // base64 编码的字节
}
```

**行为约束**：
- 仅支持 PTY 支持的进程（`tty: true`）
- 管道进程（`tty: false`）会拒绝写入（stdin 已关闭）

#### 5. `command/exec/terminate` - 终止进程

**响应语义**：
- `{"running": true}` - 进程正在终止
- `{"running": false}` - 进程已不存在

### 通知（Notifications）

#### `command/exec/outputDelta`

服务器向客户端发送的流式输出通知：
```json
{
  "processId": "proc-1",
  "stream": "stdout",  // 或 "stderr"
  "chunk": "aGVsbG8K"  // base64 编码的输出字节
}
```

#### `command/exec/exited`

进程退出最终通知：
```json
{
  "processId": "proc-1",
  "exitCode": 0
}
```

### 错误代码

| 代码 | 含义 | 典型场景 |
|------|------|----------|
| `-32600` | Invalid Request | 未知方法、格式错误、重复 initialize |
| `-32602` | Invalid Params | 参数解析失败、空 argv、重复 processId |
| `-32603` | Internal Error | 服务器内部错误 |

### Rust 公开 API

```rust
// 客户端
pub use client::ExecServerClient;
pub use client::ExecServerError;
pub use client_api::ExecServerClientConnectOptions;
pub use client_api::RemoteExecServerConnectArgs;

// 协议类型
pub use protocol::InitializeParams;
pub use protocol::InitializeResponse;

// 服务器配置
pub use server::DEFAULT_LISTEN_URL;  // "ws://127.0.0.1:0"
pub use server::ExecServerListenUrlParseError;

// 服务器运行函数
pub use server::run_main;
pub use server::run_main_with_listen_url;
```

## 关键代码路径与文件引用

### 客户端实现

| 文件 | 职责 | 关键类型/函数 |
|------|------|--------------|
| `src/client.rs` | 主客户端实现 | `ExecServerClient`, `ExecServerError` |
| `src/client_api.rs` | 连接选项 API | `ExecServerClientConnectOptions`, `RemoteExecServerConnectArgs` |
| `src/client/local_backend.rs` | 进程内后端 | `LocalBackend` |
| `src/rpc.rs` | RPC 客户端 | `RpcClient`, `RpcCallError` |
| `src/connection.rs` | 传输连接抽象 | `JsonRpcConnection` |

### 服务器实现

| 文件 | 职责 | 关键类型/函数 |
|------|------|--------------|
| `src/server.rs` | 服务器模块入口 | `run_main()`, `run_main_with_listen_url()` |
| `src/server/transport.rs` | WebSocket 传输 | `DEFAULT_LISTEN_URL`, `run_transport()` |
| `src/server/processor.rs` | 连接处理 | `run_connection()`, `handle_connection_message()` |
| `src/server/handler.rs` | 请求处理器 | `ExecServerHandler::initialize()`, `initialized()` |
| `src/server/jsonrpc.rs` | JSON-RPC 工具 | `invalid_request()`, `response_message()` |

### 协议定义

| 文件 | 职责 | 关键类型 |
|------|------|----------|
| `src/protocol.rs` | exec-server 专用协议 | `InitializeParams`, `InitializeResponse`, `INITIALIZE_METHOD`, `INITIALIZED_METHOD` |
| `codex-app-server-protocol` | 共享 JSON-RPC 协议 | `JSONRPCMessage`, `JSONRPCRequest`, `JSONRPCResponse`, `JSONRPCNotification`, `JSONRPCError`, `RequestId` |

### 示例会话流程

```
客户端                                          服务器
  |                                               |
  |-- {"id":1,"method":"initialize",...} -------->|
  |                                               |
  |<-- {"id":1,"result":{}} ---------------------|
  |                                               |
  |-- {"method":"initialized","params":{}} ------>|
  |                                               |
  |-- {"id":2,"method":"command/exec",...} ----->|
  |                                               |
  |<-- {"id":2,"error":{"code":-32601,...}} -----|  (当前存根实现)
```

## 依赖与外部交互

### 协议依赖

```
codex-exec-server
├── codex-app-server-protocol (共享协议)
│   ├── JSONRPCMessage (消息信封)
│   ├── JSONRPCRequest/Response (请求响应)
│   └── RequestId (请求 ID 类型)
└── codex-utils-pty (计划中，当前未接入)
    └── PTY 进程管理
```

### 传输层依赖

```
WebSocket 连接
├── tokio::net::TcpListener (TCP 监听)
├── tokio_tungstenite::accept_async (WebSocket 握手)
└── JsonRpcConnection::from_websocket (连接包装)
```

### 客户端连接模式

1. **WebSocket 远程连接**：
   ```rust
   ExecServerClient::connect_websocket(RemoteExecServerConnectArgs {
       websocket_url: "ws://127.0.0.1:8080".to_string(),
       client_name: "my-client".to_string(),
       connect_timeout: Duration::from_secs(10),
       initialize_timeout: Duration::from_secs(10),
   }).await
   ```

2. **进程内连接**（测试/嵌入）：
   ```rust
   ExecServerClient::connect_in_process(ExecServerClientConnectOptions {
       client_name: "codex-core".to_string(),
       initialize_timeout: Duration::from_secs(10),
   }).await
   ```

## 风险、边界与改进建议

### 风险

1. **API 与实现不同步**：
   - README 描述了完整的 `command/exec` API
   - 实际代码仅为存根实现
   - 风险：用户/开发者基于文档期望完整功能

2. **协议版本演进**：
   - `codex-app-server-protocol` 可能引入破坏性变更
   - exec-server 需要同步更新

3. **并发安全性**：
   - `ExecServerHandler` 使用 `AtomicBool` 进行状态管理
   - 但后续完整实现中进程表需要更复杂的并发控制

### 边界

1. **平台限制**：
   - 集成测试标记为 `#![cfg(unix)]`
   - Windows 支持可能需要额外工作

2. **传输限制**：
   - 当前仅支持 WebSocket
   - 文档暗示可能有 stdio 传输，但未实现

3. **功能边界**：
   - 不处理文件系统操作（文档提到但标记为待实现）
   - 不处理命令执行的实际实现（仅存根）

### 改进建议

1. **文档同步**：
   - 在 API 描述中添加 "⚠️ 存根实现" 警告
   - 明确标记已实现 vs 计划中的功能

2. **版本标记**：
   ```markdown
   ## API 状态
   - ✅ `initialize` / `initialized` - 已实现
   - ⚠️ `command/exec` - 存根，返回 `-32601`
   - ⚠️ `command/exec/write` - 未实现
   - ⚠️ `command/exec/terminate` - 未实现
   ```

3. **错误信息改进**：
   当前存根错误信息：
   ```rust
   "exec-server stub does not implement `{other}` yet"
   ```
   建议添加指向文档或 issue 的链接。

4. **协议一致性检查**：
   考虑添加测试验证 README 中的示例 JSON 与代码中的 serde 定义一致。

5. **配置扩展**：
   `InitializeParams` 当前仅包含 `client_name`，可考虑添加：
   - 协议版本协商
   - 功能协商（capabilities）
   - 超时配置

6. **安全考虑**：
   文档未提及安全模型，建议添加：
   - 认证机制说明
   - 授权范围（哪些命令可以执行）
   - 沙箱边界说明
