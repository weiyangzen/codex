# Research: codex-rs/core/src/tools/runtimes

## 概述

`runtimes` 目录是 Codex Core 工具执行运行时的核心实现，负责管理各类工具（shell、apply_patch、unified_exec）的审批流程、沙箱隔离和实际执行。该模块通过统一的 `ToolRuntime` trait 抽象，为不同工具提供一致的执行语义：审批 → 沙箱选择 → 尝试执行 → 失败时升级沙箱策略重试。

---

## 场景与职责

### 核心职责

1. **工具执行运行时管理**: 为 shell 命令执行、补丁应用、统一执行接口提供具体的运行时实现
2. **审批流程编排**: 集成用户审批、缓存审批、Guardian 模式审批等多种审批机制
3. **沙箱策略执行**: 协调 Seatbelt (macOS)、Landlock (Linux)、Windows Sandbox 等平台沙箱
4. **权限升级管理**: 处理从沙箱执行到无沙箱执行的自动/手动升级流程
5. **Zsh Fork 后端支持**: 提供 Unix 平台下的 zsh-fork 权限升级机制

### 使用场景

| 场景 | 运行时 | 说明 |
|------|--------|------|
| 普通 shell 命令 | `ShellRuntime` | 执行 `shell` 工具调用的命令 |
| shell_command 工具 | `ShellRuntime` + backend | 支持 Classic 和 ZshFork 两种后端 |
| 统一执行接口 | `UnifiedExecRuntime` | TUI 等场景的长会话 PTY 执行 |
| 补丁应用 | `ApplyPatchRuntime` | 执行代码补丁应用，自调用 codex 二进制 |

---

## 功能点目的

### 1. ShellRuntime (shell.rs)

**目的**: 执行 shell 请求，支持多种后端选择

**关键特性**:
- `ShellRuntimeBackend` 枚举支持三种模式:
  - `Generic`: 通用运行时路径，无特殊后端行为
  - `ShellCommandClassic`: 标准 shell 运行时流程
  - `ShellCommandZshFork`: Unix 平台 zsh-fork + 权限升级适配器
- 支持快照包装 (`maybe_wrap_shell_lc_with_snapshot`): 在 zsh/bash/sh 登录 shell 执行前加载环境快照
- PowerShell UTF-8 前缀处理 (Windows)

### 2. UnifiedExecRuntime (unified_exec.rs)

**目的**: 为统一执行接口（如 TUI）提供审批和沙箱编排

**关键特性**:
- 支持 TTY/PTY 执行模式
- 延迟网络审批模式 (`NetworkApprovalMode::Deferred`)
- ZshFork 后端集成用于长会话执行
- 与 `UnifiedExecProcessManager` 协作管理进程生命周期

### 3. ApplyPatchRuntime (apply_patch.rs)

**目的**: 执行已验证的代码补丁

**关键特性**:
- 自调用 codex 二进制 (`codex --codex-run-as-apply-patch`) 执行补丁
- 复用上游审批决策（`assess_patch_safety` 已完成验证）
- 支持 Guardian 模式审批
- 按文件路径缓存审批结果

### 4. Unix Escalation (shell/unix_escalation.rs)

**目的**: Unix 平台下的 zsh-fork 权限升级实现

**关键特性**:
- `CoreShellActionProvider`: 实现 `EscalationPolicy` trait，决定何时升级执行
- `CoreShellCommandExecutor`: 实现 `ShellCommandExecutor` trait，实际执行命令
- 策略评估: 基于 `codex_execpolicy` 的策略规则匹配
- Skill 脚本检测: 自动识别并处理 Skill 目录下的脚本
- 会话级审批缓存 (`execve_session_approvals`)

### 5. Zsh Fork Backend (shell/zsh_fork_backend.rs)

**目的**: 跨平台的 zsh-fork 后端适配层

**关键特性**:
- 平台条件编译 (`#[cfg(unix)]` / `#[cfg(not(unix))]`)
- `ZshForkSpawnLifecycle`: 管理 zsh-fork 会话的生命周期和文件描述符继承

---

## 具体技术实现

### 核心 Trait 体系

