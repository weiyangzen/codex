# review.rs 研究文档

## 场景与职责

`review.rs` 实现了 **ReviewTask**（代码审查任务），用于执行 AI 辅助的代码审查流程。该任务创建一个子代理（sub-agent）会话，专门分析代码变更并提供审查反馈。

### 核心职责
1. **子代理创建**：启动独立的审查代理会话
2. **事件流处理**：过滤和转换审查事件流
3. **审查输出解析**：从代理响应中提取结构化审查结果
4. **模式退出处理**：发送审查完成事件和记录对话历史

### 使用场景
- 用户执行 `/review` 命令请求代码审查
- 需要独立配置（禁用某些功能）的专门审查流程
- 生成结构化审查报告（`ReviewOutputEvent`）

## 功能点目的

### 1. 隔离审查环境
审查代理使用独立的配置：
- **禁用 Web 搜索**：`WebSearchMode::Disabled`
- **禁用特定功能**：`SpawnCsv`、`Collab`
- **专用审查提示词**：`REVIEW_PROMPT`
- **自动审批策略**：`AskForApproval::Never`（审查代理不需要人工审批）

### 2. 事件流过滤
审查任务需要特殊的事件处理：
- **抑制 `AgentMessage`**：不直接转发，等待 `TurnComplete`
- **抑制 `ItemCompleted`**（助手消息）：避免触发遗留事件
- **抑制 Delta 事件**：`AgentMessageDelta`、`AgentMessageContentDelta`
- **转发其他事件**：错误、警告等保持可见

### 3. 输出解析
支持多种输出格式：
- **标准 JSON**：直接反序列化为 `ReviewOutputEvent`
- **嵌入 JSON**：从文本中提取 JSON 对象子串
- **纯文本回退**：作为 `overall_explanation` 包装

### 4. 模式退出
审查完成时：
1. 发送 `ExitedReviewMode` 事件
2. 记录用户消息（审查结果摘要）
3. 记录助手消息（格式化审查输出）
4. 确保持久化 rollout

## 具体技术实现

### 关键数据结构

```rust
#[derive(Clone, Copy)]
pub(crate) struct ReviewTask;

impl ReviewTask {
    pub(crate) fn new() -> Self {
        Self
    }
}
```

### SessionTask 实现

```rust
#[async_trait]
impl SessionTask for ReviewTask {
    fn kind(&self) -> TaskKind {
        TaskKind::Review
    }

    fn span_name(&self) -> &'static str {
        "session_task.review"
    }

    async fn run(...) -> Option<String> {
        // 1. 记录审查任务指标
        // 2. 启动审查对话
        // 3. 处理事件流
        // 4. 退出审查模式
    }

    async fn abort(&self, ...) {
        // 取消时退出审查模式
        exit_review_mode(..., /*review_output*/ None, ...).await;
    }
}
```

### 审查对话启动

```rust
async fn start_review_conversation(
    session: Arc<SessionTaskContext>,
    ctx: Arc<TurnContext>,
    input: Vec<UserInput>,
    cancellation_token: CancellationToken,
) -> Option<async_channel::Receiver<Event>>
```

**配置步骤**：

1. **克隆并修改配置**
   ```rust
   let mut sub_agent_config = config.as_ref().clone();
   ```

2. **禁用受限功能**
   ```rust
   sub_agent_config.web_search_mode.set(WebSearchMode::Disabled)?;
   sub_agent_config.features.disable(Feature::SpawnCsv);
   sub_agent_config.features.disable(Feature::Collab);
   ```

3. **设置审查提示词和审批策略**
   ```rust
   sub_agent_config.base_instructions = Some(crate::REVIEW_PROMPT.to_string());
   sub_agent_config.permissions.approval_policy = Constrained::allow_only(AskForApproval::Never);
   ```

4. **选择审查模型**
   ```rust
   let model = config.review_model.clone()
       .unwrap_or_else(|| ctx.model_info.slug.clone());
   sub_agent_config.model = Some(model);
   ```

