# escalate_server.rs 研究文档

## 场景与职责

`escalate_server.rs` 是 Unix 平台 shell 权限提升机制的**服务器端实现**，是整个权限提升系统的核心控制中枢。它负责监听来自 execve 包装器的权限提升请求，根据配置的权限策略决定命令的执行方式（本地执行、提升权限执行或拒绝），并管理 escalated 命令的生命周期。

核心职责：
1. 创建和管理权限提升会话（`EscalationSession`）
2. 监听并处理来自客户端的 `EscalateRequest`
3. 根据 `EscalationPolicy` 决策执行策略
4. 在需要时接收客户端的 stdio FD 并执行命令
5. 管理命令生命周期（超时、取消、信号处理）
6. 返回执行结果给客户端

## 功能点目的

### 1. ShellCommandExecutor Trait

```rust
#[async_trait::async_trait]
pub trait ShellCommandExecutor: Send + Sync {
    async fn run(
        &self,
        command: Vec<String>,
        cwd: PathBuf,
        env_overlay: HashMap<String, String>,
        cancel_rx: CancellationToken,
        after_spawn: Option<Box<dyn FnOnce() + Send>>,
    ) -> anyhow::Result<ExecResult>;

    async fn prepare_escalated_exec(
        &self,
        program: &AbsolutePathBuf,
        argv: &[String],
        workdir: &AbsolutePathBuf,
        env: HashMap<String, String>,
        execution: EscalationExecution,
    ) -> anyhow::Result<PreparedExec>;
}
```

- **解耦设计**：让 `shell-escalation` crate 拥有 Unix 权限提升协议，而调用者控制进程创建、输出捕获和沙箱集成
- `run()`：运行 shell 命令并返回捕获的结果
- `prepare_escalated_exec()`：准备 escalated 子命令的执行参数

### 2. EscalateServer

```rust
pub struct EscalateServer {
    bash_path: PathBuf,
    execve_wrapper: PathBuf,
    policy: Arc<dyn EscalationPolicy>,
}
```

服务器主结构，包含：
- `bash_path`：shell 可执行文件路径
- `execve_wrapper`：execve 包装器路径
- `policy`：权限提升策略（动态分发）

主要方法：
- `new()`：创建服务器实例
- `exec()`：执行完整流程（创建会话、运行 shell、返回结果）
- `start_session()`：启动权限提升会话，返回环境变量覆盖

### 3. EscalationSession

```rust
pub struct EscalationSession {
    env: HashMap<String, String>,
    task: JoinHandle<anyhow::Result<()>>,
    client_socket: Arc<Mutex<Option<Socket>>>,
    cancellation_token: CancellationToken,
}
```

表示一个活跃的权限提升会话：
- `env`：execve 包装器需要的环境变量（socket FD、包装器路径）
- `task`：后台监听任务
- `client_socket`：客户端 socket（用于在 spawn 后关闭）
- `cancellation_token`：会话取消信号

实现 `Drop` trait，确保会话销毁时：
1. 关闭客户端 socket
2. 取消 cancellation token
3. 中止后台任务

### 4. 核心处理流程

**escalate_task**：后台任务主循环
```rust
async fn escalate_task(
    socket: AsyncDatagramSocket,
    policy: Arc<dyn EscalationPolicy>,
    command_executor: Arc<dyn ShellCommandExecutor>,
    parent_cancellation_token: CancellationToken,
    session_cancellation_token: CancellationToken,
) -> anyhow::Result<()>
```

流程：
1. 循环接收 datagram（包含握手消息和 stream socket FD）
2. 为每个连接 spawn 独立的处理任务
3. 监听取消信号

**handle_escalate_session_with_policy**：单个会话处理
```rust
async fn handle_escalate_session_with_policy(
    socket: AsyncSocket,
    policy: Arc<dyn EscalationPolicy>,
    command_executor: Arc<dyn ShellCommandExecutor>,
    parent_cancellation_token: CancellationToken,
    session_cancellation_token: CancellationToken,
) -> anyhow::Result<()>
```

流程：
1. 接收 `EscalateRequest`
2. 解析程序路径（处理相对路径）
3. 调用 `policy.determine_action()` 获取决策
4. 根据决策分支处理：
   - `Run`：发送 `EscalateAction::Run`
   - `Escalate`：发送 `EscalateAction::Escalate`，接收 `SuperExecMessage` 和 FDs，执行命令，返回结果
   - `Deny`：发送 `EscalateAction::Deny`

