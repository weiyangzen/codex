# DIR Research: codex-rs/core/src/tools/runtimes/shell

## 概述

本目录包含 Codex CLI 的 **Shell 运行时实现**，负责执行 shell 命令请求，并提供基于 `zsh-fork` 的权限升级机制。这是 Codex 工具执行链中的关键组件，连接了用户命令输入与底层沙箱执行环境。

---

## 场景与职责

### 核心场景

1. **Shell 命令执行**: 处理 `shell` 和 `shell_command` 工具的命令执行请求
2. **权限升级 (Escalation)**: 当命令需要超出当前沙箱限制的权限时，通过 `zsh-fork` 机制进行权限升级
3. **策略执行**: 根据 `execpolicy` 规则决定命令是否允许执行、需要用户确认还是被禁止
4. **Skill 脚本支持**: 识别并处理来自 Skill 的脚本执行，应用 Skill 特定的权限配置

### 主要职责

| 组件 | 职责 |
|------|------|
| `shell.rs` | 主 Shell 运行时，处理命令执行流程、审批流程、沙箱配置 |
| `unix_escalation.rs` | Unix 平台的权限升级实现，包含策略评估、命令拦截、权限计算 |
| `zsh_fork_backend.rs` | Zsh-fork 后端适配器，连接 shell-escalation crate |
| `unix_escalation_tests.rs` | 单元测试，覆盖策略评估、权限计算、命令解析等 |

---

## 功能点目的

### 1. ShellRuntime - 主运行时

```rust
pub struct ShellRuntime {
    backend: ShellRuntimeBackend,
}
```

- **目的**: 实现 `ToolRuntime` trait，作为 shell 命令的执行引擎
- **关键行为**:
  - 支持三种后端模式：`Generic`（通用）、`ShellCommandClassic`（经典模式）、`ShellCommandZshFork`（Zsh-fork 模式）
  - 处理命令审批流程（通过 `Approvable` trait）
  - 管理沙箱偏好设置和失败后的升级策略

### 2. Zsh-fork 权限升级机制

**目的**: 允许命令在需要时从沙箱内"升级"到沙箱外执行，或应用不同的沙箱策略。

**工作流程**:
1. 用户 shell 通过 `EXEC_WRAPPER` 环境变量配置的包装器拦截所有 `execve()` 调用
2. 包装器通过 Unix socket (`CODEX_ESCALATE_SOCKET`) 向 `EscalateServer` 发送升级请求
3. 服务器根据策略决定：
   - `Run`: 在沙箱内直接执行
   - `Escalate`: 在服务器端以升级后的权限执行
   - `Deny`: 拒绝执行

### 3. 策略评估系统

**目的**: 基于 `codex_execpolicy` 的规则引擎，对命令进行细粒度的访问控制。

**决策来源**:
- `SkillScript`: 来自 Skill 的脚本，使用 Skill 的权限配置
- `PrefixRule`: 匹配 `*.rules` 文件中定义的前缀规则
- `UnmatchedCommandFallback`: 未匹配任何规则时的默认行为

### 4. 会话级审批缓存

**目的**: 避免对同一命令重复请求用户审批。

- 使用 `execve_session_approvals` 存储已批准的程序路径
- 支持 `ApprovedForSession` 决策，允许用户"本次会话内不再询问"

---

## 具体技术实现

### 关键流程

#### 1. 命令执行流程 (ShellRuntime::run)

```
ShellRequest
    ↓
maybe_wrap_shell_lc_with_snapshot  (应用 shell snapshot)
    ↓
ShellRuntimeBackend::ShellCommandZshFork?
    ├─ Yes → zsh_fork_backend::maybe_run_shell_command
    │           ↓
    │       unix_escalation::try_run_zsh_fork
    │           ↓
    │       EscalateServer::exec
    │           ↓
    │       CoreShellCommandExecutor::run
    │
    └─ No → build_command_spec → execute_env (标准沙箱执行)
```

