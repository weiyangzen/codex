# GuardianApprovalReviewStatus.ts Research Document

## 场景与职责

`GuardianApprovalReviewStatus` 类型定义了 Guardian 自动审批系统的生命周期状态枚举。该类型在以下场景中发挥核心作用：

1. **审批状态追踪**：标识单个操作请求的审批流程当前所处的阶段，从发起审批到最终决策的完整生命周期管理。

2. **UI 状态渲染**：驱动用户界面的审批状态展示，包括进度指示器、状态徽章、操作按钮的启用/禁用状态。

3. **流程控制**：作为状态机的基础，控制审批流程的流转逻辑，决定哪些操作在特定状态下是合法的。

4. **事件通知**：在审批状态变更时触发相应的通知事件，使系统各组件能够响应状态变化。

**⚠️ 重要提示**：该类型被标记为 **UNSTABLE（不稳定）**，其定义预计在近期会发生变更。

## 功能点目的

`GuardianApprovalReviewStatus` 的设计目的是：

- **明确生命周期**：清晰定义审批流程的各个阶段，避免状态歧义
- **支持异步流程**：`inProgress` 状态支持耗时较长的风险评估操作
- **完整结果覆盖**：涵盖所有可能的审批结果（批准、拒绝、中止）
- **可扩展性**：枚举结构便于未来添加新的状态（如"待人工审核"）

### 状态语义

| 状态值 | 语义 |
|--------|------|
| `inProgress` | 审批正在进行中，风险评估尚未完成 |
| `approved` | 审批通过，操作被允许执行 |
| `denied` | 审批被拒绝，操作不被允许执行 |
| `aborted` | 审批被中止（用户取消、超时或系统错误） |

## 具体技术实现

### 数据结构定义

```typescript
/**
 * [UNSTABLE] Lifecycle state for a guardian approval review.
 */
export type GuardianApprovalReviewStatus = "inProgress" | "approved" | "denied" | "aborted";
```

### 关键字段说明

这是一个字符串字面量联合类型（String Literal Union Type），包含四个可能的值：

| 值 | 类型 | 说明 |
|----|------|------|
| `"inProgress"` | 字符串字面量 | 审批进行中状态。表示 Guardian 系统正在评估操作风险，尚未做出最终决策。此状态下通常会显示加载指示器。 |
| `"approved"` | 字符串字面量 | 审批通过状态。表示 Guardian 评估认为操作风险可接受，允许执行。这是成功的终态之一。 |
| `"denied"` | 字符串字面量 | 审批拒绝状态。表示 Guardian 评估认为操作风险过高，不允许执行。这是失败的终态之一。 |
| `"aborted"` | 字符串字面量 | 审批中止状态。表示审批流程被中断，可能原因包括：用户主动取消、操作超时、系统错误或依赖服务不可用。 |

### 状态机模型

```
                    ┌─────────────────────────────────────┐
                    │           用户发起操作                │
                    └───────────────┬─────────────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────────┐
         ┌─────────│          inProgress           │◄──── 审批开始
         │         │        （评估进行中）          │
         │         └───────────────┬───────────────┘
         │                         │
         │    ┌────────────────────┼────────────────────┐
         │    │                    │                    │
         │    ▼                    ▼                    ▼
         │ ┌─────────┐      ┌─────────────┐      ┌───────────┐
         └►│approved │      │   denied    │      │  aborted  │
           │（已批准）│      │  （已拒绝）  │      │ （已中止） │
           └────┬────┘      └──────┬──────┘      └─────┬─────┘
                │                  │                   │
                ▼                  ▼                   ▼
           ┌─────────┐      ┌─────────────┐      ┌───────────┐
           │执行操作  │      │  阻止操作    │      │  清理资源  │
           └─────────┘      └─────────────┘      └───────────┘
```

## 关键代码路径与文件引用

- **TypeScript 源文件**: `codex-rs/app-server-protocol/schema/typescript/v2/GuardianApprovalReviewStatus.ts`
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (第 4283-4291 行)

