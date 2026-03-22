# PlanType.ts Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`PlanType` 定义了用户的订阅计划类型，用于区分不同级别的服务访问权限和功能限制。

**使用场景：**
- 用户账户信息显示订阅级别
- 根据计划类型应用不同的速率限制和功能访问
- 在 UI 中显示用户的计划状态

**职责：**
- 提供标准化的计划类型定义
- 支持向后兼容（`unknown` 变体处理未识别的计划类型）
- 默认值为 `Free`，确保新用户有基本访问权限

## 2. 功能点目的 (Purpose of This Type)

该类型的主要目的是：

1. **服务分级**：根据用户订阅级别提供不同的服务和限制
2. **功能控制**：基于计划类型启用/禁用特定功能
3. **速率限制**：应用与计划类型匹配的速率限制

**计划类型：**
- `free`：免费计划（默认）
- `go`：Go 计划
- `plus`：Plus 计划
- `pro`：Pro 计划
- `team`：团队计划
- `business`：商业计划
- `enterprise`：企业计划
- `edu`：教育计划
- `unknown`：未知/未识别的计划类型

## 3. 具体技术实现 (Technical Implementation Details)

**Rust 定义**（位于 `codex-rs/protocol/src/account.rs`）：

```rust
#[derive(Serialize, Deserialize, Copy, Clone, Debug, PartialEq, Eq, JsonSchema, TS, Default)]
#[serde(rename_all = "lowercase")]
#[ts(rename_all = "lowercase")]
pub enum PlanType {
    #[default]
    Free,
    Go,
    Plus,
    Pro,
    Team,
    Business,
    Enterprise,
    Edu,
    #[serde(other)]
    Unknown,
}
```

**TypeScript 生成定义：**

```typescript
export type PlanType = "free" | "go" | "plus" | "pro" | "team" | "business" | "enterprise" | "edu" | "unknown";
```

**关键实现细节：**
- 使用 `lowercase` 序列化格式
- `#[serde(other)]` 属性确保未知值反序列化为 `Unknown` 而非失败
- 默认值为 `Free`

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

**Rust 源文件：**
- `/home/sansha/Github/codex/codex-rs/protocol/src/account.rs`：主要定义

**TypeScript 生成文件：**
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/PlanType.ts`

**使用位置：**
- `RateLimitSnapshot`（protocol.rs 第 1867-1875 行）
- 账户相关的 API 响应
- 测试代码（common.rs 第 947-957 行）

**相关类型：**
- `RateLimitSnapshot`：包含计划类型的速率限制信息
- `CreditsSnapshot`：包含账户额度信息

## 5. 依赖与外部交互 (Dependencies and External Interactions)

**依赖 crate：**
- `serde`：序列化/反序列化
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成

**序列化格式：**
- JSON 中使用 lowercase：`"free"`, `"plus"`, `"pro"` 等

**与后端服务的交互：**
- 从账户服务获取用户的计划类型
- 用于应用相应的速率限制和功能访问控制

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

**潜在风险：**
1. **计划变更**：用户升级/降级计划时的状态同步问题
2. **缓存过期**：计划类型缓存可能导致权限判断不准确
3. **未知计划**：新推出的计划类型可能被归类为 `unknown`

**边界情况：**
1. `#[serde(other)]` 确保未知值不会导致反序列化失败
2. 默认 `Free` 确保新用户有基本访问权限

**改进建议：**
1. **计划特性矩阵**：定义每个计划类型的具体功能访问权限
2. **计划升级提示**：当用户尝试使用超出当前计划的功能时，显示升级提示
3. **计划过期处理**：处理计划过期后的降级逻辑
4. **计划预览**：允许用户预览其他计划的功能
5. **团队计划管理**：支持团队计划中的成员管理和权限分配
6. **计划迁移**：支持用户在计划之间迁移数据和设置
