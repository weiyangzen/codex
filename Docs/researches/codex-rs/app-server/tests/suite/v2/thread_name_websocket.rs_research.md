# thread_name_websocket.rs 研究文档

## 场景与职责

`thread_name_websocket.rs` 是 Codex App Server v2 API 的集成测试文件，专注于测试通过 WebSocket 传输时 `thread/name/set` 方法的广播通知机制。该测试验证当线程名称被修改时，服务器是否正确地通过 WebSocket 向所有连接的客户端广播 `thread/name/updated` 通知。

该测试文件位于 `codex-rs/app-server/tests/suite/v2/` 目录下，属于 app-server 端到端测试套件的一部分。与基于 stdin/stdout 的 MCP 测试不同，该测试使用 WebSocket 作为传输层，验证多客户端场景下的通知广播功能。

## 功能点目的

该测试文件覆盖了以下核心功能：

1. **WebSocket 通知广播** - 验证线程名称更新时，所有 WebSocket 客户端都能收到通知
2. **已加载线程的名称更新** - 验证对已加载到内存的线程进行重命名时的广播行为
3. **未加载线程的名称更新** - 验证对仅存储在磁盘（未加载）的线程进行重命名时的广播行为
4. **通知内容验证** - 验证通知中包含正确的 thread_id 和新的 thread_name

### 与 MCP 传输的区别

| 特性 | WebSocket 传输 | MCP (stdio) 传输 |
|------|---------------|-----------------|
| 连接方式 | 多客户端可同时连接 | 单进程单连接 |
| 通知广播 | 支持多客户端广播 | 仅单客户端 |
| 使用场景 | 桌面应用、Web 客户端 | CLI、编辑器插件 |
| 初始化 | 需要显式连接和握手 | 由父进程启动 |

## 具体技术实现

### WebSocket 测试基础设施

测试复用 `connection_handling_websocket.rs` 中的基础设施：

```rust
use super::connection_handling_websocket::DEFAULT_READ_TIMEOUT;
use super::connection_handling_websocket::WsClient;
use super::connection_handling_websocket::connect_websocket;
use super::connection_handling_websocket::spawn_websocket_server;
use super::connection_handling_websocket::send_request;
use super::connection_handling_websocket::read_response_for_id;
use super::connection_handling_websocket::read_notification_for_method;
use super::connection_handling_websocket::read_response_and_notification_for_method;
use super::connection_handling_websocket::assert_no_message;
```

#### 关键类型和常量

**WsClient** - WebSocket 客户端类型：
```rust
pub(super) type WsClient = WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>;
```

**DEFAULT_READ_TIMEOUT** - 默认读取超时：
```rust
pub(super) const DEFAULT_READ_TIMEOUT: Duration = Duration::from_secs(5);
```

### 协议类型定义

**ThreadSetNameParams** (`codex-rs/app-server-protocol/src/protocol/v2.rs` 行 2785-2788):
```rust
pub struct ThreadSetNameParams {
    pub thread_id: String,
    pub name: String,
}
```

**ThreadSetNameResponse** (行 2797-2800):
```rust
pub struct ThreadSetNameResponse {}
```

**ThreadNameUpdatedNotification** - 名称更新通知：
```rust
pub struct ThreadNameUpdatedNotification {
    pub thread_id: String,
    pub thread_name: Option<String>,
}
```

**ThreadResumeParams** (行 2558-2611) 和 **ThreadResumeResponse** (行 2613-2628):
用于恢复已存储的线程。

### 测试流程

#### 测试 1: thread_name_updated_broadcasts_for_loaded_threads

验证对已加载线程的重命名广播：

