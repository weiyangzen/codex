# network_policy_decision_tests.rs 深度研究文档

## 场景与职责

`network_policy_decision_tests.rs` 是 `network_policy_decision.rs` 的配套测试模块，提供对网络策略决策处理逻辑的单元测试覆盖。测试验证决策解析、审批上下文提取、协议映射和错误消息生成等核心功能。

## 功能点目的

### 1. 审批上下文来源验证 (`network_approval_context_requires_ask_from_decider`)
- **目的**：验证只有 `Ask` + `Decider` 来源的决策才需要审批
- **测试场景**：`Deny` 决策不应产生审批上下文

### 2. 协议映射测试 (`network_approval_context_maps_http_https_and_socks_protocols`)
- **目的**：验证所有支持的协议类型都能正确映射到审批上下文
- **测试场景**：
  - HTTP 协议
  - HTTPS 协议
  - SOCKS5 TCP 协议
  - SOCKS5 UDP 协议

### 3. 协议别名反序列化测试 (`network_policy_decision_payload_deserializes_proxy_protocol_aliases`)
- **目的**：验证协议别名的反序列化支持
- **测试场景**：
  - `https_connect` 别名映射到 `Https`
  - `http-connect` 别名映射到 `Https`

### 4. 执行策略规则修正测试 (`execpolicy_network_rule_amendment_maps_protocol_action_and_justification`)
- **目的**：验证审批决策到执行策略规则的映射
- **测试场景**：`Deny` 动作映射到 `Forbidden` 决策，并生成正确的理由

### 5. 拒绝消息决策过滤测试 (`denied_network_policy_message_requires_deny_decision`)
- **目的**：验证只有 `Deny` 决策才生成拒绝消息
- **测试场景**：`Ask` 决策不应产生拒绝消息

### 6. 拒绝消息详细原因测试 (`denied_network_policy_message_for_denylist_block_is_explicit`)
- **目的**：验证明确的拒绝原因消息生成
- **测试场景**：`denied` 原因生成特定的错误说明

## 具体技术实现

### 测试结构

```rust
use super::*;
use codex_network_proxy::BlockedRequest;
use codex_protocol::approvals::NetworkPolicyAmendment;
use codex_protocol::approvals::NetworkPolicyRuleAction;
use pretty_assertions::assert_eq;
```

### 测试数据构造模式

```rust
// 构造决策载荷
let payload = NetworkPolicyDecisionPayload {
    decision: NetworkPolicyDecision::Ask,
    source: NetworkDecisionSource::Decider,
    protocol: Some(NetworkApprovalProtocol::Https),
    host: Some("example.com".to_string()),
    reason: Some("not_allowed".to_string()),
    port: Some(443),
};

// 构造被阻止请求
let blocked = BlockedRequest {
    host: "example.com".to_string(),
    reason: "denied".to_string(),
    client: None,
    method: Some("GET".to_string()),
    mode: None,
    protocol: "http".to_string(),
    decision: Some("deny".to_string()),
    source: Some("baseline_policy".to_string()),
    port: Some(80),
    timestamp: 0,
};

// 构造策略修正
let amendment = NetworkPolicyAmendment {
    action: NetworkPolicyRuleAction::Deny,
    host: "example.com".to_string(),
};
let context = NetworkApprovalContext {
    host: "example.com".to_string(),
    protocol: NetworkApprovalProtocol::Socks5Udp,
};
```

### JSON 反序列化测试

```rust
let payload: NetworkPolicyDecisionPayload = serde_json::from_str(
    r#"{
        "decision":"ask",
        "source":"decider",
        "protocol":"https_connect",
        "host":"example.com",
        "reason":"not_allowed",
        "port":443
    }"#,
).expect("payload should deserialize");
```

## 关键代码路径与文件引用

### 测试函数清单

| 测试函数 | 行号 | 测试目标 |
|----------|------|----------|
| `network_approval_context_requires_ask_from_decider` | 7-19 | 审批来源过滤 |
| `network_approval_context_maps_http_https_and_socks_protocols` | 21-102 | 协议映射 |
| `network_policy_decision_payload_deserializes_proxy_protocol_aliases` | 104-131 | 协议别名 |
| `execpolicy_network_rule_amendment_maps_protocol_action_and_justification` | 133-152 | 规则修正 |
| `denied_network_policy_message_requires_deny_decision` | 154-169 | 拒绝消息过滤 |
| `denied_network_policy_message_for_denylist_block_is_explicit` | 171-191 | 详细拒绝消息 |

### 被测函数覆盖

| 被测函数 | 测试覆盖 |
|----------|----------|
| `network_approval_context_from_payload` | `network_approval_context_requires_*`, `network_approval_context_maps_*` |
| `NetworkPolicyDecisionPayload::is_ask_from_decider` | `network_approval_context_requires_*` |
| `execpolicy_network_rule_amendment` | `execpolicy_network_rule_amendment_*` |
| `denied_network_policy_message` | `denied_network_policy_message_*` |
| `parse_network_policy_decision` | 间接通过 `denied_network_policy_message_*` |

