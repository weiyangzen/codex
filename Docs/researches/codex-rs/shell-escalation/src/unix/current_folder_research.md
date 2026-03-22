# codex-rs/shell-escalation/src/unix 深度研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 核心场景

`codex-rs/shell-escalation/src/unix` 模块实现了 **Unix 平台下的 Shell 命令权限升级协议（Shell Escalation Protocol）**。该协议解决的核心问题是：

> **如何在沙箱环境中执行 shell 命令，同时允许特定命令"升级"到更高权限或脱离沙箱执行？**

这在 AI 编程助手（如 Codex）场景中至关重要：
- 默认情况下，AI 执行的 shell 命令应受到严格沙箱限制
- 但某些命令（如 `git push`、`docker build`）需要访问用户凭证、网络或系统资源
- 需要一种安全机制来拦截、审查并决定是否允许这些命令升级执行

### 职责边界

| 职责 | 说明 |
|------|------|
| **命令拦截** | 通过 patched shell（bash/zsh）拦截所有 `execve()` 调用 |
| **权限决策** | 根据策略决定命令是：直接运行（Run）、升级执行（Escalate）、还是拒绝（Deny） |
| **FD 转发** | 在升级场景下，将子进程的标准输入输出通过 Unix Socket 转发 |
| **生命周期管理** | 管理 escalation session 的创建、维护和清理 |
| **超时控制** | 提供可暂停的秒表机制，支持用户审批时的超时暂停 |

### 架构角色

```
┌─────────────────────────────────────────────────────────────────┐
│                         Codex CLI (Rust)                         │
│  ┌─────────────────┐    ┌─────────────────────────────────────┐  │
│  │  Shell Runtime  │───▶│  shell-escalation (this module)     │  │
│  │  (core crate)   │    │  - EscalateServer                   │  │
│  └─────────────────┘    │  - EscalationPolicy                 │  │
│                         │  - EscalationSession                │  │
│                         └─────────────────────────────────────┘  │
│                                      │                           │
│                         ┌────────────▼────────────┐              │
│                         │  codex-execve-wrapper   │              │
│                         │  (binary entry point)   │              │
│                         └────────────┬────────────┘              │
│                                      │                           │
└──────────────────────────────────────┼───────────────────────────┘
                                       │
                              ┌────────▼────────┐
                              │   Patched Zsh   │
                              │  (via EXEC_WRAPPER)
                              └────────┬────────┘
                                       │
                              ┌────────▼────────┐
                              │  User Commands  │
                              └─────────────────┘
```

---

## 功能点目的

### 1. 命令拦截与包装（Execve Wrapper）

**目的**：在不修改用户 shell 配置的前提下，透明地拦截所有命令执行。

**实现方式**：
- 通过 `EXEC_WRAPPER` 环境变量，patched bash/zsh 在调用 `execve()` 前将命令转发给 wrapper
- Wrapper 通过 Unix Socket 与 EscalateServer 通信，请求执行决策

**关键代码**：
```rust
// execve_wrapper.rs
pub async fn main_execve_wrapper() -> anyhow::Result<()> {
    let ExecveWrapperCli { file, argv } = ExecveWrapperCli::parse();
    let exit_code = crate::run_shell_escalation_execve_wrapper(file, argv).await?;
    std::process::exit(exit_code);
}
```

### 2. 三级执行决策（Run/Escalate/Deny）

**目的**：根据策略灵活控制命令执行方式。

| 决策 | 含义 | 使用场景 |
|------|------|----------|
| **Run** | 直接在沙箱内执行 | 普通安全命令（如 `ls`, `cat`） |
| **Escalate** | 脱离沙箱，在服务端执行 | 需要凭证/网络的命令（如 `git push`） |
| **Deny** | 拒绝执行 | 明确禁止的危险命令 |

