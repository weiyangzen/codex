# shell.rs 深入研究

## 场景与职责

`shell.rs` 实现了 Codex 的 **Shell 运行时**（`ShellRuntime`），负责执行传统的 shell 命令（`shell` 和 `shell_command` 工具）。它是 Codex 执行外部命令的核心组件，处理命令审批、沙箱选择、执行和重试的完整生命周期。

**核心职责：**
1. **命令执行**：在沙箱环境中执行 shell 命令
2. **审批管理**：集成审批流程，处理用户授权
3. **后端选择**：支持多种执行后端（Generic、ShellCommandClassic、ShellCommandZshFork）
4. **Shell 快照集成**：利用用户 shell 环境快照提供一致的执行环境
5. **权限管理**：处理额外权限请求和审批

**架构定位：**
- 位于工具运行时层（`tools/runtimes/`）
- 被 `ShellHandler` 和 `ShellCommandHandler`（`handlers/shell.rs`）调用
- 通过 `ToolOrchestrator` 进行审批和沙箱管理
- 支持多种执行后端，包括实验性的 ZshFork 后端

---

## 功能点目的

### 1. ShellRequest - 请求数据结构

```rust
pub struct ShellRequest {
    pub command: Vec<String>,           // 命令行（已分词）
    pub cwd: PathBuf,                   // 工作目录
    pub timeout_ms: Option<u64>,        // 超时（毫秒）
    pub env: HashMap<String, String>,   // 环境变量
    pub explicit_env_overrides: HashMap<String, String>, // 显式覆盖的环境变量
    pub network: Option<NetworkProxy>,  // 网络代理配置
    pub sandbox_permissions: SandboxPermissions, // 沙箱权限
    pub additional_permissions: Option<PermissionProfile>, // 额外权限
    #[cfg(unix)]
    pub additional_permissions_preapproved: bool, // 额外权限是否已预批准
    pub justification: Option<String>,  // 执行理由
    pub exec_approval_requirement: ExecApprovalRequirement, // 执行审批要求
}
```

**设计目的：**
- 封装单次 shell 执行的所有上下文
- 支持网络代理（用于托管网络环境）
- 支持额外权限的动态请求和审批

### 2. ShellRuntimeBackend - 后端选择枚举

```rust
pub(crate) enum ShellRuntimeBackend {
    #[default]
    Generic,              // 通用运行时路径（默认）
    ShellCommandClassic,  // shell_command 工具的传统后端
    ShellCommandZshFork,  // 实验性 ZshFork 后端
}
```

**设计区别：**
- `Generic`: 标准 shell 工具路径，无特殊后端行为
- `ShellCommandClassic`: `shell_command` 的传统路径，标准执行流程
- `ShellCommandZshFork`: 使用 Zsh fork + `codex-shell-escalation` 适配器，支持更细粒度的权限控制

### 3. ApprovalKey - 审批缓存键

```rust
pub(crate) struct ApprovalKey {
    command: Vec<String>,
    cwd: PathBuf,
    sandbox_permissions: SandboxPermissions,
    additional_permissions: Option<PermissionProfile>,
}
```

**设计目的：**
- 唯一标识需要审批的命令配置
- 用于审批缓存，避免重复询问用户
- 包含命令、工作目录和权限配置

### 4. ShellRuntime - 运行时实现

实现了三个核心 trait：

#### `Sandboxable` - 沙箱偏好
```rust
impl Sandboxable for ShellRuntime {
    fn sandbox_preference(&self) -> SandboxablePreference { SandboxablePreference::Auto }
    fn escalate_on_failure(&self) -> bool { true }
}
```

#### `Approvable<ShellRequest>` - 审批逻辑

**审批键生成：**
```rust
fn approval_keys(&self, req: &ShellRequest) -> Vec<Self::ApprovalKey> {
    vec![ApprovalKey {
        command: canonicalize_command_for_approval(&req.command),
        cwd: req.cwd.clone(),
        sandbox_permissions: req.sandbox_permissions,
        additional_permissions: req.additional_permissions.clone(),
    }]
}
```

- 使用 `canonicalize_command_for_approval` 规范化命令（如去除注释、标准化空白）
- 单键审批（与 `apply_patch` 的多键不同）

**审批流程：**
1. Guardian 路由检查
2. 缓存审批（`with_cached_approval`）
3. 命令审批请求（`request_command_approval`）

