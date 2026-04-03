# Approval Overlay Additional Permissions macOS Prompt Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `approval_overlay.rs` 模块的测试快照，用于验证**macOS 额外权限请求的审批覆盖层**的渲染输出。当 Codex 需要访问 macOS 系统功能（如自动化、辅助功能、日历等）时，向用户展示此界面。

### 业务场景
- 执行需要控制其他 macOS 应用的 AppleScript（如 `osascript`）
- 需要访问 macOS 系统偏好设置
- 需要访问日历、提醒事项、通讯录等系统数据
- 需要辅助功能权限以控制 UI

### 权限类型展示
该快照展示了以下 macOS 权限组合：
- `macOS preferences readwrite` - 系统偏好设置读写
- `macOS automation com.apple.Calendar, com.apple.Notes` - 控制特定应用
- `macOS accessibility` - 辅助功能
- `macOS calendar` - 日历访问
- `macOS reminders` - 提醒事项访问

## 功能点目的

### 核心功能
1. **命令预览**：展示将要执行的命令（`$ osascript -e 'tell application'`）
2. **权限规则展示**：清晰列出所有请求的权限
3. **理由说明**：解释为什么需要这些权限（"need macOS automation"）
4. **用户决策**：提供批准或拒绝的选项

### 安全设计目标
- **透明度**：用户必须明确知道哪些系统功能将被访问
- **最小权限**：只请求完成任务所需的具体权限
- **可追溯性**：所有权限请求都有理由说明

## 具体技术实现

### 关键数据结构
```rust
pub(crate) enum ApprovalRequest {
    Exec {
        thread_id: ThreadId,
        thread_label: Option<String>,
        id: String,
        command: Vec<String>,
        reason: Option<String>,
        available_decisions: Vec<ReviewDecision>,
        network_approval_context: Option<NetworkApprovalContext>,
        additional_permissions: Option<PermissionProfile>,  // macOS 权限在这里
    },
    // ... 其他变体
}

// macOS 特定权限结构
pub struct MacOsSeatbeltProfileExtensions {
    pub macos_preferences: MacOsPreferencesPermission,  // ReadOnly/ReadWrite/None
    pub macos_automation: MacOsAutomationPermission,    // All/BundleIds/None
    pub macos_launch_services: bool,
    pub macos_accessibility: bool,
    pub macos_calendar: bool,
    pub macos_reminders: bool,
    pub macos_contacts: MacOsContactsPermission,
}
```

### 权限格式化
```rust
pub(crate) fn format_additional_permissions_rule(
    additional_permissions: &PermissionProfile,
) -> Option<String> {
    let mut parts = Vec::new();
    
    // macOS 权限处理
    if let Some(macos) = additional_permissions.macos.as_ref() {
        // 偏好设置
        if !matches!(macos.macos_preferences, MacOsPreferencesPermission::ReadOnly) {
            parts.push(format!("macOS preferences {value}"));
        }
        
        // 自动化
        match &macos.macos_automation {
            MacOsAutomationPermission::All => {
                parts.push("macOS automation all".to_string());
            }
            MacOsAutomationPermission::BundleIds(bundle_ids) => {
                parts.push(format!("macOS automation {}", bundle_ids.join(", ")));
            }
            MacOsAutomationPermission::None => {}
        }
        
        // 其他权限标志
        if macos.macos_accessibility { parts.push("macOS accessibility".to_string()); }
        if macos.macos_calendar { parts.push("macOS calendar".to_string()); }
        if macos.macos_reminders { parts.push("macOS reminders".to_string()); }
    }
    
    Some(parts.join("; "))
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/approval_overlay.rs`
- **测试函数**: `additional_permissions_macos_prompt_snapshot` (行 1393-1427)
- **权限格式化**: `format_additional_permissions_rule` (行 736-813)

### 测试参数
```rust
ApprovalRequest::Exec {
    thread_id: ThreadId::new(),
    thread_label: None,
    id: "test".into(),
    command: vec!["osascript".into(), "-e".into(), "tell application".into()],
    reason: Some("need macOS automation".into()),
    available_decisions: vec![ReviewDecision::Approved, ReviewDecision::Abort],
    network_approval_context: None,
    additional_permissions: Some(PermissionProfile {
        macos: Some(MacOsSeatbeltProfileExtensions {
            macos_preferences: MacOsPreferencesPermission::ReadWrite,
            macos_automation: MacOsAutomationPermission::BundleIds(vec![
                "com.apple.Calendar".to_string(),
                "com.apple.Notes".to_string(),
            ]),
            macos_launch_services: false,
            macos_accessibility: true,
            macos_calendar: true,
            macos_reminders: true,
            macos_contacts: MacOsContactsPermission::None,
        }),
        ..Default::default()
    }),
}
```

## 依赖与外部交互

### 内部依赖
- `codex_protocol::models::MacOsSeatbeltProfileExtensions` - macOS 权限模型
- `codex_protocol::models::MacOsPreferencesPermission` - 偏好设置权限枚举
- `codex_protocol::models::MacOsAutomationPermission` - 自动化权限枚举
- `codex_protocol::models::MacOsContactsPermission` - 通讯录权限枚举

### 外部交互
- **Seatbelt**: macOS 沙盒系统，实际执行权限控制
- **Launch Services**: 用于应用间通信
- **TCC (Transparency, Consent, and Control)**: macOS 隐私保护框架

### 权限映射
```
MacOsPreferencesPermission::ReadWrite → "macOS preferences readwrite"
MacOsAutomationPermission::BundleIds([...]) → "macOS automation {bundle_ids}"
macos_accessibility: true → "macOS accessibility"
macos_calendar: true → "macOS calendar"
macos_reminders: true → "macOS reminders"
```

## 风险、边界与改进建议

### 潜在风险
1. **权限升级攻击**: 恶意 prompt 可能尝试通过社会工程学诱导用户批准危险权限
2. **权限持久化**: 批准的权限可能在会话结束后仍然有效，取决于具体实现
3. **用户体验**: 频繁的权限请求可能导致用户疲劳，习惯性点击"批准"

### 边界情况
1. **权限组合复杂性**: 当同时请求文件系统、网络和 macOS 权限时，显示可能过长
2. **Bundle ID 长度**: 大量或长 Bundle ID 可能导致权限规则行过长
3. **无权限场景**: `format_additional_permissions_rule` 返回 `None` 时不显示权限行

### 改进建议
1. **权限分组显示**: 将相关权限分组，使用图标或颜色区分
2. **风险评级**: 根据权限敏感度添加风险指示（如 🔴 高风险）
3. **权限解释**: 为每个权限添加悬停/展开说明，解释具体用途
4. **时间限制**: 添加"仅本次会话"选项，限制权限有效期
5. **审计日志**: 记录所有权限批准事件，便于后续审计

### 测试覆盖
- macOS 权限格式化: `additional_permissions_macos_prompt_snapshot`
- 文件系统+网络权限: `additional_permissions_prompt_snapshot`
- 权限规则行显示: `additional_permissions_prompt_shows_permission_rule_line`

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/approval_overlay.rs`
- 权限模型: `codex-rs/protocol/src/models/mod.rs` 或相关文件
- Seatbelt 集成: `codex-rs/core/src/seatbelt.rs`（如果存在）
