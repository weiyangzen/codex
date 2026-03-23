# 传输层研究文档

## 场景与职责

`transport.rs` 是 codex-exec-server 的网络传输层实现，负责监听 WebSocket 连接、接受客户端连接并为每个连接启动处理任务。它是 exec-server 的入口点，将网络 I/O 与业务逻辑解耦。

该模块位于 `codex-rs/exec-server/src/server/transport.rs`，实现了基于 WebSocket 的 JSON-RPC 传输协议。

## 功能点目的

### 1. 监听地址解析
- **目的**: 解析用户提供的监听 URL，支持灵活的地址配置
- **实现**: `parse_listen_url` 函数解析 `ws://IP:PORT` 格式的 URL

### 2. WebSocket 服务器
- **目的**: 提供持久的 WebSocket 监听服务
- **实现**: `run_websocket_listener` 使用 `tokio::net::TcpListener` 和 `tokio_tungstenite` 处理 WebSocket 升级

### 3. 连接生命周期管理
- **目的**: 为每个客户端连接创建独立的处理任务
- **实现**: 使用 `tokio::spawn` 为每个连接创建异步任务，实现并发处理

### 4. 错误隔离
- **目的**: 单个连接的失败不影响其他连接和监听服务
- **实现**: 每个连接在独立的任务中处理，错误被捕获并记录

## 具体技术实现

### 默认配置

```rust
pub const DEFAULT_LISTEN_URL: &str = "ws://127.0.0.1:0";
```

- 默认绑定到本地回环地址
- 端口 `0` 表示由操作系统分配可用端口

### 地址解析流程

```
用户输入: "ws://127.0.0.1:8080"
         |
         v
┌─────────────────┐
│ parse_listen_url │
└────────┬────────┘
         |
    ┌────┴────┐
    v         v
 ws://    IP:PORT
    |         |
    |    SocketAddr::parse()
    |         |
    v         v
  Ok()    或 Err(InvalidWebSocketListenUrl)
         |
         v
  不支持的其他协议
         |
         v
  Err(UnsupportedListenUrl)
```

### 服务器架构

```
┌─────────────────────────────────────┐
│         run_websocket_listener       │
│              主循环                  │
└───────────────┬─────────────────────┘
                │ TcpListener::accept()
                v
┌─────────────────────────────────────┐
│           tokio::spawn               │
│    为每个连接创建独立任务            │
└───────────────┬─────────────────────┘
                │
        ┌───────┴───────┐
        v               v
┌──────────────┐  ┌──────────────┐
│ accept_async │  │ 连接失败处理  │
│ WebSocket升级 │  │ 记录警告日志  │
└──────┬───────┘  └──────────────┘
       │
       v
┌─────────────────────────────────────┐
│   run_connection(JsonRpcConnection)  │
│      进入 JSON-RPC 处理流程          │
└─────────────────────────────────────┘
```

### 关键函数详解

#### 1. `parse_listen_url` - 地址解析
```rust
pub(crate) fn parse_listen_url(
    listen_url: &str,
) -> Result<SocketAddr, ExecServerListenUrlParseError> {
    if let Some(socket_addr) = listen_url.strip_prefix("ws://") {
        return socket_addr.parse::<SocketAddr>().map_err(|_| {
            ExecServerListenUrlParseError::InvalidWebSocketListenUrl(listen_url.to_string())
        });
    }

    Err(ExecServerListenUrlParseError::UnsupportedListenUrl(
        listen_url.to_string(),
    ))
}
```

**设计决策**:
- 仅支持 `ws://` 协议（WebSocket）
- 要求 IP 地址而非主机名（避免 DNS 解析复杂性）
- 自定义错误类型提供清晰的错误信息

#### 2. `run_transport` - 传输层入口
```rust
pub(crate) async fn run_transport(
    listen_url: &str,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let bind_address = parse_listen_url(listen_url)?;
    run_websocket_listener(bind_address).await
}
```

**职责**:
- 解析地址
- 启动 WebSocket 监听器
- 错误向上传播

#### 3. `run_websocket_listener` - 核心服务器
```rust
async fn run_websocket_listener(
    bind_address: SocketAddr,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let listener = TcpListener::bind(bind_address).await?;
    let local_addr = listener.local_addr()?;
    tracing::info!("codex-exec-server listening on ws://{local_addr}");

    loop {
        let (stream, peer_addr) = listener.accept().await?;
        tokio::spawn(async move {
            match accept_async(stream).await {
                Ok(websocket) => {
                    run_connection(JsonRpcConnection::from_websocket(
                        websocket,
                        format!("exec-server websocket {peer_addr}"),
                    ))
                    .await;
                }
                Err(err) => {
                    warn!(
                        "failed to accept exec-server websocket connection from {peer_addr}: {err}"
                    );
                }
            }
        });
    }
}
```

**关键点**:
- `TcpListener::bind` 绑定地址
- `local_addr()` 获取实际分配的地址（端口为 0 时）
- 无限循环接受连接
- 每个连接在独立任务中处理
- WebSocket 升级失败仅记录日志，不影响服务

### 错误类型定义

