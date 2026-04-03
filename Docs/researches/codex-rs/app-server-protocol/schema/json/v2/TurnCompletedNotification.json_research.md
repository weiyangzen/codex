# TurnCompletedNotification.json 研究文档

## 场景与职责

`TurnCompletedNotification` 是 Codex App-Server Protocol v2 中定义的服务器向客户端发送的关键通知类型，用于告知客户端某个 Turn（对话轮次）已完成。这是对话流程中最核心的通知之一，标志着一次完整的用户输入到 AI 响应的交互周期结束。

典型使用场景：
- AI 完成对用户输入的响应生成
- 所有工具调用和执行完成
- 文件修改操作完成
- 命令执行完成并返回结果
- 多轮对话中的每一轮结束标记

## 功能点目的

该通知的主要目的是：
1. **流程标记**：明确标记一个对话轮次的完成
2. **结果传递**：传递完成的 Turn 对象，包含所有生成的内容
3. **状态同步**：更新客户端的 Thread 状态
4. **触发后续操作**：客户端可以基于此通知执行保存、显示等操作

### Turn 完成流程

```
Client -> Server: turn/start (TurnStartParams)
Server -> Client: TurnStartedNotification
Server -> Client: ItemStartedNotification (多个)
Server -> Client: ItemCompletedNotification (多个)
Server -> Client: AgentMessageDeltaNotification (流式内容)
Server -> Client: TurnCompletedNotification (完成)
```

### Turn 状态

| 状态 | 说明 |
|------|------|
| `completed` | Turn 成功完成 |
| `interrupted` | Turn 被用户中断 |
| `failed` | Turn 执行失败 |
| `inProgress` | Turn 正在进行中 |

## 具体技术实现

### JSON Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "threadId": { "type": "string" },
    "turn": { "$ref": "#/definitions/Turn" }
  },
  "required": ["threadId", "turn"]
}
```

### Rust 实现

位于 `codex-rs/app-server-protocol/src/protocol/v2.rs`（行 4694-4700）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TurnCompletedNotification {
    pub thread_id: String,
    pub turn: Turn,
}
```

### Turn 结构定义

```rust
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

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum TurnStatus {
    Completed,
    Interrupted,
    Failed,
    InProgress,
}
```

### 服务端注册

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中：

```rust
server_notification_definitions! {
    TurnCompleted => "turn/completed" (v2::TurnCompletedNotification),
    // ...
}
```

## 关键代码路径与文件引用

### 核心定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/json/v2/TurnCompletedNotification.json` | JSON Schema 定义（约 37KB） |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（行 4694-4700） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 服务器通知注册（行 887） |

### Schema 文件结构

`TurnCompletedNotification.json` 包含以下内联定义：
- `Turn` - 完整的 Turn 类型
- `TurnStatus` - Turn 状态枚举
- `TurnError` - Turn 错误信息
- `ThreadItem` - Thread 中的项目类型（多种变体）
- `UserInput` - 用户输入类型
- `CommandAction` - 命令动作
- `PatchChangeKind` - 补丁变更类型
- `CodexErrorInfo` - Codex 错误信息
- 以及许多其他辅助类型

### 服务端发送代码

位于 `codex-rs/app-server/src/bespoke_event_handling.rs`：
- 处理来自核心 Codex 引擎的 Turn 完成事件
- 构建 `TurnCompletedNotification` 通知
- 发送给订阅了该 Thread 的所有客户端

位于 `codex-rs/tui_app_server/src/app.rs`：
- TUI 应用服务器处理 Turn 完成通知
- 更新应用状态和用户界面

### 客户端处理代码

位于 `codex-rs/app-server-client/src/lib.rs`：
- 客户端库处理 Turn 完成通知

位于 `codex-rs/tui_app_server/src/chatwidget.rs`：
- 聊天组件处理 Turn 完成事件

### 测试文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/tests/suite/v2/turn_start.rs` | Turn 启动测试 |
| `codex-rs/app-server/tests/suite/v2/turn_interrupt.rs` | Turn 中断测试 |
| `codex-rs/app-server/tests/suite/v2/thread_shell_command.rs` | Shell 命令测试 |
| `codex-rs/app-server/tests/suite/v2/plan_item.rs` | Plan 项目测试 |
| `codex-rs/app-server/tests/suite/v2/compaction.rs` | 压缩测试 |

## 依赖与外部交互

### 上游依赖

1. **codex_protocol::items::TurnItem**: 核心 Turn 项目类型
2. **codex_protocol::protocol**: 核心协议类型
3. **bespoke_event_handling**: 事件处理系统

### 下游消费者

1. **tui_app_server**: TUI 应用服务器更新界面
2. **VSCode 扩展**: 更新编辑器界面
3. **CLI 工具**: 显示 Turn 完成状态
4. **app-server-client**: 客户端库处理

### 相关通知类型

| 通知类型 | 说明 |
|---------|------|
| `TurnStartedNotification` | Turn 开始时的通知 |
| `ItemStartedNotification` | 项目开始时的通知 |
| `ItemCompletedNotification` | 项目完成时的通知 |
| `TurnDiffUpdatedNotification` | Turn 差异更新通知 |
| `TurnPlanUpdatedNotification` | Turn 计划更新通知 |

## 风险、边界与改进建议

### 潜在风险

1. **响应体积过大**：Schema 文件约 37KB，包含大量类型定义
2. **items 为空**：根据注释，TurnCompletedNotification 中的 `items` 通常为空列表
3. **状态竞争**：Turn 完成和客户端状态更新之间可能存在竞态条件

### 边界情况

1. **Turn 失败**：`status` 为 `failed` 时，`error` 字段包含错误信息
2. **Turn 中断**：用户主动中断 Turn，状态为 `interrupted`
3. **items 为空**：除 `thread/resume` 和 `thread/fork` 外，items 通常为空
4. **并发 Turns**：某些场景下可能有多个活跃的 Turn

### 改进建议

1. **包含 items 选项**：考虑添加参数控制是否在完成通知中包含 items
2. **摘要信息**：添加 Turn 摘要信息（如 Token 使用量、执行时间）
3. **完成原因**：添加更详细的完成原因（正常完成、超时、错误等）
4. **性能指标**：添加 Turn 执行的性能指标
5. **关联通知**：明确与其他通知（如 ItemCompleted）的关系

### 客户端处理示例

```typescript
// 示例：客户端处理 TurnCompletedNotification
function handleTurnCompleted(notification: TurnCompletedNotification) {
    const { threadId, turn } = notification;
    
    switch (turn.status) {
        case 'completed':
            console.log(`Turn ${turn.id} 成功完成`);
            updateThreadStatus(threadId, 'idle');
            // 注意：items 通常为空，需要调用 thread/read 获取完整内容
            refreshThreadContent(threadId);
            break;
            
        case 'interrupted':
            console.log(`Turn ${turn.id} 被中断`);
            updateThreadStatus(threadId, 'idle');
            showInterruptionNotice();
            break;
            
        case 'failed':
            console.error(`Turn ${turn.id} 失败:`, turn.error);
            updateThreadStatus(threadId, 'systemError');
            showErrorDialog(turn.error);
            break;
    }
}
```

### 版本兼容性

- 当前为 v2 API，遵循 camelCase 命名规范
- 与 v1 API 不兼容
- 注意 `items` 字段的行为差异（通常为空）