```rust
#[tokio::test]
async fn thread_name_updated_broadcasts_for_loaded_threads() -> Result<()> {
    // 1. 创建 mock 服务器和临时 CODEX_HOME
    let server = create_mock_responses_server_repeating_assistant("Done").await;
    let codex_home = TempDir::new()?;
    create_config_toml(codex_home.path(), &server.uri(), "never")?;
    
    // 2. 创建 rollout 文件（模拟已存储的线程）
    let conversation_id = create_rollout(codex_home.path(), "2025-01-05T12-00-00")?;
    
    // 3. 启动 WebSocket 服务器
    let (mut process, bind_addr) = spawn_websocket_server(codex_home.path()).await?;
    
    // 4. 连接两个 WebSocket 客户端
    let mut ws1 = connect_websocket(bind_addr).await?;
    let mut ws2 = connect_websocket(bind_addr).await?;
    initialize_both_clients(&mut ws1, &mut ws2).await?;
    
    // 5. 客户端 1 恢复线程（加载到内存）
    send_request(&mut ws1, "thread/resume", 10, Some(serde_json::to_value(
        ThreadResumeParams { thread_id: conversation_id.clone(), ..Default::default() }
    )?)).await?;
    let resume_resp: JSONRPCResponse = read_response_for_id(&mut ws1, 10).await?;
    
    // 6. 客户端 1 重命名线程
    let renamed = "Loaded rename";
    send_request(&mut ws1, "thread/name/set", 11, Some(serde_json::to_value(
        ThreadSetNameParams { thread_id: conversation_id.clone(), name: renamed.to_string() }
    )?)).await?;
    
    // 7. 客户端 1 收到响应和通知
    let (rename_resp, ws1_notification) = 
        read_response_and_notification_for_method(&mut ws1, 11, "thread/name/updated").await?;
    assert_thread_name_updated(ws1_notification, &conversation_id, renamed)?;
    
    // 8. 客户端 2 也收到通知（广播）
    let ws2_notification = read_notification_for_method(&mut ws2, "thread/name/updated").await?;
    assert_thread_name_updated(ws2_notification, &conversation_id, renamed)?;
    
    // 9. 验证没有额外的消息
    assert_no_message(&mut ws1, Duration::from_millis(250)).await?;
    assert_no_message(&mut ws2, Duration::from_millis(250)).await?;
    
    // 清理
    process.kill().await?;
    Ok(())
}
```

#### 测试 2: thread_name_updated_broadcasts_for_not_loaded_threads

验证对未加载线程的重命名广播：

```rust
#[tokio::test]
async fn thread_name_updated_broadcasts_for_not_loaded_threads() -> Result<()> {
    // 1-4. 与测试 1 相同：创建 rollout、启动服务器、连接两个客户端
    
    // 5. 直接重命名（不恢复线程）
    let renamed = "Stored rename";
    send_request(&mut ws1, "thread/name/set", 20, Some(serde_json::to_value(
        ThreadSetNameParams { thread_id: conversation_id.clone(), name: renamed.to_string() }
    )?)).await?;
    
    // 6-9. 与测试 1 相同：验证两个客户端都收到通知
}
```

### 辅助函数

**`initialize_both_clients`** - 初始化两个 WebSocket 客户端：
```rust
async fn initialize_both_clients(ws1: &mut WsClient, ws2: &mut WsClient) -> Result<()> {
    send_initialize_request(ws1, 1, "ws_client_one").await?;
    timeout(DEFAULT_READ_TIMEOUT, read_response_for_id(ws1, 1)).await??;
    
    send_initialize_request(ws2, 2, "ws_client_two").await?;
    timeout(DEFAULT_READ_TIMEOUT, read_response_for_id(ws2, 2)).await??;
    Ok(())
}
```

**`create_rollout`** - 创建测试 rollout 文件：
```rust
fn create_rollout(codex_home: &std::path::Path, filename_ts: &str) -> Result<String> {
    create_fake_rollout_with_text_elements(
        codex_home,
        filename_ts,
        "2025-01-05T12:00:00Z",
        "Saved user message",
        Vec::new(),
        Some("mock_provider"),
        None,
    )
}
```

**`assert_thread_name_updated`** - 验证通知内容：
```rust
fn assert_thread_name_updated(
    notification: JSONRPCNotification,
    thread_id: &str,
    thread_name: &str,
) -> Result<()> {
    let notification: ThreadNameUpdatedNotification =
        serde_json::from_value(notification.params.context("thread/name/updated params")?)?;
    assert_eq!(notification.thread_id, thread_id);
    assert_eq!(notification.thread_name.as_deref(), Some(thread_name));
    Ok(())
}
```

### WebSocket 服务器启动

**`spawn_websocket_server`** (来自 connection_handling_websocket.rs)：

```rust
pub(super) async fn spawn_websocket_server(codex_home: &Path) -> Result<(Child, SocketAddr)> {
    let program = codex_utils_cargo_bin::cargo_bin("codex-app-server")
        .context("should find app-server binary")?;
    let mut cmd = Command::new(program);
    cmd.arg("--listen")
        .arg("ws://127.0.0.1:0")  // 绑定到随机端口
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .env("CODEX_HOME", codex_home)
        .env("RUST_LOG", "debug");
    
    let mut process = cmd.kill_on_drop(true).spawn()?;
    
    // 从 stderr 解析绑定的地址
    // 等待 "ws://127.0.0.1:PORT" 格式的日志行
    let bind_addr = parse_bind_addr_from_stderr(&mut process).await?;
    
    Ok((process, bind_addr))
}
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/app-server/tests/suite/v2/thread_name_websocket.rs` - 本测试文件（168 行）
- `codex-rs/app-server/tests/suite/v2/connection_handling_websocket.rs` - WebSocket 测试基础设施（461 行）

