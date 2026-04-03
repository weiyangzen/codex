# Approval Overlay Additional Permissions macOS Prompt Snapshot 研究文档

## 场景与职责

此快照文件是 `codex_tui` crate 中 `approval_overlay` 模块的测试快照，用于验证 **Approval Overlay** 在执行命令需要额外 macOS 权限时的 UI 渲染输出。这是 Codex TUI 安全模型的关键组件，负责向用户透明展示命令执行所需的权限，并获取用户授权。

### 业务场景
- 当 Codex 需要执行涉及 macOS 系统权限的命令时触发（如 AppleScript、系统偏好设置访问）
- 作为命令执行审批流程的一部分，在标准执行审批之上叠加额外的权限请求
- 特别针对 macOS 平台特有的权限：自动化、辅助功能、日历、提醒事项等

### 与其他 Approval 类型的区别
| 类型 | 场景 | 特殊元素 |
|------|------|---------|
| 标准 Exec | 普通命令执行 | 命令片段、原因 |
| Network | 网络访问请求 | 主机名、协议 |
| Permissions | 纯权限授予 | 无命令片段 |
| **Additional Permissions (macOS)** | **macOS 系统权限** | **Permission rule 行、macOS 特定权限** |
| Apply Patch | 文件修改 | Diff 预览 |

## 功能点目的

### 核心功能
1. **权限透明化**：清晰展示命令需要的所有 macOS 系统权限
2. **分级授权**：支持"仅一次"、"会话内允许"、"永久允许"等多种授权级别
3. **安全决策**：用户可查看权限详情后做出知情决策
4. **历史记录**：审批决策被记录到历史单元格供后续审计

### UI 元素（从快照可见）
```
Would you like to run the following command?

Reason: need macOS automation

Permission rule: macOS preferences readwrite; macOS automation com.apple.Calendar, com.apple.Notes; macOS
accessibility; macOS calendar; macOS reminders

$ osascript -e 'tell application'

› 1. Yes, proceed (y)
  2. No, and tell Codex what to do differently (esc)

Press enter to confirm or esc to cancel
```

### 权限规则格式
```
macOS preferences readwrite
macOS automation com.apple.Calendar, com.apple.Notes
macOS accessibility
macOS calendar
macOS reminders
```

## 具体技术实现

### 关键数据结构

