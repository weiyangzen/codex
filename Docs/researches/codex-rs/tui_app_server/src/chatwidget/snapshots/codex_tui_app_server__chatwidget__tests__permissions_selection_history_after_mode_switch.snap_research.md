# 权限选择历史在模式切换后测试研究文档

## 场景与职责

该 snapshot 测试验证当用户切换权限模式时，tui_app_server 的 ChatWidget 能够在历史记录中正确显示权限更新信息。

**测试场景**：
1. 用户打开权限选择弹出框
2. 用户导航到不同的权限预设（如从 Default 切换到 Full Access）
3. 确认选择后，系统在历史记录中显示权限更新消息

**职责**：确保权限变更对用户可见，提供操作反馈和审计追踪。

## 功能点目的

- **操作反馈**：用户变更权限后立即收到视觉确认
- **审计追踪**：历史记录中保留权限变更记录
- **状态同步**：确保 UI 状态与实际配置保持一致
- **平台适配**：在不同操作系统上显示适当的权限描述

## 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/chatwidget/tests.rs` 第 9121-9142 行

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
    chat.handle_key_event(KeyEvent::from(KeyCode::Down));
    #[cfg(target_os = "windows")]
    chat.handle_key_event(KeyEvent::from(KeyCode::Down));
    chat.handle_key_event(KeyEvent::from(KeyCode::Enter));

    let cells = drain_insert_history(&mut rx);
    assert_eq!(cells.len(), 1, "expected one mode-switch history cell");
    assert_snapshot!(
        "permissions_selection_history_after_mode_switch",
        lines_to_single_string(&cells[0])
    );
}
```

### 关键实现细节

1. **平台特定配置**：
   - Windows 平台：设置沙箱模式为 `Unelevated`（非提升权限）
   - 隐藏世界可写警告和完全访问警告

2. **权限切换流程**：
   - 打开权限弹出框 (`open_permissions_popup`)
   - 按 Down 键导航到下一个权限选项
   - Windows 平台需要额外按一次 Down 键（可能因为 Windows 有额外的选项）
   - 按 Enter 确认选择

3. **历史记录验证**：
   - 使用 `drain_insert_history` 收集插入的历史记录单元格
   - 验证只有一个历史单元格被插入
   - 捕获并验证历史记录内容

### Snapshot 输出内容

```
• Permissions updated to Full Access
```

## 关键代码路径与文件引用

### 主要代码文件

1. **测试文件**：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
   - 测试函数：`permissions_selection_history_snapshot_after_mode_switch` (第 9121 行)

2. **ChatWidget 实现**：`codex-rs/tui_app_server/src/chatwidget/mod.rs`
   - 方法：`open_permissions_popup`
   - 权限处理逻辑

3. **权限管理**：`codex-rs/tui_app_server/src/permissions.rs`（假设位置）
   - 权限预设定义

4. **历史记录单元格**：`codex-rs/tui_app_server/src/history_cell/mod.rs`
   - 历史记录单元格渲染

### 相关协议类型

- `SandboxPolicy`：沙箱策略枚举
- `AskForApproval`：审批策略枚举
- `WindowsSandboxModeToml`：Windows 沙箱模式配置

## 依赖与外部交互

### 内部依赖

| 组件 | 用途 |
|------|------|
| `ChatWidget` | 主聊天组件，管理权限选择流程 |
| `BottomPane` | 渲染权限选择弹出框 |
| `HistoryCell` | 渲染历史记录中的权限更新消息 |
| `Config` | 存储和更新权限配置 |

### 外部依赖

- `ratatui`：终端 UI 渲染库
- `insta`：snapshot 测试框架
- `tokio`：异步运行时

### 平台特定处理

- **Windows**：需要额外的 Down 键导航，因为 Windows 平台有额外的沙箱选项
- **非 Windows**：标准的权限选项列表

## 风险、边界与改进建议

### 潜在风险

1. **平台差异**：Windows 和非 Windows 平台的权限选项不同，需要分别维护测试
2. **配置漂移**：如果权限预设改变，历史记录消息可能需要更新
3. **重复记录**：频繁切换权限可能产生大量历史记录

### 边界情况

1. **相同权限选择**：即使选择当前已激活的权限，也会生成历史记录（见 `permissions_selection_emits_history_cell_when_current_is_selected` 测试）
2. **Full Access 确认**：切换到 Full Access 可能需要额外确认（见 `permissions_full_access_history_cell_emitted_only_after_confirmation` 测试）
3. **Guardian Approvals**：如果启用了 Guardian Approvals 功能，权限选项列表会变化

### 改进建议

1. **批量权限变更**：如果用户快速切换多个权限，考虑合并历史记录
2. **权限变更原因**：允许用户添加权限变更的原因说明
3. **权限回滚**：提供快速回滚到之前权限设置的快捷方式
4. **权限预设保存**：允许用户保存自定义权限预设
5. **时间戳**：在历史记录中添加权限变更的时间戳

### 相关测试

- `permissions_selection_history_snapshot_full_access_to_default`：从 Full Access 切换回 Default
- `permissions_selection_emits_history_cell_when_selection_changes`：权限变更时生成历史记录
- `permissions_selection_emits_history_cell_when_current_is_selected`：选择当前权限也生成历史记录
- `permissions_full_access_history_cell_emitted_only_after_confirmation`：Full Access 需要确认
