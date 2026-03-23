# unified_exec.rs 研究文档

## 场景与职责

`unified_exec.rs` 实现了 `UnifiedExecHandler`，是 Codex 的核心命令执行工具处理器。它统一了传统的 shell 命令执行和交互式 PTY 会话管理，支持 `exec_command`（执行命令）和 `write_stdin`（向运行中进程写入输入）两种操作。该处理器是 Codex 与操作系统交互的主要通道，负责命令执行、权限管理、沙箱隔离等关键功能。

## 功能点目的

### 1. 统一命令执行
提供统一的命令执行接口，支持：
- 一次性命令执行（类似传统 shell 工具）
- 交互式会话管理（支持 TTY 分配）
- 长时间运行进程的输出流式获取

### 2. 权限与沙箱管理
集成 Codex 的权限系统：
- 支持请求额外权限（文件系统、网络）
- 沙箱策略应用和覆盖
- 审批流程集成（Guardian、策略规则）

### 3. 进程生命周期管理
通过 `UnifiedExecProcessManager` 管理：
- 进程 ID 分配和回收
- 标准输入写入
- 输出流控制（token 限制、超时）

## 具体技术实现

### 核心数据结构

```rust
pub struct UnifiedExecHandler;

// exec_command 参数
#[derive(Debug, Deserialize)]
pub(crate) struct ExecCommandArgs {
    cmd: String,                              // 命令字符串
    #[serde(default)]
    pub(crate) workdir: Option<String>,       // 工作目录
    #[serde(default)]
    shell: Option<String>,                    // 指定 shell
    #[serde(default)]
    login: Option<bool>,                      // 登录 shell 标志
    #[serde(default = "default_tty")]
    tty: bool,                                // 是否分配 TTY
    #[serde(default = "default_exec_yield_time_ms")]
    yield_time_ms: u64,                       // 输出等待时间（默认 10s）
    #[serde(default)]
    max_output_tokens: Option<usize>,         // 最大输出 token 数
    #[serde(default)]
    sandbox_permissions: SandboxPermissions,  // 沙箱权限级别
    #[serde(default)]
    additional_permissions: Option<PermissionProfile>,  // 额外权限
    #[serde(default)]
    justification: Option<String>,            // 权限提升理由
    #[serde(default)]
    prefix_rule: Option<Vec<String>>,         // 前缀规则建议
}

// write_stdin 参数
#[derive(Debug, Deserialize)]
struct WriteStdinArgs {
    session_id: i32,      // 进程/会话 ID
    #[serde(default)]
    chars: String,        // 输入字符
    #[serde(default = "default_write_stdin_yield_time_ms")]
    yield_time_ms: u64,   // 默认 250ms
    #[serde(default)]
    max_output_tokens: Option<usize>,
}
```

### 主处理流程

