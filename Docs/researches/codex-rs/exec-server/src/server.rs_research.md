# server.rs 深入研究文档

## 场景与职责

`server.rs` 是 `codex-exec-server` crate 的服务器端入口模块，负责组织和导出服务器相关功能。作为服务器子系统的根模块，它协调传输层、协议处理和请求处理等组件，提供简洁的服务器启动接口。

## 功能点目的

### 1. 模块组织
- **目的**：将服务器功能划分为逻辑子模块
- **子模块**：handler（请求处理）、jsonrpc（工具函数）、processor（连接处理）、transport（网络传输）

### 2. 简化启动接口
- **目的**：为二进制入口提供简洁的服务器启动函数
- **设计**：`run_main()` 和 `run_main_with_listen_url(listen_url)`

### 3. 公共类型导出
- **目的**：暴露服务器配置和错误类型给使用者
- **导出**：`DEFAULT_LISTEN_URL`, `ExecServerListenUrlParseError`

## 具体技术实现

### 模块声明

```rust
mod handler;      // 请求处理器实现
mod jsonrpc;      // JSON-RPC 工具函数
mod processor;    // 连接处理循环
mod transport;    // WebSocket 传输层
```

### 内部类型导出

```rust
pub(crate) use handler::ExecServerHandler;  // 仅 crate 内部使用
```

### 公共类型导出

```rust
pub use transport::DEFAULT_LISTEN_URL;               // 默认监听地址
pub use transport::ExecServerListenUrlParseError;    // URL 解析错误
```

### 服务器启动函数

```rust
/// 使用默认监听地址启动服务器
pub async fn run_main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    run_main_with_listen_url(DEFAULT_LISTEN_URL).await
}

/// 使用指定监听地址启动服务器
pub async fn run_main_with_listen_url(
    listen_url: &str,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    transport::run_transport(listen_url).await
}
```

### 默认监听地址

```rust
// transport.rs 中定义
pub const DEFAULT_LISTEN_URL: &str = "ws://127.0.0.1:0";
```

- `127.0.0.1`：仅本地访问，安全默认
- `:0`：让操作系统分配可用端口

## 关键代码路径与文件引用

### 子模块文件映射

| 模块声明 | 文件路径 | 职责 |
|----------|----------|------|
| `mod handler;` | `server/handler.rs` | 处理 `initialize` 和 `initialized` 请求 |
| `mod jsonrpc;` | `server/jsonrpc.rs` | JSON-RPC 错误构造和响应包装 |
| `mod processor;` | `server/processor.rs` | 单连接消息处理循环 |
| `mod transport;` | `server/transport.rs` | TCP 监听和 WebSocket 握手 |

### 子模块测试

```rust
#[cfg(test)]
#[path = "transport_tests.rs"]
mod transport_tests;  // transport.rs 的单元测试
```

### 使用位置

| 文件 | 使用方式 |
|------|----------|
| `bin/codex-exec-server.rs` | 调用 `run_main_with_listen_url` |
| `client.rs` | 使用 `ExecServerHandler`（进程内模式） |
| `client/local_backend.rs` | 使用 `ExecServerHandler` |

### 启动流程

```
run_main_with_listen_url(listen_url)
└── transport::run_transport(listen_url)
    ├── parse_listen_url(listen_url) -> SocketAddr
    ├── TcpListener::bind(bind_address)
    └── loop { accept connection }
        └── run_connection(JsonRpcConnection)
            └── processor::run_connection
                └── handle_connection_message
                    └── handler::ExecServerHandler
```

## 依赖与外部交互

### 内部模块依赖

```
server.rs
├── handler (被 processor 使用)
├── jsonrpc (被 processor 使用)
├── processor (被 transport 使用)
└── transport (入口)
```

### 与 client 的交互

```rust
// client.rs 中进程内模式
let backend = LocalBackend::new(crate::server::ExecServerHandler::new());
```

`ExecServerHandler` 被客户端在进程内模式下复用，避免代码重复。

### 与二进制入口的交互

```rust
// bin/codex-exec-server.rs
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let args = ExecServerArgs::parse();
    codex_exec_server::run_main_with_listen_url(&args.listen).await
}
```

## 风险、边界与改进建议

### 当前设计特点

1. **简洁接口**：仅需一个 URL 参数即可启动服务器
2. **分层架构**：传输层、处理层、业务层清晰分离
3. **本地优先**：默认仅监听本地接口，安全默认

### 潜在风险

1. **错误类型擦除**：
   ```rust
   pub async fn run_main_with_listen_url(
       listen_url: &str,
   ) -> Result<(), Box<dyn std::error::Error + Send + Sync>>
   ```
   使用 `Box<dyn Error>` 擦除具体错误类型，调用者难以针对性处理。

2. **无优雅关闭**：
   - 没有 `shutdown()` 函数
   - 接收到 SIGTERM 时无法优雅关闭连接

3. **配置局限**：
   - 仅支持 URL 参数
   - 无日志级别、并发限制、超时等配置

4. **单点故障**：
   - 无健康检查端点
   - 无指标暴露

### 改进建议

1. **具体错误类型**：
   ```rust
   #[derive(Debug, thiserror::Error)]
   pub enum ServerError {
       #[error("invalid listen URL: {0}")]
       InvalidUrl(#[from] ExecServerListenUrlParseError),
       #[error("bind failed: {0}")]
       Bind(#[source] std::io::Error),
       #[error("accept failed: {0}")]
       Accept(#[source] std::io::Error),
   }
   ```

2. **服务器句柄**：
   ```rust
   pub struct ServerHandle {
       local_addr: SocketAddr,
       shutdown_tx: oneshot::Sender<()>,
   }
   
   impl ServerHandle {
       pub fn local_addr(&self) -> SocketAddr;
       pub async fn shutdown(self);
   }
   
   pub async fn run_with_handle(listen_url: &str) -> Result<ServerHandle, ServerError>;
   ```

3. **配置结构**：
   ```rust
   pub struct ServerConfig {
       pub listen_url: String,
       pub max_connections: usize,
       pub request_timeout: Duration,
       pub log_level: tracing::Level,
   }
   
   pub async fn run_with_config(config: ServerConfig) -> Result<(), ServerError>;
   ```

4. **信号处理**：
   ```rust
   use tokio::signal;
   
   pub async fn run_main() -> Result<(), Box<dyn Error>> {
       let server = run_transport(...);
       let shutdown = signal::ctrl_c();
       
       tokio::select! {
           result = server => result,
           _ = shutdown => {
               tracing::info!("received shutdown signal");
               // 优雅关闭
           }
       }
   }
   ```

5. **健康检查端点**：
   ```rust
   // 支持 HTTP 健康检查
   GET /health -> 200 OK { "status": "healthy" }
   ```

6. **指标暴露**：
   ```rust
   // 使用 prometheus 或 opentelemetry
   - active_connections
   - requests_total
   - request_duration_seconds
   ```

### 架构演进方向

当前服务器处于 stub 阶段，未来可能需要：

1. **多传输支持**：
   - stdio（用于 LSP 兼容模式）
   - Unix Domain Socket
   - TLS WebSocket

2. **认证授权**：
   - Token 验证
   - mTLS

3. **资源限制**：
   - 最大并发连接数
   - 单连接请求速率限制
   - 进程资源配额

4. **高可用**：
   - 多实例支持
   - 负载均衡
   - 状态外置（Redis 等）
