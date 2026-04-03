# 权限选择历史从完全访问到默认测试研究文档

## 场景与职责

该 snapshot 测试验证当用户从 "Full Access"（完全访问）权限模式切换回 "Default"（默认）模式时，tui_app_server 的 ChatWidget 能够在历史记录中正确显示权限更新信息。

**测试场景**：
1. 用户当前处于 Full Access 权限模式（最宽松的权限）
2. 用户打开权限选择弹出框
3. 用户导航并选择 Default 权限模式
4. 确认选择后，系统在历史记录中显示权限更新消息

**职责**：确保从高权限模式降级到低权限模式时，用户得到明确的反馈，历史记录中保留这一重要的安全相关变更。

## 功能点目的

- **安全反馈**：当用户降低权限级别时提供明确的视觉确认
- **审计追踪**：记录从高权限到低权限的变更，便于安全审计
- **状态同步**：确保 UI 显示与实际权限配置一致
- **降级确认**：确认用户有意降低权限级别

## 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/chatwidget/tests.rs` 第 9145-9183 行

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
    chat.config
        .permissions
        .approval_policy
        .set(AskForApproval::Never)
        .expect("set approval policy");
    chat.config.permissions.sandbox_policy =
        Constrained::allow_any(SandboxPolicy::DangerFullAccess);

    chat.open_permissions_popup();
    let popup = render_bottom_popup(&chat, 120);
    chat.handle_key_event(KeyEvent::from(KeyCode::Up));
    if popup.contains("Guardian Approvals") {
        chat.handle_key_event(KeyEvent::from(KeyCode::Up));
    }
    chat.handle_key_event(KeyEvent::from(KeyCode::Enter));

    let cells = drain_insert_history(&mut rx);
    assert_eq!(cells.len(), 1, "expected one mode-switch history cell");
    #[cfg(target_os = "windows")]
    insta::with_settings!({ snapshot_suffix => "windows" }, {
        assert_snapshot!(
            "permissions_selection_history_full_access_to_default",
            lines_to_single_string(&cells[0])
        );
    });
    #[cfg(not(target_os = "windows"))]
    assert_snapshot!(
        "permissions_selection_history_full_access_to_default",
        lines_to_single_string(&cells[0])
    );
}
```

### 关键实现细节

1. **初始状态设置**：
   - 设置审批策略为 `Never`（从不询问）
   - 设置沙箱策略为 `DangerFullAccess`（完全访问）
   - 使用 `Constrained::allow_any` 允许任何沙箱策略

2. **平台特定配置**：
   - Windows 平台：隐藏世界可写警告，设置非提升沙箱模式
   - 隐藏完全访问警告

3. **导航逻辑**：
   - 打开权限弹出框
   - 检查是否包含 "Guardian Approvals" 选项
   - 如果包含，需要额外按 Up 键跳过
   - 按 Up 键导航到 Default 选项
   - 按 Enter 确认选择

4. **Snapshot 平台区分**：
   - Windows 平台使用 `snapshot_suffix => "windows"` 生成独立的 snapshot
   - 非 Windows 平台使用标准 snapshot 名称

### Snapshot 输出内容（非 Windows）

```
• Permissions updated to Default
```

### Snapshot 输出内容（Windows）

```
• Permissions updated to Default (non-admin sandbox)
```

## 关键代码路径与文件引用

### 主要代码文件

1. **测试文件**：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
   - 测试函数：`permissions_selection_history_snapshot_full_access_to_default` (第 9145 行)

2. **ChatWidget 实现**：`codex-rs/tui_app_server/src/chatwidget/mod.rs`
   - 方法：`open_permissions_popup`
   - 权限处理逻辑

3. **权限配置**：`codex-core/src/config/types.rs`
   - `SandboxPolicy`：沙箱策略定义
   - `AskForApproval`：审批策略定义
   - `Constrained`：受约束配置包装器

4. **历史记录单元格**：`codex-rs/tui_app_server/src/history_cell/mod.rs`
   - 历史记录单元格渲染

### 相关协议类型

- `SandboxPolicy::DangerFullAccess`：完全访问模式，无沙箱限制
- `AskForApproval::Never`：从不询问审批
- `Constrained<T>`：包装配置值并允许约束验证

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

| 平台 | 特殊处理 |
|------|----------|
| Windows | 显示 "(non-admin sandbox)" 后缀，使用独立的 snapshot 文件 |
| 非 Windows | 标准 "Default" 显示 |

## 风险、边界与改进建议

### 潜在风险

1. **权限降级遗漏**：用户可能无意中降低权限，导致后续操作失败
2. **平台差异维护**：Windows 和非 Windows 的不同输出需要分别维护
3. **导航复杂性**：Guardian Approvals 功能的存在改变了导航路径

### 边界情况

1. **Guardian Approvals 影响**：如果启用了 Guardian Approvals，权限列表会变化，导航逻辑需要调整
2. **配置约束**：某些配置可能限制可用的权限选项
3. **Windows 沙箱模式**：不同的 Windows 沙箱模式会影响显示文本

### 改进建议

1. **权限变更确认**：对于从高权限到低权限的变更，考虑添加额外确认步骤
2. **影响提示**：在权限变更历史中显示可能的影响（如"某些操作可能需要额外确认"）
3. **快速恢复**：提供快速恢复到之前权限设置的选项
4. **权限对比**：显示新旧权限的对比，帮助用户理解变更
5. **批量变更警告**：如果权限变更会影响多个正在进行的任务，提前警告用户

### 相关测试

- `permissions_selection_history_after_mode_switch`：一般模式切换测试
- `permissions_selection_emits_history_cell_when_selection_changes`：权限变更历史记录测试
- `permissions_selection_can_disable_guardian_approvals`：禁用 Guardian Approvals 测试
- `permissions_selection_history_full_access_to_default@windows`：Windows 平台特定测试