```rust
#[async_trait]
impl ToolHandler for UnifiedExecHandler {
    type Output = ExecCommandToolOutput;

    async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError> {
        let manager = &session.services.unified_exec_manager;
        let context = UnifiedExecContext::new(session.clone(), turn.clone(), call_id.clone());

        match tool_name.as_str() {
            "exec_command" => {
                // 1. 解析工作目录和参数
                let cwd = resolve_workdir_base_path(&arguments, context.turn.cwd.as_path())?;
                let args: ExecCommandArgs = parse_arguments_with_base_path(&arguments, cwd.as_path())?;

                // 2. 触发隐式技能调用
                maybe_emit_implicit_skill_invocation(session.as_ref(), turn.as_ref(), &args.cmd, args.workdir.as_deref()).await;

                // 3. 分配进程 ID
                let process_id = manager.allocate_process_id().await;

                // 4. 构建命令
                let command = get_command(&args, session.user_shell(), &turn.tools_config.unified_exec_shell_mode, turn.tools_config.allow_login_shell)?;

                // 5. 应用权限（包括已授予的粘性权限）
                let effective_additional_permissions = apply_granted_turn_permissions(
                    context.session.as_ref(),
                    sandbox_permissions,
                    additional_permissions,
                ).await;

                // 6. 检查审批策略
                if effective_additional_permissions.sandbox_permissions.requests_sandbox_override()
                    && !effective_additional_permissions.permissions_preapproved
                    && !matches!(context.turn.approval_policy.value(), AskForApproval::OnRequest)
                {
                    manager.release_process_id(process_id).await;
                    return Err(FunctionCallError::RespondToModel(format!(
                        "approval policy is {approval_policy:?}; reject command..."
                    )));
                }

                // 7. 拦截 apply_patch（如果命令是补丁应用）
                if let Some(output) = intercept_apply_patch(&command, &cwd, ...).await? {
                    manager.release_process_id(process_id).await;
                    return Ok(output);
                }

                // 8. 执行命令
                manager.exec_command(ExecCommandRequest {
                    command,
                    process_id,
                    yield_time_ms,
                    max_output_tokens,
                    workdir,
                    network: context.turn.network.clone(),
                    tty,
                    sandbox_permissions: effective_additional_permissions.sandbox_permissions,
                    additional_permissions: normalized_additional_permissions,
                    additional_permissions_preapproved: effective_additional_permissions.permissions_preapproved,
                    justification,
                    prefix_rule,
                }, &context).await.map_err(...)?
            }

            "write_stdin" => {
                let args: WriteStdinArgs = parse_arguments(&arguments)?;
                let response = manager.write_stdin(WriteStdinRequest {
                    process_id: args.session_id,
                    input: &args.chars,
                    yield_time_ms: args.yield_time_ms,
                    max_output_tokens: args.max_output_tokens,
                }).await?;

                // 发送终端交互事件
                let interaction = TerminalInteractionEvent {
                    call_id: response.event_call_id.clone(),
                    process_id: args.session_id.to_string(),
                    stdin: args.chars.clone(),
                };
                session.send_event(turn.as_ref(), EventMsg::TerminalInteraction(interaction)).await;

                response
            }
            // ...
        }
    }
}
```

### 命令构建逻辑

```rust
pub(crate) fn get_command(
    args: &ExecCommandArgs,
    session_shell: Arc<Shell>,
    shell_mode: &UnifiedExecShellMode,
    allow_login_shell: bool,
) -> Result<Vec<String>, String> {
    // 1. 解析登录 shell 配置
    let use_login_shell = match args.login {
        Some(true) if !allow_login_shell => {
            return Err("login shell is disabled by config...".to_string());
        }
        Some(use_login_shell) => use_login_shell,
        None => allow_login_shell,
    };

    match shell_mode {
        // 2. Direct 模式：使用用户 shell 或指定 shell
        UnifiedExecShellMode::Direct => {
            let model_shell = args.shell.as_ref().map(|shell_str| {
                let mut shell = get_shell_by_model_provided_path(&PathBuf::from(shell_str));
                shell.shell_snapshot = crate::shell::empty_shell_snapshot_receiver();
                shell
            });
            let shell = model_shell.as_ref().unwrap_or(session_shell.as_ref());
            Ok(shell.derive_exec_args(&args.cmd, use_login_shell))
        }

        // 3. ZshFork 模式：使用特定 zsh 路径
        UnifiedExecShellMode::ZshFork(zsh_fork_config) => Ok(vec![
            zsh_fork_config.shell_zsh_path.to_string_lossy().to_string(),
            if use_login_shell { "-lc" } else { "-c" }.to_string(),
            args.cmd.clone(),
        ]),
    }
}
```

### 变异检测

```rust
async fn is_mutating(&self, invocation: &ToolInvocation) -> bool {
    let ToolPayload::Function { arguments } = &invocation.payload else {
        return true;
    };

    let Ok(params) = serde_json::from_str::<ExecCommandArgs>(arguments) else {
        return true;
    };

    // 构建命令并检查是否安全
    let command = match get_command(&params, ..., &turn.tools_config.unified_exec_shell_mode, ...) {
        Ok(command) => command,
        Err(_) => return true,
    };

    !is_known_safe_command(&command)  // 不安全命令 = 变异操作
}
```

## 关键代码路径与文件引用