**决策流程**：
```rust
// escalate_protocol.rs
pub enum EscalationDecision {
    Run,
    Escalate(EscalationExecution),
    Deny { reason: Option<String> },
}

pub enum EscalationExecution {
    Unsandboxed,           // 完全无沙箱
    TurnDefault,           // 使用当前 turn 的默认沙箱
    Permissions(EscalationPermissions), // 指定权限配置
}
```

### 3. 文件描述符转发（FD Passing）

**目的**：升级执行的命令需要保持与用户终端的交互（stdin/stdout/stderr）。

**技术方案**：
- 使用 Unix Domain Socket 的 `SCM_RIGHTS` 控制消息传递文件描述符
- 客户端发送 `SuperExecMessage` 包含目标 FD 编号
- 服务端通过 `dup2()` 将接收到的 FD 映射到子进程的标准 IO

```rust
// escalate_server.rs
unsafe {
    command.pre_exec(move || {
        for (dst_fd, src_fd) in msg.fds.iter().zip(&fds) {
            libc::dup2(src_fd.as_raw_fd(), *dst_fd);
        }
        Ok(())
    });
}
```

### 4. 可暂停超时控制（Stopwatch）

**目的**：用户审批命令时，暂停超时计时。

**特性**：
- 支持嵌套/重叠暂停（引用计数）
- 异步通知机制（`tokio::sync::Notify`）
- 与 `CancellationToken` 集成

```rust
// stopwatch.rs
pub async fn pause_for<F, T>(&self, fut: F) -> T
where
    F: Future<Output = T>,
{
    self.pause().await;
    let result = fut.await;
    self.resume().await;
    result
}
```

---

## 具体技术实现

### 3.1 通信协议设计

#### 3.1.1 协议消息定义

```rust
// escalate_protocol.rs

/// 客户端发送的执行请求
#[derive(Clone, Serialize, Deserialize, Debug, PartialEq, Eq)]
pub struct EscalateRequest {
    pub file: PathBuf,           // 可执行文件路径
    pub argv: Vec<String>,       // 参数列表（含 argv[0]）
    pub workdir: AbsolutePathBuf, // 工作目录
    pub env: HashMap<String, String>, // 环境变量
}

/// 服务端返回的执行决策
#[derive(Clone, Serialize, Deserialize, Debug, PartialEq, Eq)]
pub struct EscalateResponse {
    pub action: EscalateAction,
}

pub enum EscalateAction {
    Run,
    Escalate,
    Deny { reason: Option<String> },
}

/// FD 转发消息
#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct SuperExecMessage {
    pub fds: Vec<RawFd>,  // 目标 FD 编号（如 [0, 1, 2]）
}

/// 执行结果返回
#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct SuperExecResult {
    pub exit_code: i32,
}
```

#### 3.1.2 双 Socket 设计

为避免并发请求冲突，协议采用 **Datagram Socket + Stream Socket** 的双层设计：

```
┌─────────────────────────────────────────────────────────────┐
│  Handshake Phase (Datagram Socket - CODEX_ESCALATE_SOCKET)  │
│  ┌──────────────┐                    ┌──────────────┐       │
│  │   Client     │ ──[0]+stream_fd──▶ │    Server    │       │
│  │  (Wrapper)   │ ◀──────ack───────  │              │       │
│  └──────────────┘                    └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│   Data Phase (Stream Socket - created per request)          │
│  ┌──────────────┐                    ┌──────────────┐       │
│  │   Client     │ ──EscalateRequest─▶│    Server    │       │
│  │              │ ◀─EscalateResponse─│              │       │
│  │              │ ──SuperExecMessage─│              │       │
│  │              │ ◀─SuperExecResult──│              │       │
│  └──────────────┘                    └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

**关键代码**（escalate_client.rs）：
```rust
pub async fn run_shell_escalation_execve_wrapper(
    file: String,
    argv: Vec<String>,
) -> anyhow::Result<i32> {
    // 1. 获取 handshake socket
    let handshake_client = get_escalate_client()?;
    
    // 2. 创建新的 stream socket pair
    let (server, client) = AsyncSocket::pair()?;
    
    // 3. 通过 datagram socket 发送 stream socket 的 server end
    handshake_client
        .send_with_fds(&HANDSHAKE_MESSAGE, &[server.into_inner().into()])
        .await?;
    
    // 4. 在 stream socket 上发送 EscalateRequest
    client.send(EscalateRequest { ... }).await?;
    
    // 5. 接收决策并处理
    let message = client.receive::<EscalateResponse>().await?;
    match message.action { ... }
}
```

### 3.2 Socket 抽象层

#### 3.2.1 AsyncSocket（Stream Socket）

位于 `socket.rs`，提供基于 `tokio::io::unix::AsyncFd` 的异步读写能力：

```rust
pub(crate) struct AsyncSocket {
    inner: AsyncFd<Socket>,
}

