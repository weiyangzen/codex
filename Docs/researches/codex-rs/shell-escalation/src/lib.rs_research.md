# lib.rs 深度研究文档

## 文件基本信息

- **文件路径**: `codex-rs/shell-escalation/src/lib.rs`
- **所属 Crate**: `codex-shell-escalation`
- **定位**: Unix 平台 shell 权限提升协议的公共 API 入口

---

## 1. 场景与职责

### 1.1 核心场景

`lib.rs` 是 `codex-shell-escalation` crate 的公共接口层，负责在 **Unix 平台** 上实现 shell 命令执行的权限提升（escalation）机制。该机制解决的核心问题是：

> **如何在沙箱环境中执行的 shell 进程，能够安全地请求提升权限执行特定命令，同时保持细粒度的安全控制？**

典型使用场景：
1. **Zsh Fork 后端**: Codex CLI 使用 Zsh 作为 shell 后端执行命令
2. **Execve 拦截**: 通过打补丁的 Bash 拦截 `execve()` 调用
3. **权限决策**: 根据策略决定命令是在沙箱内运行（`Run`）、提升到沙箱外运行（`Escalate`），还是拒绝执行（`Deny`）
4. **文件描述符转发**: 将 stdin/stdout/stderr 等 FD 从客户端转发到服务端执行环境

### 1.2 架构定位

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Codex CLI (codex-rs/core)                          │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────────────┐  │
│  │  Shell Runtime  │───▶│ EscalateServer  │───▶│ ShellCommandExecutor    │  │
│  │  (unix_escalation)│   │  (权限提升服务器)  │    │  (实际执行命令)          │  │
│  └─────────────────┘    └────────┬────────┘    └─────────────────────────┘  │
│                                  │                                          │
│  ┌───────────────────────────────┼─────────────────────────────────────┐   │
│  │                               ▼                                     │   │
│  │  ┌─────────────────────────────────────────────────────────────┐   │   │
│  │  │              codex-shell-escalation (本 crate)               │   │   │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │   │   │
│  │  │  │ lib.rs (API) │  │escalate_server│  │ escalate_client   │   │   │   │
│  │  │  │              │  │   (服务端)    │  │   (客户端)        │   │   │   │
│  │  │  └──────────────┘  └──────────────┘  └──────────────────┘   │   │   │
│  │  └─────────────────────────────────────────────────────────────┘   │   │
│  └───────────────────────────────────────────────────────────────────────┘   │
│                                  │                                          │
│                                  ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    codex-execve-wrapper (子进程)                     │   │
│  │                    (通过 arg0 dispatch 调用)                         │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.3 职责边界

| 职责 | 说明 |
|------|------|
| **平台抽象** | 仅暴露 Unix 平台实现，非 Unix 平台无导出 |
| **协议封装** | 封装 escalate_protocol、escalate_server、escalate_client 等模块 |
| **类型导出** | 导出所有公共类型供外部使用（core crate） |
| **二进制入口** | 提供 `main_execve_wrapper` 供 `codex-execve-wrapper` 二进制使用 |

---

## 2. 功能点目的

### 2.1 条件编译导出 (`#[cfg(unix)]`)

```rust
#[cfg(unix)]
mod unix;

#[cfg(unix)]
pub use unix::EscalateAction;
// ... 其他导出
```

**目的**: 
- 该 crate 的权限提升机制依赖 Unix 特有的进程间通信机制（Unix Domain Socket、SCM_RIGHTS 文件描述符传递）
- 非 Unix 平台（Windows）使用完全不同的沙箱架构
- 通过条件编译确保跨平台编译不会失败

### 2.2 核心类型导出

