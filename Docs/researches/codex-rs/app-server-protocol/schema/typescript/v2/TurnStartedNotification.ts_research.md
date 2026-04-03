# TurnStartedNotification.ts Research Document

## 场景与职责

`TurnStartedNotification` 是 App-Server Protocol v2 中的服务器端通知类型，用于在对话回合（Turn）开始时向客户端发送通知。该通知在以下场景中发挥关键作用：

1. **对话状态同步**: 当用户发起新的对话回合时，服务器通过此通知告知客户端回合已开始处理
2. **实时对话更新**: 在 TUI（终端用户界面）或 Web 客户端中，用于实时显示新回合的开始状态
3. **多客户端同步**: 当同一对话在多个客户端间共享时，确保所有连接的客户端都收到回合开始事件
4. **历史记录管理**: 客户端可以基于该通知更新本地对话历史状态

## 功能点目的

该通知类型的核心目的是：

- **状态广播**: 将新回合的创建事件广播给所有订阅该对话的客户端
- **数据传递**: 传递新回合的完整信息（ID、状态、错误等），使客户端能够立即显示或处理
- **线程上下文维护**: 通过 `threadId` 确保客户端知道该回合属于哪个对话线程
- **UI 响应**: 触发客户端 UI 更新，例如显示加载状态、清空输入框、滚动到底部等

## 具体技术实现

### TypeScript 类型定义

```typescript
export type TurnStartedNotification = { 
  threadId: string, 
  turn: Turn, 
};
```

### Rust 源类型定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TurnStartedNotification {
    pub thread_id: String,
    pub turn: Turn,
}
```

### 关联类型

- **`Turn`**: 包含回合的完整信息
  - `id`: 回合唯一标识符
  - `items`: 回合中的项目列表（在 `thread/resume` 或 `thread/fork` 响应中填充，其他情况为空）
  - `status`: 回合状态（`TurnStatus` 枚举）
  - `error`: 错误信息（仅当状态为 `failed` 时填充）

### 序列化特性

- 使用 `camelCase` 命名规范进行序列化
- 通过 `ts-rs` 自动生成 TypeScript 类型定义
- 通过 `schemars` 生成 JSON Schema 用于验证

## 关键代码路径与文件引用

### 定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 4671-4674) | Rust 类型定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/TurnStartedNotification.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/json/v2/TurnStartedNotification.json` | JSON Schema 定义 |

### 使用位置

| 文件路径 | 用途 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 注册为服务器通知变体 |
| `codex-rs/app-server-protocol/schema/typescript/ServerNotification.ts` | 包含在服务器通知联合类型中 |
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 处理回合开始事件并发送通知 |
| `codex-rs/tui_app_server/src/app.rs` | TUI 应用服务器处理通知 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试用例中使用 |
| `codex-rs/app-server/tests/suite/v2/turn_start.rs` | 回合开始功能测试 |

### 通知流程

```
用户输入 → CodexMessageProcessor → BespokeEventHandling → TurnStartedNotification → WebSocket/Stream → 客户端
```

## 依赖与外部交互

### 内部依赖

- **`Turn`**: 嵌套类型，定义回合数据结构
- **`ThreadItem`**: Turn 中包含的项目类型
- **`TurnStatus`**: 回合状态枚举
- **`TurnError`**: 回合错误类型

### 协议依赖

- 属于 **Server Notification** 类别（服务器 → 客户端单向通知）
- 通过 WebSocket 或 SSE（Server-Sent Events）传输
- 使用 JSON-RPC 2.0 通知格式封装

### 客户端交互

- **TUI 客户端**: 在 `tui/src/app.rs` 和 `tui_app_server/src/app.rs` 中处理，更新聊天界面
- **测试客户端**: 在集成测试中验证通知接收

## 风险、边界与改进建议

### 潜在风险

1. **竞态条件**: 如果客户端在收到 `TurnStartedNotification` 之前发送了新的回合请求，可能导致状态不一致
2. **网络延迟**: 在高延迟环境下，通知可能延迟到达，影响 UI 响应性
3. **重复通知**: 网络重连或重试机制可能导致客户端收到重复的回合开始通知

### 边界情况

1. **空 Turn 数据**: 正常情况下 `turn.items` 为空列表（仅在 `thread/resume` 或 `thread/fork` 时填充）
2. **并发回合**: 协议设计上是否支持同一对话的并发回合需要验证
3. **错误状态**: 如果回合创建立即失败，`TurnStartedNotification` 是否还会发送需要确认

### 改进建议

1. **添加序列号**: 考虑添加序列号或时间戳，帮助客户端处理乱序或重复通知
2. **乐观更新**: 客户端可以实现乐观 UI 更新，在发送请求时立即显示新回合，收到通知时确认
3. **心跳机制**: 对于长轮询场景，考虑添加心跳确认机制确保通知送达
4. **批量通知**: 在高频场景下，考虑支持批量回合通知以减少网络开销
5. **元数据扩展**: 考虑添加 `timestamp` 字段记录回合开始时间，便于调试和日志分析

### 测试覆盖

- 单元测试: `codex-rs/app-server/tests/suite/v2/turn_start.rs`
- 集成测试: `codex-rs/tui_app_server/src/chatwidget/tests.rs`
- 建议添加：网络分区恢复后的通知重传测试
