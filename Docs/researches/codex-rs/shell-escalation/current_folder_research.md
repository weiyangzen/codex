# codex-rs/shell-escalation 深度研究文档

## 1. 场景与职责

### 1.1 核心定位

`shell-escalation` crate 是 Codex CLI 的 **Unix 平台专用** 模块，实现了一种创新的**进程执行拦截与权限升级协议**。其核心使命是：

1. **透明拦截**：通过 patched shell（Bash/Zsh）拦截子进程的 `execve(2)` 系统调用
2. **动态决策**：将执行决策委托给 Rust 服务端，根据策略决定允许/拒绝/升级执行
3. **安全沙箱**：支持在保持沙箱限制的同时，按需将特定命令提升到更高权限或完全无沙箱环境执行

### 1.2 解决的问题

| 问题 | 解决方案 |
|------|---------|
| shell 命令执行前无法确定实际二进制路径（受 PATH/alias/function 影响） | 在 `execve()` 拦截点获取已解析的绝对路径 |
| 沙箱内执行需要特权命令（如 `sudo`、`docker`） | 支持将特定命令升级到沙箱外执行 |
| 细粒度命令管控 | 基于 `.rules` 文件的策略引擎，支持 `allow`/`prompt`/`forbidden` 决策 |
| 子进程逃逸风险 | 通过 FD 传递和进程隔离确保 wrapper 无法直接访问父进程资源 |

### 1.3 典型使用场景

- **Skill 脚本执行**：识别并允许项目特定脚本在受控权限下运行
- **受信任命令升级**：如 `git`、`npm` 等已知安全命令可配置为自动升级到无沙箱执行
- **敏感命令拦截**：如 `rm -rf /` 或未知二进制可配置为拒绝或提示用户

---

## 2. 功能点目的

### 2.1 核心组件功能

| 组件 | 功能目的 |
|------|---------|
| `codex-execve-wrapper` | 可执行文件，被 patched shell 调用作为 exec wrapper，负责与 escalation server 通信 |
| `EscalateServer` | 服务端核心，监听 escalation 请求，执行策略决策 |
| `EscalationPolicy` trait | 策略抽象，由 `CoreShellActionProvider` 实现，集成 execpolicy 引擎 |
| `ShellCommandExecutor` trait | 命令执行抽象，由 `CoreShellCommandExecutor` 实现，集成沙箱系统 |
| `Stopwatch` | 可暂停的计时器，支持在 approval 等待期间暂停超时计数 |

### 2.2 决策类型

```rust
pub enum EscalationDecision {
    Run,           // 在沙箱内直接执行
    Escalate(EscalationExecution),  // 升级到特定权限环境执行
    Deny { reason }, // 拒绝执行
}

pub enum EscalationExecution {
    Unsandboxed,   // 完全无沙箱
    TurnDefault,   // 使用当前 turn 的默认沙箱配置
    Permissions(EscalationPermissions), // 使用特定权限配置
}
```

### 2.3 环境变量协议

| 变量 | 用途 |
|------|------|
| `CODEX_ESCALATE_SOCKET` | Datagram socket FD，用于初始握手 |
| `EXEC_WRAPPER` | 指向 `codex-execve-wrapper` 可执行文件路径 |
| `BASH_EXEC_WRAPPER` | 兼容旧版 patched bash 的别名 |

---

## 3. 具体技术实现

### 3.1 协议流程

#### 3.1.1 Escalation Flow（升级执行）

```
Command  Server  Shell  Execve Wrapper
         |
         o----->o                    # Server 启动 Shell，设置 EXEC_WRAPPER 环境变量
         |      |
         |      o--(exec)-->o        # Shell 执行命令，触发 wrapper
         |      |           |
         |o<-(EscalateReq)--o        # Wrapper 发送 EscalateRequest（含新 socket pair 的 server FD）
         ||     |           |
         |o--(Escalate)---->o        # Server 决定升级，发送 Escalate 响应
         ||     |           |
         |o<---------(fds)--o        # Wrapper 发送 stdio FDs（stdin/stdout/stderr）
         ||     |           |
  o<------o     |           |        # Server 在新进程中执行目标命令，继承 wrapper 的 stdio
  |      ||     |           |
  x------>o     |           |        # 命令执行完成
         ||     |           |
         |x--(exit code)--->o        # Server 将 exit code 返回给 wrapper
         |      |           |
         |      o<--(exit)--x        # Wrapper 以接收到的 exit code 退出
         |      |
         o<-----x                       # Shell 等待 wrapper 完成
```

