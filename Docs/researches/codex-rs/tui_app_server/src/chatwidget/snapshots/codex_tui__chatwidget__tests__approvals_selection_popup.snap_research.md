# 研究文档: codex_tui__chatwidget__tests__approvals_selection_popup.snap

## 场景与职责

本快照文件验证 **权限选择弹窗** 的渲染输出，显示在非 Windows 平台上（如 Linux/macOS）。

该弹窗允许用户在 "Default" 和 "Full Access" 两种权限模式之间切换。

## 功能点目的

1. **权限模式切换**: 允许用户动态调整 Codex 的操作权限
2. **安全提示**: 清晰说明每种权限模式的能力和风险
3. **快速切换**: 提供快捷键快速选择

## 具体技术实现

### 快照内容结构
```
Update Model Permissions

› 1. Default      Codex can read and edit files in the current workspace, and
                  run commands. Approval is required to access the internet or
                  edit other files.
  2. Full Access  Codex can edit files outside this workspace and access the
                  internet without asking for approval. Exercise caution when
                  using.

Press enter to confirm or esc to go back
```

### 权限模式对比

| 模式 | 文件访问 | 命令执行 | 网络访问 | 外部文件 |
|------|---------|---------|---------|---------|
| Default | 工作区内读写 | 允许 | 需审批 | 需审批 |
| Full Access | 全系统读写 | 允许 | 允许 | 允许 |

### 平台差异
- **非 Windows**: 2 个选项（Default/Full Access）
- **Windows**: 3 个选项（Read Only/Default/Full Access）

## 关键代码路径与文件引用

### 测试定义
```rust
// tui/src/chatwidget/tests.rs
assertion_line: 7368
expression: popup
```

### 权限配置
```rust
enum SandboxPolicy {
    ReadOnly,    // 只读（Windows 特有）
    Default,     // 默认沙箱
    FullAccess,  // 完全访问
}
```

### 相关模块
- `chatwidget.rs` - 弹窗状态管理
- `codex_core::config` - 权限配置定义

## 依赖与外部交互

### 配置系统
- `Config::sandbox_policy` - 当前权限策略
- `AskForApproval` - 审批策略

### 安全系统
- 沙箱实现（Seatbelt/Windows Sandbox）
- 网络访问控制

## 风险、边界与改进建议

### 安全风险
1. **Full Access 风险**: 用户可能不理解完全访问的风险
2. **持久化问题**: 权限切换是否持久化到配置

### 改进建议
1. **风险警告**: Full Access 选项使用红色/警告色
2. **确认对话框**: 切换到 Full Access 需要二次确认
3. **会话限制**: 提供 "仅本次会话" 选项
4. **权限预览**: 显示当前权限下的允许/禁止操作列表

### 相关测试
- `approvals_selection_popup@windows.snap` - Windows 平台版本
- `approvals_selection_popup@windows_degraded.snap` - Windows 降级模式
