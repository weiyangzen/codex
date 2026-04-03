# 研究文档: codex_tui__chatwidget__tests__approval_modal_exec.snap

## 场景与职责

本快照文件验证 **命令执行审批模态框** 的渲染输出。当 Codex 需要执行 shell 命令时，会弹出此模态框请求用户批准。

这是 TUI 安全模型的核心组件，确保用户在命令执行前有机会审查和拒绝潜在危险操作。

## 功能点目的

1. **用户确认机制**: 在执行命令前强制用户确认
2. **透明度**: 显示命令执行的完整原因说明
3. **快捷操作**: 提供 "是/否/不再询问" 多种选项
4. **键盘导航**: 支持键盘快捷键快速选择

## 具体技术实现

### 快照内容结构
```
Would you like to run the following command?

Reason: this is a test reason such as one that would be produced by the model

$ echo hello world

› 1. Yes, proceed (y)
  2. Yes, and don't ask again for commands that start with `echo hello world` (p)
  3. No, and tell Codex what to do differently (esc)

Press enter to confirm or esc to cancel
```

### UI 组件分析

| 元素 | 说明 |
|------|------|
| 标题 | "Would you like to run the following command?" |
| 原因说明 | 模型提供的执行理由 |
| 命令预览 | `$ echo hello world` - 带语法高亮 |
| 选项列表 | 3个选项，当前选中项用 `›` 标记 |
| 快捷键提示 | `(y)`, `(p)`, `(esc)` |
| 底部提示 | 确认/取消操作说明 |

### 渲染技术
- 使用 `VT100Backend` 捕获终端输出
- 通过 `terminal.backend().vt100().screen().contents()` 获取屏幕内容
- 支持 ANSI 转义序列的颜色和样式

## 关键代码路径与文件引用

### 测试定义
```rust
// tui/src/chatwidget/tests.rs
expression: terminal.backend().vt100().screen().contents()
```

### 相关源码
- `chatwidget.rs` - 处理 `ExecApprovalRequestEvent`
- `bottom_pane/` - 底部面板模态框渲染
- `approval_modal.rs` (如存在) - 专门的审批模态框组件

### 协议事件
```rust
ExecApprovalRequestEvent {
    command: String,           // "echo hello world"
    reason: Option<String>,    // 执行原因
    policy: ExecPolicy,        // 执行策略
}
```

## 依赖与外部交互

### 核心依赖
- `codex_protocol::protocol::ExecApprovalRequestEvent` - 审批请求事件
- `codex_protocol::protocol::ExecPolicy` - 执行策略配置
- `ratatui` - TUI 渲染框架

### 配置依赖
- `AskForApproval` 配置 - 控制审批行为
- `ApprovalsReviewer` - 审批人设置（用户/自动）

## 风险、边界与改进建议

### 安全风险
1. **命令注入显示**: 确保命令显示不会被转义序列欺骗
2. **原因说明长度**: 过长的原因说明需要正确处理换行
3. **前缀匹配**: "不再询问" 基于前缀匹配，可能被绕过

### 边界情况
- 超长命令的截断显示
- 多行命令的渲染
- 无原因说明的情况（见 `approval_modal_exec_no_reason.snap`）

### 改进建议
1. **语法高亮**: 对命令进行语法高亮，提高可读性
2. **风险评估**: 显示命令的风险等级（如文件删除警告）
3. **历史记录**: 显示类似命令的历史审批记录
4. **确认延迟**: 对高风险命令添加强制延迟

### 相关测试
- `approval_modal_exec_no_reason.snap` - 无原因说明场景
- `approval_modal_exec_multiline_prefix_no_execpolicy.snap` - 多行命令场景
- `exec_approval_modal_exec.snap` - Buffer 级别的详细渲染测试
