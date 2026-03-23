# Research: remote_pre_turn_compaction_context_window_exceeded_shapes.snap

## 场景与职责

该快照文件记录了**远程轮前压缩上下文窗口溢出（Remote Pre-turn Compaction Context Window Exceeded）**场景，验证当远程压缩请求超出上下文窗口时的错误处理。

**测试场景**：用户对话历史已经很长，在轮前自动压缩时，远程压缩请求本身超出模型上下文窗口。

---

## 功能点目的

1. **溢出错误处理**：正确处理远程压缩的上下文溢出错误
2. **轮次停止**：压缩失败时停止当前轮次
3. **错误信息**：向用户提供清晰的错误提示

---

## 具体技术实现

### 关键流程

```
长历史对话 → 触发轮前压缩 → 远程压缩请求超出窗口 → API 返回400错误 → 轮次停止
```

### 数据结构

**远程压缩请求（Remote Compaction Request - Incoming User Excluded）**:
```
00:message/developer:<PERMISSIONS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:USER_ONE
03:message/assistant:REMOTE_FIRST_REPLY
```

### 关键观察

1. **请求结构**：
   - 包含开发者指令
   - 环境上下文
   - 先前用户消息和助手回复
   - 不包含新用户消息（USER_TWO）

2. **错误响应**：
   - HTTP 400 Bad Request
   - 错误码：`context_length_exceeded`

3. **错误处理**：
   - 轮次停止
   - 不发送跟进请求
   - 返回错误事件

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/compact_remote.rs`
- **测试函数**: `snapshot_request_shape_remote_pre_turn_compaction_context_window_exceeded` (行 2207-2307)
- **快照生成**: 行 2291-2300

### Mock 配置
```rust
let compact_mock = responses::mount_compact_response_once(
    harness.server(),
    ResponseTemplate::new(400).set_body_json(serde_json::json!({
        "error": {
            "code": "context_length_exceeded",
            "message": "Your input exceeds the context window of this model..."
        }
    })),
).await;
```

### 关键断言
```rust
let error_message = wait_for_event_match(&codex, |event| match event {
    EventMsg::Error(err) => Some(err.message.clone()),
    _ => None,
}).await;

assert!(error_message.to_lowercase().contains("context window"));
assert_eq!(compact_mock.requests().len(), 1);
assert!(post_compact_turn_mock.requests().is_empty());
```

---

## 依赖与外部交互

### 外部依赖
1. **Mock Server**: `wiremock::MockServer`
2. **TestCodexHarness**: 测试工具

### API 错误响应
```json
HTTP/1.1 400 Bad Request
Content-Type: application/json

{
  "error": {
    "code": "context_length_exceeded",
    "message": "Your input exceeds the context window of this model. Please adjust your input and try again."
  }
}
```

---

## 风险、边界与改进建议

### 风险点
1. **数据丢失**：新用户消息因压缩失败而丢失
2. **用户体验差**：用户可能不理解为什么消息发送失败
3. **无法恢复**：远程压缩失败后无法像本地压缩那样重试

### 边界情况
1. **部分历史可压缩**：是否应尝试压缩部分历史
2. **渐进压缩**：多次尝试，每次减少历史量
3. **本地备选**：远程压缩失败后回退到本地压缩

### 改进建议
1. **本地备选**：远程压缩失败时尝试本地压缩
2. **智能截断**：自动截断最旧的历史再尝试
3. **用户提示**：明确告知用户"历史记录过长，请开始新对话"
4. **新会话建议**：提供创建新会话的快捷方式
5. **历史导出**：允许用户导出历史后再开始新会话

### 相关测试
- `pre_turn_compaction_context_window_exceeded_shapes`: 本地压缩溢出
- `auto_remote_compact_failure_stops_agent_loop`: 远程压缩失败停止
