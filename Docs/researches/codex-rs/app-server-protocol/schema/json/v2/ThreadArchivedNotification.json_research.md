# ThreadArchivedNotification.json 研究文档

## 场景与职责

`ThreadArchivedNotification` 是 App-Server Protocol v2 中用于通知客户端线程已归档的服务器通知。当线程被成功归档后，服务器发送此通知给所有订阅的客户端。

该通知用于保持客户端状态同步，确保所有客户端都知道线程的归档状态变更。

## 功能点目的

1. **状态同步**: 通知所有客户端线程已归档
2. **UI 更新**: 触发客户端从活动线程列表中移除归档线程
3. **事件广播**: 广播归档事件供其他组件响应

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
  "title": "ThreadArchivedNotification",
  "type": "object"
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `threadId` | string | 是 | 已归档的线程 ID |

### 通知方法名

```
thread/archived
```

### 关联定义

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs
server_notification_definitions! {
    // ...
    ThreadArchived => "thread/archived" (v2::ThreadArchivedNotification),
    // ...
}
```

## 关键代码路径与文件引用

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadArchivedNotification {
    pub thread_id: String,
}
```

### 发送代码

```rust
// codex-rs/app-server/src/codex_message_processor.rs
async fn thread_archive(&self, request_id: ConnectionRequestId, params: ThreadArchiveParams) {
    // ... 归档逻辑 ...
    
    // 发送归档通知
    self.outgoing.send_notification(
        ServerNotification::ThreadArchived(ThreadArchivedNotification {
            thread_id: params.thread_id.clone(),
        })
    ).await;
}
```

### 相关文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ServerNotification 枚举定义 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 请求处理实现 |
| `codex-rs/app-server/tests/suite/v2/thread_archive.rs` | 归档测试 |
| `codex-rs/tui_app_server/src/app.rs` | TUI 应用中的处理 |

## 依赖与外部交互

### 上游依赖

1. **归档操作**: 由 `thread/archive` 请求触发
2. **线程管理器**: `codex_core::ThreadManager` 执行归档

### 下游交互

1. **线程列表更新**: 客户端从活动线程列表中移除归档线程
2. **归档列表更新**: 客户端可能更新归档线程列表

### 协议版本

- **版本**: v2
- **稳定性**: 稳定 API (非实验性)

## 风险、边界与改进建议

### 风险点

1. **通知丢失**: 作为通知，可能丢失导致客户端状态不一致
2. **重复通知**: 可能收到重复的归档通知
3. **顺序问题**: 归档通知可能与其他线程事件通知乱序到达

### 边界情况

1. **已归档线程**: 重复收到同一线程的归档通知
2. **客户端离线**: 客户端离线期间错过的通知
3. **多客户端**: 多个客户端同时处理归档通知

### 改进建议

1. **添加时间戳**: 建议添加 `archived_at: i64` 字段
2. **添加归档者**: 建议添加 `archived_by: Option<String>` 字段
3. **添加原因**: 建议添加 `reason: Option<String>` 字段
4. **序列号**: 建议添加全局序列号帮助检测丢失的通知

### 示例改进结构

```json
{
  "threadId": "thread-123",
  "archivedAt": 1234567890,
  "archivedBy": "user@example.com",
  "reason": "Project completed"
}
```

### 测试覆盖

相关测试文件：`codex-rs/app-server/tests/suite/v2/thread_archive.rs`

建议测试场景：
- 归档通知发送
- 多客户端通知接收
- 通知丢失恢复
