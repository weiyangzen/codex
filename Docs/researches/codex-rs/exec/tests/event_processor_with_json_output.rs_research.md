# event_processor_with_json_output.rs 研究文档

## 场景与职责

`event_processor_with_json_output.rs` 是 `codex-exec` crate 的核心单元测试文件，专门测试 `EventProcessorWithJsonOutput` 结构体的行为。该处理器负责将 Codex 内部协议事件（`protocol::Event`）转换为面向用户的 JSONL 输出格式（`ThreadEvent`）。

**核心职责：**
1. 验证事件转换逻辑的正确性（协议事件 → 线程事件）
2. 确保 JSONL 输出格式符合预期结构
3. 测试各种边界情况（缺失的开始事件、错误处理等）
4. 验证状态管理（运行中命令、待办列表、MCP 调用等）

## 功能点目的

### 1. 事件转换测试

测试将内部 `protocol::Event` 转换为外部 `ThreadEvent` 的所有路径：

| 测试函数 | 测试场景 |
|---------|---------|
| `session_configured_produces_thread_started_event` | 会话配置事件 → 线程开始事件 |
| `task_started_produces_turn_started_event` | 任务开始 → 轮次开始 |
| `web_search_begin_emits_item_started` | 网络搜索开始 → 项目开始 |
| `web_search_end_emits_item_completed` | 网络搜索结束 → 项目完成 |
| `web_search_begin_then_end_reuses_item_id` | 验证事件对使用相同 item_id |

### 2. 复杂工作流测试

| 测试函数 | 测试场景 |
|---------|---------|
| `plan_update_emits_todo_list_started_updated_and_completed` | 计划更新工作流（开始→更新→完成） |
| `plan_update_after_complete_starts_new_todo_list_with_new_id` | 新一轮次生成新的待办列表 ID |
| `mcp_tool_call_begin_and_end_emit_item_events` | MCP 工具调用完整生命周期 |
| `mcp_tool_call_failure_sets_failed_status` | MCP 调用失败处理 |
| `mcp_tool_call_defaults_arguments_and_preserves_structured_content` | 参数默认值和结构化内容保留 |

### 3. 协作代理测试

| 测试函数 | 测试场景 |
|---------|---------|
| `collab_spawn_begin_and_end_emit_item_events` | 协作代理创建生命周期 |
| `collab_wait_end_without_begin_synthesizes_failed_item` | 缺失开始事件时的失败合成 |

### 4. 命令执行测试

| 测试函数 | 测试场景 |
|---------|---------|
| `exec_command_end_success_produces_completed_command_item` | 命令成功执行 |
| `exec_command_end_failure_produces_failed_command_item` | 命令失败执行 |
| `command_execution_output_delta_updates_item_progress` | 输出增量更新 |
| `exec_command_end_without_begin_is_ignored` | 孤立结束事件处理 |

### 5. 补丁应用测试

| 测试函数 | 测试场景 |
|---------|---------|
| `patch_apply_success_produces_item_completed_patchapply` | 补丁成功应用 |
| `patch_apply_failure_produces_item_completed_patchapply_failed` | 补丁应用失败 |

### 6. 错误处理测试

| 测试函数 | 测试场景 |
|---------|---------|
| `error_event_produces_error` | 错误事件转换 |
| `warning_event_produces_error_item` | 警告作为错误项目 |
| `stream_error_event_produces_error` | 流错误处理 |
| `error_followed_by_task_complete_produces_turn_failed` | 错误导致轮次失败 |

### 7. Token 使用统计

| 测试函数 | 测试场景 |
|---------|---------|
| `task_complete_produces_turn_completed_with_usage` | Token 使用统计传递 |

## 具体技术实现

### 核心数据结构

```rust
// 被测试的核心处理器
pub struct EventProcessorWithJsonOutput {
    last_message_path: Option<PathBuf>,
    last_proposed_plan: Option<String>,
    next_event_id: AtomicU64,
    running_commands: HashMap<String, RunningCommand>,
    running_patch_applies: HashMap<String, protocol::PatchApplyBeginEvent>,
    running_todo_list: Option<RunningTodoList>,
    last_total_token_usage: Option<codex_protocol::protocol::TokenUsage>,
    running_mcp_tool_calls: HashMap<String, RunningMcpToolCall>,
    running_collab_tool_calls: HashMap<String, RunningCollabToolCall>,
    running_web_search_calls: HashMap<String, String>,
    last_critical_error: Option<ThreadErrorEvent>,
}
```

### 辅助结构体

```rust
#[derive(Debug, Clone)]
struct RunningCommand {
    command: String,
    item_id: String,
    aggregated_output: String,
}

#[derive(Debug, Clone)]
struct RunningTodoList {
    item_id: String,
    items: Vec<TodoItem>,
}

#[derive(Debug, Clone)]
struct RunningMcpToolCall {
    server: String,
    tool: String,
    item_id: String,
    arguments: JsonValue,
}

#[derive(Debug, Clone)]
struct RunningCollabToolCall {
    tool: CollabTool,
    item_id: String,
}
```

### 事件转换核心方法

```rust
impl EventProcessorWithJsonOutput {
    pub fn collect_thread_events(&mut self, event: &protocol::Event) -> Vec<ThreadEvent> {
        match &event.msg {
            protocol::EventMsg::SessionConfigured(ev) => self.handle_session_configured(ev),
            protocol::EventMsg::AgentMessage(ev) => self.handle_agent_message(ev),
            protocol::EventMsg::ExecCommandBegin(ev) => self.handle_exec_command_begin(ev),
            protocol::EventMsg::ExecCommandEnd(ev) => self.handle_exec_command_end(ev),
            protocol::EventMsg::McpToolCallBegin(ev) => self.handle_mcp_tool_call_begin(ev),
            protocol::EventMsg::McpToolCallEnd(ev) => self.handle_mcp_tool_call_end(ev),
            // ... 其他事件处理
        }
    }
}
```

