# Approval Overlay Permissions Prompt Snapshot 研究文档

## 场景与职责

此快照文件是 `codex_tui` crate 中 `approval_overlay` 模块的测试快照，用于验证 **Approval Overlay** 在纯权限请求场景下的 UI 渲染输出。与命令执行审批不同，此场景专门处理独立的权限授予请求，不涉及具体命令的执行。

### 业务场景
- 当 Codex 需要请求额外权限以继续任务，但不执行具体命令时触发
- 通常发生在任务执行过程中，发现需要更多权限才能完成
- 用户可以选择授予权限、仅会话内授予，或拒绝继续

### 与 Exec 审批的区别
| 维度 | Permissions | Exec |
|------|-------------|------|
| 标题 | "Would you like to grant these permissions?" | "Would you like to run the following command?" |
| 命令片段 | 无 | 有 |
| 决策选项 | Yes / Yes for session / No without | Yes / Yes for session / Abort |
| 用途 | 纯权限授予 | 命令执行 + 权限 |

## 功能点目的

### 核心功能
1. **权限请求展示**：清晰展示请求的具体权限内容
2. **分级授权**：支持"授予"、"会话内授予"、"拒绝"三种选择
3. **权限范围控制**：用户可以控制权限的有效期
4. **历史记录**：记录权限授予决策到历史单元格

### UI 元素（从快照可见）
```
Would you like to grant these permissions?

Reason: need workspace access

Permission rule: network; read `/tmp/readme.txt`; write `/tmp/out.txt`

› 1. Yes, grant these permissions (y)
  2. Yes, grant these permissions for this session (a)
  3. No, continue without permissions (n)

Press enter to confirm or esc to cancel
```

### 决策选项
| 选项 | 快捷键 | 决策类型 | 效果 |
|------|--------|---------|------|
| Yes, grant these permissions | y | `ReviewDecision::Approved` | 永久授予 |
| Yes, grant these permissions for this session | a | `ReviewDecision::ApprovedForSession` | 仅当前会话 |
| No, continue without permissions | n | `ReviewDecision::Denied` | 拒绝，继续执行 |

## 具体技术实现

### 关键数据结构

```rust
// ApprovalRequest::Permissions 变体
pub(crate) enum ApprovalRequest {
    Permissions {
        thread_id: ThreadId,
        thread_label: Option<String>,
        call_id: String,           // 权限请求的唯一标识
        reason: Option<String>,
        permissions: RequestPermissionProfile,  // 请求的权限
    },
    // ... 其他变体
}

// 请求权限配置
pub struct RequestPermissionProfile {
    pub network: Option<NetworkPermissions>,
    pub file_system: Option<FileSystemPermissions>,
}
```

### 权限选项生成

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

### 头部构建

```rust
fn build_header(request: &ApprovalRequest) -> Box<dyn Renderable> {
    match request {
        ApprovalRequest::Permissions { thread_label, reason, permissions, .. } => {
            let mut header: Vec<Line<'static>> = Vec::new();
            
            // 线程标签（如果跨线程）
            if let Some(thread_label) = thread_label {
                header.push(Line::from(vec![
                    "Thread: ".into(),
                    thread_label.clone().bold(),
                ]));
                header.push(Line::from(""));
            }
            
            // 原因
            if let Some(reason) = reason {
                header.push(Line::from(vec!["Reason: ".into(), reason.clone().italic()]));
                header.push(Line::from(""));
            }
            
            // 权限规则（复用 format_additional_permissions_rule）
            if let Some(rule_line) = format_requested_permissions_rule(permissions) {
                header.push(Line::from(vec![
                    "Permission rule: ".into(),
                    rule_line.cyan(),
                ]));
            }
            
            Box::new(Paragraph::new(header).wrap(Wrap { trim: false }))
        }
        // ...
    }
}
```

### 权限决策处理

```rust
fn handle_permissions_decision(
    &self,
    call_id: &str,
    permissions: &RequestPermissionProfile,
    decision: ReviewDecision,
) {
    let Some(request) = self.current_request.as_ref() else { return; };
    
    // 根据决策确定授予的权限
    let granted_permissions = match decision {
        ReviewDecision::Approved | ReviewDecision::ApprovedForSession => permissions.clone(),
        ReviewDecision::Denied | ReviewDecision::Abort => Default::default(),
        _ => Default::default(),
    };
    
    // 确定权限范围
    let scope = if matches!(decision, ReviewDecision::ApprovedForSession) {
        PermissionGrantScope::Session
    } else {
        PermissionGrantScope::Turn
    };
    
    // 记录到历史（仅非跨线程）
    if request.thread_label().is_none() {
        let message = if granted_permissions.is_empty() {
            "You did not grant additional permissions"
        } else if matches!(scope, PermissionGrantScope::Session) {
            "You granted additional permissions for this session"
        } else {
            "You granted additional permissions"
        };
        self.app_event_tx.send(AppEvent::InsertHistoryCell(Box::new(
            PlainHistoryCell::new(vec![message.into()]),
        )));
    }
    
    // 发送权限响应
    let thread_id = request.thread_id();
    self.app_event_tx.send(AppEvent::SubmitThreadOp {
        thread_id,
        op: Op::RequestPermissionsResponse {
            id: call_id.to_string(),
            response: RequestPermissionsResponse {
                permissions: granted_permissions,
                scope,
            },
        },
    });
}
```

