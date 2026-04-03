# 研究文档: final_reasoning_then_message_without_deltas_are_rendered.snap

## 场景与职责

该快照文件测试当最终推理内容后跟消息（没有增量更新）时的渲染行为。验证非流式消息的正确处理。

## 功能点目的

1. **非流式渲染**: 处理没有增量更新的完整消息
2. **推理展示**: 显示AI的推理过程
3. **内容一致性**: 确保消息正确显示无重复

## 具体技术实现

### 消息处理

```rust
// 推理事件
AgentReasoningEvent { reasoning: "..." }

// 最终消息（无增量）
AgentMessageEvent { message: "...", phase: Some(MessagePhase::FinalAnswer) }
```

### 渲染逻辑

- 推理内容可能折叠或单独显示
- 最终消息直接显示
- 无增量更新时的特殊处理

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs`
- **消息处理**: `handle_codex_event` 中的消息事件分支

## 改进建议
1. 添加推理内容的展开/折叠功能
2. 区分推理和最终答案的视觉样式
