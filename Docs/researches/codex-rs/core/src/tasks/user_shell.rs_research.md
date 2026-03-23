# user_shell.rs 研究文档

## 场景与职责

`user_shell.rs` 实现了 **UserShellCommandTask**（用户 Shell 命令任务），用于执行用户通过 `/shell` 命令或其他方式输入的 shell 命令。该任务提供了在 Codex 会话中直接执行系统命令的能力。

### 核心职责
1. **Shell 命令执行**：在用户的默认 shell 中执行命令
2. **生命周期管理**：支持独立轮次和辅助执行两种模式
3. **输出捕获**：捕获 stdout、stderr 和执行结果
4. **事件通知**：发送命令开始/结束事件，报告执行状态

### 使用场景
- 用户执行 `/shell <command>` 命令
- 需要快速执行系统命令而无需模型参与
- 在活跃对话轮次中执行辅助命令

## 功能点目的

### 1. 双模式执行

**StandaloneTurn 模式**：
- 作为独立的对话轮次执行
- 发送完整的 `TurnStarted` / `TurnComplete` 生命周期事件
- 输出记录到对话历史

**ActiveTurnAuxiliary 模式**：
- 在现有活跃轮次中执行
- 不发送额外的生命周期事件
- 输出注入到当前轮次的 pending input

### 2. Shell 环境支持
- 使用用户的默认 shell（通过 `session.user_shell()`）
- 支持登录 shell（`use_login_shell = true`）
- 保留 shell 特性（管道、重定向、逻辑操作符）

### 3. 输出持久化
- 执行输出格式化为对话消息
- 支持截断策略（`truncation_policy`）
- 区分成功（exit_code = 0）和失败状态

## 具体技术实现

### 关键数据结构

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum UserShellCommandMode {
    /// 独立轮次生命周期
    StandaloneTurn,
    /// 活跃轮次辅助执行
    ActiveTurnAuxiliary,
}

#[derive(Clone)]
pub(crate) struct UserShellCommandTask {
    command: String,
}

impl UserShellCommandTask {
    pub(crate) fn new(command: String) -> Self {
        Self { command }
    }
}
```

### 超时配置

```rust
const USER_SHELL_TIMEOUT_MS: u64 = 60 * 60 * 1000; // 1 小时
```

**注意**：当前使用固定超时，TODO 提到应使用 `ExecExpiration::Cancellation` 替代。

### SessionTask 实现

```rust
#[async_trait]
impl SessionTask for UserShellCommandTask {
    fn kind(&self) -> TaskKind {
        TaskKind::Regular
    }

