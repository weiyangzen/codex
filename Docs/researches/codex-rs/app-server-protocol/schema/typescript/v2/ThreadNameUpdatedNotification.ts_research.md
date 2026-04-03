# ThreadNameUpdatedNotification Research

## TypeScript Schema

```typescript
export type ThreadNameUpdatedNotification = { threadId: string, threadName?: string, };
```

## 场景与职责

`ThreadNameUpdatedNotification` 是一个服务器推送通知（Server Notification），用于在会话（Thread）的名称发生变化时，实时通知所有订阅该会话的客户端。

### 使用场景

1. **用户重命名会话**: 当用户通过 `thread/setName` API 修改会话名称时，服务器会广播此通知
2. **多客户端同步**: 确保所有连接到同一会话的客户端（如桌面端、Web端、移动端）能够实时看到会话名称的变更
3. **会话列表更新**: 客户端收到此通知后，可以更新本地缓存的会话列表中的显示名称

### 职责

- 提供会话标识（`threadId`）和新的会话名称（`threadName`）
- 支持可选的 `threadName`（当名称为空或重置时可能为 `undefined`）
- 通过 WebSocket 广播给所有订阅者

## 功能点目的

### 核心功能

1. **实时同步**: 确保会话名称变更能够即时传播到所有相关客户端
2. **状态一致性**: 维护客户端与会话服务器之间会话元数据的一致性
3. **用户体验**: 支持用户在多设备场景下获得一致的会话命名体验

### 设计考量

- `threadName` 是可选字段（`?`），允许表示会话名称被清除或重置的情况
- 使用 `threadId` 而非 `conversationId` 作为标识，与 App-Server v2 API 的命名规范保持一致

## 具体技术实现

### 数据结构

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadNameUpdatedNotification {
    pub thread_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub thread_name: Option<String>,
}
```

### 序列化行为

- 使用 `camelCase` 命名规范（Rust 端 `thread_id` → TypeScript 端 `threadId`）
- `thread_name` 字段使用 `skip_serializing_if = "Option::is_none"`，当值为 `None` 时不序列化该字段
- TypeScript 端标记为可选属性（`threadName?: string`）

### 协议映射

| 协议方法 | 方向 | 类型 |
|---------|------|------|
| `thread/name/updated` | Server → Client | Notification |

## 关键代码路径与文件引用

### 协议定义

- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 4661-4666)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/ThreadNameUpdatedNotification.ts`
- **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/ThreadNameUpdatedNotification.json`

### 协议注册

- **Common 协议**: `codex-rs/app-server-protocol/src/protocol/common.rs`
  - 注册为 `ThreadNameUpdated => "thread/name/updated" (v2::ThreadNameUpdatedNotification)`

### 实现代码

- **事件处理**: `codex-rs/app-server/src/bespoke_event_handling.rs`
  - 处理 `EventMsg::ThreadNameUpdated` 事件，构造并发送通知

### 测试代码

- **集成测试**: `codex-rs/app-server/tests/suite/v2/thread_read.rs` (lines 204-357)
  - 测试 `thread/name/updated` 通知在重命名后的接收和验证
- **WebSocket 测试**: `codex-rs/app-server/tests/suite/v2/thread_name_websocket.rs`
  - 专门测试会话名称更新的 WebSocket 通知机制

### 客户端使用

- **TUI App Server**: `codex-rs/tui_app_server/src/chatwidget/tests.rs`
  - 测试客户端对会话名称更新通知的处理

## 依赖与外部交互

### 内部依赖

| 依赖项 | 用途 |
|--------|------|
| `serde` | 序列化/反序列化 |
| `ts-rs` | TypeScript 类型生成 |
| `schemars` | JSON Schema 生成 |

### 外部交互

1. **触发源**: 
   - `EventMsg::ThreadNameUpdated` 事件，由 `thread/setName` API 调用触发
   
2. **通知目标**:
   - 所有订阅该 `threadId` 的 WebSocket 客户端
   - 通过 `outgoing.send_global_server_notification()` 广播

### 事件流

```
Client A ──thread/setName──► Server ──ThreadNameUpdatedNotification──► Client A
                                           │
                                           └────────────────────────► Client B
                                           │
                                           └────────────────────────► Client C
```

## 风险、边界与改进建议

### 潜在风险

1. **通知丢失**: 如果客户端在名称变更时未连接，将错过通知（需通过 `thread/read` 或 `thread/list` 重新获取状态）
2. **竞态条件**: 多个客户端同时修改同一会话名称时，最后写入者获胜（Last-Write-Wins），但通知顺序可能不一致
3. **空名称处理**: `threadName` 为 `undefined` 时，客户端需要正确处理显示逻辑（如显示默认名称或预览文本）

### 边界情况

| 场景 | 行为 |
|------|------|
| `threadName` 为 `undefined` | 表示名称被清除，客户端应显示默认标题或预览 |
| 会话不存在 | 通知不会发送给任何客户端 |
| 无订阅者 | 通知被丢弃，不影响系统状态 |

### 改进建议

1. **添加版本号**: 考虑添加 `version` 或 `timestamp` 字段，帮助客户端处理乱序通知
2. **批量通知**: 对于批量重命名操作，考虑支持批量通知格式
3. **变更原因**: 添加可选的 `reason` 字段，说明名称变更的触发原因（用户手动、系统自动等）
4. **历史记录**: 考虑是否需要在服务端保留名称变更历史

### 相关类型

- `ThreadSetNameParams` / `ThreadSetNameResponse`: 触发此通知的 API
- `Thread`: 包含 `name` 字段的会话对象