#### 3.1.2 Non-escalation Flow（沙箱内执行）

```
Server  Shell  Execve Wrapper  Command
  |
  o----->o
  |      |
  |      o--(exec)-->o
  |      |           |
  |o<-(EscalateReq)--o
  ||     |           |
  |o-(Run)---------->o           # Server 决定不升级，发送 Run 响应
  |      |           |
  |      |           x--(exec)-->o   # Wrapper 直接 execve 到目标命令
  |      |                       |
  |      o<--------------(exit)--x   # 命令在沙箱内完成
  |      |
  o<-----x
```

### 3.2 关键数据结构

#### 3.2.1 协议消息（escalate_protocol.rs）

```rust
// Client -> Server: 请求执行决策
pub struct EscalateRequest {
    pub file: PathBuf,           // 可执行文件路径（可能相对）
    pub argv: Vec<String>,       // 参数列表（含 argv[0]）
    pub workdir: AbsolutePathBuf, // 当前工作目录
    pub env: HashMap<String, String>, // 环境变量
}

// Server -> Client: 执行决策
pub struct EscalateResponse {
    pub action: EscalateAction,
}

pub enum EscalateAction {
    Run,                    // 直接执行
    Escalate,               // 升级执行（需后续 FD 传递）
    Deny { reason },        // 拒绝执行
}

// Client -> Server: 传递 stdio FDs（仅 Escalate 路径）
pub struct SuperExecMessage {
    pub fds: Vec<RawFd>,     // 目标 FD 编号（0=stdin, 1=stdout, 2=stderr）
}

// Server -> Client: 执行结果
pub struct SuperExecResult {
    pub exit_code: i32,
}
```

#### 3.2.2 服务端核心结构（escalate_server.rs）

```rust
pub struct EscalateServer {
    bash_path: PathBuf,           // Shell 可执行文件路径
    execve_wrapper: PathBuf,      // wrapper 可执行文件路径
    policy: Arc<dyn EscalationPolicy>, // 策略引擎
}

pub struct EscalationSession {
    env: HashMap<String, String>, // 需要注入到 Shell 的环境变量
    task: JoinHandle<...>,        // 服务端监听任务
    client_socket: Arc<Mutex<Option<Socket>>>, // escalation socket
    cancellation_token: CancellationToken,
}
```

### 3.3 Socket 通信实现

#### 3.3.1 双阶段 Socket 设计

| 阶段 | Socket 类型 | 用途 |
|------|------------|------|
| 握手阶段 | `SOCK_DGRAM` (Unix domain) | 通过 `CODEX_ESCALATE_SOCKET` 传递新的 stream socket FD |
| 通信阶段 | `SOCK_STREAM` (Unix domain) | 传输 JSON 消息和 SCM_RIGHTS FDs |

#### 3.3.2 FD 传递机制（socket.rs）

```rust
// 发送带 FD 的消息
pub async fn send_with_fds<T: Serialize>(
    &self,
    msg: T,
    fds: &[OwnedFd],
) -> std::io::Result<()>

// 接收带 FD 的消息
pub async fn receive_with_fds<T: Deserialize<'de>>(
    &self,
) -> std::io::Result<(T, Vec<OwnedFd>)>
```

使用 `SCM_RIGHTS` 控制消息在 Unix domain socket 上传递文件描述符，允许子进程继承父进程的 stdio。

### 3.4 Patched Shell 集成

#### 3.4.1 Bash Patch（shell-tool-mcp/patches/bash-exec-wrapper.patch）

```c
// 在 shell_execve() 函数中插入
char* exec_wrapper = getenv("EXEC_WRAPPER");
if (exec_wrapper && *exec_wrapper && !whitespace (*exec_wrapper))
{
    // 将原命令包装为：exec_wrapper <original_command> <original_args>
    char *orig_command = command;
    larray = strvec_len (args);
    memmove (args + 2, args, (++larray) * sizeof (char *));
    args[0] = exec_wrapper;
    args[1] = orig_command;
    command = exec_wrapper;
}
```

#### 3.4.2 Zsh Patch（shell-tool-mcp/patches/zsh-exec-wrapper.patch）

类似逻辑在 `zexecve()` 函数中实现，通过检查 `EXEC_WRAPPER` 环境变量决定是否拦截。

### 3.5 策略引擎集成

#### 3.5.1 CoreShellActionProvider（unix_escalation.rs）

