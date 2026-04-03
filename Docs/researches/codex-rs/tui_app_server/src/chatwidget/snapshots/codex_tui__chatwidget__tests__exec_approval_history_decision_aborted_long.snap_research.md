# 研究文档: codex_tui__chatwidget__tests__exec_approval_history_decision_aborted_long.snap

## 场景与职责

本快照文件验证 **取消长命令执行** 后的历史记录渲染。

测试当用户取消一个长命令的执行请求时，历史记录中如何显示该取消操作。

## 功能点目的

1. **取消反馈**: 明确显示用户取消了命令执行
2. **命令截断**: 长命令的合理截断显示
3. **历史记录**: 将取消操作记录到历史中

## 具体技术实现

### 快照内容
```
✗ You canceled the request to run echo
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa...
```

### UI 元素
- `✗` - 取消/错误指示符
- "You canceled the request to run" - 取消说明
- 命令预览 - 长命令截断显示
- `...` - 截断标记

### 截断逻辑
```rust
const MAX_COMMAND_DISPLAY_LEN: usize = 80;

fn truncate_command(cmd: &str) -> String {
    if cmd.len() > MAX_COMMAND_DISPLAY_LEN {
        format!("{}...", &cmd[..MAX_COMMAND_DISPLAY_LEN-3])
    } else {
        cmd.to_string()
    }
}
```

## 关键代码路径与文件引用

### 测试定义
```rust
assertion_line: 495
expression: lines_to_single_string(&aborted_long)
```

### 相关事件
- `ExecApprovalRequestEvent` - 触发审批
- 用户选择取消 - 生成历史记录

## 依赖与外部交互

### 用户交互
- 用户在审批模态框选择 "No"
- 或按 `Esc` 键取消

## 风险、边界与改进建议

### 边界情况
- 多行命令的截断
- 包含特殊字符的命令
- 非常长的命令（>1000 字符）

### 改进建议
1. **智能截断**: 在单词边界处截断
2. **展开查看**: 支持查看完整命令
3. **取消原因**: 允许用户输入取消原因
