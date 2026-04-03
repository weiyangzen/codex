# ThreadClosedNotification.ts 研究文档

## 场景与职责

`ThreadClosedNotification` 是 Codex App-Server Protocol v2 API 的服务器通知类型，当线程被关闭时由服务器发送给客户端。线程关闭意味着该会话已结束，不再接受新的对话轮次。

## 功能点目的

### 核心功能

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 已关闭的线程 ID |

### 设计特点

1. **生命周期终点**：表示线程生命周期的正式结束
2. **资源释放信号**：提示客户端可以释放相关资源
3. **UI 状态更新**：驱动客户端更新线程状态显示

## 具体技术实现

### TypeScript 类型定义

```typescript
export type ThreadClosedNotification = { threadId: string, };
```

### Rust 源码对应

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 4642-4647) 中定义：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadClosedNotification {
    pub thread_id: String,
}
```

### 在 ServerNotification 中的注册

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中注册：

```rust
server_notification_definitions! {
    // ...
    ThreadClosed => "thread/closed" (v2::ThreadClosedNotification),
    // ...
}
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源码）
- `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 4642-4647): Rust 类型定义
- `codex-rs/app-server-protocol/src/protocol/common.rs`: 通知注册

### 下游使用方
- 客户端接收并处理服务器通知

### 相关类型
- `ThreadStatus.ts`: 线程状态类型，关闭后状态变更
- `Thread.ts`: 线程类型，包含状态信息

## 依赖与外部交互

### 使用示例

```typescript
import type { ThreadClosedNotification } from "./v2";

// 客户端通知处理
client.onNotification("thread/closed", (notification: ThreadClosedNotification) => {
  console.log(`Thread ${notification.threadId} has been closed`);
  
  // 更新线程状态
  updateThreadStatus(notification.threadId, "closed");
  
  // 禁用输入框
  disableInputForThread(notification.threadId);
  
  // 释放资源
  cleanupThreadResources(notification.threadId);
  
  // 显示关闭提示
  showNotification("This conversation has been closed");
});
```

### 与 ThreadStatus 的关系

```typescript
// 关闭通知
export type ThreadClosedNotification = { threadId: string };

// 线程状态（关闭后可能变为 idle 或其他状态）
export type ThreadStatus = 
  | { "type": "notLoaded" } 
  | { "type": "idle" } 
  | { "type": "systemError" } 
  | { "type": "active", activeFlags: Array<ThreadActiveFlag> };
```

## 风险、边界与改进建议

### 边界情况

1. **重复关闭**：对已经关闭的线程再次发送关闭通知
2. **关闭原因**：当前未提供关闭原因（正常关闭/错误关闭/超时等）
3. **恢复可能性**：关闭后是否可以通过某种方式重新打开

### 改进建议

1. **添加关闭原因**：
   ```typescript
   export type ThreadClosedNotification = { 
     threadId: string,
     reason?: "completed" | "error" | "timeout" | "user_request"
   };
   ```
2. **添加错误信息**：如果是错误导致的关闭，提供错误详情
3. **添加关闭时间**：`closedAt: number` 记录关闭时间戳

### 注意事项

- 该文件为**自动生成**
- 关闭与归档是不同的概念：关闭结束会话，归档只是隐藏
- 客户端应做好幂等处理
