# shell.rs 研究文档

## 场景与职责

`shell.rs` 实现了 Codex 的 shell 命令执行工具，是 Codex 与操作系统交互的核心组件。它支持两种主要工具：
1. **shell**: 执行任意 shell 命令（通过 shell 解释器）
2. **shell_command**: 执行特定 shell 命令（支持登录 shell 选项）

该模块负责命令执行的全生命周期管理，包括权限验证、沙箱控制、执行策略和输出处理。

## 功能点目的

### 1. Shell 工具 (ShellHandler)
- **通用命令执行**: 通过系统 shell 执行任意命令
- **多 Payload 支持**: 支持 `ToolPayload::Function` 和 `ToolPayload::LocalShell`
- **变异检测**: 通过 `is_mutating` 方法检测命令是否会修改系统状态

### 2. ShellCommand 工具 (ShellCommandHandler)
- **特定 shell 执行**: 使用特定 shell（bash/zsh/powershell）执行命令
- **登录 shell 支持**: 可选使用登录 shell 环境
- **后端选择**: 支持 Classic 和 ZshFork 两种后端

### 3. 执行参数构建
- **ExecParams 转换**: 将工具参数转换为内部执行参数
- **环境变量**: 创建包含依赖环境变量的执行环境
- **工作目录解析**: 解析相对路径为绝对路径

### 4. 权限和沙箱控制
- **额外权限应用**: 应用用户授予的额外权限
- **沙箱策略**: 根据配置应用不同的沙箱级别
- **执行审批**: 根据审批策略决定是否需要用户确认

### 5. 特殊处理
- **apply_patch 拦截**: 检测并拦截 apply_patch 命令，使用专用处理器
- **技能隐式调用**: 检测并触发隐式技能调用

## 具体技术实现

### 核心数据结构

```rust
pub struct ShellHandler;
pub struct ShellCommandHandler {
    backend: ShellCommandBackend,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ShellCommandBackend {
    Classic,
    ZshFork,
}

// 执行参数结构
struct RunExecLikeArgs {
    tool_name: String,
    exec_params: ExecParams,
    additional_permissions: Option<PermissionProfile>,
    prefix_rule: Option<Vec<String>>,
    session: Arc<crate::codex::Session>,
    turn: Arc<TurnContext>,
    tracker: crate::tools::context::SharedTurnDiffTracker,
    call_id: String,
    freeform: bool,
    shell_runtime_backend: ShellRuntimeBackend,
}
```

### ShellHandler 实现

```rust
#[async_trait]
impl ToolHandler for ShellHandler {
    type Output = FunctionToolOutput;

    fn kind(&self) -> ToolKind {
        ToolKind::Function
    }

    fn matches_kind(&self, payload: &ToolPayload) -> bool {
        matches!(
            payload,
            ToolPayload::Function { .. } | ToolPayload::LocalShell { .. }
        )
    }

    async fn is_mutating(&self, invocation: &ToolInvocation) -> bool {
        match &invocation.payload {
            ToolPayload::Function { arguments } => {
                serde_json::from_str::<ShellToolCallParams>(arguments)
                    .map(|params| !is_known_safe_command(&params.command))
                    .unwrap_or(true)
            }
            ToolPayload::LocalShell { params } => !is_known_safe_command(&params.command),
            _ => true,
        }
    }

    async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError> {
        let ToolInvocation { session, turn, tracker, call_id, tool_name, payload, .. } = invocation;

        match payload {
            ToolPayload::Function { arguments } => {
                // 解析参数并构建 ExecParams
                let cwd = resolve_workdir_base_path(&arguments, turn.cwd.as_path())?;
                let params: ShellToolCallParams = parse_arguments_with_base_path(&arguments, cwd.as_path())?;
                let prefix_rule = params.prefix_rule.clone();
                let exec_params = Self::to_exec_params(&params, turn.as_ref(), session.conversation_id);
                
                Self::run_exec_like(RunExecLikeArgs {
                    tool_name: tool_name.clone(),
                    exec_params,
                    additional_permissions: params.additional_permissions.clone(),
                    prefix_rule,
                    session,
                    turn,
                    tracker,
                    call_id,
                    freeform: false,
                    shell_runtime_backend: ShellRuntimeBackend::Generic,
                }).await
            }
            ToolPayload::LocalShell { params } => { ... }
            _ => Err(...),
        }
    }
}
```

### ExecParams 构建

```rust
impl ShellHandler {
    fn to_exec_params(
        params: &ShellToolCallParams,
        turn_context: &TurnContext,
        thread_id: ThreadId,
    ) -> ExecParams {
        ExecParams {
            command: params.command.clone(),
            cwd: turn_context.resolve_path(params.workdir.clone()),
            expiration: params.timeout_ms.into(),
            env: create_env(&turn_context.shell_environment_policy, Some(thread_id)),
            network: turn_context.network.clone(),
            sandbox_permissions: params.sandbox_permissions.unwrap_or_default(),
            windows_sandbox_level: turn_context.windows_sandbox_level,
            windows_sandbox_private_desktop: turn_context.config.permissions.windows_sandbox_private_desktop,
            justification: params.justification.clone(),
            arg0: None,
        }
    }
}
```

