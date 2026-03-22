# mcp_process.rs 研究文档

## 场景与职责

该文件实现了 `McpProcess` 结构体，用于在集成测试中管理 `codex-app-server` 子进程。它提供了完整的 JSON-RPC 2.0 客户端功能，支持：
1. 启动和初始化 MCP（Model Context Protocol）服务器进程
2. 发送 JSON-RPC 请求和通知
3. 接收和解析 JSON-RPC 响应、错误和通知
4. 管理请求-响应对应关系
5. 优雅地关闭子进程

这是 app-server 集成测试的核心基础设施，几乎所有测试都通过 `McpProcess` 与 app-server 交互。

## 功能点目的

1. **进程生命周期管理**：启动、监控和关闭 codex-app-server 子进程
2. **JSON-RPC 通信**：通过 stdin/stdout 与服务器进行 JSON-RPC 通信
3. **请求管理**：自动生成递增的请求 ID，追踪请求-响应关系
4. **消息缓冲**：支持消息缓冲和重放，处理异步通知
5. **环境控制**：支持自定义环境变量注入

## 具体技术实现

### 核心数据结构

```rust
pub struct McpProcess {
    next_request_id: AtomicI64,           // 原子递增的请求 ID
    #[allow(dead_code)]
    process: Child,                       // 子进程句柄（保留以维持进程生命周期）
    stdin: Option<ChildStdin>,            // 标准输入（用于发送请求）
    stdout: BufReader<ChildStdout>,       // 标准输出（用于接收响应）
    pending_messages: VecDeque<JSONRPCMessage>, // 消息缓冲区
}

pub const DEFAULT_CLIENT_NAME: &str = "codex-app-server-tests";
```

### 进程创建

```rust
impl McpProcess {
    pub async fn new(codex_home: &Path) -> anyhow::Result<Self> {
        Self::new_with_env(codex_home, &[]).await
    }

    pub async fn new_with_env(
        codex_home: &Path,
        env_overrides: &[(&str, Option<&str>)],  // (key, Some(value)) 设置，(key, None) 删除
    ) -> anyhow::Result<Self> {
        let program = codex_utils_cargo_bin::cargo_bin("codex-app-server")
            .context("should find binary for codex-app-server")?;
        
        let mut cmd = Command::new(program);
        cmd.stdin(Stdio::piped())
           .stdout(Stdio::piped())
           .stderr(Stdio::piped())
           .current_dir(codex_home)
           .env("CODEX_HOME", codex_home)
           .env("RUST_LOG", "info")
           .env_remove(CODEX_INTERNAL_ORIGINATOR_OVERRIDE_ENV_VAR);

        // 应用环境变量覆盖
        for (k, v) in env_overrides {
            match v {
                Some(val) => cmd.env(k, val),
                None => cmd.env_remove(k),
            };
        }

        let mut process = cmd.kill_on_drop(true).spawn()?;
        // ... 初始化 stdin/stdout/stderr 处理
    }
}
```

### 初始化握手

```rust
pub async fn initialize(&mut self) -> anyhow::Result<()> {
    self.initialize_with_client_info(ClientInfo {
        name: DEFAULT_CLIENT_NAME.to_string(),
        title: None,
        version: "0.1.0".to_string(),
    }).await?;
    Ok(())
}

async fn initialize_with_params(
    &mut self,
    params: InitializeParams,
) -> anyhow::Result<JSONRPCMessage> {
    let params = Some(serde_json::to_value(params)?);
    let request_id = self.send_request("initialize", params).await?;
    let message = self.read_jsonrpc_message().await?;
    
    match message {
        JSONRPCMessage::Response(response) => {
            // 验证响应 ID
            if response.id != RequestId::Integer(request_id) {
                anyhow::bail!("initialize response id mismatch");
            }
            // 发送 initialized 通知确认
            self.send_notification(ClientNotification::Initialized).await?;
            Ok(JSONRPCMessage::Response(response))
        }
        JSONRPCMessage::Error(error) => { /* 处理错误 */ }
        _ => anyhow::bail!("unexpected message type"),
    }
}
```

