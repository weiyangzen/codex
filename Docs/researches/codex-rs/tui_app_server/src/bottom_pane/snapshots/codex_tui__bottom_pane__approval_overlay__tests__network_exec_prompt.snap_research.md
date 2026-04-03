# Approval Overlay Network Exec Prompt Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `approval_overlay.rs` 模块的测试快照，用于验证**网络访问审批覆盖层**的渲染输出。当 Codex 需要访问特定网络主机时，向用户展示此界面。

### 业务场景
- 执行 `curl`、`wget` 等网络命令
- 访问 API 端点
- 下载依赖或资源

### 网络审批特性
与常规 Exec 审批相比，网络审批：
- **标题包含主机名**：明确显示要访问的主机
- **不显示命令行**：避免命令细节干扰网络决策
- **主机级别授权**：可以授权特定主机的访问
- **持久化选项**：可以永久允许或拒绝特定主机

## 功能点目的

### 核心功能
1. **主机标识**：清晰显示要访问的网络主机
2. **理由说明**：解释为什么需要网络访问
3. **分级授权**：
   - 仅本次（Yes, just this once）
   - 本会话允许（Yes, and allow this host for this conversation）
   - 永久允许（Yes, and allow this host in the future）
4. **拒绝选项**：允许拒绝并继续

### 安全设计目标
- **主机隔离**：按主机粒度控制访问
- **协议明确**：显示访问协议（HTTP/HTTPS）
- **可追溯性**：记录网络访问决策

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
        network_approval_context: Option<NetworkApprovalContext>,  // 网络上下文
        additional_permissions: Option<PermissionProfile>,
    },
    // ... 其他变体
}

pub struct NetworkApprovalContext {
    pub host: String,      // 主机名，如 "example.com"
    pub protocol: NetworkApprovalProtocol,  // 协议：Http 或 Https
}

pub enum NetworkApprovalProtocol {
    Http,
    Https,
}

pub struct NetworkPolicyAmendment {
    pub host: String,
    pub action: NetworkPolicyRuleAction,  // Allow 或 Deny
}

pub enum NetworkPolicyRuleAction {
    Allow,
    Deny,
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
            network_approval_context,
            ..
        } => (
            exec_options(/* ... */),
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
        // ... 其他变体
    };
    // ...
}
```

### 选项生成
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
                // ...
            }),
            ReviewDecision::ApprovedForSession => Some(ApprovalOption {
                label: if network_approval_context.is_some() {
                    "Yes, and allow this host for this conversation".to_string()
                } else {
                    "Yes, and don't ask again for this command in this session".to_string()
                },
                // ...
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
            // ... 其他决策类型
        })
        .collect()
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/approval_overlay.rs`
- **测试函数**: `network_exec_prompt_title_includes_host` (行 1429-1484)
- **测试函数**: `network_deny_forever_shortcut_is_not_bound` (行 1104-1141)

### 测试参数
```rust
ApprovalRequest::Exec {
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
}
```

### 渲染输出分析
```
Buffer {
    area: Rect { x: 0, y: 0, width: 100, height: 12 },
    content: [
        "  Do you want to approve network access to "example.com"?",
        "  Reason: network request blocked",
        "› 1. Yes, just this once (y)",
        "  2. Yes, and allow this host for this conversation (a)",
        "  3. Yes, and allow this host in the future (p)",
        "  4. No, and tell Codex what to do differently (esc)",
        "  Press enter to confirm or esc to cancel",
    ],
    styles: [
        // 标题加粗
        x: 2, y: 1, fg: Reset, bg: Reset, underline: Reset, modifier: BOLD,
        // 理由斜体
        x: 10, y: 3, fg: Reset, bg: Reset, underline: Reset, modifier: ITALIC,
        // 选中选项青色加粗
        x: 0, y: 6, fg: Cyan, bg: Reset, underline: Reset, modifier: BOLD,
        // 快捷键灰色
        x: 53, y: 7, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
    ]
}
```

## 依赖与外部交互

### 内部依赖
- `codex_protocol::protocol::NetworkApprovalContext` - 网络审批上下文
- `codex_protocol::protocol::NetworkApprovalProtocol` - 网络协议枚举
- `codex_protocol::protocol::NetworkPolicyAmendment` - 网络策略修改
- `codex_protocol::protocol::NetworkPolicyRuleAction` - 策略动作

### 外部交互
- **网络策略管理器**: 存储和应用网络访问规则
- **DNS 解析**: 验证主机名
- **防火墙/代理**: 实际执行网络访问控制

## 风险、边界与改进建议

### 潜在风险
1. **主机欺骗**: 恶意命令可能使用误导性主机名
2. **DNS 重绑定**: 批准后被攻击者利用进行 DNS 重绑定攻击
3. **子域绕过**: `*.example.com` 规则可能被滥用

### 边界情况
1. **IP 地址**: 直接使用 IP 地址时的处理
2. **端口指定**: `example.com:8080` 这样的带端口主机名
3. **通配符**: 是否应该支持 `*.example.com`
4. **拒绝快捷键隐藏**: 测试 `network_deny_forever_shortcut_is_not_bound` 确认 `d` 快捷键未绑定

### 改进建议
1. **域名验证**: 添加域名格式验证
2. **子域策略**: 明确子域是否继承父域权限
3. **IP 范围**: 支持 CIDR 表示法的 IP 范围
4. **协议分离**: 分别控制 HTTP 和 HTTPS 访问
5. **证书固定**: 对 HTTPS 主机验证证书指纹
6. **网络日志**: 显示该主机的历史访问记录

### 测试覆盖
- 网络提示标题: `network_exec_prompt_title_includes_host`
- 拒绝快捷键: `network_deny_forever_shortcut_is_not_bound`
- 网络选项标签: `network_exec_options_use_expected_labels_and_hide_execpolicy_amendment`

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/approval_overlay.rs`
- 网络协议: `codex-rs/protocol/src/protocol/` 下的网络相关模块