### 核心执行逻辑 (run_exec_like)

```rust
impl ShellHandler {
    async fn run_exec_like(args: RunExecLikeArgs) -> Result<FunctionToolOutput, FunctionCallError> {
        let RunExecLikeArgs { tool_name, mut exec_params, additional_permissions, prefix_rule, 
                             session, turn, tracker, call_id, freeform, shell_runtime_backend } = args;

        // 1. 应用依赖环境变量
        let dependency_env = session.dependency_env().await;
        if !dependency_env.is_empty() {
            exec_params.env.extend(dependency_env.clone());
        }
        
        // 2. 收集显式环境覆盖
        let mut explicit_env_overrides = turn.shell_environment_policy.r#set.clone();
        for key in dependency_env.keys() {
            if let Some(value) = exec_params.env.get(key) {
                explicit_env_overrides.insert(key.clone(), value.clone());
            }
        }

        // 3. 处理额外权限
        let exec_permission_approvals_enabled = session.features().enabled(Feature::ExecPermissionApprovals);
        let effective_additional_permissions = apply_granted_turn_permissions(
            session.as_ref(),
            exec_params.sandbox_permissions,
            additional_permissions,
        ).await;
        
        // 4. 验证权限策略
        let additional_permissions_allowed = exec_permission_approvals_enabled
            || (session.features().enabled(Feature::RequestPermissionsTool)
                && effective_additional_permissions.permissions_preapproved);
        
        let normalized_additional_permissions = implicit_granted_permissions(...)
            .map_or_else(
                || normalize_and_validate_additional_permissions(...),
                |permissions| Ok(Some(permissions)),
            )
            .map_err(FunctionCallError::RespondToModel)?;

        // 5. 审批策略检查
        if effective_additional_permissions.sandbox_permissions.requests_sandbox_override()
            && !effective_additional_permissions.permissions_preapproved
            && !matches!(turn.approval_policy.value(), AskForApproval::OnRequest)
        {
            return Err(FunctionCallError::RespondToModel(format!(
                "approval policy is {approval_policy:?}; reject command — you should not ask for escalated permissions if the approval policy is {approval_policy:?}"
            )));
        }

        // 6. 拦截 apply_patch
        if let Some(output) = intercept_apply_patch(...).await? {
            return Ok(output);
        }

        // 7. 发送开始事件
        let emitter = ToolEmitter::shell(exec_params.command.clone(), exec_params.cwd.clone(), source, freeform);
        let event_ctx = ToolEventCtx::new(session.as_ref(), turn.as_ref(), &call_id, None);
        emitter.begin(event_ctx).await;

        // 8. 创建执行审批要求
        let exec_approval_requirement = session.services.exec_policy
            .create_exec_approval_requirement_for_command(ExecApprovalRequest { ... })
            .await;

        // 9. 构建并执行 shell 请求
        let req = ShellRequest {
            command: exec_params.command.clone(),
            cwd: exec_params.cwd.clone(),
            timeout_ms: exec_params.expiration.timeout_ms(),
            env: exec_params.env.clone(),
            explicit_env_overrides,
            network: exec_params.network.clone(),
            sandbox_permissions: effective_additional_permissions.sandbox_permissions,
            additional_permissions: normalized_additional_permissions,
            #[cfg(unix)]
            additional_permissions_preapproved: effective_additional_permissions.permissions_preapproved,
            justification: exec_params.justification.clone(),
            exec_approval_requirement,
        };
        
        let mut orchestrator = ToolOrchestrator::new();
        let mut runtime = match shell_runtime_backend {
            ShellRuntimeBackend::Generic => ShellRuntime::new(),
            backend @ (ShellRuntimeBackend::ShellCommandClassic | ShellRuntimeBackend::ShellCommandZshFork) => {
                ShellRuntime::for_shell_command(backend)
            }
        };
        
        let tool_ctx = ToolCtx { session: session.clone(), turn: turn.clone(), call_id: call_id.clone(), tool_name };
        let out = orchestrator.run(&mut runtime, &req, &tool_ctx, &turn, turn.approval_policy.value())
            .await
            .map(|result| result.output);
        
        // 10. 发送完成事件并返回结果
        let event_ctx = ToolEventCtx::new(session.as_ref(), turn.as_ref(), &call_id, None);
        let content = emitter.finish(event_ctx, out).await?;
        Ok(FunctionToolOutput::from_text(content, Some(true)))
    }
}
```

### ShellCommandHandler 特有逻辑

```rust
impl ShellCommandHandler {
    fn shell_runtime_backend(&self) -> ShellRuntimeBackend {
        match self.backend {
            ShellCommandBackend::Classic => ShellRuntimeBackend::ShellCommandClassic,
            ShellCommandBackend::ZshFork => ShellRuntimeBackend::ShellCommandZshFork,
        }
    }

    fn resolve_use_login_shell(
        login: Option<bool>,
        allow_login_shell: bool,
    ) -> Result<bool, FunctionCallError> {
        if !allow_login_shell && login == Some(true) {
            return Err(FunctionCallError::RespondToModel(
                "login shell is disabled by config; omit `login` or set it to false.".to_string()
            ));
        }
        Ok(login.unwrap_or(allow_login_shell))
    }

    fn base_command(shell: &Shell, command: &str, use_login_shell: bool) -> Vec<String> {
        shell.derive_exec_args(command, use_login_shell)
    }
}
```