#### 2. 权限升级决策流程 (CoreShellActionProvider::determine_action)

```rust
async fn determine_action(&self, program, argv, workdir) -> EscalationDecision {
    // 1. 检查会话缓存
    if let Some(approval) = execve_session_approvals.get(program) {
        return EscalationDecision::escalate(execution);
    }
    
    // 2. 检查 Skill 匹配
    if let Some(skill) = find_skill(program).await {
        if skill.permission_profile.is_empty() {
            return EscalationDecision::escalate(TurnDefault);
        }
        return process_decision(Decision::Prompt, skill_execution);
    }
    
    // 3. 评估 execpolicy
    let evaluation = evaluate_intercepted_exec_policy(policy, program, argv, context);
    process_decision(evaluation.decision, escalation_execution)
}
```

#### 3. Zsh-fork 执行流程

```
EscalateServer::exec
    ↓
EscalateServer::start_session  (创建 escalation socket)
    ↓
ShellCommandExecutor::run      (启动 shell 进程)
    ↓
(shell 进程内) execve 被拦截
    ↓
execve_wrapper 发送 EscalateRequest
    ↓
escalate_task 处理请求
    ↓
EscalationPolicy::determine_action
    ↓
EscalateResponse::Run | Escalate | Deny
```

### 关键数据结构

#### ShellRequest

```rust
pub struct ShellRequest {
    pub command: Vec<String>,           // 命令及参数
    pub cwd: PathBuf,                   // 工作目录
    pub timeout_ms: Option<u64>,        // 超时时间
    pub env: HashMap<String, String>,   // 环境变量
    pub explicit_env_overrides: HashMap<String, String>,
    pub network: Option<NetworkProxy>,  // 网络代理配置
    pub sandbox_permissions: SandboxPermissions,  // 沙箱权限模式
    pub additional_permissions: Option<PermissionProfile>, // 额外权限
    pub justification: Option<String>,  // 执行理由
    pub exec_approval_requirement: ExecApprovalRequirement, // 审批要求
}
```

#### CoreShellActionProvider

```rust
struct CoreShellActionProvider {
    policy: Arc<RwLock<Policy>>,        // execpolicy 规则
    session: Arc<Session>,              // 会话上下文
    turn: Arc<TurnContext>,             // 当前 turn 上下文
    call_id: String,
    tool_name: &'static str,
    approval_policy: AskForApproval,    // 审批策略
    sandbox_policy: SandboxPolicy,      // 沙箱策略
    file_system_sandbox_policy: FileSystemSandboxPolicy,
    network_sandbox_policy: NetworkSandboxPolicy,
    sandbox_permissions: SandboxPermissions,
    approval_sandbox_permissions: SandboxPermissions,
    prompt_permissions: Option<PermissionProfile>,
    stopwatch: Stopwatch,               // 超时控制
}
```

#### CoreShellCommandExecutor

```rust
struct CoreShellCommandExecutor {
    command: Vec<String>,
    cwd: PathBuf,
    sandbox_policy: SandboxPolicy,
    file_system_sandbox_policy: FileSystemSandboxPolicy,
    network_sandbox_policy: NetworkSandboxPolicy,
    sandbox: SandboxType,
    env: HashMap<String, String>,
    network: Option<NetworkProxy>,
    windows_sandbox_level: WindowsSandboxLevel,
    sandbox_permissions: SandboxPermissions,
    justification: Option<String>,
    arg0: Option<String>,
    sandbox_policy_cwd: PathBuf,
    macos_seatbelt_profile_extensions: Option<MacOsSeatbeltProfileExtensions>,
    codex_linux_sandbox_exe: Option<PathBuf>,
    use_legacy_landlock: bool,
}
```

### 协议与命令

#### Escalation 协议 (来自 codex-shell-escalation)

