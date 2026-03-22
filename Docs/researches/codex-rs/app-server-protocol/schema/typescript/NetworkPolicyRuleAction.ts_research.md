# NetworkPolicyRuleAction.ts Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`NetworkPolicyRuleAction` 是一个简单的枚举类型，定义网络策略规则的动作类型：允许（allow）或拒绝（deny）。

**使用场景：**
- 定义 `NetworkPolicyAmendment` 的动作类型
- 网络沙箱策略决策
- 执行审批流程中的网络访问决策

**职责：**
- 提供明确的二元决策选项
- 支持序列化和反序列化
- 作为 `NetworkPolicyAmendment` 的一部分

## 2. 功能点目的 (Purpose of This Type)

该类型的主要目的是：

1. **二元决策**：明确区分允许和拒绝两种网络访问策略
2. **类型安全**：使用枚举而非字符串，确保类型安全
3. **标准化**：在网络策略相关代码中提供一致的动作表示

**动作定义：**
- `allow`：允许访问指定网络主机
- `deny`：拒绝访问指定网络主机

## 3. 具体技术实现 (Technical Implementation Details)

**Rust 定义**（位于 `codex-rs/protocol/src/approvals.rs` 第 80-85 行）：

```rust
#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
pub enum NetworkPolicyRuleAction {
    Allow,
    Deny,
}
```

**TypeScript 生成定义：**

```typescript
export type NetworkPolicyRuleAction = "allow" | "deny";
```

**关键实现细节：**
- 简单的二元枚举
- 使用 `snake_case` 序列化
- 实现了 `Copy` trait，便于值传递

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

**Rust 源文件：**
- `/home/sansha/Github/codex/codex-rs/protocol/src/approvals.rs`（第 80-85 行）：主要定义

**TypeScript 生成文件：**
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/NetworkPolicyRuleAction.ts`

**使用位置：**
- `NetworkPolicyAmendment.action` 字段
- `ExecApprovalRequestEvent::default_available_decisions` 方法（第 227-230 行）

**相关类型：**
- `NetworkPolicyAmendment`：使用此枚举定义策略修改

## 5. 依赖与外部交互 (Dependencies and External Interactions)

**依赖 crate：**
- `serde`：序列化/反序列化
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成

**序列化格式：**
- JSON 中使用 snake_case：`"allow"`, `"deny"`

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

**潜在风险：**
1. **过于简单**：二元选择可能不足以表达复杂的网络策略需求
2. **默认行为**：需要明确默认行为（通常是拒绝）

**边界情况：**
1. 规则顺序：在策略评估中，规则的顺序可能影响最终结果

**改进建议：**
1. **添加更多动作**：考虑添加 `log`（仅记录不阻止）、`prompt`（每次询问）等动作
2. **条件动作**：支持基于时间、用户等的条件规则
3. **动作参数**：允许动作携带额外参数（如限速、超时等）
