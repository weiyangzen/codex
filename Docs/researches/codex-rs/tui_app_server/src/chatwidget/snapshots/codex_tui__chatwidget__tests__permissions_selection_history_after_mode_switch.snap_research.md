# Permissions Selection History After Mode Switch Snapshot Research

## 场景与职责

该 snapshot 测试验证权限模式切换后在历史记录中生成的通知消息。当用户通过权限选择弹出框切换到不同的权限模式时，系统在历史记录中插入一条记录，告知用户权限已更新。

**测试场景**：
- 用户打开权限选择弹出框 (`/permissions` 或 `/approvals`)
- 用户选择切换到 "Full Access" 模式
- 系统在历史记录中显示权限更新通知

## 功能点目的

1. **操作可追溯**：记录权限变更历史，便于审计和回溯
2. **用户确认**：明确告知用户权限已成功更新
3. **状态同步**：确保用户了解当前生效的权限配置

## 具体技术实现

### 测试代码路径
**文件**：`codex-rs/tui_app_server/src/chatwidget/tests.rs` (约第 9120-9142 行)

```rust
#[tokio::test]
async fn permissions_selection_history_snapshot_after_mode_switch() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    #[cfg(target_os = "windows")]
    {
        chat.config.notices.hide_world_writable_warning = Some(true);
        chat.set_windows_sandbox_mode(Some(WindowsSandboxModeToml::Unelevated));
    }
    chat.config.notices.hide_full_access_warning = Some(true);

    chat.open_permissions_popup();
    chat.handle_key_event(KeyEvent::from(KeyCode::Down));  // 向下选择
    #[cfg(target_os = "windows")]
    chat.handle_key_event(KeyEvent::from(KeyCode::Down));  // Windows 需要额外一次
    chat.handle_key_event(KeyEvent::from(KeyCode::Enter)); // 确认选择

    let cells = drain_insert_history(&mut rx);
    assert_eq!(cells.len(), 1, "expected one mode-switch history cell");
    assert_snapshot!(
        "permissions_selection_history_after_mode_switch",
        lines_to_single_string(&cells[0])
    );
}
```

### Snapshot 内容
```
• Permissions updated to Full Access
```

### 历史记录生成逻辑
**文件**：`codex-rs/tui_app_server/src/chatwidget.rs` (权限选择处理代码)

当用户选择权限预设时，系统会：
1. 更新配置中的 `approval_policy` 和 `sandbox_policy`
2. 发送 `AppEvent::InsertHistoryCell` 事件
3. 在历史记录中显示格式化的权限更新消息

```rust
// 权限更新后生成历史记录消息
fn emit_permissions_history_cell(&self, preset_name: &str) -> AppEvent {
    AppEvent::InsertHistoryCell(Box::new(
        history_cell::new_info_event(
            format!("Permissions updated to {preset_name}")
        )
    ))
}
```

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs:8126-8319` | `open_permissions_popup()` - 权限选择主逻辑 |
| `codex-rs/tui_app_server/src/chatwidget.rs:8258-8294` | "Default" 和 "Guardian Approvals" 选项处理 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs:9120-9142` | 测试用例实现 |
| `codex-rs/tui_app_server/src/history_cell.rs` | 历史记录单元格创建函数 |

### 权限预设匹配
```rust
fn preset_matches_current(
    current_approval: AskForApproval,
    current_sandbox: &SandboxPolicy,
    preset: &ApprovalPreset,
) -> bool {
    current_approval == preset.approval && 
    current_sandbox.matches(&preset.sandbox)
}
```

## 依赖与外部交互

### 依赖模块
1. **ApprovalPreset**：定义权限预设（Default、Full Access、Read-only 等）
2. **AskForApproval**：审批策略枚举（Always、OnRequest、Never）
3. **SandboxPolicy**：沙箱策略配置
4. **HistoryCell**：历史记录单元格创建和渲染

### 事件流
```
用户打开权限选择弹出框
    ↓
显示可用权限预设列表
    ↓
用户选择新的权限模式
    ↓
更新 approval_policy 和 sandbox_policy
    ↓
发送 AppEvent::InsertHistoryCell
    ↓
在历史记录中显示 "Permissions updated to X"
```

### 与 Windows 平台的差异
- Windows 平台有额外的 "Default (non-admin sandbox)" 选项
- 需要处理 Windows 沙箱级别配置
- 测试中使用 `#[cfg(target_os = "windows")]` 条件编译

## 风险、边界与改进建议

### 潜在风险
1. **历史记录膨胀**：频繁的权限切换可能导致历史记录过长
2. **信息不足**：简单的文本可能不足以理解权限变更的完整影响
3. **误操作**：用户可能意外切换权限模式

### 边界情况
1. **相同模式选择**：选择当前已激活的模式是否生成历史记录
2. **配置失败**：权限更新失败时的错误处理
3. **并发修改**：多处同时修改权限的竞态条件

### 改进建议
1. **详细变更记录**：显示权限变更前后的详细对比
2. **撤销功能**：允许用户撤销最近的权限变更
3. **变更确认**：重要权限变更（如切换到 Full Access）需要额外确认
4. **时间戳**：在历史记录中显示权限变更的时间
5. **变更原因**：允许用户（可选）记录变更原因
6. **批量变更**：将多个相关配置变更合并为一条历史记录

### 相关测试
- `permissions_selection_history_full_access_to_default`：测试从 Full Access 切换回 Default
- `permissions_selection_history_full_access_to_default@windows`：Windows 平台变体
- `permissions_selection_emits_history_cell_when_current_is_selected`：测试选择当前模式

### 历史记录格式对比
| 场景 | 历史记录内容 |
|------|-------------|
| 切换到 Full Access | `• Permissions updated to Full Access` |
| 切换到 Default | `• Permissions updated to Default` |
| Windows 切换到 Default | `• Permissions updated to Default (non-admin sandbox)` |
