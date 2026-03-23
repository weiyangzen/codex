# user_shell_cmd.rs 研究文档

## 场景与职责

`user_shell_cmd.rs` 是 Codex Core 集成测试套件中的关键测试文件，专注于验证**用户 Shell 命令执行功能**的正确性和鲁棒性。该测试文件位于 `codex-rs/core/tests/suite/` 目录下，属于核心测试套件的一部分。

### 核心职责

1. **验证用户 Shell 命令执行**：测试用户通过 Codex 执行本地 Shell 命令的完整流程
2. **测试命令生命周期管理**：验证命令的开始、执行、中断、完成等状态转换
3. **验证与模型对话的集成**：确保用户 Shell 命令的输出能够正确记录到对话历史中
4. **测试并发场景**：验证用户 Shell 命令与活跃模型回合的共存行为

---

## 功能点目的

### 1. 基本命令执行 (`user_shell_cmd_ls_and_cat_in_temp_dir`)

**目的**：验证基本的文件系统命令（如 `ls` 和 `cat`）能够在临时工作目录中正确执行。

**测试逻辑**：
- 创建临时目录并在其中写入测试文件
- 执行 `ls` 命令验证文件列表输出
- 执行 `cat` 命令验证文件内容读取
- 处理 Windows 平台的 CRLF 行尾差异

**关键断言**：
```rust
assert_eq!(exit_code, 0);
assert!(stdout.contains(file_name));
assert_eq!(stdout, contents); // 内容精确匹配
```

### 2. 命令中断 (`user_shell_cmd_can_be_interrupted`)

**目的**：验证长时间运行的用户命令可以被中断，并正确触发 `TurnAborted` 事件。

**测试逻辑**：
- 启动一个长时间睡眠命令 (`sleep 5`)
- 等待命令开始执行（`ExecCommandBegin` 事件）
- 发送 `Op::Interrupt` 中断信号
- 验证收到 `TurnAborted(Interrupted)` 事件

### 3. 与活跃回合共存 (`user_shell_command_does_not_replace_active_turn`)

**目的**：确保用户 Shell 命令不会干扰正在进行的模型回合。

**测试逻辑**：
- 启动一个模型回合（触发 `shell_command` 工具调用）
- 在模型命令执行期间，提交用户 Shell 命令
- 验证用户命令能够完成而不导致回合被替换
- 确认模型回合继续执行并发出后续请求

**关键验证点**：
- `saw_replaced_abort` 必须为 false（没有发生回合替换）
- `saw_user_shell_end` 必须为 true（用户命令完成）
- `saw_turn_complete` 必须为 true（模型回合完成）
- 验证发出了 2 个模型请求

### 4. 历史记录持久化 (`user_shell_command_history_is_persisted_and_shared_with_model`)

**目的**：验证用户 Shell 命令的执行结果被正确记录到对话历史中，并能在后续模型请求中使用。

**测试逻辑**：
- 禁用 `ShellSnapshot` 特性以简化命令匹配
- 执行用户 Shell 命令读取环境变量
- 验证 `ExecCommandBegin`、`ExecCommandOutputDelta`、`ExecCommandEnd` 事件序列
- 提交后续模型回合，验证请求中包含用户命令的历史记录

**历史记录格式**：
```xml
<user_shell_command>
<command>{command}</command>
<result>
Exit code: 0
Duration: {seconds} seconds
Output:
{output}
</result>
</user_shell_command>
```

### 5. 网络沙箱环境变量 (`user_shell_command_does_not_set_network_sandbox_env_var`)

**目的**：验证用户 Shell 命令不会设置 `CODEX_SANDBOX_NETWORK_DISABLED` 环境变量，确保用户命令在受限网络策略下仍能正常工作。

### 6. 输出截断 (`user_shell_command_output_is_truncated_in_history`)

**目的**：验证当命令输出超过 token 限制时，历史记录中的输出会被正确截断。

**测试逻辑**：
- 设置 `tool_output_token_limit = 100`
- 执行生成大量输出的命令（`seq 1 400`）
- 验证历史记录中包含截断标记和首尾内容

**截断格式**：
```
Total output lines: 400

{前69行}
70…273 tokens truncated…351
{后49行}
```