**首次尝试沙箱覆盖：**
```rust
fn sandbox_mode_for_first_attempt(&self, req: &ShellRequest) -> SandboxOverride {
    sandbox_override_for_first_attempt(req.sandbox_permissions, &req.exec_approval_requirement)
}
```

#### `ToolRuntime<ShellRequest, ExecToolCallOutput>` - 执行逻辑

**网络审批规范：**
```rust
fn network_approval_spec(&self, req: &ShellRequest, _ctx: &ToolCtx) -> Option<NetworkApprovalSpec> {
    req.network.as_ref()?;
    Some(NetworkApprovalSpec {
        network: req.network.clone(),
        mode: NetworkApprovalMode::Immediate,  // 立即模式
    })
}
```

**执行流程：**
1. **Shell 快照包装**：`maybe_wrap_shell_lc_with_snapshot`
2. **PowerShell UTF-8 处理**：如果启用 `PowershellUtf8` 特性，添加 BOM
3. **ZshFork 后端尝试**：如果配置为 `ShellCommandZshFork`，尝试使用 ZshFork 后端
4. **标准执行**：构建 `CommandSpec`，通过 `SandboxAttempt` 执行

---

## 具体技术实现

### 执行流程详解

```rust
async fn run(&mut self, req: &ShellRequest, attempt: &SandboxAttempt<'_>, ctx: &ToolCtx) 
    -> Result<ExecToolCallOutput, ToolError> {
    // 1. 获取用户 shell 并包装命令
    let session_shell = ctx.session.user_shell();
    let command = maybe_wrap_shell_lc_with_snapshot(
        &req.command,
        session_shell.as_ref(),
        &req.cwd,
        &req.explicit_env_overrides,
    );
    
    // 2. PowerShell UTF-8 处理
    let command = if matches!(session_shell.shell_type, ShellType::PowerShell)
        && ctx.session.features().enabled(Feature::PowershellUtf8) {
        prefix_powershell_script_with_utf8(&command)
    } else {
        command
    };
    
    // 3. ZshFork 后端尝试
    if self.backend == ShellRuntimeBackend::ShellCommandZshFork {
        match zsh_fork_backend::maybe_run_shell_command(req, attempt, ctx, &command).await? {
            Some(out) => return Ok(out),
            None => { /* 回退到标准执行 */ }
        }
    }
    
    // 4. 标准执行流程
    let spec = build_command_spec(&command, &req.cwd, &req.env, ...)?;
    let env = attempt.env_for(spec, req.network.as_ref())?;
    let out = execute_env(env, Self::stdout_stream(ctx)).await?;
    Ok(out)
}
```

### ZshFork 后端集成

**条件检查：**
```rust
if self.backend == ShellRuntimeBackend::ShellCommandZshFork {
    match zsh_fork_backend::maybe_run_shell_command(req, attempt, ctx, &command).await? {
        Some(out) => return Ok(out),
        None => {
            tracing::warn!(
                "ZshFork backend specified, but conditions for using it were not met, falling back to normal execution",
            );
        }
    }
}
```

**回退机制：**
- ZshFork 有前置条件（如 Zsh 可用性、配置正确性）
- 条件不满足时自动回退到标准执行
- 记录警告日志便于调试

### 审批上下文构建

```rust
fn start_approval_async<'a>(...) -> BoxFuture<'a, ReviewDecision> {
    let keys = self.approval_keys(req);
    let command = req.command.clone();
    let cwd = req.cwd.clone();
    let retry_reason = ctx.retry_reason.clone();
    let reason = retry_reason.clone().or_else(|| req.justification.clone());
    
    Box::pin(async move {
        if routes_approval_to_guardian(turn) {
            // Guardian 模式：构建 GuardianApprovalRequest::Shell
            return review_approval_request(session, turn, GuardianApprovalRequest::Shell { ... }, retry_reason).await;
        }
        // 标准模式：使用缓存审批
        with_cached_approval(&session.services, "shell", keys, || async move {
            session.request_command_approval(turn, call_id, ..., ctx.network_approval_context.clone(), ...).await
        }).await
    })
}
```

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|------|------|
| `shell.rs` | 本文件，Shell 运行时实现 |
| `shell/zsh_fork_backend.rs` | ZshFork 后端实现 |
| `shell/unix_escalation.rs` | Unix 权限提升逻辑 |
| `handlers/shell.rs` | Handler 层，解析输入并调用运行时 |
| `orchestrator.rs` | 编排器，管理审批→沙箱→执行流程 |

### 调用链

