# 研究文档: codex_tui__chatwidget__tests__exec_approval_history_decision_aborted_multiline.snap

## 场景与职责

本快照文件验证 **取消多行命令执行** 后的历史记录渲染。

测试多行命令被取消时的历史记录显示。

## 功能点目的

1. **多行处理**: 正确处理多行命令的取消显示
2. **简洁展示**: 在有限空间内展示多行命令的本质
3. **一致性**: 与单行命令取消保持一致的体验

## 具体技术实现

### 快照内容
```
✗ You canceled the request to run echo line1 ...

```

### 与单行取消的区别
- 多行命令显示第一行 + `...`
- 额外的空行分隔

### 多行检测
```rust
fn is_multiline(cmd: &str) -> bool {
    cmd.contains('\n')
}
```

## 关键代码路径与文件引用

### 测试定义
```rust
expression: lines_to_single_string(&aborted_multi)
```

### 相关测试
- `exec_approval_history_decision_aborted_long.snap` - 长单行命令
- `exec_approval_history_decision_approved_short.snap` - 短命令批准

## 依赖与外部交互

### 命令解析
- `ParsedCommand` - 命令解析结构
- `parse_command.rs` - 命令解析逻辑

## 风险、边界与改进建议

### 改进建议
1. **第一行预览**: 显示更有意义的第一行
2. **行数提示**: 显示 "(+5 more lines)"
3. **语法识别**: 识别 heredoc 等特殊语法
