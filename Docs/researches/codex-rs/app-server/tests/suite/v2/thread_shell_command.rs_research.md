# thread_shell_command.rs 研究文档

## 场景与职责

`thread_shell_command.rs` 是 Codex App Server v2 API 的集成测试文件，专门测试**线程 Shell 命令（Thread Shell Command）**功能。该功能允许用户在对话线程中直接执行 Shell 命令（以 `!` 开头的命令），作为独立的 Turn 或在现有 Turn 中执行。这是 Codex 作为编程助手的重要能力，让用户可以直接在对话环境中运行代码。

### 核心测试场景

1. **独立 Turn 执行** - Shell 命令作为独立的 Turn 执行并持久化历史
2. **活跃 Turn 复用** - 在 Agent 正在执行的 Turn 中插入用户 Shell 命令
3. **命令输出流式传输** - 验证命令输出通过 SSE 流式传输
4. **持久化验证** - 确认 Shell 命令执行记录正确保存到 rollout 文件

## 功能点目的

### Thread Shell Command 的核心价值

- **即时执行**: 用户可以直接在对话中运行 Shell 命令，无需切换上下文
- **环境验证**: 快速验证代码行为、检查文件状态
- **交互式工作流**: 在 Agent 工作时并行执行命令
- **历史记录**: 所有命令执行都被记录，便于审计和复现

### 命令来源区分

```rust
pub enum CommandExecutionSource {
    Agent,      // Agent 发起的命令（如代码执行）
    UserShell,  // 用户通过 !command 发起的命令
}
```

### 关键测试功能点

| 测试函数 | 目的 |
|---------|------|
| `thread_shell_command_runs_as_standalone_turn_and_persists_history` | 验证独立 Turn 执行和持久化 |
| `thread_shell_command_uses_existing_active_turn` | 验证在活跃 Turn 中插入执行 |

## 具体技术实现

### 关键数据结构

#### ThreadShellCommandParams
```rust
pub struct ThreadShellCommandParams {
    pub thread_id: String,
    pub command: String,  // 要执行的 Shell 命令
}
```

#### ThreadShellCommandResponse
```rust
pub struct ThreadShellCommandResponse {
    // 命令已提交执行的确认
}
```

#### CommandExecution 相关通知

```rust
// 命令开始执行
pub struct ItemStartedNotification {
    pub turn_id: String,
    pub item: ThreadItem::CommandExecution {
        id: String,
        command: String,
        source: CommandExecutionSource::UserShell,
        status: CommandExecutionStatus::InProgress,
        // ...
    },
}

// 输出增量更新
pub struct CommandExecutionOutputDeltaNotification {
    pub item_id: String,
    pub delta: String,  // 新输出的文本片段
}

// 命令完成
pub struct ItemCompletedNotification {
    pub turn_id: String,
    pub item: ThreadItem::CommandExecution {
        status: CommandExecutionStatus::Completed,
        aggregated_output: Option<String>,
        exit_code: Option<i32>,
        // ...
    },
}
```

### 关键流程

#### 1. 独立 Turn 执行流程

```
Client -> thread/shellCommand (command="printf 'hello\n'")
    |
    v
Server 创建新的 Turn
    |
    v
启动 Shell 进程执行命令
    |
    v
发送 item/started 通知
    |
    v
流式发送 item/commandExecution/outputDelta 通知
    |
    v
命令完成，发送 item/completed 通知
    |
    v
发送 turn/completed 通知
    |
    v
持久化到 rollout 文件
```

#### 2. 活跃 Turn 复用流程

```
Client A -> turn/start (Agent 开始工作)
    |
    v
Agent 请求命令执行 -> 等待用户批准
    |
Client B -> thread/shellCommand
    |
    v
Server 检测到存在活跃 Turn
    |
    v
在同一个 Turn 中插入 CommandExecution item
    |
    v
复用现有的 Turn 上下文
```

### 核心代码路径

#### 测试辅助函数

```rust
// 等待命令执行开始通知
async fn wait_for_command_execution_started(
    mcp: &mut McpProcess,
    expected_id: Option<&str>,
) -> Result<ItemStartedNotification>

// 按来源等待命令执行开始
async fn wait_for_command_execution_started_by_source(
    mcp: &mut McpProcess,
    expected_source: CommandExecutionSource,
) -> Result<ItemStartedNotification>

// 等待命令执行完成
async fn wait_for_command_execution_completed(
    mcp: &mut McpProcess,
    expected_id: Option<&str>,
) -> Result<ItemCompletedNotification>

// 等待输出增量
async fn wait_for_command_execution_output_delta(
    mcp: &mut McpProcess,
    item_id: &str,
) -> Result<CommandExecutionOutputDeltaNotification>
```

#### 命令格式化

```rust
// 使用当前 Shell 格式化命令
pub fn format_with_current_shell_display(command: &str) -> String {
    // 例如: "python3 -c 'print(42)'"
}
```

## 关键代码路径与文件引用