impl AsyncSocket {
    /// 创建 socket pair
    pub fn pair() -> std::io::Result<(AsyncSocket, AsyncSocket)> {
        let (server, client) = Socket::pair_raw(Domain::UNIX, Type::STREAM, None)?;
        server.set_cloexec(true)?;
        client.set_cloexec(true)?;
        Ok((AsyncSocket::new(server)?, AsyncSocket::new(client)?))
    }

    /// 发送带 FD 的消息
    pub async fn send_with_fds<T: Serialize>(
        &self,
        msg: T,
        fds: &[OwnedFd],
    ) -> std::io::Result<()> {
        let payload = serde_json::to_vec(&msg)?;
        let mut frame = Vec::with_capacity(LENGTH_PREFIX_SIZE + payload.len());
        frame.extend_from_slice(&encode_length(payload.len())?);
        frame.extend_from_slice(&payload);
        send_stream_frame(&self.inner, &frame, fds).await
    }

    /// 接收带 FD 的消息
    pub async fn receive_with_fds<T: for<'de> Deserialize<'de>>(
        &self,
    ) -> std::io::Result<(T, Vec<OwnedFd>)> {
        let (payload, fds) = read_frame(&self.inner).await?;
        let message: T = serde_json::from_slice(&payload)?;
        Ok((message, fds))
    }
}
```

#### 3.2.2 帧协议

消息采用 **Length-Prefixed Framing**：

```
┌─────────────────┬─────────────────────────────────────┐
│  Length (4 bytes) │           Payload (JSON)            │
│   (u32 LE)        │                                     │
└─────────────────┴─────────────────────────────────────┘
```

**FD 传递** 通过 `SCM_RIGHTS` 控制消息实现：

```rust
fn make_control_message(fds: &[OwnedFd]) -> std::io::Result<Vec<u8>> {
    let mut control = vec![0u8; control_space_for_fds(fds.len())];
    unsafe {
        let cmsg = control.as_mut_ptr().cast::<libc::cmsghdr>();
        (*cmsg).cmsg_len = libc::CMSG_LEN(size_of::<RawFd>() as c_uint * fds.len() as c_uint) as _;
        (*cmsg).cmsg_level = libc::SOL_SOCKET;
        (*cmsg).cmsg_type = libc::SCM_RIGHTS;
        let data_ptr = libc::CMSG_DATA(cmsg).cast::<RawFd>();
        for (i, fd) in fds.iter().enumerate() {
            data_ptr.add(i).write(fd.as_raw_fd());
        }
    }
    Ok(control)
}
```

### 3.3 EscalateServer 实现

#### 3.3.1 核心结构

```rust
// escalate_server.rs
pub struct EscalateServer {
    bash_path: PathBuf,           // Shell 路径（如 /bin/zsh）
    execve_wrapper: PathBuf,      // wrapper 可执行文件路径
    policy: Arc<dyn EscalationPolicy>, // 决策策略
}

