# unix_escalation.rs 研究文档

## 场景与职责

`unix_escalation.rs` 是 Codex CLI 中 **Zsh Fork 后端**在 Unix 平台上的核心实现文件，负责处理 shell 命令执行的**权限升级（escalation）**流程。它位于 `codex-rs/core/src/tools/runtimes/shell/` 目录下，是 shell 工具运行时与 `codex-shell-escalation` crate 之间的关键桥梁。

### 核心职责

1. **Zsh Fork 执行入口**：提供 `try_run_zsh_fork` 函数，尝试通过 zsh-fork 机制执行 shell 命令
2. **Unified Exec 准备**：提供 `prepare_unified_exec_zsh_fork` 函数，为统一执行模式准备升级会话
3. **策略决策**：实现 `CoreShellActionProvider`，根据执行策略决定命令的执行方式（允许、拒绝、提示用户、升级权限）
4. **命令执行**：实现 `CoreShellCommandExecutor`，实际执行被拦截的 execve 调用

### 架构定位

```
┌─────────────────────────────────────────────────────────────────┐
│                     Shell Runtime (shell.rs)                     │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              Zsh Fork Backend (zsh_fork_backend.rs)        │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │         Unix Escalation (unix_escalation.rs)         │  │  │
│  │  │  ┌──────────────┐  ┌──────────────────────────────┐ │  │  │
│  │  │  │EscalateServer│  │CoreShellActionProvider       │ │  │  │
│  │  │  │              │  │(EscalationPolicy trait impl) │ │  │  │
│  │  │  └──────────────┘  └──────────────────────────────┘ │  │  │
│  │  │  ┌──────────────────────────────────────────────┐   │  │  │
│  │  │  │CoreShellCommandExecutor                      │   │  │  │
│  │  │  │(ShellCommandExecutor trait impl)             │   │  │  │
│  │  │  └──────────────────────────────────────────────┘   │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              codex-shell-escalation crate (Unix)                 │
│         (escalate_server.rs, escalate_client.rs, ...)            │
└─────────────────────────────────────────────────────────────────┘
```

---

## 功能点目的

### 1. 条件检查与前置过滤 (`try_run_zsh_fork`)

**目的**：在执行前验证所有必要条件，避免不必要的资源分配。

**检查项**：
- `shell_zsh_path` 是否配置
- `ShellZshFork` 特性是否启用
- 用户 shell 是否为 Zsh

### 2. 命令解析 (`extract_shell_script`)

**目的**：从复杂的 shell 命令行中提取关键信息（程序路径、脚本内容、登录标志）。

**支持格式**：
- `/bin/zsh -c "echo hi"` → 非登录shell
- `/bin/zsh -lc "echo hi"` → 登录shell
- `/usr/bin/env VAR=val /bin/zsh -lc "cmd"` → 支持环境包装器

### 3. 策略驱动的执行决策 (`CoreShellActionProvider`)

**目的**：根据执行策略（Policy）和用户配置，决定如何处理每个 execve 调用。

**决策类型**：
| 决策 | 含义 |
|------|------|
| `Run` | 直接在沙箱中执行 |
| `Escalate(TurnDefault)` | 使用当前 turn 的默认沙箱配置执行 |
| `Escalate(Unsandboxed)` | 无沙箱执行（完全特权） |
| `Escalate(Permissions(...))` | 使用指定的权限配置执行 |
| `Deny` | 拒绝执行 |

### 4. Skill 脚本识别与处理

**目的**：自动识别并处理 Skill 目录下的脚本，应用 Skill 声明的权限配置。

**流程**：
1. 检查命令路径是否位于任何 Skill 的 `scripts/` 子目录下
2. 如果 Skill 有 `permission_profile`，则提示用户批准
3. 如果 Skill 无权限声明，直接继承 turn 沙箱

### 5. 会话级批准缓存 (`execve_session_approvals`)

**目的**：避免对同一程序重复提示用户批准。

**机制**：
- 用户选择 "Approve for session" 后，程序路径被加入会话批准缓存
- 后续相同路径的执行直接允许，无需再次提示

---

## 具体技术实现

### 关键数据结构

