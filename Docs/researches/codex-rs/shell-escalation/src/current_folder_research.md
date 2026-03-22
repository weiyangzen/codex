# codex-rs/shell-escalation/src 研究文档

## 概述

`codex-rs/shell-escalation` 是 Codex CLI 的 Unix shell 权限提升（escalation）协议实现。该 crate 提供了一个机制，允许在沙箱中运行的 shell 将特定的 `execve()` 调用提升（escalate）到服务器端执行，从而突破沙箱限制执行需要更高权限的命令。

---

## 场景与职责

### 核心场景

1. **沙箱内 Shell 执行**: 用户在沙箱环境中运行 shell（如 zsh），执行命令时受到沙箱限制
2. **命令拦截与决策**: 通过 patched bash/zsh 的 `EXEC_WRAPPER` 机制拦截 `execve()` 调用
3. **权限提升执行**: 对于需要突破沙箱限制的命令，通过协议将执行提升到服务器端
4. **透明回退**: 对于不需要提升的命令，直接在沙箱内执行

### 职责划分

| 组件 | 职责 |
|------|------|
| `escalate_protocol` | 定义协议数据结构（Request/Response/Action） |
| `escalate_server` | 服务端实现，监听请求、决策、执行提升后的命令 |
| `escalate_client` | 客户端实现（execve wrapper），发送请求、处理响应 |
| `escalation_policy` | 策略 trait 定义，由调用方实现具体决策逻辑 |
| `socket` | Unix domain socket 通信实现（带 FD 传递） |
| `stopwatch` | 可暂停的计时器，用于超时控制 |
| `execve_wrapper` | CLI 入口点定义 |

---

## 功能点目的

### 1. 协议设计 (`escalate_protocol.rs`)

**目的**: 定义客户端（execve wrapper）与服务器之间的通信协议。

**关键类型**:
- `EscalateRequest`: 客户端发送的执行请求，包含 file、argv、workdir、env
- `EscalateResponse`: 服务器响应，包含 `EscalateAction`
- `EscalateAction`: 三种可能的动作
  - `Run`: 直接在沙箱内执行
  - `Escalate`: 提升到服务器端执行
  - `Deny`: 拒绝执行
- `EscalationDecision`: 服务器内部决策枚举（Run/Escalate/Deny）
- `EscalationExecution`: 提升执行时的沙箱配置（Unsandboxed/TurnDefault/Permissions）

**环境变量**:
- `CODEX_ESCALATE_SOCKET`: 继承的 socket FD，用于通信
- `EXEC_WRAPPER` / `BASH_EXEC_WRAPPER`: execve wrapper 可执行文件路径

### 2. 服务器实现 (`escalate_server.rs`)

**目的**: 实现 escalation 服务器，处理客户端请求并执行提升后的命令。

**关键结构**:
- `EscalateServer`: 服务器主结构，包含 bash 路径、execve wrapper 路径、策略
- `EscalationSession`: 会话句柄，包含环境变量覆盖和任务句柄
- `ShellCommandExecutor` (trait): 由调用方实现的命令执行器
- `ExecParams`/`ExecResult`: 执行参数和结果
- `PreparedExec`: 准备好的执行命令

**核心流程**:
1. `start_session()`: 创建 socket pair，返回 `EscalationSession`（包含环境变量）
2. `exec()`: 启动会话，运行 shell 命令，等待完成
3. `escalate_task()`: 后台任务，监听 datagram socket，为每个请求 spawn 处理任务
4. `handle_escalate_session_with_policy()`: 处理单个 escalation 请求

### 3. 客户端实现 (`escalate_client.rs`)

**目的**: 实现 execve wrapper，拦截 execve 调用并与服务器通信。

**核心函数**:
- `run_shell_escalation_execve_wrapper()`: 主入口点
  1. 从环境变量获取 socket FD
  2. 创建新的 socket pair 用于本次请求
  3. 发送 handshake（通过 datagram socket 传递 stream socket FD）
  4. 发送 `EscalateRequest`
  5. 接收 `EscalateResponse`，根据 action 处理:
     - `Run`: 调用 `libc::execv()` 直接执行
     - `Escalate`: 发送 stdio FDs，等待 `SuperExecResult`，返回 exit code
     - `Deny`: 打印错误，返回 exit code 1

### 4. 策略接口 (`escalation_policy.rs`)

**目的**: 定义决策策略 trait，由调用方实现。

