# process.rs 研究文档

## 场景与职责

`process.rs` 是 Code Mode 的 **Node.js 进程管理模块**，负责管理 Node.js 子进程的完整生命周期。它是 Rust 代码与 Node.js 运行时之间的底层通信桥梁，处理进程启动、消息传递、错误处理和资源清理。

**核心定位**：
- 进程生命周期管理：启动、监控、终止 Node.js 进程
- 双向通信：通过 stdin/stdout 与 Node.js 进行 JSON 行协议通信
- 异步消息路由：将响应路由到正确的等待者
- 错误处理：捕获 stderr 输出并记录警告

## 功能点目的

### 1. 进程结构管理（CodeModeProcess）
```rust
pub(super) struct CodeModeProcess {
    pub(super) child: tokio::process::Child,
    pub(super) stdin: Arc<Mutex<tokio::process::ChildStdin>>,
    pub(super) stdout_task: JoinHandle<()>,
    pub(super) response_waiters: Arc<Mutex<HashMap<String, oneshot::Sender<NodeToHostMessage>>>>,
    pub(super) message_rx: Arc<Mutex<mpsc::UnboundedReceiver<NodeToHostMessage>>>,
}
```
- `child`：子进程句柄，用于进程控制
- `stdin`：标准输入，用于发送消息到 Node.js
- `stdout_task`：异步任务，持续读取 stdout 并解析消息
- `response_waiters`：等待响应的 oneshot channel 映射表
- `message_rx`：接收异步消息（如 ToolCall、Notify）的通道

### 2. 消息发送（send 方法）
```rust
pub(super) async fn send(
    &mut self,
    request_id: &str,
    message: &HostToNodeMessage,
) -> Result<NodeToHostMessage, std::io::Error>
```
流程：
1. 检查 stdout_task 是否已完成（进程是否存活）
2. 创建 oneshot channel 用于接收响应
3. 将 sender 注册到 response_waiters
4. 序列化消息并写入 stdin
5. 等待 oneshot receiver 返回响应

### 3. 进程启动（spawn_code_mode_process）
```rust
pub(super) async fn spawn_code_mode_process(
    node_path: &std::path::Path,
) -> Result<CodeModeProcess, std::io::Error>
```
启动流程：
1. 构建 `tokio::process::Command`
2. 添加 `--experimental-vm-modules` 标志（支持 VM 模块）
3. 使用 `--eval` 执行 `runner.cjs` 内容
4. 配置 stdin/stdout/stderr 管道
5. 启动进程
6. 启动 stderr 读取任务（记录警告日志）
7. 启动 stdout 读取任务（解析 JSON 消息）
8. 返回 `CodeModeProcess`

### 4. 消息写入（write_message）
```rust
pub(super) async fn write_message(
    stdin: &Arc<Mutex<tokio::process::ChildStdin>>,
    message: &HostToNodeMessage,
) -> Result<(), std::io::Error>
```
- 序列化消息为 JSON
- 写入 stdin 并添加换行符
- 刷新缓冲区

## 具体技术实现

### 进程启动命令
```rust
let mut cmd = tokio::process::Command::new(node_path);
cmd.arg("--experimental-vm-modules");  // 启用 VM 模块实验特性
cmd.arg("--eval");
cmd.arg(CODE_MODE_RUNNER_SOURCE);       // runner.cjs 内容
cmd.stdin(std::process::Stdio::piped())
   .stdout(std::process::Stdio::piped())
   .stderr(std::process::Stdio::piped())
   .kill_on_drop(true);                  // 进程在 CodeModeProcess drop 时自动终止
```

### 消息路由机制

**请求-响应模式**：
```
Rust 端
    │
    ├──> send(request_id, message)
    │       │
    │       ├──> response_waiters.insert(request_id, tx)
    │       ├──> write_message(stdin, message)
    │       └──> rx.await (等待响应)
    │
    └──> stdout_task 循环
            │
            ├──> 读取一行 stdout
            ├──> 解析为 NodeToHostMessage
            ├──> 如果 message 有 request_id
            │       └──> 从 response_waiters 移除并发送给等待者
            └──> 如果 message 是 ToolCall/Notify
                    └──> 发送到 message_tx (异步消息)
```

**消息分类处理**：
```rust
match message {
    // 异步消息：转发到 message_tx
    message @ (NodeToHostMessage::ToolCall { .. } | NodeToHostMessage::Notify { .. }) => {
        let _ = message_tx.send(message);
    }
    // 响应消息：路由到对应的等待者
    message => {
        if let Some(request_id) = message_request_id(&message)
            && let Some(waiter) = response_waiters.lock().await.remove(request_id)
        {
            let _ = waiter.send(message);
        }
    }
}
```

### 错误处理策略

| 场景 | 处理方式 |
|------|---------|
| 进程启动失败 | 返回 `std::io::Error` |
| stdout 读取错误 | 记录警告，退出读取循环 |
| JSON 解析错误 | 记录警告，退出读取循环 |
| 消息写入错误 | 从 response_waiters 移除等待者，返回错误 |
| 等待者已消失 | 忽略（使用 `let _ =`） |
| 进程已退出 | `send` 方法返回错误 "runner is not available" |

### 资源清理

**Drop 行为**：
- `kill_on_drop(true)` 确保进程在 `CodeModeProcess` 被 drop 时终止
- `stdout_task` 在进程退出或读取错误时自动结束
- `response_waiters` 在 stdout_task 结束时被清空