    fn span_name(&self) -> &'static str {
        "session_task.user_shell"
    }

    async fn run(...) -> Option<String> {
        execute_user_shell_command(
            session.clone_session(),
            turn_context,
            self.command.clone(),
            cancellation_token,
            UserShellCommandMode::StandaloneTurn,
        ).await;
        None
    }
}
```

### 核心执行函数

```rust
pub(crate) async fn execute_user_shell_command(
    session: Arc<Session>,
    turn_context: Arc<TurnContext>,
    command: String,
    cancellation_token: CancellationToken,
    mode: UserShellCommandMode,
)
```

**执行流程**：

1. **记录指标**
   ```rust
   session.services.session_telemetry
       .counter("codex.task.user_shell", 1, &[]);
   ```

2. **发送 TurnStarted**（仅 StandaloneTurn 模式）
   ```rust
   if mode == UserShellCommandMode::StandaloneTurn {
       let event = EventMsg::TurnStarted(TurnStartedEvent {
           turn_id: turn_context.sub_id.clone(),
           model_context_window: turn_context.model_context_window(),
           collaboration_mode_kind: turn_context.collaboration_mode.mode,
       });
       session.send_event(turn_context.as_ref(), event).await;
   }
   ```

3. **准备命令**
   ```rust
   let use_login_shell = true;
   let session_shell = session.user_shell();
   let display_command = session_shell.derive_exec_args(&command, use_login_shell);
   let exec_command = maybe_wrap_shell_lc_with_snapshot(
       &display_command,
       session_shell.as_ref(),
       turn_context.cwd.as_path(),
       &turn_context.shell_environment_policy.r#set,
   );
   ```

4. **发送开始事件**
   ```rust
   session.send_event(
       turn_context.as_ref(),
       EventMsg::ExecCommandBegin(ExecCommandBeginEvent {
           call_id: call_id.clone(),
           process_id: None,
           turn_id: turn_context.sub_id.clone(),
           command: display_command.clone(),
           cwd: cwd.clone(),
           parsed_cmd: parsed_cmd.clone(),
           source: ExecCommandSource::UserShell,
           interaction_input: None,
       }),
   ).await;
   ```

5. **创建执行环境**
   ```rust
   let sandbox_policy = SandboxPolicy::DangerFullAccess;
   let exec_env = ExecRequest {
       command: exec_command.clone(),
       cwd: cwd.clone(),
       env: create_env(&turn_context.shell_environment_policy, Some(session.conversation_id)),
       network: turn_context.network.clone(),
       expiration: USER_SHELL_TIMEOUT_MS.into(),
       sandbox: SandboxType::None,
       windows_sandbox_level: turn_context.windows_sandbox_level,
       windows_sandbox_private_desktop: turn_context.config.permissions.windows_sandbox_private_desktop,
       sandbox_permissions: SandboxPermissions::UseDefault,
       sandbox_policy: sandbox_policy.clone(),
       file_system_sandbox_policy: FileSystemSandboxPolicy::from(&sandbox_policy),
       network_sandbox_policy: NetworkSandboxPolicy::from(&sandbox_policy),
       justification: None,
       arg0: None,
   };
   ```

6. **执行命令**
   ```rust
   let stdout_stream = Some(StdoutStream {
       sub_id: turn_context.sub_id.clone(),
       call_id: call_id.clone(),
       tx_event: session.get_tx_event(),
   });

   let exec_result = execute_exec_request(
       exec_env,
       &sandbox_policy,
       stdout_stream,
       /*after_spawn*/ None,
   )
   .or_cancel(&cancellation_token)
   .await;
   ```

7. **处理结果**
   - **取消**：发送失败状态，exit_code = -1
   - **成功**：发送 `ExecCommandEnd` 带完整输出
   - **执行错误**：记录错误，发送失败状态

### 输出持久化

```rust
async fn persist_user_shell_output(
    session: &Session,
    turn_context: &TurnContext,
    raw_command: &str,
    exec_output: &ExecToolCallOutput,
    mode: UserShellCommandMode,
)
```

**模式差异**：

| 模式 | 处理方式 |
|------|---------|
| `StandaloneTurn` | `record_conversation_items` + `ensure_rollout_materialized` |
| `ActiveTurnAuxiliary` | `inject_response_items` 或 `record_conversation_items` |

**辅助模式逻辑**：
```rust
let response_input_item = match output_item {
    ResponseItem::Message { role, content, .. } => {
        ResponseInputItem::Message { role, content }
    }
    _ => unreachable!("user shell command output record should always be a message"),
};

if let Err(items) = session.inject_response_items(vec![response_input_item]).await {
    // 注入失败，直接记录
    let response_items = items.into_iter().map(ResponseItem::from).collect();
    session.record_conversation_items(turn_context, &response_items).await;
}
```

## 关键代码路径与文件引用

### 调用路径

**独立模式**：
```
codex.rs:4573-4597 (run_user_shell_command)
  → spawn_task(Arc<UserShellCommandTask>)
    → tasks/mod.rs:spawn_task
      → user_shell.rs:75-92 (UserShellCommandTask::run)
        → execute_user_shell_command(mode = StandaloneTurn)
```

**辅助模式**：
```
codex.rs:4573-4588 (run_user_shell_command)
  → 检查活跃轮次
    → tokio::spawn(execute_user_shell_command(mode = ActiveTurnAuxiliary))
