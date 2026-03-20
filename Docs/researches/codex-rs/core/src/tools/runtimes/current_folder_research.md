# DIR Research: codex-rs/core/src/tools/runtimes

## 概述

`codex-rs/core/src/tools/runtimes` 目录包含 Codex 工具系统中**具体工具运行时（ToolRuntime）的实现**。这些运行时负责执行特定工具（shell、apply_patch、unified_exec）的实际逻辑，包括权限审批、沙箱选择和重试机制。该目录是工具执行管道的核心执行层，与 `orchestrator.rs`（编排器）和 `sandboxing.rs`（沙箱抽象）紧密协作。

---

## 场景与职责

### 核心职责

1. **具体工具运行时实现**：为每个需要执行外部命令或修改文件系统的工具提供专门的 `ToolRuntime` 实现
2. **权限审批集成**：实现 `Approvable` trait，定义如何生成审批键、如何启动异步审批流程
3. **沙箱策略执行**：实现 `Sandboxable` trait，声明沙箱偏好和失败时的升级策略
4. **命令执行**：构建 `CommandSpec`，通过沙箱管理层执行实际命令
5. **Zsh-Fork 特权提升**：Unix 平台特有的 shell 命令特权提升机制

### 适用场景

| 场景 | 运行时 | 说明 |
|------|--------|------|
| 执行 shell 命令 | `ShellRuntime` | 处理 `shell` 和 `shell_command` 工具调用 |
| 应用代码补丁 | `ApplyPatchRuntime` | 安全地执行文件修改操作 |
| 交互式命令执行 | `UnifiedExecRuntime` | PTY 支持的长时间运行命令 |
| 特权命令执行 | Zsh-Fork 后端 | 通过 `codex-shell-escalation` 实现特权提升 |

---

## 功能点目的

### 1. ShellRuntime (`shell.rs`)

**目的**：执行 shell 命令，支持多种后端模式（Generic、ShellCommandClassic、ShellCommandZshFork）。

**关键功能**：
- 支持三种后端模式：
  - `Generic`：通用工具路径，无特定后端行为
  - `ShellCommandClassic`：传统 shell_command 工具路径
  - `ShellCommandZshFork`：使用 zsh-fork + 特权提升适配器
- 命令规范化：通过 `canonicalize_command_for_approval` 生成审批键
- 环境变量处理：支持显式环境变量覆盖和 shell snapshot 注入
- PowerShell UTF-8 支持：Windows 平台自动添加 UTF-8 前缀

### 2. ApplyPatchRuntime (`apply_patch.rs`)

**目的**：在沙箱保护下执行代码补丁应用。

**关键功能**：
- 自调用机制：通过 `codex --codex-run-as-apply-patch` 执行补丁
- 最小化环境：使用空环境变量集确保确定性执行
- 权限预批准支持：如果权限已预批准，跳过重复审批
- Guardian 集成：支持将审批请求路由到 Guardian 模式

### 3. UnifiedExecRuntime (`unified_exec.rs`)

**目的**：处理需要 PTY 支持的交互式命令执行。

**关键功能**：
- PTY 会话管理：与 `UnifiedExecProcessManager` 协作管理长时间运行的进程
- 延迟网络审批：支持 `Deferred` 模式的网络权限审批
- Zsh-Fork 集成：支持通过 zsh-fork 后端启动 PTY 会话
- TTY 支持：可选择分配 TTY 进行交互式命令执行

### 4. Unix Escalation (`shell/unix_escalation.rs`)

**目的**：实现 Unix 平台特有的命令特权提升机制。

**关键功能**：
- **Execve 拦截**：通过 `codex-execve-wrapper` 拦截 `execve(2)` 调用
- **策略评估**：基于 `codex_execpolicy` 评估命令执行策略
- **Skill 脚本检测**：自动检测并处理 Skill 脚本执行
- **会话审批缓存**：支持会话级别的命令审批缓存
- **多级权限提升**：
  - `TurnDefault`：使用当前 turn 的沙箱策略
  - `Unsandboxed`：无沙箱执行
  - `Permissions`：使用特定权限配置执行

### 5. Zsh Fork Backend (`shell/zsh_fork_backend.rs`)

**目的**：为 shell 命令和 unified exec 提供 zsh-fork 后端适配。

**关键功能**：
- 平台抽象：Unix 平台实现实际功能，其他平台返回 `None` 回退
- 生命周期管理：`ZshForkSpawnLifecycle` 管理 escalation 会话生命周期
- 文件描述符继承：正确处理 `CODEX_ESCALATE_SOCKET` 等环境变量