**stderr 处理**：
```rust
tokio::spawn(async move {
    let mut reader = BufReader::new(stderr);
    let mut buf = Vec::new();
    match reader.read_to_end(&mut buf).await {
        Ok(_) => {
            let stderr = String::from_utf8_lossy(&buf).trim().to_string();
            if !stderr.is_empty() {
                warn!("{PUBLIC_TOOL_NAME} runner stderr: {stderr}");
            }
        }
        Err(err) => {
            warn!("failed to read {PUBLIC_TOOL_NAME} stderr: {err}");
        }
    }
});
```
- 异步读取整个 stderr
- 非空时记录警告日志

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/process.rs`

### 调用方
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/service.rs`
  - `ensure_started()` 调用 `spawn_code_mode_process`
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/execute_handler.rs`
  - `process.send()` 发送执行请求
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/wait_handler.rs`
  - `process.send()` 发送 poll/terminate 请求
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/worker.rs`
  - `process.worker()` 创建工作器
  - `write_message()` 发送工具响应

### 依赖项
| crate | 用途 |
|-------|------|
| `tokio::process` | 异步进程管理 |
| `tokio::io` | 异步 IO（BufReader, AsyncBufReadExt, AsyncWriteExt） |
| `tokio::sync` | 同步原语（Mutex, mpsc, oneshot） |
| `tracing::warn` | 日志记录 |

### 相关常量
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/mod.rs`
  - `CODE_MODE_RUNNER_SOURCE`：Node.js 运行时代码
  - `PUBLIC_TOOL_NAME`：工具名称（"exec"）

## 依赖与外部交互

### 与 CodeModeService 的交互
```rust
// service.rs
let node_path = resolve_compatible_node(self.js_repl_node_path.as_deref())
    .await
    .map_err(std::io::Error::other)?;
*process_slot = Some(spawn_code_mode_process(&node_path).await?);
```

### 与 execute_handler/wait_handler 的交互
```rust
// execute_handler.rs
let process_slot = service.ensure_started().await?;
let message = process.send(&request_id, &message).await?;
```

### 与 worker 的交互
```rust
// worker.rs
impl CodeModeProcess {
    pub(super) fn worker(&self, exec: ExecContext, tool_runtime: ToolCallRuntime) -> CodeModeWorker {
        let stdin = self.stdin.clone();
        let message_rx = self.message_rx.clone();
        // 启动工作器任务...
    }
}
```

### 与 protocol 的交互
```rust
use super::protocol::HostToNodeMessage;
use super::protocol::NodeToHostMessage;
use super::protocol::message_request_id;
```

## 风险、边界与改进建议

### 风险点

1. **进程僵死风险**
   - 如果 Node.js 进程陷入无限循环且不响应消息，`send` 会永远等待
   - 缺乏超时机制

2. **消息丢失风险**
   - 如果响应在请求注册之前到达，消息会被丢弃
   - 虽然概率低，但在高并发场景可能发生

3. **内存泄漏风险**
   - `response_waiters` 中的 sender 如果未被移除，会占用内存
   - 当前在 stdout_task 结束时清空，但如果任务异常退出可能残留

4. **JSON 行协议限制**
   - 消息不能包含换行符
   - 大消息可能导致缓冲区问题

### 边界情况

1. **进程快速退出**
   ```rust
   pub(super) fn has_exited(&mut self) -> Result<bool, std::io::Error> {
       self.child.try_wait().map(|status| status.is_some())
   }
   ```
   在 `send` 前检查，但检查和使用之间可能有竞争条件

2. **空消息**
   ```rust
   if line.trim().is_empty() {
       continue;
   }
   ```
   正确处理空行

3. **无效 JSON**
   ```rust
   let message: NodeToHostMessage = match serde_json::from_str(&line) {
       Ok(message) => message,
       Err(err) => {
           warn!("failed to parse {PUBLIC_TOOL_NAME} stdout message: {err}");
           break;
       }
   };
   ```
   记录警告并退出读取循环

4. **并发发送**
   - `stdin` 使用 `Arc<Mutex<>>` 保护，确保并发安全
   - 但 `response_waiters` 的操作和消息写入不是原子的

### 改进建议

1. **添加超时机制**
   ```rust
   pub(super) async fn send_with_timeout(
       &mut self,
       request_id: &str,
       message: &HostToNodeMessage,
       timeout: Duration,
   ) -> Result<NodeToHostMessage, std::io::Error> {
       tokio::time::timeout(timeout, self.send(request_id, message)).await
           .map_err(|_| std::io::Error::new(std::io::ErrorKind::TimedOut, "request timeout"))?
   }
   ```

2. **心跳检测**
   - 定期发送 ping 消息检测进程健康
   - 无响应时自动重启进程

3. **消息队列优化**
   - 使用有界通道替代 `mpsc::unbounded_channel`，防止内存无限增长
   - 设置合理的缓冲区大小

4. **更好的错误分类**
   ```rust
   pub enum CodeModeProcessError {
       ProcessNotAvailable,
       RequestTimeout,
       InvalidResponse(String),
       Io(std::io::Error),
   }
   ```

5. **进程重启策略**
   - 记录进程启动时间和请求次数
   - 定期重启进程，防止内存泄漏累积

6. **指标收集**
   - 记录消息发送/接收延迟
   - 记录进程重启次数
   - 记录队列长度

7. **优雅关闭**
   - 实现 `shutdown` 方法，发送关闭信号而非直接 kill
   - 给 Node.js 进程清理资源的机会
