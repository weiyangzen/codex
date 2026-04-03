# 研究文档: interrupt_exec_marks_failed.snap

## 场景与职责

该快照文件测试当执行被中断时，如何将执行标记为失败并渲染到历史记录中。

## 功能点目的

1. **中断处理**: 正确处理用户中断命令执行
2. **失败标记**: 将中断的执行标记为失败状态
3. **状态同步**: 确保UI状态与实际执行状态一致

## 具体技术实现

### 中断事件

```rust
// 开始执行
begin_exec(&mut chat, "call-int", "sleep 1");

// 中断执行
chat.handle_codex_event(Event {
    id: "call-int".into(),
    msg: EventMsg::TurnAborted(codex_protocol::protocol::TurnAbortedEvent {
        turn_id: Some("turn-1".to_string()),
        reason: TurnAbortReason::Interrupted,
    }),
});
```

### 渲染输出

```
✗ Interrupted
  └ sleep 1
```

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs` (行 6470-6496)
- **中断处理**: `handle_codex_event` 中的 `TurnAborted` 处理

## 依赖与外部交互

1. **进程管理**: 中断信号发送

## 改进建议
1. 显示中断前的执行时长
2. 区分用户中断和系统中断
3. 提供重试选项
