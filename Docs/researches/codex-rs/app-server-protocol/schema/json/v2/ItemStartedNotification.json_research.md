# ItemStartedNotification.json 研究文档

## 场景与职责

`ItemStartedNotification` 是 Codex App Server Protocol v2 中的核心服务器通知类型，用于通知客户端某个 ThreadItem（线程项）已开始执行。它是 `ItemCompletedNotification` 的配对通知，共同构成完整的操作项生命周期事件流。

该通知在操作实际执行前发送，使客户端能够：
- 提前显示操作进行中状态
- 建立操作项的跟踪记录
- 实现乐观更新 UI

## 功能点目的

1. **操作开始通知**：在操作实际执行前通知客户端
2. **UI 乐观更新**：支持客户端立即显示操作进行中状态
3. **并发控制**：帮助客户端管理多个并发操作的状态
4. **超时检测**：客户端可基于开始时间检测操作超时
5. **流程编排**：支持基于操作开始的后续流程触发

## 具体技术实现

### 数据结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "item": { "$ref": "#/definitions/ThreadItem" },
    "threadId": { "type": "string" },
    "turnId": { "type": "string" }
  },
  "required": ["item", "threadId", "turnId"]
}
```

### ThreadItem 类型（Started 状态）

在 `ItemStartedNotification` 中，`ThreadItem` 的状态字段通常为 `inProgress`：

| 类型 | 状态字段 | 说明 |
|------|----------|------|
| `commandExecution` | `status: "inProgress"` | 命令开始执行 |
| `fileChange` | `status: "inProgress"` | 文件变更开始 |
| `mcpToolCall` | `status: "inProgress"` | MCP 工具调用开始 |
| `dynamicToolCall` | `status: "inProgress"` | 动态工具调用开始 |
| `collabAgentToolCall` | `status: "inProgress"` | 协作代理工具调用开始 |

### 与 Completed 通知的差异

虽然结构相同，但 `ItemStartedNotification` 中的 `ThreadItem` 通常：
- 状态为 `inProgress`
- 结果字段为 null 或未设置
- 执行时长为 null
- 输出内容为空或部分可用

### 协议映射

Rust 结构体定义（v2.rs）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ItemStartedNotification {
    pub item: ThreadItem,
    pub thread_id: String,
    pub turn_id: String,
}
```

服务器通知枚举（common.rs）：
```rust
server_notification_definitions! {
    ItemStarted => "item/started" (v2::ItemStartedNotification),
    ItemCompleted => "item/completed" (v2::ItemCompletedNotification),
}
```

Wire 格式：`method: "item/started"`

### 事件生成逻辑

**bespoke_event_handling.rs** 中的关键生成点：

1. **FileChange 开始**（行 486-505）：
```rust
let first_start = {
    let mut state = thread_state.lock().await;
    state.turn_summary.file_change_started.insert(item_id.clone())
};
if first_start {
    let item = ThreadItem::FileChange {
        id: item_id.clone(),
        changes: patch_changes.clone(),
        status: PatchApplyStatus::InProgress,
    };
    let notification = ItemStartedNotification {
        thread_id: conversation_id.to_string(),
        turn_id: event_turn_id.clone(),
        item,
    };
    outgoing.send_server_notification(...).await;
}
```

2. **DynamicToolCall 开始**（行 844-866）：
```rust
let item = ThreadItem::DynamicToolCall {
    id: call_id.clone(),
    tool: tool.clone(),
    arguments: arguments.clone(),
    status: DynamicToolCallStatus::InProgress,
    content_items: None,
    success: None,
    duration_ms: None,
};
let notification = ItemStartedNotification {
    thread_id: conversation_id.to_string(),
    turn_id: turn_id.clone(),
    item,
};
```

3. **McpToolCall 开始**（行 940-949）：
```rust
let notification = construct_mcp_tool_call_notification(
    begin_event,
    conversation_id.to_string(),
    event_turn_id.clone(),
).await;
```

4. **CollabAgentSpawn 开始**（行 962-981）：
```rust
let item = ThreadItem::CollabAgentToolCall {
    id: begin_event.call_id,
    tool: CollabAgentTool::SpawnAgent,
    status: V2CollabToolCallStatus::InProgress,
    // ...
};
```

## 关键代码路径与文件引用

### 核心定义文件