```rust
struct CoreShellActionProvider {
    policy: Arc<RwLock<Policy>>,           // execpolicy 规则引擎
    session: Arc<Session>,
    turn: Arc<TurnContext>,
    call_id: String,
    approval_policy: AskForApproval,       // 用户审批策略
    sandbox_policy: SandboxPolicy,
    // ... 其他沙箱配置
    stopwatch: Stopwatch,                  // 可暂停的超时计时器
}
```

#### 3.5.2 决策流程

1. **Session Approval 检查**：检查该程序是否已在当前 session 中被批准
2. **Skill 匹配**：检查是否属于项目 skill 脚本
3. **Execpolicy 评估**：使用 `codex_execpolicy` crate 评估规则
4. **用户提示**：根据策略决定是否需要用户确认
5. **权限映射**：将决策映射到 `EscalationExecution` 类型

---

## 4. 关键代码路径与文件引用

### 4.1 Crate 结构

```
codex-rs/shell-escalation/
├── Cargo.toml                    # 定义 codex-execve-wrapper bin
├── src/
│   ├── lib.rs                   # 模块导出
│   ├── bin/
│   │   └── main_execve_wrapper.rs  # wrapper 入口
│   └── unix/
│       ├── mod.rs               # 模块组织与文档
│       ├── escalate_client.rs   # wrapper 客户端逻辑
│       ├── escalate_server.rs   # 服务端核心实现
│       ├── escalate_protocol.rs # 协议消息定义
│       ├── escalation_policy.rs # EscalationPolicy trait
│       ├── execve_wrapper.rs    # CLI 解析
│       ├── socket.rs            # 异步 socket 工具
│       └── stopwatch.rs         # 可暂停计时器
```

### 4.2 关键代码路径

| 路径 | 功能 | 关键行号 |
|------|------|---------|
| `src/unix/escalate_client.rs:37` | `run_shell_escalation_execve_wrapper()` - wrapper 主逻辑 | 37-130 |
| `src/unix/escalate_server.rs:146` | `EscalateServer::exec()` - 执行 shell 命令 | 146-179 |
| `src/unix/escalate_server.rs:186` | `EscalateServer::start_session()` - 启动 escalation session | 186-224 |
| `src/unix/escalate_server.rs:227` | `escalate_task()` - 监听并处理 escalation 请求 | 227-263 |
| `src/unix/escalate_server.rs:265` | `handle_escalate_session_with_policy()` - 单 session 处理 | 265-380 |
| `src/unix/socket.rs:247` | `AsyncSocket` - stream socket 封装 | 247-313 |
| `src/unix/socket.rs:362` | `AsyncDatagramSocket` - datagram socket 封装 | 362-406 |

### 4.3 调用方代码路径

| 路径 | 功能 |
|------|------|
| `codex-rs/core/src/tools/runtimes/shell/unix_escalation.rs:90` | `try_run_zsh_fork()` - shell 工具入口 |
| `codex-rs/core/src/tools/runtimes/shell/zsh_fork_backend.rs:74` | `maybe_run_shell_command()` - 后端路由 |
| `codex-rs/arg0/src/lib.rs:57` | `arg0_dispatch()` - 通过 argv[0] 分发到 wrapper |

### 4.4 测试代码

| 路径 | 功能 |
|------|------|
| `codex-rs/shell-escalation/src/unix/escalate_server.rs:382` | 单元测试（start_session, exec, handle_escalate_session） |
| `codex-rs/shell-escalation/src/unix/socket.rs:408` | Socket 通信测试 |
| `codex-rs/core/tests/common/zsh_fork.rs` | 集成测试辅助函数 |
| `codex-rs/app-server/tests/suite/v2/turn_start_zsh_fork.rs` | 端到端 MCP 测试 |

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| Crate | 用途 |
|-------|------|
| `codex-protocol` | `EscalationPermissions`、`Permissions` 类型定义（src/approvals.rs） |
| `codex-utils-absolute-path` | `AbsolutePathBuf` 路径处理 |
| `codex-execpolicy` | 策略规则引擎（Decision, Policy, RuleMatch 等） |
| `codex-shell-command` | Shell 命令解析 |
| `arg0` | 通过 argv[0] 分发到 wrapper 执行 |

### 5.2 外部依赖

| Crate | 用途 |
|-------|------|
| `tokio` | 异步运行时，features: io-std, net, process, rt-multi-thread, signal, time |
| `socket2` | 底层 socket 操作，SCM_RIGHTS FD 传递 |
| `libc` | 系统调用（dup2, execve, fcntl 等） |
| `serde`/`serde_json` | 协议序列化 |
| `tokio-util` | `CancellationToken` |
| `tracing` | 日志追踪 |