```rust
#[async_trait::async_trait]
pub trait EscalationPolicy: Send + Sync {
    async fn determine_action(
        &self,
        file: &AbsolutePathBuf,
        argv: &[String],
        workdir: &AbsolutePathBuf,
    ) -> anyhow::Result<EscalationDecision>;
}
```

### 5. Socket 通信 (`socket.rs`)

**目的**: 实现基于 Unix domain socket 的异步通信，支持 FD 传递（SCM_RIGHTS）。

**关键结构**:
- `AsyncSocket`: 基于 `SOCK_STREAM` 的异步 socket，用于请求/响应
- `AsyncDatagramSocket`: 基于 `SOCK_DGRAM` 的异步 socket，用于 handshake

**协议细节**:
- 帧格式: 4字节长度前缀（little-endian u32）+ JSON payload
- FD 传递: 通过 `SCM_RIGHTS` control message，最多 16 个 FD
- Handshake: 客户端通过 datagram socket 发送 stream socket FD，后续通信使用 stream socket

### 6. 计时器 (`stopwatch.rs`)

**目的**: 提供可暂停/恢复的超时计时器，用于用户交互时暂停计时。

**特性**:
- `Stopwatch::new(limit)`: 创建有限时长的计时器
- `Stopwatch::unlimited()`: 创建无限时长的计时器
- `cancellation_token()`: 获取取消令牌，超时后自动触发
- `pause_for(fut)`: 在 future 执行期间暂停计时（支持嵌套/重叠）

---

## 具体技术实现

### 关键流程

#### Escalation 流程（提升执行）

```
Command  Server  Shell  Execve Wrapper
         |
         o----->o  (启动 shell，设置 EXEC_WRAPPER)
         |      |
         |      o--(exec)-->o  (shell 执行命令，触发 wrapper)
         |      |           |
         |o<-(EscalateReq)--o  (wrapper 发送请求)
         ||     |           |
         |o--(Escalate)---->o  (服务器决策：需要提升)
         ||     |           |
         |o<---------(fds)--o  (wrapper 发送 stdio FDs)
         ||     |           |
  o<------o     |           |  (服务器执行命令，继承 FDs)
  |      ||     |           |
  x------>o     |           |  (命令执行完成)
         ||     |           |
         |x--(exit code)--->o  (服务器返回 exit code)
         |      |           |
         |      o<--(exit)--x  (wrapper 退出，shell 继续)
         |      |
         o<-----x
```

#### Non-Escalation 流程（直接执行）

```
Server  Shell  Execve Wrapper  Command
  |
  o----->o  (启动 shell)
  |      |
  |      o--(exec)-->o  (触发 wrapper)
  |      |           |
  |o<-(EscalateReq)--o  (发送请求)
  ||     |           |
  |o-(Run)---------->o  (服务器决策：直接执行)
  |      |           |
  |      |           x--(exec)-->o  (wrapper exec 到目标命令)
  |      |                       |
  |      o<--------------(exit)--x  (命令完成，返回 shell)
  |      |
  o<-----x
```

### 数据结构

#### EscalateRequest
```rust
pub struct EscalateRequest {
    pub file: PathBuf,        // 可执行文件路径（可能相对）
    pub argv: Vec<String>,    // 参数列表（包含 argv[0]）
    pub workdir: AbsolutePathBuf,  // 工作目录
    pub env: HashMap<String, String>,  // 环境变量
}
```

#### EscalateResponse / EscalateAction
```rust
pub struct EscalateResponse {
    pub action: EscalateAction,
}

pub enum EscalateAction {
    Run,                       // 直接执行
    Escalate,                  // 提升执行
    Deny { reason: Option<String> },  // 拒绝
}
```

#### SuperExecMessage / SuperExecResult
```rust
pub struct SuperExecMessage {
    pub fds: Vec<RawFd>,      // 目标 FD 编号（stdin/stdout/stderr）
}

pub struct SuperExecResult {
    pub exit_code: i32,       // 命令退出码
}
```

### 协议细节

1. **Socket 创建**: 服务器使用 `AsyncDatagramSocket::pair()` 创建 socket pair
2. **FD 继承**: 客户端 socket 设置 `CLOEXEC=false`，允许跨 exec 继承
3. **Handshake**: 每个 escalation 请求通过 datagram socket 发送新的 stream socket FD
4. **并发处理**: 服务器为每个请求 spawn 独立任务，通过独立的 stream socket 通信
5. **FD 传递**: 使用 `SCM_RIGHTS` 传递 stdio FDs，支持重叠 FD 编号（通过 `dup2` 处理）

