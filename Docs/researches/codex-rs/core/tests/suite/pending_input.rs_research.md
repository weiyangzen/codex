# pending_input.rs 研究文档

## 场景与职责

`pending_input.rs` 是 Codex 核心库的待处理输入 (pending input) 测试套件。它负责验证当用户在当前回合尚未完成时提交新输入的行为——这种输入会被暂存，并在当前回合完成后自动触发新的后续请求。

这是 Codex 交互模型的关键特性，允许用户：
- 在当前回合处理期间继续输入
- 无需等待当前回合完成即可准备下一个查询
- 实现更流畅的连续对话体验

## 功能点目的

### 注入用户输入触发后续请求 (`injected_user_input_triggers_follow_up_request_with_deltas`)

验证当用户在当前 SSE 流尚未完成时提交新输入：
1. 新输入被暂存为 "pending input"
2. 当前回合完成后，自动触发新的 API 请求
3. 新请求包含之前所有回合的历史记录
4. 新请求包含新提交的输入

这个测试目前标记为 `#[ignore = "TODO(aibrahim): flaky"]`，表明存在不稳定性问题。

## 具体技术实现

### 关键数据结构

```rust
// SSE 事件构造辅助函数
fn ev_message_item_done(id: &str, text: &str) -> Value {
    serde_json::json!({
        "type": "response.output_item.done",
        "item": {
            "type": "message",
            "role": "assistant",
            "id": id,
            "content": [{"type": "output_text", "text": text}]
        }
    })
}

fn sse_event(event: Value) -> String {
    responses::sse(vec![event])
}

// 从请求体中提取特定角色的消息文本
fn message_input_texts(body: &Value, role: &str) -> Vec<String> {
    body.get("input")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter(|item| item.get("type").and_then(Value::as_str) == Some("message"))
        .filter(|item| item.get("role").and_then(Value::as_str) == Some(role))
        .filter_map(|item| item.get("content").and_then(Value::as_array))
        .flatten()
        .filter(|span| span.get("type").and_then(Value::as_str) == Some("input_text"))
        .filter_map(|span| span.get("text").and_then(Value::as_str).map(str::to_owned))
        .collect()
}
```

### 流式 SSE 服务器

测试使用 `StreamingSseServer` 实现精细的 SSE 流控制：

```rust
// 第一个响应：包含门控的完成事件
let first_chunks = vec![
    StreamingSseChunk { gate: None, body: sse_event(ev_response_created("resp-1")) },
    StreamingSseChunk { gate: None, body: sse_event(ev_message_item_added("msg-1", "")) },
    StreamingSseChunk { gate: None, body: sse_event(ev_output_text_delta("first ")) },
    StreamingSseChunk { gate: None, body: sse_event(ev_output_text_delta("turn")) },
    StreamingSseChunk { gate: None, body: sse_event(ev_message_item_done("msg-1", "first turn")) },
    StreamingSseChunk {
        gate: Some(gate_completed_rx),  // 关键：门控暂停
        body: sse_event(ev_completed("resp-1")),
    },
];

// 第二个响应：后续请求
let second_chunks = vec![
    StreamingSseChunk { gate: None, body: sse_event(ev_response_created("resp-2")) },
    StreamingSseChunk { gate: None, body: sse_event(ev_completed("resp-2")) },
];
```

### 测试流程

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
#[ignore = "TODO(aibrahim): flaky"]
async fn injected_user_input_triggers_follow_up_request_with_deltas() {
    // 1. 创建门控通道
    let (gate_completed_tx, gate_completed_rx) = oneshot::channel();

    // 2. 配置带门控的 SSE 响应
    let first_chunks = vec![...];
    let second_chunks = vec![...];
    
    // 3. 启动流式 SSE 服务器
    let (server, _completions) =
        start_streaming_sse_server(vec![first_chunks, second_chunks]).await;

    // 4. 创建 TestCodex 实例
    let codex = test_codex()
        .with_model("gpt-5.1")
        .build_with_streaming_server(&server)
        .await
        .unwrap()
        .codex;

    // 5. 提交第一个提示
    codex.submit(Op::UserInput { ... }).await.unwrap();

    // 6. 等待第一个内容增量事件
    wait_for_event(&codex, |event| {
        matches!(event, EventMsg::AgentMessageContentDelta(_))
    }).await;

    // 7. 在第一个回合完成前提交第二个提示（pending input）
    codex.submit(Op::UserInput { ... }).await.unwrap();

    // 8. 释放门控，允许第一个回合完成
    let _ = gate_completed_tx.send(());

    // 9. 等待第二个回合完成
    wait_for_event(&codex, |event| matches!(event, EventMsg::TurnComplete(_))).await;

    // 10. 验证请求历史
    let requests = server.requests().await;
    assert_eq!(requests.len(), 2);

    // 11. 验证第一个请求只包含第一个提示
    let first_body: Value = serde_json::from_slice(&requests[0]).expect("parse first request");
    let first_texts = message_input_texts(&first_body, "user");
    assert!(first_texts.iter().any(|text| text == "first prompt"));
    assert!(!first_texts.iter().any(|text| text == "second prompt"));

    // 12. 验证第二个请求包含两个提示
    let second_body: Value = serde_json::from_slice(&requests[1]).expect("parse second request");
    let second_texts = message_input_texts(&second_body, "user");
    assert!(second_texts.iter().any(|text| text == "first prompt"));
    assert!(second_texts.iter().any(|text| text == "second prompt"));

    server.shutdown().await;
}
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/core/tests/suite/pending_input.rs` - 本测试文件

### 被测试的源文件
- `codex-rs/core/src/codex.rs` - Codex 核心实现，处理 pending input 逻辑
- `codex-rs/core/src/state/turn.rs` - 回合状态管理
- `codex-rs/core/src/state/session.rs` - 会话状态管理

### 测试支持文件
- `codex-rs/core/tests/common/streaming_sse.rs` - StreamingSseServer 实现
- `codex-rs/core/tests/common/test_codex.rs` - TestCodex 测试工具
- `codex-rs/core/tests/common/responses.rs` - SSE 事件构造辅助函数

### 协议定义
- `codex-rs/protocol/src/protocol.rs` - `Op::UserInput` 和 `EventMsg` 定义
- `codex-rs/protocol/src/user_input.rs` - `UserInput` 类型定义

## 依赖与外部交互

### 内部依赖

```rust
// Codex 协议
codex_protocol::protocol::EventMsg
codex_protocol::protocol::Op
codex_protocol::user_input::UserInput

