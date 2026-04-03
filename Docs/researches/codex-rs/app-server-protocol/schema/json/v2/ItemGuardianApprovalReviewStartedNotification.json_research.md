# ItemGuardianApprovalReviewStartedNotification.json 研究文档

## 场景与职责

`ItemGuardianApprovalReviewStartedNotification` 是 Codex App Server Protocol v2 中的服务器通知类型，用于通知客户端 Guardian（守护者）自动审批审查已开始。这是 Guardian 审查流程的起始通知，与 `ItemGuardianApprovalReviewCompletedNotification` 配对使用，共同构成完整的 Guardian 审查生命周期通知。

**重要提示**: 该 API 被标记为 `[UNSTABLE]`，表示其形状预计会发生变化。

## 功能点目的

1. **审查开始通知**：通知客户端 Guardian 已开始对特定操作项进行自动审批审查
2. **UI 反馈**：支持客户端显示审查中的加载状态或进度指示
3. **超时管理**：客户端可基于开始时间戳管理审查超时
4. **流程跟踪**：与 Completed 通知配对，形成完整的审查流程追踪

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

### 与 Completed 通知的结构对比

`ItemGuardianApprovalReviewStartedNotification` 和 `ItemGuardianApprovalReviewCompletedNotification` 共享完全相同的结构：

| 字段 | 类型 | Started 状态 | Completed 状态 |
|------|------|--------------|----------------|
| `review.status` | enum | `inProgress` | `approved`/`denied`/`aborted` |
| `review.riskScore` | uint8/null | 可能为 null | 通常有值 |
| `review.riskLevel` | enum/null | 可能为 null | 通常有值 |
| `review.rationale` | string/null | 可能为 null | 通常有值 |
| `targetItemId` | string | 被审查项 ID | 被审查项 ID |
| `threadId` | string | 线程 ID | 线程 ID |
| `turnId` | string | 回合 ID | 回合 ID |
| `action` | any | 操作详情 | 操作详情 |

### 协议映射

Rust 结构体定义（v2.rs）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
/// [UNSTABLE] Temporary notification payload for guardian automatic approval review...
pub struct ItemGuardianApprovalReviewStartedNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub target_item_id: String,
    pub review: GuardianApprovalReview,
    pub action: Option<JsonValue>,
}
```

服务器通知枚举（common.rs）：
```rust
server_notification_definitions! {
    ItemGuardianApprovalReviewStarted => "item/autoApprovalReview/started" (v2::ItemGuardianApprovalReviewStartedNotification),
    ItemGuardianApprovalReviewCompleted => "item/autoApprovalReview/completed" (v2::ItemGuardianApprovalReviewCompletedNotification),
}
```

Wire 格式：
- Started: `method: "item/autoApprovalReview/started"`
- Completed: `method: "item/autoApprovalReview/completed"`

### 事件生成逻辑

在 `bespoke_event_handling.rs` 中（行 191-249）：

```rust
fn guardian_auto_approval_review_notification(
    conversation_id: &ThreadId,
    event_turn_id: &str,
    assessment: &GuardianAssessmentEvent,
) -> ServerNotification {
    // ... 构造 review 对象 ...
    
    match assessment.status {
        GuardianAssessmentStatus::InProgress => {
            ServerNotification::ItemGuardianApprovalReviewStarted(
                ItemGuardianApprovalReviewStartedNotification {
                    thread_id: conversation_id.to_string(),
                    turn_id,
                    target_item_id: assessment.id.clone(),
                    review,
                    action: assessment.action.clone(),
                },
            )
        }
        // ... Completed 分支 ...
    }
}
```

## 关键代码路径与文件引用

### 核心定义文件

1. **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/ItemGuardianApprovalReviewStartedNotification.json`
2. **Rust 结构体**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 4777-4792)
3. **GuardianApprovalReview**: `v2.rs` 行 4316-4327
4. **协议枚举**: `codex-rs/app-server-protocol/src/protocol/common.rs` (行 892-893)

### 相关类型定义

- `GuardianApprovalReviewStatus`: `v2.rs` 行 4286-4291
- `GuardianRiskLevel`: `v2.rs` 行 4297-4301
- `GuardianApprovalReview`: `v2.rs` 行 4316-4327

### 事件处理

- **生成逻辑**: `codex-rs/app-server/src/bespoke_event_handling.rs` 行 191-249
- **事件监听**: `EventMsg::GuardianAssessment` 处理分支

