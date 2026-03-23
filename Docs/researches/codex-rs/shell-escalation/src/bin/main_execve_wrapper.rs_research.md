# main_execve_wrapper.rs 深度研究文档

## 文件基本信息

- **文件路径**: `codex-rs/shell-escalation/src/bin/main_execve_wrapper.rs`
- **二进制名称**: `codex-execve-wrapper`
- **所属 Crate**: `codex-shell-escalation`
- **平台支持**: 仅 Unix (Linux/macOS)

---

## 1. 场景与职责

### 1.1 核心定位

`main_execve_wrapper.rs` 是 **Codex Shell Escalation 协议** 的客户端入口点，作为一个独立的可执行二进制文件 (`codex-execve-wrapper`) 部署。它的核心职责是：

1. **拦截 execve 调用**: 通过 patched shell (Bash/Zsh) 的 `EXEC_WRAPPER` 机制，在子进程执行 `execve()` 系统调用前拦截并接管控制流
2. **权限升级协商**: 与 Codex 主进程中的 `EscalateServer` 通过 Unix Domain Socket 通信，决定命令执行策略
3. **透明代理执行**: 根据服务器决策，要么直接执行原命令（沙箱内），要么将文件描述符传递给服务器进行特权执行

### 1.2 部署场景

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Codex CLI 主进程                                │
│  ┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐    │
│  │  EscalateServer │◄───│  escalation      │◄───│  ShellCommandExecutor│   │
│  │  (监听 socket)  │    │  protocol        │    │  (沙箱/特权执行)      │   │
│  └────────┬────────┘    └──────────────────┘    └─────────────────────┘    │
│           │                                                                 │
│           │  CODEX_ESCALATE_SOCKET (Unix Domain Socket)                     │
│           │                                                                 │
└───────────┼─────────────────────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Patched Zsh/Bash 子进程                            │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  用户输入: git status                                                  │
│  │      │                                                                 │
│  │      ▼                                                                 │
│  │  shell_execve() ──► EXEC_WRAPPER 拦截                                  │
│  │      │                                                                 │
│  │      ▼                                                                 │
│  │  codex-execve-wrapper /usr/bin/git git status                          │
│  │      │                                                                 │
│  │      ▼                                                                 │
│  │  通过 CODEX_ESCALATE_SOCKET 发送 EscalateRequest                       │
│  └──────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.3 两种执行路径

| 路径 | 场景 | 行为 |
|------|------|------|
| **Run** (直接执行) | 命令被允许在沙箱内运行 | wrapper 直接调用 `libc::execv()` 执行原命令 |
| **Escalate** (升级执行) | 命令需要特权或特殊沙箱配置 | wrapper 发送文件描述符给服务器，服务器执行后返回 exit code |
| **Deny** (拒绝) | 命令被策略禁止 | wrapper 打印错误信息并返回 exit code 1 |

---

## 2. 功能点目的

### 2.1 跨平台兼容层

```rust
#[cfg(not(unix))]
fn main() {
    eprintln!("codex-execve-wrapper is only implemented for UNIX");
    std::process::exit(1);
}

#[cfg(unix)]
pub use codex_shell_escalation::main_execve_wrapper as main;
```

- **目的**: 明确声明仅支持 Unix 平台，非 Unix 平台编译时提供清晰的错误信息
- **设计**: 使用条件编译 (`cfg`) 在编译期确定平台支持

### 2.2 CLI 参数解析

```rust
#[derive(Parser)]
pub struct ExecveWrapperCli {
    file: String,  // 被拦截的可执行文件路径
    #[arg(trailing_var_arg = true)]
    argv: Vec<String>,  // 参数列表 (包含 argv[0])
}
```

- **目的**: 接收 patched shell 传递的原始 execve 参数
- **关键设计**: 使用 `trailing_var_arg` 捕获所有剩余参数作为 argv

### 2.3 日志初始化

```rust
tracing_subscriber::fmt()
    .with_env_filter(EnvFilter::from_default_env())
    .with_writer(std::io::stderr)
    .with_ansi(false)
    .init();
```

