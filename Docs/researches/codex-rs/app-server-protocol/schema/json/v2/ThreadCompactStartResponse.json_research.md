# ThreadCompactStartResponse.json 研究文档

## 场景与职责

`ThreadCompactStartResponse` 是 App-Server Protocol v2 中线程上下文压缩启动操作的响应结构。它是一个空对象，表示压缩操作已成功启动。

该响应用于确认压缩请求已接受，实际的压缩结果通过后续的事件通知传达。

## 功能点目的

1. **操作确认**: 确认压缩请求已成功接受
2. **异步处理**: 表示压缩将在后台异步执行
3. **空响应模式**: 遵循 JSON-RPC 2.0 无返回值操作的规范

## 具体技术实现

### 数据结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "ThreadCompactStartResponse",
  "type": "object"
}
```

### 字段说明

该响应是一个空对象，不包含任何字段。这表示：
- 压缩操作已成功启动
- 压缩将在后台异步执行
- 结果将通过 `ContextCompacted` 通知传达

### 关联的 RPC 方法

- **方法**: `thread/compact/start`
- **请求参数**: `ThreadCompactStartParams`
- **通知**: `ContextCompacted` (已弃用，建议使用 `ContextCompaction` ThreadItem)

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs
ThreadCompactStart => "thread/compact/start" {
    params: v2::ThreadCompactStartParams,
    response: v2::ThreadCompactStartResponse,
}
```

## 关键代码路径与文件引用

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadCompactStartResponse {}
```

### 处理代码

```rust
// codex-rs/app-server/src/codex_message_processor.rs
async fn thread_compact_start(&self, request_id: ConnectionRequestId, params: ThreadCompactStartParams) {
    // ... 启动压缩逻辑 ...
    
    // 发送空响应表示成功启动
    self.outgoing.send_response(request_id, ThreadCompactStartResponse {}).await;
    
    // 压缩完成后发送通知或添加 ThreadItem
}
```

### 相关文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ClientRequest 枚举定义 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 请求处理实现 |
| `codex-rs/app-server/tests/suite/v2/compaction.rs` | 压缩测试 |

## 依赖与外部交互

### 上游依赖

1. **线程管理器**: `codex_core::ThreadManager`
2. **压缩启动**: 上下文压缩的启动逻辑

### 下游交互

1. **异步压缩**: 压缩在后台执行
2. **完成通知**: 压缩完成后发送通知或添加 ThreadItem

### 协议版本

- **版本**: v2
- **稳定性**: 稳定 API (非实验性)

## 风险、边界与改进建议

### 风险点

1. **无进度反馈**: 空响应无法提供压缩进度
2. **启动失败延迟**: 某些错误可能在启动后才被发现
3. **状态不一致**: 响应成功但压缩实际失败

### 边界情况

1. **重复启动**: 重复启动压缩的处理
2. **压缩中线程关闭**: 压缩过程中线程被关闭

### 改进建议

1. **添加操作 ID**: 建议添加 `operation_id: String` 字段用于追踪
2. **添加预估时间**: 建议添加 `estimated_duration_ms: Option<u64>` 字段
3. **添加状态**: 建议添加 `status: CompactionStatus` 字段

### 示例改进结构

```json
{
  "operationId": "compact-123",
  "estimatedDurationMs": 5000,
  "status": "started"
}
```

### 测试覆盖

相关测试文件：`codex-rs/app-server/tests/suite/v2/compaction.rs`

建议测试场景：
- 压缩启动响应
- 异步压缩完成验证