### 依赖的测试基础设施
- `codex-rs/app-server/tests/common/mcp_process.rs` - McpProcess 实现（用于参考）
- `codex-rs/app-server/tests/common/rollout.rs` - create_fake_rollout_with_text_elements
- `codex-rs/app-server/tests/common/lib.rs` - 测试公共库

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs` - v2 API 协议类型定义
  - `ThreadSetNameParams` (行 2785-2788)
  - `ThreadSetNameResponse` (行 2797-2800)
  - `ThreadNameUpdatedNotification` - 名称更新通知类型
  - `ThreadResumeParams` (行 2558-2611)
  - `ThreadResumeResponse` (行 2613-2628)

### 被测实现（app-server 内部）
- `codex-rs/app-server/src/mcp/methods/thread_set_name.rs` - thread/name/set 方法实现
- `codex-rs/app-server/src/websocket/` - WebSocket 服务器和广播机制
- `codex-rs/app-server/src/session_store.rs` - 会话存储管理

## 依赖与外部交互

### 外部依赖

| Crate | 用途 |
|-------|------|
| `anyhow` | 错误处理 |
| `tokio` | 异步运行时 |
| `tokio-tungstenite` | WebSocket 客户端 |
| `tempfile` | 临时目录创建（CODEX_HOME） |
| `serde_json` | JSON 序列化/反序列化 |
| `pretty_assertions` | 测试断言美化 |
| `futures` | Stream/Sink trait |

### 内部依赖

| Crate | 用途 |
|-------|------|
| `codex_app_server_protocol` | 协议类型定义 |
| `app_test_support` | 测试辅助函数 |

### 进程间交互

```
测试进程 --(WebSocket)--> app-server WebSocket 服务器
    |                           |
    |<--(broadcast)-------------|
    |                           |
ws_client_one               (内存中的会话)
    |                           |
    |<--(broadcast)-------------|
    |                           |
ws_client_two               (磁盘上的 rollout)
```

## 风险、边界与改进建议

### 当前风险与边界

1. **测试覆盖有限** - 仅测试了两个基础场景：
   - 已加载线程的重命名
   - 未加载线程的重命名
   缺少以下场景：
   - 多线程同时重命名
   - 大量客户端同时连接
   - 网络断开/重连场景

2. **时序敏感性** - 测试依赖 `assert_no_message` 的超时机制来验证没有额外消息，这在慢速 CI 环境下可能不稳定。

3. **客户端数量限制** - 仅测试了两个客户端，未验证广播机制在更多客户端下的表现。

4. **错误场景缺失** - 未测试：
   - 重命名不存在的线程
   - 两个客户端同时重命名同一线程
   - WebSocket 断开时的行为

5. **通知顺序** - 未验证通知是否在响应之后发送（虽然代码中先读取响应再读取通知）。

### 改进建议

1. **增加并发测试**：
   ```rust
   async fn thread_name_updated_broadcasts_to_many_clients() -> Result<()>
   async fn thread_name_updated_under_concurrent_renames() -> Result<()>
   ```

2. **增加错误场景测试**：
   ```rust
   async fn thread_name_updated_not_sent_for_nonexistent_thread() -> Result<()>
   async fn thread_name_updated_handles_disconnected_client() -> Result<()>
   ```

3. **增加压力测试**：
   ```rust
   async fn thread_name_updated_performance_with_100_clients() -> Result<()>
   ```

4. **验证 MCP 传输** - 添加对应的 MCP (stdio) 测试：
   ```rust
   // 在 thread_read.rs 或单独文件中
   async fn thread_name_set_via_mcp() -> Result<()>
   ```

5. **扩展通知测试** - 测试其他广播通知：
   - `thread/created`
   - `thread/deleted`
   - `turn/completed`
   - `error` 通知

6. **测试隔离优化** - 考虑：
   - 使用随机端口避免冲突
   - 添加测试超时机制
   - 改进进程清理逻辑

7. **文档补充** - 在协议文档中明确：
   - 广播的精确语义（是否保证送达）
   - 通知的顺序保证
   - 客户端断开后的行为