```rust
// ApprovalRequest::Exec 变体（简化）
pub(crate) enum ApprovalRequest {
    Exec {
        thread_id: ThreadId,
        thread_label: Option<String>,
        id: String,
        command: Vec<String>,
        reason: Option<String>,
        available_decisions: Vec<ReviewDecision>,
        network_approval_context: Option<NetworkApprovalContext>,
        additional_permissions: Option<PermissionProfile>,  // macOS 权限来源
    },
    // ... 其他变体
}

// macOS 特定权限配置
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

### 权限规则格式化

```rust
pub(crate) fn format_additional_permissions_rule(
    additional_permissions: &PermissionProfile,
) -> Option<String> {
    let mut parts = Vec::new();
    
    // macOS 偏好设置
    if let Some(macos) = additional_permissions.macos.as_ref() {
        if !matches!(macos.macos_preferences, MacOsPreferencesPermission::ReadOnly) {
            let value = match macos.macos_preferences {
                MacOsPreferencesPermission::ReadOnly => "readonly",
                MacOsPreferencesPermission::ReadWrite => "readwrite",
                MacOsPreferencesPermission::None => "none",
            };
            parts.push(format!("macOS preferences {value}"));
        }
        
        // macOS 自动化
        match &macos.macos_automation {
            MacOsAutomationPermission::All => {
                parts.push("macOS automation all".to_string());
            }
            MacOsAutomationPermission::BundleIds(bundle_ids) => {
                if !bundle_ids.is_empty() {
                    parts.push(format!("macOS automation {}", bundle_ids.join(", ")));
                }
            }
            MacOsAutomationPermission::None => {}
        }
        
        // 其他布尔权限
        if macos.macos_accessibility {
            parts.push("macOS accessibility".to_string());
        }
        if macos.macos_calendar {
            parts.push("macOS calendar".to_string());
        }
        if macos.macos_reminders {
            parts.push("macOS reminders".to_string());
        }
    }
    
    if parts.is_empty() { None } else { Some(parts.join("; ")) }
}
```

### 决策选项生成

```rust
fn exec_options(
    available_decisions: &[ReviewDecision],
    network_approval_context: Option<&NetworkApprovalContext>,
    additional_permissions: Option<&PermissionProfile>,
) -> Vec<ApprovalOption> {
    available_decisions
        .iter()
        .filter_map(|decision| match decision {
            ReviewDecision::Approved => Some(ApprovalOption {
                label: "Yes, proceed".to_string(),
                decision: ApprovalDecision::Review(ReviewDecision::Approved),
                display_shortcut: None,
                additional_shortcuts: vec![key_hint::plain(KeyCode::Char('y'))],
            }),
            ReviewDecision::ApprovedForSession => Some(ApprovalOption {
                label: if additional_permissions.is_some() {
                    "Yes, and allow these permissions for this session".to_string()
                } else {
                    "Yes, and don't ask again for this command in this session".to_string()
                },
                decision: ApprovalDecision::Review(ReviewDecision::ApprovedForSession),
                additional_shortcuts: vec![key_hint::plain(KeyCode::Char('a'))],
            }),
            ReviewDecision::Abort => Some(ApprovalOption {
                label: "No, and tell Codex what to do differently".to_string(),
                decision: ApprovalDecision::Review(ReviewDecision::Abort),
                display_shortcut: Some(key_hint::plain(KeyCode::Esc)),
                additional_shortcuts: vec![key_hint::plain(KeyCode::Char('n'))],
            }),
            // ... 其他决策类型
        })
        .collect()
}
```

### 头部构建

```rust
fn build_header(request: &ApprovalRequest) -> Box<dyn Renderable> {
    match request {
        ApprovalRequest::Exec { reason, command, additional_permissions, .. } => {
            let mut header: Vec<Line<'static>> = Vec::new();
            
            if let Some(reason) = reason {
                header.push(Line::from(vec!["Reason: ".into(), reason.clone().italic()]));
                header.push(Line::from(""));
            }
            
            // 权限规则行（青色高亮）
            if let Some(additional_permissions) = additional_permissions
                && let Some(rule_line) = format_additional_permissions_rule(additional_permissions)
            {
                header.push(Line::from(vec![
                    "Permission rule: ".into(),
                    rule_line.cyan(),  // 青色高亮
                ]));
                header.push(Line::from(""));
            }
            
            // 命令片段（语法高亮）
            let full_cmd = strip_bash_lc_and_escape(command);
            let mut full_cmd_lines = highlight_bash_to_lines(&full_cmd);
            // ...
            
            Box::new(Paragraph::new(header).wrap(Wrap { trim: false }))
        }
        // ...
    }
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs:750-827` | `format_additional_permissions_rule` 函数 |
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs:660-748` | `exec_options` 函数 |
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs:516-556` | `build_header` 函数（Exec 变体） |
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs:1407-1441` | macOS 权限提示快照测试 |
| `codex-protocol/src/models.rs` | `MacOsSeatbeltProfileExtensions` 定义 |

### 相关测试用例

```rust
#[test]
fn additional_permissions_macos_prompt_snapshot() {
    let exec_request = ApprovalRequest::Exec {
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
    };
    // ... 断言快照
}
```

## 依赖与外部交互

### 权限模型依赖

```rust
// codex-protocol/src/models.rs
pub enum MacOsPreferencesPermission {
    None,
    ReadOnly,
    ReadWrite,
}

pub enum MacOsAutomationPermission {
    None,
    BundleIds(Vec<String>),  // 特定应用 Bundle ID 列表
    All,                      // 所有应用
}

pub enum MacOsContactsPermission {
    None,
    ReadOnly,
    ReadWrite,
}
```

### 事件交互

| 事件 | 方向 | 触发条件 |
|------|------|---------|
| `AppEvent::SubmitThreadOp { op: Op::ExecApproval }` | TUI → 后端 | 用户做出决策 |
| `AppEvent::InsertHistoryCell` | TUI → 历史系统 | 记录审批决策 |
| `AppEvent::FullScreenApprovalRequest` | TUI → 全屏视图 | Ctrl+A 快捷键 |

### 样式系统

```rust
// 权限规则使用青色高亮
rule_line.cyan()

// 原因使用斜体
reason.clone().italic()

// 命令使用 bash 语法高亮
highlight_bash_to_lines(&full_cmd)
```

## 风险、边界与改进建议

### 安全边界

1. **权限升级风险**: 
   - `ReadWrite` 偏好设置权限可能被滥用修改系统设置
   - `accessibility` 权限允许控制其他应用，风险较高
   - 建议：对高风险权限添加额外警告

2. **自动化权限范围**:
   - `BundleIds` 列表可能不完整，导致权限请求重复出现
   - `All` 权限过于宽泛，应尽量避免

3. **权限持久化**:
   - 用户选择"永久允许"后，权限在配置中持久化
   - 需要机制让用户查看和撤销已授予的权限

### 已知限制

1. **平台限制**: 此功能仅适用于 macOS，其他平台有各自的权限模型
2. **沙盒限制**: 在严格沙盒环境中，某些权限可能无法授予
3. **命令可见性**: 长命令可能被截断，用户无法看到完整执行内容

### 改进建议

1. **权限详情展开**: 添加选项查看每个权限的具体含义和风险
2. **权限预设**: 允许用户为常用工作流预定义权限配置
3. **审计日志**: 增强历史记录，包含权限授予的时间戳和上下文
4. **权限撤销 UI**: 在设置中添加权限管理界面
5. **风险提示分级**: 根据权限风险级别使用不同颜色（如 accessibility 用红色）

### 代码改进

```rust
// 建议：添加权限风险评级
enum PermissionRiskLevel {
    Low,      // 只读偏好设置
    Medium,   // 日历/提醒事项访问
    High,     // 辅助功能
    Critical, // 系统级写权限
}

// 根据风险级别调整 UI
fn risk_color(level: PermissionRiskLevel) -> Color {
    match level {
        PermissionRiskLevel::Low => Color::Green,
        PermissionRiskLevel::Medium => Color::Yellow,
        PermissionRiskLevel::High => Color::Red,
        PermissionRiskLevel::Critical => Color::Magenta,
    }
}
```