### 6. 共享工具函数 (`mod.rs`)

**目的**：提供运行时共享的辅助函数。

**关键功能**：
- `build_command_spec`：从 tokenized 命令行构建 `CommandSpec`
- `maybe_wrap_shell_lc_with_snapshot`：将 shell 命令包装为加载 snapshot 的脚本
- `shell_single_quote`：安全的 shell 单引号转义
- 环境变量覆盖处理：支持显式环境变量优先于 snapshot 变量

---

## 具体技术实现

### 关键流程

#### 1. Shell 命令执行流程

```
ShellHandler::handle
  ↓
RunExecLikeArgs 构建
  ↓
ShellRuntime::run (通过 ToolOrchestrator)
  ↓
maybe_wrap_shell_lc_with_snapshot (注入环境)
  ↓
[如果是 ZshFork 后端] zsh_fork_backend::maybe_run_shell_command
  ↓
unix_escalation::try_run_zsh_fork
  ↓
EscalateServer::exec → 执行命令
  ↓
或回退到标准执行：build_command_spec → execute_env
```

#### 2. Zsh-Fork 特权提升流程

```
try_run_zsh_fork
  ↓
检查前提条件（shell_zsh_path, ShellZshFork feature, Zsh shell）
  ↓
extract_shell_script（解析 shell 命令）
  ↓
CoreShellActionProvider::determine_action
  ↓
检查 execve_session_approvals 缓存
  ↓
Skill 脚本检测（find_skill）
  ↓
执行策略评估（evaluate_intercepted_exec_policy）
  ↓
process_decision（处理策略决定）
  ↓
EscalateServer::exec
  ↓
CoreShellCommandExecutor::run / prepare_escalated_exec
```

#### 3. Apply Patch 执行流程

```
ApplyPatchHandler::handle
  ↓
codex_apply_patch::maybe_parse_apply_patch_verified
  ↓
apply_patch::apply_patch（尝试直接应用）
  ↓
如果失败 → DelegateToExec
  ↓
ApplyPatchRequest 构建
  ↓
ApplyPatchRuntime::run
  ↓
build_command_spec（自调用 codex --codex-run-as-apply-patch）
  ↓
execute_env
```

### 关键数据结构

#### ShellRequest
```rust
pub struct ShellRequest {
    pub command: Vec<String>,           // 命令及参数
    pub cwd: PathBuf,                   // 工作目录
    pub timeout_ms: Option<u64>,        // 超时时间
    pub env: HashMap<String, String>,   // 环境变量
    pub explicit_env_overrides: HashMap<String, String>, // 显式覆盖
    pub network: Option<NetworkProxy>,  // 网络代理
    pub sandbox_permissions: SandboxPermissions, // 沙箱权限
    pub additional_permissions: Option<PermissionProfile>, // 额外权限
    pub justification: Option<String>,  // 执行理由
    pub exec_approval_requirement: ExecApprovalRequirement, // 审批要求
}
```

#### ApprovalKey (Shell)
```rust
pub(crate) struct ApprovalKey {
    command: Vec<String>,
    cwd: PathBuf,
    sandbox_permissions: SandboxPermissions,
    additional_permissions: Option<PermissionProfile>,
}
```

#### CoreShellActionProvider
```rust
struct CoreShellActionProvider {
    policy: Arc<RwLock<Policy>>,        // 执行策略
    session: Arc<Session>,              // 会话
    turn: Arc<TurnContext>,             // Turn 上下文
    call_id: String,                    // 调用 ID
    tool_name: &'static str,            // 工具名称
    approval_policy: AskForApproval,    // 审批策略
    sandbox_policy: SandboxPolicy,      // 沙箱策略
    stopwatch: Stopwatch,               // 超时控制
    // ... 其他策略字段
}
```

#### ParsedShellCommand
```rust
struct ParsedShellCommand {
    program: String,    // 程序路径
    script: String,     // 脚本内容
    login: bool,        // 是否登录 shell
}
```

### 协议与接口

#### 1. ToolRuntime Trait
```rust
pub(crate) trait ToolRuntime<Req, Out>: Approvable<Req> + Sandboxable {
    fn network_approval_spec(&self, _req: &Req, _ctx: &ToolCtx) -> Option<NetworkApprovalSpec>;
    async fn run(&mut self, req: &Req, attempt: &SandboxAttempt<'_>, ctx: &ToolCtx) 
        -> Result<Out, ToolError>;
}
```