#### `CoreShellActionProvider`
```rust
struct CoreShellActionProvider {
    policy: Arc<RwLock<Policy>>,                    // 执行策略（来自 .rules 文件）
    session: Arc<crate::codex::Session>,           // 会话上下文
    turn: Arc<crate::codex::TurnContext>,          // Turn 上下文
    call_id: String,                               // 调用 ID
    tool_name: &'static str,                       // "shell" 或 "exec_command"
    approval_policy: AskForApproval,               // 用户批准策略
    sandbox_policy: SandboxPolicy,                 // 沙箱策略
    file_system_sandbox_policy: FileSystemSandboxPolicy,
    network_sandbox_policy: NetworkSandboxPolicy,
    sandbox_permissions: SandboxPermissions,       // 请求的权限级别
    approval_sandbox_permissions: SandboxPermissions,
    prompt_permissions: Option<PermissionProfile>, // 额外请求的权限
    stopwatch: Stopwatch,                          // 超时控制
}
```

#### `CoreShellCommandExecutor`
```rust
struct CoreShellCommandExecutor {
    command: Vec<String>,                          // 原始命令
    cwd: PathBuf,                                  // 工作目录
    sandbox_policy: SandboxPolicy,                 // 沙箱策略配置
    file_system_sandbox_policy: FileSystemSandboxPolicy,
    network_sandbox_policy: NetworkSandboxPolicy,
    sandbox: SandboxType,                          // 沙箱类型
    env: HashMap<String, String>,                  // 环境变量
    network: Option<NetworkProxy>,                 // 网络代理配置
    windows_sandbox_level: WindowsSandboxLevel,    // Windows 沙箱级别
    sandbox_permissions: SandboxPermissions,
    justification: Option<String>,                 // 执行理由
    arg0: Option<String>,                          // argv[0] 覆盖
    sandbox_policy_cwd: PathBuf,                   // 策略计算的工作目录
    macos_seatbelt_profile_extensions: Option<MacOsSeatbeltProfileExtensions>,
    codex_linux_sandbox_exe: Option<PathBuf>,      // Linux 沙箱可执行文件
    use_legacy_landlock: bool,                     // 是否使用旧版 Landlock
}
```

#### `ParsedShellCommand`
```rust
struct ParsedShellCommand {
    program: String,    // 程序路径（如 "/bin/zsh"）
    script: String,     // 脚本内容（如 "echo hi"）
    login: bool,        // 是否使用登录 shell（-lc vs -c）
}
```

### 关键流程

#### 1. 执行流程 (`try_run_zsh_fork`)

```
┌─────────────────┐
│  前置条件检查    │
│ (配置/特性/Shell)│
└────────┬────────┘
         ▼
┌─────────────────┐
│ 构建 CommandSpec │
└────────┬────────┘
         ▼
┌─────────────────┐
│  创建 Sandbox    │
│  ExecRequest     │
└────────┬────────┘
         ▼
┌─────────────────┐
│ 解析 Shell 命令  │
│ extract_shell_  │
│   script()       │
└────────┬────────┘
         ▼
┌─────────────────┐
│ 创建并启动       │
│ EscalateServer   │
└────────┬────────┘
         ▼
┌─────────────────┐
│ 执行并返回结果   │
│ map_exec_result  │
└─────────────────┘
```

#### 2. 策略决策流程 (`determine_action`)

```
┌─────────────────────────────────────────┐
│ 检查会话批准缓存                        │
│ (execve_session_approvals)              │
└─────────────────┬───────────────────────┘
                  │
         ┌────────┴────────┐
         │ 有缓存？         │
         └────────┬────────┘
                  │
      ┌───────────┴───────────┐
      ▼                       ▼
┌─────────────┐         ┌─────────────────┐
│ 直接 Escalate│         │ 检查是否为 Skill │
│ (使用缓存的  │         │ 脚本             │
│  执行方式)   │         └────────┬────────┘
└─────────────┘                  │
                        ┌────────┴────────┐
                        │ 是 Skill？       │
                        └────────┬────────┘
                                 │
                    ┌────────────┴────────────┐
                    ▼                         ▼
            ┌─────────────┐           ┌─────────────────┐
            │ Skill 处理   │           │ 评估执行策略     │
            │ (权限检查)   │           │ (evaluate_inter-│
            └─────────────┘           │ cepted_exec_    │
                                      │   policy)       │
                                      └────────┬────────┘
                                               │
                                      ┌────────┴────────┐
                                      │ 根据决策和来源   │
                                      │ 确定执行方式     │
                                      └─────────────────┘
```

