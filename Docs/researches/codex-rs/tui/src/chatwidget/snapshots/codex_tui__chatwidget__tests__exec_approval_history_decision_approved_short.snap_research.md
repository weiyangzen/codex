# 研究文档: exec_approval_history_decision_approved_short.snap

## 场景与职责

该快照文件测试当用户批准执行短命令时，历史记录中决策信息的渲染效果。

## 功能点目的

1. **批准记录**: 记录用户批准执行命令的决策
2. **简洁显示**: 短命令的完整显示（无需截断）
3. **成功标记**: 使用视觉标记表示已批准

## 具体技术实现

### 测试数据

```rust
let ev = ExecApprovalRequestEvent {
    call_id: "call-short".into(),
    approval_id: Some("call-short".into()),
    turn_id: "turn-short".into(),
    command: vec!["bash".into(), "-lc".into(), "echo hello world".into()],
    // ...
};

// 用户批准
chat.handle_key_event(KeyEvent::new(KeyCode::Char('y'), KeyModifiers::NONE));
```

### 历史记录格式

```
✓ Approved: echo hello world
```

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs` (行 3286-3333)

## 依赖与外部交互

1. **codex-protocol**: 审批决策事件

## 风险、边界与改进建议

### 改进建议
1. 添加时间戳到历史记录
2. 提供跳转到命令输出的链接
