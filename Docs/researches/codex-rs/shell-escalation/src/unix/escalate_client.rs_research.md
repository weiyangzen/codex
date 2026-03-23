# escalate_client.rs 研究文档

## 场景与职责

`escalate_client.rs` 是 Unix 平台 shell 权限提升机制的**客户端实现**，负责在 execve 包装器（wrapper）与权限提升服务器之间建立通信通道。当打补丁的 shell 尝试执行命令时，execve 包装器被调用，该模块负责将执行请求发送给服务器，并根据服务器的响应决定是本地执行还是将 stdio 文件描述符传递给服务器进行远程执行。

核心职责：
1. 从环境变量获取权限提升 socket 的文件描述符
2. 与服务器建立专用的流式 socket 连接（每个请求独立）
3. 序列化并发送 `EscalateRequest` 请求
4. 根据服务器的 `EscalateResponse` 决定执行策略
5. 在需要提升权限时，将 stdin/stdout/stderr 的 FD 传递给服务器
6. 接收并返回远程执行的结果（退出码）

## 功能点目的

### 1. 获取权限提升客户端 Socket

```rust
fn get_escalate_client() -> anyhow::Result<AsyncDatagramSocket>
```

- 从环境变量 `CODEX_ESCALATE_SOCKET` 读取 FD 编号
- 验证 FD 有效性（必须 >= 0）
- 将原始 FD 包装为 `AsyncDatagramSocket`
- **注意**：TODO 注释指出应防御性地限制此函数只能调用一次，因为 `AsyncSocket` 会获取 FD 的所有权

### 2. 文件描述符复制

```rust
fn duplicate_fd_for_transfer(fd: impl AsFd, name: &str) -> anyhow::Result<OwnedFd>
```

- 使用 `try_clone_to_owned()` 复制 FD
- 确保在传递 FD 给服务器时不会关闭原始 FD
- 包装错误上下文以便调试

### 3. 主执行流程

```rust
pub async fn run_shell_escalation_execve_wrapper(
    file: String,
    argv: Vec<String>,
) -> anyhow::Result<i32>
```

这是 execve 包装器的核心入口点，完整流程：

1. **Handshake**：通过 datagram socket 发送握手消息，同时传递一个新创建的 stream socket 的服务器端
2. **过滤环境变量**：移除 `ESCALATE_SOCKET_ENV_VAR`、`EXEC_WRAPPER_ENV_VAR`、`LEGACY_BASH_EXEC_WRAPPER_ENV_VAR`
3. **发送请求**：通过 stream socket 发送 `EscalateRequest`，包含程序路径、参数、工作目录、环境变量
4. **处理响应**：根据 `EscalateAction` 枚举决定后续行为

## 具体技术实现

### 协议流程

```
Client (Wrapper)                    Server
     |                                  |
     |---- [0] + FD (stream socket) --->|  (datagram handshake)
     |                                  |
     |---- EscalateRequest ------------>|  (stream socket)
     |                                  |
     |<--- EscalateResponse ------------|  (Run/Escalate/Deny)
     |                                  |
     |  [如果是 Escalate]               |
     |---- SuperExecMessage + FDs ----->|  (传递 stdin/stdout/stderr)
     |                                  |
     |<--- SuperExecResult -------------|  (exit_code)
```

### 三种执行策略

| 策略 | 说明 |
|------|------|
| `Run` | 客户端直接执行命令，使用 `libc::execv` 保持透明性 |
| `Escalate` | 将 stdio FD 传递给服务器，由服务器执行并返回退出码 |
| `Deny` | 拒绝执行，输出错误信息，返回退出码 1 |

### 关键数据结构

```rust
// 请求结构（定义在 escalate_protocol.rs）
EscalateRequest {
    file: PathBuf,           // 可执行文件路径
    argv: Vec<String>,       // 参数列表（含 argv[0]）
    workdir: AbsolutePathBuf,// 工作目录
    env: HashMap<String, String>, // 环境变量
}

// 响应结构
EscalateResponse {
    action: EscalateAction,
}

// 超级执行消息（传递 FD）
SuperExecMessage {
    fds: Vec<RawFd>,  // 目标 FD 编号（0,1,2）
}

SuperExecResult {
    exit_code: i32,
}
```

### 本地执行实现细节

当服务器返回 `Run` 时，客户端使用裸 `libc::execv` 而非 `std::process::Command`：

