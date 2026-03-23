# compact_remote.rs 研究文档

## 概述

`compact_remote.rs` 是 Codex Core 测试套件中的关键测试文件，专注于**远程上下文压缩（Remote Context Compaction）**功能的端到端测试。该文件包含 30+ 个集成测试用例，验证当使用 OpenAI 远程压缩端点（`/v1/responses/compact`）时的完整行为链。

---

## 1. 场景与职责

### 1.1 核心场景

| 场景 | 描述 |
|------|------|
| **Remote Compaction** | 使用远程 API 端点压缩对话历史，而非本地模型生成摘要 |
| **Auto-compaction** | 当 token 使用超过阈值时自动触发压缩 |
| **Manual compaction** | 用户通过 `/compact` 命令手动触发压缩 |
| **Pre-turn compaction** | 在模型采样前执行压缩（回合开始前） |
| **Mid-turn compaction** | 在回合中间（如工具调用后）执行压缩 |
| **Realtime integration** | 与实时对话（WebSocket）模式下的压缩行为 |
| **Resume after compaction** | 从压缩后的状态恢复会话 |

### 1.2 测试文件职责

1. **验证远程压缩端点调用**：确保正确调用 `/v1/responses/compact`
2. **验证压缩后历史重建**：确认压缩后的对话历史正确重建
3. **验证 Realtime 模式集成**：测试实时对话状态下的压缩行为
4. **验证错误处理**：测试远程压缩失败时的降级行为
5. **验证 Token 估算**：确保压缩前的 token 估算准确
6. **验证 Function Call 修剪**：测试超出上下文窗口时的函数调用历史修剪

---

## 2. 功能点目的

### 2.1 远程压缩 vs 本地压缩

```rust
// codex-rs/core/src/tasks/compact.rs
if crate::compact::should_use_remote_compact_task(&ctx.provider) {
    // 使用远程压缩（OpenAI 提供商）
    crate::compact_remote::run_remote_compact_task(session.clone(), ctx).await
} else {
    // 使用本地压缩（其他提供商）
    crate::compact::run_compact_task(session.clone(), ctx, input).await
}
```

远程压缩的优势：
- 由专门的压缩模型处理，质量更高
- 减少客户端计算负担
- 支持更复杂的压缩策略

### 2.2 关键功能点

| 功能 | 目的 | 测试覆盖 |
|------|------|----------|
| `remote_compact_replaces_history_for_followups` | 验证压缩后历史被正确替换 | ✅ |
| `remote_compact_runs_automatically` | 验证自动压缩触发机制 | ✅ |
| `remote_compact_trims_function_call_history` | 验证函数调用历史修剪 | ✅ |
| `auto_remote_compact_failure_stops_agent_loop` | 验证压缩失败时停止代理循环 | ✅ |
| `remote_compact_and_resume_refresh_stale_developer_instructions` | 验证恢复时刷新过时的开发者指令 | ✅ |
| `snapshot_request_shape_*` | 验证请求形状的快照测试 | ✅ 多个测试 |

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 远程压缩执行流程

```rust
// codex-rs/core/src/compact_remote.rs
pub(crate) async fn run_remote_compact_task_inner_impl(
    sess: &Arc<Session>,
    turn_context: &Arc<TurnContext>,
    initial_context_injection: InitialContextInjection,
) -> CodexResult<()> {
    // 1. 创建压缩项目并发送开始事件
    let compaction_item = TurnItem::ContextCompaction(ContextCompactionItem::new());
    sess.emit_turn_item_started(turn_context, &compaction_item).await;
    
    // 2. 克隆历史记录
    let mut history = sess.clone_history().await;
    let base_instructions = sess.get_base_instructions().await;
    
    // 3. 修剪函数调用历史以适应上下文窗口
    let deleted_items = trim_function_call_history_to_fit_context_window(
        &mut history,
        turn_context.as_ref(),
        &base_instructions,
    );
    
    // 4. 准备提示词输入
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
    
    // 5. 调用远程压缩端点
    let mut new_history = sess
        .services
        .model_client
        .compact_conversation_history(
            &prompt,
            &turn_context.model_info,
            turn_context.reasoning_effort,
            turn_context.reasoning_summary,
            &turn_context.session_telemetry,
        )
        .await?;
    
    // 6. 处理压缩后的历史
    new_history = process_compacted_history(
        sess.as_ref(),
        turn_context.as_ref(),
        new_history,
        initial_context_injection,
    )
    .await;
    
    // 7. 替换历史并重新计算 token 使用
    sess.replace_compacted_history(new_history, reference_context_item, compacted_item)
        .await;
    sess.recompute_token_usage(turn_context).await;
    
    // 8. 发送完成事件
    sess.emit_turn_item_completed(turn_context, compaction_item).await;
    Ok(())
}
```

