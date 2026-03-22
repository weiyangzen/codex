# network_policy_decision.rs 深度研究文档

## 场景与职责

`network_policy_decision.rs` 是 Codex CLI 的网络策略决策处理模块，负责将网络代理层的决策结果转换为协议层的审批上下文和错误消息。该模块在网络访问控制和用户审批流程中扮演关键角色：

1. **决策转换**：将网络代理的原始决策转换为结构化的审批请求
2. **错误消息生成**：为被拒绝的网络请求生成用户友好的错误消息
3. **策略修正映射**：将用户审批决策映射到执行策略（execpolicy）规则修正
4. **协议适配**：桥接 `codex_network_proxy` 和 `codex_protocol` 两个 crate

## 功能点目的

### 1. 决策载荷结构 (`NetworkPolicyDecisionPayload`)
- **目的**：定义网络策略决策的序列化表示
- **字段说明**：
  - `decision`: 决策类型（Ask/Deny）
  - `source`: 决策来源（Decider/BaselinePolicy 等）
  - `protocol`: 网络协议（Http/Https/Socks5Tcp/Socks5Udp）
  - `host`: 目标主机
  - `port`: 目标端口
  - `reason`: 决策原因代码

### 2. 审批上下文提取 (`network_approval_context_from_payload`)
- **目的**：从决策载荷中提取需要用户审批的上下文
- **过滤逻辑**：仅当决策为 `Ask` 且来源为 `Decider` 时才需要审批
- **验证**：确保 host 非空且 protocol 有效

### 3. 拒绝消息生成 (`denied_network_policy_message`)
- **目的**：为被拒绝的网络请求生成清晰的错误说明
- **原因映射**：
  - `denied`: 域名被显式拒绝
  - `not_allowed`: 域名不在允许列表
  - `not_allowed_local`: 本地/私有网络被阻止
  - `method_not_allowed`: 请求方法被阻止
  - `proxy_disabled`: 托管网络代理被禁用

### 4. 执行策略规则修正 (`execpolicy_network_rule_amendment`)
- **目的**：将用户审批决策转换为执行策略规则
- **协议映射**：`NetworkApprovalProtocol` ↔ `ExecPolicyNetworkRuleProtocol`
- **决策映射**：`Allow` → `Allow`, `Deny` → `Forbidden`
- **理由生成**：格式为 "{Action} {protocol} access to {host}"

## 具体技术实现

### 关键数据结构

```rust
/// 网络策略决策载荷（从代理层接收）
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct NetworkPolicyDecisionPayload {
    pub decision: NetworkPolicyDecision,
    pub source: NetworkDecisionSource,
    #[serde(default)]
    pub protocol: Option<NetworkApprovalProtocol>,
    pub host: Option<String>,
    pub reason: Option<String>,
    pub port: Option<u16>,
}

/// 执行策略网络规则修正（内部表示）
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ExecPolicyNetworkRuleAmendment {
    pub protocol: ExecPolicyNetworkRuleProtocol,
    pub decision: ExecPolicyDecision,
    pub justification: String,
}
```

### 决策解析

```rust
fn parse_network_policy_decision(value: &str) -> Option<NetworkPolicyDecision> {
    match value {
        "deny" => Some(NetworkPolicyDecision::Deny),
        "ask" => Some(NetworkPolicyDecision::Ask),
        _ => None,
    }
}
```

### 审批上下文提取逻辑

```rust
pub(crate) fn network_approval_context_from_payload(
    payload: &NetworkPolicyDecisionPayload,
) -> Option<NetworkApprovalContext> {
    // 仅 Ask + Decider 来源需要审批
    if !payload.is_ask_from_decider() {
        return None;
    }

    let protocol = payload.protocol?;
    let host = payload.host.as_deref()?.trim();
    if host.is_empty() {
        return None;
    }

    Some(NetworkApprovalContext {
        host: host.to_string(),
        protocol,
    })
}
```

### 拒绝消息生成

```rust
pub(crate) fn denied_network_policy_message(blocked: &BlockedRequest) -> Option<String> {
    // 仅处理明确的 Deny 决策
    let decision = blocked
        .decision
        .as_deref()
        .and_then(parse_network_policy_decision);
    if decision != Some(NetworkPolicyDecision::Deny) {
        return None;
    }

    let detail = match blocked.reason.as_str() {
        "denied" => "domain is explicitly denied by policy and cannot be approved from this prompt",
        "not_allowed" => "domain is not on the allowlist for the current sandbox mode",
        "not_allowed_local" => "local/private network addresses are blocked by policy",
        "method_not_allowed" => "request method is blocked by the current network mode",
        "proxy_disabled" => "managed network proxy is disabled",
        _ => "request is blocked by network policy",
    };

    Some(format!("Network access to \"{host}\" was blocked: {detail}."))
}
```

### 执行策略规则修正