5. **启动一次性代理线程**
   ```rust
   run_codex_thread_one_shot(
       sub_agent_config,
       session.auth_manager(),
       session.models_manager(),
       input,
       session.clone_session(),
       ctx.clone(),
       cancellation_token,
       SubAgentSource::Review,
       /*final_output_json_schema*/ None,
       /*initial_history*/ None,
   )
   ```

### 事件流处理

```rust
async fn process_review_events(
    session: Arc<SessionTaskContext>,
    ctx: Arc<TurnContext>,
    receiver: async_channel::Receiver<Event>,
) -> Option<ReviewOutputEvent>
```

**事件处理逻辑**：

```rust
while let Ok(event) = receiver.recv().await {
    match event.clone().msg {
        EventMsg::AgentMessage(_) => {
            // 暂存，等待可能的 TurnComplete
            if let Some(prev) = prev_agent_message.take() {
                session.clone_session().send_event(...).await;
            }
            prev_agent_message = Some(event);
        }
        EventMsg::ItemCompleted(ItemCompletedEvent { item: TurnItem::AgentMessage(_), .. })
        | EventMsg::AgentMessageDelta(_)
        | EventMsg::AgentMessageContentDelta(_) => {
            // 抑制这些事件
        }
        EventMsg::TurnComplete(task_complete) => {
            // 解析审查输出
            return task_complete.last_agent_message
                .as_deref()
                .map(parse_review_output_event);
        }
        EventMsg::TurnAborted(_) => {
            return None;
        }
        other => {
            // 转发其他事件
            session.clone_session().send_event(...).await;
        }
    }
}
```

### 输出解析

```rust
fn parse_review_output_event(text: &str) -> ReviewOutputEvent {
    // 尝试 1：直接解析
    if let Ok(ev) = serde_json::from_str::<ReviewOutputEvent>(text) {
        return ev;
    }
    
    // 尝试 2：提取 JSON 子串
    if let (Some(start), Some(end)) = (text.find('{'), text.rfind('}'))
        && start < end
        && let Some(slice) = text.get(start..=end)
        && let Ok(ev) = serde_json::from_str::<ReviewOutputEvent>(slice)
    {
        return ev;
    }
    
    // 回退：包装为纯文本
    ReviewOutputEvent {
        overall_explanation: text.to_string(),
        ..Default::default()
    }
}
```

### 模式退出

```rust
pub(crate) async fn exit_review_mode(
    session: Arc<Session>,
    review_output: Option<ReviewOutputEvent>,
    ctx: Arc<TurnContext>,
)
```

**执行步骤**：

1. **准备消息内容**
   ```rust
   let (user_message, assistant_message) = if let Some(out) = review_output.clone() {
       // 格式化审查结果
       let findings_str = format_findings(&out);
       let rendered = REVIEW_EXIT_SUCCESS_TMPL.replace("{results}", &findings_str);
       let assistant_message = render_review_output_text(&out);
       (rendered, assistant_message)
   } else {
       // 中断情况
       (REVIEW_EXIT_INTERRUPTED_TMPL.to_string(), "Review was interrupted...".to_string())
   };
   ```

2. **记录用户消息**
   ```rust
   session.record_conversation_items(&ctx, &[ResponseItem::Message {
       id: Some("review_rollout_user".to_string()),
       role: "user".to_string(),
       content: vec![ContentItem::InputText { text: user_message }],
       ...
   }]).await;
   ```

3. **发送退出事件**
   ```rust
   session.send_event(
       ctx.as_ref(),
       EventMsg::ExitedReviewMode(ExitedReviewModeEvent { review_output }),
   ).await;
   ```

4. **记录助手消息**
   ```rust
   session.record_response_item_and_emit_turn_item(ctx.as_ref(), ResponseItem::Message {
       id: Some("review_rollout_assistant".to_string()),
       role: "assistant".to_string(),
       content: vec![ContentItem::OutputText { text: assistant_message }],
       ...
   }).await;
   ```

