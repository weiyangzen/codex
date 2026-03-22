# codex-rs/shell-escalation/src/bin 研究文档

## 概述

本目录包含 `codex-execve-wrapper` 可执行文件的入口点，这是 Codex 项目中用于 Unix 平台 Shell 权限提升机制的核心组件。该二进制文件作为 execve 系统调用的拦截包装器，与 shell-escalation 协议配合实现细粒度的命令执行控制。

---

## 场景与职责

### 核心场景

`codex-execve-wrapper` 解决以下关键场景：

1. **execve 拦截与委托**：当 patched shell（如打了补丁的 zsh/bash）准备执行命令时，通过 `EXEC_WRAPPER` 环境变量将 execve 调用委托给本包装器
2. **权限提升决策**：包装器通过 Unix Domain Socket 与 Codex 主进程通信，由策略引擎决定命令的执行方式
3. **沙箱边界控制**：支持在沙箱内执行、提升到沙箱外执行、或拒绝执行三种决策路径

### 架构定位

```
┌─────────────────┐     ┌─────────────────────┐     ┌─────────────────┐
│   Patched Shell │────▶│ codex-execve-wrapper│────▶│  EscalateServer │
│   (zsh/bash)    │     │   (本二进制文件)     │     │  (Codex 核心)   │
└─────────────────┘     └─────────────────────┘     └─────────────────┘
        │                        │                           │
        │                        │                           │
        ▼                        ▼                           ▼
   触发 execve()           发送 EscalateRequest         执行策略决策
   设置 EXEC_WRAPPER       通过 CODEX_ESCALATE_SOCKET    Run/Escalate/Deny
```

---

## 功能点目的

### 1. 跨平台入口 (`main_execve_wrapper.rs`)

**文件**: `codex-rs/shell-escalation/src/bin/main_execve_wrapper.rs`

```rust
#[cfg(not(unix))]
fn main() {
    eprintln!("codex-execve-wrapper is only implemented for UNIX");
    std::process::exit(1);
}

#[cfg(unix)]
pub use codex_shell_escalation::main_execve_wrapper as main;
```

**目的**：
- 提供非 Unix 平台的友好错误提示
- Unix 平台直接委托给库中的 `main_execve_wrapper` 实现
- 保持二进制入口点的简洁性

### 2. CLI 参数解析 (`execve_wrapper.rs`)

**文件**: `codex-rs/shell-escalation/src/unix/execve_wrapper.rs`

```rust
#[derive(Parser)]
pub struct ExecveWrapperCli {
    file: String,           // 要执行的文件路径
    #[arg(trailing_var_arg = true)]
    argv: Vec<String>,      // 参数列表（包含 argv[0]）
}
```

**目的**：
- 使用 `clap` 解析被拦截的 execve 参数
- `trailing_var_arg` 捕获所有剩余参数作为 argv

### 3. 权限提升协议客户端 (`escalate_client.rs`)

**核心函数**: `run_shell_escalation_execve_wrapper`

**目的**：
- 从环境变量 `CODEX_ESCALATE_SOCKET` 获取与服务器通信的 socket fd
- 创建独立的 stream socket 用于接收响应（支持并发请求）
- 发送 `EscalateRequest` 包含：文件路径、参数、工作目录、环境变量
- 根据服务器响应执行三种操作之一：
  - **Run**: 直接调用 `libc::execv` 执行原命令
  - **Escalate**: 转发 stdio fd 给服务器，由服务器执行并返回 exit code
  - **Deny**: 打印错误信息并返回 exit code 1

---

## 具体技术实现

### 关键流程

#### 1. 初始化与握手流程

```rust
// escalate_client.rs: run_shell_escalation_execve_wrapper
pub async fn run_shell_escalation_execve_wrapper(
    file: String,
    argv: Vec<String>,
) -> anyhow::Result<i32> {
    // 1. 从环境变量获取 datagram socket
    let handshake_client = get_escalate_client()?;
    
    // 2. 创建一对 stream socket 用于后续通信
    let (server, client) = AsyncSocket::pair()?;
    
    // 3. 发送握手消息，将 server 端 fd 传递给主进程
    handshake_client.send_with_fds(&HANDSHAKE_MESSAGE, &[server.into_inner().into()]).await?;
    
    // 4. 发送 EscalateRequest
    client.send(EscalateRequest { file, argv, workdir, env }).await?;
    
    // 5. 接收响应并处理
    let message = client.receive::<EscalateResponse>().await?;
    match message.action { ... }
}
```

