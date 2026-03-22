# TurnStartResponse.json 研究文档

## 场景与职责

`TurnStartResponse` 是 Codex App-Server Protocol v2 中 `turn/start` RPC 方法的响应结构。它在客户端发起新 Turn 请求后返回，携带了新创建 Turn 的初始状态信息。

**核心职责：**
- 返回新创建 Turn 的完整状态
- 提供 Turn ID 供后续操作引用
- 返回 Turn 的初始 items 列表（在 thread/resume 或 thread/fork 时填充）
- 指示 Turn 的当前状态（进行中、已完成、中断或失败）

## 功能点目的

### 1. Turn 状态传递
响应包含一个完整的 `Turn` 对象，其中：
- `id`: Turn 的唯一标识符
- `status`: Turn 状态（completed/interrupted/failed/inProgress）
- `items`: Turn 中的项目列表（通常为空，除非在 thread/resume 或 thread/fork 响应中）
- `error`: 仅当 status 为 failed 时填充

### 2. 异步处理确认
`turn/start` 是异步操作：
- 响应返回时 Turn 可能仍在 `inProgress` 状态
- 客户端需要通过 `turn/started` 和 `turn/completed` 通知跟踪实际进度
- Turn ID 用于关联后续的 steer/interrupt 操作

### 3. 与 ThreadItem 的关联
`Turn` 的 `items` 字段是 `Vec<ThreadItem>`，包含：
- `UserMessage`: 用户消息（包含 UserInput）
- `AgentMessage`: 助手消息
- `CommandExecution`: 命令执行
- `FileChange`: 文件变更
- `McpToolCall`: MCP 工具调用
- `DynamicToolCall`: 动态工具调用
- `CollabAgentToolCall`: 协作代理工具调用
- `WebSearch`: 网页搜索
- `ImageView`: 图片查看
- `ImageGeneration`: 图片生成
- `Reasoning`: 推理内容
- `Plan`: 计划（实验性）
- `EnteredReviewMode`/`ExitedReviewMode`: 审查模式切换
- `ContextCompaction`: 上下文压缩

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TurnStartResponse {
    pub turn: Turn,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct Turn {
    pub id: String,
    /// Only populated on a `thread/resume` or `thread/fork` response.
    /// For all other responses and notifications returning a Turn,
    /// the items field will be an empty list.
    pub items: Vec<ThreadItem>,
    pub status: TurnStatus,
    /// Only populated when the Turn's status is failed.
    pub error: Option<TurnError>,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum TurnStatus {
    Completed,
    Interrupted,
    Failed,
    InProgress,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS, Error)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TurnError {
    pub message: String,
    pub codex_error_info: Option<CodexErrorInfo>,
    #[serde(default)]
    pub additional_details: Option<String>,
}
```

### ThreadItem 枚举

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "camelCase")]
#[ts(tag = "type")]
#[ts(export_to = "v2/")]
pub enum ThreadItem {
    UserMessage { id: String, content: Vec<UserInput> },
    AgentMessage { id: String, text: String, phase: Option<MessagePhase>, memory_citation: Option<MemoryCitation> },
    Plan { id: String, text: String },
    Reasoning { id: String, summary: Vec<String>, content: Vec<String> },
    CommandExecution { id: String, command: String, cwd: PathBuf, process_id: Option<String>, source: CommandExecutionSource, status: CommandExecutionStatus, command_actions: Vec<CommandAction>, aggregated_output: Option<String>, exit_code: Option<i32>, duration_ms: Option<i64> },
    FileChange { id: String, changes: Vec<FileUpdateChange>, status: PatchApplyStatus },
    McpToolCall { id: String, server: String, tool: String, status: McpToolCallStatus, arguments: JsonValue, result: Option<McpToolCallResult>, error: Option<McpToolCallError>, duration_ms: Option<i64> },
    DynamicToolCall { id: String, tool: String, arguments: JsonValue, status: DynamicToolCallStatus, content_items: Option<Vec<DynamicToolCallOutputContentItem>>, success: Option<bool>, duration_ms: Option<i64> },
    CollabAgentToolCall { id: String, tool: CollabAgentTool, status: CollabAgentToolCallStatus, sender_thread_id: String, receiver_thread_ids: Vec<String>, prompt: Option<String>, model: Option<String>, reasoning_effort: Option<ReasoningEffort>, agents_states: HashMap<String, CollabAgentState> },
    WebSearch { id: String, query: String, action: Option<WebSearchAction> },
    ImageView { id: String, path: String },
    ImageGeneration { id: String, status: String, revised_prompt: Option<String>, result: String },
    EnteredReviewMode { id: String, review: String },
    ExitedReviewMode { id: String, review: String },
    ContextCompaction { id: String },
}
```

### 关键流程

1. **Turn 创建**：服务器接收 `turn/start` 请求，创建新 Turn
2. **初始响应**：立即返回 `TurnStartResponse`，状态通常为 `InProgress`
3. **异步通知**：
   - 发送 `turn/started` 通知
   - 处理过程中发送各种 `item/*` 通知
   - 完成时发送 `turn/completed` 通知

## 关键代码路径与文件引用

### 定义位置
- `TurnStartResponse`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:3937`
- `Turn`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:3583`
- `TurnStatus`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:3555`
- `TurnError`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:3632`
- `ThreadItem`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:4121`

### 使用位置
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs:351-355`
  - 注册为 `turn/start` 的响应类型
- `/home/sansha/Github/codex/codex-rs/app-server/tests/suite/v2/turn_start.rs`
  - 测试用例中验证响应结构

### 相关通知类型
- `TurnStartedNotification`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:4671`
- `TurnCompletedNotification`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:4697`

## 依赖与外部交互

### 上游依赖
- `ThreadItem`: 定义在 v2.rs，包含所有可能的 Turn 项目类型
- `CodexErrorInfo`: 错误信息类型，包含多种错误变体
- `MessagePhase`: 消息阶段（commentary/final_answer）
- `MemoryCitation`: 内存引用信息

### 下游消费
- 客户端（TUI、VSCode 扩展）接收响应并更新 UI
- 客户端使用 `turn.id` 进行后续的 `turn/steer` 或 `turn/interrupt` 操作

### 协议集成
- 作为 JSON-RPC 2.0 响应的 `result` 字段
- 请求方法: `turn/start`
- 请求参数: `TurnStartParams`

## 风险、边界与改进建议

### 已知风险

1. **Items 字段的延迟填充**
   - `items` 字段在普通 `turn/start` 响应中为空列表
   - 仅在 `thread/resume` 或 `thread/fork` 时填充
   - 客户端不能依赖响应中的 `items` 获取完整历史

2. **状态同步问题**
   - 响应返回时 Turn 可能仍在 `InProgress` 状态
   - 客户端需要正确处理异步状态流转
   - 网络中断可能导致错过 `turn/completed` 通知

3. **Error 字段的条件填充**
   - `error` 仅在 `status == Failed` 时填充
   - 客户端需要检查状态后再访问 error

### 边界情况

1. **Turn ID 唯一性**
   - Turn ID 在单个线程内唯一
   - 跨线程可能重复（但通常使用 UUID）

2. **并发 Turn 限制**
   - 一个线程通常只能有一个活动的 Turn
   - 尝试在 Turn 进行中启动新 Turn 可能被拒绝

3. **Items 列表大小**
   - 在 `thread/resume` 时可能包含大量历史 items
   - 客户端需要考虑内存和渲染性能

### 改进建议

1. **API 语义澄清**
   - 考虑为 `items` 字段添加更明确的文档说明
   - 考虑区分 "初始响应" 和 "完整状态" 两种响应类型

2. **错误处理增强**
   - 考虑在 `TurnError` 中添加错误代码枚举
   - 为不同类型的失败提供结构化错误信息

3. **状态追踪改进**
   - 考虑添加 `Turn` 的 `created_at` 和 `updated_at` 时间戳
   - 有助于调试和超时处理

4. **性能优化**
   - 对于大量 items 的场景，考虑分页或懒加载机制
   - 在 `thread/resume` 时只返回最近的 N 个 items

5. **类型安全**
   - 考虑为 `Turn.id` 使用强类型 `TurnId` 而非裸 `String`
   - 类似地，为 `Thread.id` 使用 `ThreadId`
