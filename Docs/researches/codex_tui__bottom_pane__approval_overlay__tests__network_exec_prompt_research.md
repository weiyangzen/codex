# Approval Overlay - Network Exec Prompt 研究报告

## 1. 场景与职责

### UI场景
该快照展示了 **Approval Overlay** 组件在处理 **网络访问审批（Network Approval）** 时的渲染效果。当 Codex 需要访问特定网络主机（如 "example.com"）时，系统会弹出此界面请求用户批准网络访问，并提供多种授权选项。

### 组件职责
- **网络访问控制**: 控制 Agent 的网络访问权限
- **主机级别授权**: 支持按主机名进行细粒度授权
- **策略持久化**: 支持将授权决策持久化为网络策略规则
- **安全审计**: 记录网络访问审批历史

## 2. 功能点目的

### 核心功能
1. **主机识别**: 清晰展示请求访问的目标主机
2. **原因说明**: 解释为什么需要访问该主机
3. **多级授权**: 提供"仅一次"、"本次会话"、"永久允许/拒绝"等选项
4. **策略管理**: 支持添加网络策略规则

### 用户体验目标
- 让用户清楚了解哪些外部资源将被访问
- 提供灵活的授权选项，避免重复提示
- 支持快速拒绝并阻止未来类似请求

## 3. 具体技术实现

### 关键数据结构

```rust
// 网络审批上下文
pub(crate) struct NetworkApprovalContext {
    pub host: String,                          // 目标主机
    pub protocol: NetworkApprovalProtocol,     // 协议类型
}

pub(crate) enum NetworkApprovalProtocol {
    Http,
    Https,
    Ssh,
    // ...
}

// 网络策略修改
pub(crate) struct NetworkPolicyAmendment {
    pub network_policy_amendment: NetworkPolicyRule,
}

pub(crate) struct NetworkPolicyRule {
    pub action: NetworkPolicyRuleAction,  // Allow 或 Deny
    pub host: String,
    pub protocol: NetworkApprovalProtocol,
}

pub(crate) enum NetworkPolicyRuleAction {
    Allow,
    Deny,
}

// 审批请求中的网络相关信息
pub(crate) enum ApprovalRequest {
    Exec {
        thread_id: ThreadId,
        thread_label: Option<String>,
        id: String,
        command: Vec<String>,
        reason: Option<String>,
        available_decisions: Vec<ReviewDecision>,
        network_approval_context: Option<NetworkApprovalContext>, // 本场景重点
        additional_permissions: Option<PermissionProfile>,
    },
    // ...
}

// 决策类型中的网络相关决策
pub(crate) enum ReviewDecision {
    Approved,
    ApprovedForSession,
    ApprovedExecpolicyAmendment { ... },
    NetworkPolicyAmendment { network_policy_amendment: NetworkPolicyRule }, // 网络策略修改
    Denied,
    Abort,
}
```

### 标题生成（网络场景）

```rust
let (options, title) = match request {
    ApprovalRequest::Exec {
        network_approval_context,
        ..
    } => (
        exec_options(available_decisions, network_approval_context.as_ref(), ...),
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
```

### 网络场景专用选项

```rust
fn exec_options(
    available_decisions: &[ReviewDecision],
    network_approval_context: Option<&NetworkApprovalContext>,
    additional_permissions: Option<&PermissionProfile>,
) -> Vec<ApprovalOption> {
    available_decisions.iter().filter_map(|decision| match decision {
        // 仅本次批准
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
        
        // 本次会话批准
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
        
        // 网络策略修改（允许或拒绝）
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
        
        // 拒绝选项...
        ReviewDecision::Denied => Some(ApprovalOption {
            label: "No, continue without running it".to_string(),
            decision: ApprovalDecision::Review(ReviewDecision::Denied),
            display_shortcut: None,
            additional_shortcuts: vec![key_hint::plain(KeyCode::Char('d'))],
        }),
        
        ReviewDecision::Abort => Some(ApprovalOption {
            label: "No, and tell Codex what to do differently".to_string(),
            decision: ApprovalDecision::Review(ReviewDecision::Abort),
            display_shortcut: Some(key_hint::plain(KeyCode::Esc)),
            additional_shortcuts: vec![key_hint::plain(KeyCode::Char('n'))],
        }),
        
        _ => None,
    }).collect()
}
```

