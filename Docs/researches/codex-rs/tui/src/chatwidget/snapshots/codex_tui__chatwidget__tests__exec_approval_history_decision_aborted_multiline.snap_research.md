# 研究文档: exec_approval_history_decision_aborted_multiline.snap

## 场景与职责

该快照文件测试当用户拒绝执行多行命令时，历史记录中决策信息的渲染效果。

## 功能点目的

1. **多行命令处理**: 正确处理包含换行符的命令
2. **拒绝记录**: 记录对多行命令的拒绝决策
3. **格式一致性**: 保持单行显示格式

## 具体技术实现

### 测试数据

```rust
let ev_multi = ExecApprovalRequestEvent {
    call_id: "call-multi".into(),
    approval_id: Some("call-multi".into()),
    turn_id: "turn-multi".into(),
    command: vec!["bash".into(), "-lc".into(), "echo line1\necho line2".into()],
    // ...
};
```

### 多行处理

- 模态框显示完整多行命令
- 历史记录中显示截断/简化的单行版本
- 使用 "..." 表示有多行内容

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs` (行 3379-3438)

## 依赖与外部交互

1. **字符串处理**: 换行符检测和处理

## 风险、边界与改进建议

### 风险
- 多行命令的简化显示可能丢失重要信息
- 用户可能不理解命令的完整影响

### 改进建议
1. 显示多行命令的行数统计
2. 提供查看完整命令的选项
3. 对多行命令添加特殊标记
