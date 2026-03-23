# turn_timing_tests.rs 研究文档

## 场景与职责

`turn_timing_tests.rs` 是 `turn_timing.rs` 的配套测试模块，负责验证回合计时功能的正确性。测试覆盖：

1. **TTFT 单次记录**：确保每个回合只记录一次 TTFT
2. **TTFM 独立记录**：确保 TTFM 与 TTFT 独立计算
3. **事件类型判断**：验证不同响应项类型的 TTFT 记录行为

## 功能点目的

### 测试用例设计意图

| 测试函数 | 目的 |
|----------|------|
| `turn_timing_state_records_ttft_only_once_per_turn` | 验证 TTFT 只记录一次，后续事件被忽略 |
| `turn_timing_state_records_ttfm_independently_of_ttft` | 验证 TTFM 和 TTFT 独立记录 |
| `response_item_records_turn_ttft_for_first_output_signals` | 验证各类输出信号应触发 TTFT |
| `response_item_records_turn_ttft_ignores_empty_non_output_items` | 验证空消息和输出项不触发 TTFT |

## 具体技术实现

### 测试 1：TTFT 单次记录

```rust
#[tokio::test]
async fn turn_timing_state_records_ttft_only_once_per_turn()
```

**测试流程**：
1. 创建默认 `TurnTimingState`
2. 未标记开始时，验证返回 `None`
3. 标记回合开始（`mark_turn_started`）
4. 发送 `Created` 事件，验证返回 `None`（不记录）
5. 发送 `OutputTextDelta`，验证返回 `Some(Duration)`
6. 再次发送 `OutputTextDelta`，验证返回 `None`（已记录过）

**关键技术点**：
- 使用 `std::time::Instant::now()` 作为开始时间
- 验证单次记录语义

### 测试 2：TTFM 独立记录

```rust
#[tokio::test]
async fn turn_timing_state_records_ttfm_independently_of_ttft()
```

**测试流程**：
1. 标记回合开始
2. 记录 TTFT（通过 `OutputTextDelta`）
3. 记录 TTFM（通过 `AgentMessage`），验证成功
4. 再次尝试记录 TTFM，验证返回 `None`

**关键技术点**：
- 验证 TTFT 和 TTFM 使用独立的标记位
- 使用 `AgentMessageItem` 构造测试数据

### 测试 3：输出信号触发 TTFT

```rust
#[test]
fn response_item_records_turn_ttft_for_first_output_signals()
```

**测试内容**：
- `FunctionCall`：应触发 TTFT
- `CustomToolCall`：应触发 TTFT
- `Message`（包含 `OutputText`）：应触发 TTFT

**关键技术点**：
- 同步测试（`#[test]`）
- 直接测试 `response_item_records_turn_ttft` 函数
- 使用 `assert!` 验证返回值为 `true`

### 测试 4：忽略空内容

```rust
#[test]
fn response_item_records_turn_ttft_ignores_empty_non_output_items()
```

**测试内容**：
- `Message`（空 `OutputText`）：不触发 TTFT
- `FunctionCallOutput`：不触发 TTFT

**关键技术点**：
- 验证空内容过滤逻辑
- 验证输出项类型过滤逻辑

## 关键代码路径与文件引用

### 被测试代码

| 被测试项 | 定义位置 |
|----------|----------|
| `TurnTimingState::mark_turn_started` | `turn_timing.rs:53` |
| `TurnTimingState::record_ttft_for_response_event` | `turn_timing.rs:60` |
| `TurnTimingState::record_ttfm_for_turn_item` | `turn_timing.rs:71` |
| `response_item_records_turn_ttft` | `turn_timing.rs:120` |

### 测试依赖

| 依赖 | 用途 |
|------|------|
| `codex_protocol::items::AgentMessageItem` | 构造测试消息 |
| `codex_protocol::items::TurnItem` | 回合项类型 |
| `codex_protocol::models::ResponseItem` | 响应项类型 |
| `std::time::Instant` | 计时 |
| `pretty_assertions::assert_eq` | 更好的断言输出 |

## 依赖与外部交互

### 测试数据构造

```rust
AgentMessageItem {
    id: "msg-1".to_string(),
    content: Vec::new(),  // 空内容
    phase: None,
    memory_citation: None,
}
```

测试使用简化的数据结构，不依赖真实协议数据。

### 事件类型

```rust
ResponseEvent::OutputTextDelta("hi".to_string())
ResponseEvent::Created
```

使用简单的字符串构造测试事件。

## 风险、边界与改进建议

### 当前测试覆盖的不足

1. **缺少未标记开始的测试**
   - 应验证未调用 `mark_turn_started` 时的行为

2. **缺少并发测试**
   - 未测试多线程同时访问的情况
   - 未验证锁的正确性

3. **缺少边界时间测试**
   - 未测试极短或极长时间
   - 未测试 `Instant` 溢出（虽然极不可能）

4. **缺少推理内容测试**
   - 未测试 `Reasoning` 类型的 TTFT 判断
   - 未测试 `ReasoningSummaryDelta` 事件

5. **缺少遥测集成测试**
   - 未验证指标是否正确发送到遥测系统

### 改进建议

1. **添加未标记开始测试**
```rust
#[tokio::test]
async fn returns_none_when_turn_not_started() {
    let state = TurnTimingState::default();
    assert_eq!(
        state.record_ttft_for_response_event(&ResponseEvent::OutputTextDelta("hi".to_string())).await,
        None
    );
}
```

2. **添加并发测试**
```rust
#[tokio::test]
async fn concurrent_events_record_only_one_ttft() {
    // 启动多个任务同时发送事件
    // 验证只记录一次
}
```

3. **添加推理内容测试**
```rust
#[test]
fn reasoning_with_content_triggers_ttft() {
    // 测试 Reasoning 类型的判断逻辑
}
```

4. **添加遥测验证**
   - 使用 mock 验证 `session_telemetry.record_duration` 被调用

### 潜在风险

1. **测试与实现耦合**
   - 测试直接依赖 `ResponseItem` 和 `TurnItem` 的结构
   - 如果协议变更，测试需要同步更新

2. **时间敏感性**
   - 测试使用真实时间，虽然极短
   - 在极端负载下可能不稳定

3. **异步复杂性**
   - `#[tokio::test]` 引入异步运行时
   - 增加了测试的复杂性

### 测试质量评估

| 维度 | 评分 | 说明 |
|------|------|------|
| 覆盖率 | 中 | 基本路径覆盖，缺少边界和并发 |
| 可读性 | 高 | 测试意图清晰，命名良好 |
| 维护性 | 高 | 结构简单，易于修改 |
| 可靠性 | 高 | 不依赖外部系统 |
