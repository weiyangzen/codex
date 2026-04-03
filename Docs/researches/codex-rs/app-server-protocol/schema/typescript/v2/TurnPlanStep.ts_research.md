# TurnPlanStep.ts Research

## 场景与职责

`TurnPlanStep` 是 App-Server Protocol v2 中用于表示 AI 执行计划（Plan）中单个步骤的数据类型。它是 `TurnPlanUpdatedNotification` 的核心组成部分，描述了 AI 为完成用户请求而制定的执行计划中的具体步骤及其当前状态。

主要使用场景包括：
- **计划展示**：向用户展示 AI 的执行计划，增强透明度和可控性
- **进度追踪**：实时显示每个计划步骤的执行状态
- **用户确认**：在需要用户确认的场景下展示计划详情
- **调试分析**：开发者和运维人员通过计划步骤了解 AI 决策过程
- **历史记录**：保存执行计划用于后续分析和审计

## 功能点目的

该类型的核心目的是：

1. **步骤描述**：用人类可读的文本描述计划中的具体步骤
2. **状态追踪**：追踪每个步骤的执行状态（pending、inProgress、completed）
3. **计划可视化**：支持客户端渲染计划进度界面
4. **透明度提升**：让用户了解 AI 的执行意图和当前进展

与其他类型的关系：
- 作为 `TurnPlanUpdatedNotification.plan` 数组的元素类型
- 与 `TurnPlanStepStatus` 枚举配合使用，表示步骤状态
- 从核心层的 `CorePlanItemArg` 转换而来

## 具体技术实现

### TypeScript 类型定义

```typescript
export type TurnPlanStep = { 
  step: string, 
  status: TurnPlanStepStatus, 
};
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TurnPlanStep {
    pub step: String,
    pub status: TurnPlanStepStatus,
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `step` | string | 步骤的描述文本，人类可读的执行计划说明 |
| `status` | TurnPlanStepStatus | 步骤的当前执行状态 |

### TurnPlanStepStatus 枚举

```typescript
export type TurnPlanStepStatus = "pending" | "inProgress" | "completed";
```

| 状态值 | 说明 |
|--------|------|
| `pending` | 步骤等待执行 |
| `inProgress` | 步骤正在执行中 |
| `completed` | 步骤已完成 |

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
```

`CorePlanItemArg` 来自 `codex_protocol::plan_tool` 模块，是核心层的计划项类型。

## 关键代码路径与文件引用

### 协议定义

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:4732-4738` | Rust 结构体定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs:4749-4756` | From 转换实现 |
| `codex-rs/app-server-protocol/schema/typescript/v2/TurnPlanStep.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/json/v2/TurnPlanUpdatedNotification.json` | 包含 TurnPlanStep 的 JSON Schema |

### 核心层关联

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:49` | `CorePlanItemArg` 导入 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs:50` | `CorePlanStepStatus` 导入 |

### 服务器端处理

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 计划更新事件处理 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 计划消息处理 |

### 客户端消费

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs` | TUI 计划展示 |
| `codex-rs/tui/src/chatwidget.rs` | TUI 计划渲染 |

### 测试覆盖

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/tests/suite/v2/plan_item.rs` | 计划项相关测试 |

## 依赖与外部交互

### 内部依赖

```
TurnPlanStep
├── step: String
├── status: TurnPlanStepStatus
│   ├── Pending
│   ├── InProgress
│   └── Completed
├── CorePlanItemArg (From 转换)
├── serde (Serialize, Deserialize)
├── schemars (JsonSchema)
└── ts_rs (TS)
```

### 协议集成

- **使用位置**：`TurnPlanUpdatedNotification.plan: Vec<TurnPlanStep>`
- **通知类型**：`turn/plan/updated`
- **状态流转**：
  ```
  pending -> inProgress -> completed
  ```

### 典型数据结构示例

```json
{
  "threadId": "thread-123",
  "turnId": "turn-456",
  "explanation": "我将帮您分析代码并修复 bug",
  "plan": [
    { "step": "阅读相关源代码文件", "status": "completed" },
    { "step": "分析错误原因", "status": "inProgress" },
    { "step": "编写修复代码", "status": "pending" },
    { "step": "验证修复结果", "status": "pending" }
  ]
}
```

## 风险、边界与改进建议

### 潜在风险

1. **步骤描述质量**：`step` 字段的内容质量取决于 AI 生成能力，可能不够清晰或准确
2. **状态同步延迟**：状态更新可能存在延迟，客户端看到的不是实时状态
3. **步骤数量膨胀**：复杂任务可能产生大量步骤，影响 UI 渲染性能
4. **状态不一致**：网络问题可能导致客户端与服务器状态不一致

### 边界情况

| 场景 | 行为 |
|------|------|
| 空计划 | plan 数组为空 |
| 单步骤计划 | plan 数组只有一个元素 |
| 所有步骤完成 | 所有 status 为 completed |
| 步骤回退 | 理论上不支持，但可能因错误重置状态 |

### 改进建议

1. **步骤分类**：添加 `category` 字段区分不同类型的步骤（分析、修改、验证等）
2. **预估时间**：添加 `estimatedDuration` 字段，提供步骤预估执行时间
3. **步骤依赖**：添加 `dependsOn` 字段表示步骤间的依赖关系
4. **可跳过标记**：添加 `skippable` 字段标识可跳过的可选步骤
5. **错误状态**：扩展 `TurnPlanStepStatus` 添加 `failed` 状态
6. **进度百分比**：添加 `progress` 字段表示步骤内部进度（0-100）
7. **子步骤支持**：支持嵌套的子步骤结构，处理复杂任务

### UI 展示建议

1. **进度条**：根据 completed / total 计算整体进度
2. **状态图标**：为不同状态使用不同的视觉图标
3. **动画效果**：inProgress 状态使用动画表示正在进行
4. **折叠展开**：大量步骤时支持折叠已完成步骤
5. **时间戳**：显示每个步骤的开始和完成时间

### 监控指标建议

- 平均计划步骤数
- 各状态步骤的分布
- 步骤执行时长分布
- 计划完成率
