# turn_timing.rs 研究文档

## 场景与职责

`turn_timing.rs` 是 Codex Core 中负责**回合性能计时**的模块。其核心职责是测量和记录两个关键性能指标：

1. **TTFT (Time To First Token)**：从回合开始到收到第一个 token 的时间
2. **TTFM (Time To First Message)**：从回合开始到收到第一条完整消息的时间

这些指标用于：
- 性能监控和遥测
- 识别模型响应延迟问题
- 优化用户体验

## 功能点目的

### 1. TTFT (Time To First Token)

测量模型开始生成响应的速度。触发条件：
- 收到 `OutputTextDelta` 事件（文本增量）
- 收到 `ReasoningSummaryDelta` 或 `ReasoningContentDelta`（推理增量）
- 收到包含非空内容的 `OutputItemDone`/`OutputItemAdded` 事件

### 2. TTFM (Time To First Message)

测量模型生成第一条完整消息的速度。触发条件：
- 收到 `TurnItem::AgentMessage` 类型的回合项

### 3. 单次记录保证

每个回合的 TTFT 和 TTFM 只记录一次：
- 使用 `Option<Instant>` 标记是否已记录
- 首次记录后，后续事件不再更新

## 具体技术实现

### 核心数据结构

```rust
#[derive(Debug, Default)]
pub(crate) struct TurnTimingState {
    state: Mutex<TurnTimingStateInner>,
}

#[derive(Debug, Default)]
struct TurnTimingStateInner {
    started_at: Option<Instant>,      // 回合开始时间
    first_token_at: Option<Instant>,  // 首次 token 时间
    first_message_at: Option<Instant>, // 首次消息时间
}
```

使用 `Mutex` 保护内部状态，支持异步访问。

### 关键流程

#### 1. 标记回合开始

```rust
pub(crate) async fn mark_turn_started(&self, started_at: Instant) {
    let mut state = self.state.lock().await;
    state.started_at = Some(started_at);
    state.first_token_at = None;    // 重置
    state.first_message_at = None;  // 重置
}
```

每个新回合开始时调用，重置计时状态。

#### 2. 记录 TTFT

```rust
pub(crate) async fn record_ttft_for_response_event(
    &self,
    event: &ResponseEvent,
) -> Option<Duration>
```

流程：
1. 检查事件类型是否应该记录 TTFT（`response_event_records_turn_ttft`）
2. 获取锁
3. 如果 `first_token_at` 已设置，返回 `None`（已记录过）
4. 计算 `started_at` 到当前时间的差值
5. 保存 `first_token_at` 并返回持续时间

#### 3. 记录 TTFM

```rust
pub(crate) async fn record_ttfm_for_turn_item(&self, item: &TurnItem) -> Option<Duration>
```

流程：
1. 检查是否为 `TurnItem::AgentMessage`
2. 获取锁
3. 如果 `first_message_at` 已设置，返回 `None`
4. 计算并返回持续时间

### 事件类型判断

```rust
fn response_event_records_turn_ttft(event: &ResponseEvent) -> bool
```

**记录 TTFT 的事件**：
- `OutputItemDone` / `OutputItemAdded`（包含特定内容类型）
- `OutputTextDelta`
- `ReasoningSummaryDelta`
- `ReasoningContentDelta`

**不记录的事件**：
- `Created`
- `ServerModel`
- `Completed`
- `RateLimits`
- 等元数据事件

### 内容类型判断

```rust
fn response_item_records_turn_ttft(item: &ResponseItem) -> bool
```

| 内容类型 | 记录条件 |
|----------|----------|
| `Message` | 包含非空的 `OutputText` |
| `Reasoning` | 摘要或内容包含非空文本 |
| `FunctionCall` | 总是记录 |
| `CustomToolCall` | 总是记录 |
| `ToolSearchCall` | 总是记录 |
| `WebSearchCall` | 总是记录 |
| `ImageGenerationCall` | 总是记录 |
| `FunctionCallOutput` | 不记录 |