#### 2. Approvable Trait
```rust
pub(crate) trait Approvable<Req> {
    type ApprovalKey: Hash + Eq + Clone + Debug + Serialize;
    fn approval_keys(&self, req: &Req) -> Vec<Self::ApprovalKey>;
    fn start_approval_async<'a>(&'a mut self, req: &'a Req, ctx: ApprovalCtx<'a>) 
        -> BoxFuture<'a, ReviewDecision>;
    fn exec_approval_requirement(&self, _req: &Req) -> Option<ExecApprovalRequirement>;
}
```

#### 3. EscalationPolicy Trait (shell-escalation crate)
```rust
#[async_trait::async_trait]
pub trait EscalationPolicy: Send + Sync {
    async fn determine_action(
        &self,
        program: &AbsolutePathBuf,
        argv: &[String],
        workdir: &AbsolutePathBuf,
    ) -> anyhow::Result<EscalationDecision>;
}
```

### 命令构建

#### build_command_spec
```rust
pub(crate) fn build_command_spec(
    command: &[String],
    cwd: &Path,
    env: &HashMap<String, String>,
    expiration: ExecExpiration,
    sandbox_permissions: SandboxPermissions,
    additional_permissions: Option<PermissionProfile>,
    justification: Option<String>,
) -> Result<CommandSpec, ToolError> {
    let (program, args) = command
        .split_first()
        .ok_or_else(|| ToolError::Rejected("command args are empty".to_string()))?;
    Ok(CommandSpec { /* ... */ })
}
```

#### maybe_wrap_shell_lc_with_snapshot
将 `shell -lc "<script>"` 重写为：
```bash
user_shell -c ". SNAPSHOT (best effort); exec shell -c <script>"
```

支持环境变量覆盖的复杂逻辑：
```bash
__CODEX_SNAPSHOT_OVERRIDE_SET_0="${PATH+x}"
__CODEX_SNAPSHOT_OVERRIDE_0="${PATH-}"

if . '/path/to/snapshot.sh' >/dev/null 2>&1; then :; fi

if [ -n "${__CODEX_SNAPSHOT_OVERRIDE_SET_0}" ]; then
    export PATH="${__CODEX_SNAPSHOT_OVERRIDE_0}"
else
    unset PATH
fi

exec '/bin/bash' -c 'echo hello'
```

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `mod.rs` | 181 | 共享工具函数、模块导出 |
| `shell.rs` | 266 | `ShellRuntime` 实现 |
| `apply_patch.rs` | 220 | `ApplyPatchRuntime` 实现 |
| `unified_exec.rs` | 290 | `UnifiedExecRuntime` 实现 |
| `shell/unix_escalation.rs` | 1155 | Unix 特权提升实现 |
| `shell/zsh_fork_backend.rs` | 136 | Zsh-Fork 后端适配器 |

### 测试文件

| 文件 | 行数 | 测试覆盖 |
|------|------|----------|
| `mod_tests.rs` | 398 | `maybe_wrap_shell_lc_with_snapshot` 各种场景 |
| `apply_patch_tests.rs` | 70 | 审批策略、Guardian 请求构建 |
| `shell/unix_escalation_tests.rs` | 841 | 策略评估、权限提升、命令解析 |

### 关键代码路径

1. **审批流程**：
   - `shell.rs:129-193` - `Approvable<ShellRequest>` 实现
   - `apply_patch.rs:122-198` - `Approvable<ApplyPatchRequest>` 实现
   - `unified_exec.rs:96-174` - `Approvable<UnifiedExecRequest>` 实现

2. **执行流程**：
   - `shell.rs:217-265` - `ToolRuntime::run` 实现
   - `apply_patch.rs:200-215` - 补丁执行
   - `unified_exec.rs:189-289` - PTY 命令执行

3. **Zsh-Fork 特权提升**：
   - `unix_escalation.rs:90-222` - `try_run_zsh_fork`
   - `unix_escalation.rs:309-613` - `CoreShellActionProvider` 策略实现
   - `unix_escalation.rs:1009-1078` - `prepare_sandboxed_exec`

4. **命令解析**：
   - `unix_escalation.rs:1087-1110` - `extract_shell_script`
   - `unix_escalation.rs:1147-1151` - `join_program_and_argv`

---

## 依赖与外部交互

### 内部依赖