**环境变量**:
- `CODEX_ESCALATE_SOCKET`: Unix socket 文件描述符
- `EXEC_WRAPPER`: execve 包装器路径
- `BASH_EXEC_WRAPPER`: 兼容旧版 bash 包装器

**消息类型**:
```rust
// 客户端 → 服务器
pub struct EscalateRequest {
    pub file: PathBuf,           // 可执行文件路径
    pub argv: Vec<String>,       // 参数列表
    pub workdir: AbsolutePathBuf,
    pub env: HashMap<String, String>,
}

// 服务器 → 客户端
pub struct EscalateResponse {
    pub action: EscalateAction,  // Run / Escalate / Deny
}

// 客户端发送文件描述符
pub struct SuperExecMessage {
    pub fds: Vec<RawFd>,         // 要传递的文件描述符
}

// 服务器返回执行结果
pub struct SuperExecResult {
    pub exit_code: i32,
}
```

#### 命令解析

```rust
fn extract_shell_script(command: &[String]) -> Result<ParsedShellCommand, ToolError> {
    // 查找 -c 或 -lc 标志
    // 支持 wrapped command: env VAR=value /bin/zsh -lc "script"
}
```

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 行数 | 描述 |
|------|------|------|
| `shell.rs` | 266 | 主 Shell 运行时实现 |
| `unix_escalation.rs` | 1155 | Unix 权限升级核心逻辑 |
| `unix_escalation_tests.rs` | 841 | 单元测试 |
| `zsh_fork_backend.rs` | 136 | Zsh-fork 后端适配器 |

### 关键函数路径

```
shell.rs
├── ShellRuntime::run (line 217-265)
│   ├── maybe_wrap_shell_lc_with_snapshot
│   └── zsh_fork_backend::maybe_run_shell_command (if ZshFork backend)
│
└── impl Approvable<ShellRequest> (line 129-202)
    ├── approval_keys
    └── start_approval_async

unix_escalation.rs
├── try_run_zsh_fork (line 90-222)
│   ├── extract_shell_script
│   ├── CoreShellCommandExecutor::new
│   └── EscalateServer::exec
│
├── CoreShellActionProvider::determine_action (line 622-751)
│   ├── find_skill
│   ├── evaluate_intercepted_exec_policy
│   └── process_decision
│
├── CoreShellCommandExecutor::run (line 881-929)
│   └── crate::sandboxing::execute_exec_request_with_after_spawn
│
└── CoreShellCommandExecutor::prepare_escalated_exec (line 931-1006)
    └── prepare_sandboxed_exec

zsh_fork_backend.rs
├── maybe_run_shell_command (line 21-28)
│   └── unix_escalation::try_run_zsh_fork
│
└── maybe_prepare_unified_exec (line 36-44)
    └── unix_escalation::prepare_unified_exec_zsh_fork
```

### 外部依赖

```
codex-shell-escalation crate
├── src/unix/escalate_server.rs    # EscalateServer, EscalationSession
├── src/unix/escalate_protocol.rs  # 协议消息定义
├── src/unix/escalation_policy.rs  # EscalationPolicy trait
└── src/unix/execve_wrapper.rs     # execve 包装器

codex-execpolicy crate
├── Policy, Decision, Evaluation   # 策略评估
├── RuleMatch                      # 规则匹配结果
└── MatchOptions                   # 匹配选项
```