---

## 关键代码路径与文件引用

### 入口点

| 文件 | 功能 |
|------|------|
| `src/bin/main_execve_wrapper.rs` | `codex-execve-wrapper` 二进制入口 |
| `src/lib.rs` | 模块导出和平台条件编译 |
| `src/unix/mod.rs` | Unix 模块组织和文档 |

### 核心实现

| 文件 | 行数 | 关键内容 |
|------|------|----------|
| `src/unix/escalate_protocol.rs` | 91 | 协议数据结构定义 |
| `src/unix/escalate_server.rs` | 1071 | 服务器实现（含测试） |
| `src/unix/escalate_client.rs` | 150 | 客户端/wrapper 实现 |
| `src/unix/escalation_policy.rs` | 14 | 策略 trait 定义 |
| `src/unix/socket.rs` | 519 | Socket 通信实现（含测试） |
| `src/unix/stopwatch.rs` | 237 | 计时器实现（含测试） |
| `src/unix/execve_wrapper.rs` | 25 | CLI 入口点定义 |

### 关键函数路径

```
# 服务器启动
EscalateServer::new() -> EscalateServer
EscalateServer::start_session() -> EscalationSession
  -> AsyncDatagramSocket::pair()
  -> tokio::spawn(escalate_task())

# 命令执行
EscalateServer::exec()
  -> start_session()
  -> ShellCommandExecutor::run() [调用方实现]
    -> 启动 shell（带 EXEC_WRAPPER 环境变量）

# 请求处理（后台任务）
escalate_task()
  -> socket.receive_with_fds() [等待 handshake]
  -> AsyncSocket::from_fd() [创建 stream socket]
  -> tokio::spawn(handle_escalate_session_with_policy())

handle_escalate_session_with_policy()
  -> socket.receive::<EscalateRequest>()
  -> policy.determine_action() [策略决策]
  -> 根据决策:
       Run -> 发送 EscalateAction::Run
       Escalate -> 发送 EscalateAction::Escalate
         -> socket.receive_with_fds::<SuperExecMessage>()
         -> command_executor.prepare_escalated_exec()
         -> Command::spawn() [带 pre_exec dup2]
         -> child.wait()
         -> socket.send(SuperExecResult)
       Deny -> 发送 EscalateAction::Deny

# 客户端流程
run_shell_escalation_execve_wrapper()
  -> get_escalate_client() [从环境变量获取 socket]
  -> AsyncSocket::pair() [创建请求专用 socket]
  -> handshake_client.send_with_fds() [发送 stream socket FD]
  -> client.send(EscalateRequest)
  -> client.receive::<EscalateResponse>()
  -> 根据 action:
       Run -> libc::execv() [直接执行]
       Escalate -> duplicate_fd_for_transfer()
         -> client.send_with_fds(SuperExecMessage)
         -> client.receive::<SuperExecResult>()
         -> 返回 exit_code
       Deny -> eprintln!() -> 返回 1
```

---

## 依赖与外部交互

### 内部依赖

| Crate | 用途 |
|-------|------|
| `codex-protocol` | `EscalationPermissions`、`Permissions` 类型 |
| `codex-utils-absolute-path` | `AbsolutePathBuf` 路径处理 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `tokio` | 异步运行时、process、signal、time |
| `tokio-util` | `CancellationToken` |
| `socket2` | 底层 socket 操作（FD 传递） |
| `serde`/`serde_json` | 序列化 |
| `libc` | `execv`、`dup2`、`kill` 等系统调用 |
| `async-trait` | 异步 trait |
| `anyhow` | 错误处理 |
| `tracing` | 日志 |
| `clap` | CLI 参数解析 |

### 调用方（核心使用者）

| 文件 | 用途 |
|------|------|
| `codex-rs/core/src/tools/runtimes/shell/unix_escalation.rs` | 核心集成，实现 `ShellCommandExecutor` 和 `EscalationPolicy` |
| `codex-rs/core/src/tools/runtimes/shell/zsh_fork_backend.rs` | ZshFork 后端集成 |
| `codex-rs/arg0/src/lib.rs` | `arg0_dispatch()` 中通过 `codex-execve-wrapper` 别名调用 |

### 配置集成

在 `codex-rs/core/src/config/mod.rs` 中:
```rust
/// Path to the `codex-execve-wrapper` executable.
pub main_execve_wrapper_exe: Option<PathBuf>,
```

