# 研究文档: `codex-rs/core/tests/suite/compact.rs`

## 1. 场景与职责

### 1.1 文件定位

`compact.rs` 是 Codex 核心库的集成测试套件中的关键测试文件，专注于**上下文压缩（Context Compaction）**功能的端到端测试。该文件位于 `codex-rs/core/tests/suite/` 目录下，是 `suite` 模块的一部分（见 `mod.rs` 第71行）。

### 1.2 核心职责

该测试文件负责验证以下核心场景：

1. **手动压缩（Manual Compact）**: 用户通过 `/compact` 命令主动触发上下文压缩
2. **自动压缩（Auto Compact）**: 当 token 使用量超过配置阈值时自动触发压缩
3. **预采样压缩（Pre-sampling Compact）**: 模型切换时针对较小上下文窗口的压缩
4. **远程压缩（Remote Compact）**: 使用 OpenAI 远程 `/v1/responses/compact` 端点的压缩
5. **压缩恢复（Resume with Compact）**: 会话恢复后的压缩行为

### 1.3 测试架构

测试使用 `wiremock` 模拟 OpenAI API 服务器，通过 SSE（Server-Sent Events）流式响应模拟模型行为。测试框架核心组件：

- `TestCodexBuilder`: 构建测试用的 Codex 实例
- `MockServer`: 模拟 API 服务器
- `ResponseMock`: 捕获和验证请求
- `mount_sse_sequence`: 按顺序挂载 SSE 响应

---

## 2. 功能点目的

### 2.1 上下文压缩的核心价值

在长时间对话中，上下文窗口会被大量历史消息填满，导致：
- Token 成本激增
- 模型性能下降
- 达到上下文窗口上限

**压缩机制**通过将历史对话总结为简洁的摘要，替换原始历史，从而：
- 保留关键信息
- 减少 token 使用量
- 延长有效对话长度

### 2.2 压缩类型对比

| 类型 | 触发方式 | 使用场景 | 关键特征 |
|------|----------|----------|----------|
| **手动压缩** | 用户提交 `Op::Compact` | 用户主动整理上下文 | 完整生命周期事件（TurnStarted/TurnComplete） |
| **自动压缩** | Token 超限自动触发 | 后台静默处理 | 无生命周期事件，对用户透明 |
| **预采样压缩** | 模型切换时触发 | 大模型→小模型切换 | 使用原模型执行压缩 |
| **远程压缩** | OpenAI 端点处理 | OpenAI 官方 provider | 调用 `/v1/responses/compact` |
| **本地压缩** | 本地执行 | 非 OpenAI provider | 本地模型生成摘要 |

### 2.3 关键配置项

```rust
// 自动压缩 token 阈值
config.model_auto_compact_token_limit = Some(200_000);

// 上下文窗口大小
config.model_context_window = Some(100);

// 自定义压缩提示词
config.compact_prompt = Some("自定义摘要提示".to_string());
```

---

## 3. 具体技术实现

### 3.1 核心数据结构

#### 3.1.1 压缩相关事件项

```rust
// codex-rs/protocol/src/items.rs
#[derive(Debug, Clone, Deserialize, Serialize, TS, JsonSchema)]
pub struct ContextCompactionItem {
    pub id: String,
}

#[derive(Serialize, Deserialize, Clone, Debug, JsonSchema, TS)]
pub struct CompactedItem {
    pub message: String,
    pub replacement_history: Option<Vec<ResponseItem>>,
}
```

#### 3.1.2 初始上下文注入策略

```rust
// codex-rs/core/src/compact.rs
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum InitialContextInjection {
    BeforeLastUserMessage,  // 中轮压缩：在最后一个用户消息前注入
    DoNotInject,            // 预轮/手动压缩：不注入，由下一轮重新注入
}
```

### 3.2 关键流程

#### 3.2.1 本地压缩流程 (`compact.rs`)