```rust
// ToolRuntime: 工具运行时的核心抽象
trait ToolRuntime<Req, Out>: Approvable<Req> + Sandboxable {
    fn network_approval_spec(&self, req: &Req, ctx: &ToolCtx) -> Option<NetworkApprovalSpec>;
    async fn run(&mut self, req: &Req, attempt: &SandboxAttempt<'_>, ctx: &ToolCtx) 
        -> Result<Out, ToolError>;
}

// Approvable: 审批能力
trait Approvable<Req> {
    type ApprovalKey: Hash + Eq + Clone + Debug + Serialize;
    fn approval_keys(&self, req: &Req) -> Vec<Self::ApprovalKey>;
    fn start_approval_async<'a>(&'a mut self, req: &'a Req, ctx: ApprovalCtx<'a>) 
        -> BoxFuture<'a, ReviewDecision>;
    fn exec_approval_requirement(&self, req: &Req) -> Option<ExecApprovalRequirement>;
    fn sandbox_mode_for_first_attempt(&self, req: &Req) -> SandboxOverride;
}

// Sandboxable: 沙箱偏好
trait Sandboxable {
    fn sandbox_preference(&self) -> SandboxablePreference;
    fn escalate_on_failure(&self) -> bool;
}
```

### 审批流程

```
┌─────────────────┐
│  ToolOrchestrator.run()
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────┐
│ ExecApprovalRequirement  │     │  Skip / Forbidden │
│ 评估                    │────▶│  直接返回         │
└────────┬────────┘     └─────────────────┘
         │ NeedsApproval
         ▼
┌─────────────────┐     ┌─────────────────┐
│ Approvable::    │────▶│  Guardian 模式?  │
│ start_approval_async    │     │                 │
└─────────────────┘     └────────┬────────┘
                                 │
                    ┌────────────┴────────────┐
                    ▼                         ▼
           ┌─────────────────┐       ┌─────────────────┐
           │ GuardianApproval│       │ with_cached_approval
           │ review_approval_│       │ 缓存检查 → 用户审批 │
           │ request()       │       │                 │
           └─────────────────┘       └─────────────────┘
```

### Zsh Fork 执行流程 (Unix)

```
ShellRuntime::run() / UnifiedExecRuntime::run()
         │
         ▼
┌─────────────────┐
│ backend ==      │────▶ 否 ──▶ 标准沙箱执行
│ ShellCommandZshFork? │
└────────┬────────┘
         │ 是
         ▼
┌─────────────────┐
│ zsh_fork_backend::  │
│ maybe_run_shell_    │────▶ 条件不满足 ──▶ 回退到标准执行
│ command() /         │      (警告日志)
│ maybe_prepare_unified_exec()
└────────┬────────┘
         │ 条件满足
         ▼
┌─────────────────┐
│ unix_escalation::   │
│ try_run_zsh_fork()  │
│ / prepare_unified_  │
│ exec_zsh_fork()     │
└────────┬────────┘
         ▼
┌─────────────────┐
│ EscalateServer::exec()  │
│ (codex_shell_escalation) │
│ - 启动 zsh 子进程        │
│ - 拦截 execve 调用       │
│ - 策略评估               │
│ - 必要时提示用户         │
└─────────────────┘
```

### 关键数据结构

#### ShellRequest
```rust
pub struct ShellRequest {
    pub command: Vec<String>,           // 命令及参数
    pub cwd: PathBuf,                   // 工作目录
    pub timeout_ms: Option<u64>,        // 超时时间
    pub env: HashMap<String, String>,   // 环境变量
    pub explicit_env_overrides: HashMap<String, String>, // 显式覆盖的环境变量
    pub network: Option<NetworkProxy>,  // 网络代理配置
    pub sandbox_permissions: SandboxPermissions, // 沙箱权限模式
    pub additional_permissions: Option<PermissionProfile>, // 额外权限
    pub additional_permissions_preapproved: bool, // 额外权限是否已预批准
    pub justification: Option<String>,  // 执行理由
    pub exec_approval_requirement: ExecApprovalRequirement, // 审批要求
}
```

#### UnifiedExecRequest
```rust
pub struct UnifiedExecRequest {
    pub command: Vec<String>,
    pub cwd: PathBuf,
    pub env: HashMap<String, String>,
    pub explicit_env_overrides: HashMap<String, String>,
    pub network: Option<NetworkProxy>,
    pub tty: bool,                      // 关键区别: 支持 TTY 模式
    pub sandbox_permissions: SandboxPermissions,
    pub additional_permissions: Option<PermissionProfile>,
    pub additional_permissions_preapproved: bool,
    pub justification: Option<String>,
    pub exec_approval_requirement: ExecApprovalRequirement,
}
```

