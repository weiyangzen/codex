# ThreadUnarchivedNotification.json 研究文档

## 场景与职责

`ThreadUnarchivedNotification` 是 Codex App-Server Protocol v2 中定义的服务器向客户端发送的通知类型，用于广播某个 Thread（会话线程）已被解归档的事件。与 `ThreadUnarchiveResponse` 不同，这是服务器主动推送的通知，用于通知所有订阅了该 Thread 的客户端。

典型使用场景：
- 多设备同步：用户在一台设备上解归档 Thread，其他设备收到通知
- 协作场景：多个用户共享 Thread 时，通知所有参与者
- 客户端状态同步：确保所有连接的客户端都能及时更新 Thread 列表
- 后台恢复：服务端自动恢复归档 Thread 时通知客户端

## 功能点目的

该通知的主要目的是：
1. **状态广播**：向所有订阅者广播 Thread 解归档事件
2. **多客户端同步**：确保多个客户端之间的 Thread 状态保持一致
3. **实时更新**：无需客户端轮询即可获取最新的归档状态变化
4. **事件驱动**：支持基于事件驱动的 UI 更新逻辑

### 与 ThreadUnarchiveResponse 的区别

| 特性 | ThreadUnarchiveResponse | ThreadUnarchivedNotification |
|------|------------------------|------------------------------|
| 方向 | Server -> Client（响应） | Server -> Client（通知） |
| 触发 | 客户端发起解归档请求 | 任何解归档操作完成 |
| 接收者 | 发起请求的客户端 | 所有订阅该 Thread 的客户端 |
| 内容 | 完整的 Thread 对象 | 仅 Thread ID |
| 用途 | 确认操作并提供数据 | 广播状态变化 |

## 具体技术实现

### JSON Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "threadId": { "type": "string" }
  },
  "required": ["threadId"]
}
```

### Rust 实现

位于 `codex-rs/app-server-protocol/src/protocol/v2.rs`（行 4635-4640）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadUnarchivedNotification {
    pub thread_id: String,
}
```

### 服务端注册

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中注册为服务器通知：

```rust
server_notification_definitions! {
    ThreadUnarchived => "thread/unarchived" (v2::ThreadUnarchivedNotification),
    // ...
}
```

### 通知发送流程

```
Client A -> Server: thread/unarchive (ThreadUnarchiveParams)
Server -> Client A: ThreadUnarchiveResponse
Server -> Client A: ThreadUnarchivedNotification
Server -> Client B: ThreadUnarchivedNotification (如果 Client B 订阅了该 Thread)
Server -> Client C: ThreadUnarchivedNotification (如果 Client C 订阅了该 Thread)
```

## 关键代码路径与文件引用

### 核心定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ThreadUnarchivedNotification.json` | JSON Schema 定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（行 4635-4640） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 服务器通知注册（行 880） |
| `codex-rs/app-server-protocol/schema/typescript/v2/ThreadUnarchivedNotification.ts` | TypeScript 类型定义 |

### 服务端发送代码

位于 `codex-rs/app-server/src/codex_message_processor.rs`：
- 处理 `thread/unarchive` 请求成功后
- 构建 `ThreadUnarchivedNotification` 通知
- 广播给所有订阅了该 Thread 的客户端连接

### 测试文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/tests/suite/v2/thread_unarchive.rs` | 解归档功能测试（包含通知验证） |

## 依赖与外部交互

### 上游依赖

1. **Thread 管理服务**：执行实际的解归档操作
2. **订阅管理服务**：管理哪些客户端订阅了哪些 Thread
3. **WebSocket 连接**：用于向客户端推送通知

### 下游消费者

1. **多客户端应用**：在多个窗口/设备间同步 Thread 状态
2. **Thread 列表组件**：更新归档/活跃 Thread 列表显示
3. **通知中心**：可能显示 Thread 解归档的提示

### 相关通知类型

| 通知类型 | 说明 |
|---------|------|
| `ThreadArchivedNotification` | Thread 被归档时的通知 |
| `ThreadStartedNotification` | Thread 创建时的通知 |
| `ThreadClosedNotification` | Thread 关闭时的通知 |
| `ThreadStatusChangedNotification` | Thread 状态变化时的通知 |

## 风险、边界与改进建议

### 潜在风险

1. **通知丢失**：WebSocket 连接断开期间可能丢失通知
2. **重复通知**：网络重连后可能收到重复的通知
3. **顺序问题**：通知和响应的顺序可能不固定

### 边界情况

1. **无订阅者**：如果没有客户端订阅该 Thread，通知不会被发送
2. **发送失败**：某些客户端连接断开时，通知发送可能失败
3. **重复解归档**：对未归档的 Thread 调用解归档，通知行为未定义

### 改进建议

1. **添加时间戳**：在通知中添加事件时间戳，帮助客户端排序和去重
2. **添加操作者信息**：标识是哪个客户端/用户执行了解归档操作
3. **确认机制**：重要的通知可以要求客户端发送确认
4. **通知历史**：支持客户端查询错过的通知
5. **批量通知**：支持批量解归档时发送单个批量通知

### 客户端处理建议

```typescript
// 示例：客户端处理 ThreadUnarchivedNotification
function handleThreadUnarchived(notification: ThreadUnarchivedNotification) {
    // 1. 更新本地 Thread 列表
    moveThreadFromArchivedToActive(notification.threadId);
    
    // 2. 如果当前正在查看该 Thread，刷新数据
    if (currentThreadId === notification.threadId) {
        refreshThreadData(notification.threadId);
    }
    
    // 3. 显示提示（可选）
    showToast(`Thread ${notification.threadId} 已恢复`);
}
```

### 版本兼容性

- 当前为 v2 API，使用 camelCase 命名
- 通知仅包含 Thread ID，客户端需要调用 `thread/read` 获取完整数据
- 与 v1 API 不兼容
