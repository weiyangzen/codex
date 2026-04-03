# Research: approvals_selection_popup@windows (App Server)

## 场景与职责

此 snapshot 测试验证 **tui_app_server** 中权限选择弹出框在 **Windows 平台**上的渲染效果。Windows 版本包含额外的 "Read Only" 选项和 Windows 沙箱相关的特殊处理。

**测试目的**：确保 Windows 平台的权限选择弹出框正确显示所有可用的权限模式，包括 Windows 特有的沙箱选项。

## 功能点目的

1. **Windows 特有选项**：提供 Read Only 模式，适合 Windows 非管理员沙箱环境
2. **沙箱感知**：显示当前 Windows 沙箱状态（管理员/非管理员）
3. **降级沙箱提示**：当 Windows 沙箱未以管理员权限运行时显示提示
4. **权限升级引导**：提供链接或提示帮助用户设置默认沙箱

## 具体技术实现

### Snapshot 内容
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

### 与非 Windows 版本的对比

**非 Windows 版本** (2 个选项):
```
› 1. Default      ...
  2. Full Access  ...
```

**Windows 版本** (3 个选项):
```
› 1. Read Only (current)  ...
  2. Default              ...
  3. Full Access          ...
```

### 关键代码路径

1. **测试函数**：
   - 文件：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
   - 函数：`approvals_selection_popup_snapshot` (约 line 8481)
   - 条件编译：`#[cfg(target_os = "windows")]`

2. **Windows 特有测试**：
   - 文件：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
   - 函数：`approvals_selection_popup_snapshot_windows_degraded_sandbox` (约 line 8496)
   - 测试降级沙箱状态的显示

3. **权限选项构建**：
   - 根据 `WindowsSandboxModeToml` 和特性标志构建选项
   - 检测 `Feature::WindowsSandbox` 和 `Feature::WindowsSandboxElevated`

4. **当前模式标记**：
   - 在选项标签后附加 `(current)` 标记当前激活的模式
   - 示例：`Read Only (current)`

### 数据结构

```rust
// Windows 平台的可用模式
#[cfg(target_os = "windows")]
[
    ApprovalSelectionItem {
        label: "Read Only (current)".to_string(),
        description: "Codex can read files in the current workspace. Approval is required to edit files or access the internet.".to_string(),
        sandbox_policy: SandboxPolicy::ReadOnly,
        is_current: true,
    },
    ApprovalSelectionItem {
        label: "Default".to_string(),
        description: "Codex can read and edit files in the current workspace, and run commands. Approval is required to access the internet or edit other files.".to_string(),
        sandbox_policy: SandboxPolicy::WorkspaceWrite,
        is_current: false,
    },
    ApprovalSelectionItem {
        label: "Full Access".to_string(),
        description: "Codex can edit files outside this workspace and access the internet without asking for approval. Exercise caution when using.".to_string(),
        sandbox_policy: SandboxPolicy::FullAccess,
        is_current: false,
    },
]
```

### Windows 沙箱特性

| 特性 | 描述 |
|------|------|
| `WindowsSandbox` | Windows 沙箱功能启用 |
| `WindowsSandboxElevated` | 以管理员权限运行 |
| 降级沙箱 | 非管理员沙箱显示特殊标签和提示 |

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `chatwidget::ChatWidget` | 主控件 |
| `codex_core::features` | Windows 沙箱特性检测 |
| `codex_core::config::types::WindowsSandboxModeToml` | Windows 沙箱配置 |

### 平台特定代码
```rust
#[cfg(target_os = "windows")]
{
    // Windows 特有逻辑
    chat.set_feature_enabled(Feature::WindowsSandbox, true);
    chat.set_feature_enabled(Feature::WindowsSandboxElevated, false); // 降级沙箱
}
```

### 降级沙箱测试
- 测试函数：`approvals_selection_popup_snapshot_windows_degraded_sandbox`
- 验证内容：
  - `Default (non-admin sandbox)` 标签
  - `/setup-default-sandbox` 设置提示
  - `non-admin sandbox` 警告说明

## 风险、边界与改进建议

### 当前风险
1. **沙箱检测准确性**：Windows 沙箱权限检测可能受 UAC 设置影响
2. **模式切换限制**：某些沙箱状态下可能无法切换到某些模式
3. **用户体验差异**：Windows 用户看到的选项与其他平台不同，可能造成困惑

### 边界情况
1. **管理员权限检测**：准确检测是否以管理员权限运行
2. **沙箱安装状态**：检测 Windows 沙箱功能是否已安装
3. **企业环境**：企业策略可能限制沙箱使用

### 改进建议
1. **沙箱状态图标**：使用图标直观显示沙箱状态
2. **一键修复**：提供按钮自动配置默认沙箱
3. **权限提升提示**：在需要时引导用户提升权限
4. **沙箱文档链接**：提供 Windows 沙箱设置的详细指南
5. **模式推荐**：根据当前沙箱状态推荐合适的权限模式

### 平台差异总结

| 特性 | macOS/Linux | Windows |
|------|-------------|---------|
| Read Only 模式 | ❌ | ✅ |
| 沙箱状态检测 | Seatbelt | Windows Sandbox |
| 降级沙箱提示 | N/A | ✅ |
| 选项数量 | 2 | 3 |

### 与 TUI 版本的关系
- 与 `codex_tui__chatwidget__tests__approvals_selection_popup@windows.snap` 保持平行实现
- Windows 沙箱逻辑在两个版本中一致
- 降级沙箱处理逻辑相同

### 测试验证点
1. ✅ Windows 平台显示 3 个选项
2. ✅ Read Only 模式正确显示
3. ✅ 当前模式标记 `(current)` 正确显示
4. ✅ 降级沙箱测试验证特殊标签和提示
5. ✅ 页脚提示正确显示