### Rust 实现细节

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
/// [UNSTABLE] Lifecycle state for a guardian approval review.
pub enum GuardianApprovalReviewStatus {
    InProgress,
    Approved,
    Denied,
    Aborted,
}
```

### 序列化映射

| Rust 变体 | JSON 值 | TypeScript 值 |
|-----------|---------|---------------|
| `InProgress` | `"inProgress"` | `"inProgress"` |
| `Approved` | `"approved"` | `"approved"` |
| `Denied` | `"denied"` | `"denied"` |
| `Aborted` | `"aborted"` | `"aborted"` |

### 使用位置

1. **GuardianApprovalReview**（第 4319 行）：作为审批结果的核心状态字段
   ```rust
   pub struct GuardianApprovalReview {
       pub status: GuardianApprovalReviewStatus,
       // ...
   }
   ```

2. **测试用例**（第 7432、7452 行）：验证状态反序列化
   ```rust
   let review: GuardianApprovalReview = serde_json::from_value(json!({
       "status": "denied",  // 或 "aborted"
       // ...
   }))
   ```

## 依赖与外部交互

### 上游依赖

- 无直接依赖（基础枚举类型）

### 下游消费者

- `GuardianApprovalReview`：包含此状态作为核心字段
- **通知系统**：`ItemGuardianApprovalReviewStartedNotification`、`ItemGuardianApprovalReviewCompletedNotification`
- **UI 组件**：状态徽章、进度指示器、操作按钮
- **状态机逻辑**：控制审批流程的流转

### 核心协议映射

```rust
// v2.rs 中的转换实现
impl From<CoreGuardianApprovalReviewStatus> for GuardianApprovalReviewStatus {
    fn from(value: CoreGuardianApprovalReviewStatus) -> Self {
        match value {
            CoreGuardianApprovalReviewStatus::InProgress => Self::InProgress,
            CoreGuardianApprovalReviewStatus::Approved => Self::Approved,
            CoreGuardianApprovalReviewStatus::Denied => Self::Denied,
            CoreGuardianApprovalReviewStatus::Aborted => Self::Aborted,
        }
    }
}
```

## 风险、边界与改进建议

### 潜在风险

1. **API 不稳定**：明确标记为 UNSTABLE，可能在未来的版本中变更或扩展
2. **状态歧义**：`denied` 和 `aborted` 在某些场景下可能被混淆使用
3. **缺少中间状态**：当前只有四个状态，可能不足以覆盖复杂的审批流程
4. **无时间信息**：状态本身不包含时间戳，需要配合其他字段使用

### 边界情况

1. **状态回退**：当前设计不支持状态回退（如从 `denied` 回到 `inProgress`）
2. **并发审批**：多个审批同时进行时的状态管理
3. **状态持久化**：服务重启后的状态恢复
4. **终态识别**：`approved`、`denied`、`aborted` 都是终态，但客户端需要显式判断

### 改进建议

1. **添加中间状态**：
   - `pending`：等待用户确认
   - `queued`：在队列中等待处理
   - `reviewing`：人工审核中

2. **添加元数据**：
   - 状态变更时间戳
   - 状态变更原因
   - 状态变更操作者

3. **状态分组**：
   - 提供辅助函数判断是否为终态
   - 提供辅助函数判断是否成功

4. **扩展中止原因**：
   - `aborted` 可细分为 `userCancelled`、`timeout`、`systemError` 等

5. **稳定 API**：
   - 尽快确定最终设计并移除 UNSTABLE 标记

### TypeScript 使用模式

```typescript
// 状态检查辅助函数
function isTerminalStatus(status: GuardianApprovalReviewStatus): boolean {
  return status === 'approved' || status === 'denied' || status === 'aborted';
}

function isSuccessStatus(status: GuardianApprovalReviewStatus): boolean {
  return status === 'approved';
}

//  exhaustive switch 示例
function getStatusDisplayText(status: GuardianApprovalReviewStatus): string {
  switch (status) {
    case 'inProgress':
      return '评估中...';
    case 'approved':
      return '已批准';
    case 'denied':
      return '已拒绝';
    case 'aborted':
      return '已中止';
    default:
      // TypeScript 会在此检查 exhaustive
      const _exhaustive: never = status;
      return '未知状态';
  }
}
```

### 兼容性注意事项

- 该类型处于活跃开发中，可能添加新的状态值
- 客户端应使用 exhaustive switch 或默认分支处理未知状态
- 类型由 `ts-rs` 自动生成，手动修改会被覆盖
- JSON 传输使用 camelCase 命名