- **目的**: 提供结构化日志输出，便于调试 escalation 流程
- **设计决策**: 
  - 输出到 stderr 避免污染 stdout（可能被重定向）
  - 禁用 ANSI 颜色（兼容非终端环境）
  - 支持 `RUST_LOG` 环境变量控制日志级别

---

## 3. 具体技术实现

### 3.1 核心调用链

```
main_execve_wrapper() 
    └── ExecveWrapperCli::parse() 
        └── run_shell_escalation_execve_wrapper(file, argv)
            ├── get_escalate_client()  [获取 socket 连接]
            ├── AsyncSocket::pair()     [创建请求/响应对]
            ├── 发送 Handshake + stream socket FD
            ├── 发送 EscalateRequest
            ├── 接收 EscalateResponse
            │   ├── Run ──► libc::execv() 直接执行
            │   ├── Escalate ──► 发送 stdio FDs ──► 接收 SuperExecResult
            │   └── Deny ──► eprintln!() ──► exit(1)
```

### 3.2 关键数据结构

#### 3.2.1 EscalateRequest (客户端 → 服务器)

```rust
#[derive(Clone, Serialize, Deserialize, Debug, PartialEq, Eq)]
pub struct EscalateRequest {
    pub file: PathBuf,           // 可执行文件路径（可能相对）
    pub argv: Vec<String>,       // 参数列表（含 argv[0]）
    pub workdir: AbsolutePathBuf,// 当前工作目录（绝对路径）
    pub env: HashMap<String, String>, // 环境变量
}
```

#### 3.2.2 EscalateResponse (服务器 → 客户端)

```rust
#[derive(Clone, Serialize, Deserialize, Debug, PartialEq, Eq)]
pub struct EscalateResponse {
    pub action: EscalateAction,
}

pub enum EscalateAction {
    Run,                      // 直接执行
    Escalate,                 // 需要升级执行
    Deny { reason: Option<String> }, // 拒绝执行
}
```

#### 3.2.3 SuperExecMessage (Escalate 路径)

```rust
pub struct SuperExecMessage {
    pub fds: Vec<RawFd>,  // 目标文件描述符编号 (stdin=0, stdout=1, stderr=2)
}
```

### 3.3 Socket 通信协议

#### 3.3.1 双 Socket 设计

| Socket 类型 | 用途 | 生命周期 |
|------------|------|----------|
| **Datagram Socket** (`CODEX_ESCALATE_SOCKET`) | 初始握手，传递 stream socket FD | 进程级，继承自父进程 |
| **Stream Socket Pair** | 具体请求/响应通信 | 每次 exec 拦截创建新 pair |

#### 3.3.2 通信流程

```
Client (wrapper)                          Server (EscalateServer)
     │                                           │
     │───── Handshake (1 byte + stream FD) ─────►│
     │                                           │
     │◄──────────── 使用 stream socket ──────────│
     │                                           │
     │────────── EscalateRequest ───────────────►│
     │                                           │
     │◄───────── EscalateResponse ───────────────│
     │                                           │
     │  [如果是 Escalate]                        │
     │                                           │
     │────── SuperExecMessage + stdio FDs ──────►│
     │                                           │
     │◄────────── SuperExecResult ───────────────│
```

### 3.4 文件描述符传递 (SCM_RIGHTS)

```rust
// escalate_client.rs
let destination_fds = [
    io::stdin().as_raw_fd(),
    io::stdout().as_raw_fd(),
    io::stderr().as_raw_fd(),
];
let fds_to_send = [
    duplicate_fd_for_transfer(io::stdin(), "stdin")?,
    duplicate_fd_for_transfer(io::stdout(), "stdout")?,
    duplicate_fd_for_transfer(io::stderr(), "stderr")?,
];

client.send_with_fds(
    SuperExecMessage { fds: destination_fds.into_iter().collect() },
    &fds_to_send,
).await?;
```

- **技术**: 使用 Unix Domain Socket 的 `SCM_RIGHTS` 控制消息传递 FD
- **目的**: 让服务器端执行的进程能够接管 wrapper 的标准输入输出
- **注意**: 使用 `dup()` 复制 FD，避免关闭 wrapper 自身的 stdio

### 3.5 Run 路径的直接执行

