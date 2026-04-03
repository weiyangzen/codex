# NetworkPolicyRuleAction 研究文档

## 场景与职责

`NetworkPolicyRuleAction` 是一个简单的枚举类型，定义了网络策略规则的可能动作。它用于在网络访问控制中明确表示允许或拒绝某个网络请求。

## 功能点目的

该类型的核心功能是：
1. **二元决策**: 提供明确的允许/拒绝二元选择
2. **策略表达**: 作为网络策略规则的核心动作字段
3. **用户审批**: 在用户界面中呈现网络访问审批选项

## 具体技术实现

### 数据结构

```typescript
export type NetworkPolicyRuleAction = "allow" | "deny";
```

### Rust 源码定义

```rust
v2_enum_from_core! {
    pub enum NetworkPolicyRuleAction from CoreNetworkPolicyRuleAction {
        Allow, Deny
    }
}
```

### 枚举值详解

| 枚举值 | 序列化值 | 说明 |
|-------|---------|------|
| `Allow` | `"allow"` | 允许网络访问 |
| `Deny` | `"deny"` | 拒绝网络访问 |

### 宏实现

使用 `v2_enum_from_core!` 宏自动生成：
- 序列化/反序列化实现
- 与核心类型的转换方法
- TypeScript 导出配置

生成的代码包括：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum NetworkPolicyRuleAction {
    Allow,
    Deny,
}

impl NetworkPolicyRuleAction {
    pub fn to_core(self) -> CoreNetworkPolicyRuleAction {
        match self {
            NetworkPolicyRuleAction::Allow => CoreNetworkPolicyRuleAction::Allow,
            NetworkPolicyRuleAction::Deny => CoreNetworkPolicyRuleAction::Deny,
        }
    }
}

impl From<CoreNetworkPolicyRuleAction> for NetworkPolicyRuleAction {
    fn from(value: CoreNetworkPolicyRuleAction) -> Self {
        match value {
            CoreNetworkPolicyRuleAction::Allow => NetworkPolicyRuleAction::Allow,
            CoreNetworkPolicyRuleAction::Deny => NetworkPolicyRuleAction::Deny,
        }
    }
}
```

### 使用场景

该枚举主要用于 `NetworkPolicyAmendment` 类型：

```rust
pub struct NetworkPolicyAmendment {
    pub host: String,
    pub action: NetworkPolicyRuleAction,
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 类型定义，行 1404-1408 |
| `codex-rs/app-server-protocol/schema/typescript/v2/NetworkPolicyRuleAction.ts` | TypeScript 类型定义 |

## 依赖与外部交互

### 依赖类型
- `CoreNetworkPolicyRuleAction`: 来自 codex_protocol 的核心枚举类型

### 协议集成
- 属于 App-Server Protocol v2 API
- 用于网络策略配置和审批流程

## 风险、边界与改进建议

### 潜在风险
1. **过于简化**: 二元选择可能无法满足复杂的网络策略需求
2. **无中间状态**: 没有"询问"或"日志记录"等中间选项

### 边界情况
1. **默认策略**: 需要明确没有匹配规则时的默认行为
2. **规则顺序**: 多个规则匹配同一主机时的优先级问题

### 改进建议
1. 考虑添加 `Log` 变体，只记录不阻止
2. 可以添加 `Ask` 变体，每次询问用户
3. 考虑添加 `RateLimit` 变体，支持速率限制
4. 可以添加 `Redirect` 变体，支持流量重定向
