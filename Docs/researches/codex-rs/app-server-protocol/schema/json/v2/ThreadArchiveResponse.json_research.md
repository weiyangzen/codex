# ThreadArchiveResponse.json 研究文档

## 场景与职责

`ThreadArchiveResponse` 是 App-Server Protocol v2 中线程归档操作的响应结构。它是一个空对象，表示归档操作已成功完成。

该响应用于确认归档请求已处理，实际的状态变更通过 `ThreadArchivedNotification` 通知传达。

## 功能点目的

1. **操作确认**: 确认归档请求已成功处理
2. **空响应模式**: 遵循 JSON-RPC 2.0 无返回值操作的规范
3. **状态同步**: 配合通知机制完成状态同步

## 具体技术实现

### 数据结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "ThreadArchiveResponse",
  "type": "object"
}
```

### 字段说明

该响应是一个空对象，不包含任何字段。这表示：
- 操作成功完成
- 无需返回额外数据
- 状态变更通过通知传达

### 关联的 RPC 方法

- **方法**: `thread/archive`
- **请求参数**: `ThreadArchiveParams`
- **通知**: `ThreadArchivedNotification`

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs
ThreadArchive => "thread/archive" {
    params: v2::ThreadArchiveParams,
    response: v2::ThreadArchiveResponse,
}
```

## 关键代码路径与文件引用

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadArchiveResponse {}
```

### 处理代码

```rust
// codex-rs/app-server/src/codex_message_processor.rs
async fn thread_archive(&self, request_id: ConnectionRequestId, params: ThreadArchiveParams) {
    // ... 归档逻辑 ...
    
    // 发送空响应表示成功
    self.outgoing.send_response(request_id, ThreadArchiveResponse {}).await;
    
    // 发送通知告知状态变更
    self.outgoing.send_notification(
        ServerNotification::ThreadArchived(ThreadArchivedNotification {
            thread_id: params.thread_id,
        })
    ).await;
}
```

### 相关文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ClientRequest 枚举定义 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 请求处理实现 |
| `codex-rs/app-server/tests/suite/v2/thread_archive.rs` | 归档测试 |

## 依赖与外部交互

### 上游依赖

1. **线程管理器**: `codex_core::ThreadManager`
2. **归档逻辑**: 线程归档的具体实现

### 下游交互

1. **归档通知**: 归档成功后发送 `ThreadArchivedNotification`
2. **UI 更新**: 客户端收到响应后更新 UI 状态

### 协议版本

- **版本**: v2
- **稳定性**: 稳定 API (非实验性)

## 风险、边界与改进建议

### 风险点

1. **无错误详情**: 空响应无法提供操作的部分成功信息
2. **状态不一致**: 响应成功但通知丢失可能导致状态不一致
3. **操作确认**: 无法从响应中确认具体归档了哪个线程

### 边界情况

1. **重复归档**: 重复归档同一线程仍返回成功
2. **并发归档**: 多个客户端同时归档同一线程

### 改进建议

1. **添加时间戳**: 建议添加 `archived_at: i64` 字段
2. **添加线程信息**: 建议添加 `thread: Thread` 字段返回归档后的线程信息
3. **添加状态**: 建议添加 `status: ArchiveStatus` 字段

### 示例改进结构

```json
{
  "archivedAt": 1234567890,
  "thread": {
    "id": "thread-123",
    "status": { "type": "archived" },
    // ... 其他线程字段
  }
}
```

### 测试覆盖

相关测试文件：`codex-rs/app-server/tests/suite/v2/thread_archive.rs`

建议测试场景：
- 归档成功响应
- 归档失败错误响应
- 响应与通知的一致性