### 主要测试文件
- `codex-rs/app-server/tests/suite/v2/thread_shell_command.rs` - 本文件，包含 2 个测试用例

### 被测实现文件
- `codex-rs/app-server/src/codex_message_processor.rs` - 处理 thread/shellCommand 请求
- `codex-rs/app-server/src/command_exec.rs` - 命令执行实现

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs`:
  - `ThreadShellCommandParams`
  - `ThreadShellCommandResponse`
  - `CommandExecutionSource`
  - `CommandExecutionStatus`
  - `CommandExecutionOutputDeltaNotification`

### 测试基础设施
- `codex-rs/app-server/tests/common/mcp_process.rs` - MCP 进程管理
- `codex-rs/app-server/tests/common/mock_model_server.rs` - Mock 模型服务器
- `codex-rs/core_test_support/src/lib.rs` - Shell 格式化辅助

## 依赖与外部交互

### 测试详解：独立 Turn 执行

```rust
#[tokio::test]
async fn thread_shell_command_runs_as_standalone_turn_and_persists_history() -> Result<()> {
    // 1. 设置环境
    let tmp = TempDir::new()?;
    let codex_home = tmp.path().join("codex_home");
    let workspace = tmp.path().join("workspace");
    
    // 2. 创建 Mock 服务器（空响应，因为不需要 Agent 响应）
    let server = create_mock_responses_server_sequence(vec![]).await;
    
    // 3. 初始化 MCP
    let mut mcp = McpProcess::new(codex_home.as_path()).await?;
    
    // 4. 创建线程（启用扩展历史持久化）
    let start_resp = mcp.send_thread_start_request(ThreadStartParams {
        persist_extended_history: true,
        ..Default::default()
    }).await?;
    
    // 5. 发送 Shell 命令
    let shell_resp = mcp.send_thread_shell_command_request(ThreadShellCommandParams {
        thread_id: thread.id.clone(),
        command: "printf 'hello from bang\n'".to_string(),
    }).await?;
    
    // 6. 验证执行流程
    // 6.1 等待 item/started 通知
    let started = wait_for_command_execution_started(&mut mcp, None).await?;
    assert_eq!(started.item.source, CommandExecutionSource::UserShell);
    assert_eq!(started.item.status, CommandExecutionStatus::InProgress);
    
    // 6.2 等待输出增量
    let delta = wait_for_command_execution_output_delta(&mut mcp, &command_id).await?;
    assert_eq!(delta.delta, "hello from bang\n");
    
    // 6.3 等待 item/completed 通知
    let completed = wait_for_command_execution_completed(&mut mcp, Some(&command_id)).await?;
    assert_eq!(completed.item.status, CommandExecutionStatus::Completed);
    assert_eq!(completed.item.aggregated_output, Some("hello from bang\n".to_string()));
    assert_eq!(completed.item.exit_code, Some(0));
    
    // 6.4 等待 turn/completed
    timeout(
        DEFAULT_READ_TIMEOUT,
        mcp.read_stream_until_notification_message("turn/completed"),
    ).await??;
    
    // 7. 验证持久化
    let read_resp = mcp.send_thread_read_request(ThreadReadParams {
        thread_id: thread.id,
        include_turns: true,
    }).await?;
    
    // 验证 Turn 中包含 CommandExecution item
    assert_eq!(thread.turns.len(), 1);
    let command_item = thread.turns[0].items.iter()
        .find(|item| matches!(item, ThreadItem::CommandExecution { .. }))
        .expect("expected persisted command execution item");
}
```

### 测试详解：活跃 Turn 复用

```rust
#[tokio::test]
async fn thread_shell_command_uses_existing_active_turn() -> Result<()> {
    // 1. 设置 Mock 服务器，提供 Agent 命令执行响应
    let responses = vec![
        create_shell_command_sse_response(
            vec!["python3", "-c", "print(42)"],
            None,
            Some(5000),  // 5秒超时
            "call-approve",
        )?,
        create_final_assistant_message_sse_response("done")?,
    ];
    let server = create_mock_responses_server_sequence(responses).await;
    
    // 2. 创建线程并启动 Turn
    let turn_id = mcp.send_turn_start_request(TurnStartParams {
        thread_id: thread.id.clone(),
        input: vec![V2UserInput::Text { text: "run python".to_string(), .. }],
        cwd: Some(workspace.clone()),
        ..Default::default()
    }).await?;
    
    // 3. 等待 Agent 请求命令执行批准
    let agent_started = wait_for_command_execution_started(&mut mcp, Some("call-approve")).await?;
    assert_eq!(agent_started.item.source, CommandExecutionSource::Agent);
    
    // 4. 在 Agent 等待批准期间，发送用户 Shell 命令
    let shell_resp = mcp.send_thread_shell_command_request(ThreadShellCommandParams {
        thread_id: thread.id.clone(),
        command: "printf 'active turn bang\n'".to_string(),
    }).await?;
    
    // 5. 验证用户命令在同一个 Turn 中执行
    let started = wait_for_command_execution_started_by_source(
        &mut mcp, 
        CommandExecutionSource::UserShell
    ).await?;
    assert_eq!(started.turn_id, turn.id);  // 关键验证：相同的 Turn ID
    
    // 6. 完成用户命令
    let completed = wait_for_command_execution_completed(&mut mcp, Some(&command_id)).await?;
    assert_eq!(completed.turn_id, turn.id);
    
    // 7. 响应 Agent 的批准请求
    mcp.send_response(request_id, serde_json::to_value(
        CommandExecutionRequestApprovalResponse { decision: CommandExecutionApprovalDecision::Decline }
    )?).await?;
    
    // 8. 验证持久化包含用户命令
    let read_resp = mcp.send_thread_read_request(...).await?;
    assert!(thread.turns[0].items.iter().any(|item| {
        matches!(item, ThreadItem::CommandExecution {
            source: CommandExecutionSource::UserShell,
            aggregated_output,
            ..
        } if aggregated_output.as_deref() == Some("active turn bang\n"))
    }));
}
```

### 依赖关系

```
thread_shell_command.rs
    |
    +-> app_test_support
    |       +-> McpProcess
    |       +-> create_mock_responses_server_sequence
    |       +-> create_shell_command_sse_response
    |       +-> create_final_assistant_message_sse_response
    |       +-> format_with_current_shell_display
    |
    +-> codex_app_server_protocol
    |       +-> ThreadShellCommandParams/Response
    |       +-> CommandExecutionSource
    |       +-> CommandExecutionStatus
    |       +-> CommandExecutionOutputDeltaNotification
    |       +-> ItemStartedNotification
    |       +-> ItemCompletedNotification
    |       +-> TurnCompletedNotification
    |
    +-> codex_core::features
    |       +-> FEATURES (功能标志检查)
    |
    +-> codex_protocol
            +-> ThreadItem
