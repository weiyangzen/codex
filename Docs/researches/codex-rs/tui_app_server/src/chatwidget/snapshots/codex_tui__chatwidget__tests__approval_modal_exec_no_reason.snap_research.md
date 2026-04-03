# 研究文档: codex_tui__chatwidget__tests__approval_modal_exec_no_reason.snap

## 场景与职责

本快照文件验证 **无原因说明的命令执行审批模态框** 渲染输出。

当 Codex 执行命令但没有提供具体原因说明时，TUI 需要正确渲染简化版的审批界面。

## 功能点目的

1. **简化界面**: 当没有原因说明时，不显示空的原因区域
2. **保持可用性**: 即使缺少原因，仍提供完整的审批选项
3. **一致性**: 保持与其他审批模态框相同的视觉风格

## 具体技术实现

### 快照内容结构
```
Would you like to run the following command?

$ echo hello world

› 1. Yes, proceed (y)
  2. Yes, and don't ask again for commands that start with `echo hello world` (p)
  3. No, and tell Codex what to do differently (esc)

Press enter to confirm or esc to cancel
```

### 与完整模态框的对比

| 元素 | 完整版 | 本场景（无原因） |
|------|--------|-----------------|
| 原因区域 | "Reason: ..." | 无 |
| 命令间距 | 原因后有换行 | 标题后直接命令 |
| 选项数量 | 3个 | 3个（保持不变） |

### 布局逻辑
```
[标题]
[空行]
[命令]           ← 直接显示，无原因区域
[空行]
[选项列表]
[底部提示]
```

## 关键代码路径与文件引用

### 测试定义
```rust
// tui/src/chatwidget/tests.rs
expression: terminal.backend().vt100().screen().contents()
```

### 条件渲染逻辑
```rust
// 伪代码
if let Some(reason) = &event.reason {
    render_reason(reason);
    render_empty_line();
}
render_command(&event.command);
```

### 相关事件字段
```rust
ExecApprovalRequestEvent {
    command: String,
    reason: Option<String>,  // 本场景为 None
    policy: ExecPolicy,
}
```

## 依赖与外部交互

### 模型行为
- 某些模型可能不提供执行原因
- 快速执行模式可能跳过原因生成

### 用户体验
- 缺少原因可能降低用户信任度
- 建议模型始终提供执行原因

## 风险、边界与改进建议

### 用户体验风险
1. **透明度降低**: 用户不知道为什么执行该命令
2. **误操作风险**: 缺乏上下文可能导致错误批准

### 改进建议
1. **默认原因**: 当模型未提供原因时，显示默认说明如 "Model requested execution"
2. **警告提示**: 对无原因命令添加视觉警告
3. **强制原因**: 配置选项要求模型必须提供原因
4. **命令解释**: 提供 "Explain" 按钮请求模型解释命令目的

### 测试覆盖
- 应补充测试：原因为空字符串 vs None 的处理差异
- 应补充测试：超长命令在无原因区域的布局