```rust
#[derive(Debug, Clone, Eq, PartialEq)]
pub enum ExecServerListenUrlParseError {
    UnsupportedListenUrl(String),
    InvalidWebSocketListenUrl(String),
}

impl std::fmt::Display for ExecServerListenUrlParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ExecServerListenUrlParseError::UnsupportedListenUrl(listen_url) => write!(
                f,
                "unsupported --listen URL `{listen_url}`; expected `ws://IP:PORT`"
            ),
            ExecServerListenUrlParseError::InvalidWebSocketListenUrl(listen_url) => write!(
                f,
                "invalid websocket --listen URL `{listen_url}`; expected `ws://IP:PORT`"
            ),
        }
    }
}

impl std::error::Error for ExecServerListenUrlParseError {}
```

**设计特点**:
- 使用枚举区分错误类型
- 实现 `Display` 提供用户友好的错误信息
- 实现 `Error` trait 便于错误处理
- 包含原始 URL 便于调试

## 依赖与外部交互

### 内部模块依赖

```
transport.rs
    ├── processor.rs    (run_connection, 连接处理)
    └── connection.rs   (JsonRpcConnection, WebSocket 包装)
```

### 外部 crate 依赖

| crate | 用途 |
|-------|------|
| `tokio::net::TcpListener` | TCP 监听 |
| `tokio_tungstenite::accept_async` | WebSocket 协议升级 |
| `tracing` | 日志记录（info, warn） |

### 调用关系

#### 被调用方
- `server.rs:17` - `run_main_with_listen_url` 调用 `run_transport`
- `codex-exec-server.rs:17` - CLI 入口调用 `run_main_with_listen_url`

#### 调用方
- `processor::run_connection` - 连接建立后进入处理流程
- `JsonRpcConnection::from_websocket` - 包装 WebSocket 流

### 模块导出

```rust
// server.rs
pub use transport::DEFAULT_LISTEN_URL;
pub use transport::ExecServerListenUrlParseError;
```

```rust
// lib.rs
pub use server::DEFAULT_LISTEN_URL;
pub use server::ExecServerListenUrlParseError;
```

## 风险、边界与改进建议

### 当前风险

1. **无连接数限制**
   - 现状：无限接受新连接
   - 风险：资源耗尽（文件描述符、内存）
   - 建议：添加最大连接数限制和连接速率限制

2. **无 TLS 支持**
   - 现状：仅支持 `ws://`，不支持 `wss://`
   - 风险：传输数据未加密
   - 建议：添加 TLS 支持

3. **连接无超时**
   - 现状：空闲连接永久保持
   - 风险：资源泄漏
   - 建议：添加空闲超时和总连接超时

4. **优雅关闭未实现**
   - 现状：`loop` 无限循环，无法优雅关闭
   - 风险：服务重启时可能中断活跃连接
   - 建议：添加关闭信号处理

5. **单点故障**
   - 现状：单线程监听
   - 风险：无法利用多核 CPU
   - 建议：考虑多线程/多进程监听（SO_REUSEPORT）

### 边界情况

1. **端口冲突**
   - 如果指定端口被占用，`TcpListener::bind` 返回错误
   - 使用端口 0 可避免此问题

2. **WebSocket 升级失败**
   - 非 WebSocket 客户端连接会导致升级失败
   - 错误被捕获并记录，服务继续运行

3. **连接突然断开**
   - 网络问题或客户端崩溃
   - `run_connection` 会处理断开事件并清理资源

4. **IPv6 支持**
   - 当前支持 IPv6 地址（如 `ws://[::1]:8080`）
   - 但文档仅提及 IP:PORT

### 改进建议

1. **添加连接限制**
```rust
use tokio::sync::Semaphore;

static CONNECTION_LIMIT: Semaphore = Semaphore::const_new(1000);

// 在 accept 循环中
let _permit = CONNECTION_LIMIT.try_acquire()?;
tokio::spawn(async move {
    // ... 处理连接
    drop(_permit);  // 连接关闭时释放
});
```

2. **添加 TLS 支持**
```rust
pub(crate) async fn run_tls_websocket_listener(
    bind_address: SocketAddr,
    tls_config: rustls::ServerConfig,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // 使用 tokio-rustls 处理 TLS
}
```

3. **优雅关闭**
```rust
use tokio::signal;

pub(crate) async fn run_transport_with_shutdown(
    listen_url: &str,
    mut shutdown: tokio::sync::broadcast::Receiver<()>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // 使用 tokio::select! 监听关闭信号
}
```

4. **连接指标**
```rust
metrics::gauge!("exec_server_active_connections").set(active_connections as f64);
metrics::counter!("exec_server_connections_total").increment(1);
metrics::counter!("exec_server_connection_errors_total").increment(1);
```

5. **支持更多地址格式**
```rust
// 支持主机名
if let Some(host_port) = listen_url.strip_prefix("ws://") {
    if let Ok(socket_addr) = host_port.parse::<SocketAddr>() {
        return Ok(socket_addr);
    }
    // 尝试 DNS 解析
    if let Ok(addrs) = tokio::net::lookup_host(host_port).await {
        return Ok(addrs.next().unwrap());
    }
}
```

### 相关文件引用

- 本文件：`codex-rs/exec-server/src/server/transport.rs`
- 测试文件：`codex-rs/exec-server/src/server/transport_tests.rs`
- 连接处理：`codex-rs/exec-server/src/server/processor.rs`
- 连接管理：`codex-rs/exec-server/src/connection.rs`
- 服务器模块：`codex-rs/exec-server/src/server.rs`
- 库入口：`codex-rs/exec-server/src/lib.rs`
- CLI 入口：`codex-rs/exec-server/src/bin/codex-exec-server.rs`