### 权限规则格式化适配

```rust
pub(crate) fn format_requested_permissions_rule(
    permissions: &RequestPermissionProfile,
) -> Option<String> {
    // 复用 format_additional_permissions_rule，将 RequestPermissionProfile 转换为 PermissionProfile
    format_additional_permissions_rule(&permissions.clone().into())
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs:59-66` | `ApprovalRequest::Permissions` 定义 |
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs:858-879` | `permissions_options` 函数 |
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs:557-582` | Permissions 头部构建 |
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs:277-320` | `handle_permissions_decision` 方法 |
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs:829-833` | `format_requested_permissions_rule` 函数 |
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs:1396-1406` | 权限提示快照测试 |

### 相关测试用例

```rust
#[test]
fn permissions_prompt_snapshot() {
    let (tx, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx);
    let view = ApprovalOverlay::new(
        make_permissions_request(),  // 创建 Permissions 请求
        tx,
        Features::with_defaults(),
    );
    assert_snapshot!(
        "approval_overlay_permissions_prompt",
        normalize_snapshot_paths(render_overlay_lines(&view, 120))
    );
}

#[test]
fn permissions_session_shortcut_submits_session_scope() {
    let (tx, mut rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx);
    let mut view = ApprovalOverlay::new(make_permissions_request(), tx, Features::with_defaults());

    view.handle_key_event(KeyEvent::new(KeyCode::Char('a'), KeyModifiers::NONE));

    // 验证发送了 Session 范围的响应
    while let Ok(ev) = rx.try_recv() {
        if let AppEvent::SubmitThreadOp {
            op: Op::RequestPermissionsResponse { response, .. },
            ..
        } = ev
        {
            assert_eq!(response.scope, PermissionGrantScope::Session);
            // ...
        }
    }
}
```

## 依赖与外部交互

### 权限范围枚举

```rust
// codex-protocol/src/request_permissions.rs
pub enum PermissionGrantScope {
    Turn,     // 仅当前回合
    Session,  // 当前会话
}

pub struct RequestPermissionsResponse {
    pub permissions: RequestPermissionProfile,
    pub scope: PermissionGrantScope,
}
```

### 事件交互

| 事件 | 方向 | 说明 |
|------|------|------|
| `AppEvent::SubmitThreadOp { op: Op::RequestPermissionsResponse }` | TUI → 后端 | 发送权限响应 |
| `AppEvent::InsertHistoryCell` | TUI → 历史 | 记录权限决策 |

### 历史消息格式

| 决策 | 历史消息 |
|------|---------|
| Approved | "You granted additional permissions" |
| ApprovedForSession | "You granted additional permissions for this session" |
| Denied | "You did not grant additional permissions" |

## 风险、边界与改进建议

### 安全边界

1. **权限范围混淆**:
   - 用户可能不理解 "Turn" 和 "Session" 的区别
   - 建议添加工具提示或帮助文本解释权限范围

2. **权限累积**:
   - 多次授予权限可能导致权限范围不断扩大
   - 建议提供权限审计功能

3. **拒绝后行为**:
   - 拒绝权限后任务可能失败，但用户可能不理解原因
   - 建议添加解释性文本说明拒绝的后果

### 用户体验边界

1. **权限描述可读性**:
   - 技术路径（如 `/tmp/readme.txt`）可能对用户不够友好
   - 建议添加人类可读的描述

2. **频繁请求**:
   - 如果任务需要多次权限请求，用户体验会下降
   - 建议批量权限请求

3. **上下文缺失**:
   - 用户可能不理解为什么需要这些权限
   - 建议添加更详细的 "Reason" 说明

### 改进建议

1. **权限预览**:
   ```rust
   // 显示权限可能访问的具体内容预览
   fn preview_permission_access(permissions: &RequestPermissionProfile) -> Vec<String> {
       // 例如：显示文件内容预览、网络请求目标等
   }
   ```

2. **权限模板**:
   - 预定义常用权限组合（如"Web 开发"、"数据分析"）
   - 用户可以一键授予一组相关权限

3. **权限过期提醒**:
   - Session 权限在会话结束时提醒用户
   - 提供快速重新授权选项

4. **权限使用统计**:
   - 显示权限实际使用频率
   - 帮助用户做出知情决策

5. **智能权限建议**:
   - 根据任务类型自动建议合适的权限范围
   - 减少用户决策负担

```rust
// 建议添加权限建议
fn suggest_permission_scope(task_type: &str) -> PermissionGrantScope {
    match task_type {
        "one-time-analysis" => PermissionGrantScope::Turn,
        "long-running-session" => PermissionGrantScope::Session,
        _ => PermissionGrantScope::Turn,  // 默认保守
    }
}
```