#### 3. 命令执行流程 (`ShellCommandExecutor::run`)

```rust
async fn run(
    &self,
    _command: Vec<String>,
    _cwd: PathBuf,
    env_overlay: HashMap<String, String>,  // 来自 EscalationSession 的环境
    cancel_rx: CancellationToken,
    after_spawn: Option<Box<dyn FnOnce() + Send>>,
) -> anyhow::Result<ExecResult> {
    // 1. 合并环境变量（只合并 wrapper/socket 变量）
    // 2. 调用 sandboxing::execute_exec_request_with_after_spawn 执行
    // 3. 返回 ExecResult
}
```

#### 4. 升级执行准备 (`prepare_escalated_exec`)

根据 `EscalationExecution` 类型准备执行：

| 执行类型 | 处理方式 |
|---------|---------|
| `Unsandboxed` | 直接执行，无沙箱包装 |
| `TurnDefault` | 使用当前 turn 的沙箱配置 |
| `Permissions(PermissionProfile)` | 合并 Skill/请求的额外权限到 turn 配置 |
| `Permissions(Permissions)` | 使用完全指定的权限配置 |

### 策略评估 (`evaluate_intercepted_exec_policy`)

```rust
fn evaluate_intercepted_exec_policy(
    policy: &Policy,
    program: &AbsolutePathBuf,
    argv: &[String],
    context: InterceptedExecPolicyContext<'_>,
) -> Evaluation
```

**逻辑**：
1. 如果启用 shell wrapper 解析，尝试解析内部命令
2. 使用 `policy.check_multiple_with_options` 匹配规则
3. 无匹配时使用 fallback 函数（基于 `AskForApproval` 配置）

**常量控制**：
```rust
const ENABLE_INTERCEPTED_EXEC_POLICY_SHELL_WRAPPER_PARSING: bool = false;
```
（默认禁用，因为 shell wrapper 解析比直接 exec 拦截弱）

---

## 关键代码路径与文件引用

### 内部依赖

| 路径 | 用途 |
|------|------|
| `shell.rs` | 定义 `ShellRequest`，调用 `zsh_fork_backend` |
| `zsh_fork_backend.rs` | 平台抽象，调用 `unix_escalation` |
| `../sandboxing.rs` | `ToolCtx`, `SandboxAttempt`, `ToolError` 定义 |
| `../../spec.rs` | `ZshForkConfig` 定义 |
| `../../../sandboxing/` | `SandboxManager`, `ExecRequest` 等 |
| `../../../exec_policy.rs` | `render_decision_for_unmatched_command` |
| `../../../skills.rs` | `SkillMetadata` 定义 |

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_shell_escalation` | `EscalateServer`, `EscalationPolicy`, `ShellCommandExecutor` trait |
| `codex_execpolicy` | `Policy`, `Decision`, `RuleMatch`, `Evaluation` |
| `codex_protocol` | `SandboxPolicy`, `PermissionProfile`, `AskForApproval` |
| `codex_utils_absolute_path` | `AbsolutePathBuf` |

### 关键函数调用链

```
try_run_zsh_fork
├── build_command_spec (tools/runtimes/mod.rs)
├── extract_shell_script
│   └── 解析 -c/-lc 参数
├── EscalateServer::new
│   └── shell-escalation/src/unix/escalate_server.rs
├── EscalateServer::exec
│   ├── start_session
│   │   ├── AsyncDatagramSocket::pair
│   │   └── escalate_task (spawn)
│   └── command_executor.run
│       └── CoreShellCommandExecutor::run
│           └── sandboxing::execute_exec_request_with_after_spawn
└── map_exec_result
```

---

## 依赖与外部交互

### 与 `codex-shell-escalation` 的交互

```rust
// unix_escalation.rs 实现 EscalationPolicy trait
#[async_trait::async_trait]
impl EscalationPolicy for CoreShellActionProvider {
    async fn determine_action(
        &self,
        program: &AbsolutePathBuf,
        argv: &[String],
        workdir: &AbsolutePathBuf,
    ) -> anyhow::Result<EscalationDecision>;
}