### 5.3 外部系统依赖

| 组件 | 用途 |
|------|------|
| Patched Bash/Zsh | 支持 `EXEC_WRAPPER` 环境变量的 shell 二进制 |
| `codex-execve-wrapper` | 作为独立可执行文件部署，通过 PATH 或 argv[0] 调用 |

### 5.4 配置集成

```rust
// codex-rs/core/src/config/mod.rs
pub struct Config {
    pub zsh_path: Option<PathBuf>,                    // patched zsh 路径
    pub main_execve_wrapper_exe: Option<PathBuf>,     // wrapper 可执行文件路径
    // ...
}
```

通过 `arg0` crate 的 `prepend_path_entry_for_codex_aliases()` 自动创建 wrapper 的符号链接到临时目录并加入 PATH。

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 安全风险

| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| FD 泄漏 | 传递的 FD 可能被恶意利用 | 使用 `CLOEXEC` 标志，session 结束后关闭 socket |
| 竞争条件 | 多并发 escalation 请求可能冲突 | 每请求创建独立 stream socket |
| 策略绕过 | 未 patched 的 shell 直接执行命令 | 仅支持通过 Codex 启动的 patched shell |
| 拒绝服务 | 大量 escalation 请求耗尽资源 | 使用 `CancellationToken` 和超时机制 |

#### 6.1.2 兼容性风险

| 风险 | 描述 |
|------|------|
| 平台限制 | 仅 Unix 平台支持（依赖 Unix domain socket 和 SCM_RIGHTS） |
| Shell 版本 | 需要特定版本的 patched Bash/Zsh |
| macOS 差异 | SCM_RIGHTS 行为在 macOS 上可能有细微差异（代码中有特殊处理） |

### 6.2 边界条件

| 边界 | 处理 |
|------|------|
| 最大 FD 数 | `MAX_FDS_PER_MESSAGE = 16`，超出返回错误 |
| 消息大小 | 最大 4GB（u32 长度前缀），实际受 8KB datagram 限制 |
| 超时处理 | `Stopwatch` 支持暂停，但 escalation 执行期间不计入超时 |
| 相对路径 | 在 server 端根据 `workdir` 解析为绝对路径 |

### 6.3 改进建议

#### 6.3.1 架构改进

1. **Windows 支持**：考虑使用命名管道或本地 RPC 实现类似机制
2. **协议版本化**：当前协议无版本字段，未来升级困难
3. **指标收集**：增加 escalation 请求数、决策分布、延迟等指标
4. **缓存优化**：策略评估结果可缓存以避免重复计算

#### 6.3.2 代码改进

1. **错误处理**：部分错误场景仅打印日志，可考虑更严格的错误传播
2. **测试覆盖**：增加更多边界条件测试（如 FD 耗尽、超大消息）
3. **文档完善**：协议文档可更详细，便于第三方实现

#### 6.3.3 安全加固

1. **FD 验证**：接收 FD 后验证其类型（是否真的是 pipe/terminal）
2. **沙箱逃逸检测**：监控 escalated 进程的行为
3. **审计日志**：记录所有 escalation 决策和执行结果

### 6.4 相关配置项

| 配置项 | 类型 | 说明 |
|--------|------|------|
| `features.ShellZshFork` | bool | 启用 zsh-fork 后端 |
| `zsh_path` | PathBuf | patched zsh 可执行文件路径 |
| `main_execve_wrapper_exe` | PathBuf | wrapper 可执行文件路径 |
| `permissions.approval_policy` | AskForApproval | 审批策略 |
| `permissions.sandbox_policy` | SandboxPolicy | 默认沙箱策略 |

---

## 7. 总结

`shell-escalation` crate 是 Codex CLI 安全架构的核心组件，通过创新的 execve 拦截协议，实现了：

1. **精确的执行时控制**：在 `execve()` 点拦截，获知确切的二进制路径
2. **灵活的权限升级**：支持从完全沙箱到无沙箱的多级执行环境
3. **无缝的用户体验**：用户可在执行前审批，且审批等待期间不消耗超时
4. **可扩展的策略引擎**：集成 execpolicy，支持 `.rules` 文件定义策略

该机制目前仅在 Unix 平台实现，是 Codex 区别于传统 shell 工具的关键安全特性。
