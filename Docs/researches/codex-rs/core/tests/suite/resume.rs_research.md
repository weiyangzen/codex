# resume.rs 深入研究

## 场景与职责

`resume.rs` 是 Codex Core 的集成测试文件，专门测试**会话恢复（Session Resume）**功能。该功能允许用户从之前的会话状态继续对话，保留历史消息和上下文。

### 核心测试场景

1. **基础恢复流程**：验证从 rollout 文件恢复会话时，`initial_messages` 正确包含历史事件
2. **推理事件恢复**：验证带有推理（reasoning）事件的会话恢复后，推理内容正确还原
3. **模型切换保持基础指令**：验证恢复时切换模型，基础指令（base instructions）保持不变
4. **模型切换消息去重**：验证恢复后首次轮次发送模型切换消息，后续轮次不再重复
5. **预轮次覆盖与模型切换**：验证 `OverrideTurnContext` 与模型切换的协同工作

### 恢复流程概览

```
┌─────────────────────────────────────────────────────────────────┐
│                      会话恢复流程                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  原始会话                    恢复会话                            │
│  ┌─────────┐               ┌─────────┐                          │
│  │ 用户输入 │───>│ 恢复 rollout │                          │
│  └─────────┘               └─────────┘                          │
│       │                         │                               │
│       ▼                         ▼                               │
│  ┌─────────┐               ┌─────────┐                          │
│  │模型响应 │               │读取历史 │                          │
│  │(rollout)│               │生成 initial_messages               │
│  └─────────┘               └─────────┘                          │
│       │                         │                               │
│       ▼                         ▼                               │
│  保存到文件              继续新对话                              │
│  (rollout.jsonl)                                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 功能点目的

### 1. 会话恢复 (Resume)

允许用户从之前保存的会话状态继续：
- **历史消息还原**：恢复用户和助手的对话历史
- **推理内容保留**：保留模型的推理过程（reasoning）
- **Turn 上下文保持**：保留每轮对话的上下文设置
- **模型切换支持**：恢复时可以使用不同的模型

### 2. Rollout 文件

会话历史以 JSON Lines 格式保存：
- **EventMsg 事件**：对话中的各种事件
- **TurnContextItem**：每轮对话的上下文配置
- **ResponseItem**：模型响应项

### 3. Initial Messages

恢复会话时生成的事件序列，用于：
- 重建对话历史上下文
- 让新模型了解之前的对话内容
- 保持用户体验的连续性

---

## 具体技术实现

### 关键数据结构

```rust
// 恢复后的会话结构
pub struct TestCodex {
    pub home: Arc<TempDir>,
    pub cwd: Arc<TempDir>,
    pub codex: Arc<CodexThread>,
    pub session_configured: SessionConfiguredEvent,
    pub config: Config,
    pub thread_manager: Arc<ThreadManager>,
}

// SessionConfiguredEvent 中的初始消息
pub struct SessionConfiguredEvent {
    pub initial_messages: Option<Vec<EventMsg>>,  // 恢复的历史事件
    pub rollout_path: Option<PathBuf>,            // rollout 文件路径
    // ... 其他字段
}
```

### 恢复轮询机制

```rust
async fn resume_until_initial_messages(
    builder: &mut TestCodexBuilder,
    server: &MockServer,
    home: Arc<TempDir>,
    rollout_path: PathBuf,
    predicate: impl Fn(&[EventMsg]) -> bool,
) -> Result<TestCodex> {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(2);
    let poll_interval = Duration::from_millis(10);
    
    loop {
        let resumed = builder.resume(server, Arc::clone(&home), rollout_path.clone()).await?;
        
        if let Some(initial_messages) = resumed.session_configured.initial_messages.as_ref() {
            if predicate(initial_messages) {
                return Ok(resumed);
            }
        }
        
        if tokio::time::Instant::now() >= deadline {
            panic!("timed out waiting for rollout resume messages to stabilize");
        }
        
        drop(resumed);
        tokio::time::sleep(poll_interval).await;
    }
}
```

### 测试 1：基础事件恢复

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn resume_includes_initial_messages_from_rollout_events() -> Result<()> {
    // 1. 创建初始会话并执行一轮对话
    let server = start_mock_server().await;
    let mut builder = test_codex();
    let initial = builder.build(&server).await?;
    let codex = Arc::clone(&initial.codex);
    let home = initial.home.clone();
    let rollout_path = initial.session_configured.rollout_path.clone().expect("rollout path");
    
    // 2. 挂载 SSE 响应并提交用户输入
    mount_sse_once(&server, sse(vec![
        ev_response_created("resp-initial"),
        ev_assistant_message("msg-1", "Completed first turn"),
        ev_completed("resp-initial"),
    ])).await;
    
    codex.submit(Op::UserInput { ... }).await?;
    wait_for_event(&codex, |event| matches!(event, EventMsg::TurnComplete(_))).await;
    
    // 3. 恢复会话并验证 initial_messages
    let resumed = resume_until_initial_messages(
        &mut builder, &server, home, rollout_path,
        |initial_messages| {
            matches!(initial_messages, [
                EventMsg::TurnStarted(_),
                EventMsg::UserMessage(_),
                EventMsg::TokenCount(_),
                EventMsg::AgentMessage(_),
                EventMsg::TokenCount(_),
                EventMsg::TurnComplete(_),
            ])
        },
    ).await;
    
    // 4. 验证消息内容
    let initial_messages = resumed.session_configured.initial_messages.expect("...");
    match initial_messages.as_slice() {
        [EventMsg::TurnStarted(started), EventMsg::UserMessage(first_user), ...] => {
            assert_eq!(first_user.message, "Record some messages");
            assert_eq!(assistant_message.message, "Completed first turn");
            assert_eq!(completed.turn_id, started.turn_id);
        }
        other => panic!("unexpected initial messages: {other:#?}"),
    }
    
    Ok(())
}
```