### 7. 单次截断保证 (`user_shell_command_is_truncated_only_once`)

**目的**：确保输出截断只发生一次，不会出现重复截断标记。

---

## 具体技术实现

### 关键数据结构

#### `ExecCommandSource` 枚举
```rust
pub enum ExecCommandSource {
    UserShell,  // 用户发起的 Shell 命令
    Agent,      // 模型代理执行的工具调用
}
```

#### `ExecCommandBeginEvent` 和 `ExecCommandEndEvent`
```rust
pub struct ExecCommandBeginEvent {
    pub call_id: String,
    pub process_id: Option<u32>,
    pub turn_id: String,
    pub command: Vec<String>,
    pub cwd: PathBuf,
    pub parsed_cmd: ParsedCommand,
    pub source: ExecCommandSource,
    pub interaction_input: Option<String>,
}

pub struct ExecCommandEndEvent {
    pub call_id: String,
    pub process_id: Option<u32>,
    pub turn_id: String,
    pub command: Vec<String>,
    pub cwd: PathBuf,
    pub parsed_cmd: ParsedCommand,
    pub source: ExecCommandSource,
    pub interaction_input: Option<String>,
    pub stdout: String,
    pub stderr: String,
    pub aggregated_output: String,
    pub exit_code: i32,
    pub duration: Duration,
    pub formatted_output: String,
    pub status: ExecCommandStatus,
}
```

#### `UserShellCommandMode` 枚举（内部实现）
```rust
pub(crate) enum UserShellCommandMode {
    StandaloneTurn,       // 作为独立的回合生命周期执行
    ActiveTurnAuxiliary,  // 在活跃回合中作为辅助执行
}
```

### 关键流程

#### 用户 Shell 命令执行流程

1. **命令提交**：通过 `Op::RunUserShellCommand { command }` 提交命令
2. **任务创建**：创建 `UserShellCommandTask` 实例
3. **事件发射**：
   - `TurnStarted`（如果是独立回合模式）
   - `ExecCommandBegin`（命令开始执行）
4. **命令执行**：
   - 解析命令参数
   - 创建执行环境（包含环境变量）
   - 调用 `execute_exec_request` 执行命令
5. **输出处理**：
   - 实时流式输出通过 `StdoutStream` 发送 `ExecCommandOutputDelta` 事件
   - 命令完成后发送 `ExecCommandEnd` 事件
6. **历史记录**：
   - 格式化输出为 `user_shell_command_record_item`
   - 注入到对话历史中或记录为对话项

#### 命令格式化流程

```rust
// 1. 派生执行参数
let display_command = session_shell.derive_exec_args(&command, use_login_shell);

// 2. 可选：包装 shell 快照
let exec_command = maybe_wrap_shell_lc_with_snapshot(
    &display_command,
    session_shell.as_ref(),
    turn_context.cwd.as_path(),
    &turn_context.shell_environment_policy.r#set,
);
```

### 测试辅助工具

#### `core_test_support` 提供的关键工具

1. **`test_codex()`**：创建测试用的 Codex 实例构建器
2. **`start_mock_server()`**：启动模拟的 OpenAI API 服务器
3. **`wait_for_event()` / `wait_for_event_match()`**：等待特定事件
4. **`wait_for_event_with_timeout()`**：带超时的事件等待
5. **`responses::mount_sse_once()`**：挂载 SSE 响应模拟
6. **`responses::mount_sse_sequence()`**：挂载顺序 SSE 响应序列

#### 事件构造辅助函数

```rust
responses::ev_response_created("resp-1"),
responses::ev_function_call(call_id, "shell_command", &args),
responses::ev_completed("resp-1"),
responses::ev_assistant_message("msg-1", "done"),
```

---

## 关键代码路径与文件引用

### 核心实现文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/src/tasks/user_shell.rs` | 用户 Shell 命令任务的核心实现 |
| `codex-rs/core/src/user_shell_command.rs` | 用户命令历史记录格式化 |
| `codex-rs/core/src/exec.rs` | 命令执行底层实现 |
| `codex-rs/core/src/shell.rs` | Shell 类型和参数派生 |