pub struct EscalationSession {
    env: HashMap<String, String>,  // 需要注入的环境变量
    task: JoinHandle<anyhow::Result<()>>, // 后台处理任务
    client_socket: Arc<Mutex<Option<Socket>>>, // 客户端 socket
    cancellation_token: CancellationToken, // 取消令牌
}
```

#### 3.3.2 Session 生命周期

```rust
impl EscalateServer {
    pub fn start_session(
        &self,
        parent_cancellation_token: CancellationToken,
        command_executor: Arc<dyn ShellCommandExecutor>,
    ) -> anyhow::Result<EscalationSession> {
        // 1. 创建 datagram socket pair
        let (escalate_server, escalate_client) = AsyncDatagramSocket::pair()?;
        let client_socket = escalate_client.into_inner();
        let client_socket_fd = client_socket.as_raw_fd();
        
        // 2. 设置 CLOEXEC=false，使 socket 可以传递给子进程
        client_socket.set_cloexec(false)?;
        
        // 3. 启动后台任务处理 escalation 请求
        let task = tokio::spawn(escalate_task(
            escalate_server,
            Arc::clone(&self.policy),
            Arc::clone(&command_executor),
            parent_cancellation_token,
            cancellation_token.clone(),
        ));
        
        // 4. 构建环境变量
        let mut env = HashMap::new();
        env.insert(ESCALATE_SOCKET_ENV_VAR.to_string(), client_socket_fd.to_string());
        env.insert(EXEC_WRAPPER_ENV_VAR.to_string(), self.execve_wrapper.to_string_lossy().to_string());
        env.insert(LEGACY_BASH_EXEC_WRAPPER_ENV_VAR.to_string(), self.execve_wrapper.to_string_lossy().to_string());
        
        Ok(EscalationSession { env, task, client_socket, cancellation_token })
    }
}
```

#### 3.3.3 请求处理流程

```rust
async fn escalate_task(
    socket: AsyncDatagramSocket,
    policy: Arc<dyn EscalationPolicy>,
    command_executor: Arc<dyn ShellCommandExecutor>,
    parent_cancellation_token: CancellationToken,
    session_cancellation_token: CancellationToken,
) -> anyhow::Result<()> {
    loop {
        // 1. 接收 handshake（包含 stream socket）
        let (_, mut fds) = socket.receive_with_fds().await?;
        let stream_socket = AsyncSocket::from_fd(fds.remove(0))?;
        
        // 2. 为每个请求 spawn 独立任务
        tokio::spawn(handle_escalate_session_with_policy(
            stream_socket, policy, command_executor, ...
        ));
    }
}
```

### 3.4 策略接口（EscalationPolicy）

```rust
// escalation_policy.rs
#[async_trait::async_trait]
pub trait EscalationPolicy: Send + Sync {
    async fn determine_action(
        &self,
        file: &AbsolutePathBuf,      // 可执行文件绝对路径
        argv: &[String],             // 参数列表
        workdir: &AbsolutePathBuf,   // 工作目录
    ) -> anyhow::Result<EscalationDecision>;
}
```

**实际实现** 位于 `codex-rs/core/src/tools/runtimes/shell/unix_escalation.rs`：
- 检查 `execve_session_approvals` 缓存
- 匹配 skill 脚本
- 执行 execpolicy 规则评估
- 根据配置决定是否需要用户审批

### 3.5 Shell Patches

#### Bash Patch（shell-tool-mcp/patches/bash-exec-wrapper.patch）

```c
char* exec_wrapper = getenv("EXEC_WRAPPER");
if (exec_wrapper && *exec_wrapper && !whitespace (*exec_wrapper))
{
    char *orig_command = command;
    larray = strvec_len (args);
    memmove (args + 2, args, (++larray) * sizeof (char *));
    args[0] = exec_wrapper;
    args[1] = orig_command;
    command = exec_wrapper;
}
execve (command, args, env);
```

#### Zsh Patch（shell-tool-mcp/patches/zsh-exec-wrapper.patch）

```c
exec_argv = argv;
if ((exec_wrapper = getenv("EXEC_WRAPPER")) &&
    *exec_wrapper && !inblank(*exec_wrapper)) {
    exec_argv = argv - 2;
    exec_argv[0] = exec_wrapper;
    exec_argv[1] = orig_pth;
    pth = exec_wrapper;
}
execve(pth, exec_argv, newenvp);
```

---

## 关键代码路径与文件引用

### 4.1 模块文件结构

```
codex-rs/shell-escalation/src/unix/
├── mod.rs                    # 模块入口，导出公共 API
├── escalate_protocol.rs      # 协议消息定义（Request/Response/Action）
├── escalate_server.rs        # EscalateServer 和 Session 实现
├── escalate_client.rs        # Client 端 wrapper 逻辑
├── escalation_policy.rs      # EscalationPolicy trait 定义
├── execve_wrapper.rs         # CLI 入口（main_execve_wrapper）
├── socket.rs                 # AsyncSocket/AsyncDatagramSocket 实现
└── stopwatch.rs              # 可暂停的秒表实现
```

### 4.2 关键代码路径

| 功能 | 文件 | 函数/结构 |
|------|------|-----------|
| 协议消息 | `escalate_protocol.rs` | `EscalateRequest`, `EscalateResponse`, `EscalateAction`, `EscalationDecision` |
| Server 创建 | `escalate_server.rs:128-144` | `EscalateServer::new()` |
| Session 启动 | `escalate_server.rs:186-224` | `EscalateServer::start_session()` |
| 请求处理 | `escalate_server.rs:227-263` | `escalate_task()` |
| 决策执行 | `escalate_server.rs:265-380` | `handle_escalate_session_with_policy()` |
| Client 入口 | `escalate_client.rs:37-130` | `run_shell_escalation_execve_wrapper()` |
| FD 转发 | `escalate_client.rs:74-95` | `SuperExecMessage` 发送 |
| Socket 创建 | `socket.rs:264-273` | `AsyncSocket::pair()` |
| FD 发送 | `socket.rs:275-285` | `AsyncSocket::send_with_fds()` |
| FD 接收 | `socket.rs:287-293` | `AsyncSocket::receive_with_fds()` |
| 帧读取 | `socket.rs:81-85` | `read_frame()` |
| 控制消息构造 | `socket.rs:206-229` | `make_control_message()` |
| 控制消息解析 | `socket.rs:49-75` | `extract_fds()` |
| 策略接口 | `escalation_policy.rs` | `EscalationPolicy` trait |
| 秒表 | `stopwatch.rs` | `Stopwatch` struct |

### 4.3 外部调用路径

```
codex-rs/cli/src/main.rs
    └── arg0_dispatch_or_else()
        └── codex-rs/arg0/src/lib.rs
            └── arg0_dispatch()
                └── if exe_name == "codex-execve-wrapper"
                    └── codex_shell_escalation::run_shell_escalation_execve_wrapper()
                        └── escalate_client.rs