#### 3.1.2 压缩后历史处理流程

```rust
pub(crate) async fn process_compacted_history(
    sess: &Session,
    turn_context: &TurnContext,
    mut compacted_history: Vec<ResponseItem>,
    initial_context_injection: InitialContextInjection,
) -> Vec<ResponseItem> {
    // 1. 决定是否需要注入初始上下文
    let initial_context = if matches!(
        initial_context_injection,
        InitialContextInjection::BeforeLastUserMessage
    ) {
        sess.build_initial_context(turn_context).await
    } else {
        Vec::new()
    };
    
    // 2. 过滤保留的压缩历史项目
    compacted_history.retain(should_keep_compacted_history_item);
    
    // 3. 在最后一个真实用户消息或摘要前插入初始上下文
    insert_initial_context_before_last_real_user_or_summary(compacted_history, initial_context)
}
```

### 3.2 关键数据结构

#### 3.2.1 ResponseItem（协议层）

```rust
// codex-protocol 中的核心数据结构
pub enum ResponseItem {
    Message {
        id: Option<String>,
        role: String,  // "user", "assistant", "developer"
        content: Vec<ContentItem>,
        end_turn: Option<bool>,
        phase: Option<String>,
    },
    Compaction {
        encrypted_content: String,  // 压缩后的加密摘要
    },
    FunctionCall {
        call_id: String,
        name: String,
        arguments: String,
    },
    FunctionCallOutput {
        call_id: String,
        output: FunctionCallOutputPayload,
    },
    // ... 其他变体
}
```

#### 3.2.2 ContextManager（历史管理）

```rust
// codex-rs/core/src/context_manager/history.rs
pub(crate) struct ContextManager {
    /// 历史项目，最旧的在向量开头
    items: Vec<ResponseItem>,
    token_info: Option<TokenUsageInfo>,
    /// 参考上下文快照，用于差异计算
    reference_context_item: Option<TurnContextItem>,
}
```

#### 3.2.3 InitialContextInjection（上下文注入策略）

```rust
// codex-rs/core/src/compact.rs
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum InitialContextInjection {
    /// 在最后一个用户消息前注入（用于 mid-turn 压缩）
    BeforeLastUserMessage,
    /// 不注入（用于 pre-turn/manual 压缩）
    DoNotInject,
}
```

### 3.3 协议与 API

#### 3.3.1 远程压缩端点

```rust
// codex-rs/core/src/client.rs
const RESPONSES_COMPACT_ENDPOINT: &str = "/responses/compact";

pub async fn compact_conversation_history(
    &self,
    prompt: &Prompt,
    model_info: &ModelInfo,
    effort: Option<ReasoningEffortConfig>,
    summary: ReasoningSummaryConfig,
    session_telemetry: &SessionTelemetry,
) -> Result<Vec<ResponseItem>> {
    // 构建压缩请求
    let compaction_input = ApiCompactionInput {
        model: &model_info.slug,
        input: &prompt.input,
        instructions: &prompt.base_instructions.text,
        tools: &tools_json,
        parallel_tool_calls: prompt.parallel_tool_calls,
        reasoning,
        text,
    };
    
    // 调用 API
    let response = compact_client.compact(compaction_input).await?;
    Ok(response.output)
}
```

#### 3.3.2 请求/响应格式

**请求格式**（发送到 `/v1/responses/compact`）：
```json
{
  "model": "gpt-5.1-codex",
  "input": [
    {"type": "message", "role": "developer", "content": [...]},
    {"type": "message", "role": "user", "content": [...]},
    {"type": "message", "role": "assistant", "content": [...]},
    {"type": "function_call", "call_id": "...", "name": "...", "arguments": "..."},
    {"type": "function_call_output", "call_id": "...", "output": "..."}
  ],
  "instructions": "...",
  "tools": [...],
  "parallel_tool_calls": true,
  "reasoning": {...},
  "text": {...}
}
```