## 具体技术实现

### 会话启动流程

```rust
pub fn start_session(
    &self,
    parent_cancellation_token: CancellationToken,
    command_executor: Arc<dyn ShellCommandExecutor>,
) -> anyhow::Result<EscalationSession>
```

1. 创建新的 `CancellationToken`
2. 创建 `AsyncDatagramSocket` pair
3. 获取客户端 socket FD，设置 `CLOEXEC = false`（允许跨 exec）
4. Spawn `escalate_task` 后台任务
5. 构建环境变量：
   - `CODEX_ESCALATE_SOCKET=<fd>`
   - `EXEC_WRAPPER=<path>`
   - `BASH_EXEC_WRAPPER=<path>`
6. 返回 `EscalationSession`

### Escalate 执行流程

```rust
// 1. 发送 Escalate 响应
socket.send(EscalateResponse { action: EscalateAction::Escalate }).await?;

// 2. 接收 SuperExecMessage 和 FDs
let (msg, fds) = socket.receive_with_fds::<SuperExecMessage>().await?;

// 3. 验证 FD 数量匹配
if fds.len() != msg.fds.len() { ... }

// 4. 准备执行参数
let PreparedExec { command, cwd, env, arg0 } = 
    command_executor.prepare_escalated_exec(...).await?;

// 5. 创建命令
let mut command = Command::new(program);
command
    .args(args)
    .arg0(arg0.unwrap_or_else(|| program.clone()))
    .envs(&env)
    .current_dir(&cwd)
    .stdin(Stdio::null())
    .stdout(Stdio::null())
    .stderr(Stdio::null())
    .kill_on_drop(true);

// 6. 使用 pre_exec 设置 FD
unsafe {
    command.pre_exec(move || {
        for (dst_fd, src_fd) in msg.fds.iter().zip(&fds) {
            libc::dup2(src_fd.as_raw_fd(), *dst_fd);
        }
        Ok(())
    });
}

// 7. Spawn 并等待
let mut child = command.spawn()?;
let exit_status = tokio::select! {
    status = child.wait() => status?,
    _ = parent_cancellation_token.cancelled() => { ... }
    _ = session_cancellation_token.cancelled() => { ... }
};

// 8. 返回结果
socket.send(SuperExecResult { exit_code: exit_status.code().unwrap_or(127) }).await?;
```

### 取消处理

使用 `tokio_util::sync::CancellationToken` 实现协作式取消：
- `parent_cancellation_token`：父级取消（如整个 turn 结束）
- `session_cancellation_token`：会话级取消（如 `EscalationSession` 被 drop）

在所有异步操作点使用 `tokio::select!` 监听取消信号：
```rust
tokio::select! {
    request = socket.receive::<EscalateRequest>() => request?,
    _ = parent_cancellation_token.cancelled() => return Ok(()),
    _ = session_cancellation_token.cancelled() => return Ok(()),
}
```

## 关键代码路径与文件引用

### 本文件内关键行

| 行号 | 内容 | 说明 |
|------|------|------|
| 35-63 | `ShellCommandExecutor` trait | 执行器抽象接口 |
| 65-86 | `ExecParams`, `ExecResult` | 执行参数和结果 |
| 88-94 | `PreparedExec` | 准备好的执行参数 |
| 96-126 | `EscalationSession` | 会话管理 |
| 128-224 | `EscalateServer` | 服务器主结构 |
| 227-263 | `escalate_task` | 后台监听任务 |
| 265-380 | `handle_escalate_session_with_policy` | 会话处理核心 |
| 382-1071 | 测试模块 |  comprehensive tests |

### 依赖文件

- `escalate_protocol.rs`：协议消息定义
- `escalation_policy.rs`：`EscalationPolicy` trait
- `socket.rs`：`AsyncDatagramSocket`, `AsyncSocket`
- `codex-rs/core/src/tools/runtimes/shell/unix_escalation.rs`：`CoreShellCommandExecutor` 实现

### 被依赖文件

| 文件 | 用途 |
|------|------|
| `mod.rs` | 重新导出 `EscalateServer`, `EscalationSession`, `ExecParams`, `ExecResult`, `PreparedExec`, `ShellCommandExecutor` |
| `codex-rs/core/src/tools/runtimes/shell/unix_escalation.rs` | 实现 `ShellCommandExecutor` trait |

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `anyhow` | 错误处理 |
| `async-trait` | async trait 支持 |
| `codex_utils_absolute_path::AbsolutePathBuf` | 绝对路径处理 |
| `socket2::Socket` | 底层 socket 操作 |
| `tokio::process::Command` | 异步进程管理 |
| `tokio_util::sync::CancellationToken` | 取消信号 |
| `libc` | `dup2` 系统调用 |