## 关键代码路径与文件引用

### 本文件位置
`codex-rs/core/src/tools/handlers/shell.rs`

### 配套测试文件
`codex-rs/core/src/tools/handlers/shell_tests.rs`

### 依赖模块
```rust
use crate::exec::ExecParams;
use crate::exec_env::create_env;
use crate::exec_policy::ExecApprovalRequest;
use crate::is_safe_command::is_known_safe_command;
use crate::shell::Shell;
use crate::skills::maybe_emit_implicit_skill_invocation;
use crate::tools::handlers::apply_granted_turn_permissions;
use crate::tools::handlers::apply_patch::intercept_apply_patch;
use crate::tools::orchestrator::ToolOrchestrator;
use crate::tools::runtimes::shell::{ShellRequest, ShellRuntime, ShellRuntimeBackend};
use crate::tools::sandboxing::ToolCtx;
```

### 调用路径
1. 模型调用 `shell` 或 `shell_command` 工具
2. Handler 解析参数并构建 `ExecParams`
3. 应用额外权限和沙箱策略
4. 检查审批策略
5. 拦截特殊命令（如 apply_patch）
6. 创建 `ShellRequest` 并执行
7. 返回执行结果

## 依赖与外部交互

### 外部模块依赖
| 模块 | 用途 |
|-----|------|
| `crate::exec` | ExecParams 定义 |
| `crate::exec_env` | 环境变量创建 |
| `crate::exec_policy` | 执行审批策略 |
| `crate::is_safe_command` | 安全命令检测 |
| `crate::shell` | Shell 抽象 |
| `crate::skills` | 隐式技能调用 |
| `crate::tools::orchestrator` | 工具编排 |
| `crate::tools::runtimes::shell` | Shell 运行时 |

### 运行时交互
- `ShellRuntime`: 执行实际 shell 命令
- `ToolOrchestrator`: 协调执行流程
- `ToolEmitter`: 发送执行事件

### 安全相关
- `is_known_safe_command`: 检测命令是否安全（只读）
- `apply_granted_turn_permissions`: 应用用户授予的权限
- `intercept_apply_patch`: 拦截 patch 命令

## 风险、边界与改进建议

### 潜在风险
1. **命令注入**: 虽然使用参数化执行，但仍需警惕 shell 注入
2. **权限提升**: 额外权限可能被滥用，需要严格审计
3. **资源耗尽**: 长时间运行的命令可能耗尽系统资源
4. **信息泄露**: 环境变量可能包含敏感信息

### 边界情况
1. **空命令**: 未显式处理空命令
2. **超长命令**: 未限制命令长度
3. **特殊字符**: 需要确保特殊字符正确处理
4. **并发执行**: 多个 shell 命令并发执行的资源竞争

### 改进建议

1. **添加命令长度限制**:
   ```rust
   const MAX_COMMAND_LENGTH: usize = 10000;
   if params.command.len() > MAX_COMMAND_LENGTH {
       return Err(FunctionCallError::RespondToModel(
           "Command too long".to_string()
       ));
   }
   ```

2. **添加命令黑名单**:
   ```rust
   const DANGEROUS_COMMANDS: &[&str] = &["rm -rf /", ":(){ :|:& };:"];
   if is_dangerous_command(&params.command) {
       return Err(FunctionCallError::RespondToModel(
           "Dangerous command detected".to_string()
       ));
   }
   ```

3. **改进超时处理**:
   ```rust
   // 添加更细粒度的超时控制
   pub struct TimeoutConfig {
       pub soft_timeout_ms: u64,  // 发送警告
       pub hard_timeout_ms: u64,  // 强制终止
   }
   ```

4. **添加审计日志**:
   ```rust
   // 记录所有执行的命令
   session.audit_log().record_shell_execution(&exec_params, &result).await;
   ```

5. **环境变量过滤**:
   ```rust
   // 过滤敏感环境变量
   const SENSITIVE_VARS: &[&str] = &["PASSWORD", "SECRET", "TOKEN"];
   for key in SENSITIVE_VARS {
       exec_params.env.remove(*key);
   }
   ```

6. **添加测试覆盖**:
   - 当前 `shell_tests.rs` 主要测试参数转换
   - 建议添加：
     - 权限验证测试
     - 审批策略测试
     - 超时处理测试
     - 错误处理测试

### 代码质量观察
- 代码结构清晰，职责分离良好
- 使用 `RunExecLikeArgs` 结构体避免参数过多
- 异步处理完善，使用 `async_trait`
- 建议提取更多常量（如超时默认值）
- 部分代码块较长（`run_exec_like` 约 170 行），可考虑进一步拆分
