# exec_server.rs 研究文档

## 场景与职责

`exec_server.rs` 是 `codex-exec-server` 的集成测试框架，提供测试基础设施用于启动、连接和与 exec-server 进程进行 WebSocket 通信。它是测试套件的核心辅助模块，负责：

1. **进程生命周期管理**：启动 exec-server 二进制文件，管理其生命周期
2. **WebSocket 连接管理**：建立和维护与 exec-server 的 WebSocket 连接
3. **JSON-RPC 协议封装**：提供高级 API 发送请求/通知，接收响应
4. **测试同步原语**：提供事件等待和超时处理机制

该文件位于 `codex-rs/exec-server/tests/common/exec_server.rs`，作为测试共享库被 `initialize.rs`、`process.rs` 和 `websocket.rs` 等测试文件使用。

## 功能点目的

### 1. ExecServerHarness 结构体
测试 harness，封装测试所需的全部资源：

```rust
pub(crate) struct ExecServerHarness {
    child: Child,                    // 子进程句柄
    websocket: WebSocketStream<...>, // WebSocket 连接
    next_request_id: i64,            // 自增请求 ID
}
```

**设计意图**：
- 通过 `Drop` trait 实现自动清理，确保测试失败时进程被终止
- 封装 WebSocket 连接细节，提供面向 JSON-RPC 的接口
- 维护请求 ID 状态，简化测试代码

### 2. 服务器启动流程 (`exec_server` 函数)
```rust
pub(crate) async fn exec_server() -> anyhow::Result<ExecServerHarness>
```

启动流程：
1. 使用 `cargo_bin("codex-exec-server")` 定位二进制文件（支持 Cargo 和 Bazel 两种构建环境）
2. 调用 `reserve_websocket_url()` 绑定到 `127.0.0.1:0` 获取随机可用端口
3. 使用 `--listen` 参数启动子进程
4. 轮询连接直到服务器就绪（带超时和重试）

### 3. 连接建立机制 (`connect_websocket_when_ready`)
实现带指数退避的连接重试逻辑：
- **超时**：5 秒 (`CONNECT_TIMEOUT`)
- **重试间隔**：25 毫秒 (`CONNECT_RETRY_INTERVAL`)
- **重试条件**：仅对 `ConnectionRefused` 错误进行重试

### 4. JSON-RPC 通信接口

| 方法 | 用途 |
|------|------|
| `send_request` | 发送 JSON-RPC 请求，返回请求 ID 用于匹配响应 |
| `send_notification` | 发送 JSON-RPC 通知（无响应） |
| `send_raw_text` | 发送原始文本（用于测试协议错误处理） |
| `next_event` | 接收下一个事件（5 秒超时） |
| `wait_for_event` | 轮询等待满足条件的事件 |

### 5. 事件处理循环 (`next_event_with_timeout`)
处理 WebSocket 帧类型：
- `Text`/`Binary`：解析为 JSON-RPC 消息
- `Close`：返回连接关闭错误
- `Ping`/`Pong`：忽略（协议保活）

## 具体技术实现

### 关键常量
```rust
const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);
const CONNECT_RETRY_INTERVAL: Duration = Duration::from_millis(25);
const EVENT_TIMEOUT: Duration = Duration::from_secs(5);
```

### 端口分配策略
使用 `TcpListener::bind("127.0.0.1:0")` 让操作系统分配随机端口，立即关闭监听器但保留地址，避免端口冲突：

```rust
fn reserve_websocket_url() -> anyhow::Result<String> {
    let listener = std::net::TcpListener::bind("127.0.0.1:0")?;
    let addr = listener.local_addr()?;
    drop(listener);  // 立即释放，服务器将重新绑定
    Ok(format!("ws://{addr}"))
}
```

### 请求 ID 生成
使用自增整数（从 1 开始），保证每个请求有唯一标识：
```rust
let id = RequestId::Integer(self.next_request_id);
self.next_request_id += 1;
```

### 错误处理模式
- 使用 `anyhow` 进行错误传播和上下文包装
- WebSocket 错误转换为 `anyhow::Error`
- JSON 解析错误直接传播

## 关键代码路径与文件引用

### 调用关系图
```
tests/initialize.rs
    └── common::exec_server::exec_server()
        ├── cargo_bin("codex-exec-server")  [codex-utils-cargo-bin]
        ├── reserve_websocket_url()
        ├── Command::spawn()                [tokio::process]
        └── connect_websocket_when_ready()
            └── tokio_tungstenite::connect_async()
```