#### ApplyPatchRequest
```rust
pub struct ApplyPatchRequest {
    pub action: ApplyPatchAction,       // 补丁动作
    pub file_paths: Vec<AbsolutePathBuf>, // 受影响的文件路径
    pub changes: HashMap<PathBuf, FileChange>, // 变更内容
    pub exec_approval_requirement: ExecApprovalRequirement,
    pub sandbox_permissions: SandboxPermissions,
    pub additional_permissions: Option<PermissionProfile>,
    pub permissions_preapproved: bool,
    pub timeout_ms: Option<u64>,
    pub codex_exe: Option<PathBuf>,     // codex 可执行文件路径
}
```

### 快照包装机制 (mod.rs)

```rust
/// POSIX-only: 将 shell -lc "<script>" 包装为在用户 shell 中执行
/// 格式: shell -lc "<script>" 
///   => user_shell -c ". SNAPSHOT; exec shell -c <script>"
pub(crate) fn maybe_wrap_shell_lc_with_snapshot(
    command: &[String],
    session_shell: &Shell,
    cwd: &Path,
    explicit_env_overrides: &HashMap<String, String>,
) -> Vec<String>
```

**处理逻辑**:
1. 检查是否为 POSIX 平台
2. 检查会话 shell 是否有快照配置
3. 检查快照文件是否存在
4. 检查命令 CWD 是否与快照 CWD 匹配
5. 检查命令格式是否为 `[shell, "-lc", script]`
6. 生成包装脚本: 先 source 快照，再执行原命令
7. 处理显式环境变量覆盖（安全地不将敏感值嵌入脚本）

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 | 关键类型/函数 |
|------|------|---------------|
| `mod.rs` | 模块入口，共享工具函数 | `build_command_spec`, `maybe_wrap_shell_lc_with_snapshot` |
| `shell.rs` | Shell 运行时实现 | `ShellRuntime`, `ShellRequest`, `ApprovalKey` |
| `unified_exec.rs` | 统一执行运行时 | `UnifiedExecRuntime`, `UnifiedExecRequest` |
| `apply_patch.rs` | 补丁应用运行时 | `ApplyPatchRuntime`, `ApplyPatchRequest` |
| `shell/unix_escalation.rs` | Unix 权限升级 | `CoreShellActionProvider`, `CoreShellCommandExecutor` |
| `shell/zsh_fork_backend.rs` | ZshFork 后端适配 | `maybe_run_shell_command`, `maybe_prepare_unified_exec` |

### 测试文件

| 文件 | 测试内容 |
|------|----------|
| `mod_tests.rs` | 快照包装功能测试（12 个测试用例） |
| `apply_patch_tests.rs` | ApplyPatch 审批策略测试 |
| `shell/unix_escalation_tests.rs` | Unix 权限升级逻辑测试（20+ 测试用例） |

### 调用关系

```
codex-rs/core/src/tools/
├── handlers/shell.rs          # 调用 ShellRuntime
├── handlers/apply_patch.rs    # 调用 ApplyPatchRuntime
├── orchestrator.rs            # 统一编排所有运行时
├── sandboxing.rs              # 定义核心 trait (ToolRuntime, Approvable, Sandboxable)
└── runtimes/
    ├── mod.rs                 # 共享函数
    ├── shell.rs               # ShellRuntime
    ├── unified_exec.rs        # UnifiedExecRuntime
    ├── apply_patch.rs         # ApplyPatchRuntime
    └── shell/
        ├── unix_escalation.rs # Unix 权限升级
        └── zsh_fork_backend.rs # ZshFork 适配
```

---

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::sandboxing` | `CommandSpec`, `SandboxManager`, `SandboxPermissions`, `execute_env` |
| `crate::exec` | `ExecToolCallOutput`, `ExecExpiration`, `SandboxType` |
| `crate::guardian` | Guardian 模式审批路由 (`routes_approval_to_guardian`, `review_approval_request`) |
| `crate::tools::sandboxing` | 核心 trait 定义 (`ToolRuntime`, `Approvable`, `Sandboxable`, `ToolCtx`) |
| `crate::tools::orchestrator` | `ToolOrchestrator` 统一编排执行 |
| `crate::skills` | Skill 脚本检测和元数据 (`SkillMetadata`) |
| `crate::exec_policy` | 执行策略评估 |

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_shell_escalation` | Zsh fork 权限升级核心实现 (`EscalateServer`, `EscalationPolicy`, `ShellCommandExecutor`) |
| `codex_execpolicy` | 执行策略解析和评估 (`Policy`, `Decision`, `RuleMatch`) |
| `codex_protocol` | 协议类型 (`ReviewDecision`, `AskForApproval`, `PermissionProfile`, `SandboxPolicy`) |
| `codex_apply_patch` | 补丁解析和验证 (`ApplyPatchAction`, `maybe_parse_apply_patch_verified`) |
| `codex_network_proxy` | 网络代理配置 (`NetworkProxy`) |
| `codex_utils_absolute_path` | 绝对路径类型 (`AbsolutePathBuf`) |

