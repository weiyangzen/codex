# 研究文档: exec_approval_history_decision_aborted_long.snap

## 场景与职责

该快照文件测试当用户拒绝（中止）执行长命令时，历史记录中决策信息的渲染效果。

## 功能点目的

1. **拒绝记录**: 记录用户拒绝执行命令的决策
2. **长命令截断**: 对超长命令进行适当的截断显示
3. **历史一致性**: 保持历史记录的格式一致性

## 具体技术实现

### 测试数据

```rust
let long = format!("echo {}", "a".repeat(200));  // 超长命令
let ev_long = ExecApprovalRequestEvent {
    call_id: "call-long".into(),
    approval_id: Some("call-long".into()),
    turn_id: "turn-long".into(),
    command: vec!["bash".into(), "-lc".into(), long],
    reason: None,
    // ...
};

// 用户拒绝
chat.handle_key_event(KeyEvent::new(KeyCode::Char('n'), KeyModifiers::NONE));
```

### 截断逻辑

```rust
// 命令显示截断至 <= 80 字符，添加尾部 ...
let truncated = if command.len() > 80 {
    format!("{}...", &command[..77])
} else {
    command.to_string()
};
```

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs` (行 3439-3473)
- **历史记录生成**: 拒绝决策后的历史插入逻辑

## 依赖与外部交互

1. **文本截断**: 使用标准字符串操作

## 风险、边界与改进建议

### 风险
- 截断可能丢失关键命令信息
- 用户可能无法从截断文本理解被拒绝的命令

### 改进建议
1. 提供展开查看完整命令的功能
2. 智能截断（保留命令名，截断参数）
3. 添加命令哈希或ID用于后续查询
