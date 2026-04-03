# 研究文档: interrupted_turn_error_message.snap

## 场景与职责

该快照文件测试中断回合（turn）时显示的错误消息渲染效果。

## 功能点目的

1. **中断反馈**: 向用户说明回合已被中断
2. **后续指导**: 指导用户如何继续操作
3. **错误处理**: 优雅地处理中断后的状态

## 具体技术实现

### 中断错误消息

```rust
chat.handle_codex_event(Event {
    id: "task-1".into(),
    msg: EventMsg::TurnAborted(codex_protocol::protocol::TurnAbortedEvent {
        turn_id: Some("turn-1".to_string()),
        reason: TurnAbortReason::Interrupted,
    }),
});
```

### 渲染输出

```
⚠️  Turn interrupted

The model was interrupted before completing its response.
You can:
• Tell the model what to do differently
• Use /feedback to report issues
```

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs` (行 6500-6530)

## 改进建议
1. 添加中断原因说明（如果可用）
2. 提供恢复/重试选项
3. 显示已生成的部分响应