| 导出类型 | 来源模块 | 功能目的 |
|----------|----------|----------|
| `EscalateAction` | `escalate_protocol` | 服务端对客户端的响应动作（Run/Escalate/Deny） |
| `EscalateServer` | `escalate_server` | 权限提升服务器，监听并处理 escalation 请求 |
| `EscalationDecision` | `escalate_protocol` | 策略决策结果（Run/Escalate/Deny） |
| `EscalationExecution` | `escalate_protocol` | 提升执行的模式（Unsandboxed/TurnDefault/Permissions） |
| `EscalationPermissions` | `codex_protocol::approvals` | 权限配置（沙箱策略、网络策略等） |
| `EscalationPolicy` | `escalation_policy` | 策略 trait，决定如何处理 escalation 请求 |
| `EscalationSession` | `escalate_server` | 一次 escalation 会话的生命周期管理 |
| `ExecParams` | `escalate_server` | 执行参数（命令、工作目录、超时等） |
| `ExecResult` | `escalate_server` | 执行结果（退出码、输出、耗时等） |
| `Permissions` | `codex_protocol::approvals` | 权限集合（文件系统、网络、macOS seatbelt 扩展） |
| `PreparedExec` | `escalate_server` | 准备好的执行命令配置 |
| `ShellCommandExecutor` | `escalate_server` | 命令执行器 trait，由调用方实现 |
| `Stopwatch` | `stopwatch` | 可暂停的计时器，用于命令超时控制 |
| `ESCALATE_SOCKET_ENV_VAR` | `escalate_protocol` | 环境变量名常量 `CODEX_ESCALATE_SOCKET` |
| `main_execve_wrapper` | `execve_wrapper` | execve wrapper 二进制入口函数 |
| `run_shell_escalation_execve_wrapper` | `escalate_client` | 客户端主逻辑函数 |

---

## 3. 具体技术实现

### 3.1 模块结构

```
codex-rs/shell-escalation/src/
├── lib.rs                    # 公共 API 入口（本文件）
├── bin/
│   └── main_execve_wrapper.rs # codex-execve-wrapper 二进制入口
└── unix/
    ├── mod.rs                # Unix 模块聚合与文档
    ├── escalate_protocol.rs  # 协议消息定义（EscalateRequest/EscalateResponse 等）
    ├── escalate_server.rs    # 服务端实现（EscalateServer、EscalationSession）
    ├── escalate_client.rs    # 客户端实现（run_shell_escalation_execve_wrapper）
    ├── escalation_policy.rs  # 策略 trait 定义（EscalationPolicy）
    ├── execve_wrapper.rs     # execve wrapper CLI 入口
    ├── socket.rs             # 异步 Unix socket 封装（AsyncSocket、AsyncDatagramSocket）
    └── stopwatch.rs          # 可暂停计时器实现
```

### 3.2 关键协议流程

#### 3.2.1 Escalation 流程（权限提升）

```
Command   Server   Shell   Execve Wrapper
          |
          o──────▶o
          │       │
          │       o──(exec)──▶o
          │       │           │
          │o◀──(EscalateReq)──o
          ││      │           │
          │o──(Escalate)─────▶o
          ││      │           │
          │o◀──────────(fds)──o
          ││      │           │
   o◀──────o│      │           │
   │      ││      │           │
   x──────▶o│      │           │
          ││      │           │
          │x──(exit code)────▶o
          │      │           │
          │      o◀──(exit)──x
          │      │
          o◀─────x
```

**流程说明**:
1. **Shell** 通过打补丁的 Bash 拦截 `execve()`，设置 `EXEC_WRAPPER` 环境变量
2. **Execve Wrapper** 被调用，通过 `CODEX_ESCALATE_SOCKET` 连接到 **Server**
3. **Wrapper** 发送 `EscalateRequest`（包含 file、argv、workdir、env）
4. **Server** 根据 `EscalationPolicy` 决定动作：
   - `Run`: 允许在沙箱内直接执行
   - `Escalate`: 需要提升到沙箱外执行
   - `Deny`: 拒绝执行
5. 如决定 `Escalate`，**Wrapper** 发送 `SuperExecMessage` 传递 stdio FD
6. **Server** 在新进程中执行命令，完成后返回 `SuperExecResult`（exit code）

#### 3.2.2 Non-Escalation 流程（直接运行）

```
Server   Shell   Execve Wrapper   Command
  │
  o──────▶o
  │       │
  │       o──(exec)──▶o
  │       │           │
  │o◀──(EscalateReq)──o
  ││      │           │
  │o─(Run)───────────▶o
  │       │           │
  │       │           x──(exec)──▶o
  │       │                       │
  │       o◀──────────────(exit)──x
  │       │
  o◀─────x
```

**流程说明**:
1. **Server** 决定 `Run`，通知 **Wrapper** 直接执行
2. **Wrapper** 调用 `libc::execv()` 执行原始命令
3. 命令在沙箱内运行，exit code 直接返回给 Shell

### 3.3 核心数据结构

#### 3.3.1 EscalateRequest（客户端 → 服务端）