```

### 相关文件
- `codex-rs/core/src/tasks/user_shell.rs`：本文件（357行）
- `codex-rs/core/src/tasks/mod.rs`：`SessionTask` trait
- `codex-rs/core/src/codex.rs`：`Session::run_user_shell_command`
- `codex-rs/core/src/exec.rs`：`execute_exec_request`, `ExecToolCallOutput`
- `codex-rs/core/src/exec_env.rs`：`create_env`
- `codex-rs/core/src/user_shell_command.rs`：`user_shell_command_record_item`

### 依赖类型
- `crate::exec::{ExecToolCallOutput, SandboxType, StdoutStream, StreamOutput, execute_exec_request}`
- `crate::exec_env::create_env`
- `crate::parse_command::parse_command`
- `crate::protocol::{ExecCommandBeginEvent, ExecCommandEndEvent, ExecCommandSource, ExecCommandStatus, SandboxPolicy}`
- `crate::sandboxing::{ExecRequest, SandboxPermissions}`

## 依赖与外部交互

### 外部 crate
| Crate | 用途 |
|-------|------|
| `async_trait` | 异步 trait |
| `tokio_util::sync::CancellationToken` | 取消机制 |
| `uuid::Uuid` | 生成 call_id |
| `tracing::error` | 错误日志 |
| `codex_async_utils::{CancelErr, OrCancelExt}` | 取消扩展 |
| `codex_protocol` | 协议类型 |

### 内部模块
```
user_shell.rs
  ├── uses crate::codex::{TurnContext, Session}
  ├── uses crate::exec::{ExecToolCallOutput, SandboxType, StdoutStream, StreamOutput, execute_exec_request}
  ├── uses crate::exec_env::create_env
  ├── uses crate::parse_command::parse_command
  ├── uses crate::protocol::{EventMsg, ExecCommandBeginEvent, ExecCommandEndEvent, ...}
  ├── uses crate::sandboxing::{ExecRequest, SandboxPermissions}
  ├── uses crate::tools::format_exec_output_str
  ├── uses crate::tools::runtimes::maybe_wrap_shell_lc_with_snapshot
  ├── uses crate::user_shell_command::user_shell_command_record_item
  └── uses super::{SessionTask, SessionTaskContext}
```

### 沙箱策略
```rust
let sandbox_policy = SandboxPolicy::DangerFullAccess;
```

用户 shell 命令使用完全访问权限，因为：
- 用户明确请求执行
- 需要访问用户环境的完整功能
- 与工具调用的沙箱策略区分

## 风险、边界与改进建议

### 已知风险

1. **安全风险**
   - 使用 `SandboxPolicy::DangerFullAccess`
   - 用户可能执行危险命令
   - 建议添加确认提示（类似工具调用审批）

2. **超时处理**
   - 固定 1 小时超时可能过长或过短
   - 无进度指示，用户无法知道命令是否仍在运行
   - 建议添加可配置超时和进度更新

3. **并发执行**
   - 辅助模式在后台执行
   - 可能与主任务产生资源竞争
   - 建议限制并发 shell 命令数量

4. **输出大小**
   - 大输出可能消耗大量内存和网络
   - 当前依赖 `truncation_policy` 截断
   - 建议流式输出或分页

### 边界条件

| 场景 | 处理 |
|------|------|
| 取消 | `or_cancel` 返回 `CancelErr::Cancelled`，发送失败状态 |
| 命令解析失败 | `parse_command` 返回错误信息 |
| 执行错误 | 记录错误，发送失败事件 |
| 空命令 | 由 shell 处理（通常返回错误） |
| 超长输出 | 根据 `truncation_policy` 截断 |

### 改进建议

1. **审批机制**
   ```rust
   // 对于危险命令，请求用户确认
   if is_dangerous_command(&parsed_cmd) {
       request_user_approval(&call_id).await?;
   }
   ```

2. **可配置超时**
   ```rust
   // 从配置读取或命令参数指定
   expiration: command_timeout_ms.map(Into::into)
       .unwrap_or_else(|| USER_SHELL_TIMEOUT_MS.into()),
   ```

3. **进度指示**
   ```rust
   // 长时间运行的命令发送进度心跳
   EventMsg::ExecCommandProgress { call_id, elapsed_seconds }
   ```

4. **历史记录**
   ```rust
   // 记录最近执行的命令，支持快速重复
   struct ShellHistory {
       commands: VecDeque<String>,
       max_size: usize,
   }
   ```

5. **测试覆盖**
   - 当前无专门测试文件
   - 建议添加：
     - 命令执行成功/失败场景
     - 取消处理
     - 两种模式的行为差异
     - 输出格式化