### 测试辅助函数

```rust
fn event(id: &str, msg: EventMsg) -> Event {
    Event {
        id: id.to_string(),
        msg,
    }
}
```

## 关键代码路径与文件引用

### 被测试代码

| 文件 | 内容 |
|-----|------|
| `codex-rs/exec/src/event_processor_with_jsonl_output.rs` | `EventProcessorWithJsonOutput` 实现 |
| `codex-rs/exec/src/exec_events.rs` | `ThreadEvent` 和 `ThreadItem` 定义 |

### 依赖的协议类型

```rust
// 来自 codex_protocol crate
use codex_protocol::protocol::{
    Event, EventMsg, SessionConfiguredEvent, TurnStartedEvent,
    ExecCommandBeginEvent, ExecCommandEndEvent, ExecCommandOutputDeltaEvent,
    McpToolCallBeginEvent, McpToolCallEndEvent,
    CollabAgentSpawnBeginEvent, CollabAgentSpawnEndEvent, CollabWaitingEndEvent,
    PatchApplyBeginEvent, PatchApplyEndEvent,
    WebSearchBeginEvent, WebSearchEndEvent,
    AgentMessageEvent, AgentReasoningEvent,
    ErrorEvent, WarningEvent, TurnCompleteEvent,
};
```

### 事件类型映射

| 协议事件 (protocol) | 线程事件 (ThreadEvent) |
|-------------------|----------------------|
| `SessionConfigured` | `ThreadStarted` |
| `TurnStarted` | `TurnStarted` |
| `TurnComplete` | `TurnCompleted` / `TurnFailed` |
| `ExecCommandBegin` | `ItemStarted(CommandExecution)` |
| `ExecCommandEnd` | `ItemCompleted(CommandExecution)` |
| `McpToolCallBegin` | `ItemStarted(McpToolCall)` |
| `McpToolCallEnd` | `ItemCompleted(McpToolCall)` |
| `PatchApplyBegin` | (无输出，仅记录) |
| `PatchApplyEnd` | `ItemCompleted(FileChange)` |
| `WebSearchBegin` | `ItemStarted(WebSearch)` |
| `WebSearchEnd` | `ItemCompleted(WebSearch)` |
| `PlanUpdate` | `ItemStarted/ItemUpdated(TodoList)` |
| `AgentMessage` | `ItemCompleted(AgentMessage)` |
| `AgentReasoning` | `ItemCompleted(Reasoning)` |
| `Error` | `Error` |
| `Warning` | `ItemCompleted(Error)` |

## 依赖与外部交互

### 测试依赖

```rust
[dev-dependencies]
pretty_assertions = { workspace = true }
rmcp = { workspace = true }  // 用于 MCP 类型
serde_json = { workspace = true }
```

### 外部 crate 类型使用

| Crate | 使用目的 |
|-------|---------|
| `pretty_assertions` | 美观的断言失败输出 |
| `rmcp::model::Content` | MCP 工具结果内容 |
| `serde_json::json!` | 构造测试 JSON 数据 |
| `std::time::Duration` | 命令执行时长 |

### 协议 crate 依赖

```rust
use codex_protocol::{
    ThreadId,
    config_types::ModeKind,
    mcp::CallToolResult,
    models::WebSearchAction,
    openai_models::ReasoningEffort,
    plan_tool::{PlanItemArg, StepStatus, UpdatePlanArgs},
    protocol::*,
};
```

## 风险、边界与改进建议

### 当前风险

1. **状态泄漏风险**：测试中 `EventProcessorWithJsonOutput` 的 `running_commands` 等 HashMap 可能在测试间累积状态（虽然每个测试创建新实例）
2. **TODO 遗留**：`handle_output_chunk` 和 `handle_terminal_interaction` 方法标记为 TODO，未完全实现
3. **HashMap 迭代顺序**：`collab_wait_end_without_begin_synthesizes_failed_item` 测试中显式排序 `receiver_thread_ids` 以避免非确定性

### 边界情况处理

| 边界情况 | 处理方式 |
|---------|---------|
| 命令结束无对应开始 | 记录警告，忽略事件 |
| MCP 调用结束无对应开始 | 合成新 item（降级处理） |
| 协作等待结束无对应开始 | 合成失败 item |
| 参数为 None | 默认使用 `JsonValue::Null` |
| 退出码非零 | 标记为 `CommandExecutionStatus::Failed` |

### 测试覆盖缺口

1. **输出增量处理**：`handle_output_chunk` 返回空 Vec，未测试实际增量更新
2. **终端交互**：`handle_terminal_interaction` 返回空 Vec，未测试
3. **协作交互**：`CollabAgentInteractionBegin/End` 未在测试中覆盖
4. **协作关闭**：`CollabCloseBegin/End` 未在测试中覆盖

### 改进建议

1. **补充 TODO 测试**：为 `handle_output_chunk` 和 `handle_terminal_interaction` 添加测试
2. **协作测试扩展**：添加 `CollabAgentInteraction` 和 `CollabClose` 的测试用例
3. **并发测试**：测试多命令同时运行时的状态隔离
4. **错误注入**：测试更多错误边界（如无效的 call_id、损坏的事件序列）
5. **性能测试**：测试大量事件流处理的性能特征
6. **序列化验证**：显式验证生成的 JSON 符合预期模式

### 代码质量建议

1. 测试中使用 `unwrap_or_else` 生成新 ID 的模式可以提取为辅助方法
2. 大量重复的 `event()` 构造可以进一步简化
3. 考虑使用 `insta` snapshot 测试来验证复杂的 JSON 输出