```rust
pub struct EscalateRequest {
    /// 可执行文件路径（可能是相对路径，需要针对 workdir 解析）
    pub file: PathBuf,
    /// 参数向量，包含程序名（argv[0]）
    pub argv: Vec<String>,
    /// 工作目录（绝对路径）
    pub workdir: AbsolutePathBuf,
    /// 环境变量
    pub env: HashMap<String, String>,
}
```

#### 3.3.2 EscalateResponse（服务端 → 客户端）

```rust
pub struct EscalateResponse {
    pub action: EscalateAction,
}

pub enum EscalateAction {
    /// 客户端直接运行命令
    Run,
    /// 客户端应将命令提升到服务端执行
    Escalate,
    /// 命令被拒绝执行
    Deny { reason: Option<String> },
}
```

#### 3.3.3 EscalationDecision（策略决策）

```rust
pub enum EscalationDecision {
    Run,
    Escalate(EscalationExecution),
    Deny { reason: Option<String> },
}

pub enum EscalationExecution {
    /// 在无沙箱 wrapper 的环境中重新运行
    Unsandboxed,
    /// 使用当前 turn 的默认沙箱配置运行
    TurnDefault,
    /// 使用请求中附加的显式沙箱配置运行
    Permissions(EscalationPermissions),
}
```

#### 3.3.4 SuperExecMessage（FD 转发）

```rust
pub struct SuperExecMessage {
    /// 目标文件描述符编号（如 stdin=0, stdout=1, stderr=2）
    pub fds: Vec<RawFd>,
}

pub struct SuperExecResult {
    pub exit_code: i32,
}
```

### 3.4 Socket 通信机制

#### 3.4.1 双 Socket 设计

```rust
// escalate_server.rs
let (escalate_server, escalate_client) = AsyncDatagramSocket::pair()?;
```

**设计原因**:
- **Datagram Socket**: 用于初始握手，传递 stream socket 的 FD
- **Stream Socket**: 用于实际的请求/响应通信，支持并发处理多个 escalation 请求

**并发处理**:
```rust
async fn escalate_task(...) -> anyhow::Result<()> {
    loop {
        // 1. 接收 datagram，获取 stream socket FD
        let (_, mut fds) = socket.receive_with_fds().await?;
        let stream_socket = AsyncSocket::from_fd(fds.remove(0))?;
        
        // 2. 为每个请求 spawn 独立任务
        tokio::spawn(async move {
            handle_escalate_session_with_policy(stream_socket, ...).await
        });
    }
}
```

#### 3.4.2 SCM_RIGHTS 文件描述符传递

```rust
// socket.rs - 发送 FD
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

// 使用 libc::CMSG_SPACE 构造控制消息
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

### 3.5 Stopwatch 实现

**功能**: 可暂停的异步计时器，用于命令执行超时控制

```rust
pub struct Stopwatch {
    limit: Option<Duration>,
    inner: Arc<Mutex<StopwatchState>>,
    notify: Arc<Notify>,
}

struct StopwatchState {
    elapsed: Duration,
    running_since: Option<Instant>,
    active_pauses: u32,  // 支持嵌套暂停
}
```

**关键特性**:
- **暂停/恢复**: `pause_for()` 方法支持嵌套暂停（引用计数）
- **取消令牌**: `cancellation_token()` 返回 `CancellationToken`，超时后自动触发
- **无限制模式**: `Stopwatch::unlimited()` 创建永不超时的计时器

---

## 4. 关键代码路径与文件引用

### 4.1 调用链（从 Codex CLI 到执行）

```
codex-rs/core/src/tools/runtimes/shell/unix_escalation.rs
├── try_run_zsh_fork()
│   ├── 创建 CoreShellActionProvider (EscalationPolicy 实现)
│   ├── 创建 CoreShellCommandExecutor (ShellCommandExecutor 实现)
│   ├── 创建 EscalateServer
│   │   └── codex-rs/shell-escalation/src/unix/escalate_server.rs
│   └── 调用 escalate_server.exec()
│       ├── start_session()
│       │   ├── AsyncDatagramSocket::pair()  [socket.rs]
│       │   ├── spawn escalate_task()        [escalate_server.rs]
│       │   └── 返回 EscalationSession
│       └── command_executor.run()
│           └── 实际执行 shell 命令
│
└── CoreShellActionProvider::determine_action() (EscalationPolicy)
    ├── 检查 execve_session_approvals 缓存
    ├── 匹配 skill 脚本
    ├── 评估 exec policy
    └── 返回 EscalationDecision

