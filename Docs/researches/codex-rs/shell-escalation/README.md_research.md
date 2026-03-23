# codex-rs/shell-escalation/README.md 研究文档

## 场景与职责

`README.md` 是 `codex-shell-escalation` crate 的文档入口，描述了该 crate 的核心功能：Unix 平台的 shell-escalation 协议实现和 `codex-execve-wrapper` 可执行文件。该机制允许在沙箱环境中拦截 execve 调用，并根据策略决定是否升级权限执行。

## 功能点目的

### 1. Execve 拦截与升级机制

当 patched shell（如 bash）执行命令时，通过 `EXEC_WRAPPER` 环境变量将 execve 调用委托给 `codex-execve-wrapper`，后者通过 escalation protocol 与 server 通信决定执行策略。

### 2. 三种执行决策

| 决策 | 描述 | 执行流程 |
|------|------|----------|
| **Run** | 直接在沙箱内执行 | wrapper 调用 `execve` 执行原命令 |
| **Escalate** | 升级到 server 端执行 | 转发 FDs，server 执行后返回 exit code |
| **Deny** | 拒绝执行 | 输出错误到 stderr，返回 exit code 1 |

## 具体技术实现

### 协议流程

#### Escalation Flow（升级执行）

```
Command  Server  Shell  Execve Wrapper
         |
         o----->o          # Server 启动 Shell
         |      |
         |      o--(exec)-->o   # Shell 执行命令触发 wrapper
         |      |           |
         |o<-(EscalateReq)--o   # Wrapper 发送升级请求
         ||     |           |
         |o--(Escalate)---->o   # Server 响应：需要升级
         ||     |           |
         |o<---------(fds)--o   # Wrapper 转发 stdin/stdout/stderr FDs
         ||     |           |
  o<------o     |           |    # Server 在沙箱外执行命令
  |      ||     |           |
  x------>o     |           |    # 命令执行完成
         ||     |           |
         |x--(exit code)--->o   # Server 返回 exit code
         |      |           |
         |      o<--(exit)--x   # Wrapper 退出
         |      |
         o<-----x
```

#### Non-escalation Flow（直接执行）

```
Server  Shell  Execve Wrapper  Command
  |
  o----->o           # Server 启动 Shell
  |      |
  |      o--(exec)-->o    # Shell 执行命令触发 wrapper
  |      |           |
  |o<-(EscalateReq)--o    # Wrapper 发送升级请求
  ||     |           |
  |o-(Run)---------->o    # Server 响应：直接执行
  |      |           |
  |      |           x--(exec)-->o  # Wrapper 调用 execve 执行原命令
  |      |                       |
  |      o<--------------(exit)--x  # 命令执行完成
  |      |
  o<-----x
```

### 关键协议消息

```rust
// 客户端 -> 服务端
pub struct EscalateRequest {
    pub file: PathBuf,           // 可执行文件路径
    pub argv: Vec<String>,       // 参数列表（含 argv[0]）
    pub workdir: AbsolutePathBuf, // 工作目录
    pub env: HashMap<String, String>, // 环境变量
}

// 服务端 -> 客户端
pub struct EscalateResponse {
    pub action: EscalateAction,  // Run / Escalate / Deny
}

// FD 转发消息（Escalate 决策后）
pub struct SuperExecMessage {
    pub fds: Vec<RawFd>,         // 目标 FD 编号（0,1,2）
}

// 执行结果
pub struct SuperExecResult {
    pub exit_code: i32,
}
```

### Socket 通信机制

- **环境变量**: `CODEX_ESCALATE_SOCKET` 指定继承的 socket FD
- **双 socket 设计**:
  - **Datagram Socket**: 用于初始握手，传递 stream socket 的 FD
  - **Stream Socket**: 用于后续请求/响应通信，支持并发
- **SCM_RIGHTS**: 使用 Unix domain socket 的辅助消息传递文件描述符

## 关键代码路径与文件引用

### 核心实现文件

