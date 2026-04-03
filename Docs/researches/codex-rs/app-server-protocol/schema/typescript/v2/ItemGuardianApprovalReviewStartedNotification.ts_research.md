# ItemGuardianApprovalReviewStartedNotification 研究文档

## 1. 场景与职责

`ItemGuardianApprovalReviewStartedNotification` 是 App-Server Protocol v2 中的通知类型，用于在 Guardian（安全守护系统）开始对某个项目进行自动审核时向客户端发送通知。**该类型标记为 [UNSTABLE]，API 可能会在未来版本中变更。**

**主要使用场景：**
- Guardian 系统开始自动安全审核
- 通知客户端审核正在进行中
- 客户端显示审核进度或等待指示
- 安全审计记录审核开始时间

## 2. 功能点目的

该类型的核心目的是通知客户端 Guardian 审核已开始：

1. **审核定位**：通过 `threadId`、`turnId` 和 `targetItemId` 确定被审核的项目
2. **审核信息**：通过 `review` 字段提供审核的初始信息
3. **预期动作**：通过 `action` 字段提供预期的后续操作（如果有）

这个设计使得客户端能够：
- 了解哪些项目正在等待安全审核
- 向用户显示审核中状态
- 预估审核完成时间
- 为审核结果做准备

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type ItemGuardianApprovalReviewStartedNotification = { 
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
pub struct ItemGuardianApprovalReviewStartedNotification {
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
| `review` | `GuardianApprovalReview` | Guardian 审核的初始信息 |
| `action` | `JsonValue \| null` | 预期的后续操作（JSON 格式） |

### 特性注解

- `#[serde(rename_all = "camelCase")]`：字段序列化为 camelCase 格式
- `#[ts(export_to = "v2/")]`：TypeScript 类型导出到 `v2/` 目录
- 标记为 `[UNSTABLE]`，API 可能变更
- 包含 TODO 注释说明未来改进方向

## 4. 关键代码路径与文件引用

### Rust 源文件

- **主定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 第 4777-4792 行

### 相关通知类型

- `ItemGuardianApprovalReviewCompletedNotification`：Guardian 审核完成通知（第 4794-4809 行）
- `ItemStartedNotification`：项目开始通知（第 4768-4775 行）
- `ItemCompletedNotification`：项目完成通知（第 4811-4818 行）

### 依赖类型

- `GuardianApprovalReview`：Guardian 审核结果类型
- `JsonValue`：JSON 值类型（来自 `serde_json`）

## 5. 依赖与外部交互

### 导入类型

| 类型 | 来源 | 说明 |
|------|------|------|
| `GuardianApprovalReview` | 同文件定义 | Guardian 审核信息 |
| `JsonValue` | `serde_json` | 动态 JSON 值类型 |

### 序列化行为

- 使用 `serde` 进行 JSON 序列化/反序列化
- 字段名自动转换为 camelCase
- `action` 字段为可选的 JSON 值

## 6. 风险、边界与改进建议

### 潜在风险

1. **API 不稳定**：标记为 `[UNSTABLE]`，可能在任何版本中变更
2. **TODO 未解决**：当前实现是临时的，计划将审核状态附加到工具项目生命周期
3. **通知丢失**：开始通知可能丢失，导致客户端不知道审核正在进行
4. **状态不一致**：独立的通知可能导致状态与实际情况不一致

### 边界情况

- 审核开始后客户端才连接
- 审核立即完成（开始和完成通知几乎同时到达）
- 审核被取消或超时
- 多个项目同时进入审核状态

### 改进建议

1. **API 稳定化**：
   - 解决 TODO 中提到的设计问题
   - 将审核状态集成到 `ThreadItem` 生命周期
   - 支持通过 `thread/read` 获取当前审核状态

2. **可靠性增强**：
   - 实现开始通知的确认机制
   - 支持状态同步查询
   - 添加审核超时的通知

3. **用户体验**：
   - 添加预计审核时间
   - 支持审核进度更新
   - 允许用户取消审核（如果适用）

4. **可观测性**：
   - 记录审核开始时间
   - 统计审核队列长度
   - 监控审核耗时分布

### 与完成通知的关系

| 通知类型 | 触发时机 | 用途 |
|----------|----------|------|
| `ItemGuardianApprovalReviewStartedNotification` | Guardian 开始审核时 | 显示审核中状态 |
| `ItemGuardianApprovalReviewCompletedNotification` | Guardian 审核完成时 | 显示审核结果 |

### 使用警告

⚠️ **重要提示**：
- 该 API 不稳定，生产环境使用需谨慎
- 客户端应同时处理开始和完成通知
- 考虑实现超时机制处理丢失的开始通知
- 关注版本更新日志中的 API 变更