### 协议定义文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/protocol/src/protocol.rs` | `EventMsg`、`ExecCommandBeginEvent`、`ExecCommandEndEvent` 等定义 |
| `codex-rs/protocol/src/user_input.rs` | `UserInput` 类型定义 |

### 测试支持文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/tests/common/lib.rs` | 通用测试辅助函数 |
| `codex-rs/core/tests/common/test_codex.rs` | `TestCodex` 和 `TestCodexBuilder` 实现 |
| `codex-rs/core/tests/common/responses.rs` | Mock 服务器和响应构造 |

### 关键代码引用

#### 用户 Shell 命令任务执行入口
```rust
// codex-rs/core/src/tasks/user_shell.rs:75-92
async fn run(
    self: Arc<Self>,
    session: Arc<SessionTaskContext>,
    turn_context: Arc<TurnContext>,
    _input: Vec<UserInput>,
    cancellation_token: CancellationToken,
) -> Option<String> {
    execute_user_shell_command(
        session.clone_session(),
        turn_context,
        self.command.clone(),
        cancellation_token,
        UserShellCommandMode::StandaloneTurn,
    )
    .await;
    None
}
```

#### 历史记录格式化
```rust
// codex-rs/core/src/user_shell_command.rs:36-43
pub fn format_user_shell_command_record(
    command: &str,
    exec_output: &ExecToolCallOutput,
    turn_context: &TurnContext,
) -> String {
    let body = format_user_shell_command_body(command, exec_output, turn_context);
    USER_SHELL_COMMAND_FRAGMENT.wrap(body)
}
```

---

## 依赖与外部交互

### 外部依赖

1. **Wiremock**：用于模拟 OpenAI API 服务器
2. **Tokio**：异步运行时
3. **Tempfile**：创建临时目录
4. **Serde JSON**：JSON 序列化/反序列化
5. **Regex Lite**：正则表达式匹配

### 内部依赖

1. **codex_core**：核心功能实现
2. **codex_protocol**：协议类型定义
3. **core_test_support**：测试支持库

### 环境交互

1. **文件系统**：创建临时目录和测试文件
2. **Shell 执行**：调用系统 Shell 执行命令
3. **环境变量**：
   - `CODEX_SANDBOX`：沙箱类型标识
   - `CODEX_SANDBOX_NETWORK_DISABLED`：网络沙箱状态

### 平台差异处理

```rust
#[cfg(windows)]
let command = r#"$val = $env:CODEX_SANDBOX; ..."#;  // PowerShell
#[cfg(not(windows))]
let command = r#"sh -c "printf '%s' \"${CODEX_SANDBOX:-not-set}\"""#;  // POSIX sh
```

---

## 风险、边界与改进建议

### 已知风险

1. **平台差异**：Windows 和 Unix 系统的命令语法差异需要分别测试
2. **超时依赖**：测试依赖 `tokio::time::timeout`，在慢速 CI 环境可能不稳定
3. **环境依赖**：部分测试需要网络访问（通过 `skip_if_no_network!` 宏跳过）

### 边界情况

1. **空输出处理**：命令输出为空时的格式化行为
2. **超长命令**：命令字符串长度限制未明确测试
3. **特殊字符**：命令中包含特殊 Shell 字符的转义处理
4. **并发限制**：多个用户 Shell 命令同时执行的边界

### 改进建议

1. **增加测试覆盖率**：
   - 添加命令执行失败（非零退出码）的测试用例
   - 测试标准错误输出（stderr）的记录
   - 测试包含特殊字符的命令

2. **性能优化**：
   - 考虑并行执行独立的测试用例
   - 优化 Mock 服务器的响应时间

3. **可维护性**：
   - 提取通用的测试设置代码到辅助函数
   - 使用参数化测试减少重复代码

4. **文档完善**：
   - 添加更多关于 `UserShellCommandMode` 的文档
   - 说明历史记录截断算法的具体逻辑

### 相关 TODO

```rust
// TODO(ccunningham): After TurnStarted, emit model-visible turn context diffs...
// TODO(zhao-oai): Now that we have ExecExpiration::Cancellation, we should use that...
```

这些 TODO 表明：
1. 计划改进 TurnStarted 后的上下文差异展示
2. 考虑使用 `ExecExpiration::Cancellation` 替代固定超时