### 请求发送

```rust
async fn send_request(
    &mut self,
    method: &str,
    params: Option<serde_json::Value>,
) -> anyhow::Result<i64> {
    let request_id = self.next_request_id.fetch_add(1, Ordering::Relaxed);
    
    let message = JSONRPCMessage::Request(JSONRPCRequest {
        id: RequestId::Integer(request_id),
        method: method.to_string(),
        params,
        trace: None,
    });
    
    self.send_jsonrpc_message(message).await?;
    Ok(request_id)
}

async fn send_jsonrpc_message(&mut self, message: JSONRPCMessage) -> anyhow::Result<()> {
    eprintln!("writing message to stdin: {message:?}");
    let stdin = self.stdin.as_mut().ok_or_else(|| anyhow::format_err!("mcp stdin closed"))?;
    let payload = serde_json::to_string(&message)?;
    stdin.write_all(payload.as_bytes()).await?;
    stdin.write_all(b"\n").await?;
    stdin.flush().await?;
    Ok(())
}
```

### 消息接收与缓冲

```rust
async fn read_jsonrpc_message(&mut self) -> anyhow::Result<JSONRPCMessage> {
    let mut line = String::new();
    self.stdout.read_line(&mut line).await?;
    let message = serde_json::from_str::<JSONRPCMessage>(&line)?;
    eprintln!("read message from stdout: {message:?}");
    Ok(message)
}

async fn read_stream_until_message<F>(&mut self, predicate: F) -> anyhow::Result<JSONRPCMessage>
where
    F: Fn(&JSONRPCMessage) -> bool,
{
    // 首先检查缓冲区
    if let Some(message) = self.take_pending_message(&predicate) {
        return Ok(message);
    }
    
    // 从流中读取直到匹配
    loop {
        let message = self.read_jsonrpc_message().await?;
        if predicate(&message) {
            return Ok(message);
        }
        self.pending_messages.push_back(message);
    }
}
```

### 专用读取方法

```rust
pub async fn read_stream_until_response_message(
    &mut self,
    request_id: RequestId,
) -> anyhow::Result<JSONRPCResponse> { ... }

pub async fn read_stream_until_error_message(
    &mut self,
    request_id: RequestId,
) -> anyhow::Result<JSONRPCError> { ... }

pub async fn read_stream_until_notification_message(
    &mut self,
    method: &str,
) -> anyhow::Result<JSONRPCNotification> { ... }

pub async fn read_stream_until_request_message(&mut self) -> anyhow::Result<ServerRequest> { ... }
```

### Turn 中断处理

```rust
pub async fn interrupt_turn_and_wait_for_aborted(
    &mut self,
    thread_id: String,
    turn_id: String,
    read_timeout: std::time::Duration,
) -> anyhow::Result<()> {
    // 发送中断请求
    let interrupt_request_id = self.send_turn_interrupt_request(...).await?;
    
    // 等待中断响应
    match tokio::time::timeout(
        read_timeout,
        self.read_stream_until_response_message(RequestId::Integer(interrupt_request_id)),
    ).await { ... }
    
    // 等待 turn/completed 通知
    match tokio::time::timeout(
        read_timeout,
        self.read_stream_until_notification_message("turn/completed"),
    ).await { ... }
}
```

### 进程清理（Drop 实现）