5. **确保持久化**
   ```rust
   session.ensure_rollout_materialized().await;
   ```

## 关键代码路径与文件引用

### 调用路径
```
codex.rs:5159-5327 (review)
  → spawn_review_thread
    → spawn_task(Arc<ReviewTask>)
      → tasks/mod.rs:spawn_task
        → review.rs:51-85 (ReviewTask::run)
          → start_review_conversation
          → process_review_events
          → exit_review_mode
```

### 相关文件
- `codex-rs/core/src/tasks/review.rs`：本文件（273行）
- `codex-rs/core/src/codex_delegate.rs`：`run_codex_thread_one_shot`
- `codex-rs/core/src/review_prompts.rs`：`REVIEW_PROMPT`
- `codex-rs/core/src/review_format.rs`：`format_review_findings_block`, `render_review_output_text`
- `codex-rs/core/src/client_common.rs`：`REVIEW_EXIT_SUCCESS_TMPL`, `REVIEW_EXIT_INTERRUPTED_TMPL`

### 依赖类型
- `codex_protocol::protocol::ReviewOutputEvent`：审查输出结构
- `codex_protocol::protocol::ExitedReviewModeEvent`：退出事件
- `codex_protocol::protocol::SubAgentSource::Review`：子代理来源
- `crate::codex_delegate::run_codex_thread_one_shot`：子代理启动

## 依赖与外部交互

### 外部 crate
| Crate | 用途 |
|-------|------|
| `async_trait` | 异步 trait |
| `tokio_util::sync::CancellationToken` | 取消机制 |
| `async_channel` | 事件流通道 |
| `codex_protocol` | 协议类型 |
| `serde_json` | 输出解析 |

### 内部模块
```
review.rs
  ├── uses crate::codex::{Session, TurnContext}
  ├── uses crate::codex_delegate::run_codex_thread_one_shot
  ├── uses crate::config::Constrained
  ├── uses crate::features::Feature
  ├── uses crate::review_format::{format_review_findings_block, render_review_output_text}
  ├── uses crate::state::TaskKind
  └── uses super::{SessionTask, SessionTaskContext}
```

## 风险、边界与改进建议

### 已知风险

1. **JSON 解析脆弱性**
   - 依赖正则式提取 JSON（`find('{')` / `rfind('}')`）
   - 嵌套 JSON 或特殊字符可能导致解析失败
   - 回退到纯文本会丢失结构化数据

2. **事件竞争**
   - `prev_agent_message` 暂存机制可能丢失消息
   - 如果 `TurnComplete` 前没有 `AgentMessage`，不会发送任何消息

3. **子代理失败**
   - 子代理启动失败返回 `None`，用户无感知
   - 建议添加错误提示

### 边界条件

| 场景 | 处理 |
|------|------|
| 取消 | `abort` 调用 `exit_review_mode` 带 `None` |
| 空输出 | `parse_review_output_event` 返回默认结构 |
| 无效 JSON | 尝试提取子串，失败则回退到纯文本 |
| 通道关闭 | 视为中断，返回 `None` |

### 改进建议

1. **鲁棒的 JSON 解析**
   ```rust
   // 使用更可靠的提取方法
   fn extract_json_objects(text: &str) -> Vec<&str> {
       // 使用括号匹配算法
   }
   ```

2. **错误报告**
   ```rust
   // 在 start_review_conversation 失败时通知用户
   if receiver.is_none() {
       session.notify_background_event("Failed to start review agent").await;
   }
   ```

3. **审查进度指示**
   - 添加 `ReviewProgress` 事件
   - 报告正在审查的文件/行数

4. **多轮审查**
   - 支持审查对话（追问、澄清）
   - 保留审查历史

5. **测试覆盖**
   - 当前无专门测试文件
   - 建议添加：
     - 输出解析测试（各种 JSON 格式）
     - 事件过滤测试
     - 取消处理测试