```rust
pub(crate) async fn run_compact_task_inner(
    sess: Arc<Session>,
    turn_context: Arc<TurnContext>,
    input: Vec<UserInput>,
    initial_context_injection: InitialContextInjection,
) -> CodexResult<()> {
    // 1. 发射压缩开始事件
    let compaction_item = TurnItem::ContextCompaction(ContextCompactionItem::new());
    sess.emit_turn_item_started(&turn_context, &compaction_item).await;
    
    // 2. 构建历史记录并添加压缩提示
    let mut history = sess.clone_history().await;
    history.record_items(&[initial_input_for_turn.into()], turn_context.truncation_policy);
    
    // 3. 流式请求模型生成摘要
    let mut stream = client_session.stream(prompt, ...).await?;
    drain_to_completed(...).await?;
    
    // 4. 提取摘要并构建压缩历史
    let summary_suffix = get_last_assistant_message_from_turn(history_items).unwrap_or_default();
    let summary_text = format!("{SUMMARY_PREFIX}\n{summary_suffix}");
    let mut new_history = build_compacted_history(Vec::new(), &user_messages, &summary_text);
    
    // 5. 根据策略注入初始上下文
    if matches!(initial_context_injection, InitialContextInjection::BeforeLastUserMessage) {
        let initial_context = sess.build_initial_context(turn_context.as_ref()).await;
        new_history = insert_initial_context_before_last_real_user_or_summary(new_history, initial_context);
    }
    
    // 6. 替换历史并持久化
    sess.replace_compacted_history(new_history, reference_context_item, compacted_item).await;
    sess.recompute_token_usage(&turn_context).await;
    
    // 7. 发射完成事件和警告
    sess.emit_turn_item_completed(&turn_context, compaction_item).await;
    sess.send_event(&turn_context, warning).await;
}
```

#### 3.2.2 远程压缩流程 (`compact_remote.rs`)

```rust
async fn run_remote_compact_task_inner_impl(
    sess: &Arc<Session>,
    turn_context: &Arc<TurnContext>,
    initial_context_injection: InitialContextInjection,
) -> CodexResult<()> {
    // 1. 修剪历史以适应上下文窗口
    let deleted_items = trim_function_call_history_to_fit_context_window(...);
    
    // 2. 构建工具路由和提示
    let tool_router = built_tools(...).await?;
    let prompt = Prompt { ... };
    
    // 3. 调用远程压缩端点
    let mut new_history = sess.services.model_client
        .compact_conversation_history(&prompt, ...)
        .await?;
    
    // 4. 处理压缩后的历史
    new_history = process_compacted_history(sess, turn_context, new_history, initial_context_injection).await;
    
    // 5. 替换历史
    sess.replace_compacted_history(new_history, reference_context_item, compacted_item).await;
}
```

#### 3.2.3 压缩历史构建逻辑

```rust
pub(crate) fn build_compacted_history(
    initial_context: Vec<ResponseItem>,
    user_messages: &[String],
    summary_text: &str,
) -> Vec<ResponseItem> {
    // 1. 从用户消息中筛选（排除已存在的摘要消息）
    // 2. 应用 token 限制（默认 20,000 tokens）
    // 3. 添加用户消息到历史
    // 4. 最后添加摘要消息（带 SUMMARY_PREFIX 前缀）
}
```

### 3.3 压缩提示模板

#### 3.3.1 默认压缩提示 (`templates/compact/prompt.md`)

```markdown
You are performing a CONTEXT CHECKPOINT COMPACTION. Create a handoff summary for another LLM that will resume the task.

Include:
- Current progress and key decisions made
- Important context, constraints, or user preferences
- What remains to be done (clear next steps)
- Any critical data, examples, or references needed to continue

Be concise, structured, and focused on helping the next LLM seamlessly continue the work.
```

#### 3.3.2 摘要前缀 (`templates/compact/summary_prefix.md`)

```markdown
Another language model started to solve this problem and produced a summary of its thinking process...
```

### 3.4 关键测试工具函数