**响应格式**：
```json
{
  "output": [
    {"type": "compaction", "encrypted_content": "..."},
    {"type": "message", "role": "user", "content": [...]}
  ]
}
```

### 3.4 测试辅助函数

#### 3.4.1 Token 估算

```rust
// compact_remote.rs 中的辅助函数
fn approx_token_count(text: &str) -> i64 {
    i64::try_from(text.len().saturating_add(3) / 4).unwrap_or(i64::MAX)
}

fn estimate_compact_input_tokens(request: &responses::ResponsesRequest) -> i64 {
    request.input().into_iter().fold(0i64, |acc, item| {
        acc.saturating_add(approx_token_count(&item.to_string()))
    })
}
```

#### 3.4.2 Realtime 测试服务器

```rust
async fn start_remote_realtime_server() -> responses::WebSocketTestServer {
    start_websocket_server(vec![vec![
        vec![json!({
            "type": "session.updated",
            "session": { "id": "sess_remote_compact", "instructions": "backend prompt" }
        })],
        vec![], // 保持 WebSocket 打开状态
        vec![],
        // ...
    ]])
    .await
}
```

#### 3.4.3 压缩 Mock 响应

```rust
// 使用 wiremock 模拟远程压缩端点
let compact_mock = responses::mount_compact_json_once(
    harness.server(),
    serde_json::json!({ 
        "output": vec![ResponseItem::Compaction {
            encrypted_content: "ENCRYPTED_COMPACTION_SUMMARY".to_string(),
        }]
    }),
).await;

// 或使用智能 mock 保留 user/developer 消息
let compact_mock = responses::mount_compact_user_history_with_summary_once(
    harness.server(),
    "REMOTE_COMPACTED_SUMMARY",
).await;
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心实现文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/core/src/compact_remote.rs` | 远程压缩任务的核心实现 |
| `codex-rs/core/src/compact.rs` | 本地压缩实现，共享 InitialContextInjection 等类型 |
| `codex-rs/core/src/tasks/compact.rs` | 压缩任务的分发（本地 vs 远程） |
| `codex-rs/core/src/client.rs` | ModelClient，包含 `compact_conversation_history` 方法 |
| `codex-rs/core/src/context_manager/history.rs` | ContextManager，管理对话历史 |

### 4.2 测试支持文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/core/tests/suite/compact_remote.rs` | 本研究文档的目标测试文件 |
| `codex-rs/core/tests/suite/compact.rs` | 本地压缩测试 |
| `codex-rs/core/tests/common/responses.rs` | Mock 响应服务器和辅助函数 |
| `codex-rs/core/tests/common/test_codex.rs` | TestCodexBuilder 和测试基础设施 |
| `codex-rs/core/tests/common/context_snapshot.rs` | 请求快照格式化工具 |

### 4.3 关键代码路径

```
用户触发压缩
    ↓
codex-rs/core/src/tasks/compact.rs::CompactTask::run()
    ↓
crate::compact::should_use_remote_compact_task(&ctx.provider) ?
    ↓ 是
codex-rs/core/src/compact_remote.rs::run_remote_compact_task()
    ↓
run_remote_compact_task_inner_impl()
    ├── 1. emit_turn_item_started()
    ├── 2. clone_history()
    ├── 3. trim_function_call_history_to_fit_context_window()
    ├── 4. built_tools() + Prompt 构建
    ├── 5. model_client.compact_conversation_history()
    │       ↓
    │   codex-rs/core/src/client.rs::compact_conversation_history()
    │       ↓
    │   POST /v1/responses/compact
    ├── 6. process_compacted_history()
    │       ├── should_keep_compacted_history_item() 过滤
    │       └── insert_initial_context_before_last_real_user_or_summary()
    ├── 7. replace_compacted_history()
    └── 8. emit_turn_item_completed()
```

---

## 5. 依赖与外部交互

### 5.1 外部依赖

