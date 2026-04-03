# ThreadCompactStartParams.json 研究文档

## 场景与职责

`ThreadCompactStartParams` 是 App-Server Protocol v2 中用于启动线程上下文压缩的请求参数结构。客户端通过此参数指定要压缩的线程 ID，触发上下文压缩流程以减少 token 使用量。

上下文压缩是管理长对话的重要机制，通过总结历史对话内容来减少上下文窗口的占用。

## 功能点目的

1. **上下文压缩**: 减少线程历史记录的 token 使用量
2. **内存管理**: 管理长对话的内存使用
3. **成本控制**: 减少 API 调用成本

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
  "title": "ThreadCompactStartParams",
  "type": "object"
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `threadId` | string | 是 | 要压缩的线程 ID |

### 关联的 RPC 方法

- **方法**: `thread/compact/start`
- **响应**: `ThreadCompactStartResponse` (空对象)

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
pub struct ThreadCompactStartParams {
    pub thread_id: String,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadCompactStartResponse {}
```

### 处理代码

```rust
// codex-rs/app-server/src/codex_message_processor.rs
async fn thread_compact_start(&self, request_id: ConnectionRequestId, params: ThreadCompactStartParams) {
    let thread_id = match ThreadId::from_string(&params.thread_id) {
        Ok(id) => id,
        Err(e) => {
            self.outgoing.send_error(request_id, e).await;
            return;
        }
    };
    
    match self.thread_manager.start_compaction(thread_id).await {
        Ok(()) => {
            self.outgoing.send_response(request_id, ThreadCompactStartResponse {}).await;
        }
        Err(e) => { /* 错误处理 */ }
    }
}
```

### 相关文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ClientRequest 枚举定义 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 请求处理实现 |
| `codex-rs/app-server/tests/suite/v2/compaction.rs` | 压缩测试 |
| `codex-rs/tui_app_server/src/app_server_session.rs` | TUI 应用中的使用 |

## 依赖与外部交互

### 上游依赖

1. **线程管理器**: `codex_core::ThreadManager`
2. **压缩逻辑**: 上下文压缩算法实现

### 下游交互

1. **压缩完成**: 压缩完成后添加 `ContextCompaction` 类型的 ThreadItem
2. **Token 使用更新**: 压缩后 token 使用量更新

### 协议版本

- **版本**: v2
- **稳定性**: 稳定 API (非实验性)

## 风险、边界与改进建议

### 风险点

1. **信息丢失**: 压缩过程可能丢失部分对话细节
2. **压缩失败**: 压缩过程可能失败
3. **并发压缩**: 重复启动压缩可能导致问题

### 边界情况

1. **短对话**: 短对话可能不需要压缩
2. **压缩中**: 压缩过程中再次请求压缩
3. **压缩失败**: 压缩失败后的恢复

### 改进建议

1. **添加压缩选项**: 建议添加 `options: CompactionOptions` 字段
2. **添加目标 token 数**: 建议添加 `target_tokens: Option<u32>` 字段
3. **添加压缩策略**: 建议添加 `strategy: CompactionStrategy` 字段

### 示例改进结构

```json
{
  "threadId": "thread-123",
  "options": {
    "targetTokens": 4000,
    "strategy": "summarize",
    "preserveRecentTurns": 5
  }
}
```

### 测试覆盖

相关测试文件：`codex-rs/app-server/tests/suite/v2/compaction.rs`

建议测试场景：
- 正常压缩启动
- 压缩完成验证
- 并发压缩请求处理
