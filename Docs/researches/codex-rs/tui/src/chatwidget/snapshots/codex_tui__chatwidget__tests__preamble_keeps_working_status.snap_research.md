# 研究文档: preamble_keeps_working_status.snap

## 场景与职责

该快照文件测试在序言（preamble）阶段保持工作状态指示器的渲染效果。

## 功能点目的

1. **状态保持**: 在AI生成序言内容时保持工作状态显示
2. **用户反馈**: 告知用户AI仍在处理中
3. **避免状态丢失**: 防止序言流式传输时状态指示器消失

## 具体技术实现

### 序言处理

```rust
chat.on_task_started();
chat.on_agent_message_delta("Preamble line\n".to_string());
chat.on_commit_tick();
// 评论完成后恢复状态指示器
complete_assistant_message(&mut chat, "msg-commentary-snapshot", "Preamble line\n", Some(MessagePhase::Commentary));
```

### 渲染验证

确保在序言流式传输期间和之后，状态指示器保持可见。

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs` (行 3954-3979)
- **状态管理**: `StatusIndicatorState` 管理

## 改进建议
1. 添加序言进度指示
2. 区分序言和最终答案的状态
