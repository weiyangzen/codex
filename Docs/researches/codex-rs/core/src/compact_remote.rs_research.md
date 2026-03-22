# compact_remote.rs 深度研究文档

## 场景与职责

`compact_remote.rs` 实现了 Codex 的**远程上下文压缩（Remote Context Compaction）**功能。与 `compact.rs` 的本地压缩不同，远程压缩将历史记录发送到模型提供者的 API 进行压缩，利用专门的压缩端点获得更好的摘要质量。

### 核心场景

1. **OpenAI 远程压缩**: 当使用 OpenAI 提供者时，使用其专门的压缩端点
2. **历史预处理**: 在发送前预处理历史记录，移除不必要的内容
3. **压缩后处理**: 处理远程返回的压缩结果，注入初始上下文

### 与本地压缩的区别

| 特性 | 本地压缩 (compact.rs) | 远程压缩 (compact_remote.rs) |
|------|----------------------|----------------------------|
| 执行位置 | 本地 | 远程 API |
| 摘要质量 | 依赖本地模型 | 依赖远程压缩端点 |
| 网络依赖 | 无 | 需要网络连接 |
| 延迟 | 较低 | 较高（网络往返） |
| 适用提供者 | 所有 | 主要 OpenAI |

## 功能点目的

### 1. 利用专用压缩端点

OpenAI 等提供者可能提供专门的上下文压缩端点：
- 针对压缩任务优化的模型
- 更好的摘要质量
- 保留更多关键信息

### 2. 历史预处理

在发送前清理历史记录：
- 移除函数调用历史以适应上下文窗口
- 保留 Ghost Snapshots 用于撤销功能
- 估算 Token 使用量

### 3. 压缩结果处理

处理远程返回的压缩结果：
- 过滤不必要的消息类型
- 注入当前初始上下文
- 保留压缩项和 Ghost Snapshots

## 具体技术实现

### 提供者检测

```rust
pub(crate) fn should_use_remote_compact_task(provider: &ModelProviderInfo) -> bool {
    provider.is_openai()
}
```

仅对 OpenAI 提供者启用远程压缩。

### 主压缩流程

```rust
pub(crate) async fn run_remote_compact_task(
    sess: Arc<Session>,
    turn_context: Arc<TurnContext>,
) -> CodexResult<()> {
    // 1. 发送回合开始事件
    let start_event = EventMsg::TurnStarted(TurnStartedEvent { ... });
    sess.send_event(&turn_context, start_event).await;
    
    // 2. 执行内部压缩逻辑
    run_remote_compact_task_inner(&sess, &turn_context, InitialContextInjection::DoNotInject).await
}
```

### 内部压缩实现

```rust
async fn run_remote_compact_task_inner_impl(
    sess: &Arc<Session>,
    turn_context: &Arc<TurnContext>,
    initial_context_injection: InitialContextInjection,
) -> CodexResult<()> {
    // 1. 创建压缩项
    let compaction_item = TurnItem::ContextCompaction(ContextCompactionItem::new());
    sess.emit_turn_item_started(turn_context, &compaction_item).await;
    
    // 2. 获取并预处理历史
    let mut history = sess.clone_history().await;
    let base_instructions = sess.get_base_instructions().await;
    let deleted_items = trim_function_call_history_to_fit_context_window(
        &mut history,
        turn_context.as_ref(),
        &base_instructions,
    );
    
    // 3. 保留 Ghost Snapshots
    let ghost_snapshots: Vec<ResponseItem> = history
        .raw_items()
        .iter()
        .filter(|item| matches!(item, ResponseItem::GhostSnapshot { .. }))
        .cloned()
        .collect();
    
    // 4. 构建提示
    let prompt_input = history.for_prompt(&turn_context.model_info.input_modalities);
    let tool_router = built_tools(...).await?;
    let prompt = Prompt {
        input: prompt_input,
        tools: tool_router.model_visible_specs(),
        parallel_tool_calls: turn_context.model_info.supports_parallel_tool_calls,
        base_instructions,
        personality: turn_context.personality,
        output_schema: None,
    };
    
    // 5. 调用远程压缩 API
    let mut new_history = sess
        .services
        .model_client
        .compact_conversation_history(&prompt, ...)
        .or_else(|err| {
            // 错误时记录详细日志
            log_remote_compact_failure(...);
            Err(err)
        })
        .await?;
    
    // 6. 处理压缩结果
    new_history = process_compacted_history(sess, turn_context, new_history, initial_context_injection).await;
    
    // 7. 添加 Ghost Snapshots
    if !ghost_snapshots.is_empty() {
        new_history.extend(ghost_snapshots);
    }
    
    // 8. 替换历史
    let compacted_item = CompactedItem {
        message: String::new(),
        replacement_history: Some(new_history.clone()),
    };
    sess.replace_compacted_history(new_history, reference_context_item, compacted_item).await;
    sess.recompute_token_usage(turn_context).await;
    
    // 9. 发送完成事件
    sess.emit_turn_item_completed(turn_context, compaction_item).await;
    Ok(())
}
```

### 压缩结果处理

```rust
pub(crate) async fn process_compacted_history(
    sess: &Session,
    turn_context: &TurnContext,
    mut compacted_history: Vec<ResponseItem>,
    initial_context_injection: InitialContextInjection,
) -> Vec<ResponseItem> {
    // 1. 获取初始上下文（仅 Mid-turn 压缩）
    let initial_context = if matches!(
        initial_context_injection,
        InitialContextInjection::BeforeLastUserMessage
    ) {
        sess.build_initial_context(turn_context).await
    } else {
        Vec::new()
    };
    
    // 2. 过滤保留项
    compacted_history.retain(should_keep_compacted_history_item);
    
    // 3. 插入初始上下文
    insert_initial_context_before_last_real_user_or_summary(compacted_history, initial_context)
}
```