```rust
EscalateAction::Run => {
    // 避免使用 std::process::Command，保持信号掩码和 FD 的透明性
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
    Err(err.into())
}
```

- **关键决策**: 直接使用 `libc::execv()` 而非 `std::process::Command`
- **原因**: `Command::exec()` 会修改信号掩码和重定向标准 FD，破坏透明性

---

## 4. 关键代码路径与文件引用

### 4.1 调用方 (谁启动 wrapper)

| 调用方 | 方式 | 代码位置 |
|--------|------|----------|
| **Patched Bash/Zsh** | 通过 `EXEC_WRAPPER` 环境变量 | `patches/bash-exec-wrapper.patch` |
| **arg0 dispatch** | 通过 argv[0] 识别 | `codex-rs/arg0/src/lib.rs:57-80` |

#### Patched Shell 拦截逻辑 (bash-exec-wrapper.patch):

```c
char* exec_wrapper = getenv("EXEC_WRAPPER");
if (exec_wrapper && *exec_wrapper && !whitespace (*exec_wrapper))
{
    char *orig_command = command;
    larray = strvec_len (args);
    memmove (args + 2, args, (++larray) * sizeof (char *));
    args[0] = exec_wrapper;    // /path/to/codex-execve-wrapper
    args[1] = orig_command;    // /usr/bin/git
    command = exec_wrapper;
}
execve(command, args, env);
```

### 4.2 被调用方 (wrapper 调用谁)

| 被调用模块 | 功能 | 代码位置 |
|-----------|------|----------|
| `run_shell_escalation_execve_wrapper` | 核心 escalation 逻辑 | `codex-rs/shell-escalation/src/unix/escalate_client.rs:37` |
| `EscalateServer` | 服务器端决策 | `codex-rs/shell-escalation/src/unix/escalate_server.rs` |
| `EscalationPolicy` | 策略判断 trait | `codex-rs/shell-escalation/src/unix/escalation_policy.rs` |

### 4.3 配置文件关联

| 配置项 | 类型 | 代码位置 |
|--------|------|----------|
| `main_execve_wrapper_exe` | `Option<PathBuf>` | `codex-rs/core/src/config/mod.rs:457` |
| `shell_zsh_path` | `Option<PathBuf>` | `codex-rs/core/src/config/mod.rs` |

### 4.4 环境变量

| 变量名 | 用途 | 定义位置 |
|--------|------|----------|
| `CODEX_ESCALATE_SOCKET` | Datagram socket FD 编号 | `codex-rs/shell-escalation/src/unix/escalate_protocol.rs:11` |
| `EXEC_WRAPPER` | Patched shell 使用的 wrapper 路径 | `codex-rs/shell-escalation/src/unix/escalate_protocol.rs:14` |
| `BASH_EXEC_WRAPPER` | 旧版兼容别名 | `codex-rs/shell-escalation/src/unix/escalate_protocol.rs:17` |

---

## 5. 依赖与外部交互

### 5.1 Crate 依赖

```toml
[dependencies]
anyhow = { workspace = true }
async-trait = { workspace = true }
clap = { workspace = true, features = ["derive"] }
codex-protocol = { workspace = true }
codex-utils-absolute-path = { workspace = true }
libc = { workspace = true }
serde = { workspace = true, features = ["derive"] }
serde_json = { workspace = true }
socket2 = { workspace = true, features = ["all"] }
tokio = { workspace = true, features = [...] }
tokio-util = { workspace = true }
tracing = { workspace = true }
tracing-subscriber = { workspace = true, features = ["env-filter", "fmt"] }
```

### 5.2 外部系统依赖

| 依赖 | 用途 |
|------|------|
| **Patched Bash/Zsh** | 必须应用 `bash-exec-wrapper.patch` 或 `zsh-exec-wrapper.patch` 才能拦截 execve |
| **Unix Domain Socket** | 进程间通信机制 |
| **SCM_RIGHTS** | 文件描述符传递的 Unix 特性 |

### 5.3 与 Core 模块的交互