```

## 风险、边界与改进建议

### 当前测试覆盖的局限

1. **有限的测试数量**
   - 仅 2 个测试用例
   - 许多边界情况未覆盖

2. **未覆盖的场景**
   - 命令执行失败（非零退出码）
   - 长时间运行的命令
   - 大输出量的命令
   - 特殊字符和编码
   - 并发多个 Shell 命令
   - 取消正在执行的命令

3. **安全考虑**
   - 测试使用 `approval_policy = "never"` 或 `"untrusted"`
   - 未测试沙箱限制对 Shell 命令的影响

### 改进建议

1. **增加错误场景测试**
   ```rust
   #[tokio::test]
   async fn thread_shell_command_handles_failure() -> Result<()> {
       // 测试命令返回非零退出码
       let command = "exit 1";
       // 验证 exit_code = Some(1)
       // 验证 status = Completed (或 Failed)
   }
   ```

2. **增加超时测试**
   ```rust
   #[tokio::test]
   async fn thread_shell_command_timeout() -> Result<()> {
       // 测试长时间运行的命令
       let command = "sleep 100";
       // 验证可以中断/取消
   }
   ```

3. **增加并发测试**
   ```rust
   #[tokio::test]
   async fn thread_shell_command_concurrent() -> Result<()> {
       // 测试同时发送多个 Shell 命令
       // 验证正确的顺序和隔离
   }
   ```

4. **增加沙箱测试**
   ```rust
   #[tokio::test]
   async fn thread_shell_command_sandbox_restricted() -> Result<()> {
       // 测试在 read-only 沙箱中执行写操作
       // 验证适当的错误处理
   }
   ```

5. **验证输出流式传输**
   - 当前测试只验证单个 delta
   - 建议测试多行输出的流式传输

### 实现层面的潜在风险

1. **进程管理**
   - Shell 进程可能僵死
   - 需要确保超时和清理机制

2. **资源限制**
   - 大输出可能消耗大量内存
   - 需要流式处理和限制

3. **并发安全**
   - 多个 Shell 命令同时执行时的资源竞争
   - 工作目录的并发访问

4. **编码问题**
   - 非 UTF-8 输出的处理
   - 二进制输出的处理

### 与 Agent 命令执行的对比

| 特性 | UserShell | Agent |
|-----|-----------|-------|
| 来源 | 用户主动发起 | Agent 工具调用 |
| 批准流程 | 通常不需要 | 需要用户批准（根据策略） |
| 目的 | 用户环境操作 | 代码执行、测试 |
| 上下文 | 用户当前工作目录 | Agent 指定的工作目录 |
| 超时控制 | 用户可控 | Agent 配置 |

### 测试代码改进

1. **减少重复代码**
   - `create_config_toml` 在多个文件中重复
   - 建议提取到公共库

2. **增强验证**
   - 当前主要验证 source 和 status
   - 建议增加对 command、cwd、duration_ms 的验证

3. **清理资源**
   - 确保测试创建的进程被正确清理
   - 使用 `kill_on_drop` 模式
