# NetworkPolicyAmendment 研究文档

## 场景与职责

`NetworkPolicyAmendment` 定义了网络策略修正规则，用于在用户批准网络访问请求时，选择性地添加持久化的网络策略规则。这允许用户"记住"对特定主机的允许或拒绝决定。

## 功能点目的

该类型的核心功能是：
1. **持久化网络规则**: 允许用户将临时批准转换为持久策略
2. **主机级控制**: 基于主机名配置网络访问规则
3. **策略修正**: 在运行时动态修改网络访问策略

## 具体技术实现

### 数据结构

```typescript
export type NetworkPolicyAmendment = { 
  host: string, 
  action: NetworkPolicyRuleAction 
};
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct NetworkPolicyAmendment {
    pub host: String,
    pub action: NetworkPolicyRuleAction,
}
```

### 字段详解

| 字段 | 类型 | 说明 |
|-----|------|------|
| `host` | `string` | 目标主机名或域名 |
| `action` | `NetworkPolicyRuleAction` | 规则动作：`allow` 或 `deny` |

### 关联类型

`NetworkPolicyRuleAction` 枚举定义了可能的动作：

```rust
pub enum NetworkPolicyRuleAction {
    Allow,  // 允许访问
    Deny,   // 拒绝访问
}
```

### 使用场景

在命令执行审批决策中使用：

```rust
pub enum CommandExecutionApprovalDecision {
    // ... 其他变体
    ApplyNetworkPolicyAmendment {
        network_policy_amendment: NetworkPolicyAmendment,
    },
    // ...
}
```

### 转换方法

```rust
impl NetworkPolicyAmendment {
    pub fn into_core(self) -> CoreNetworkPolicyAmendment {
        CoreNetworkPolicyAmendment {
            host: self.host,
            action: self.action.to_core(),
        }
    }
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 类型定义，行 1410-1434 |
| `codex-rs/app-server-protocol/schema/typescript/v2/NetworkPolicyAmendment.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/NetworkPolicyRuleAction.ts` | 规则动作枚举 |

## 依赖与外部交互

### 依赖类型
- `NetworkPolicyRuleAction`: 规则动作枚举
- `CoreNetworkPolicyAmendment`: 来自 codex_protocol 的核心类型

### 协议集成
- 属于 App-Server Protocol v2 API
- 用于 `CommandExecutionApprovalDecision` 枚举
- 通过 `PermissionsRequestApproval` 流程应用

### 沙箱集成
- 影响沙箱的网络访问策略
- 与 `SandboxPolicy` 中的网络配置相关

## 风险、边界与改进建议

### 潜在风险
1. **主机名匹配**: 简单的字符串匹配可能无法处理通配符或子域名
2. **策略冲突**: 多个规则可能产生冲突，需要明确的优先级策略
3. **持久化安全**: 用户可能无意中允许恶意主机访问

### 边界情况
1. **IP 地址**: 当前设计使用主机名，直接使用 IP 地址的处理方式
2. **端口控制**: 当前不区分不同端口的访问控制
3. **CIDR 范围**: 不支持 IP 范围（如 192.168.0.0/24）

### 改进建议
1. 支持通配符主机名（如 `*.example.com`）
2. 添加端口级别的控制（如 `example.com:8080`）
3. 支持 IP 地址和 CIDR 范围
4. 添加规则优先级或顺序字段
5. 添加规则过期时间，支持临时规则
6. 添加规则描述字段，帮助用户理解规则用途
