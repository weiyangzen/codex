# compact.rs 深度研究文档

## 场景与职责

`compact.rs` 实现了 Codex 的**上下文压缩（Context Compaction）**功能，用于解决长对话导致的上下文窗口溢出问题。当对话历史超过模型上下文窗口限制时，该模块通过生成摘要来替换详细历史，同时保留关键信息。

### 核心场景

1. **自动压缩**: 当上下文接近窗口限制时自动触发
2. **手动压缩**: 用户主动请求压缩历史
3. **回合内压缩**: 在模型生成过程中进行压缩（Mid-turn）
4. **回合间压缩**: 在回合边界进行压缩（Pre-turn）

### 职责边界

- 管理压缩任务的生命周期
- 处理压缩过程中的错误和重试
- 维护压缩后的历史记录结构
- 保留用户消息和关键上下文

## 功能点目的

### 1. 上下文窗口管理

防止对话历史超过模型上下文窗口限制：
- 监控 Token 使用量
- 在溢出前主动压缩
- 优雅处理溢出错误

### 2. 信息保留策略

压缩时保留：
- 用户消息（去重和截断）
- 助手生成的摘要
- 工具调用结果的关键信息
- Ghost Snapshots（用于撤销功能）

### 3. 透明用户体验

- 压缩过程对用户透明
- 保留足够上下文保持对话连贯性
- 压缩后发送警告提示用户

## 具体技术实现

### 核心常量

```rust
/// 压缩提示模板路径
pub const SUMMARIZATION_PROMPT: &str = include_str!("../templates/compact/prompt.md");

/// 摘要前缀，用于标识压缩消息
pub const SUMMARY_PREFIX: &str = include_str!("../templates/compact/summary_prefix.md");

/// 用户消息最大 Token 限制
const COMPACT_USER_MESSAGE_MAX_TOKENS: usize = 20_000;
```