### 测试文件

- `codex-rs/app-server/tests/suite/v2/safety_check_downgrade.rs`
- `codex-rs/tui_app_server/src/chatwidget.rs`
- `codex-rs/tui_app_server/src/app/app_server_adapter.rs`

## 依赖与外部交互

### 内部依赖

1. **核心协议**: 
   - `codex_protocol::protocol::GuardianAssessmentEvent`
   - `codex_protocol::protocol::GuardianAssessmentStatus`
   - `codex_protocol::protocol::GuardianRiskLevel`

2. **序列化**: `serde`, `serde_json::Value`

### 外部交互

| 组件 | 交互方式 | 说明 |
|------|----------|------|
| Guardian 子代理 | 内部事件 | 触发 Started 通知 |
| TUI 客户端 | WebSocket | 显示审查中状态 |
| 监控系统 | 指标收集 | 跟踪审查延迟 |

### 生成产物

- TypeScript: `typescript/v2/ItemGuardianApprovalReviewStartedNotification.ts`
- 合并 Schema: `json/codex_app_server_protocol.v2.schemas.json`

## 风险、边界与改进建议

### API 不稳定警告

与 Completed 通知相同，此 API 被标记为不稳定：

> [UNSTABLE] Temporary notification payload for guardian automatic approval review. This shape is expected to change soon.

### 生命周期管理

典型的 Guardian 审查生命周期：

```
操作项创建
    ↓
ItemStarted (操作开始)
    ↓
ItemGuardianApprovalReviewStarted (审查开始)
    ↓
[Guardian 评估中...]
    ↓
ItemGuardianApprovalReviewCompleted (审查完成)
    ↓
操作执行 / 被拒绝
    ↓
ItemCompleted (操作完成)
```

### 边界情况

1. **快速完成**: Guardian 可能极快完成审查，Started 和 Completed 通知可能几乎同时到达
2. **审查中止**: 可能收到 `aborted` 状态的 Completed 通知，而无明确原因
3. **重复通知**: 网络重连后可能重复收到 Started 通知

### 改进建议

1. **添加时间戳**: 添加 `startedAt` 时间戳，便于计算审查耗时
2. **审查版本**: 添加 Guardian 配置版本，便于追踪行为变化
3. **超时提示**: 在 Started 通知中建议超时时间
4. **取消机制**: 提供客户端取消 Guardian 审查的机制

### 客户端实现建议

```typescript
// 示例：处理 Guardian 审查通知
class GuardianReviewHandler {
  private pendingReviews = new Map<string, {
    startedAt: number;
    timeoutId: NodeJS.Timeout;
  }>();

  handleStarted(notification: ItemGuardianApprovalReviewStartedNotification) {
    const key = `${notification.threadId}:${notification.targetItemId}`;
    
    // 记录开始时间
    this.pendingReviews.set(key, {
      startedAt: Date.now(),
      timeoutId: setTimeout(() => {
        this.handleTimeout(key);
      }, 30000) // 30秒超时
    });
    
    // 更新 UI 显示审查中
    this.ui.showReviewPending(notification.targetItemId);
  }

  handleCompleted(notification: ItemGuardianApprovalReviewCompletedNotification) {
    const key = `${notification.threadId}:${notification.targetItemId}`;
    const pending = this.pendingReviews.get(key);
    
    if (pending) {
      clearTimeout(pending.timeoutId);
      const duration = Date.now() - pending.startedAt;
      this.pendingReviews.delete(key);
      
      // 记录审查耗时
      this.metrics.recordReviewDuration(duration);
    }
    
    // 处理审查结果
    switch (notification.review.status) {
      case 'approved':
        this.ui.showReviewApproved(notification.targetItemId, notification.review);
        break;
      case 'denied':
        this.ui.showReviewDenied(notification.targetItemId, notification.review);
        break;
      case 'aborted':
        this.ui.showReviewAborted(notification.targetItemId);
        break;
    }
  }
}
```

### 与 Completed 通知的关系

两个通知共享相同的结构，但语义不同：

| 方面 | Started | Completed |
|------|---------|-----------|
| 触发时机 | 审查开始时 | 审查结束时 |
| status 值 | 固定 `inProgress` | `approved`/`denied`/`aborted` |
| risk 字段 | 通常为 null | 通常有值 |
| 用途 | UI 加载状态 | 最终决策展示 |

客户端应始终配对处理这两个通知，确保状态一致性。