### 环境变量

| 变量 | 来源 | 用途 |
|------|------|------|
| `CODEX_ESCALATE_SOCKET` | `codex_shell_escalation` | Zsh fork 升级通信 socket |
| `EXEC_WRAPPER` / `BASH_EXEC_WRAPPER` | 沙箱执行 | 执行包装器路径 |

---

## 风险、边界与改进建议

### 已知风险

1. **平台差异复杂性**
   - ZshFork 仅支持 Unix 平台，Windows 完全回退到标准执行
   - macOS Seatbelt 和 Linux Landlock 的行为差异需要仔细处理
   - 代码中存在大量 `#[cfg(unix)]` / `#[cfg(target_os = "macos")]` 条件编译

2. **权限升级的安全边界**
   - `ShellCommandZshFork` 后端需要 `shell_zsh_path` 和 `main_execve_wrapper_exe` 配置
   - 配置缺失时静默回退到标准执行（有警告日志）
   - 权限升级绕过了沙箱，依赖策略评估和用户审批保证安全

3. **审批缓存的粒度**
   - `apply_patch` 按文件路径缓存，`shell` 按命令规范化后的 key 缓存
   - Skill 脚本使用 `execve_session_approvals` 会话级缓存
   - 缓存 key 的设计影响用户体验（过于严格导致重复审批，过于宽松有安全风险）

4. **快照包装的局限性**
   - 仅支持 `[shell, "-lc", script]` 格式的命令
   - CWD 必须完全匹配（已处理 `.` 别名）
   - 单引号转义依赖 `shell_single_quote` 函数

### 边界情况

1. **超时处理**: ZshFork 使用 `Stopwatch` 结构管理超时，支持暂停等待用户审批的时间
2. **网络审批**: UnifiedExec 使用延迟审批模式，ShellRuntime 使用立即审批模式
3. **空命令处理**: `build_command_spec` 会拒绝空命令数组
4. **环境变量覆盖**: 敏感值（如 API keys）通过外部 env 传递，不嵌入脚本

### 改进建议

1. **代码组织**
   - `unix_escalation.rs` 超过 1000 行，可考虑将 `CoreShellActionProvider` 和 `CoreShellCommandExecutor` 拆分为独立模块
   - 策略评估逻辑 (`evaluate_intercepted_exec_policy`) 可考虑提取到独立模块

2. **错误处理**
   - 部分错误场景使用 `tracing::warn!` 记录后静默回退，可考虑增加更严格的错误传播选项
   - `ToolError::Rejected` 的错误信息可进一步标准化

3. **测试覆盖**
   - Windows 平台的测试覆盖有限（大部分 ZshFork 测试是 Unix-only）
   - 可考虑增加集成测试验证完整的审批 → 执行 → 升级流程

4. **文档**
   - ZshFork 的工作流程（execve 拦截、策略评估、用户提示）可补充架构图
   - Skill 脚本的权限继承规则可进一步文档化

5. **性能优化**
   - `execve_session_approvals` 使用 `RwLock<HashMap<...>>`，在高并发场景可能成为瓶颈
   - 策略评估每次执行都重新读取 `exec_policy`，可考虑更激进的缓存策略

---

## 附录：关键常量

```rust
// unix_escalation.rs
const PROMPT_CONFLICT_REASON: &str = "approval required by policy, but AskForApproval is set to Never";
const REJECT_SANDBOX_APPROVAL_REASON: &str = "approval required by policy, but AskForApproval::Granular.sandbox_approval is false";
const REJECT_RULES_APPROVAL_REASON: &str = "approval required by policy rule, but AskForApproval::Granular.rules is false";
const REJECT_SKILL_APPROVAL_REASON: &str = "approval required by skill, but AskForApproval::Granular.skill_approval is false";

// 默认禁用 shell wrapper 解析，因为路径敏感规则依赖 execve 拦截
const ENABLE_INTERCEPTED_EXEC_POLICY_SHELL_WRAPPER_PARSING: bool = false;
```

---

*Generated: 2026-03-21*
*Researcher: Kimi Code CLI (k2p5)*