#### 2. Escalate 流程（权限提升执行）

```rust
EscalateAction::Escalate => {
    // 1. 复制当前进程的 stdio fd（避免转移所有权后无法使用）
    let destination_fds = [stdin().as_raw_fd(), stdout().as_raw_fd(), stderr().as_raw_fd()];
    let fds_to_send = [
        duplicate_fd_for_transfer(stdin(), "stdin")?,
        duplicate_fd_for_transfer(stdout(), "stdout")?,
        duplicate_fd_for_transfer(stderr(), "stderr")?,
    ];
    
    // 2. 发送 stdio fd 给服务器
    client.send_with_fds(SuperExecMessage { fds: destination_fds }, &fds_to_send).await?;
    
    // 3. 等待服务器返回执行结果
    let SuperExecResult { exit_code } = client.receive::<SuperExecResult>().await?;
    Ok(exit_code)
}
```

#### 3. Run 流程（直接执行）

```rust
EscalateAction::Run => {
    // 直接使用 libc::execv 执行，保持最大透明性
    // 避免使用 std::process::Command 的信号掩码和 dup2 操作
    let file = CString::new(file)?;
    let argv_cstrs: Vec<CString> = argv.iter()
        .map(|s| CString::new(s.as_str()))
        .collect::<Result<Vec<_>, _>>()?;
    let mut argv: Vec<*const libc::c_char> = argv_cstrs.iter().map(|s| s.as_ptr()).collect();
    argv.push(std::ptr::null());
    
    unsafe {
        libc::execv(file.as_ptr(), argv.as_ptr());
        Err(std::io::Error::last_os_error().into())
    }
}
```

### 数据结构

#### EscalateRequest（客户端 → 服务器）

```rust
#[derive(Clone, Serialize, Deserialize, Debug, PartialEq, Eq)]
pub struct EscalateRequest {
    pub file: PathBuf,           // 可执行文件路径（可能相对）
    pub argv: Vec<String>,       // 参数列表（含 argv[0]）
    pub workdir: AbsolutePathBuf,// 当前工作目录
    pub env: HashMap<String, String>, // 环境变量
}
```

#### EscalateResponse（服务器 → 客户端）

```rust
#[derive(Clone, Serialize, Deserialize, Debug, PartialEq, Eq)]
pub struct EscalateResponse {
    pub action: EscalateAction,
}

pub enum EscalateAction {
    Run,                    // 客户端直接执行
    Escalate,               // 提升权限，服务器执行
    Deny { reason: Option<String> }, // 拒绝执行
}
```

#### SuperExecMessage（fd 转发）

```rust
pub struct SuperExecMessage {
    pub fds: Vec<RawFd>,     // 目标 fd 编号（如 0, 1, 2）
}

pub struct SuperExecResult {
    pub exit_code: i32,      // 子进程退出码
}
```

### 协议与通信

#### Socket 类型

1. **Datagram Socket** (`AsyncDatagramSocket`):
   - 用于初始握手
   - 通过 `CODEX_ESCALATE_SOCKET` 环境变量传递的 fd
   - 仅用于发送新的 stream socket fd 给服务器

2. **Stream Socket** (`AsyncSocket`):
   - 用于实际的请求/响应通信
   - 每请求创建一对新的 socket
   - 支持发送文件描述符（SCM_RIGHTS）

#### 消息帧格式

```rust
const LENGTH_PREFIX_SIZE: usize = size_of::<u32>();
const MAX_FDS_PER_MESSAGE: usize = 16;

// 帧结构：[4字节长度前缀][JSON 负载]
// 控制消息：SCM_RIGHTS 携带 fd 列表
```

### 关键环境变量