codex-rs/core/src/tools/runtimes/shell.rs
    └── ShellRuntime::run()
        └── zsh_fork_backend::maybe_run_shell_command()
            └── unix_escalation::try_run_zsh_fork()
                └── EscalateServer::exec()
                    └── EscalateServer::start_session()
                        └── escalate_server.rs
```

---

## 依赖与外部交互

### 5.1 内部依赖

| Crate | 用途 |
|-------|------|
| `codex-protocol` | `EscalationPermissions`, `Permissions`, `PermissionProfile` |
| `codex-utils-absolute-path` | `AbsolutePathBuf` 路径处理 |

### 5.2 外部依赖

| Crate | 版本 | 用途 |
|-------|------|------|
| `tokio` | workspace | 异步运行时、process、signal、time |
| `tokio-util` | workspace | `CancellationToken` |
| `socket2` | workspace | 底层 Unix Socket 操作 |
| `serde`/`serde_json` | workspace | 协议序列化 |
| `libc` | workspace | `dup2`, `fcntl`, `kill` 等系统调用 |
| `async-trait` | workspace | 异步 trait 支持 |
| `anyhow` | workspace | 错误处理 |
| `tracing` | workspace | 日志追踪 |
| `clap` | workspace | CLI 参数解析 |

### 5.3 环境变量

| 变量名 | 定义位置 | 用途 |
|--------|----------|------|
| `CODEX_ESCALATE_SOCKET` | `escalate_protocol.rs:11` | Wrapper 与 Server 通信的 socket FD |
| `EXEC_WRAPPER` | `escalate_protocol.rs:14` | Patched shell 使用的 wrapper 路径 |
| `BASH_EXEC_WRAPPER` | `escalate_protocol.rs:17` | Bash 兼容性别名 |

### 5.4 与 Core Crate 的交互

```rust
// codex-rs/core/src/tools/runtimes/shell/unix_escalation.rs

