# NetworkPolicyAmendment.ts Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`NetworkPolicyAmendment` 用于定义网络策略的修改提议，当 AI 代理尝试访问被阻止的网络主机时，系统可以向用户提议添加允许或拒绝规则。

**使用场景：**
- AI 代理执行命令时需要访问特定网络主机但被沙箱阻止
- 用户批准网络访问时，可以选择将此规则持久化到网络策略中
- 执行审批流程（`ExecApprovalRequestEvent`）中作为提议的修改

**职责：**
- 封装网络策略修改的目标主机和动作
- 支持允许（allow）和拒绝（deny）两种动作
- 作为执行审批事件的一部分传递给客户端

## 2. 功能点目的 (Purpose of This Type)

该类型的主要目的是：

1. **网络访问控制**：精细控制 AI 代理的网络访问权限
2. **策略持久化**：允许用户将临时批准转换为持久策略规则
3. **安全决策**：为用户提供明确的允许/拒绝选项

**结构定义：**
- `host`：目标主机名（字符串）
- `action`：策略动作（`NetworkPolicyRuleAction`：allow 或 deny）

## 3. 具体技术实现 (Technical Implementation Details)

**Rust 定义**（位于 `codex-rs/protocol/src/approvals.rs` 第 104-108 行）：

```rust
#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq, JsonSchema, TS)]
pub struct NetworkPolicyAmendment {
    pub host: String,
    pub action: NetworkPolicyRuleAction,
}
```

**TypeScript 生成定义：**

```typescript
import type { NetworkPolicyRuleAction } from "./NetworkPolicyRuleAction";

export type NetworkPolicyAmendment = { host: string, action: NetworkPolicyRuleAction, };
```

**关键实现细节：**
- 简单的结构体，包含主机名和动作
- 与 `NetworkPolicyRuleAction` 枚举配合使用
- 在 `ExecApprovalRequestEvent` 中作为可选字段使用

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

**Rust 源文件：**
- `/home/sansha/Github/codex/codex-rs/protocol/src/approvals.rs`（第 104-108 行）：主要定义
- `/home/sansha/Github/codex/codex-rs/protocol/src/approvals.rs`（第 176-179 行）：在 `ExecApprovalRequestEvent` 中使用
- `/home/sansha/Github/codex/codex-rs/protocol/src/approvals.rs`（第 219-252 行）：默认决策逻辑

**TypeScript 生成文件：**
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/NetworkPolicyAmendment.ts`

**使用位置：**
- `ExecApprovalRequestEvent.proposed_network_policy_amendments` 字段
- `ReviewDecision::NetworkPolicyAmendment` 变体

**相关类型：**
- `NetworkPolicyRuleAction`：定义 allow/deny 动作
- `NetworkApprovalContext`：提供网络审批的上下文信息

## 5. 依赖与外部交互 (Dependencies and External Interactions)

**依赖 crate：**
- `serde`：序列化/反序列化
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成

**序列化格式：**
- JSON 对象格式：`{ "host": "example.com", "action": "allow" }`

**与网络沙箱的交互：**
- 修改最终被应用到 `NetworkSandboxPolicy`
- 影响后续命令的网络访问决策

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

**潜在风险：**
1. **过于宽泛的规则**：如果只指定主机名而不指定端口或协议，可能过于宽泛
2. **持久化风险**：用户可能无意中允许了恶意主机的访问
3. **规则冲突**：多个规则可能相互冲突

**边界情况：**
1. 通配符主机：当前实现可能不支持通配符（如 `*.example.com`）
2. IP 地址 vs 主机名：需要明确处理 IP 地址和主机名的区别

**改进建议：**
1. **添加端口和协议**：扩展结构以支持端口范围和协议类型
2. **通配符支持**：支持通配符主机名匹配
3. **规则优先级**：添加优先级字段以处理规则冲突
4. **过期时间**：支持设置规则的过期时间
5. **规则描述**：添加可选的描述字段，帮助用户理解规则的用途
6. **审计日志**：记录所有策略修改操作