| 环境变量 | 说明 | 来源 |
|---------|------|------|
| `CODEX_ESCALATE_SOCKET` | datagram socket 的 fd 编号 | EscalateServer::start_session |
| `EXEC_WRAPPER` | execve 包装器路径 | EscalateServer::start_session |
| `BASH_EXEC_WRAPPER` | 兼容旧版 bash 的别名 | EscalateServer::start_session |

---

## 关键代码路径与文件引用

### 核心文件结构

```
codex-rs/shell-escalation/
├── src/
│   ├── bin/
│   │   └── main_execve_wrapper.rs    # 二进制入口点
│   ├── unix/
│   │   ├── mod.rs                     # 模块导出
│   │   ├── execve_wrapper.rs          # CLI 解析和主入口
│   │   ├── escalate_client.rs         # 客户端协议实现
│   │   ├── escalate_protocol.rs       # 协议数据结构
│   │   ├── escalate_server.rs         # 服务器端实现
│   │   ├── escalation_policy.rs       # 策略 trait 定义
│   │   ├── socket.rs                  # 异步 socket 封装
│   │   └── stopwatch.rs               # 超时控制
│   └── lib.rs                         # 库入口
├── Cargo.toml                         # 定义 codex-execve-wrapper 二进制
└── README.md                          # 文档说明
```

### 调用链

```
main_execve_wrapper.rs (main)
    └── unix/execve_wrapper.rs::main_execve_wrapper
        └── unix/escalate_client.rs::run_shell_escalation_execve_wrapper
            ├── unix/socket.rs::AsyncDatagramSocket (握手)
            ├── unix/socket.rs::AsyncSocket (通信)
            └── libc::execv (Run 分支) 或 等待 SuperExecResult (Escalate 分支)
```

### 依赖 crate

| Crate | 用途 |
|-------|------|
| `clap` | CLI 参数解析 |
| `tokio` | 异步运行时 |
| `socket2` | 底层 socket 操作 |
| `serde`/`serde_json` | 协议序列化 |
| `libc` | execv 系统调用 |
| `codex-protocol` | 共享协议类型 |
| `codex-utils-absolute-path` | 绝对路径处理 |

---

## 依赖与外部交互

### 上游依赖（调用方）

1. **Patched Shell** (`patches/bash-exec-wrapper.patch`):
   - 修改 bash/zsh 源码，支持 `EXEC_WRAPPER` 环境变量
   - 在 execute_cmd.c 中拦截 execve 调用
   - 将原命令行参数传递给 wrapper

2. **Codex Core** (`codex-rs/core/src/tools/runtimes/shell/`):
   - `unix_escalation.rs`: 实现 `CoreShellActionProvider` 策略
   - `zsh_fork_backend.rs`: 集成到 shell 运行时
   - 创建 `EscalateServer` 并配置环境变量

3. **配置系统**:
   - `main_execve_wrapper_exe`: 配置 wrapper 二进制路径
   - `zsh_path`: patched zsh 可执行路径
   - `features.ShellZshFork`: 功能开关

### 下游依赖（被调用方）

1. **libc::execv**:
   - Run 分支直接调用，保持透明性
   - 不修改信号掩码，不做额外的 fd 操作

2. **Codex EscalateServer**:
   - 监听 datagram socket 接收新连接
   - 处理 EscalateRequest 并返回决策
   - Escalate 分支时执行命令并返回 exit code

### 系统集成

```rust
// 典型集成示例（来自 unix_escalation.rs）
let escalate_server = EscalateServer::new(
    shell_zsh_path.clone(),
    main_execve_wrapper_exe,
    escalation_policy,
);

let exec_result = escalate_server
    .exec(exec_params, cancel_token, Arc::new(command_executor))
    .await?;
```

---

## 风险、边界与改进建议

### 已知风险

1. **fd 泄漏风险**:
   - `get_escalate_client()` 注释提到应防御性限制只调用一次
   - `AsyncSocket` 会取得 fd 所有权，重复调用可能导致问题

2. **环境变量过滤**:
   - 当前过滤 `EXEC_WRAPPER` 等变量时可能遗漏其他内部变量
   - 建议：审计所有需要过滤的内部环境变量