### 历史项过滤策略

```rust
fn should_keep_compacted_history_item(item: &ResponseItem) -> bool {
    match item {
        // 丢弃 developer 消息（可能包含过时的指令）
        ResponseItem::Message { role, .. } if role == "developer" => false,
        
        // 只保留解析为 UserMessage 的 user 消息
        ResponseItem::Message { role, .. } if role == "user" => {
            matches!(
                crate::event_mapping::parse_turn_item(item),
                Some(TurnItem::UserMessage(_))
            )
        }
        
        // 保留 assistant 消息
        ResponseItem::Message { role, .. } if role == "assistant" => true,
        
        // 保留压缩项
        ResponseItem::Compaction { .. } => true,
        
        // 丢弃其他类型
        _ => false,
    }
}
```

### 函数调用历史修剪

```rust
fn trim_function_call_history_to_fit_context_window(
    history: &mut ContextManager,
    turn_context: &TurnContext,
    base_instructions: &BaseInstructions,
) -> usize {
    let mut deleted_items = 0usize;
    let Some(context_window) = turn_context.model_context_window() else {
        return deleted_items;
    };
    
    // 当估计 Token 数超过窗口时，移除最后的 Codex 生成项
    while history
        .estimate_token_count_with_base_instructions(base_instructions)
        .is_some_and(|estimated| estimated > context_window)
    {
        let Some(last_item) = history.raw_items().last() else {
            break;
        };
        if !is_codex_generated_item(last_item) {
            break;  // 只移除 Codex 生成的项
        }
        if !history.remove_last_item() {
            break;
        }
        deleted_items += 1;
    }
    
    deleted_items
}
```

### 错误日志记录

```rust
fn log_remote_compact_failure(
    turn_context: &TurnContext,
    log_data: &CompactRequestLogData,
    total_usage_breakdown: TotalTokenUsageBreakdown,
    err: &CodexErr,
) {
    error!(
        turn_id = %turn_context.sub_id,
        last_api_response_total_tokens = total_usage_breakdown.last_api_response_total_tokens,
        all_history_items_model_visible_bytes = total_usage_breakdown.all_history_items_model_visible_bytes,
        estimated_tokens_of_items_added_since_last_successful_api_response = total_usage_breakdown.estimated_tokens_of_items_added_since_last_successful_api_response,
        estimated_bytes_of_items_added_since_last_successful_api_response = total_usage_breakdown.estimated_bytes_of_items_added_since_last_successful_api_response,
        model_context_window_tokens = ?turn_context.model_context_window(),
        failing_compaction_request_model_visible_bytes = log_data.failing_compaction_request_model_visible_bytes,
        compact_error = %err,
        "remote compaction failed"
    );
}
```

## 关键代码路径与文件引用

### 调用关系

```
compact_remote.rs
├── Codex::submit (codex.rs) - 根据提供者选择压缩方式
├── run_remote_compact_task - 远程压缩入口
│   └── run_remote_compact_task_inner
│       └── run_remote_compact_task_inner_impl
│           ├── trim_function_call_history_to_fit_context_window
│           ├── compact_conversation_history (ModelClient)
│           └── process_compacted_history
│               └── should_keep_compacted_history_item
└── compact_tests.rs - 单元测试
```

### 依赖模块

| 模块 | 用途 |
|------|------|
| `compact.rs` | `InitialContextInjection`, `insert_initial_context_before_last_real_user_or_summary` |
| `context_manager.rs` | 历史记录管理 |
| `client.rs` | 模型客户端 |

## 依赖与外部交互

### 外部 Crate

| Crate | 用途 |
|-------|------|
| `futures::TryFutureExt` | 异步错误处理 |
| `tokio_util::sync::CancellationToken` | 取消令牌 |
| `tracing` | 日志记录 |

### 协议类型

```rust
use codex_protocol::items::{ContextCompactionItem, TurnItem};
use codex_protocol::models::{BaseInstructions, ResponseItem};
```

## 风险、边界与改进建议

### 当前风险点

1. **网络依赖**: 远程压缩完全依赖网络连接，网络故障时无法回退到本地压缩
2. **API 兼容性**: `compact_conversation_history` 是特定于提供者的扩展，不是所有提供者都支持
3. **数据隐私**: 历史记录发送到远程服务器，可能涉及隐私问题

### 边界情况

1. **压缩失败**: 远程压缩失败时没有自动重试或回退机制
2. **超大历史**: 即使经过修剪，历史仍可能超过远程 API 的限制
3. **并发压缩**: 需要防止多个远程压缩请求同时执行

### 改进建议

1. **回退机制**: 远程压缩失败时自动回退到本地压缩
   ```rust
   match remote_compact(...).await {
       Ok(result) => result,
       Err(e) => {
           warn!("Remote compact failed, falling back to local: {}", e);
           run_inline_auto_compact_task(...).await
       }
   }
   ```

2. **压缩质量评估**: 比较远程和本地压缩的结果质量

3. **增量压缩**: 仅发送新增历史进行压缩，而非整个历史

4. **本地缓存**: 缓存远程压缩结果，避免重复请求

5. **隐私模式**: 添加配置选项，敏感内容不进行远程压缩

### 相关文档

- `compact.rs` - 本地压缩实现
- `compact_tests.rs` - 单元测试
- `client.rs` - 模型客户端
