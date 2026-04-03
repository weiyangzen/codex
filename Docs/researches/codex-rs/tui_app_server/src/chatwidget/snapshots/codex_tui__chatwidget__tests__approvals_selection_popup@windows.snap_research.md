# 研究文档: codex_tui__chatwidget__tests__approvals_selection_popup@windows.snap

## 场景与职责

本快照文件验证 **Windows 平台的权限选择弹窗** 渲染输出。

Windows 平台提供 3 种权限模式，包括特有的 "Read Only" 只读模式。

## 功能点目的

1. **Windows 特有模式**: 提供 Read Only 模式，适合安全审查场景
2. **当前状态标识**: 清晰标记当前激活的权限模式
3. **平台适配**: 针对 Windows 安全模型优化选项描述

## 具体技术实现

### 快照内容结构
```
Update Model Permissions

› 1. Read Only (current)  Codex can read files in the current workspace.
                          Approval is required to edit files or access the
                          internet.
  2. Default              Codex can read and edit files in the current
                          workspace, and run commands. Approval is required to
                          access the internet or edit other files.
  3. Full Access          Codex can edit files outside this workspace and
                          access the internet without asking for approval.
                          Exercise caution when using.

Press enter to confirm or esc to go back
```

### Windows 特有元素

| 特性 | 说明 |
|------|------|
| Read Only | Windows 特有模式，仅允许读取 |
| (current) | 标记当前激活的模式 |
| 3 个选项 | 比非 Windows 多一个选项 |

### 权限模式详解

```
Read Only (current)
├── 读取工作区文件 ✓
├── 编辑文件 ✗（需审批）
├── 执行命令 ✗（需审批）
└── 网络访问 ✗（需审批）

Default
├── 读取工作区文件 ✓
├── 编辑工作区文件 ✓
├── 执行命令 ✓
├── 网络访问 ✗（需审批）
└── 外部文件 ✗（需审批）

Full Access
└── 所有操作 ✓（无需审批）
```

## 关键代码路径与文件引用

### 平台条件编译
```rust
#[cfg(target_os = "windows")]
use codex_core::config::types::WindowsSandboxModeToml;
```

### Windows 沙箱级别
```rust
enum WindowsSandboxLevel {
    ReadOnly,
    Default,
    FullAccess,
}
```

### 测试标记
```rust
assertion_line: 7365
```

## 依赖与外部交互

### Windows 特有依赖
- `codex_core::windows_sandbox` - Windows 沙箱实现
- `WindowsSandboxLevelExt` - 扩展方法

### 配置持久化
- 保存到 `config.toml`
- 会话级覆盖

## 风险、边界与改进建议

### Windows 特有考虑
1. **UAC 交互**: 某些操作可能需要 UAC 提升
2. **Windows Sandbox**: 与系统 Windows Sandbox 功能的区分
3. **路径格式**: Windows 路径格式处理

### 改进建议
1. **图标区分**: 为每种模式添加视觉图标
2. **快速切换**: 添加快捷键直接切换
3. **模式说明**: 展开显示每种模式的详细能力矩阵
4. **恢复默认**: 添加 "恢复默认" 按钮

### 相关测试
- `approvals_selection_popup.snap` - 非 Windows 版本
- `approvals_selection_popup@windows_degraded.snap` - 降级模式