```rust
use std::ffi::CString;
let file = CString::new(file).context("NUL in file")?;
let argv_cstrs: Vec<CString> = argv
    .iter()
    .map(|s| CString::new(s.as_str()).context("NUL in argv"))
    .collect::<Result<Vec<_>, _>>()?;
let mut argv: Vec<*const libc::c_char> =
    argv_cstrs.iter().map(|s| s.as_ptr()).collect();
argv.push(std::ptr::null());

let err = unsafe {
    libc::execv(file.as_ptr(), argv.as_ptr());
    std::io::Error::last_os_error()
};
```

**原因**：`std::os::unix::process::CommandExt` 的 `.exec()` 会修改信号掩码和 dup2 标准 FD，可能干扰包装器的预期行为。

## 关键代码路径与文件引用

### 本文件内关键行

| 行号 | 内容 | 说明 |
|------|------|------|
| 20-29 | `get_escalate_client` | 获取权限提升 socket |
| 31-35 | `duplicate_fd_for_transfer` | 复制 FD 用于传输 |
| 37-130 | `run_shell_escalation_execve_wrapper` | 主执行流程 |
| 42-46 | handshake | 发送握手消息和 stream socket |
| 48-63 | 过滤环境变量并发送请求 | |
| 69-97 | Escalate 分支 | 传递 FD 并获取结果 |
| 99-121 | Run 分支 | 本地 execv 执行 |
| 122-129 | Deny 分支 | 拒绝执行 |

### 依赖文件

- `escalate_protocol.rs`：协议消息定义、环境变量常量
- `socket.rs`：`AsyncDatagramSocket`、`AsyncSocket` 实现
- `escalate_server.rs`：服务器端处理逻辑

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `anyhow` | 错误处理 |
| `codex_utils_absolute_path::AbsolutePathBuf` | 绝对路径处理 |
| `libc` | `execv` 系统调用 |
| `std::os::fd` | FD 操作（`AsFd`, `AsRawFd`, `OwnedFd`） |

### 环境变量

| 变量名 | 定义位置 | 用途 |
|--------|----------|------|
| `CODEX_ESCALATE_SOCKET` | `escalate_protocol.rs:11` | 权限提升 socket 的 FD |
| `EXEC_WRAPPER` | `escalate_protocol.rs:14` | execve 包装器路径 |
| `BASH_EXEC_WRAPPER` | `escalate_protocol.rs:17` | 兼容旧版 bash 的别名 |

### 调用方

- `execve_wrapper.rs`：`main_execve_wrapper` 调用 `run_shell_escalation_execve_wrapper`
- 打补丁的 shell 通过 `EXEC_WRAPPER` 环境变量指向的二进制文件间接调用

## 风险、边界与改进建议

### 已知风险

1. **FD 泄漏风险**：TODO 注释指出 `get_escalate_client` 应该限制只能调用一次，因为 `AsyncSocket` 会获取 FD 所有权，重复调用可能导致未定义行为

2. **信号转发缺失**：TODO 注释（第 85 行）指出尚未实现信号转发功能：
   ```rust
   // TODO: also forward signals over the super-exec socket
   ```

3. **NUL 字节检查**：使用 `CString::new` 检查参数中的 NUL 字节，如果存在则返回错误

### 边界情况

1. **FD 重叠处理**：服务器端 `handle_escalate_session_with_policy` 中处理了 `src_fd == dst_fd` 的情况（通过 `dup2`）

2. **环境变量过滤**：明确过滤三个内部环境变量，防止子进程继承

3. **大参数支持**：通过 stream socket 的帧协议支持大消息（长度前缀 + payload）

### 改进建议

1. **实现信号转发**：添加信号捕获和转发机制，使远程执行的进程能正确响应终端信号（SIGINT, SIGTERM 等）

2. **防御性编程**：为 `get_escalate_client` 添加调用次数限制，防止重复调用导致的 FD 问题

3. **错误处理细化**：当前 `Deny` 分支只是简单打印到 stderr，可以考虑更结构化的错误报告

4. **超时机制**：客户端层面可以添加请求超时，防止服务器无响应时挂起

### 测试覆盖

文件包含一个单元测试（第 132-150 行）：
- `duplicate_fd_for_transfer_does_not_close_original`：验证 FD 复制不会关闭原始 FD

测试使用 `UnixStream::pair()` 创建测试 socket，验证复制后的 FD 与原始 FD 不同，且丢弃复制后原始 FD 仍然有效。