## 关键代码路径与文件引用

### 本文件关键函数

| 函数 | 行号 | 说明 |
|------|------|------|
| `record_turn_ttft_metric` | 14-25 | 公共接口：记录 TTFT 指标 |
| `record_turn_ttfm_metric` | 27-38 | 公共接口：记录 TTFM 指标 |
| `mark_turn_started` | 53-58 | 标记回合开始 |
| `record_ttft_for_response_event` | 60-69 | 处理响应事件并记录 TTFT |
| `record_ttfm_for_turn_item` | 71-77 | 处理回合项并记录 TTFM |
| `response_event_records_turn_ttft` | 102-118 | 判断事件是否应记录 TTFT |
| `response_item_records_turn_ttft` | 120-154 | 判断内容项是否应记录 TTFT |

### 依赖文件

| 文件 | 依赖内容 |
|------|----------|
| `codex_otel::metrics::names` | `TURN_TTFM_DURATION_METRIC`, `TURN_TTFT_DURATION_METRIC` |
| `codex_protocol::items::TurnItem` | 回合项类型 |
| `codex_protocol::models::ResponseItem` | 响应项类型 |
| `stream_events_utils.rs` | `raw_assistant_output_text_from_item` |
| `codex.rs` | `TurnContext` |

### 调用方

- `codex.rs`: 在事件处理循环中调用 `record_turn_ttft_metric` 和 `record_turn_ttfm_metric`
- 通过 `turn_context.turn_timing_state` 访问

## 依赖与外部交互

### 遥测集成

```rust
turn_context
    .session_telemetry
    .record_duration(TURN_TTFT_DURATION_METRIC, duration, &[]);
```

- 使用 OpenTelemetry 风格的指标记录
- 指标名称定义在 `codex_otel` crate

### 并发模型

- 使用 `tokio::sync::Mutex` 保护状态
- 异步锁确保不阻塞执行器线程
- 锁持有时间极短（仅几次字段访问）

## 风险、边界与改进建议

### 风险点

1. **时钟回拨**
   - 使用 `Instant::now()`，不受系统时间回拨影响
   - 但虚拟机挂起/恢复可能导致异常

2. **并发竞争**
   - 虽然使用 Mutex，但多个事件可能同时到达
   - 第一个获取锁的事件获胜，其他被忽略

3. **事件顺序依赖**
   - 假设 `mark_turn_started` 在事件到达前调用
   - 如果顺序错乱，计时可能不准确

### 边界情况

1. **空消息**
   - `AgentMessage` 内容为空时仍记录 TTFM
   - 这是设计选择（消息到达即记录）

2. **推理内容**
   - 推理摘要和文本内容都参与判断
   - 只要任一非空即记录 TTFT

3. **多次标记开始**
   - 重复调用 `mark_turn_started` 会重置计时
   - 可能导致部分事件使用旧时间

### 改进建议

1. **添加更多指标**
   - 可考虑添加 TTFL (Time To First Line)
   - 或 TTLS (Time To Last Token)

2. **细化事件分类**
   - 当前某些事件类型（如工具调用）总是记录
   - 可考虑根据实际内容判断

3. **调试支持**
   - 添加 tracing 日志记录计时事件
   - 便于排查性能问题

4. **测试增强**
   - 添加并发压力测试
   - 验证锁的正确性

### 相关测试

测试文件：`turn_timing_tests.rs`

| 测试 | 说明 |
|------|------|
| `turn_timing_state_records_ttft_only_once_per_turn` | 验证 TTFT 只记录一次 |
| `turn_timing_state_records_ttfm_independently_of_ttft` | 验证 TTFM 独立记录 |
| `response_item_records_turn_ttft_for_first_output_signals` | 验证各类输出信号触发 TTFT |
| `response_item_records_turn_ttft_ignores_empty_non_output_items` | 验证空内容不触发 |
