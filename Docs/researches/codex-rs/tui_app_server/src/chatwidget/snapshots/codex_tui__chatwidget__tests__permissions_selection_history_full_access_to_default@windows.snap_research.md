# Permissions Selection History Full Access To Default (Windows) Snapshot Research

## 场景与职责

该 snapshot 测试验证 Windows 平台上从 "Full Access" 权限模式切换回 "Default" 模式时的历史记录通知消息。Windows 平台有特殊的沙箱处理逻辑，因此权限模式的显示名称和描述与非 Windows 平台有所不同。

**测试场景**：
- Windows 平台用户当前处于 "Full Access" 模式
- 用户切换回 "Default" 模式
- 系统在历史记录中显示带有 Windows 特定后缀的权限更新消息

## 功能点目的

1. **平台特定提示**：Windows 用户需要了解非管理员沙箱的限制
2. **安全边界明确**：明确告知用户当前处于降级沙箱模式
3. **升级路径提示**：暗示用户可以通过 `/setup-default-sandbox` 升级到完整沙箱

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
    chat.config.permissions.approval_policy
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
}
```

### Windows 特定配置
```rust
#[cfg(target_os = "windows")]
{
    chat.config.notices.hide_world_writable_warning = Some(true);
    chat.set_windows_sandbox_mode(Some(WindowsSandboxModeToml::Unelevated));
}
```

### Snapshot 内容（Windows 平台）
```
• Permissions updated to Default (non-admin sandbox)
```

### Windows 沙箱级别
**文件**：`codex-rs/core/src/windows_sandbox.rs`

```rust
pub enum WindowsSandboxLevel {
    Disabled,         // 沙箱完全禁用
    RestrictedToken,  // 受限令牌模式（非管理员）
    Elevated,         // 提升权限模式（完整沙箱）
}
```

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs:8136-8142` | Windows 沙箱级别检测 |
| `codex-rs/tui_app_server/src/chatwidget.rs:8162-8166` | "Default (non-admin sandbox)" 标签生成 |
| `codex-rs/tui_app_server/src/chatwidget.rs:8144-8146` | 升级提示显示条件判断 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs:9144-9183` | 测试用例实现 |
| `codex-rs/core/src/windows_sandbox.rs` | Windows 沙箱实现 |

### Windows 特定标签逻辑
**文件**：`codex-rs/tui_app_server/src/chatwidget.rs` (约第 8162-8166 行)

```rust
let base_name = if preset.id == "auto" && windows_degraded_sandbox_enabled {
    "Default (non-admin sandbox)".to_string()
} else {
    preset.label.to_string()
};
```

### 升级提示逻辑
**文件**：`codex-rs/tui_app_server/src/chatwidget.rs` (约第 8144-8146 行)

```rust
let show_elevate_sandbox_hint = codex_core::windows_sandbox::ELEVATED_SANDBOX_NUX_ENABLED
    && windows_degraded_sandbox_enabled
    && presets.iter().any(|preset| preset.id == "auto");
```

## 依赖与外部交互

### 依赖模块
1. **WindowsSandboxLevel**：Windows 沙箱级别枚举
2. **WindowsSandboxModeToml**：配置中的 Windows 沙箱模式
3. **ELEVATED_SANDBOX_NUX_ENABLED**：功能标志，控制升级提示显示
4. **ELEVATED_SANDBOX_NUX_ENABLED**：功能标志，控制升级提示显示

### Windows 平台差异
| 特性 | Windows | 其他平台 |
|------|---------|----------|
| 沙箱实现 | Windows 特定令牌限制 | Seatbelt (macOS) / Landlock (Linux) |
| 降级模式显示 | "Default (non-admin sandbox)" | "Default" |
| 升级提示 | 显示 `/setup-default-sandbox` 提示 | 无 |
| Read-only 预设 | 可用 | 不可用 |

### 事件流（Windows）
```
设置 Windows 沙箱为 Unelevated 模式
    ↓
打开权限选择弹出框
    ↓
检测到 windows_degraded_sandbox_enabled = true
    ↓
Default 预设显示为 "Default (non-admin sandbox)"
    ↓
显示升级提示（如果启用）
    ↓
用户选择 Default
    ↓
历史记录显示 "Permissions updated to Default (non-admin sandbox)"
```

## 风险、边界与改进建议

### 潜在风险
1. **用户困惑**："non-admin sandbox" 术语可能让普通用户困惑
2. **功能限制**：降级沙箱可能限制某些功能（如网络访问）
3. **升级复杂性**：升级到完整沙箱需要额外步骤

### 边界情况
1. **管理员权限**：如果用户以管理员身份运行，沙箱行为不同
2. **企业环境**：组策略可能限制沙箱配置
3. **防病毒软件**：某些防病毒软件可能干扰沙箱操作

### 改进建议
1. **帮助链接**：在提示中添加指向文档的链接，解释 "non-admin sandbox" 含义
2. **一键升级**：提供一键执行 `/setup-default-sandbox` 的按钮
3. **功能对比表**：显示降级沙箱与完整沙箱的功能差异
4. **智能推荐**：根据用户操作模式推荐合适的沙箱级别
5. **升级向导**：提供交互式向导引导用户完成沙箱升级

### 相关测试
- `permissions_selection_history_full_access_to_default`：非 Windows 平台版本
- `approvals_selection_popup@windows`：Windows 平台的权限选择弹出框测试

### 代码维护注意
当修改 Windows 沙箱相关逻辑时，需要同时更新：
1. 显示标签逻辑（`base_name` 生成）
2. 升级提示逻辑
3. 相关的 snapshot 测试
4. 文档字符串和用户可见消息

### 平台特定测试配置
```rust
#[cfg(target_os = "windows")]
insta::with_settings!({ snapshot_suffix => "windows" }, {
    assert_snapshot!(...);
});
```

使用 `insta::with_settings!` 宏为 Windows 平台生成带 `@windows` 后缀的 snapshot 文件。