```rust
// 测试辅助函数
fn auto_summary(summary: &str) -> String { summary.to_string() }
fn summary_with_prefix(summary: &str) -> String { format!("{SUMMARY_PREFIX}\n{summary}") }
fn set_test_compact_prompt(config: &mut Config) { config.compact_prompt = Some(SUMMARIZATION_PROMPT.to_string()); }
fn body_contains_text(body: &str, text: &str) -> bool { body.contains(&json_fragment(text)) }
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心实现文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/core/src/compact.rs` | 本地压缩核心实现 |
| `codex-rs/core/src/compact_remote.rs` | 远程压缩实现 |
| `codex-rs/core/src/compact_tests.rs` | 压缩模块单元测试 |
| `codex-rs/core/src/tasks/compact.rs` | 压缩任务定义（SessionTask 实现） |
| `codex-rs/protocol/src/items.rs` | `ContextCompactionItem` 定义 |
| `codex-rs/protocol/src/protocol.rs` | `CompactedItem`, `ContextCompactedEvent` 定义 |

### 4.2 测试支持文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/core/tests/suite/compact.rs` | **本文件**：集成测试主文件 |
| `codex-rs/core/tests/suite/compact_remote.rs` | 远程压缩专项测试 |
| `codex-rs/core/tests/suite/compact_resume_fork.rs` | 恢复和分叉场景测试 |
| `codex-rs/core/tests/common/responses.rs` | Mock 响应工具（SSE 构建、请求捕获） |
| `codex-rs/core/tests/common/test_codex.rs` | TestCodexBuilder 测试框架 |

### 4.3 关键代码路径

```
用户提交 Op::Compact
  ↓
codex.rs:4324 O::Compact 处理
  ↓
tasks/compact.rs: CompactTask::run
  ↓
分支:
  ├─ OpenAI provider → compact_remote.rs: run_remote_compact_task
  └─ 其他 provider → compact.rs: run_compact_task
  ↓
构建压缩提示（SUMMARIZATION_PROMPT）
  ↓
流式请求模型生成摘要
  ↓
提取最后一条 assistant 消息作为摘要
  ↓
build_compacted_history 构建新历史
  ↓
replace_compacted_history 替换会话历史
  ↓
持久化到 rollout 文件
  ↓
发射 ItemCompleted 和 Warning 事件
```

---

## 5. 依赖与外部交互

### 5.1 外部 API 依赖

#### 5.1.1 SSE 流式响应端点

```
POST /v1/responses
Content-Type: text/event-stream

事件类型:
- response.created: 响应创建
- response.output_item.done: 输出项完成（包含 assistant 消息）
- response.completed: 响应完成（包含 token 使用量）
- response.failed: 响应失败
```

#### 5.1.2 远程压缩端点（OpenAI）

```
POST /v1/responses/compact
请求体: { "input": [...], "instructions": "..." }
响应体: { "output": [压缩后的 ResponseItem 数组] }
```

### 5.2 内部模块依赖

```rust
// 核心依赖模块
codex_core::compact::{SUMMARIZATION_PROMPT, SUMMARY_PREFIX, ...}
codex_core::config::Config
codex_protocol::items::TurnItem
codex_protocol::protocol::{Op, EventMsg, ItemCompletedEvent, ...}
codex_protocol::user_input::UserInput

// 测试支持模块
core_test_support::responses::{ev_assistant_message, ev_completed, mount_sse_sequence, ...}
core_test_support::test_codex::test_codex
core_test_support::wait_for_event
```

### 5.3 配置依赖

| 配置项 | 说明 |
|--------|------|
| `model_auto_compact_token_limit` | 自动压缩触发阈值 |
| `model_context_window` | 模型上下文窗口大小 |
| `compact_prompt` | 自定义压缩提示词 |
| `model_provider` | 模型提供商配置（决定是否使用远程压缩） |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险与边界

#### 6.1.1 压缩精度损失

**风险**: 长线程和多次压缩可能导致模型准确性下降。

**当前缓解**: 
- 压缩完成后发送警告消息：`"Heads up: Long threads and multiple compactions can cause the model to be less accurate..."`
- 建议用户及时开启新线程

#### 6.1.2 上下文窗口超限处理