### 测试 2：推理事件恢复

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn resume_includes_initial_messages_from_reasoning_events() -> Result<()> {
    // 启用原始推理内容显示
    let mut builder = test_codex().with_config(|config| {
        config.show_raw_agent_reasoning = true;
    });
    
    // 挂载包含推理事件的 SSE
    let initial_sse = sse(vec![
        ev_response_created("resp-initial"),
        ev_reasoning_item("reason-1", &["Summarized step"], &["raw detail"]),
        ev_assistant_message("msg-1", "Completed reasoning turn"),
        ev_completed("resp-initial"),
    ]);
    
    // 验证恢复后包含推理事件
    let resumed = resume_until_initial_messages(..., |initial_messages| {
        matches!(initial_messages, [
            EventMsg::TurnStarted(_),
            EventMsg::UserMessage(_),
            EventMsg::TokenCount(_),
            EventMsg::AgentReasoning(_),
            EventMsg::AgentReasoningRawContent(_),
            EventMsg::AgentMessage(_),
            EventMsg::TokenCount(_),
            EventMsg::TurnComplete(_),
        ])
    }).await;
}
```

### 测试 3：模型切换保持基础指令

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn resume_switches_models_preserves_base_instructions() -> Result<()> {
    // 1. 初始会话使用 gpt-5.2
    let mut builder = test_codex().with_config(|config| {
        config.model = Some("gpt-5.2".to_string());
    });
    
    // 2. 执行一轮对话，捕获基础指令
    let initial_mock = mount_sse_once(&server, initial_sse).await;
    let initial_body = initial_mock.single_request().body_json();
    let initial_instructions = initial_body.get("instructions").and_then(|v| v.as_str()).unwrap();
    
    // 3. 恢复会话使用 gpt-5.2-codex
    let mut resume_builder = test_codex().with_config(|config| {
        config.model = Some("gpt-5.2-codex".to_string());
    });
    let resumed = resume_builder.resume(&server, home, rollout_path).await?;
    
    // 4. 验证恢复后的请求使用相同基础指令
    let requests = resumed_mock.requests();
    assert_eq!(requests[0].instructions_text(), initial_instructions);
    
    // 5. 验证模型切换消息
    let first_model_switch_count = first_developer_texts
        .iter()
        .filter(|text| text.contains("<model_switch>"))
        .count();
    assert!(first_model_switch_count >= 1);
}
```

### 测试 4：模型切换消息去重

```rust
// 验证第二次轮次不再包含重复的模型切换消息
let second_model_switch_count = second_developer_texts
    .iter()
    .filter(|text| text.contains("<model_switch>"))
    .count();
assert_eq!(second_model_switch_count, 1,
    "did not expect duplicate model switch message after first post-resume turn"
);
```

### 测试 5：预轮次覆盖与模型切换

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn resume_model_switch_is_not_duplicated_after_pre_turn_override() -> Result<()> {
    // 1. 恢复会话
    let resumed = resume_builder.resume(&server, home, rollout_path).await?;
    
    // 2. 提交 OverrideTurnContext（切换模型）
    resumed.codex.submit(Op::OverrideTurnContext {
        model: Some("gpt-5.1-codex-max".to_string()),
        // ... 其他字段为 None
    }).await?;
    
    // 3. 提交用户输入
    resumed.codex.submit(Op::UserInput { ... }).await?;
    
    // 4. 验证只包含一个模型切换消息
    let model_switch_count = developer_texts
        .iter()
        .filter(|text| text.contains("<model_switch>"))
        .count();
    assert_eq!(model_switch_count, 1);
}
```

---

## 关键代码路径与文件引用

### 测试文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/tests/suite/resume.rs` | 本测试文件 |
| `codex-rs/core/tests/common/lib.rs` | 测试支持库 |
| `codex-rs/core/tests/common/responses.rs` | SSE Mock 响应工具 |
| `codex-rs/core/tests/common/test_codex.rs` | TestCodex 构建器（含 resume 方法） |