```
[Model] shell/shell_command tool call
    ↓
[ShellHandler::handle / ShellCommandHandler::handle] (handlers/shell.rs)
    ↓
[ShellHandler::run_exec_like] (handlers/shell.rs:320)
    ↓
[ShellRequest 构建]
    ↓
[ToolOrchestrator::run] (orchestrator.rs:100)
    ↓
[ShellRuntime::start_approval_async] (shell.rs:141)
    ↓ (if approved)
[ShellRuntime::run] (shell.rs:217)
    ↓
[maybe_wrap_shell_lc_with_snapshot] (mod.rs:68)
    ↓
[build_command_spec → execute_env] (sandboxing/mod.rs:727)
```

### 依赖模块

| 模块 | 用途 |
|------|------|
| `crate::command_canonicalization` | 命令规范化（用于审批键） |
| `crate::exec::ExecToolCallOutput` | 执行输出结构 |
| `crate::guardian` | Guardian 审批集成 |
| `crate::powershell` | PowerShell UTF-8 处理 |
| `crate::sandboxing` | 沙箱执行 |
| `crate::shell::ShellType` | Shell 类型枚举 |
| `crate::tools::network_approval` | 网络审批 |
| `crate::tools::runtimes::{build_command_spec, maybe_wrap_shell_lc_with_snapshot}` | 共享工具函数 |

---

## 依赖与外部交互

### 外部 crate

| Crate | 用途 |
|-------|------|
| `codex_network_proxy::NetworkProxy` | 网络代理配置 |
| `codex_protocol::models::PermissionProfile` | 权限配置 |
| `codex_protocol::protocol::ReviewDecision` | 审批决策 |
| `futures::future::BoxFuture` | 异步 trait 方法 |

### 特性标志

| 特性 | 用途 |
|------|------|
| `Feature::PowershellUtf8` | 为 PowerShell 脚本添加 UTF-8 BOM |
| `Feature::ExecPermissionApprovals` | 启用执行权限审批 |

### 平台特定代码

```rust
#[cfg(unix)]
pub(crate) mod unix_escalation;
pub(crate) mod zsh_fork_backend;
```

- `unix_escalation`: Unix 特有的权限提升逻辑
- `zsh_fork_backend`: ZshFork 后端（主要面向 Unix）

---

## 风险、边界与改进建议

### 风险点

1. **ZshFork 后端复杂性**
   - **风险**：ZshFork 后端增加了执行路径的复杂性
   - **现状**：有回退机制，但增加了维护负担
   - **建议**：考虑逐步稳定化或简化 ZshFork 逻辑

2. **命令规范化安全性**
   - **风险**：`canonicalize_command_for_approval` 可能无法正确处理所有边缘情况
   - **现状**：用于审批缓存键，不影响实际执行
   - **建议**：审计规范化逻辑，确保不会合并不同语义的命令

3. **PowerShell 处理**
   - **风险**：`prefix_powershell_script_with_utf8` 可能不适用于所有 PowerShell 版本
   - **现状**：由特性标志控制
   - **建议**：添加版本检测或配置选项

4. **环境变量传递**
   - **风险**：`explicit_env_overrides` 和 `env` 的交互可能复杂
   - **现状**：通过 shell 快照包装处理
   - **建议**：添加更多文档和测试明确优先级

### 边界条件

| 边界 | 处理 |
|------|------|
| 空命令 | `build_command_spec` 返回错误 |
| 无网络配置 | `network_approval_spec` 返回 `None` |
| ZshFork 条件不满足 | 回退到标准执行 |
| 非 PowerShell | 跳过 UTF-8 前缀处理 |

### 改进建议

1. **后端选择透明化**
   - 当前：ZshFork 回退时仅记录警告
   - 建议：向用户/模型报告后端选择决策

2. **审批键优化**
   - 当前：包含完整命令向量
   - 建议：考虑哈希化减少内存占用

3. **错误信息增强**
   - 当前：沙箱拒绝时返回通用错误
   - 建议：提供更具体的重试建议

4. **测试覆盖**
   - 当前：依赖 Handler 层测试
   - 建议：添加独立的运行时单元测试

5. **文档完善**
   - 当前：代码注释较清晰
   - 建议：添加架构文档说明各后端的选择场景

### 与相关组件的协调

- **与 `unified_exec.rs` 的关系**：两者功能重叠，`unified_exec` 更现代，支持 PTY
- **与 `apply_patch.rs` 的关系**：`apply_patch` 通过 shell 执行补丁应用，但审批逻辑不同
- **与 `orchestrator.rs` 的关系**：所有运行时共享相同的编排逻辑