// 1. 创建 EscalateServer
let escalate_server = EscalateServer::new(
    shell_zsh_path.clone(),
    main_execve_wrapper_exe,
    escalation_policy,  // 实现 EscalationPolicy trait
);

// 2. 执行命令
let exec_result = escalate_server
    .exec(exec_params, cancel_token, Arc::new(command_executor))
    .await?;

// 3. CoreShellCommandExecutor 实现 ShellCommandExecutor trait
#[async_trait::async_trait]
impl ShellCommandExecutor for CoreShellCommandExecutor {
    async fn run(&self, ...) -> anyhow::Result<ExecResult> { ... }
    async fn prepare_escalated_exec(&self, ...) -> anyhow::Result<PreparedExec> { ... }
}
```

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 FD 泄漏风险

**问题**：`AsyncDatagramSocket::from_raw_fd()` 标记为 `unsafe`，且 TODO 注释指出应限制单次调用。

```rust
// escalate_client.rs:20-29
fn get_escalate_client() -> anyhow::Result<AsyncDatagramSocket> {
    // TODO: we should defensively require only calling this once, 
    // since AsyncSocket will take ownership of the fd.
    let client_fd = std::env::var(ESCALATE_SOCKET_ENV_VAR)?.parse::<i32>()?;
    Ok(unsafe { AsyncDatagramSocket::from_raw_fd(client_fd) }?)
}
```

**建议**：添加运行时检查确保每个进程只调用一次。

#### 6.1.2 信号转发未实现

```rust
// escalate_client.rs:85
// TODO: also forward signals over the super-exec socket
```

**影响**：升级执行的命令无法接收 Ctrl+C 等信号。

#### 6.1.3 FD 重叠边界情况

虽然代码已处理 `src_fd == dst_fd` 的情况（见测试 `handle_escalate_session_accepts_received_fds_that_overlap_destinations`），但仍需确保：

```rust
// escalate_server.rs:346-351
unsafe {
    command.pre_exec(move || {
        for (dst_fd, src_fd) in msg.fds.iter().zip(&fds) {
            libc::dup2(src_fd.as_raw_fd(), *dst_fd);  // 可能 src == dst
        }
        Ok(())
    });
}
```

### 6.2 边界条件

| 边界 | 处理 |
|------|------|
| 最大 FD 数 | `MAX_FDS_PER_MESSAGE = 16`（socket.rs:19） |
| 最大消息大小 | `MAX_DATAGRAM_SIZE = 8192`（socket.rs:21） |
| 消息长度 | `u32` 限制（约 4GB） |
| 超时处理 | 通过 `Stopwatch` + `CancellationToken` |
| 并发请求 | 每个请求独立 stream socket，由独立任务处理 |

### 6.3 改进建议

#### 6.3.1 安全性增强

1. **FD 验证**：在 `dup2` 前验证目标 FD 是否在允许范围内（如 0-2）
2. **路径验证**：确保 `file` 参数解析后的绝对路径不在敏感目录
3. **环境变量过滤**：增强敏感环境变量的过滤（当前仅过滤 wrapper 相关变量）

#### 6.3.2 可观测性

1. **Metrics**：添加 escalation 次数、决策分布、延迟等指标
2. **Tracing**：增强 span 信息，便于追踪单个请求的全链路
3. **日志分级**：当前部分错误仅记录为 `tracing::error!`，可考虑分级处理

#### 6.3.3 性能优化

1. **Socket 复用**：考虑连接池化，减少 socket 创建开销
2. **零拷贝**：对于大输出，考虑使用 `splice` 或 `sendfile`
3. **批处理**：对于高频小命令，考虑批处理策略

#### 6.3.4 代码质量

1. **文档**：部分内部函数缺少文档注释
2. **测试覆盖**：虽已有多项测试，但可补充更多边界情况（如超大参数、特殊字符路径）
3. **错误信息**：部分错误信息可更具体，便于排查问题

### 6.4 测试覆盖

当前测试（位于各文件 `#[cfg(test)]` 模块）：