在 `codex-rs/core/src/tools/spec.rs` 中:
```rust
pub struct ZshForkConfig {
    pub shell_zsh_path: PathBuf,
    pub main_execve_wrapper_exe: PathBuf,
}
```

---

## 风险、边界与改进建议

### 已知风险

1. **FD 泄漏风险**
   - `escalate_client.rs:21` 有 TODO: 应该防御性地限制 `get_escalate_client()` 只调用一次
   - 当前实现中 `AsyncSocket` 会取得 FD 所有权，重复调用可能导致未定义行为

2. **信号处理不完整**
   - `escalate_client.rs:85` 有 TODO: 需要在 super-exec socket 上转发信号
   - 当前实现不会将客户端信号转发到服务器端执行的命令

3. **macOS 特殊处理**
   - `escalate_server.rs:1013-1022`: 需要保持 server stream guard 存活直到 worker 响应
   - 这是 macOS 特有的行为，可能导致跨平台不一致

4. **并发限制**
   - `socket.rs:19`: 每条消息最多传递 16 个 FDs
   - 虽然对 stdio（3 个 FD）足够，但限制了未来扩展

5. **超时处理**
   - `stopwatch.rs`: 计时器在暂停期间不会累积时间，但依赖于 Tokio 的定时器精度
   - 大量重叠的暂停可能导致计时器任务堆积

### 边界条件

1. **路径解析**
   - `file` 可能是相对路径，需要针对 `workdir` 解析
   - 服务器使用 `AbsolutePathBuf::resolve_path_against_base()` 处理

2. **FD 重叠**
   - `handle_escalate_session_with_policy()` 处理了接收到的 FD 与目标 FD 编号重叠的情况
   - 通过 `pre_exec` 中的 `dup2` 循环处理（`src/unix/escalate_server.rs:346-350`）

3. **环境变量过滤**
   - wrapper 会过滤掉 `ESCALATE_SOCKET_ENV_VAR`、`EXEC_WRAPPER_ENV_VAR`、`LEGACY_BASH_EXEC_WRAPPER_ENV_VAR`
   - 防止这些内部变量泄漏到子进程

4. **取消处理**
   - 服务器监听 `parent_cancellation_token` 和 `session_cancellation_token`
   - 取消时会杀死已启动的子进程（`start_kill()`）

### 改进建议

1. **安全性增强**
   - 实现 `get_escalate_client()` 的单次调用保护（使用 `std::sync::Once` 或原子标志）
   - 添加 FD 传递的校验和或认证机制，防止恶意客户端

2. **功能完善**
   - 实现信号转发机制（SIGINT、SIGTERM 等）
   - 支持更大的环境变量传输（当前受限于 datagram 大小）

3. **性能优化**
   - 考虑使用连接池复用 stream socket，减少 handshake 开销
   - 对于高频命令，可以考虑批量处理或管道化

4. **可观测性**
   - 添加更多 tracing span 和指标（请求延迟、决策分布等）
   - 记录策略决策的详细原因，便于调试

5. **跨平台支持**
   - 当前仅支持 Unix，Windows 支持需要完全不同的机制
   - 考虑抽象出平台无关的接口

6. **测试覆盖**
   - 添加压力测试（并发请求、大量 FD 传递）
   - 添加故障注入测试（网络中断、FD 耗尽）

---

## 附录：测试概览

### 单元测试

| 文件 | 测试数量 | 关键测试 |
|------|----------|----------|
| `escalate_server.rs` | 10+ | `start_session_exposes_wrapper_env_overlay`, `exec_closes_parent_socket_after_shell_spawn`, `dropping_session_aborts_intercept_workers_and_kills_spawned_child` |
| `escalate_client.rs` | 1 | `duplicate_fd_for_transfer_does_not_close_original` |
| `socket.rs` | 7 | `async_socket_round_trips_payload_and_fds`, `async_socket_handles_large_payload`, `receive_fails_when_peer_closes_before_header` |
| `stopwatch.rs` | 5 | `cancellation_receiver_fires_after_limit`, `pause_prevents_timeout_until_resumed`, `overlapping_pauses_only_resume_once` |

### 集成测试

- `codex-rs/core/src/tools/runtimes/shell/unix_escalation_tests.rs`: 841 行，测试 `CoreShellActionProvider` 的策略决策逻辑
- `codex-rs/core/tests/common/zsh_fork.rs`: 共享测试工具

---

*文档生成时间: 2026-03-22*
*基于代码版本: codex-rs/shell-escalation/src/*