## 依赖与外部交互

### 测试依赖

```rust
// 被测模块
use super::*;

// 网络代理类型
codex_network_proxy::BlockedRequest

// 协议类型
codex_protocol::approvals::NetworkPolicyAmendment
codex_protocol::approvals::NetworkPolicyRuleAction

// 断言增强
use pretty_assertions::assert_eq;
```

### 隐式依赖

| 依赖 | 来源 | 用途 |
|------|------|------|
| `serde_json` | 测试代码 | JSON 反序列化测试 |
| `NetworkApprovalContext` | codex_protocol | 审批上下文断言 |
| `NetworkApprovalProtocol` | codex_protocol | 协议类型断言 |
| `ExecPolicyNetworkRuleAmendment` | codex_execpolicy | 规则修正断言 |

## 风险、边界与改进建议

### 当前测试覆盖 gaps

1. **边界条件测试缺失**
   - 没有测试空 host 处理
   - 没有测试 None protocol 处理
   - 没有测试未知 reason 处理

2. **错误场景测试缺失**
   - 没有测试无效 JSON 处理
   - 没有测试缺失必需字段处理

3. **组合场景测试缺失**
   - 没有测试多种协议组合
   - 没有测试复杂审批流程

4. **字符串匹配测试缺失**
   - 没有直接测试 `parse_network_policy_decision`
   - 没有测试各种 decision 字符串变体

5. **理由生成测试不完整**
   - 只测试了 `Deny` 动作，没有测试 `Allow`
   - 没有测试各种协议的理由格式

### 改进建议

1. **添加边界条件测试**
```rust
#[test]
fn network_approval_context_returns_none_for_empty_host() {
    let payload = NetworkPolicyDecisionPayload {
        decision: NetworkPolicyDecision::Ask,
        source: NetworkDecisionSource::Decider,
        protocol: Some(NetworkApprovalProtocol::Https),
        host: Some("   ".to_string()),  // 仅空白
        reason: None,
        port: None,
    };
    assert_eq!(network_approval_context_from_payload(&payload), None);
}

#[test]
fn network_approval_context_returns_none_for_none_protocol() {
    let payload = NetworkPolicyDecisionPayload {
        decision: NetworkPolicyDecision::Ask,
        source: NetworkDecisionSource::Decider,
        protocol: None,
        host: Some("example.com".to_string()),
        reason: None,
        port: None,
    };
    assert_eq!(network_approval_context_from_payload(&payload), None);
}
```

2. **添加理由生成完整测试**
```rust
#[test]
fn execpolicy_justification_for_all_protocols() {
    let protocols = vec![
        (NetworkApprovalProtocol::Http, "http"),
        (NetworkApprovalProtocol::Https, "https_connect"),
        (NetworkApprovalProtocol::Socks5Tcp, "socks5_tcp"),
        (NetworkApprovalProtocol::Socks5Udp, "socks5_udp"),
    ];
    
    for (protocol, expected_label) in protocols {
        let context = NetworkApprovalContext {
            host: "test.com".to_string(),
            protocol,
        };
        let amendment = NetworkPolicyAmendment {
            action: NetworkPolicyRuleAction::Allow,
            host: "test.com".to_string(),
        };
        
        let result = execpolicy_network_rule_amendment(&amendment, &context, "test.com");
        assert!(result.justification.contains(expected_label));
    }
}
```

3. **添加拒绝消息完整测试**
```rust
#[test]
fn denied_network_policy_message_for_all_reasons() {
    let reasons = vec![
        ("denied", "explicitly denied"),
        ("not_allowed", "not on the allowlist"),
        ("not_allowed_local", "local/private"),
        ("method_not_allowed", "request method"),
        ("proxy_disabled", "managed network proxy"),
        ("unknown", "blocked by network policy"),  // 默认
    ];
    
    for (reason, expected_substring) in reasons {
        let blocked = BlockedRequest {
            host: "test.com".to_string(),
            reason: reason.to_string(),
            decision: Some("deny".to_string()),
            // ... 其他字段
        };
        
        let message = denied_network_policy_message(&blocked).unwrap();
        assert!(message.contains(expected_substring));
    }
}
```

4. **使用 insta snapshot 测试**
   - 对复杂的错误消息进行快照测试
   - 便于检测消息格式的意外变化

5. **提取测试辅助函数**
```rust
fn create_test_payload(
    decision: NetworkPolicyDecision,
    source: NetworkDecisionSource,
) -> NetworkPolicyDecisionPayload {
    NetworkPolicyDecisionPayload {
        decision,
        source,
        protocol: Some(NetworkApprovalProtocol::Https),
        host: Some("example.com".to_string()),
        reason: Some("test".to_string()),
        port: Some(443),
    }
}
```

### 测试代码质量建议

1. **减少重复代码**
   - 多个测试使用相似的 payload 构造，可以提取辅助函数

2. **添加文档注释**
   - 为复杂测试添加更详细的说明

3. **使用参数化测试**
   - 使用 `rstest` 测试多种协议和原因组合
