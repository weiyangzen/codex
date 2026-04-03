# ThreadArchivedNotification.ts 研究文档

## 场景与职责

`ThreadArchivedNotification` 是 Codex App-Server Protocol v2 API 的服务器通知类型，当线程被成功归档后由服务器发送给客户端。该通知使客户端能够及时更新 UI 状态，将归档线程从活动列表中移除。

## 功能点目的

### 核心功能

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 已归档的线程 ID |

### 设计特点

1. **轻量通知**：仅包含线程 ID，客户端可据此更新本地状态
2. **异步确认**：作为归档操作的异步确认机制
3. **广播语义**：可能广播给所有订阅该线程的客户端

## 具体技术实现

### TypeScript 类型定义

```typescript
export type ThreadArchivedNotification = { threadId: string, };
```

### Rust 源码对应

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 4628-4633) 中定义：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadArchivedNotification {
    pub thread_id: String,
}
```

### 在 ServerNotification 中的注册

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中注册：

```rust
server_notification_definitions! {
    // ...
    ThreadArchived => "thread/archived" (v2::ThreadArchivedNotification),
    // ...
}
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源码）
- `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 4628-4633): Rust 类型定义
- `codex-rs/app-server-protocol/src/protocol/common.rs`: 通知注册

### 下游使用方
- 客户端接收并处理服务器通知

### 相关类型
- `ThreadArchiveParams.ts`: 归档请求参数
- `ThreadArchiveResponse.ts`: 归档响应
- `ThreadUnarchivedNotification.ts`: 取消归档通知

## 依赖与外部交互

### 使用示例

```typescript
import type { ThreadArchivedNotification } from "./v2";

// 客户端通知处理
client.onNotification("thread/archived", (notification: ThreadArchivedNotification) => {
  console.log(`Thread ${notification.threadId} has been archived`);
  
  // 从活动线程列表中移除
  removeFromActiveThreads(notification.threadId);
  
  // 添加到归档线程列表
  addToArchivedThreads(notification.threadId);
  
  // 更新 UI
  updateThreadListUI();
});
```

### 与 ThreadUnarchivedNotification 的关系

```typescript
// 归档通知
export type ThreadArchivedNotification = { threadId: string };

// 取消归档通知
export type ThreadUnarchivedNotification = { threadId: string };
```

两者结构相同但语义相反，分别表示归档和取消归档操作。

## 风险、边界与改进建议

### 边界情况

1. **重复通知**：同一线程可能收到多次归档通知
2. **顺序问题**：通知可能在 RPC 响应之前到达
3. **离线状态**：客户端离线期间的通知处理

### 改进建议

1. **添加时间戳**：`archivedAt: number` 记录归档时间
2. **添加操作者**：`archivedBy: string` 标识执行归档的用户
3. **去重机制**：客户端实现通知去重逻辑

### 注意事项

- 该文件为**自动生成**
- 通知是单向的，客户端无需响应
- 客户端应做好幂等处理，允许重复接收相同通知