| 文件 | 职责 |
|------|------|
| `src/unix/escalate_protocol.rs` | 协议消息类型定义（`EscalateRequest`, `EscalateResponse` 等） |
| `src/unix/escalate_client.rs` | 客户端实现，`run_shell_escalation_execve_wrapper` 主逻辑 |
| `src/unix/escalate_server.rs` | 服务端实现，`EscalateServer` 和 `escalate_task` |
| `src/unix/escalation_policy.rs` | `EscalationPolicy` trait 定义 |
| `src/unix/execve_wrapper.rs` | 二进制入口 CLI 解析 |
| `src/unix/socket.rs` | 异步 socket 实现，支持 FD 传递 |
| `src/unix/stopwatch.rs` | 可暂停的计时器，用于超时控制 |

### 调用链

```
main_execve_wrapper (src/bin/main_execve_wrapper.rs)
└── main_execve_wrapper() (src/unix/execve_wrapper.rs)
    └── run_shell_escalation_execve_wrapper() (src/unix/escalate_client.rs)
        ├── get_escalate_client() - 从环境变量获取 socket
        ├── AsyncSocket::pair() - 创建通信 socket pair
        ├── 发送 EscalateRequest
        └── 处理响应:
            ├── EscalateAction::Run -> libc::execv()
            ├── EscalateAction::Escalate -> 转发 FDs，等待 SuperExecResult
            └── EscalateAction::Deny -> 输出错误，exit(1)
```

## 依赖与外部交互

### Patched Bash

README 中提到的 bash patch 添加了对 `EXEC_WRAPPER` 环境变量的支持：

- **Patch 文件**: `patches/bash-exec-wrapper.patch`（注：实际仓库中可能不存在，需从其他渠道获取）
- **目标版本**: `a8a1c2fac029404d3f42cd39f5a20f24b6e4fe4b`
- **编译配置**: `--without-bash-malloc`

### 与 codex-core 的集成

```rust
// codex-core 中的使用（src/tools/runtimes/shell/unix_escalation.rs）
use codex_shell_escalation::{
    EscalateServer, EscalationDecision, EscalationExecution,
    EscalationPermissions, EscalationPolicy, EscalationSession,
    ExecParams, ExecResult, PreparedExec, ShellCommandExecutor,
    Stopwatch, ESCALATE_SOCKET_ENV_VAR,
};
```

### 环境变量

| 变量 | 用途 |
|------|------|
| `CODEX_ESCALATE_SOCKET` | 指定 escalation socket 的文件描述符 |
| `EXEC_WRAPPER` | 指定 execve wrapper 可执行文件路径 |
| `BASH_EXEC_WRAPPER` | 兼容性别名，用于旧版 patched bash |

## 风险、边界与改进建议

### 风险点

1. **Bash Patch 依赖**: 功能完全依赖 patched bash，用户需要手动编译或获取预编译版本
2. **FD 传递安全**: SCM_RIGHTS 传递的文件描述符需要严格验证数量和目标
3. **并发安全**: 多个并发 escalation 请求需要正确处理 socket 和 FD 生命周期

### 边界条件

1. **平台限制**: 仅支持 Unix 平台（Linux/macOS）
2. **Shell 限制**: 目前主要针对 Zsh 和 patched Bash 优化
3. **FD 数量限制**: 单次消息最多传递 16 个文件描述符（`MAX_FDS_PER_MESSAGE`）
4. **消息大小限制**: Datagram 消息最大 8192 字节（`MAX_DATAGRAM_SIZE`）

### 改进建议

1. **文档完善**:
   - 添加架构图说明完整的数据流
   - 补充错误处理流程文档
   - 添加性能基准测试数据

2. **功能增强**:
   - 支持信号转发（TODO 注释中提到）
   - 支持更多 shell（fish, nushell 等）
   - 提供预编译的 patched bash 二进制

3. **安全加固**:
   - 添加 FD 类型验证（确保传递的是有效的 stdio FD）
   - 实现请求速率限制防止 DoS
   - 添加审计日志记录所有 escalation 决策

4. **测试覆盖**:
   - 添加集成测试验证完整流程
   - 测试 FD 重叠场景（如 src_fd == dst_fd）
   - 测试大负载消息（> 8192 字节）

### 已知问题

1. **macOS 兼容性**: 测试中发现 macOS 可能在 FD 完全服务前观察到 EOF，代码中通过保持 server stream guard 解决
2. **信号处理**: TODO 注释表明信号转发尚未实现