### 初始上下文注入策略

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum InitialContextInjection {
    /// 在最后一个用户消息前注入初始上下文
    /// 用于 Mid-turn 压缩，保持压缩项在最后
    BeforeLastUserMessage,
    /// 不注入初始上下文
    /// 用于 Pre-turn 压缩，后续回合会重新注入
    DoNotInject,
}
```

### 主压缩流程

```rust
pub(crate) async fn run_compact_task(
    sess: Arc<Session>,
    turn_context: Arc<TurnContext>,
    input: Vec<UserInput>,
) -> CodexResult<()> {
    // 1. 发送回合开始事件
    let start_event = EventMsg::TurnStarted(TurnStartedEvent { ... });
    sess.send_event(&turn_context, start_event).await;
    
    // 2. 执行内部压缩逻辑
    run_compact_task_inner(sess.clone(), turn_context, input, InitialContextInjection::DoNotInject).await
}
```

### 压缩内部逻辑

```rust
async fn run_compact_task_inner(
    sess: Arc<Session>,
    turn_context: Arc<TurnContext>,
    input: Vec<UserInput>,
    initial_context_injection: InitialContextInjection,
) -> CodexResult<()> {
    // 1. 创建压缩项并发送开始事件
    let compaction_item = TurnItem::ContextCompaction(ContextCompactionItem::new());
    sess.emit_turn_item_started(&turn_context, &compaction_item).await;
    
    // 2. 准备历史记录
    let mut history = sess.clone_history().await;
    history.record_items(&[initial_input_for_turn.into()], turn_context.truncation_policy);
    
    // 3. 带重试的流式处理循环
    loop {
        let turn_input = history.clone().for_prompt(&turn_context.model_info.input_modalities);
        let prompt = Prompt {
            input: turn_input,
            base_instructions: sess.get_base_instructions().await,
            personality: turn_context.personality,
            ..Default::default()
        };
        
        match drain_to_completed(...).await {
            Ok(()) => break,  // 压缩成功
            Err(CodexErr::ContextWindowExceeded) => {
                // 上下文溢出，移除最旧的历史项并重试
                history.remove_first_item();
                truncated_count += 1;
            }
            Err(e) if retries < max_retries => {
                // 可重试错误，等待后重试
                tokio::time::sleep(backoff(retries)).await;
            }
            Err(e) => return Err(e),  // 不可恢复错误
        }
    }
    
    // 4. 构建压缩后的历史
    let summary_text = format!("{SUMMARY_PREFIX}\n{summary_suffix}");
    let user_messages = collect_user_messages(history_items);
    let mut new_history = build_compacted_history(Vec::new(), &user_messages, &summary_text);
    
    // 5. 根据需要注入初始上下文
    if matches!(initial_context_injection, InitialContextInjection::BeforeLastUserMessage) {
        let initial_context = sess.build_initial_context(turn_context.as_ref()).await;
        new_history = insert_initial_context_before_last_real_user_or_summary(new_history, initial_context);
    }
    
    // 6. 保留 Ghost Snapshots
    let ghost_snapshots: Vec<ResponseItem> = history_items
        .iter()
        .filter(|item| matches!(item, ResponseItem::GhostSnapshot { .. }))
        .cloned()
        .collect();
    new_history.extend(ghost_snapshots);
    
    // 7. 替换历史并发送完成事件
    sess.replace_compacted_history(new_history, reference_context_item, compacted_item).await;
    sess.emit_turn_item_completed(&turn_context, compaction_item).await;
    
    // 8. 发送压缩警告
    let warning = EventMsg::Warning(WarningEvent {
        message: "Heads up: Long threads and multiple compactions can cause the model to be less accurate...".to_string(),
    });
    sess.send_event(&turn_context, warning).await;
}
```

### 流式响应处理

```rust
async fn drain_to_completed(
    sess: &Session,
    turn_context: &TurnContext,
    client_session: &mut ModelClientSession,
    turn_metadata_header: Option<&str>,
    prompt: &Prompt,
) -> CodexResult<()> {
    let mut stream = client_session.stream(...).await?;
    loop {
        match stream.next().await {
            Some(Ok(ResponseEvent::OutputItemDone(item))) => {
                sess.record_into_history(std::slice::from_ref(&item), turn_context).await;
            }
            Some(Ok(ResponseEvent::Completed { token_usage, .. })) => {
                sess.update_token_usage_info(turn_context, token_usage.as_ref()).await;
                return Ok(());
            }
            Some(Err(e)) => return Err(e),
            None => return Err(CodexErr::Stream("stream closed before response.completed".into(), None)),
        }
    }
}
```

### 用户消息收集

```rust
pub(crate) fn collect_user_messages(items: &[ResponseItem]) -> Vec<String> {
    items
        .iter()
        .filter_map(|item| match crate::event_mapping::parse_turn_item(item) {
            Some(TurnItem::UserMessage(user)) => {
                if is_summary_message(&user.message()) {
                    None  // 排除之前的摘要消息
                } else {
                    Some(user.message())
                }
            }
            _ => None,
        })
        .collect()
}
```

### 初始上下文插入

```rust
pub(crate) fn insert_initial_context_before_last_real_user_or_summary(
    mut compacted_history: Vec<ResponseItem>,
    initial_context: Vec<ResponseItem>,
) -> Vec<ResponseItem> {
    // 查找插入位置：最后一个真实用户消息前
    let mut last_user_or_summary_index = None;
    let mut last_real_user_index = None;
    
    for (i, item) in compacted_history.iter().enumerate().rev() {
        if let Some(TurnItem::UserMessage(user)) = crate::event_mapping::parse_turn_item(item) {
            last_user_or_summary_index.get_or_insert(i);
            if !is_summary_message(&user.message()) {
                last_real_user_index = Some(i);
                break;
            }
        }
    }
    
    let insertion_index = last_real_user_index
        .or(last_user_or_summary_index)
        .or(last_compaction_index);
    
    // 执行插入
    if let Some(insertion_index) = insertion_index {
        compacted_history.splice(insertion_index..insertion_index, initial_context);
    } else {
        compacted_history.extend(initial_context);
    }
    
    compacted_history
}
```

## 关键代码路径与文件引用

### 调用关系

```
compact.rs
├── Codex::submit (codex.rs) - 触发压缩检查
├── run_compact_task - 手动/自动压缩入口
│   └── run_compact_task_inner
│       ├── drain_to_completed - 流式处理
│       ├── build_compacted_history - 构建新历史
│       └── insert_initial_context_before_last_real_user_or_summary
├── compact_remote.rs - 远程压缩实现
└── compact_tests.rs - 单元测试
```

### 依赖模块

| 模块 | 用途 |
|------|------|
| `client.rs` | 模型客户端 |
| `context_manager.rs` | 历史记录管理 |
| `truncate.rs` | Token 截断 |
| `event_mapping.rs` | 事件解析 |

### 模板文件

| 文件 | 用途 |
|------|------|
| `templates/compact/prompt.md` | 压缩提示模板 |
| `templates/compact/summary_prefix.md` | 摘要前缀 |

## 依赖与外部交互

### 外部 Crate

| Crate | 用途 |
|-------|------|
| `futures` | 异步流处理 |
| `tokio::sync::Mutex` | 异步互斥锁 |
| `tracing` | 日志记录 |

### 协议类型

```rust
use codex_protocol::items::{ContextCompactionItem, TurnItem};
use codex_protocol::models::{ContentItem, ResponseInputItem, ResponseItem};
use codex_protocol::user_input::UserInput;
```

## 风险、边界与改进建议

### 当前风险点

1. **Token 估算不准确**: 使用 `approx_token_count` 进行估算，可能与实际 Token 数有偏差
2. **压缩质量依赖模型**: 摘要质量取决于模型能力，可能丢失关键信息
3. **无限循环风险**: 如果单个历史项就超过上下文窗口，无法通过移除项目解决

### 边界情况

1. **空历史**: 压缩空历史会产生仅包含摘要的历史
2. **全摘要历史**: 如果所有用户消息都是之前的摘要，可能丢失原始用户意图
3. **并发压缩**: 需要防止多个压缩任务同时执行

### 改进建议

1. **智能摘要**: 使用更智能的摘要策略，保留关键决策点和用户偏好
2. **压缩历史可视化**: 允许用户查看压缩前后的历史对比
3. **增量压缩**: 仅压缩新增部分，而非整个历史
4. **压缩质量评估**: 添加压缩质量指标，评估信息保留程度
5. **用户控制**: 允许用户配置压缩触发阈值和行为

### 相关文档

- `compact_remote.rs` - 远程压缩实现
- `compact_tests.rs` - 单元测试
- `templates/compact/prompt.md` - 压缩提示模板
