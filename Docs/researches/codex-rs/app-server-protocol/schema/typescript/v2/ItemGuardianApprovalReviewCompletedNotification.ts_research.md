# ItemGuardianApprovalReviewCompletedNotification 研究文档

## 1. 场景与职责

`ItemGuardianApprovalReviewCompletedNotification` 是 App-Server Protocol v2 中的通知类型，用于在 Guardian（安全守护系统）完成对某个项目的自动审核后向客户端发送通知。**该类型标记为 [UNSTABLE]，API 可能会在未来版本中变更。**

**主要使用场景：**
- Guardian 系统完成自动安全审核
- 通知客户端审核结果（批准/拒绝）
- 触发后续操作（如执行被批准的工具调用）
- 安全审计和合规性记录

## 2. 功能点目的

该类型的核心目的是通知客户端 Guardian 审核已完成：

1. **审核定位**：通过 `threadId`、`turnId` 和 `targetItemId` 确定被审核的项目
2. **审核结果**：通过 `review` 字段提供详细的审核信息
3. **后续动作**：通过 `action` 字段提供建议的后续操作

这个设计使得客户端能够：
- 了解哪些项目通过了安全审核
- 根据审核结果采取相应行动
- 向用户展示审核状态
- 维护安全合规性记录

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type ItemGuardianApprovalReviewCompletedNotification = { 
  threadId: string, 
  turnId: string, 
  targetItemId: string, 
  review: GuardianApprovalReview, 
  action: JsonValue | null, 
};
```

### Rust 源定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
/// [UNSTABLE] Temporary notification payload for guardian automatic approval
/// review. This shape is expected to change soon.
///
/// TODO(ccunningham): Attach guardian review state to the reviewed tool item's
/// lifecycle instead of sending separate standalone review notifications so the
/// app-server API can persist and replay review state via `thread/read`.
pub struct ItemGuardianApprovalReviewCompletedNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub target_item_id: String,
    pub review: GuardianApprovalReview,
    pub action: Option<JsonValue>,
}
```

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 线程ID，标识被审核项目所属的会话线程 |
| `turnId` | `string` | 回合ID，标识被审核项目所属的具体回合 |
| `targetItemId` | `string` | 被审核的目标项目ID |
| `review` | `GuardianApprovalReview` | Guardian 审核的详细结果 |
| `action` | `JsonValue \| null` | 建议的后续操作（JSON 格式） |

### 特性注解

- `#[serde(rename_all = "camelCase")]`：字段序列化为 camelCase 格式
- `#[ts(export_to = "v2/")]`：TypeScript 类型导出到 `v2/` 目录
- 标记为 `[UNSTABLE]`，API 可能变更
- 包含 TODO 注释说明未来改进方向

## 4. 关键代码路径与文件引用

### Rust 源文件

- **主定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 第 4794-4809 行

### 相关通知类型

- `ItemGuardianApprovalReviewStartedNotification`：Guardian 审核开始通知（第 4777-4792 行）
- `ItemStartedNotification`：项目开始通知（第 4768-4775 行）
- `ItemCompletedNotification`：项目完成通知（第 4811-4818 行）

### 依赖类型

- `GuardianApprovalReview`：Guardian 审核结果类型
- `JsonValue`：JSON 值类型（来自 `serde_json`）

## 5. 依赖与外部交互

### 导入类型

| 类型 | 来源 | 说明 |
|------|------|------|
| `GuardianApprovalReview` | 同文件定义 | Guardian 审核结果详情 |
| `JsonValue` | `serde_json` | 动态 JSON 值类型 |

### 序列化行为

- 使用 `serde` 进行 JSON 序列化/反序列化
- 字段名自动转换为 camelCase
- `action` 字段为可选的 JSON 值

## 6. 风险、边界与改进建议

### 潜在风险

1. **API 不稳定**：标记为 `[UNSTABLE]`，可能在任何版本中变更
2. **TODO 未解决**：当前实现是临时的，计划将审核状态附加到工具项目生命周期
3. **状态同步**：独立的通知可能导致状态不一致
4. **持久化问题**：当前设计不支持通过 `thread/read` 重放审核状态

### 边界情况

- 审核完成时客户端离线
- 审核结果与项目实际状态不一致
- `action` 字段的解析失败
- 并发审核的竞争条件

### 改进建议

1. **API 稳定化**：
   - 解决 TODO 中提到的设计问题
   - 将审核状态集成到 `ThreadItem` 生命周期
   - 支持通过 `thread/read` 获取历史审核状态

2. **状态管理**：
   - 实现审核状态的持久化
   - 支持审核历史的查询和重放
   - 添加审核状态变更的通知机制

3. **安全性增强**：
   - 添加审核结果的签名验证
   - 实现审核日志的不可篡改存储
   - 支持多级审核和人工复核

4. **可观测性**：
   - 添加审核耗时指标
   - 记录审核决策依据
   - 支持审核结果的导出和分析

### 与开始通知的关系

| 通知类型 | 触发时机 | 状态转换 |
|----------|----------|----------|
| `ItemGuardianApprovalReviewStartedNotification` | Guardian 开始审核时 | 无 → 审核中 |
| `ItemGuardianApprovalReviewCompletedNotification` | Guardian 审核完成时 | 审核中 → 已审核 |

### 使用警告

⚠️ **重要提示**：
- 该 API 不稳定，生产环境使用需谨慎
- 建议实现版本检查机制
- 关注版本更新日志中的 API 变更
- 考虑实现降级策略以应对 API 变更