### 关键数据结构

```rust
// 执行参数
pub struct ExecParams {
    pub command: String,        // 要执行的 shell 脚本
    pub workdir: String,        // 工作目录（绝对路径）
    pub timeout_ms: Option<u64>,// 超时（毫秒）
    pub login: Option<bool>,    // 是否使用 -lc（默认 true）
}

// 执行结果
pub struct ExecResult {
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
    pub output: String,         // stdout + stderr 聚合
    pub duration: Duration,
    pub timed_out: bool,
}

// 准备好的执行参数
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PreparedExec {
    pub command: Vec<String>,
    pub cwd: PathBuf,
    pub env: HashMap<String, String>,
    pub arg0: Option<String>,
}
```

## 风险、边界与改进建议

### 已知风险

1. **FD 重叠问题**：当接收到的 FD 编号与目标 FD 编号相同时（如都是 stdin=0），`dup2` 会正确处理，但测试用例（第 853-924 行）专门验证了这种边界情况

2. **macOS 特殊处理**：测试中发现需要保持 server_stream 的引用直到 worker 响应，否则 macOS 可能在 transferred fd 完全服务 stream 之前就在客户端观察到 EOF（第 1013-1016 行注释）

3. **进程泄漏风险**：如果 `EscalationSession` 被 drop，会发送取消信号并中止任务，但已经 spawn 的子进程需要通过 `kill_on_drop(true)` 确保清理

### 边界情况

1. **相对路径解析**：使用 `AbsolutePathBuf::resolve_path_against_base` 将相对路径解析为绝对路径（第 282 行）

2. **空命令检查**：`PreparedExec.command` 必须非空，否则返回错误（第 334 行）

3. **FD 数量不匹配**：如果 `SuperExecMessage.fds` 与实际接收的 FD 数量不匹配，返回错误（第 314-320 行）

4. **退出码处理**：如果进程被信号终止，`exit_status.code()` 返回 `None`，使用 `unwrap_or(127)` 作为默认值（第 367 行）

### 测试覆盖

文件包含 comprehensive 的测试套件（约 690 行测试代码）：

| 测试 | 目的 |
|------|------|
| `start_session_exposes_wrapper_env_overlay` | 验证会话只返回包装器/socket 环境变量 |
| `exec_closes_parent_socket_after_shell_spawn` | 验证 spawn 后关闭父 socket |
| `handle_escalate_session_respects_run_in_sandbox_decision` | 验证 Run 决策 |
| `handle_escalate_session_resolves_relative_file_against_request_workdir` | 验证相对路径解析 |
| `handle_escalate_session_executes_escalated_command` | 验证完整 Escalate 流程 |
| `handle_escalate_session_accepts_received_fds_that_overlap_destinations` | 验证 FD 重叠处理 |
| `handle_escalate_session_passes_permissions_to_executor` | 验证权限传递 |
| `dropping_session_aborts_intercept_workers_and_kills_spawned_child` | 验证会话 drop 时的清理 |

测试工具：
- `DeterministicEscalationPolicy`：返回固定决策的策略
- `AssertingEscalationPolicy`：验证期望路径的策略
- `ForwardingShellCommandExecutor`：直接转发执行的执行器
- `AfterSpawnAssertingShellCommandExecutor`：验证 after_spawn 回调的执行器

### 改进建议

1. **信号转发**：TODO 注释指出需要实现信号转发（`escalate_client.rs` 第 85 行），服务器端需要相应的接收和处理逻辑

2. **更细粒度的超时**：当前超时在 `ShellCommandExecutor::run()` 中处理，可以考虑在 `handle_escalate_session_with_policy` 中也添加超时

3. **资源限制**：可以考虑添加对 escalated 进程的资源限制（CPU、内存）

4. **日志增强**：关键决策点（如拒绝执行）可以添加更详细的结构化日志

5. **错误分类**：当前使用 `anyhow::Result`，可以考虑定义更具体的错误类型以便调用者处理

6. **并发控制**：`escalate_task` 为每个连接 spawn 一个任务，如果连接过多可能导致资源耗尽，可以考虑添加限流
