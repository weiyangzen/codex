# 研究文档: full_access_confirmation_popup.snap

## 场景与职责

该快照文件测试"完全访问权限"确认弹窗的渲染效果。当用户尝试切换到最高权限模式时显示此确认对话框。

## 功能点目的

1. **高风险操作确认**: 防止用户意外启用完全访问权限
2. **安全警告**: 明确告知完全访问权限的风险
3. **责任明确**: 确保用户理解并承担使用风险

## 具体技术实现

### 弹窗内容

```
Enable Full Access?

Full Access allows Codex to:
• Edit files outside the workspace
• Access the internet without approval
• Execute any system commands

This mode bypasses most safety protections.

› Yes, enable Full Access
  No, keep current restrictions

⚠️  Use with caution. Only enable if you trust the AI completely.
```

### 权限级别

```rust
enum SandboxPolicy {
    ReadOnly,      // 只读
    Default,       // 默认（工作区内读写）
    FullAccess,    // 完全访问
}
```

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs`
- **权限管理**: `codex-core/src/config/types.rs`
- **安全策略**: 沙盒策略实现

## 风险、边界与改进建议

### 风险
- 用户可能未充分理解风险就启用
- 恶意提示可能诱导用户启用

### 改进建议
1. 添加二次确认（输入"I understand"）
2. 显示当前会话的权限变更历史
3. 添加超时自动恢复功能
4. 提供权限使用的审计日志
