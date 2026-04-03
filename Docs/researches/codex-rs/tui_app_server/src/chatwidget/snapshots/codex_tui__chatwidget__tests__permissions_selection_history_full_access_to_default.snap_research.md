# Permissions Selection History Full Access To Default Snapshot Research

## 场景与职责

该 snapshot 测试验证从 "Full Access" 权限模式切换回 "Default" 模式时在历史记录中生成的通知消息。这是权限变更历史记录功能的反向场景，确保无论权限升级还是降级都被正确记录。

**测试场景**：
- 用户当前处于 "Full Access" 模式（最高权限）
- 用户通过权限选择弹出框切换回 "Default" 模式
- 系统在历史记录中显示权限已更新为 Default

## 功能点目的

1. **完整审计追踪**：记录所有权限变更，无论是升级还是降级
2. **安全合规**：满足安全审计要求，追踪权限降低事件
3. **用户透明度**：让用户清楚了解当前的安全边界

## 具体技术实现

### 测试代码路径
**文件**：`codex-rs/tui_app_server/src/chatwidget/tests.rs` (约第 9144-9183 行)

```rust
#[tokio::test]
async fn permissions_selection_history_snapshot_full_access_to_default() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    #[cfg(target_os = "windows")]
    {
        chat.config.notices.hide_world_writable_warning = Some(true);
        chat.set_windows_sandbox_mode(Some(WindowsSandboxModeToml::Unelevated));
    }
    chat.config.notices.hide_full_access_warning = Some(true);
    
    // 预先设置为 Full Access 模式
    chat.config.permissions.approval_policy
        .set(AskForApproval::Never)
        .expect("set approval policy");
    chat.config.permissions.sandbox_policy =
        Constrained::allow_any(SandboxPolicy::DangerFullAccess);

    chat.open_permissions_popup();
    let popup = render_bottom_popup(&chat, 120);
    chat.handle_key_event(KeyEvent::from(KeyCode::Up));  // 向上选择
    if popup.contains("Guardian Approvals") {
        chat.handle_key_event(KeyEvent::from(KeyCode::Up));  // 跳过 Guardian Approvals
    }
    chat.handle_key_event(KeyEvent::from(KeyCode::Enter)); // 确认选择

    let cells = drain_insert_history(&mut rx);
    assert_eq!(cells.len(), 1, "expected one mode-switch history cell");
    
    #[cfg(not(target_os = "windows"))]
    assert_snapshot!(
        "permissions_selection_history_full_access_to_default",
        lines_to_single_string(&cells[0])
    );
}
```

### Snapshot 内容（非 Windows 平台）
```
• Permissions updated to Default
```

### 预设配置对比
| 预设 | Approval Policy | Sandbox Policy |
|------|----------------|----------------|
| Default | `AskForApproval::OnRequest` | `SandboxPolicy::new_workspace_write_policy()` |
| Full Access | `AskForApproval::Never` | `SandboxPolicy::DangerFullAccess` |
| Read-only | `AskForApproval::OnRequest` | `SandboxPolicy::ReadOnly` |

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs:8126-8319` | `open_permissions_popup()` - 权限选择主逻辑 |
| `codex-rs/tui_app_server/src/chatwidget.rs:8158-8310` | 权限预设遍历和匹配逻辑 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs:9144-9183` | 测试用例实现 |
| `codex-rs/core/src/approval_preset.rs` | 内置权限预设定义 |

### 内置权限预设
```rust
pub fn builtin_approval_presets() -> Vec<ApprovalPreset> {
    vec![
        ApprovalPreset {
            id: "auto",
            label: "Default",
            description: "...",
            approval: AskForApproval::OnRequest,
            sandbox: SandboxPolicy::new_workspace_write_policy(),
        },
        ApprovalPreset {
            id: "full-access",
            label: "Full Access",
            description: "...",
            approval: AskForApproval::Never,
            sandbox: SandboxPolicy::DangerFullAccess,
        },
        // ... 其他预设
    ]
}
```

## 依赖与外部交互

### 依赖模块
1. **ApprovalPreset**：权限预设数据结构
2. **AskForApproval**：审批策略（Always、OnRequest、Never）
3. **SandboxPolicy**：沙箱策略（ReadOnly、WorkspaceWrite、DangerFullAccess 等）
4. **Constrained**：配置值的约束包装器

### 事件流
```
测试设置 Full Access 模式
    ↓
打开权限选择弹出框
    ↓
向上导航到 Default 选项
    ↓
确认选择
    ↓
更新配置：
  - approval_policy: Never → OnRequest
  - sandbox_policy: DangerFullAccess → WorkspaceWrite
    ↓
发送 InsertHistoryCell 事件
    ↓
显示 "Permissions updated to Default"
```

### 与 Guardian Approvals 的交互
- 如果 Guardian Approvals 功能启用，权限列表中会额外显示该选项
- 测试中需要检测并跳过 Guardian Approvals 选项
- Guardian Approvals 与 Default 使用相同的沙箱策略，但审批流程不同

## 风险、边界与改进建议

### 潜在风险
1. **权限降级遗漏**：用户可能忘记自己已降低权限，导致后续操作失败
2. **历史记录混淆**：频繁的权限切换可能使历史记录难以阅读
3. **测试平台差异**：Windows 和非 Windows 平台的测试结果不同

### 边界情况
1. **Guardian Approvals 干扰**：测试中需要处理 Guardian Approvals 选项的存在
2. **导航方向**：从 Full Access 向上导航到 Default 需要正确计算步数
3. **当前模式高亮**：确保当前模式在弹出框中正确高亮

### 改进建议
1. **变更详情**：在历史记录中显示权限变更的具体内容（如 "无需审批 → 按需审批"）
2. **安全提示**：降级到更安全模式时给予正面反馈
3. **快捷恢复**：提供快速恢复到之前权限模式的选项
4. **权限影响预览**：在确认前显示权限变更对当前任务的影响
5. **分组历史记录**：将相关的权限变更分组显示

### 相关测试
- `permissions_selection_history_after_mode_switch`：正向切换测试
- `permissions_selection_history_full_access_to_default@windows`：Windows 平台变体

### 平台差异说明
非 Windows 平台的权限预设列表：
1. Full Access
2. Default
3. (可选) Guardian Approvals

Windows 平台可能包含额外的 "Read-only" 选项，导致导航逻辑不同。
