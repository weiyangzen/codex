# quota_exceeded.rs 研究文档

## 场景与职责

`quota_exceeded.rs` 是 Codex Core 的集成测试套件，专门测试 **配额超限错误处理** 功能。当用户的 API 配额耗尽时，OpenAI API 会返回 `insufficient_quota` 错误，Codex 需要正确捕获该错误并向用户展示友好的错误信息。

该测试确保：
- 配额超限错误被正确识别和处理
- 用户收到清晰、可操作的错误提示
- 错误事件只触发一次，避免重复通知
- 对话正确结束（`TurnComplete` 事件）

## 功能点目的

### 1. 错误识别与转换
验证 API 返回的 `insufficient_quota` 错误码被正确识别并转换为内部错误类型。

### 2. 用户友好消息
验证错误消息从 API 的 "You exceeded your current quota, please check your plan and billing details." 转换为更简洁的 "Quota exceeded. Check your plan and billing details."

### 3. 单次错误事件
确保在整轮对话中，配额超限错误只触发一次 `EventMsg::Error`，避免错误风暴。

### 4. 对话生命周期
验证即使发生配额错误，对话仍能正确完成（触发 `TurnComplete` 事件），保持状态一致性。

## 具体技术实现

### API 错误响应结构

```json
{
    "type": "response.failed",
    "response": {
        "id": "resp-1",
        "error": {
            "code": "insufficient_quota",
            "message": "You exceeded your current quota, please check your plan and billing details."
        }
    }
}
```

### 测试流程

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn quota_exceeded_emits_single_error_event() -> Result<()> {
    // 1. 启动 Mock 服务器
    let server = start_mock_server().await;
    
    // 2. 配置 SSE 响应流，包含配额错误
    mount_sse_once(
        &server,
        sse(vec![
            ev_response_created("resp-1"),
            json!({
                "type": "response.failed",
                "response": {
                    "id": "resp-1",
                    "error": {
                        "code": "insufficient_quota",
                        "message": "You exceeded your current quota, please check your plan and billing details."
                    }
                }
            }),
        ]),
    ).await;
    
    // 3. 构建测试 Codex 实例
    let test = test_codex().build(&server).await?;
    
    // 4. 发送用户输入
    test.codex.submit(Op::UserInput {
        items: vec![UserInput::Text { text: "quota?".into(), ... }],
        final_output_json_schema: None,
    }).await?;
    
    // 5. 收集事件并验证
    let mut error_events = 0;
    loop {
        let event = wait_for_event(&test.codex, |_| true).await;
        match event {
            EventMsg::Error(err) => {
                error_events += 1;
                assert_eq!(err.message, "Quota exceeded. Check your plan and billing details.");
            }
            EventMsg::TurnComplete(_) => break,
            _ => {}
        }
    }
    
    // 6. 验证只有一个错误事件
    assert_eq!(error_events, 1, "expected exactly one Codex:Error event");
    Ok(())
}
```

### 关键断言

| 断言点 | 验证内容 |
|-------|---------|
| `error_events == 1` | 错误事件只触发一次 |
| `err.message` 匹配 | 错误消息被正确转换 |
| `EventMsg::TurnComplete` | 对话正确结束 |

## 依赖与外部交互

### 核心依赖

| 模块 | 用途 |
|-----|------|
| `codex_protocol::protocol::EventMsg` | 事件类型定义 |
| `codex_protocol::protocol::Op::UserInput` | 用户输入操作 |
| `codex_protocol::user_input::UserInput` | 用户输入数据结构 |
| `core_test_support::responses::*` | Mock SSE 响应 |
| `core_test_support::test_codex::test_codex` | 测试 Codex 构建 |
| `core_test_support::wait_for_event` | 异步事件等待 |

### 错误处理链

```
API Response (response.failed)
    ↓
codex_api  crate - 解析错误响应
    ↓
codex_core::client - 映射为内部错误
    ↓
codex_core::codex - 转换为 EventMsg::Error
    ↓
TUI / CLI - 展示给用户
```

### 错误码映射

当前测试仅覆盖 `insufficient_quota` 错误码。生产环境可能还需要处理：
- `rate_limit_exceeded` - 速率限制
- `invalid_api_key` - API 密钥无效
- `model_not_found` - 模型不可用
- `context_length_exceeded` - 上下文长度超限

## 风险、边界与改进建议

### 已知边界

1. **单一错误码覆盖**: 当前测试仅验证 `insufficient_quota`，未覆盖其他配额相关错误码。

2. **网络条件**: 测试使用 Mock 服务器，未验证真实网络环境下的错误处理。

3. **重试行为**: 未测试配额错误是否触发重试逻辑（应不触发）。

### 潜在风险

1. **错误消息变更**: 如果 API 错误消息格式变更，可能导致错误识别失败。

2. **多错误累积**: 如果 API 返回多个错误，当前逻辑可能只处理第一个。

3. **国际化**: 错误消息当前为英文，未考虑本地化需求。

### 改进建议

1. **扩展错误码覆盖**: 添加测试覆盖其他常见错误码：
   ```rust
   // 建议添加的测试
   async fn rate_limit_exceeded_emits_error_event();
   async fn invalid_api_key_emits_error_event();
   async fn model_not_found_emits_error_event();
   ```

2. **错误恢复测试**: 验证配额错误后，用户升级配额能否恢复正常对话。

3. **错误详情保留**: 考虑在友好消息之外，保留原始错误详情供调试使用。

4. **遥测上报**: 添加测试验证配额错误被正确上报到分析系统。

5. **批量错误处理**: 测试 API 返回多个错误时的行为。

### 相关文件引用

- 测试文件: `codex-rs/core/tests/suite/quota_exceeded.rs` (74 行)
- API 错误处理: `codex-rs/core/src/client.rs`
- 错误类型定义: `codex-rs/core/src/error.rs`
- API 桥接: `codex-rs/core/src/api_bridge.rs`
- 协议事件: `codex-rs/protocol/src/protocol.rs`