### 渲染输出示例

```
Buffer {
    area: Rect { x: 0, y: 0, width: 100, height: 12 },
    content: [
        "                                                                                                    ",
        "  Do you want to approve network access to \"example.com\"?                                           ",
        "                                                                                                    ",
        "  Reason: network request blocked                                                                   ",
        "                                                                                                    ",
        "                                                                                                    ",
        "› 1. Yes, just this once (y)                                                                        ",
        "  2. Yes, and allow this host for this conversation (a)                                             ",
        "  3. Yes, and allow this host in the future (p)                                                     ",
        "  4. No, and tell Codex what to do differently (esc)                                                ",
        "                                                                                                    ",
        "  Press enter to confirm or esc to cancel                                                           ",
    ],
    styles: [
        // 样式信息...
    ]
}
```

## 4. 关键代码路径与文件引用

### 主要源文件
| 文件路径 | 职责 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/tui/src/bottom_pane/approval_overlay.rs` | ApprovalOverlay 完整实现 |

### 关键代码路径

1. **标题生成（网络场景）**:
   ```
   approval_overlay.rs:149-170 -> build_options() 的标题生成逻辑
   ```

2. **网络选项生成**:
   ```
   approval_overlay.rs:660-748 -> exec_options() 中的网络处理分支
   ```

3. **网络策略修改选项**:
   ```
   approval_overlay.rs:712-733 -> NetworkPolicyAmendment 处理
   ```

4. **网络审批模型**:
   ```
   codex-protocol/src/protocol.rs (假设) -> NetworkApprovalContext, NetworkPolicyRule
   ```

## 5. 依赖与外部交互

### 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `codex_protocol::protocol::NetworkApprovalContext` | 网络审批上下文 |
| `codex_protocol::protocol::NetworkPolicyAmendment` | 网络策略修改 |
| `codex_protocol::protocol::NetworkPolicyRule` | 网络策略规则 |
| `codex_protocol::protocol::NetworkPolicyRuleAction` | 允许/拒绝动作 |

### 外部交互

1. **网络策略持久化**:
   ```rust
   AppEvent::SubmitThreadOp {
       thread_id,
       op: Op::ExecApproval {
           decision: ReviewDecision::NetworkPolicyAmendment {
               network_policy_amendment: NetworkPolicyRule {
                   action: Allow | Deny,
                   host: "example.com".to_string(),
                   protocol: Https,
               }
           }
       }
   }
   ```

2. **策略生效**:
   - 策略修改通过 `Op::ExecApproval` 提交
   - 后端将规则持久化到网络策略配置
   - 后续对该主机的访问将自动应用策略

## 6. 风险、边界与改进建议

### 潜在风险

1. **恶意主机访问**:
   - 风险: 用户可能误批准访问恶意主机
   - 缓解: 提供 "block this host in the future" 选项快速阻断

2. **通配符域名**:
   - 风险: 策略可能使用通配符覆盖过多域名
   - 缓解: 对通配符策略显示额外警告

3. **协议混淆**:
   - 风险: HTTP 和 HTTPS 被视为不同主机
   - 缓解: 明确显示协议类型

### 边界情况

1. **IP 地址 vs 域名**:
   - 系统同时支持 IP 地址和域名
   - 需要正确处理 IPv4/IPv6 格式

2. **端口信息**:
   - 当前实现可能未区分不同端口
   - 建议添加端口级别控制

3. **本地网络**:
   - localhost、127.0.0.1 等特殊地址需要特殊处理

### 改进建议

1. **主机信誉显示**:
   - 建议: 显示主机信誉评分或安全警告

2. **访问目的推断**:
   - 建议: 根据上下文推断并显示访问目的

3. **临时授权**:
   - 建议: 支持"允许 5 分钟"等临时授权

4. **网络活动监控**:
   - 建议: 实时显示当前网络连接状态

5. **策略可视化**:
   - 建议: 提供已配置网络策略的查看界面

6. **批量策略管理**:
   - 建议: 支持导入/导出网络策略配置
