# GuardianApprovalReview.ts Research Document

## 场景与职责

`GuardianApprovalReview` 类型是 Guardian 自动审批系统的审查结果载体，用于表示 AI 操作请求的自动风险评估结果。该类型在以下场景中发挥关键作用：

1. **自动审批流程**：当 AI 提交需要审批的操作（如执行命令、修改文件）时，Guardian 系统会进行风险评估并生成审查结果。

2. **实时通知**：通过 `item/autoApprovalReview/*` 通知向客户端推送审查状态变更，使用户界面能够实时显示审批进度。

3. **风险决策支持**：为用户提供结构化的风险评估信息（风险分数、风险等级、理由），辅助用户做出授权决策。

4. **审计追踪**：记录自动审批的完整决策过程，支持事后审计和分析。

**⚠️ 重要提示**：该类型被标记为 **UNSTABLE（不稳定）**，其结构预计在近期会发生变更。

## 功能点目的

`GuardianApprovalReview` 的设计目的是：

- **风险量化**：将操作风险转化为可量化的分数（0-100）和离散等级（低/中/高）
- **决策透明**：提供审批决策的理由说明，增强用户信任
- **状态追踪**：明确标识审批的生命周期状态（进行中/已批准/已拒绝/已中止）
- **自动化决策**：支持完全自动化的审批流程，减少用户干预

所有字段（除 `status` 外）均可为 `null`，因为：
- 审批进行中时，风险评估结果尚未确定
- 某些审批类型可能不需要详细的风险评估
- 系统错误可能导致评估信息缺失

## 具体技术实现

### 数据结构定义

```typescript
import type { GuardianApprovalReviewStatus } from "./GuardianApprovalReviewStatus";
import type { GuardianRiskLevel } from "./GuardianRiskLevel";

/**
 * [UNSTABLE] Temporary guardian approval review payload used by
 * `item/autoApprovalReview/*` notifications. This shape is expected to change
 * soon.
 */
export type GuardianApprovalReview = { 
  status: GuardianApprovalReviewStatus,  // 审批状态（进行中/已批准/已拒绝/已中止）
  riskScore: number | null,              // 风险分数（0-100）
  riskLevel: GuardianRiskLevel | null,   // 风险等级（低/中/高）
  rationale: string | null               // 审批决策的理由说明
};
```

### 关键字段说明

| 字段名 | 类型 | 可选性 | 说明 |
|--------|------|--------|------|
| `status` | `GuardianApprovalReviewStatus` | 必填 | 审批的生命周期状态。枚举值：`"inProgress"`、`"approved"`、`"denied"`、`"aborted"`。 |
| `riskScore` | `number \| null` | 可空 | 数值化的风险评分，范围通常为 0-100。数值越高表示风险越大。`null` 表示尚未评估或无法评估。 |
| `riskLevel` | `GuardianRiskLevel \| null` | 可空 | 离散化的风险等级。枚举值：`"low"`、`"medium"`、`"high"`。`null` 表示尚未评估或无法评估。 |
| `rationale` | `string \| null` | 可空 | 审批决策的自然语言解释。说明为什么批准或拒绝该操作，帮助用户理解决策依据。 |

### 状态转换图

```
┌─────────────┐
│  inProgress │◄──── 审批开始
└──────┬──────┘
       │
       ▼
┌─────────────────────────────────────┐
│           评估完成                   │
└──────┬──────────────────────┬───────┘
       │                      │
       ▼                      ▼
┌─────────────┐        ┌─────────────┐
│   approved  │        │   denied    │
└─────────────┘        └──────┬──────┘
                              │
                              ▼
                       ┌─────────────┐
                       │   aborted   │◄──── 用户取消/超时
                       └─────────────┘
