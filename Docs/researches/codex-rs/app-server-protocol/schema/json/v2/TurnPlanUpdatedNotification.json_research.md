# TurnPlanUpdatedNotification.json 研究文档

## 场景与职责

`TurnPlanUpdatedNotification` 是 Codex App-Server Protocol v2 中定义的服务器向客户端发送的通知类型，用于实时报告 Turn（对话轮次）的计划（Plan）更新。这是 AI 助手展示其思考过程和行动计划的核心机制，让用户能够理解 AI 将要执行的步骤。

典型使用场景：
- AI 助手生成多步骤计划来完成用户请求
- 用户需要了解 AI 将要执行的操作序列
- 复杂任务需要分阶段执行和展示
- 用户想要审查或修改 AI 的计划

## 功能点目的

该通知的主要目的是：
1. **透明度**：展示 AI 的思考过程和计划步骤
2. **用户信任**：让用户了解 AI 将要做什么
3. **进度追踪**：显示计划执行的进度
4. **交互控制**：支持用户基于计划进行干预

### Plan 结构

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | string | Thread 标识符 |
| `turnId` | string | Turn 标识符 |
| `explanation` | string \| null | 计划的解释说明 |
| `plan` | TurnPlanStep[] | 计划步骤列表 |

### TurnPlanStep 结构

| 字段 | 类型 | 说明 |
|------|------|------|
| `step` | string | 步骤描述 |
| `status` | TurnPlanStepStatus | 步骤状态 |

### TurnPlanStepStatus 状态

| 状态 | 说明 |
|------|------|
| `pending` | 步骤待执行 |
| `inProgress` | 步骤正在执行 |
| `completed` | 步骤已完成 |

## 具体技术实现

### JSON Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "TurnPlanStep": {
      "properties": {
        "status": { "$ref": "#/definitions/TurnPlanStepStatus" },
        "step": { "type": "string" }
      },
      "required": ["status", "step"]
    },
    "TurnPlanStepStatus": {
      "enum": ["pending", "inProgress", "completed"],
      "type": "string"
    }
  },
  "properties": {
    "explanation": { "type": ["string", "null"] },
    "plan": {
      "items": { "$ref": "#/definitions/TurnPlanStep" },
      "type": "array"
    },
    "threadId": { "type": "string" },
    "turnId": { "type": "string" }
  },
  "required": ["plan", "threadId", "turnId"]
}
```

### Rust 实现

位于 `codex-rs/app-server-protocol/src/protocol/v2.rs`（行 4722-4766）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TurnPlanUpdatedNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub explanation: Option<String>,
    pub plan: Vec<TurnPlanStep>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TurnPlanStep {
    pub step: String,
    pub status: TurnPlanStepStatus,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum TurnPlanStepStatus {
    Pending,
    InProgress,
    Completed,
}
```

### 从核心类型转换

```rust
impl From<CorePlanItemArg> for TurnPlanStep {
    fn from(value: CorePlanItemArg) -> Self {
        Self {
            step: value.step,
            status: value.status.into(),
        }
    }
}

impl From<CorePlanStepStatus> for TurnPlanStepStatus {
    fn from(value: CorePlanStepStatus) -> Self {
        match value {
            CorePlanStepStatus::Pending => Self::Pending,
            CorePlanStepStatus::InProgress => Self::InProgress,
            CorePlanStepStatus::Completed => Self::Completed,
        }
    }
}
```

### 服务端注册

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中：

```rust
server_notification_definitions! {
    TurnPlanUpdated => "turn/plan/updated" (v2::TurnPlanUpdatedNotification),
    // ...
}
```

### 相关 ThreadItem

```rust
#[serde(rename_all = "camelCase")]
#[ts(rename_all = "camelCase")]
/// EXPERIMENTAL - proposed plan item content. The completed plan item is
/// authoritative and may not match the concatenation of `PlanDelta` text.
Plan { id: String, text: String },
```

## 关键代码路径与文件引用

### 核心定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/json/v2/TurnPlanUpdatedNotification.json` | JSON Schema 定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（行 4722-4766） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 服务器通知注册（行 890） |

### 服务端发送代码

位于 `codex-rs/app-server/src/bespoke_event_handling.rs`：
- 监听来自核心 Codex 引擎的计划更新事件
- 转换为 v2 协议格式
- 发送 `TurnPlanUpdatedNotification`

### 测试文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/tests/suite/v2/plan_item.rs` | Plan 项目测试 |

## 依赖与外部交互

### 上游依赖

1. **codex_protocol::plan_tool::PlanItemArg**: 核心计划项目参数
2. **codex_protocol::plan_tool::StepStatus**: 核心步骤状态

### 下游消费者

1. **UI 组件**：显示计划步骤和进度
2. **进度追踪器**：跟踪计划执行进度
3. **计划编辑器**：支持用户修改计划（未来功能）

### 相关通知类型

| 通知类型 | 说明 |
|---------|------|
| `PlanDeltaNotification` | 计划内容的增量更新（实验性） |
| `ItemStartedNotification` | 项目开始通知 |
| `ItemCompletedNotification` | 项目完成通知 |

## 风险、边界与改进建议

### 潜在风险

1. **计划变更频繁**：复杂任务可能导致大量计划更新通知
2. **状态同步延迟**：通知顺序可能与实际执行顺序不一致
3. **计划不准确**：AI 生成的计划可能与实际执行有偏差

### 边界情况

1. **空计划**：`plan` 数组为空表示没有具体步骤
2. **所有步骤完成**：所有步骤状态为 `completed` 表示计划执行完毕
3. **计划变更**：执行过程中计划可能动态调整
4. **explanation 为 null**：某些情况下可能没有解释说明

### 改进建议

1. **计划版本**：添加计划版本号以追踪变更
2. **预计时间**：添加每个步骤的预计执行时间
3. **依赖关系**：支持步骤之间的依赖关系
4. **用户确认**：支持需要用户确认的步骤
5. **计划回滚**：支持回滚到之前的计划状态

### 客户端处理示例

```typescript
// 示例：客户端处理 TurnPlanUpdatedNotification
function handleTurnPlanUpdated(notification: TurnPlanUpdatedNotification) {
    const { threadId, turnId, explanation, plan } = notification;
    
    // 显示解释说明
    if (explanation) {
        showExplanation(explanation);
    }
    
    // 更新计划步骤显示
    updatePlanView({
        threadId,
        turnId,
        steps: plan.map((step, index) => ({
            index: index + 1,
            description: step.step,
            status: step.status,
            isActive: step.status === 'inProgress',
            isCompleted: step.status === 'completed'
        }))
    });
    
    // 计算进度
    const completedSteps = plan.filter(s => s.status === 'completed').length;
    const progress = plan.length > 0 ? (completedSteps / plan.length) * 100 : 0;
    updateProgressBar(progress);
}

// 渲染计划步骤
function renderPlanSteps(steps: PlanStep[]) {
    return steps.map((step, index) => (
        <div key={index} className={`plan-step ${step.status}`}>
            <span className="step-number">{index + 1}</span>
            <span className="step-description">{step.description}</span>
            <span className="step-status">{getStatusIcon(step.status)}</span>
        </div>
    ));
}
```

### 版本兼容性

- 当前为 v2 API，遵循 camelCase 命名规范
- Plan ThreadItem 标记为 `EXPERIMENTAL`
- 与 v1 API 不兼容
- 注意 `PlanDeltaNotification` 是实验性功能，用于流式计划内容