### 依赖的协议类型
来自 `codex-app-server-protocol` crate：
- `JSONRPCMessage` - 协议顶层消息枚举
- `JSONRPCRequest` / `JSONRPCResponse` / `JSONRPCNotification` - 消息类型
- `JSONRPCError` - 错误响应
- `RequestId` - 请求标识符

### 被测试的服务器端点
- `initialize` - 初始化握手
- `process/start` - 进程启动（当前返回 stub 错误）

## 依赖与外部交互

### 外部 Crate 依赖
| Crate | 用途 |
|-------|------|
| `tokio` | 异步运行时、进程管理、超时 |
| `tokio-tungstenite` | WebSocket 客户端 |
| `futures` | `SinkExt`/`StreamExt` trait |
| `serde_json` | JSON 序列化/反序列化 |
| `anyhow` | 错误处理 |
| `codex-app-server-protocol` | JSON-RPC 协议类型 |
| `codex-utils-cargo-bin` | 二进制文件定位（Cargo/Bazel 兼容） |

### 环境依赖
- 需要 `codex-exec-server` 二进制文件已构建
- 支持 `CARGO_BIN_EXE_*` 环境变量（Cargo 测试）
- 支持 Bazel runfiles（Bazel 测试）

### 进程间通信
```
测试进程 ←→ WebSocket ←→ codex-exec-server 子进程
         (JSON-RPC 2.0)
```

## 风险、边界与改进建议

### 当前风险

1. **竞态条件风险**
   - `reserve_websocket_url()` 关闭监听器后到服务器启动存在时间窗口，理论上其他进程可能占用该端口
   - 实际风险低（时间窗口极短 + 随机端口）

2. **资源泄漏风险**
   - `Drop` 实现调用 `start_kill()` 发送 SIGKILL，但不等待进程实际终止
   - 在极端情况下可能导致僵尸进程

3. **超时硬编码**
   - 5 秒超时在慢速 CI 环境可能不足
   - 无环境变量覆盖机制

### 边界情况

1. **连接拒绝处理**
   ```rust
   // 仅对 ConnectionRefused 重试，其他错误立即失败
   matches!(err, tokio_tungstenite::tungstenite::Error::Io(ref io_err)
       if io_err.kind() == std::io::ErrorKind::ConnectionRefused)
   ```

2. **畸形消息处理**
   - `send_raw_text` 允许发送非 JSON 数据，用于测试服务器的错误恢复能力
   - 服务器应返回 `JSONRPCError` 并保持连接

3. **平台限制**
   - 测试标记为 `#![cfg(unix)]`，Windows 不支持
   - 原因：进程管理信号差异

### 改进建议

1. **可配置超时**
   ```rust
   // 建议：从环境变量读取超时
   const CONNECT_TIMEOUT: Duration = Duration::from_secs(
       std::env::var("EXEC_SERVER_CONNECT_TIMEOUT")
           .ok()
           .and_then(|s| s.parse().ok())
           .unwrap_or(5)
   );
   ```

2. **优雅关闭**
   ```rust
   // 建议：实现 graceful shutdown
   pub(crate) async fn shutdown(&mut self) -> anyhow::Result<()> {
       // 1. 发送关闭通知（如果协议支持）
       // 2. 等待进程退出（带超时）
       // 3. 必要时强制终止
   }
   ```

3. **端口分配改进**
   - 考虑使用文件锁或独占绑定模式避免竞态
   - 或让服务器绑定后通过 stdout 报告实际端口

4. **日志增强**
   - 当前仅继承 stderr，建议增加结构化日志收集
   - 便于调试测试失败

5. **并发测试支持**
   - 当前设计支持并发（每个测试独立进程 + 随机端口）
   - 但可考虑连接池复用以减少资源消耗

### 相关测试覆盖

| 测试文件 | 覆盖场景 |
|---------|---------|
| `initialize.rs` | 基本初始化握手 |
| `process.rs` | 未实现方法的错误响应 |
| `websocket.rs` | 畸形消息处理、连接恢复 |

### 架构演进建议

当前 exec-server 是 stub 实现，未来扩展时需考虑：
1. 增加 `process/start` 实际实现后的测试覆盖
2. 考虑添加压力测试（并发连接、大消息体）
3. 考虑添加安全测试（认证、授权）