```rust
impl Drop for McpProcess {
    fn drop(&mut self) {
        // 1. 关闭 stdin 请求优雅关闭
        drop(self.stdin.take());
        
        // 2. 等待优雅退出（200ms 超时）
        let graceful_start = std::time::Instant::now();
        while graceful_start.elapsed() < Duration::from_millis(200) {
            match self.process.try_wait() {
                Ok(Some(_)) => return,
                Ok(None) => std::thread::sleep(Duration::from_millis(5)),
                Err(_) => return,
            }
        }
        
        // 3. 强制终止
        let _ = self.process.start_kill();
        
        // 4. 等待进程退出（5s 超时）
        let start = std::time::Instant::now();
        while start.elapsed() < Duration::from_secs(5) {
            match self.process.try_wait() {
                Ok(Some(_)) => return,
                Ok(None) => std::thread::sleep(Duration::from_millis(10)),
                Err(_) => return,
            }
        }
    }
}
```

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/app-server/tests/common/mcp_process.rs`（1148 行，是本批次最大的文件）

### 导出位置
- `lib.rs`: `pub use mcp_process::{DEFAULT_CLIENT_NAME, McpProcess};`

### 依赖的协议类型
- `codex_app_server_protocol::*` - JSON-RPC 消息类型、请求参数、响应类型

### 使用方
几乎所有 `codex-rs/app-server/tests/suite/` 下的测试文件都使用 `McpProcess`。

## 依赖与外部交互

### 外部 crate 依赖
- `tokio::process` - 异步进程管理
- `tokio::io` - 异步 IO
- `anyhow` - 错误处理
- `serde_json` - JSON 序列化

### Codex 内部依赖
```
mcp_process.rs
├── codex_app_server_protocol    (所有 JSON-RPC 类型)
├── codex_core::default_client   (CODEX_INTERNAL_ORIGINATOR_OVERRIDE_ENV_VAR)
└── codex_utils_cargo_bin        (cargo_bin 函数)
```

### 子进程交互
```
McpProcess (父进程)          codex-app-server (子进程)
        │                              │
        ├──► stdin (JSON-RPC) ────────►│
        │                              │
        │◄── stdout (JSON-RPC) ◄───────┤
        │                              │
        └──► stderr (转发到控制台) ◄───┤
```

## 风险、边界与改进建议

### 风险
1. **进程泄漏**：虽然 `Drop` 实现了清理逻辑，但在极端情况下（如系统资源耗尽）仍可能泄漏进程
2. **消息丢失**：如果子进程在消息处理期间崩溃，可能丢失未确认的消息
3. **ID 溢出**：`AtomicI64` 在极端长时间运行的测试中可能溢出（虽然实际不太可能发生）
4. **竞态条件**：`pending_messages` 缓冲区的操作是单线程的，但跨 await 点可能存在竞态

### 边界
- 仅支持 JSON-RPC 2.0 协议
- 仅支持单个并发连接（每个 `McpProcess` 实例对应一个子进程）
- 不支持二进制消息传输
- 不支持请求超时（需要调用方使用 `tokio::time::timeout`）
- 消息缓冲区无大小限制，极端情况下可能占用大量内存

### 改进建议

1. **请求超时内置支持**：
```rust
pub async fn send_request_with_timeout(
    &mut self,
    method: &str,
    params: Option<serde_json::Value>,
    timeout: Duration,
) -> anyhow::Result<JSONRPCResponse> { ... }
```

2. **连接健康检查**：
```rust
pub async fn health_check(&mut self) -> bool {
    // 发送 ping 请求验证连接状态
}
```

3. **消息缓冲区限制**：
```rust
const MAX_PENDING_MESSAGES: usize = 1000;

// 在 push_back 前检查
if self.pending_messages.len() >= MAX_PENDING_MESSAGES {
    return Err(anyhow::format_err!("pending message buffer full"));
}
```

4. **结构化日志**：
```rust
// 替换 eprintln! 使用 tracing
tracing::debug!("writing message to stdin: {:?}", message);
```

5. **批量请求支持**：
```rust
pub async fn send_batch_request(
    &mut self,
    requests: Vec<(&str, Option<serde_json::Value>)>,
) -> anyhow::Result<Vec<JSONRPCResponse>> { ... }
```

6. **异步 Drop**：
```rust
pub async fn shutdown(mut self) -> anyhow::Result<()> {
    // 显式关闭方法，替代依赖 Drop
}
```

7. **请求 ID 生成器抽象**：
```rust
trait RequestIdGenerator {
    fn next_id(&self) -> i64;
}

struct AtomicIdGenerator(AtomicI64);
struct DeterministicIdGenerator(RefCell<i64>);  // 用于需要确定性的测试
```