// 同时实现 ShellCommandExecutor trait
#[async_trait::async_trait]
impl ShellCommandExecutor for CoreShellCommandExecutor {
    async fn run(...);
    async fn prepare_escalated_exec(...);
}
```

### 与 Exec Policy 系统的交互

通过 `codex_execpolicy` crate：
- 加载 `.rules` 文件定义的策略
- 使用 `prefix_rule` 匹配命令前缀
- 使用 `host_executable` 映射主机可执行文件

### 与 Skill 系统的交互

```rust
async fn find_skill(&self, program: &AbsolutePathBuf) -> Option<SkillMetadata> {
    let skills_outcome = self
        .session
        .services
        .skills_manager
        .skills_for_cwd(&self.turn.cwd, self.turn.config.as_ref(), force_reload)
        .await;
    
    // 检查程序路径是否位于 Skill 的 scripts/ 目录下
    for skill in skills_outcome.skills {
        if program_path.starts_with(skill_root.join("scripts")) {
            return Some(skill);
        }
    }
    None
}
```

### 与 Guardian 的交互

当 `routes_approval_to_guardian` 返回 true 时，批准请求被路由到 Guardian：
```rust
if routes_approval_to_guardian(&turn) {
    return review_approval_request(
        &session,
        &turn,
        GuardianApprovalRequest::Execve { ... },
        retry_reason,
    ).await;
}
```

---

## 风险、边界与改进建议

### 已知风险

1. **路径解析风险**
   - `extract_shell_script` 使用简单的窗口匹配（`windows(3)`），可能被复杂命令结构绕过
   - 相对路径解析依赖于 `AbsolutePathBuf::resolve_path_against_base`，需确保 workdir 正确

2. **并发安全**
   - `execve_session_approvals` 使用 `RwLock`，高并发时可能成为瓶颈
   - 会话批准缓存无过期机制，长时间会话可能积累大量条目

3. **超时处理**
   - `Stopwatch` 在策略决策期间可能暂停，但复杂策略评估仍可能消耗大量时间
   - 用户提示期间不计入超时，恶意构造的 Skill 可能利用此点延长执行

4. **权限升级边界**
   - `Unsandboxed` 执行完全绕过沙箱，需确保策略决策可靠
   - macOS Seatbelt 扩展权限的合并逻辑复杂，可能产生意外组合

### 边界条件

| 场景 | 行为 |
|------|------|
| 非 Zsh shell | 返回 `Ok(None)`，回退到标准执行 |
| 非 `-c`/`-lc` 命令 | 返回 `ToolError::Rejected` |
| 未配置 `shell_zsh_path` | 返回 `Ok(None)` |
| 未配置 `main_execve_wrapper_exe` | 返回 `ToolError::Rejected` |
| Skill 脚本无权限声明 | 继承 turn 默认沙箱 |
| 用户拒绝批准 | 返回 `EscalationDecision::Deny` |
| 策略决策超时 | 由 `Stopwatch` 控制，取消执行 |

### 改进建议

1. **增强命令解析**
   - 考虑使用更健壮的 shell 解析器（如 `codex_shell_command` crate 的完整解析）
   - 添加对更多 shell 标志的支持（如 `-i` 交互模式）

2. **优化并发性能**
   - 考虑使用 `DashMap` 替代 `RwLock<HashMap>` 存储会话批准
   - 添加会话批准的 LRU 过期机制

3. **增强可观测性**
   - 添加更多 `tracing` 埋点，特别是策略决策路径
   - 导出策略评估指标（匹配规则数、决策时间等）

4. **安全加固**
   - 考虑为 `execve_session_approvals` 添加时间戳，实现自动过期
   - 添加 Skill 权限的审计日志

5. **代码简化**
   - `approval_sandbox_permissions` 函数名与参数名重复，建议重命名
   - `shell_request_escalation_execution` 和 `skill_escalation_execution` 可提取公共逻辑

### 测试覆盖

测试文件：`unix_escalation_tests.rs`

关键测试场景：
- 策略拒绝逻辑（`execve_prompt_rejection_*`）
- 沙箱权限降级（`approval_sandbox_permissions_*`）
- Shell 脚本提取（`extract_shell_script_*`）
- 命令连接（`join_program_and_argv`）
- 策略评估（`evaluate_intercepted_exec_policy_*`）
- macOS Seatbelt 扩展（`prepare_escalated_exec_*`）
