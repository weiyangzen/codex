# Approval Overlay Permissions Prompt Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `approval_overlay.rs` 模块的测试快照，用于验证**独立权限请求的审批覆盖层**的渲染输出。当 Codex 需要请求额外权限（不伴随具体命令执行）时，向用户展示此界面。

### 业务场景
- 用户主动请求增加权限（如 `/allow` 命令）
- 系统检测到需要更多权限才能继续当前任务
- 预授权场景，在命令执行前获取权限

### 与 Exec 审批的区别
| 特性 | Permissions Prompt | Exec Prompt |
|------|-------------------|-------------|
| 触发条件 | 权限请求 | 命令执行 |
| 命令预览 | 无 | 有 |
| 决策类型 | PermissionGrantScope | ReviewDecision |
| 选项 | Yes/Yes for session/No | Yes/Yes for session/Abort/etc |

## 功能点目的

### 核心功能
1. **权限规则展示**：清晰列出所有请求的权限
2. **理由说明**：解释为什么需要这些权限
3. **授权范围选择**：允许选择"本次"或"本会话"授权
4. **拒绝选项**：允许继续但不授予权限

### 安全设计目标
- **明确授权范围**：用户可以选择授权的有效期
- **最小权限原则**：默认不授权，需要明确批准
- **可追溯性**：记录权限授予决策

## 具体技术实现

### 关键数据结构
```rust
pub(crate) enum ApprovalRequest {
    // ... Exec 变体
    Permissions {
        thread_id: ThreadId,
        thread_label: Option<String>,
        call_id: String,
        reason: Option<String>,
        permissions: RequestPermissionProfile,  // 请求的权限
    },
    // ... 其他变体
}

pub struct RequestPermissionProfile {
    pub network: Option<NetworkPermissions>,
    pub file_system: Option<FileSystemPermissions>,
}

pub enum PermissionGrantScope {
    Turn,    // 仅本次
    Session, // 本会话
}
```

### 选项生成
```rust
fn permissions_options() -> Vec<ApprovalOption> {
    vec![
        ApprovalOption {
            label: "Yes, grant these permissions".to_string(),
            decision: ApprovalDecision::Review(ReviewDecision::Approved),
            display_shortcut: None,
            additional_shortcuts: vec![key_hint::plain(KeyCode::Char('y'))],
        },
        ApprovalOption {
            label: "Yes, grant these permissions for this session".to_string(),
            decision: ApprovalDecision::Review(ReviewDecision::ApprovedForSession),
            display_shortcut: None,
            additional_shortcuts: vec![key_hint::plain(KeyCode::Char('a'))],
        },
        ApprovalOption {
            label: "No, continue without permissions".to_string(),
            decision: ApprovalDecision::Review(ReviewDecision::Denied),
            display_shortcut: None,
            additional_shortcuts: vec![key_hint::plain(KeyCode::Char('n'))],
        },
    ]
}
```

### 决策处理
```rust
fn handle_permissions_decision(
    &self,
    call_id: &str,
    permissions: &RequestPermissionProfile,
    decision: ReviewDecision,
) {
    let granted_permissions = match decision {
        ReviewDecision::Approved | ReviewDecision::ApprovedForSession => permissions.clone(),
        ReviewDecision::Denied | ReviewDecision::Abort => Default::default(),
        _ => Default::default(),
    };
    
    let scope = if matches!(decision, ReviewDecision::ApprovedForSession) {
        PermissionGrantScope::Session
    } else {
        PermissionGrantScope::Turn
    };
    
    // 发送历史记录
    if request.thread_label().is_none() {
        let message = if granted_permissions.is_empty() {
            "You did not grant additional permissions"
        } else if matches!(scope, PermissionGrantScope::Session) {
            "You granted additional permissions for this session"
        } else {
            "You granted additional permissions"
        };
        self.app_event_tx.send(AppEvent::InsertHistoryCell(/* ... */));
    }
    
    // 发送权限响应
    let thread_id = request.thread_id();
    self.app_event_tx.request_permissions_response(
        thread_id,
        call_id.to_string(),
        RequestPermissionsResponse {
            permissions: granted_permissions,
            scope,
        },
    );
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/approval_overlay.rs`
- **测试函数**: `permissions_prompt_snapshot` (行 1382-1391)
- **测试函数**: `permissions_session_shortcut_submits_session_scope` (行 1276-1301)

### 测试参数
```rust
ApprovalRequest::Permissions {
    thread_id: ThreadId::new(),
    thread_label: None,
    call_id: "test".to_string(),
    reason: Some("need workspace access".to_string()),
    permissions: RequestPermissionProfile {
        network: Some(NetworkPermissions {
            enabled: Some(true),
        }),
        file_system: Some(FileSystemPermissions {
            read: Some(vec![absolute_path("/tmp/readme.txt")]),
            write: Some(vec![absolute_path("/tmp/out.txt")]),
        }),
    },
}
```

## 依赖与外部交互

### 内部依赖
- `codex_protocol::request_permissions::RequestPermissionProfile` - 权限请求配置
- `codex_protocol::request_permissions::PermissionGrantScope` - 授权范围
- `codex_protocol::request_permissions::RequestPermissionsResponse` - 权限响应

### 外部交互
- **权限管理器**: 处理权限授予和验证
- **历史记录系统**: 记录权限决策

## 风险、边界与改进建议

### 潜在风险
1. **权限范围混淆**: 用户可能不理解"本次"和"本会话"的区别
2. **权限累积**: 多次授予的权限可能累积，超出用户预期
3. **会话边界模糊**: 用户可能不清楚"本会话"何时结束

### 边界情况
1. **空权限请求**: 请求空权限集时的处理
2. **重复请求**: 对已授权权限的重复请求
3. **权限撤销**: 会话中无法撤销已授予的权限

### 改进建议
1. **权限可视化**: 显示当前已授予的所有权限
2. **会话计时器**: 显示本会话剩余时间或已持续时间
3. **权限解释**: 为每个权限添加详细说明
4. **撤销功能**: 添加撤销已授予权限的选项
5. **权限继承**: 明确子任务是否继承父任务权限

### 测试覆盖
- 权限提示: `permissions_prompt_snapshot`
- 会话范围快捷键: `permissions_session_shortcut_submits_session_scope`
- 选项标签: `permissions_options_use_expected_labels`

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/approval_overlay.rs`
- 权限请求协议: `codex-rs/protocol/src/request_permissions.rs`
