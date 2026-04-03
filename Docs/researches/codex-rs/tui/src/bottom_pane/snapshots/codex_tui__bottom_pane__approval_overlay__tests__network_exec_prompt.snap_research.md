# Approval Overlay Network Exec Prompt Snapshot 研究文档

## 场景与职责

此快照文件是 `codex_tui` crate 中 `approval_overlay` 模块的测试快照，用于验证 **Approval Overlay** 在网络访问请求场景下的 UI 渲染输出。这是 Codex TUI 网络安全模型的关键组件，负责向用户透明展示网络访问请求，并获取用户授权。

### 业务场景
- 当 Codex 需要执行涉及网络访问的命令时触发（如 curl、wget、API 调用）
- 作为命令执行审批流程的一部分，专门针对网络访问的特殊处理
- 支持一次性授权、会话内授权、永久授权（按主机）和拒绝等多种选项

### 与标准 Exec 审批的区别
| 维度 | Network Exec | 标准 Exec |
|------|-------------|-----------|
| 标题 | "Do you want to approve network access to \"{host}\"?" | "Would you like to run the following command?" |
| 命令显示 | 不显示命令片段 | 显示命令片段 |
| 选项标签 | "Yes, just this once" | "Yes, proceed" |
| 持久化选项 | 支持按主机永久授权 | 支持按命令前缀授权 |

## 功能点目的

### 核心功能
1. **网络访问透明化**：清晰展示请求访问的目标主机
2. **分级授权**：支持四种授权级别：
   - 仅一次 (`y`)
   - 会话内允许 (`a`)
   - 永久允许该主机 (`p`)
   - 拒绝 (`esc`/`n`)
3. **主机隔离**：授权按主机名隔离，不同主机需要单独授权
4. **策略持久化**：用户选择"永久允许"会更新网络策略配置

### UI 元素（从快照可见）
```
Do you want to approve network access to "example.com"?

Reason: network request blocked

› 1. Yes, just this once (y)
  2. Yes, and allow this host for this conversation (a)
  3. Yes, and allow this host in the future (p)
  4. No, and tell Codex what to do differently (esc)

Press enter to confirm or esc to cancel
```

### 样式信息（从 Buffer 输出）
- 区域大小: 100x12
- 标题使用默认前景色 + 粗体
- 原因使用斜体 (`ITALIC` modifier)
- 选中项使用青色 (`Cyan`) + 粗体
- 快捷键提示使用暗淡 (`DIM`) 样式

## 具体技术实现

### 关键数据结构

```rust
// ApprovalRequest::Exec 中的网络相关字段
pub(crate) enum ApprovalRequest {
    Exec {
        thread_id: ThreadId,
        thread_label: Option<String>,
        id: String,
        command: Vec<String>,
        reason: Option<String>,
        available_decisions: Vec<ReviewDecision>,
        network_approval_context: Option<NetworkApprovalContext>,  // 网络上下文
        additional_permissions: Option<PermissionProfile>,
    },
    // ...
}

// 网络审批上下文
pub struct NetworkApprovalContext {
    pub host: String,       // 目标主机名
    pub protocol: NetworkApprovalProtocol,  // 协议（Http/Https）
}

pub enum NetworkApprovalProtocol {
    Http,
    Https,
}
```

### 标题生成

```rust
fn build_options(
    request: &ApprovalRequest,
    header: Box<dyn Renderable>,
    _features: &Features,
) -> (Vec<ApprovalOption>, SelectionViewParams) {
    let (options, title) = match request {
        ApprovalRequest::Exec {
            available_decisions,
            network_approval_context,
            additional_permissions,
            ..
        } => (
            exec_options(
                available_decisions,
                network_approval_context.as_ref(),
                additional_permissions.as_ref(),
            ),
            network_approval_context.as_ref().map_or_else(
                || "Would you like to run the following command?".to_string(),
                |network_approval_context| {
                    format!(
                        "Do you want to approve network access to \"{}\"?",
                        network_approval_context.host
                    )
                },
            ),
        ),
        // ...
    };
    // ...
}
```