3. **信号处理**:
   - TODO 注释提到需要转发信号到 super-exec socket
   - 当前实现可能无法正确处理子进程信号

4. **大消息限制**:
   - `MAX_DATAGRAM_SIZE = 8192` 可能限制环境变量大小
   - 大量环境变量可能导致消息截断

### 边界情况

1. **并发请求**:
   - 设计支持并发：每请求创建独立 stream socket
   - 但服务器端 `escalate_task` 循环需要正确处理多个并发会话

2. **fd 重叠**:
   - 测试用例 `handle_escalate_session_accepts_received_fds_that_overlap_destinations` 验证
   - SCM_RIGHTS 分配 fd 时可能复用目标 fd 编号（如 stdin=0）

3. **跨 exec 保留**:
   - `client_socket.set_cloexec(false)` 确保 socket 跨 exec 保留
   - 但其他 fd 可能意外泄漏给子进程

4. **平台限制**:
   - 仅支持 Unix 平台（依赖 `SCM_RIGHTS`, `AF_UNIX`）
   - macOS 和 Linux 行为略有差异（如 `SO_NOSIGPIPE` 处理）

### 改进建议

1. **安全性增强**:
   ```rust
   // 建议：添加 fd 验证
   fn validate_fd(fd: RawFd) -> anyhow::Result<()> {
       if fd < 0 || unsafe { libc::fcntl(fd, libc::F_GETFD) } == -1 {
           return Err(anyhow::anyhow!("invalid fd: {}", fd));
       }
       Ok(())
   }
   ```

2. **协议版本控制**:
   - 当前协议无版本号，未来扩展可能破坏兼容性
   - 建议：在 `EscalateRequest` 中添加 `protocol_version` 字段

3. **超时控制**:
   - 当前客户端无显式超时，可能永久阻塞
   - 建议：添加 `tokio::time::timeout` 包装关键操作

4. **错误信息改进**:
   ```rust
   // 当前 Deny 仅返回简单字符串
   // 建议：添加错误码分类
   pub enum DenyReason {
       PolicyForbidden,
       UserDeclined,
       SandboxUnavailable,
       InvalidCommand,
   }
   ```

5. **监控与可观测性**:
   - 添加 metrics：请求延迟、决策分布、错误率
   - 当前仅有 tracing 日志，缺乏结构化指标

6. **测试覆盖**:
   - 当前测试主要覆盖正常路径
   - 建议添加：
     - 恶意输入测试（畸形 JSON、超大消息）
     - 资源耗尽测试（fd 耗尽、内存压力）
     - 并发压力测试

---

## 附录：相关测试

### 单元测试

- `codex-rs/shell-escalation/src/unix/socket.rs`: Socket 通信测试
- `codex-rs/shell-escalation/src/unix/escalate_client.rs`: fd 复制测试
- `codex-rs/shell-escalation/src/unix/escalate_server.rs`: 完整流程测试

### 集成测试

- `codex-rs/core/tests/common/zsh_fork.rs`: zsh fork 测试基础设施
- `codex-rs/app-server/tests/suite/v2/turn_start_zsh_fork.rs`: 端到端测试
  - `turn_start_shell_zsh_fork_executes_command_v2`
  - `turn_start_shell_zsh_fork_exec_approval_decline_v2`
  - `turn_start_shell_zsh_fork_exec_approval_cancel_v2`
  - `turn_start_shell_zsh_fork_subcommand_decline_marks_parent_declined_v2`

---

## 总结

`codex-execve-wrapper` 是 Codex 权限提升机制的关键组件，通过拦截 execve 调用实现了细粒度的命令执行控制。其设计亮点包括：

1. **双 socket 架构**：datagram 用于握手，stream 用于通信，支持并发
2. **fd 传递**：利用 Unix SCM_RIGHTS 实现 stdio 转发
3. **透明执行**：Run 分支直接调用 libc::execv，最小化干扰
4. **策略解耦**：通过 `EscalationPolicy` trait 支持灵活的决策逻辑

该组件与 patched shell 紧密配合，是 Codex 实现安全沙箱和权限管理的核心基础设施。
