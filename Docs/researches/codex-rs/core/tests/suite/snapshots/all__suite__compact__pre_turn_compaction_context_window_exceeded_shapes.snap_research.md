# Research: pre_turn_compaction_context_window_exceeded_shapes.snap

## 场景与职责

该快照文件记录了**轮前压缩上下文窗口溢出（Pre-turn Compaction Context Window Exceeded）**场景，验证当压缩请求本身超出上下文窗口时的错误处理行为。

**测试场景**：用户对话历史已经很长，在轮前自动压缩时，压缩请求本身超出模型上下文窗口，导致压缩失败。

---

## 功能点目的

1. **溢出检测**：检测压缩请求超出上下文窗口的情况
2. **优雅失败**：压缩失败时停止当前轮次，避免无效 API 调用
3. **错误信息**：向用户提供清晰的上下文窗口溢出提示

---

## 具体技术实现

### 关键流程

```
长历史对话 → 触发轮前压缩 → 压缩请求超出窗口 → API 返回错误 → 轮次停止
```

### 数据结构

**压缩请求（Local Compaction Request - Incoming User Excluded）**:
```
00:message/developer:<PERMISSIONS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:USER_ONE
03:message/assistant:FIRST_REPLY
04:message/user:<SUMMARIZATION_PROMPT>
```

### 关键观察

1. **请求结构**：
   - 包含开发者指令
   - 环境上下文
   - 先前用户消息（USER_ONE）
   - 助手回复（FIRST_REPLY）
   - 摘要提示词

2. **错误处理**：
   - 压缩请求返回 `context_length_exceeded` 错误
   - 当前轮次（USER_TWO）停止
   - 不发送跟进请求

3. **排除新用户消息**：
   - 压缩请求不包含新用户消息（USER_TWO）
   - 这是轮前压缩的标准行为

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/compact.rs`
- **测试函数**: `snapshot_request_shape_pre_turn_compaction_context_window_exceeded` (行 3211-3296)
- **快照生成**: 行 3281-3290

### 测试配置
```rust
let mut model_provider = non_openai_model_provider(&server);
model_provider.stream_max_retries = Some(0);  // 禁用重试

config.model_auto_compact_token_limit = Some(200);
```

### Mock 响应
```rust
// 第一轮成功
let first_turn = sse(vec![
    ev_assistant_message("m1", FIRST_REPLY),
    ev_completed_with_tokens("r1", 500),
]);

// 压缩请求连续失败（5次上下文溢出）
let responses = vec![first_turn];
responses.extend((0..5).map(|_| {
    sse_failed(
        "compact-failed",
        "context_length_exceeded",
        "Your input exceeds the context window of this model...",
    )
}));
```

### 关键断言
```rust
let error_message = wait_for_event_match(&codex, |event| match event {
    EventMsg::Error(err) => Some(err.message.clone()),
    _ => None,
}).await;

assert!(error_message.contains("ran out of room in the model's context window"));
```

---

## 依赖与外部交互

### 外部依赖
1. **Mock Server**: `wiremock::MockServer`
2. **SSE 错误响应**: `sse_failed` 模拟上下文溢出错误

### API 错误码
```json
{
  "error": {
    "code": "context_length_exceeded",
    "message": "Your input exceeds the context window of this model..."
  }
}
```

### 事件流
1. `TurnStarted`
2. `Error` (context_length_exceeded)
3. `TurnComplete`

---

## 风险、边界与改进建议

### 风险点
1. **数据丢失风险**：用户新消息（USER_TWO）因压缩失败而丢失
2. **用户体验差**：用户可能不理解为什么消息发送失败
3. **无限重试**：若无重试限制，可能无限尝试压缩

### 边界情况
1. **部分历史可压缩**：是否应尝试压缩部分历史而非全部
2. **渐进压缩**：多次尝试，每次减少历史量
3. **用户确认**：提示用户历史过长，需要手动清理

### 改进建议
1. **智能截断**：压缩失败时自动截断最旧的历史再尝试
2. **用户提示**：明确告知用户"历史记录过长，请开始新对话"
3. **新会话建议**：提供创建新会话的快捷方式
4. **历史导出**：允许用户导出历史后再开始新会话
5. **压缩预览**：压缩前估算令牌数，提前预警

### 相关测试
- `manual_compact_retries_after_context_window_error`: 手动压缩重试
- `remote_pre_turn_compaction_context_window_exceeded_shapes`: 远程压缩溢出
- `auto_compact_runs_after_token_limit_hit`: 令牌限制触发压缩