// 测试支持
core_test_support::responses
core_test_support::responses::ev_completed
core_test_support::responses::ev_message_item_added
core_test_support::responses::ev_output_text_delta
core_test_support::responses::ev_response_created
core_test_support::streaming_sse::StreamingSseChunk
core_test_support::streaming_sse::start_streaming_sse_server
core_test_support::test_codex::test_codex
core_test_support::wait_for_event

// 工具库
pretty_assertions::assert_eq
serde_json::Value
tokio::sync::oneshot
```

### 流式 SSE 服务器

测试使用专门的 `StreamingSseServer` 而非标准的 `wiremock`：

```rust
pub struct StreamingSseChunk {
    pub gate: Option<oneshot::Receiver<()>>,  // 门控信号
    pub body: String,                         // SSE 事件体
}
```

门控机制允许测试精确控制 SSE 流的发送时机：
- `gate: None` - 立即发送
- `gate: Some(rx)` - 等待信号后发送

### 多线程运行时

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
```

使用多线程运行时因为：
1. Codex 内部使用异步任务处理 SSE 流
2. Pending input 逻辑涉及并发状态管理
3. 需要同时处理用户输入提交和 SSE 事件接收

## 风险、边界与改进建议

### 当前风险

1. **测试不稳定**: 测试被标记为 `#[ignore]`，说明存在 flaky 问题。可能原因：
   - 时序竞争条件
   - 事件顺序的不确定性
   - 超时设置不合理

2. **有限的场景覆盖**: 目前只有一个测试，覆盖场景有限：
   - 只测试了单个 pending input
   - 未测试多个连续 pending input
   - 未测试 pending input 与工具调用的交互

3. **门控复杂性**: 使用 `oneshot::channel` 作为门控增加了测试复杂度，可能成为不稳定因素。

### 边界情况

1. **回合失败**: 如果第一个回合失败（而非正常完成），pending input 应如何处理？

2. **会话关闭**: 如果在 pending input 存在时关闭会话，是否应该丢弃或保存？

3. **模型切换**: 如果在 pending input 存在时切换模型，新回合应使用哪个模型？

4. **配置变更**: 如果在 pending input 存在时修改配置（如 approval_policy），新回合应使用哪个配置？

### 改进建议

1. **修复 Flaky 测试**:
   ```rust
   // 增加更可靠的同步机制
   // 使用事件计数而非单一事件匹配
   // 增加重试逻辑
   ```

2. **增加场景覆盖**:
   - 多个连续 pending input
   - pending input 与工具调用并发
   - pending input 与会话恢复
   - pending input 与会话分叉

3. **增加错误场景测试**:
   ```rust
   #[tokio::test]
   async fn pending_input_discarded_on_turn_failure() { ... }
   
   #[tokio::test]
   async fn pending_input_preserved_on_session_shutdown() { ... }
   ```

4. **使用更稳定的同步原语**:
   考虑使用 `tokio::sync::Barrier` 或自定义事件计数器替代 `oneshot::channel`。

5. **增加状态验证**:
   ```rust
   // 验证 pending input 队列状态
   // 验证内部状态机转换
   ```

6. **性能测试**:
   ```rust
   // 测试大量 pending input 的内存使用
   // 测试 pending input 处理的延迟
   ```

7. **文档化行为契约**:
   在代码注释中明确说明：
   - Pending input 的 FIFO 保证
   - 与回合状态的交互规则
   - 错误处理行为

8. **增加日志验证**:
   验证 pending input 相关的遥测事件：
   ```rust
   // 验证 codex.pending_input_queued 事件
   // 验证 codex.pending_input_processed 事件
   ```