```

## 关键代码路径与文件引用

- **TypeScript 源文件**: `codex-rs/app-server-protocol/schema/typescript/v2/GuardianApprovalReview.ts`
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (第 4313-4327 行)

### Rust 实现细节

```rust
/// [UNSTABLE] Temporary guardian approval review payload used by
/// `item/autoApprovalReview/*` notifications. This shape is expected to change
/// soon.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct GuardianApprovalReview {
    pub status: GuardianApprovalReviewStatus,
    #[serde(alias = "risk_score")]  // 支持遗留的 snake_case 格式
    #[ts(type = "number | null")]
    pub risk_score: Option<u8>,
    #[serde(alias = "risk_level")]  // 支持遗留的 snake_case 格式
    pub risk_level: Option<GuardianRiskLevel>,
    pub rationale: Option<String>,
}
```

### 使用位置

1. **ItemGuardianApprovalReviewStartedNotification**（第 4786 行）：审批开始通知
   ```rust
   pub struct ItemGuardianApprovalReviewStartedNotification {
       pub thread_id: String,
       pub turn_id: String,
       pub target_item_id: String,
       pub review: GuardianApprovalReview,
       pub action: Option<JsonValue>,
   }
   ```

2. **ItemGuardianApprovalReviewCompletedNotification**（第 4803 行）：审批完成通知
   ```rust
   pub struct ItemGuardianApprovalReviewCompletedNotification {
       pub thread_id: String,
       pub turn_id: String,
       pub target_item_id: String,
       pub review: GuardianApprovalReview,
       pub action: Option<JsonValue>,
   }
   ```

## 依赖与外部交互

### 上游依赖

- `GuardianApprovalReviewStatus`：审批状态枚举
- `GuardianRiskLevel`：风险等级枚举
- `serde`：序列化支持，包含 `alias` 属性用于向后兼容

### 下游消费者

- **通知系统**：通过 WebSocket/SSE 向客户端推送审批状态
- **UI 层**：在用户界面中展示审批进度和风险信息
- **审计日志**：记录审批历史用于合规审计

### 向后兼容性

Rust 实现使用 `#[serde(alias = "...")]` 支持遗留的 snake_case 字段名（`risk_score`、`risk_level`），确保旧版本客户端的兼容性。

## 风险、边界与改进建议

### 潜在风险

1. **API 不稳定**：明确标记为 UNSTABLE，生产环境使用需谨慎
2. **风险评估准确性**：自动风险评估可能存在误报或漏报
3. **理由质量**：`rationale` 字段的内容质量取决于 Guardian 系统的实现
4. **分数一致性**：不同操作类型的风险分数可能缺乏可比性

### 边界情况

1. **进行中状态**：`inProgress` 状态下，`riskScore`、`riskLevel`、`rationale` 通常为 `null`
2. **中止场景**：`aborted` 可能由用户取消、超时或系统错误触发
3. **零风险操作**：低风险操作可能直接批准，无需详细评估
4. **评估失败**：Guardian 系统故障时可能返回部分为 `null` 的结果

### 改进建议

1. **稳定性提升**：尽快稳定 API 设计，移除 UNSTABLE 标记
2. **结构化理由**：将 `rationale` 扩展为结构化对象，包含多个理由条目
3. **评估详情**：添加更详细的评估指标（如置信度、评估时间）
4. **分类信息**：添加风险类别（如安全、隐私、性能）
5. **建议操作**：添加 Guardian 建议的用户操作（如"建议拒绝"、"需要人工审核"）
6. **历史对比**：添加与类似操作历史审批结果的对比信息

### 已知问题与 TODO

根据代码注释，存在以下已知改进方向：

> TODO(ccunningham): Attach guardian review state to the reviewed tool item's
> lifecycle instead of sending separate standalone review notifications so the
> app-server API can persist and replay review state via `thread/read`.

**建议**：将 Guardian 审查状态附加到被审查工具项的生命周期中，而不是发送独立的通知，这样 app-server API 可以通过 `thread/read` 持久化和回放审查状态。

### 测试覆盖

根据代码中的测试用例（第 7431-7468 行），已验证：

1. **遗留格式兼容**：支持 snake_case 字段名（`risk_score`、`risk_level`）
2. **aborted 状态处理**：正确处理中止状态的反序列化
3. **null 值处理**：正确处理所有字段为 `null` 的情况

### 兼容性注意事项

- 该类型处于活跃开发中，结构可能变更
- 客户端应做好字段缺失和类型变更的容错处理
- 类型由 `ts-rs` 自动生成，手动修改会被覆盖
- 建议使用可选链操作符（`?.`）访问嵌套属性
