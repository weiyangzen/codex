# ThreadArchiveParams.json 研究文档

## 场景与职责

`ThreadArchiveParams` 是 App-Server Protocol v2 中用于归档线程的请求参数结构。客户端通过此参数指定要归档的线程 ID，将线程从活动状态移至归档状态。

归档操作将线程从活动线程列表中移除，但保留线程数据供将来查阅。

## 功能点目的

1. **线程归档**: 将不活跃的线程移至归档状态
2. **列表整理**: 清理活动线程列表，提高可管理性
3. **数据保留**: 保留线程历史记录供将来参考

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
  "title": "ThreadArchiveParams",
  "type": "object"
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `threadId` | string | 是 | 要归档的线程 ID |

### 关联的 RPC 方法

- **方法**: `thread/archive`
- **响应**: `ThreadArchiveResponse` (空对象)
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
pub struct ThreadArchiveParams {
    pub thread_id: String,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadArchiveResponse {}
```

### 处理代码

```rust
// codex-rs/app-server/src/codex_message_processor.rs
async fn thread_archive(&self, request_id: ConnectionRequestId, params: ThreadArchiveParams) {
    let thread_id = match ThreadId::from_string(&params.thread_id) {
        Ok(id) => id,
        Err(e) => {
            self.outgoing.send_error(request_id, e).await;
            return;
        }
    };
    
    match self.thread_manager.archive_thread(thread_id).await {
        Ok(()) => {
            self.outgoing.send_response(request_id, ThreadArchiveResponse {}).await;
            
            // 广播归档通知
            self.outgoing.send_notification(
                ServerNotification::ThreadArchived(ThreadArchivedNotification {
                    thread_id: params.thread_id,
                })
            ).await;
        }
        Err(e) => { /* 错误处理 */ }
    }
}
```

### 相关文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ClientRequest 和 ServerNotification 枚举定义 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 请求处理实现 |
| `codex-rs/app-server/tests/suite/v2/thread_archive.rs` | 归档测试 |
| `codex-rs/app-server/tests/suite/v2/thread_unarchive.rs` | 取消归档测试 |

## 依赖与外部交互

### 上游依赖

1. **线程管理器**: `codex_core::ThreadManager`
2. **状态数据库**: 线程状态持久化存储

### 下游交互

1. **线程列表更新**: 归档后从活动线程列表中移除
2. **归档通知**: 发送 `ThreadArchivedNotification` 通知所有客户端

### 协议版本

- **版本**: v2
- **稳定性**: 稳定 API (非实验性)

## 风险、边界与改进建议

### 风险点

1. **数据丢失风险**: 归档操作不可逆（除非有取消归档功能）
2. **并发操作**: 归档时线程可能正在执行
3. **通知丢失**: 归档通知可能丢失导致客户端状态不一致

### 边界情况

1. **已归档线程**: 重复归档已归档的线程
2. **不存在线程**: 归档不存在的线程
3. **活动线程**: 归档正在执行中的线程

### 改进建议

1. **添加确认选项**: 建议添加 `confirm: bool` 字段确认归档活动线程
2. **添加原因**: 建议添加 `reason: Option<String>` 字段记录归档原因
3. **添加批量操作**: 建议支持批量归档多个线程

### 示例改进结构

```json
{
  "threadId": "thread-123",
  "confirm": true,
  "reason": "Project completed"
}
```

### 测试覆盖

相关测试文件：`codex-rs/app-server/tests/suite/v2/thread_archive.rs`

建议测试场景：
- 正常线程归档
- 归档不存在的线程
- 归档活动线程
- 归档通知发送