**边界情况** (`manual_compact_retries_after_context_window_error` 测试):
- 压缩请求本身可能超出上下文窗口
- 实现采用渐进式修剪：从开头删除最旧的历史项
- 每次重试删除一项，直到适应窗口

```rust
Err(e @ CodexErr::ContextWindowExceeded) => {
    if turn_input_len > 1 {
        history.remove_first_item();  // 删除最旧项
        truncated_count += 1;
        continue;  // 重试
    }
    // 无法进一步修剪，返回错误
}
```

#### 6.1.3 Token 计算限制

**边界** (`COMPACT_USER_MESSAGE_MAX_TOKENS = 20_000`):
- 用户消息在压缩历史中有 token 上限
- 超长消息会被截断并添加 `"... (tokens truncated)"` 标记

#### 6.1.4 模型切换时的压缩

**边界** (`pre_sampling_compact_runs_on_switch_to_smaller_context_model` 测试):
- 大模型→小模型切换时，使用**原模型**执行压缩
- 确保压缩质量不因模型降级而受损

### 6.2 测试覆盖缺口

| 场景 | 状态 | 说明 |
|------|------|------|
| 手动压缩非上下文错误重试 | `#[ignore]` | 已知行为不正确，待后续 PR 修复 |
| 预轮压缩包含传入用户消息 | TODO | 当前行为排除传入消息 |
| 压缩与实时对话交互 | 未覆盖 | 需要额外测试 |

### 6.3 改进建议

#### 6.3.1 压缩质量评估

**建议**: 添加压缩质量指标收集
- 对比压缩前后模型回答一致性
- 收集用户对压缩后体验的反馈
- 基于任务完成率优化压缩提示

#### 6.3.2 智能压缩触发

**建议**: 改进自动压缩触发机制
- 不仅基于 token 数量，还考虑对话复杂度
- 检测关键决策点作为压缩时机
- 支持用户自定义压缩策略

#### 6.3.3 压缩历史可视化

**建议**: 向用户展示压缩摘要
- TUI 中显示已压缩的轮次
- 提供查看压缩摘要的快捷方式
- 允许用户拒绝特定压缩

#### 6.3.4 远程压缩失败回退

**建议**: 远程压缩失败时自动回退到本地压缩
- 当前远程压缩失败会报错
- 可配置回退策略保证服务连续性

#### 6.3.5 增量压缩优化

**建议**: 支持增量压缩而非全量替换
- 保留最近 N 轮完整对话
- 仅压缩更早的历史
- 平衡上下文完整性和 token 效率

### 6.4 监控与可观测性

当前已实现：
- `codex.task.compact` 计数器（区分 local/remote 类型）
- 压缩失败日志（包含 token 使用量、上下文窗口大小等）
- rollout 文件持久化压缩记录

建议增强：
- 压缩前后 token 节省率指标
- 压缩频率和时机分布
- 压缩后用户满意度关联分析

---

## 7. 测试用例速查

| 测试函数 | 验证场景 | 关键断言 |
|----------|----------|----------|
| `summarize_context_three_requests_and_instructions` | 手动压缩基础流程 | 3 个请求，摘要正确插入 |
| `manual_compact_uses_custom_prompt` | 自定义压缩提示 | 使用 config.compact_prompt |
| `auto_compact_runs_after_token_limit_hit` | 自动压缩触发 | token 超限时自动执行 |
| `multiple_auto_compact_per_task_runs_after_token_limit_hit` | 多次自动压缩 | 单轮对话中多次压缩 |
| `pre_sampling_compact_runs_on_switch_to_smaller_context_model` | 模型切换压缩 | 使用原模型执行压缩 |
| `manual_compact_retries_after_context_window_error` | 压缩重试机制 | 删除旧项后重试 |
| `auto_compact_persists_rollout_entries` | 压缩持久化 | rollout 文件包含 Compacted 项 |
| `snapshot_request_shape_mid_turn_continuation_compaction` | 中轮压缩形态 | 使用 insta snapshot 验证 |

---

*文档生成时间: 2026-03-23*
*基于代码版本: codex-rs/core/tests/suite/compact.rs (约 3357 行)*
