# Research: approvals_selection_popup (App Server)

## 场景与职责

此 snapshot 测试验证 **tui_app_server** 中权限选择弹出框的渲染效果（非 Windows 平台）。当用户通过 `/permissions` 命令或快捷键打开权限设置时，显示一个选择界面让用户切换不同的权限模式。

**测试目的**：确保权限选择弹出框在非 Windows 平台上正确显示可用的权限模式及其描述。

## 功能点目的

1. **权限模式切换**：允许用户在 Default 和 Full Access 模式之间切换
2. **模式描述**：为每个权限模式提供清晰的描述说明
3. **安全提示**：提醒用户谨慎使用 Full Access 模式
4. **快速选择**：通过键盘快捷键快速选择模式

## 具体技术实现

### Snapshot 内容
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

### 关键代码路径

1. **测试函数**：
   - 文件：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
   - 函数：`approvals_selection_popup_snapshot` (约 line 8481)

2. **权限弹出框打开**：
   - 文件：`codex-rs/tui_app_server/src/chatwidget.rs`
   - 方法：`open_approvals_popup`

3. **选项构建**：
   - 文件：`codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs` 或相关模块
   - 根据平台特性构建权限选项列表

4. **列表选择视图**：
   - 文件：`codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs`
   - 渲染选项列表和处理选择

### 数据结构

```rust
// 权限模式选项
pub(crate) struct ApprovalSelectionItem {
    pub label: String,
    pub description: String,
    pub sandbox_policy: SandboxPolicy,
    pub is_current: bool,
}

// 非 Windows 平台的可用模式
[
    ApprovalSelectionItem {
        label: "Default".to_string(),
        description: "Codex can read and edit files in the current workspace, and run commands. Approval is required to access the internet or edit other files.".to_string(),
        sandbox_policy: SandboxPolicy::WorkspaceWrite,
        is_current: true,  // 假设当前是 Default
    },
    ApprovalSelectionItem {
        label: "Full Access".to_string(),
        description: "Codex can edit files outside this workspace and access the internet without asking for approval. Exercise caution when using.".to_string(),
        sandbox_policy: SandboxPolicy::FullAccess,
        is_current: false,
    },
]
```

### 平台差异

| 平台 | 可用模式 | 特殊处理 |
|------|----------|----------|
| 非 Windows | Default, Full Access | 标准实现 |
| Windows | Read Only, Default, Full Access | 包含 Windows 沙箱选项 |

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `chatwidget::ChatWidget` | 主控件，处理权限弹出框打开 |
| `bottom_pane::BottomPane` | 底部面板，管理弹出框显示 |
| `bottom_pane::list_selection_view` | 选项列表渲染 |
| `codex_core::config` | 权限配置和沙箱策略 |

### 协议依赖
| 类型 | 来源 |
|------|------|
| `SandboxPolicy` | `codex_protocol::protocol` |
| `AskForApproval` | `codex_protocol::protocol` |

### 配置依赖
- `config.notices.hide_full_access_warning`：控制 Full Access 警告显示
- 平台特性检测（`#[cfg(not(target_os = "windows"))]`）

## 风险、边界与改进建议

### 当前风险
1. **描述长度**：权限描述较长，在小宽度终端可能换行不美观
2. **模式理解**：用户可能不理解不同模式的区别
3. **安全风险**：Full Access 模式的安全风险需要明确提示

### 边界情况
1. **当前模式指示**：需要清晰标记当前激活的权限模式
2. **模式切换确认**：切换到 Full Access 时可能需要额外确认
3. **会话持久化**：权限模式切换后的持久化行为

### 改进建议
1. **可视化指示**：添加图标或颜色区分不同权限级别
2. **风险提示增强**：Full Access 模式使用更醒目的警告样式
3. **快速切换**：提供快捷键直接切换常用模式
4. **模式预览**：显示当前模式下的权限详细列表
5. **帮助链接**：提供链接到权限模式的详细文档

### 与 Windows 版本的对比
- Windows 版本（`approvals_selection_popup@windows.snap`）包含 Read Only 选项
- Windows 版本可能包含沙箱相关的特殊选项
- 两者共享相同的底层实现，但选项列表不同

### 与 TUI 版本的关系
- 与 `codex_tui__chatwidget__tests__approvals_selection_popup.snap` 保持平行实现
- 权限模式定义在两个版本中一致
- 描述文本保持同步

### 测试验证点
1. ✅ 标题 "Update Model Permissions" 正确显示
2. ✅ Default 模式选项和描述正确显示
3. ✅ Full Access 模式选项和描述正确显示
4. ✅ 当前选中项标记（›）正确显示
5. ✅ 页脚提示正确显示
6. ✅ 非 Windows 平台不包含 Read Only 选项
