# ThreadClosedNotification.json 研究文档

## 场景与职责

`ThreadClosedNotification` 是 App-Server Protocol v2 中用于通知客户端线程已关闭的服务器通知。当线程被关闭（如会话结束或显式关闭）时，服务器发送此通知给所有订阅的客户端。

该通知用于保持客户端状态同步，告知客户端线程已不再可用。

## 功能点目的

1. **状态同步**: 通知所有客户端线程已关闭
2. **资源清理**: 触发客户端清理与该线程相关的资源
3. **会话管理**: 支持会话结束时的清理工作

## 具体技术实现

### 数据结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "threadId": {
      "type": "string"
    }
  },
  "required": ["threadId"],
  "title": "ThreadClosedNotification",
  "type": "object"
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `threadId` | string | 是 | 已关闭的线程 ID |

### 通知方法名

```
thread/closed
```

### 关联定义

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs
server_notification_definitions! {
    // ...
    ThreadClosed => "thread/closed" (v2::ThreadClosedNotification),
    // ...
}
```

### 与 ThreadArchivedNotification 的区别

| 通知 | 含义 | 可恢复性 |
|------|------|----------|
| `ThreadArchivedNotification` | 线程已归档 | 可通过取消归档恢复 |
| `ThreadClosedNotification` | 线程已关闭 | 通常不可恢复 |

## 关键代码路径与文件引用

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadClosedNotification {
    pub thread_id: String,
}
```

### 发送代码

```rust
// 在线程关闭时发送通知
outgoing.send_notification(
    ServerNotification::ThreadClosed(ThreadClosedNotification {
        thread_id: thread_id.to_string(),
    })
).await;
```

### 相关文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ServerNotification 枚举定义 |
| `codex-rs/tui_app_server/src/app.rs` | TUI 应用中的处理 |

## 依赖与外部交互

### 上游依赖

1. **线程关闭**: 由会话结束或显式关闭操作触发
2. **线程管理器**: `codex_core::ThreadManager` 执行关闭

### 下游交互

1. **UI 清理**: 客户端清理与该线程相关的 UI 元素
2. **状态更新**: 更新客户端线程状态跟踪

### 协议版本

- **版本**: v2
- **稳定性**: 稳定 API (非实验性)

## 风险、边界与改进建议

### 风险点

1. **通知丢失**: 作为通知，可能丢失导致客户端资源泄漏
2. **时序问题**: 关闭通知可能与其他事件通知乱序到达
3. **重复通知**: 可能收到重复的关闭通知

### 边界情况

1. **已关闭线程**: 重复收到同一线程的关闭通知
2. **客户端离线**: 客户端离线期间错过的通知
3. **关闭中操作**: 线程关闭过程中收到操作请求

### 改进建议

1. **添加原因**: 建议添加 `reason: ThreadCloseReason` 字段说明关闭原因
2. **添加时间戳**: 建议添加 `closed_at: i64` 字段
3. **添加关闭者**: 建议添加 `closed_by: Option<String>` 字段

### ThreadCloseReason 建议枚举

```rust
pub enum ThreadCloseReason {
    UserRequested,    // 用户请求关闭
    SessionEnded,     // 会话结束
    Timeout,          // 超时
    Error,            // 错误导致
    SystemShutdown,   // 系统关闭
}
```

### 示例改进结构

```json
{
  "threadId": "thread-123",
  "reason": "sessionEnded",
  "closedAt": 1234567890,
  "closedBy": null
}
```

### 测试覆盖

建议测试场景：
- 线程关闭通知发送
- 多客户端通知接收
- 关闭原因处理