---

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::sandboxing` | 沙箱管理、ExecRequest 构建、权限转换 |
| `crate::exec_policy` | 策略评估、规则匹配 |
| `crate::guardian` | Guardian 审批流程路由 |
| `crate::skills` | Skill 元数据查找 |
| `crate::features` | 功能开关检查 (ShellZshFork) |
| `crate::shell` | Shell 类型、ShellSnapshot |
| `crate::unified_exec` | UnifiedExec 集成 |

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `codex-shell-escalation` | Unix socket 升级协议、EscalateServer |
| `codex-execpolicy` | 策略规则解析与评估 |
| `codex-protocol` | 协议类型 (AskForApproval, ReviewDecision, SandboxPolicy 等) |
| `codex-utils-absolute-path` | AbsolutePathBuf 路径处理 |
| `tokio::sync::RwLock` | 并发策略缓存 |
| `tokio_util::sync::CancellationToken` | 取消信号传递 |

### 环境交互

```rust
// 从 SessionServices 获取
ctx.session.services.shell_zsh_path           // Zsh 路径
ctx.session.services.main_execve_wrapper_exe  // execve 包装器
ctx.session.services.exec_policy              // 策略管理器
ctx.session.services.skills_manager           // Skill 管理器
ctx.session.services.execve_session_approvals // 会话审批缓存
```

---

## 风险、边界与改进建议

### 已知风险

1. **Socket FD 泄漏风险**
   - 位置: `ZshForkSpawnLifecycle::inherited_fds`
   - 问题: 子进程继承的 socket FD 如果没有正确关闭，可能导致泄漏
   - 缓解: `after_spawn` 钩子调用 `close_client_socket`

2. **策略竞争条件**
   - 位置: `CoreShellActionProvider::determine_action`
   - 问题: `exec_policy` 使用 `ArcSwap` 可能被并发更新
   - 缓解: 使用 `RwLock` 保护策略读取

3. **命令注入风险**
   - 位置: `extract_shell_script`
   - 问题: 解析 shell 命令时可能误解析恶意构造的命令
   - 缓解: 仅支持 `-c`/`-lc` 格式，拒绝复杂包装

4. **超时处理复杂性**
   - 位置: `Stopwatch` 使用
   - 问题: 升级流程涉及多个异步步骤，超时处理复杂
   - 缓解: `pause_for` 机制暂停计时器

### 边界条件

1. **平台限制**
   - Zsh-fork 仅在 Unix 平台可用
   - 需要用户 shell 为 Zsh
   - 需要 `shell_zsh_path` 和 `main_execve_wrapper_exe` 配置

2. **命令格式限制**
   - 仅支持 `[program, -c/-lc, script]` 格式
   - 不支持复杂的 shell 包装（如 `env VAR=value cmd` 需要特殊处理）

3. **并发限制**
   - `ESCALATE_SERVER_TEST_LOCK` 用于测试串行化
   - 生产环境支持并发，但每个会话有自己的 escalation socket

### 改进建议

1. **错误处理增强**
   ```rust
   // 当前: 使用 unwrap 和 expect
   // 建议: 使用更详细的错误类型，包含上下文信息
   ```

2. **策略缓存优化**
   - 当前每次 `determine_action` 都重新评估策略
   - 可考虑对无状态策略结果进行缓存

3. **测试覆盖**
   - 增加集成测试覆盖完整的 escalation 流程
   - 添加性能测试评估大命令列表的策略评估性能

4. **文档完善**
   - 添加更多关于 `ENABLE_INTERCEPTED_EXEC_POLICY_SHELL_WRAPPER_PARSING` 的文档
   - 解释何时应该启用 shell wrapper 解析

5. **代码简化**
   - `CoreShellActionProvider` 包含大量字段，可考虑分组
   - `prepare_sandboxed_exec` 参数过多，可使用 builder 模式

---

## 附录：关键类型定义

```rust
// 决策来源枚举
enum DecisionSource {
    SkillScript { skill: SkillMetadata },
    PrefixRule,
    UnmatchedCommandFallback,
}

// 升级执行方式
enum EscalationExecution {
    Unsandboxed,           // 无沙箱执行
    TurnDefault,           // 使用当前 turn 的默认沙箱
    Permissions(EscalationPermissions), // 指定权限
}

// 解析后的 shell 命令
struct ParsedShellCommand {
    program: String,
    script: String,
    login: bool,
}
```

---

*Generated: 2026-03-21*
*Research Scope: codex-rs/core/src/tools/runtimes/shell*