```rust
pub(crate) fn execpolicy_network_rule_amendment(
    amendment: &NetworkPolicyAmendment,
    network_approval_context: &NetworkApprovalContext,
    host: &str,
) -> ExecPolicyNetworkRuleAmendment {
    // 协议映射
    let protocol = match network_approval_context.protocol {
        NetworkApprovalProtocol::Http => ExecPolicyNetworkRuleProtocol::Http,
        NetworkApprovalProtocol::Https => ExecPolicyNetworkRuleProtocol::Https,
        NetworkApprovalProtocol::Socks5Tcp => ExecPolicyNetworkRuleProtocol::Socks5Tcp,
        NetworkApprovalProtocol::Socks5Udp => ExecPolicyNetworkRuleProtocol::Socks5Udp,
    };

    // 决策映射
    let (decision, action_verb) = match amendment.action {
        NetworkPolicyRuleAction::Allow => (ExecPolicyDecision::Allow, "Allow"),
        NetworkPolicyRuleAction::Deny => (ExecPolicyDecision::Forbidden, "Deny"),
    };

    // 协议标签映射
    let protocol_label = match network_approval_context.protocol {
        NetworkApprovalProtocol::Http => "http",
        NetworkApprovalProtocol::Https => "https_connect",
        NetworkApprovalProtocol::Socks5Tcp => "socks5_tcp",
        NetworkApprovalProtocol::Socks5Udp => "socks5_udp",
    };

    let justification = format!("{action_verb} {protocol_label} access to {host}");

    ExecPolicyNetworkRuleAmendment { protocol, decision, justification }
}
```

## 关键代码路径与文件引用

### 本文件关键函数

| 函数 | 行号 | 可见性 | 说明 |
|------|------|--------|------|
| `NetworkPolicyDecisionPayload::is_ask_from_decider` | 32-34 | pub(crate) | 检查是否需要审批 |
| `parse_network_policy_decision` | 37-43 | private | 解析决策字符串 |
| `network_approval_context_from_payload` | 45-63 | pub(crate) | 提取审批上下文 |
| `denied_network_policy_message` | 65-91 | pub(crate) | 生成拒绝消息 |
| `execpolicy_network_rule_amendment` | 93-121 | pub(crate) | 生成执行策略修正 |

### 依赖类型

```rust
// 执行策略
codex_execpolicy::Decision as ExecPolicyDecision
codex_execpolicy::NetworkRuleProtocol as ExecPolicyNetworkRuleProtocol

// 网络代理
codex_network_proxy::BlockedRequest
codex_network_proxy::NetworkDecisionSource
codex_network_proxy::NetworkPolicyDecision

// 协议层审批
codex_protocol::approvals::NetworkApprovalContext
codex_protocol::approvals::NetworkApprovalProtocol
codex_protocol::approvals::NetworkPolicyAmendment
codex_protocol::approvals::NetworkPolicyRuleAction

// 序列化
serde::Deserialize
```

### 调用方引用

- `crate::tools/orchestrator.rs` - 工具编排器调用审批上下文提取
- `crate::tools/network_approval.rs` - 网络审批处理
- `crate::codex.rs` - 主 Codex 逻辑
- `crate::error.rs` - 错误处理

## 依赖与外部交互

### 上游依赖

1. **执行策略 Crate** (`codex_execpolicy`)
   - `Decision` - 执行决策枚举（Allow/Forbidden）
   - `NetworkRuleProtocol` - 网络规则协议类型

2. **网络代理 Crate** (`codex_network_proxy`)
   - `BlockedRequest` - 被阻止的请求信息
   - `NetworkDecisionSource` - 决策来源枚举
   - `NetworkPolicyDecision` - 策略决策枚举

3. **协议 Crate** (`codex_protocol`)
   - `NetworkApprovalContext` - 审批上下文
   - `NetworkApprovalProtocol` - 审批协议类型
   - `NetworkPolicyAmendment` - 策略修正
   - `NetworkPolicyRuleAction` - 规则动作

### 下游消费

1. **工具编排器** - 集成网络审批到工具执行流程
2. **错误处理** - 生成用户可见的错误消息
3. **执行策略管理器** - 应用用户批准的规则修正

## 风险、边界与改进建议

### 已知风险

1. **字符串匹配脆弱性**
   - `parse_network_policy_decision` 使用字符串匹配，可能与代理层不同步
   - `denied_network_policy_message` 中的 reason 字符串匹配可能失效

2. **协议枚举映射硬编码**
   - 协议类型映射分散在多个 match 语句中，容易遗漏
   - 新增协议类型需要修改多处代码

3. **Host 验证简化**
   - 仅检查 host 是否为空，没有验证格式合法性
   - 可能允许无效的主机名通过

4. **错误消息国际化**
   - 错误消息是硬编码的英文，不支持本地化

### 边界条件

| 场景 | 处理行为 |
|------|----------|
| `decision` 不是 "ask"/"deny" | `parse_network_policy_decision` 返回 None |
| `host` 为空或仅空白 | `network_approval_context_from_payload` 返回 None |
| `protocol` 为 None | `network_approval_context_from_payload` 返回 None |
| `decision` 不是 "deny" | `denied_network_policy_message` 返回 None |
| `host` 为空 | 返回通用消息 "Network access was blocked by policy." |
| 未知 reason | 使用默认消息 "request is blocked by network policy" |

### 改进建议

1. **类型安全增强**
   - 使用强类型替代字符串匹配（如 `NetworkPolicyDecision::from_str`）
   - 将 reason 定义为枚举而非字符串

2. **集中映射定义**
   - 使用宏或查找表集中定义协议映射
   - 确保新增协议时编译器强制更新所有映射

3. **Host 验证增强**
   - 添加主机名格式验证
   - 检查是否为有效的域名或 IP 地址

4. **国际化支持**
   - 使用 `fluent` 或类似框架支持多语言错误消息
   - 错误消息模板化，便于翻译

5. **测试覆盖扩展**
   - 添加模糊测试验证各种输入组合
   - 测试边界条件（空字符串、特殊字符等）

6. **文档完善**
   - 添加更多示例说明各种决策场景
   - 记录 reason 字符串的完整列表和含义
