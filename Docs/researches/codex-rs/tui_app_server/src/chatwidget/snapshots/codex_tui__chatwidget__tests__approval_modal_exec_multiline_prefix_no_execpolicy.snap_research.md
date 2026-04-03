# 研究文档: codex_tui__chatwidget__tests__approval_modal_exec_multiline_prefix_no_execpolicy.snap

## 场景与职责

本快照文件验证 **多行命令执行审批模态框** 的渲染输出，特别是在没有执行策略（execpolicy）的情况下。

该场景测试当 Codex 需要执行包含多行内容的脚本命令时，TUI 如何正确渲染审批界面。

## 功能点目的

1. **多行命令显示**: 正确处理包含 heredoc 或多行脚本的命令
2. **无策略简化**: 当没有执行策略时，简化选项（不提供 "不再询问"）
3. **格式保持**: 保持原始命令的缩进和格式

## 具体技术实现

### 快照内容结构
```
Would you like to run the following command?

$ python - <<'PY'
print('hello')
PY

› 1. Yes, proceed (y)
  2. No, and tell Codex what to do differently (esc)

Press enter to confirm or esc to cancel
```

### 与标准审批模态框的区别

| 特性 | 标准模态框 | 本场景（无 execpolicy） |
|------|-----------|------------------------|
| 选项数量 | 3个 | 2个 |
| "不再询问" | 有 | 无 |
| 前缀匹配 | 支持 | 不支持 |
| 原因说明 | 有 | 无 |

### 多行命令处理
- 使用 heredoc 语法: `<<'PY'`
- 保持原始缩进
- 结束标记 `PY` 正确显示

## 关键代码路径与文件引用

### 测试定义
```rust
// tui/src/chatwidget/tests.rs
expression: contents
```

### 逻辑分支
```rust
// 伪代码表示
if has_execpolicy {
    show_option_3_prefix_based_skip();
} else {
    // 仅显示 2 个选项
    show_yes_and_no_only();
}
```

### 相关事件
- `ExecApprovalRequestEvent` - 触发审批模态框
- `ExecPolicyAmendment` - 执行策略修正（本场景无）

## 依赖与外部交互

### 配置依赖
- `execpolicy` 配置项 - 控制是否启用前缀匹配
- `AskForApproval` - 审批策略设置

### 协议类型
```rust
enum ExecPolicy {
    AlwaysAsk,           // 总是询问
    AskUnlessPrefix(String), // 除非匹配前缀
}
```

## 风险、边界与改进建议

### 安全风险
1. **Heredoc 截断**: 长 heredoc 可能被截断，导致用户误解命令内容
2. **无策略风险**: 不提供 "不再询问" 可能增加用户负担，但更安全

### 边界情况
- 极长的多行脚本
- 包含特殊字符的 heredoc 标记
- 嵌套的 heredoc

### 改进建议
1. **代码折叠**: 对长脚本提供折叠/展开功能
2. **语法高亮**: 对 Python/Shell 代码进行语法高亮
3. **行号显示**: 显示行号便于用户定位
4. **预览滚动**: 支持在模态框内滚动查看完整命令

### 相关测试
- `approval_modal_exec.snap` - 标准单命令场景
- `approval_modal_exec_no_reason.snap` - 无原因说明场景