codex-rs/arg0/src/lib.rs
└── arg0_dispatch()
    └── 如果 argv[0] == "codex-execve-wrapper"
        └── 调用 codex_shell_escalation::run_shell_escalation_execve_wrapper()
            └── codex-rs/shell-escalation/src/unix/escalate_client.rs
                ├── get_escalate_client()  [连接到 CODEX_ESCALATE_SOCKET]
                ├── 发送 EscalateRequest
                ├── 接收 EscalateResponse
                ├── 根据 action 处理:
                │   ├── Run: 调用 libc::execv()
                │   ├── Escalate: 发送 SuperExecMessage (含 FD)，返回 exit code
                │   └── Deny: 打印错误，返回 1
                └── 返回 exit code
```

### 4.2 关键文件引用

| 文件 | 行数 | 核心功能 |
|------|------|----------|
| `lib.rs` | 35 | 公共 API 导出 |
| `unix/mod.rs` | 78 | 模块聚合、架构文档、ASCII 流程图 |
| `unix/escalate_protocol.rs` | 91 | 协议消息定义、环境变量常量 |
| `unix/escalate_server.rs` | 1071 | EscalateServer、EscalationSession、请求处理逻辑、测试 |
| `unix/escalate_client.rs` | 150 | 客户端实现、FD 转发、execve 调用 |
| `unix/escalation_policy.rs` | 14 | EscalationPolicy trait 定义 |
| `unix/execve_wrapper.rs` | 25 | CLI 入口、参数解析 |
| `unix/socket.rs` | 519 | AsyncSocket、AsyncDatagramSocket、SCM_RIGHTS 实现、测试 |
| `unix/stopwatch.rs` | 237 | Stopwatch、可暂停计时器、测试 |
| `bin/main_execve_wrapper.rs` | 8 | 二进制入口、平台检查 |

### 4.3 环境变量

| 变量名 | 定义位置 | 用途 |
|--------|----------|------|
| `CODEX_ESCALATE_SOCKET` | `escalate_protocol.rs:11` | 客户端通过此 FD 连接服务端 |
| `EXEC_WRAPPER` | `escalate_protocol.rs:14` | 指定 execve wrapper 可执行文件路径 |
| `BASH_EXEC_WRAPPER` | `escalate_protocol.rs:17` | 旧版 Bash 补丁兼容别名 |

---

## 5. 依赖与外部交互

### 5.1 Crate 依赖

```toml
[dependencies]
anyhow = { workspace = true }                    # 错误处理
async-trait = { workspace = true }               # 异步 trait
codex-protocol = { workspace = true }            # 协议类型（EscalationPermissions 等）
codex-utils-absolute-path = { workspace = true } # 绝对路径工具
libc = { workspace = true }                      # Unix 系统调用
serde = { workspace = true }                     # 序列化
serde_json = { workspace = true }                # JSON 处理
socket2 = { workspace = true }                   # 底层 socket API
tokio = { workspace = true }                     # 异步运行时
tokio-util = { workspace = true }                # CancellationToken
tracing = { workspace = true }                   # 日志追踪
```

### 5.2 外部调用方

| 调用方 | 文件 | 使用方式 |
|--------|------|----------|
| `codex-core` | `core/src/tools/runtimes/shell/unix_escalation.rs` | 实现 `EscalationPolicy` 和 `ShellCommandExecutor`，创建 `EscalateServer` |
| `codex-arg0` | `arg0/src/lib.rs:74` | 通过 `arg0_dispatch()` 调用 `run_shell_escalation_execve_wrapper()` |

### 5.3 系统依赖

- **Bash 补丁**: 需要打补丁的 Bash 支持 `EXEC_WRAPPER` 环境变量
- **Unix Domain Socket**: 依赖 `AF_UNIX` socket 家族
- **SCM_RIGHTS**: 依赖 Linux/macOS 的 `SCM_RIGHTS` 控制消息传递 FD

---

## 6. 风险、边界与改进建议

### 6.1 安全风险

| 风险点 | 严重程度 | 说明 |
|--------|----------|------|
| **FD 泄漏** | 中 | `escalate_client.rs:21` 有 TODO 注释：应防御性地限制只调用一次 `get_escalate_client()`，因为 `AsyncSocket` 会获取 FD 所有权 |
| **竞态条件** | 中 | `escalate_server.rs:196` 设置 `CLOEXEC=false` 后，FD 在子进程中可见，需要确保及时关闭 |
| **信号转发缺失** | 低 | `escalate_client.rs:85` 有 TODO：需要转发信号到 super-exec socket |
| **不安全代码** | 中 | `escalate_server.rs:345-352` 使用 `unsafe { command.pre_exec(...) }` 进行 FD dup2 操作 |

### 6.2 边界条件

| 边界 | 处理 | 位置 |
|------|------|------|
| **最大 FD 数** | 每消息最多 16 个 FD | `socket.rs:19` |
| **最大消息大小** | Datagram 最大 8192 字节 | `socket.rs:21` |
| **消息长度** | 使用 u32 编码，最大 4GB | `socket.rs:196-204` |
| **超时控制** | 通过 Stopwatch 实现可暂停计时 | `stopwatch.rs` |

### 6.3 平台限制

- **仅 Unix**: Windows 平台完全不可用
- **macOS 特殊处理**: `socket.rs:269` 使用 `pair_raw()` 避免 `SO_NOSIGPIPE` 副作用
- **Linux 特殊处理**: 同上

### 6.4 改进建议

#### 6.4.1 安全性改进

1. **FD 所有权追踪**
   ```rust
   // 当前: TODO 注释提醒
   // 建议: 使用 std::sync::Once 或原子标志确保单例调用
   ```

2. **信号转发实现**
   ```rust
   // escalate_client.rs:85 TODO
   // 建议: 在 SuperExecMessage 后添加信号转发循环
   ```

3. **更严格的 FD 验证**
   ```rust
   // 当前: 仅检查 fds.len() == msg.fds.len()
   // 建议: 验证接收的 FD 是否有效（fcntl F_GETFD）
   ```

#### 6.4.2 可维护性改进

1. **协议版本协商**
   - 当前协议无版本号，未来扩展可能破坏兼容性
   - 建议在 `EscalateRequest` 中添加 `protocol_version` 字段

2. **错误码标准化**
   - 当前使用 `anyhow::Result`，错误信息不透明
   - 建议定义专门的错误枚举，便于调用方处理

3. **指标与可观测性**
   - 添加 `tracing` span 跟踪每个 escalation 请求的完整生命周期
   - 记录决策来源（skill、prefix rule、fallback）的指标

#### 6.4.3 性能改进

1. **连接池化**
   - 当前每次 exec 都创建新的 datagram socket pair
   - 考虑对频繁执行的命令复用连接

2. **零拷贝优化**
   - 当前使用 `serde_json` 序列化，有内存分配
   - 考虑使用 `rkyv` 或 `flatbuffers` 进行零拷贝序列化

### 6.5 测试覆盖

| 测试类型 | 覆盖情况 | 位置 |
|----------|----------|------|
| 单元测试 | 良好 | `escalate_server.rs` (382-1071 行)、`socket.rs` (408-519 行)、`stopwatch.rs` (131-237 行)、`escalate_client.rs` (132-150 行) |
| 集成测试 | 部分 | `core/tests/common/zsh_fork.rs` |
| 并发测试 | 有 | `escalate_server.rs` 使用 `ESCALATE_SERVER_TEST_LOCK` 串行化测试 |

**测试缺口**:
- 无跨进程 FD 传递的模糊测试
- 无大负载（>8KB）消息的压力测试
- 无网络分区/超时场景的混沌测试

---

## 7. 总结

`codex-rs/shell-escalation/src/lib.rs` 是一个设计精良的 Unix 平台权限提升机制入口，通过清晰的模块划分和类型导出，为 Codex CLI 提供了安全的 shell 命令执行控制能力。

**核心设计亮点**:
1. **双 Socket 架构**: Datagram 用于握手，Stream 用于通信，支持并发
2. **SCM_RIGHTS FD 传递**: 精确的 stdio 转发，保持命令执行的透明性
3. **策略模式**: `EscalationPolicy` trait 允许调用方自定义决策逻辑
4. **可暂停计时器**: `Stopwatch` 解决了超时与暂停的复杂交互

**主要关注点**:
1. **平台限制**: 仅 Unix，Windows 需完全不同的实现
2. **安全风险**: FD 管理、竞态条件需要仔细审查
3. **维护成本**: 协议无版本号，未来扩展需谨慎