| 测试文件 | 测试项 |
|----------|--------|
| `escalate_client.rs` | `duplicate_fd_for_transfer_does_not_close_original` |
| `escalate_server.rs` | `start_session_exposes_wrapper_env_overlay` |
| | `exec_closes_parent_socket_after_shell_spawn` |
| | `handle_escalate_session_respects_run_in_sandbox_decision` |
| | `handle_escalate_session_resolves_relative_file_against_request_workdir` |
| | `handle_escalate_session_executes_escalated_command` |
| | `handle_escalate_session_accepts_received_fds_that_overlap_destinations` |
| | `handle_escalate_session_passes_permissions_to_executor` |
| | `dropping_session_aborts_intercept_workers_and_kills_spawned_child` |
| `socket.rs` | `async_socket_round_trips_payload_and_fds` |
| | `async_socket_handles_large_payload` |
| | `async_datagram_sockets_round_trip_messages` |
| | `send_datagram_bytes_rejects_excessive_fd_counts` |
| | `send_stream_chunk_rejects_excessive_fd_counts` |
| | `encode_length_errors_for_oversized_messages` |
| | `receive_fails_when_peer_closes_before_header` |
| `stopwatch.rs` | `cancellation_receiver_fires_after_limit` |
| | `pause_prevents_timeout_until_resumed` |
| | `overlapping_pauses_only_resume_once` |
| | `unlimited_stopwatch_never_cancels` |

---

## 附录：关键数据结构

### A.1 EscalateRequest

```rust
pub struct EscalateRequest {
    pub file: PathBuf,           // 可执行文件路径（可能相对）
    pub argv: Vec<String>,       // 参数列表，argv[0] 为程序名
    pub workdir: AbsolutePathBuf, // 绝对工作目录
    pub env: HashMap<String, String>, // 环境变量快照
}
```

### A.2 EscalateResponse / EscalateAction

```rust
pub struct EscalateResponse {
    pub action: EscalateAction,
}

pub enum EscalateAction {
    Run,                           // 直接执行
    Escalate,                      // 升级执行（需要 FD 转发）
    Deny { reason: Option<String> }, // 拒绝执行
}
```

### A.3 SuperExecMessage / SuperExecResult

```rust
pub struct SuperExecMessage {
    pub fds: Vec<RawFd>,  // 目标 FD 编号列表（如 [0, 1, 2]）
}

pub struct SuperExecResult {
    pub exit_code: i32,   // 子进程退出码
}
```

### A.4 ExecParams / ExecResult

```rust
pub struct ExecParams {
    pub command: String,       // Shell 脚本内容
    pub workdir: String,       // 工作目录（绝对路径）
    pub timeout_ms: Option<u64>, // 超时时间（毫秒）
    pub login: Option<bool>,   // 是否使用 -lc（默认 true）
}

pub struct ExecResult {
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
    pub output: String,        // stdout + stderr 聚合
    pub duration: Duration,
    pub timed_out: bool,
}
```

### A.5 PreparedExec

```rust
pub struct PreparedExec {
    pub command: Vec<String>,           // 完整命令（含程序）
    pub cwd: PathBuf,                   // 工作目录
    pub env: HashMap<String, String>,   // 环境变量
    pub arg0: Option<String>,           // 自定义 argv[0]
}
```

---

*文档生成时间：2026-03-22*
*基于 commit：HEAD*