```
┌─────────────────────────────────────────────────────────────┐
│                    codex_core (核心库)                       │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  unix_escalation.rs                                 │   │
│  │  ├── CoreShellActionProvider (EscalationPolicy)     │   │
│  │  ├── CoreShellCommandExecutor (ShellCommandExecutor)│   │
│  │  └── try_run_zsh_fork()                             │   │
│  └─────────────────────────────────────────────────────┘   │
│                          │                                  │
│  ┌───────────────────────┼─────────────────────────────┐   │
│  │                       ▼                             │   │
│  │  EscalateServer::new(shell_path, wrapper_path, policy)│ │
│  │                       │                             │   │
│  │                       ▼                             │   │
│  │  escalate_server.exec(params, cancel_token, executor)│  │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 平台限制

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| Unix Only | 仅支持 Unix 平台，Windows 无法使用 | 条件编译明确拒绝非 Unix 编译 |
| Patched Shell 依赖 | 需要特殊编译的 Bash/Zsh | 通过 DotSlash 分发 patched shell |

#### 6.1.2 安全风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| FD 泄漏 | 文件描述符传递可能存在泄漏 | `duplicate_fd_for_transfer` 使用 `dup()` |
| 环境变量注入 | `CODEX_ESCALATE_SOCKET` 可能被篡改 | 服务器端验证 FD 有效性 |
| TOCTOU 竞争 | 路径解析可能存在竞态 | 使用 `AbsolutePathBuf` 确保绝对路径 |

#### 6.1.3 稳定性风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| Socket 耗尽 | 高并发下 socket 资源耗尽 | 使用 datagram socket 做初始握手，stream socket 做实际通信 |
| 死锁 | 服务器和客户端互相等待 | 超时机制和 cancellation token |

### 6.2 边界条件

#### 6.2.1 测试覆盖

```rust
// escalate_server.rs 中的测试
#[tokio::test]
async fn handle_escalate_session_accepts_received_fds_that_overlap_destinations()
```

- 测试 FD 重叠场景（接收到的 FD 与目标 FD 相同）
- 使用 `RestoredFd` 临时关闭 stdin 来强制 FD 重用

#### 6.2.2 资源限制

| 限制 | 值 | 说明 |
|------|-----|------|
| MAX_FDS_PER_MESSAGE | 16 | 单次消息最多传递的 FD 数量 |
| MAX_DATAGRAM_SIZE | 8192 bytes | 数据报最大大小 |
| 消息长度 | u32 (4GB max) | 序列化消息长度前缀 |

### 6.3 改进建议

#### 6.3.1 短期改进

1. **信号转发**: 当前 TODO 注释提到未实现信号转发
   ```rust
   // TODO: also forward signals over the super-exec socket
   ```

2. **更严格的 FD 验证**: 当前仅检查 FD 数量匹配，可添加 FD 类型验证

3. **错误信息国际化**: 当前错误信息为硬编码英文

#### 6.3.2 中长期改进

1. **平台抽象**: 考虑设计跨平台抽象，Windows 可使用类似机制

2. **性能优化**: 
   - 考虑使用共享内存减少序列化开销
   - 连接池化避免重复创建 socket pair

3. **可观测性**:
   - 添加 metrics 收集 escalation 频率、延迟
   - 结构化日志关联请求/响应

4. **安全加固**:
   - 考虑使用 `SO_PEERCRED` 验证对端身份
   - 添加请求签名防止重放攻击

### 6.4 调试技巧

```bash
# 启用详细日志
RUST_LOG=debug codex-execve-wrapper /usr/bin/echo hello

# 查看 socket 通信
strace -e socket,sendmsg,recvmsg codex-execve-wrapper /usr/bin/echo hello

# 验证 patched shell
EXEC_WRAPPER=/usr/bin/false zsh -fc '/usr/bin/true'
echo $?  # 应该非 0（wrapper 被执行但返回失败）
```

---

## 7. 相关文档链接

- [shell-escalation README](../../../../../codex-rs/shell-escalation/README.md)
- [Bash Patch](../../../../../../patches/bash-exec-wrapper.patch)
- [Zsh Patch](../../../../../../shell-tool-mcp/patches/zsh-exec-wrapper.patch)
- [arg0 dispatch 研究](../../arg0/src/lib.rs_research.md)
- [unix_escalation 研究](../../core/src/tools/runtimes/shell/unix_escalation.rs_research.md)
