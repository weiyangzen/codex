# ItemGuardianApprovalReviewCompletedNotification.json 研究文档

## 场景与职责

`ItemGuardianApprovalReviewCompletedNotification` 是 Codex App Server Protocol v2 中的服务器通知类型，用于通知客户端 Guardian（守护者）自动审批审查已完成。Guardian 是一个基于子代理的风险评估系统，用于自动审查敏感操作（如代码执行、文件变更等）并做出批准或拒绝决策。

**重要提示**: 该 API 被标记为 `[UNSTABLE]`，表示其形状预计会发生变化。

## 功能点目的

1. **自动审批通知**：通知客户端 Guardian 已完成对特定操作项的自动审批审查
2. **风险评估传递**：传递 Guardian 评估的风险等级、风险分数和决策理由
3. **审计追踪**：提供 Guardian 决策的审计记录
4. **用户透明**：让用户了解哪些操作被自动审批及其原因

## 具体技术实现

### 数据结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "description": "[UNSTABLE] Temporary notification payload for guardian automatic approval review...",
  "properties": {
    "action": true,
    "review": { "$ref": "#/definitions/GuardianApprovalReview" },
    "targetItemId": { "type": "string" },
    "threadId": { "type": "string" },
    "turnId": { "type": "string" }
  },
  "required": ["review", "targetItemId", "threadId", "turnId"]
}
```

### GuardianApprovalReview 定义

| 字段 | 类型 | 说明 |
|------|------|------|
| `status` | enum (required) | 审查状态：`inProgress`, `approved`, `denied`, `aborted` |
| `riskScore` | uint8/null | 风险分数（0-255），数值越高风险越大 |
| `riskLevel` | enum/null | 风险等级：`low`, `medium`, `high` |
| `rationale` | string/null | 决策理由说明 |

### GuardianApprovalReviewStatus 枚举

- `inProgress`: 审查进行中
- `approved`: 已批准
- `denied`: 已拒绝
- `aborted`: 已中止（可能由于超时或错误）

### GuardianRiskLevel 枚举

- `low`: 低风险
- `medium`: 中等风险
- `high`: 高风险

### 协议映射

Rust 结构体定义（v2.rs）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
/// [UNSTABLE] Temporary notification payload for guardian automatic approval review...
pub struct ItemGuardianApprovalReviewCompletedNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub target_item_id: String,
    pub review: GuardianApprovalReview,
    pub action: Option<JsonValue>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct GuardianApprovalReview {
    pub status: GuardianApprovalReviewStatus,
    #[serde(alias = "risk_score")]
    #[ts(type = "number | null")]
    pub risk_score: Option<u8>,
    #[serde(alias = "risk_level")]
    pub risk_level: Option<GuardianRiskLevel>,
    pub rationale: Option<String>,
}
```

服务器通知枚举（common.rs）：
```rust
server_notification_definitions! {
    ItemGuardianApprovalReviewStarted => "item/autoApprovalReview/started" (v2::ItemGuardianApprovalReviewStartedNotification),
    ItemGuardianApprovalReviewCompleted => "item/autoApprovalReview/completed" (v2::ItemGuardianApprovalReviewCompletedNotification),
}
```

### 事件生成逻辑

在 `bespoke_event_handling.rs` 中（行 191-249）：

```rust
fn guardian_auto_approval_review_notification(
    conversation_id: &ThreadId,
    event_turn_id: &str,
    assessment: &GuardianAssessmentEvent,
) -> ServerNotification {
    let review = GuardianApprovalReview {
        status: match assessment.status {
            GuardianAssessmentStatus::InProgress => GuardianApprovalReviewStatus::InProgress,
            GuardianAssessmentStatus::Approved => GuardianApprovalReviewStatus::Approved,
            GuardianAssessmentStatus::Denied => GuardianApprovalReviewStatus::Denied,
            GuardianAssessmentStatus::Aborted => GuardianApprovalReviewStatus::Aborted,
        },
        risk_score: assessment.risk_score,
        risk_level: assessment.risk_level.map(Into::into),
        rationale: assessment.rationale.clone(),
    };
    
    // 根据状态返回 Started 或 Completed 通知
    match assessment.status {
        GuardianAssessmentStatus::InProgress => { /* ... */ }
        _ => ServerNotification::ItemGuardianApprovalReviewCompleted(...)
    }
}
```

## 关键代码路径与文件引用

### 核心定义文件

1. **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/ItemGuardianApprovalReviewCompletedNotification.json`
2. **Rust 结构体**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 4794-4809)
3. **GuardianApprovalReview**: `v2.rs` 行 4316-4327
4. **协议枚举**: `codex-rs/app-server-protocol/src/protocol/common.rs` (行 892-893)

### 事件处理

- **生成逻辑**: `codex-rs/app-server/src/bespoke_event_handling.rs` 行 191-249
- **事件类型**: `GuardianAssessmentEvent` (来自 `codex_protocol`)

### 测试文件

- `codex-rs/app-server/tests/suite/v2/safety_check_downgrade.rs`
- `codex-rs/tui_app_server/src/chatwidget.rs`
- `codex-rs/tui_app_server/src/chatwidget/tests.rs`

## 依赖与外部交互

### 内部依赖

1. **核心协议**: `codex_protocol::protocol::GuardianAssessmentEvent`, `GuardianAssessmentStatus`
2. **核心枚举**: `codex_protocol::protocol::GuardianRiskLevel`
3. **序列化**: `serde`, `serde_json::Value` (用于 action 字段)

### 外部交互

| 组件 | 交互 |
|------|------|
| Guardian 子代理 | 触发评估事件 |
| TUI 客户端 | 显示审批结果和风险信息 |
| 审计系统 | 记录审批决策 |

### 生成产物

- TypeScript: `typescript/v2/ItemGuardianApprovalReviewCompletedNotification.ts`

## 风险、边界与改进建议

### 重要提示：API 不稳定

源码中的描述明确指出：
> [UNSTABLE] Temporary guardian approval review payload used by `item/autoApprovalReview/*` notifications. This shape is expected to change soon.

以及 TODO 注释：
> TODO(ccunningham): Attach guardian review state to the reviewed tool item's lifecycle instead of sending separate standalone review notifications so the app-server API can persist and replay review state via `thread/read`.

### 当前限制

1. **独立通知**: Guardian 审查状态作为独立通知发送，而不是附加到工具项生命周期
2. **无法持久化**: 无法通过 `thread/read` 回放审查状态
3. **action 字段类型**: `action` 字段使用 `JsonValue`，类型不安全

### 改进建议

1. **API 稳定性**: 等待官方稳定化此 API 后再大规模使用
2. **状态整合**: 按照 TODO 建议，将审查状态整合到工具项中
3. **类型安全**: 为 `action` 字段定义具体类型，替代 `JsonValue`
4. **更多元数据**: 添加 Guardian 使用的模型、提示词版本等信息
5. **可配置性**: 允许客户端配置 Guardian 的敏感度阈值

### 风险等级解释

| 风险等级 | 分数范围 | 建议操作 |
|----------|----------|----------|
| low | 0-85 | 通常自动批准 |
| medium | 86-170 | 可能需要人工审查 |
| high | 171-255 | 通常自动拒绝或强制人工审查 |

**注意**: 实际分数阈值可能因配置而异。

### 迁移准备

由于 API 预计会变化，客户端应：
1. 实现防御性编程，处理字段缺失
2. 不依赖特定字段存在
3. 关注官方更新，准备迁移
