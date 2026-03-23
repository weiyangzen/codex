# client.rs 深入研究文档

## 场景与职责

`client.rs` 是 `codex-exec-server` crate 的核心客户端实现模块，负责建立和管理与执行服务器的连接。它提供了两种连接模式：

1. **进程内连接 (In-Process)**：直接在本地内存中创建服务器 handler 实例，无需网络通信
2. **WebSocket 远程连接**：通过 WebSocket 协议连接到远程执行服务器

该模块是 Codex 执行服务器架构的客户端入口点，为上层应用（如 TUI 或 CLI）提供统一的执行服务调用接口。

## 功能点目的

### 1. 双模式连接支持
- **目的**：支持不同部署场景——开发/测试时使用进程内模式减少开销，生产环境使用 WebSocket 模式实现服务解耦
- **设计**：通过 `ClientBackend` 枚举抽象两种后端，对外暴露统一的 `ExecServerClient` 接口

### 2. 连接生命周期管理
- **目的**：确保连接正确建立、初始化和清理
- **关键阶段**：
  - WebSocket 握手（带超时）
  - JSON-RPC 初始化握手 (`initialize` / `initialized`)
  - 连接断开时的资源清理

### 3. 错误处理与转换
- **目的**：将底层错误（WebSocket、JSON-RPC、序列化）转换为统一的 `ExecServerError` 类型
- **包含**：连接超时、协议错误、服务器错误响应等

## 具体技术实现

### 关键数据结构

```rust
// 客户端后端枚举，抽象本地和远程两种实现
enum ClientBackend {
    Remote(RpcClient),      // WebSocket 远程连接
    InProcess(LocalBackend), // 进程内直接调用
}

// 内部状态结构
struct Inner {
    backend: ClientBackend,
    reader_task: tokio::task::JoinHandle<()>, // 事件读取任务
}

// 对外暴露的客户端句柄（线程安全）
pub struct ExecServerClient {
    inner: Arc<Inner>,
}
```

### 连接流程

#### 进程内连接 (`connect_in_process`)
```
1. 创建 ExecServerHandler 实例
2. 包装为 LocalBackend
3. 执行 initialize 握手
4. 返回客户端句柄
```

#### WebSocket 连接 (`connect_websocket`)
```
1. 使用 tokio_tungstenite::connect_async 建立 WebSocket 连接（带 10s 超时）
2. 将 WebSocketStream 包装为 JsonRpcConnection
3. 创建 RpcClient 处理 JSON-RPC 消息
4. 启动 reader_task 处理服务器事件
5. 执行 initialize 握手
```

### 初始化握手协议

```rust
pub async fn initialize(&self, options: ExecServerClientConnectOptions) 
    -> Result<InitializeResponse, ExecServerError> 
{
    // 1. 发送 initialize 请求（带超时）
    // 2. 等待服务器响应
    // 3. 发送 initialized 通知（无响应）
}
```

### Drop 实现与资源清理

```rust
impl Drop for Inner {
    fn drop(&mut self) {
        // 1. 如果是本地后端，异步执行 shutdown
        // 2. 中止 reader_task
    }
}
```

### 错误类型映射

```rust
impl From<RpcCallError> for ExecServerError {
    fn from(value: RpcCallError) -> Self {
        match value {
            RpcCallError::Closed => Self::Closed,
            RpcCallError::Json(err) => Self::Json(err),
            RpcCallError::Server(error) => Self::Server { code, message },
        }
    }
}
```

## 关键代码路径与文件引用

### 内部依赖

| 模块 | 路径 | 用途 |
|------|------|------|
| `client_api` | `client_api.rs` | 连接配置结构定义 |
| `connection` | `connection.rs` | JsonRpcConnection 传输层 |
| `protocol` | `protocol.rs` | 初始化协议常量与类型 |
| `rpc` | `rpc.rs` | RpcClient JSON-RPC 客户端 |
| `local_backend` | `client/local_backend.rs` | 进程内后端实现 |
| `server::ExecServerHandler` | `server/handler.rs` | 服务器 handler |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `tokio_tungstenite` | WebSocket 异步连接 |
| `tokio::time::timeout` | 连接和初始化超时 |
| `serde_json` | JSON 序列化/反序列化 |
| `tracing` | 日志记录 |

### 关键代码路径

1. **连接建立**：`ExecServerClient::connect_websocket` → `connect_async` → `JsonRpcConnection::from_websocket` → `RpcClient::new`
2. **初始化握手**：`initialize` → `backend.initialize()` / `remote.call(INITIALIZE_METHOD, ...)` → `notify_initialized`
3. **事件处理**：`reader_task` 循环接收 `RpcClientEvent`，当前仅记录警告（stub 阶段）

## 依赖与外部交互

### 与 protocol 模块的交互
- 使用 `INITIALIZE_METHOD` 和 `INITIALIZED_METHOD` 常量
- 使用 `InitializeParams` 和 `InitializeResponse` 类型

### 与 rpc 模块的交互
- 通过 `RpcClient::call` 发送请求
- 通过 `RpcClient::notify` 发送通知
- 接收 `RpcClientEvent` 事件流

### 与 connection 模块的交互
- 使用 `JsonRpcConnection::from_websocket` 包装 WebSocket 流

### 与 server 模块的交互
- 进程内模式直接创建 `ExecServerHandler`

## 风险、边界与改进建议

### 当前风险

1. **Stub 阶段的事件处理**：
   ```rust
   RpcClientEvent::Notification(notification) => {
       warn!("ignoring unexpected exec-server notification during stub phase: {}", ...)
   }
   ```
   当前仅记录警告，未实现真正的通知处理逻辑。

2. **LocalBackend 的 Drop 处理**：
   - 使用 `tokio::runtime::Handle::try_current()` 尝试获取运行时
   - 如果不在异步上下文中，shutdown 可能无法执行

3. **硬编码超时**：
   - `CONNECT_TIMEOUT = 10s`
   - `INITIALIZE_TIMEOUT = 10s`
   - 无法根据网络环境动态调整

### 边界情况

1. **重复初始化**：`ExecServerHandler::initialize` 使用 `AtomicBool` 防止重复初始化
2. **连接断开**：通过 `Disconnected` 事件通知上层，清理 pending 请求
3. **序列化失败**：在 `call` 方法中，如果参数序列化失败，会从 pending 中移除请求 ID

### 改进建议

1. **实现通知处理**：当前 stub 阶段应实现真正的通知处理机制
2. **可配置超时**：将超时参数暴露给调用方，支持不同网络环境
3. **重连机制**：当前连接断开后需要重新创建客户端，可考虑内置重连逻辑
4. **连接池**：高并发场景下可考虑连接池优化
5. **健康检查**：定期发送 ping/heartbeat 检测连接状态
6. **指标监控**：添加连接建立时间、请求延迟等指标

### 测试覆盖

- 单元测试位于 `rpc.rs` 中，测试乱序响应匹配
- 集成测试位于 `tests/` 目录：
  - `initialize.rs`：测试初始化流程
  - `websocket.rs`：测试 WebSocket 连接和错误处理
  - `process.rs`：测试 process/start stub 响应