1. **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/ItemStartedNotification.json`
2. **Rust 结构体**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 4771-4775)
3. **ThreadItem 枚举**: `v2.rs` 行 4117-4258
4. **协议枚举**: `codex-rs/app-server-protocol/src/protocol/common.rs` (行 891)

### 事件生成代码

| 操作类型 | 文件 | 行号 |
|----------|------|------|
| FileChange | `bespoke_event_handling.rs` | 486-505 |
| DynamicToolCall | `bespoke_event_handling.rs` | 844-866 |
| McpToolCall | `bespoke_event_handling.rs` | 940-949 |
| CollabAgentSpawn | `bespoke_event_handling.rs` | 962-981 |

### 测试文件

- `codex-rs/app-server/tests/suite/v2/turn_start.rs`
- `codex-rs/app-server/tests/suite/v2/thread_resume.rs`
- `codex-rs/app-server/tests/suite/v2/compaction.rs`
- `codex-rs/app-server/tests/suite/v2/plan_item.rs`
- `codex-rs/tui_app_server/src/chatwidget/tests.rs`

## 依赖与外部交互

### 内部依赖

1. **核心协议**: `codex_protocol::items::TurnItem`, `codex_protocol::protocol::EventMsg`
2. **线程状态**: `ThreadState` 用于跟踪已开始的操作
3. **序列化**: `serde`, `serde_json`

### 外部交互

| 组件 | 交互 | 说明 |
|------|------|------|
| TUI 客户端 | WebSocket | 显示操作进行中状态 |
| VSCode 扩展 | JSON-RPC | 更新编辑器状态 |
| 测试框架 | 事件断言 | 验证操作开始 |

### 生成产物

- TypeScript: `typescript/v2/ItemStartedNotification.ts`
- 合并 Schema: `json/codex_app_server_protocol.v2.schemas.json`

## 风险、边界与改进建议

### 潜在风险

1. **Started 无 Completed**: 操作可能开始但永远不会收到 Completed（崩溃、超时）
2. **重复 Started**: 同一操作可能因重试发送多个 Started 通知
3. **时序问题**: Completed 可能在 Started 之前到达（极端网络延迟情况）

### 边界情况处理

**FileChange 的特殊处理**（行 486-491）：
```rust
let first_start = {
    let mut state = thread_state.lock().await;
    state.turn_summary.file_change_started.insert(item_id.clone())
};
if first_start {
    // 只发送一次 Started 通知
}
```

这种去重机制确保同一文件变更只发送一次 Started 通知。

### 改进建议

1. **添加时间戳**: 添加 `startedAt` 字段，便于计算操作耗时
2. **唯一标识**: 添加通知级别的唯一 ID，便于去重和追踪
3. **超时提示**: 在 Started 通知中包含建议的超时时间
4. **进度支持**: 对于长时间操作，支持进度百分比更新
5. **取消机制**: 提供客户端取消已开始操作的机制

### 客户端实现模式

```typescript
// 示例：管理操作生命周期
class OperationLifecycleManager {
  private operations = new Map<string, {
    item: ThreadItem;
    startedAt: number;
    status: 'started' | 'completed';
  }>();

  handleStarted(notification: ItemStartedNotification) {
    const key = `${notification.threadId}:${notification.turnId}:${notification.item.id}`;
    
    this.operations.set(key, {
      item: notification.item,
      startedAt: Date.now(),
      status: 'started'
    });
    
    // 乐观更新 UI
    this.ui.addOrUpdateItem(notification.item);
    
    // 设置超时检测
    setTimeout(() => this.checkTimeout(key), 60000);
  }

  handleCompleted(notification: ItemCompletedNotification) {
    const key = `${notification.threadId}:${notification.turnId}:${notification.item.id}`;
    const operation = this.operations.get(key);
    
    if (operation) {
      const duration = Date.now() - operation.startedAt;
      operation.status = 'completed';
      
      // 更新为最终状态
      this.ui.updateItem(notification.item);
      
      // 记录指标
      this.metrics.recordOperationDuration(
        notification.item.type,
        duration
      );
    } else {
      // 未收到 Started 直接收到 Completed
      this.ui.addItem(notification.item);
    }
  }

  private checkTimeout(key: string) {
    const operation = this.operations.get(key);
    if (operation && operation.status === 'started') {
      this.ui.showOperationTimeout(operation.item.id);
    }
  }
}
```

### 与 Completed 通知的配对关系

| 方面 | Started | Completed |
|------|---------|-----------|
| 触发时机 | 操作开始前 | 操作完成后 |
| 状态值 | `inProgress` | `completed`/`failed`/`declined` |
| 结果数据 | 无/部分 | 完整结果 |
| 用途 | UI 加载状态 | 最终状态展示 |
| 必需性 | 可选（某些操作可能跳过） | 必需 |

客户端应优雅处理只收到其中一个通知的情况。