### 模块结构
```
unified_exec.rs
├── UnifiedExecHandler
│   ├── ToolHandler trait 实现
│   │   ├── kind() -> ToolKind::Function
│   │   ├── matches_kind()
│   │   ├── is_mutating() - 安全命令检测
│   │   └── handle() - 主处理逻辑
│   ├── ExecCommandArgs (输入参数)
│   ├── WriteStdinArgs (输入参数)
│   └── get_command() - 命令构建
└── tests (unified_exec_tests.rs)
```

### 依赖关系
```rust
// 核心依赖
use crate::features::Feature;
use crate::function_tool::FunctionCallError;
use crate::is_safe_command::is_known_safe_command;  // 安全命令检测
use crate::protocol::{EventMsg, TerminalInteractionEvent};
use crate::sandboxing::SandboxPermissions;
use crate::shell::{Shell, get_shell_by_model_provided_path};
use crate::skills::maybe_emit_implicit_skill_invocation;
use crate::tools::context::{ExecCommandToolOutput, ToolInvocation, ToolPayload};
use crate::tools::handlers::{
    apply_granted_turn_permissions, apply_patch::intercept_apply_patch,
    implicit_granted_permissions, normalize_and_validate_additional_permissions,
    parse_arguments, parse_arguments_with_base_path, resolve_workdir_base_path
};
use crate::tools::registry::{ToolHandler, ToolKind};
use crate::tools::spec::UnifiedExecShellMode;
use crate::unified_exec::{ExecCommandRequest, UnifiedExecContext, UnifiedExecProcessManager, WriteStdinRequest};
use codex_protocol::models::PermissionProfile;
```

### 相关文件
- `codex-rs/core/src/tools/handlers/unified_exec_tests.rs` - 单元测试
- `codex-rs/core/src/tools/runtimes/unified_exec.rs` - 运行时实现
- `codex-rs/core/src/tools/spec.rs` - UnifiedExecShellMode 定义
- `codex-rs/core/src/unified_exec/` - 进程管理实现
- `codex-rs/core/src/shell.rs` - Shell 类型和命令构建

## 依赖与外部交互

### 数据流
```
模型调用 exec_command
    │
    ├──> 解析参数 (ExecCommandArgs)
    │       ├── cmd: "echo hello"
    │       ├── workdir: "./subdir"
    │       ├── tty: false
    │       └── sandbox_permissions: "use_default"
    │
    ├──> 构建命令
    │       ├── Shell::derive_exec_args() 或
    │       └── ZshFork 模式直接构建
    │
    ├──> 权限处理
    │       ├── apply_granted_turn_permissions() 应用已授予权限
    │       ├── normalize_and_validate_additional_permissions() 验证
    │       └── 检查 approval_policy
    │
    ├──> 拦截检查
    │       └── intercept_apply_patch() 如果是补丁命令
    │
    ├──> 执行
    │       └── UnifiedExecProcessManager::exec_command()
    │           ├── 创建 PTY（如果 tty=true）
    │           ├── 应用沙箱
    │           ├── 等待输出（yield_time_ms）
    │           └── 返回 ExecCommandToolOutput
    │
    └──> 返回结果
            {
                "chunk_id": "...",
                "wall_time_seconds": 0.5,
                "exit_code": 0,
                "session_id": 123,
                "output": "hello"
            }
```

### 与沙箱系统集成
```rust
// 运行时通过 SandboxAttempt 应用沙箱
let exec_env = attempt
    .env_for(spec, req.network.as_ref())
    .map_err(|err| ToolError::Codex(err.into()))?;

// 执行
manager.open_session_with_exec_env(&exec_env, req.tty, ...).await
```

### 与审批系统集成
```rust
// UnifiedExecRuntime 实现 Approvable trait
impl Approvable<UnifiedExecRequest> for UnifiedExecRuntime<'_> {
    fn start_approval_async<'b>(&'b mut self, req: &'b UnifiedExecRequest, ctx: ApprovalCtx<'b>) -> BoxFuture<'b, ReviewDecision> {
        Box::pin(async move {
            if routes_approval_to_guardian(turn) {
                // 路由到 Guardian 审批
                review_approval_request(session, turn, GuardianApprovalRequest::ExecCommand { ... }, ...).await
            } else {
                // 本地审批缓存
                with_cached_approval(&session.services, "unified_exec", keys, || async move {
                    session.request_command_approval(...).await
                }).await
            }
        })
    }
}
```