```
runtimes/
├── 依赖 ../sandboxing.rs (ToolRuntime, Approvable, Sandboxable traits)
├── 依赖 ../orchestrator.rs (ToolOrchestrator)
├── 依赖 ../handlers/shell.rs (ShellHandler 调用 ShellRuntime)
├── 依赖 ../handlers/apply_patch.rs (ApplyPatchHandler 调用 ApplyPatchRuntime)
├── 依赖 ../handlers/unified_exec.rs (UnifiedExecHandler 调用 UnifiedExecRuntime)
├── 依赖 ../../sandboxing/ (CommandSpec, SandboxManager, ExecRequest)
├── 依赖 ../../exec.rs (ExecToolCallOutput, ExecExpiration)
├── 依赖 ../../guardian.rs (Guardian 审批路由)
└── 依赖 ../../shell.rs (Shell, ShellType)
```

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `codex-shell-escalation` | Unix 特权提升协议和服务器 |
| `codex-execpolicy` | 执行策略解析和评估 |
| `codex-protocol` | 协议类型（ReviewDecision, AskForApproval 等）|
| `codex-network-proxy` | 网络代理配置 |
| `codex-apply-patch` | 补丁解析和应用 |
| `codex-utils-absolute-path` | 绝对路径处理 |

### 系统依赖

- **Unix 特有**：`codex-execve-wrapper` 可执行文件
- **Bash Patch**：支持 `EXEC_WRAPPER` 和 `BASH_EXEC_WRAPPER` 的补丁版 Bash
- **Zsh**：Zsh-Fork 后端需要 Zsh shell

---

## 风险、边界与改进建议

### 已知风险

1. **命令注入风险**
   - `maybe_wrap_shell_lc_with_snapshot` 中的 shell 脚本生成需要严格的单引号转义
   - 风险点：`shell_single_quote` 函数必须正确处理所有特殊字符
   - 缓解：现有测试覆盖基本场景，但复杂嵌套引号可能存在问题

2. **权限提升绕过**
   - `ENABLE_INTERCEPTED_EXEC_POLICY_SHELL_WRAPPER_PARSING` 默认禁用
   - 启用后可能通过 shell 包装器绕过路径敏感的策略规则
   - 代码注释：`Shell-wrapper parsing is weaker than direct exec interception`

3. **环境变量泄漏**
   - `build_override_exports` 生成临时变量名（`__CODEX_SNAPSHOT_OVERRIDE_*`）
   - 如果子进程读取环境变量，可能暴露原始值
   - 缓解：使用 `unset` 清理临时变量

4. **超时竞争条件**
   - `Stopwatch` 创建和 escalation 服务器启动之间存在时间窗口
   - 代码注释明确说明：`Stopwatch starts immediately upon creation`

### 边界条件

1. **平台限制**
   - Zsh-Fork 功能仅支持 Unix 平台
   - Windows 平台使用传统执行路径
   - `#[cfg(unix)]` 条件编译隔离平台特有代码

2. **审批策略冲突**
   - `AskForApproval::Never` + 需要审批的命令 = 拒绝执行
   - `AskForApproval::Granular` 需要仔细配置各个子标志

3. **并发限制**
   - `execve_session_approvals` 使用 `RwLock` 保护
   - 高并发场景可能成为瓶颈

### 改进建议

1. **增强测试覆盖**
   - 添加更多边界情况测试（空命令、超长命令、特殊字符）
   - 添加并发压力测试
   - 测试不同审批策略组合

2. **代码简化**
   - `unix_escalation.rs` 超过 1000 行，考虑拆分为多个模块
   - `CoreShellActionProvider` 包含过多字段，考虑使用 Builder 模式

3. **性能优化**
   - `execve_session_approvals` 可考虑使用 `DashMap` 替代 `RwLock<HashMap>`
   - 策略评估结果可添加缓存

4. **可观测性**
   - 添加更多结构化日志（当前主要使用 `tracing::debug!`）
   - 暴露指标：审批延迟、特权提升次数、缓存命中率

5. **安全加固**
   - 审计所有 `unwrap()` 和 `expect()` 调用
   - 添加命令注入 fuzz 测试
   - 考虑使用更严格的 shell 解析器替代正则/字符串操作

6. **文档完善**
   - 添加架构图说明各组件交互
   - 补充 Zsh-Fork 协议详细文档
   - 添加故障排查指南

---

## 总结

`codex-rs/core/src/tools/runtimes` 是 Codex 工具执行系统的核心执行层，负责将高层工具调用转换为实际的系统命令执行。其设计亮点包括：

1. **清晰的 trait 抽象**：`ToolRuntime`、`Approvable`、`Sandboxable` 分离关注点
2. **灵活的权限模型**：支持多种审批策略和权限提升路径
3. **Unix 特权提升**：创新的 Zsh-Fork 机制实现细粒度权限控制
4. **全面的测试覆盖**：单元测试和集成测试覆盖主要场景

该模块的复杂性主要来自需要协调多个子系统（审批、沙箱、策略、网络），建议维护时重点关注安全边界和并发正确性。
