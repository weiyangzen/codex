# 研究文档: approval_modal_exec_multiline_prefix_no_execpolicy.snap

## 场景与职责

该快照文件测试多行命令在审批模态框中的渲染效果，特别是当命令没有关联的执行策略（execpolicy）时的显示行为。

## 功能点目的

1. **多行命令显示**: 验证包含换行符的命令在审批模态框中的正确渲染
2. **无策略场景**: 测试当命令没有预设执行策略时的UI表现
3. **前缀处理**: 验证命令前缀（如 `bash -lc`）的正确显示

## 具体技术实现

### 测试数据

```rust
let ev_multi = ExecApprovalRequestEvent {
    call_id: "call-multi".into(),
    approval_id: Some("call-multi".into()),
    turn_id: "turn-multi".into(),
    command: vec!["bash".into(), "-lc".into(), "echo line1\necho line2".into()],
    cwd: std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")),
    reason: Some("this is a test reason such as one that would be produced by the model".into()),
    network_approval_context: None,
    proposed_execpolicy_amendment: None,  // 无执行策略修改
    proposed_network_policy_amendments: None,
    additional_permissions: None,
    skill_metadata: None,
    available_decisions: None,
    parsed_cmd: vec![],
};
```

### 渲染特点

- 多行命令保持原始格式显示
- 不显示执行策略相关信息（因为 `proposed_execpolicy_amendment` 为 None）
- 命令中的换行符被正确处理并在UI中呈现

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs` (行 3379-3473)
- **命令解析**: `codex_shell_command::parse_command::parse_command`
- **模态框渲染**: `render_bottom_popup` 辅助函数

## 依赖与外部交互

1. **codex-shell-command**: 命令解析库
2. **ratatui**: 终端渲染

## 风险、边界与改进建议

### 风险
- 极长多行命令可能导致模态框超出屏幕
- 特殊字符（如控制字符）可能破坏UI布局

### 边界情况
- 空命令处理
- 仅包含空白字符的命令
- Unicode 字符的宽度计算

### 改进建议
1. 添加多行命令的折叠/展开功能
2. 限制显示的最大行数，提供"查看更多"选项
3. 对无策略命令添加风险提示
