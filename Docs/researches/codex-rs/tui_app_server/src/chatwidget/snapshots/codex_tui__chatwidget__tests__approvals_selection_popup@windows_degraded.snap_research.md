# 研究文档: codex_tui__chatwidget__tests__approvals_selection_popup@windows_degraded.snap

## 场景与职责

本快照文件验证 **Windows 降级模式下的权限选择弹窗** 渲染输出。

当 Windows 系统无法使用标准沙箱时，显示降级模式的权限选项和额外警告信息。

## 功能点目的

1. **降级检测**: 检测 Windows 沙箱功能不可用
2. **风险警告**: 明确告知用户当前处于降级模式
3. **升级指引**: 提供恢复到标准沙箱的操作指引

## 具体技术实现

### 快照内容结构
```
Update Model Permissions

› 1. Read Only (current)             Codex can read files in the current
                                     workspace. Approval is required to edit
                                     files or access the internet.
  2. Default (non-admin sandbox)  Codex can read and edit files in the
                                     current workspace, and run commands.
                                     Approval is required to access the
                                     internet or edit other files.
  3. Full Access                     Codex can edit files outside this
                                     workspace and access the internet without
                                     asking for approval. Exercise caution
                                     when using.

The non-admin sandbox protects your files and prevents network access under
most circumstances. However, it carries greater risk if prompt injected. To
upgrade to the default sandbox, run /setup-default-sandbox.
Press enter to confirm or esc to go back
```

### 降级模式标识

| 元素 | 说明 |
|------|------|
| "(non-admin sandbox)" | Default 选项的降级标记 |
| 警告文本 | 底部额外风险提示 |
| 升级指引 | `/setup-default-sandbox` 命令提示 |

### 降级原因
- Windows 沙箱服务未运行
- 缺少管理员权限
- 系统版本不支持
- 组策略限制

## 关键代码路径与文件引用

### 降级检测逻辑
```rust
// 伪代码
if windows_sandbox_available() {
    show_standard_options();
} else {
    show_degraded_options();
    show_warning_message();
}
```

### 测试行号
```
assertion_line: 3945
```

### 相关命令
- `/setup-default-sandbox` - 设置默认沙箱

## 依赖与外部交互

### Windows 系统依赖
- Windows Sandbox 功能
- 管理员权限
- Hyper-V 支持

### 安全降级
- 使用非管理员沙箱作为备选
- 保持基本的文件隔离

## 风险、边界与改进建议

### 降级模式风险
1. **Prompt Injection**: 降级模式对提示注入攻击更脆弱
2. **网络隔离**: 可能无法完全阻止网络访问
3. **文件保护**: 文件系统隔离可能不完整

### 改进建议
1. **强制警告**: 每次启动时显示降级警告
2. **一键修复**: 提供自动修复沙箱的向导
3. **详细诊断**: 显示为什么降级（具体原因）
4. **功能限制**: 降级模式下限制某些高风险功能
5. **定期提醒**: 定期提示用户修复沙箱

### 用户教育
- 解释什么是 "non-admin sandbox"
- 说明降级模式的具体风险
- 提供升级到标准沙箱的详细步骤

### 相关测试
- `approvals_selection_popup@windows.snap` - 标准 Windows 模式
- 应补充测试：修复沙箱后的模式切换