## 风险、边界与改进建议

### 潜在风险

1. **命令注入风险**
   ```rust
   // cmd 是字符串，需要正确解析
   cmd: String,
   ```
   - 虽然使用 shlex 解析，但仍需警惕注入
   - 建议添加更严格的输入验证

2. **权限提升绕过**
   ```rust
   if effective_additional_permissions.sandbox_permissions.requests_sandbox_override()
       && !effective_additional_permissions.permissions_preapproved
       && !matches!(context.turn.approval_policy.value(), AskForApproval::OnRequest)
   ```
   - 复杂的权限逻辑可能有边界情况
   - 建议添加更全面的审计日志

3. **TTY 安全风险**
   ```rust
   tty: bool,  // 用户可控
   ```
   - TTY 分配可能绕过某些安全控制
   - 需要确保沙箱在 TTY 模式下仍然有效

4. **进程 ID 泄漏**
   ```rust
   let process_id = manager.allocate_process_id().await;
   // 如果早期返回，需要手动释放
   manager.release_process_id(process_id).await;
   ```
   - 多个早期返回点需要确保释放
   - 建议使用 RAII 模式

### 边界情况

1. **超长命令**
   - 未检查命令长度限制
   - 可能导致缓冲区溢出或性能问题

2. **特殊字符处理**
   ```rust
   // shell 模式直接拼接
   UnifiedExecShellMode::ZshFork(_) => Ok(vec![..., args.cmd.clone()]),
   ```
   - ZshFork 模式下特殊字符处理

3. **工作目录不存在**
   ```rust
   let workdir = workdir.map(|dir| context.turn.resolve_path(Some(dir)));
   ```
   - 未验证目录存在性

4. **并发写入**
   ```rust
   "write_stdin" => {
       manager.write_stdin(WriteStdinRequest { ... }).await
   }
   ```
   - 多个并发 write_stdin 调用的行为

### 改进建议

1. **使用 RAII 管理进程 ID**
   ```rust
   struct ProcessIdGuard {
       manager: Arc<UnifiedExecProcessManager>,
       id: i32,
   }
   
   impl Drop for ProcessIdGuard {
       fn drop(&mut self) {
           // 自动释放
       }
   }
   ```

2. **增强命令验证**
   ```rust
   fn validate_command(cmd: &str) -> Result<(), String> {
       // 检查长度
       if cmd.len() > MAX_COMMAND_LENGTH {
           return Err("Command too long".to_string());
       }
       // 检查危险模式
       if contains_dangerous_patterns(cmd) {
           return Err("Potentially dangerous command detected".to_string());
       }
       Ok(())
   }
   ```

3. **改进错误信息**
   ```rust
   // 当前
   FunctionCallError::RespondToModel(format!(
       "exec_command failed for `{command_for_display}`: {err:?}"
   ))
   
   // 建议：分类错误
   enum ExecError {
       PermissionDenied { reason: String },
       CommandNotFound { cmd: String },
       Timeout { elapsed: Duration },
       // ...
   }
   ```

4. **添加速率限制**
   ```rust
   // 防止滥用
   let rate_limiter = session.get_rate_limiter("exec_command");
   rate_limiter.check().await?;
   ```

5. **支持命令取消**
   ```rust
   // 添加 cancel_command 工具
   "cancel_command" => {
       manager.cancel_process(args.session_id).await
   }
   ```

6. **改进 TTY 检测**
   ```rust
   // 自动检测是否需要 TTY
   fn should_allocate_tty(cmd: &str) -> bool {
       // 检查交互式命令
       cmd.contains("vim") || cmd.contains("less") || ...
   }
   ```

### 测试覆盖

当前测试在 `unified_exec_tests.rs` 中覆盖：
- 默认 shell 使用
- 显式 shell 指定（bash、powershell、cmd）
- 登录 shell 配置
- ZshFork 模式
- 相对路径权限解析

建议添加：
- TTY 模式测试
- 权限提升场景
- 超时处理
- 并发写入测试
- 特殊字符处理