| 依赖 | 用途 |
|------|------|
| `wiremock` | HTTP Mock 服务器，模拟远程 API |
| `tokio-tungstenite` | WebSocket 服务器，用于 Realtime 测试 |
| `insta` | 快照测试框架 |
| `pretty_assertions` | 更好的断言输出 |
| `serde_json` | JSON 序列化/反序列化 |

### 5.2 内部模块依赖

```rust
// compact_remote.rs 的导入
use codex_core::compact::SUMMARY_PREFIX;
use codex_protocol::items::TurnItem;
use codex_protocol::models::ContentItem;
use codex_protocol::models::ResponseItem;
use codex_protocol::protocol::{ConversationStartParams, ErrorEvent, EventMsg, ...};
use core_test_support::context_snapshot;
use core_test_support::responses;
use core_test_support::test_codex::{TestCodexBuilder, TestCodexHarness, test_codex};
```

### 5.3 外部 API 交互

| 端点 | 方法 | 用途 |
|------|------|------|
| `/v1/responses` | POST | 正常的模型响应请求 |
| `/v1/responses/compact` | POST | 远程压缩请求 |
| `/v1/models` | GET | 获取可用模型列表 |

### 5.4 测试基础设施

**TestCodexHarness**：提供便捷的测试设置
```rust
let harness = TestCodexHarness::with_builder(
    test_codex()
        .with_auth(CodexAuth::create_dummy_chatgpt_auth_for_testing())
        .with_config(|config| {
            config.model_auto_compact_token_limit = Some(200);
        }),
)
.await?;
```

**ResponseMock**：捕获和验证请求
```rust
let compact_mock = responses::mount_compact_json_once(...).await;
let request = compact_mock.single_request();
assert_eq!(request.path(), "/v1/responses/compact");
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **网络依赖** | 远程压缩需要网络连接 | 使用 `skip_if_no_network!` 宏跳过无网络测试 |
| **API 兼容性** | 远程端点格式变更可能导致解析失败 | 使用 serde 的容错反序列化，版本控制 |
| **Token 估算不准确** | 本地 token 估算可能与服务器不一致 | 使用保守估算，预留安全边距 |
| **压缩失败** | 远程压缩可能失败 | 错误处理，停止代理循环防止状态损坏 |

### 6.2 边界情况

1. **空历史压缩**：`remote_manual_compact_without_previous_user_messages` 测试验证无用户消息时不应调用远程压缩

2. **上下文窗口超限**：`remote_pre_turn_compaction_context_window_exceeded` 测试验证 400 错误处理

3. **Realtime 状态变化**：多个测试验证 Realtime 会话在压缩后的正确状态恢复

4. **模型切换时的压缩**：`remote_pre_turn_compaction_strips_incoming_model_switch` 测试验证模型切换标记的处理

5. **Function Call 修剪**：当历史超过上下文窗口时，需要正确修剪函数调用对

### 6.3 改进建议

#### 6.3.1 测试覆盖

| 建议 | 优先级 | 说明 |
|------|--------|------|
| 增加并发压缩测试 | 中 | 验证多个压缩请求并发时的行为 |
| 增加压缩取消测试 | 中 | 验证压缩任务取消时的清理 |
| 增加长时间运行测试 | 低 | 验证多次压缩后的历史一致性 |

#### 6.3.2 代码改进

| 建议 | 优先级 | 说明 |
|------|--------|------|
| 压缩结果缓存 | 低 | 对相同历史缓存压缩结果 |
| 渐进式压缩 | 中 | 支持部分历史压缩而非全部 |
| 压缩质量指标 | 低 | 添加压缩质量评估指标 |

#### 6.3.3 可观测性

```rust
// 当前已有日志记录
info!(
    turn_id = %turn_context.sub_id,
    deleted_items,
    "trimmed history items before remote compaction"
);

error!(
    turn_id = %turn_context.sub_id,
    last_api_response_total_tokens = ...,
    failing_compaction_request_model_visible_bytes = ...,
    compact_error = %err,
    "remote compaction failed"
);
```

建议增加：
- 压缩延迟指标（P50, P95, P99）
- 压缩率指标（压缩前后 token 数对比）
- 压缩失败率监控

### 6.4 技术债务

1. **TODO 标记**：
   - `remote_compact_persists_replacement_history_in_rollout` 被标记为 `#[ignore]`，等待后续 PR 修复
   - `snapshot_request_shape_remote_pre_turn_compaction_including_incoming_user_message` 有 TODO 注释