### 协议定义

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/protocol/src/protocol.rs` | EventMsg, SessionConfiguredEvent, TurnStartedEvent 等 |
| `codex-rs/protocol/src/user_input.rs` | UserInput, TextElement, ByteRange |

### 核心恢复类型

```rust
// codex-rs/core/tests/common/test_codex.rs
impl TestCodexBuilder {
    pub async fn resume(
        &mut self,
        server: &wiremock::MockServer,
        home: Arc<TempDir>,
        rollout_path: PathBuf,
    ) -> anyhow::Result<TestCodex> {
        Box::pin(self.build_with_home(server, home, Some(rollout_path))).await
    }
}

// 恢复流程内部实现
async fn build_from_config(...) -> anyhow::Result<TestCodex> {
    let new_conversation = match (resume_from, user_shell_override) {
        (Some(path), None) => {
            let auth_manager = codex_core::test_support::auth_manager_from_auth(auth);
            Box::pin(thread_manager.resume_thread_from_rollout(
                config.clone(),
                path,
                auth_manager,
                /*parent_trace*/ None,
            )).await?
        }
        // ... 其他分支
    };
}
```

### 关键事件类型

```rust
// codex-rs/protocol/src/protocol.rs
pub enum EventMsg {
    TurnStarted(TurnStartedEvent),
    TurnComplete(TurnCompleteEvent),
    UserMessage(UserMessageEvent),
    AgentMessage(AgentMessageEvent),
    AgentReasoning(AgentReasoningEvent),
    AgentReasoningRawContent(AgentReasoningRawContentEvent),
    TokenCount(TokenCountEvent),
    // ... 其他事件
}

pub struct TurnStartedEvent {
    pub turn_id: String,
    pub model_context_window: Option<i64>,
    pub collaboration_mode_kind: ModeKind,
}

pub struct TurnCompleteEvent {
    pub turn_id: String,
    pub last_agent_message: Option<String>,
}
```

---

## 依赖与外部交互

### 测试依赖

```rust
// 核心依赖
codex_protocol::protocol::{EventMsg, Op}
codex_protocol::user_input::{ByteRange, TextElement, UserInput}
codex_core::CodexThread

// 测试支持
core_test_support::responses::*
core_test_support::skip_if_no_network!
core_test_support::test_codex::{TestCodex, TestCodexBuilder, test_codex}
core_test_support::wait_for_event
core_test_support::wait_for_event_match
```

### SSE 事件构建器

```rust
// 推理事件构建器
pub fn ev_reasoning_item(id: &str, summary: &[&str], raw_content: &[&str]) -> Value {
    let summary_entries: Vec<Value> = summary
        .iter()
        .map(|text| serde_json::json!({"type": "summary_text", "text": text}))
        .collect();
    
    // 加密原始内容（模拟）
    let overhead = "b".repeat(550);
    let raw_content_joined = raw_content.join("");
    let encrypted_content = base64::engine::general_purpose::STANDARD
        .encode(overhead + raw_content_joined.as_str());
    
    serde_json::json!({
        "type": "response.output_item.done",
        "item": {
            "type": "reasoning",
            "id": id,
            "summary": summary_entries,
            "encrypted_content": encrypted_content,
            "content": content_entries,  // 如果 raw_content 非空
        }
    })
}
```

---

## 风险、边界与改进建议

### 当前限制

1. **轮询等待**：`resume_until_initial_messages` 使用 2 秒超时轮询，可能不稳定
2. **多线程要求**：使用 `worker_threads = 2`，增加测试复杂度
3. **网络依赖**：需要真实网络环境

### 边界情况

1. **Rollout 文件格式**：
   - JSON Lines 格式，每行一个事件
   - 需要处理文件损坏或不完整的情况

2. **模型切换消息**：
   - 使用 `<model_switch>` XML 标签标记
   - 首次恢复后发送，后续去重

3. **推理内容加密**：
   - 原始推理内容经过 base64 编码
   - 测试中使用固定填充（550 字节 "b"）

### 改进建议

1. **稳定性改进**：
   - 使用事件驱动替代轮询等待
   - 增加更明确的同步机制

2. **测试覆盖**：
   - 添加并发恢复测试
   - 添加损坏 rollout 文件处理测试
   - 添加大文件恢复性能测试

3. **调试支持**：
   - 增加更多断言失败时的上下文信息
   - 打印完整的 initial_messages 用于调试

4. **文档改进**：
   - 说明 rollout 文件格式规范
   - 说明模型切换消息的生成逻辑

### 相关测试

- `resume_warning.rs` - 恢复时的警告测试（模型不匹配等）
- `compact_resume_fork.rs` - 压缩和恢复测试
- `sqlite_state.rs` - 状态持久化测试

### 恢复流程中的关键断言

```rust
// 验证 Turn ID 一致性
assert_eq!(completed.turn_id, started.turn_id);

// 验证最后一条助手消息
assert_eq!(completed.last_agent_message.as_deref(), Some("Completed first turn"));

// 验证文本元素保留
assert_eq!(first_user.text_elements, text_elements);
```