### 网络特定选项

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
                label: if network_approval_context.is_some() {
                    "Yes, just this once".to_string()
                } else {
                    "Yes, proceed".to_string()
                },
                decision: ApprovalDecision::Review(ReviewDecision::Approved),
                display_shortcut: None,
                additional_shortcuts: vec![key_hint::plain(KeyCode::Char('y'))],
            }),
            ReviewDecision::ApprovedForSession => Some(ApprovalOption {
                label: if network_approval_context.is_some() {
                    "Yes, and allow this host for this conversation".to_string()
                } else if additional_permissions.is_some() {
                    "Yes, and allow these permissions for this session".to_string()
                } else {
                    "Yes, and don't ask again for this command in this session".to_string()
                },
                decision: ApprovalDecision::Review(ReviewDecision::ApprovedForSession),
                display_shortcut: None,
                additional_shortcuts: vec![key_hint::plain(KeyCode::Char('a'))],
            }),
            ReviewDecision::NetworkPolicyAmendment { network_policy_amendment } => {
                let (label, shortcut) = match network_policy_amendment.action {
                    NetworkPolicyRuleAction::Allow => (
                        "Yes, and allow this host in the future".to_string(),
                        KeyCode::Char('p'),
                    ),
                    NetworkPolicyRuleAction::Deny => (
                        "No, and block this host in the future".to_string(),
                        KeyCode::Char('d'),
                    ),
                };
                Some(ApprovalOption {
                    label,
                    decision: ApprovalDecision::Review(ReviewDecision::NetworkPolicyAmendment {
                        network_policy_amendment: network_policy_amendment.clone(),
                    }),
                    display_shortcut: None,
                    additional_shortcuts: vec![key_hint::plain(shortcut)],
                })
            }
            // ... Abort, Denied
        })
        .collect()
}
```

### 命令片段隐藏

```rust
fn build_header(request: &ApprovalRequest) -> Box<dyn Renderable> {
    match request {
        ApprovalRequest::Exec {
            network_approval_context,
            // ...
        } => {
            // ...
            
            // 网络请求时不显示命令片段
            if network_approval_context.is_none() {
                header.extend(full_cmd_lines);
            }
            
            Box::new(Paragraph::new(header).wrap(Wrap { trim: false }))
        }
        // ...
    }
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs:56` | `network_approval_context` 字段 |
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs:144-170` | 标题生成逻辑 |
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs:660-748` | `exec_options` 函数 |
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs:712-733` | `NetworkPolicyAmendment` 处理 |
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs:1443-1498` | 网络执行提示快照测试 |

### 相关测试用例

```rust
#[test]
fn network_exec_prompt_title_includes_host() {
    let (tx, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx);
    let exec_request = ApprovalRequest::Exec {
        thread_id: ThreadId::new(),
        thread_label: None,
        id: "test".into(),
        command: vec!["curl".into(), "https://example.com".into()],
        reason: Some("network request blocked".into()),
        available_decisions: vec![
            ReviewDecision::Approved,
            ReviewDecision::ApprovedForSession,
            ReviewDecision::NetworkPolicyAmendment {
                network_policy_amendment: NetworkPolicyAmendment {
                    host: "example.com".to_string(),
                    action: NetworkPolicyRuleAction::Allow,
                },
            },
            ReviewDecision::Abort,
        ],
        network_approval_context: Some(NetworkApprovalContext {
            host: "example.com".to_string(),
            protocol: NetworkApprovalProtocol::Https,
        }),
        additional_permissions: None,
    };

    let view = ApprovalOverlay::new(exec_request, tx, Features::with_defaults());
    assert_snapshot!("network_exec_prompt", format!("{buf:?}"));
    
    // 验证标题包含主机名
    assert!(rendered.iter().any(|line| {
        line.contains("Do you want to approve network access to \"example.com\"?")
    }));
    
    // 验证不显示命令
    assert!(!rendered.iter().any(|line| line.contains("$ curl")));
    
    // 验证不显示 execpolicy 选项
    assert!(!rendered.iter().any(|line| line.contains("don't ask again")));
}

#[test]
fn network_deny_forever_shortcut_is_not_bound() {
    // 验证隐藏的 "deny forever" 选项没有绑定快捷键
    // 防止用户意外阻止主机
}
```

## 依赖与外部交互

### 网络策略类型

```rust
// codex-protocol/src/protocol.rs
pub struct NetworkPolicyAmendment {
    pub host: String,
    pub action: NetworkPolicyRuleAction,
}

pub enum NetworkPolicyRuleAction {
    Allow,  // 允许访问
    Deny,   // 阻止访问
}
```

### 事件交互

| 事件 | 方向 | 说明 |
|------|------|------|
| `AppEvent::SubmitThreadOp { op: Op::ExecApproval { decision: NetworkPolicyAmendment } }` | TUI → 后端 | 发送网络策略更新 |

## 风险、边界与改进建议

### 安全边界

1. **主机名欺骗**:
   - 子域名可能绕过限制（如 `evil.example.com` vs `example.com`）
   - 建议支持通配符或域名匹配规则

2. **协议区分**:
   - 当前区分 Http/Https，但用户可能不理解区别
   - 建议统一处理或明确提示安全风险

3. **隐藏选项**:
   - "deny forever" 选项存在但没有快捷键绑定
   - 这是有意设计，防止用户意外阻止合法主机

### 用户体验边界

1. **主机识别**:
   - 用户可能不认识某些主机名（如 CDN 域名）
   - 建议添加主机描述或分类

2. **频繁请求**:
   - 访问多个不同主机时，审批请求可能频繁弹出
   - 建议批量审批或域名组授权

3. **命令不可见**:
   - 网络审批不显示命令，用户不知道具体做什么
   - 建议可选显示命令详情

### 改进建议

1. **主机分类**:
   ```rust
   enum HostCategory {
       Trusted,      // 已知可信域名（如 github.com）
       Suspicious,   // 可疑域名
       Unknown,      // 未知域名
       Local,        // 本地网络
   }
   ```

2. **域名组授权**:
   - 允许用户授权整个域名组（如 `*.github.com`）
   - 减少重复审批

3. **命令预览**:
   - 添加选项查看完整命令
   - 帮助用户理解请求的上下文

4. **网络活动监控**:
   - 显示当前会话的网络活动摘要
   - 帮助用户了解已授权的网络访问

5. **撤销机制**:
   - 提供界面查看和撤销已授权的主机
   - 增强安全控制

```rust
// 建议添加网络策略管理
struct NetworkPolicyManager {
    allowed_hosts: Vec<String>,
    denied_hosts: Vec<String>,
    session_hosts: Vec<String>,
}

impl NetworkPolicyManager {
    fn revoke_host(&mut self, host: &str) { ... }
    fn list_authorized_hosts(&self) -> Vec<&str> { ... }
}
```