2. **Windows 测试限制**：
   - 部分测试使用 `#[cfg_attr(target_os = "windows", ignore)]` 跳过 Windows 平台

3. **快照维护**：
   - 28 个快照文件需要随代码变更同步更新
   - 使用 `cargo insta accept` 接受变更

---

## 7. 附录

### 7.1 测试列表

| 测试名称 | 描述 |
|----------|------|
| `remote_compact_replaces_history_for_followups` | 验证压缩后历史替换 |
| `remote_compact_runs_automatically` | 验证自动压缩 |
| `remote_compact_trims_function_call_history_to_fit_context_window` | 验证函数调用修剪 |
| `auto_remote_compact_trims_function_call_history_to_fit_context_window` | 验证自动压缩时的修剪 |
| `auto_remote_compact_failure_stops_agent_loop` | 验证失败时停止代理 |
| `remote_compact_trim_estimate_uses_session_base_instructions` | 验证 token 估算使用 base instructions |
| `remote_manual_compact_emits_context_compaction_items` | 验证压缩项目事件 |
| `remote_manual_compact_failure_emits_task_error_event` | 验证失败事件 |
| `remote_compact_persists_replacement_history_in_rollout` | 验证 rollout 持久化（被忽略） |
| `remote_compact_and_resume_refresh_stale_developer_instructions` | 验证恢复时刷新指令 |
| `remote_compact_refreshes_stale_developer_instructions_without_resume` | 验证即时刷新指令 |
| `snapshot_request_shape_remote_pre_turn_compaction_restates_realtime_start` | 快照：pre-turn 压缩 restate realtime start |
| `remote_request_uses_custom_experimental_realtime_start_instructions` | 验证自定义 realtime 指令 |
| `snapshot_request_shape_remote_pre_turn_compaction_restates_realtime_end` | 快照：pre-turn 压缩 restate realtime end |
| `snapshot_request_shape_remote_manual_compact_restates_realtime_start` | 快照：manual 压缩 restate realtime start |
| `snapshot_request_shape_remote_mid_turn_compaction_does_not_restate_realtime_end` | 快照：mid-turn 压缩不 restate realtime end |
| `snapshot_request_shape_remote_compact_resume_restates_realtime_end` | 快照：恢复后压缩 restate realtime end |
| `snapshot_request_shape_remote_pre_turn_compaction_including_incoming_user_message` | 快照：包含 incoming user message |
| `snapshot_request_shape_remote_pre_turn_compaction_strips_incoming_model_switch` | 快照：剥离 model switch |
| `snapshot_request_shape_remote_pre_turn_compaction_context_window_exceeded` | 快照：上下文窗口超限 |
| `snapshot_request_shape_remote_mid_turn_continuation_compaction` | 快照：mid-turn 延续压缩 |
| `snapshot_request_shape_remote_mid_turn_compaction_summary_only_reinjects_context` | 快照：仅摘要时重新注入上下文 |
| `snapshot_request_shape_remote_mid_turn_compaction_multi_summary_reinjects_above_last_summary` | 快照：多摘要时重新注入位置 |
| `snapshot_request_shape_remote_manual_compact_without_previous_user_messages` | 快照：无先前用户消息 |

### 7.2 相关配置项

```rust
// Config 中与远程压缩相关的配置
pub struct Config {
    pub model_auto_compact_token_limit: Option<i64>,  // 自动压缩阈值
    pub model_context_window: Option<i64>,            // 上下文窗口大小
    pub base_instructions: Option<String>,            // 基础指令
    pub experimental_realtime_ws_base_url: Option<String>, // Realtime WebSocket URL
    pub experimental_realtime_start_instructions: Option<String>, // 自定义 realtime 启动指令
}
```

### 7.3 参考资料

- [OpenAI Responses API 文档](https://platform.openai.com/docs/api-reference/responses)
- [Codex AGENTS.md](../AGENTS.md) - 项目级代理指南
- [insta 快照测试文档](https://insta.rs/docs/)
