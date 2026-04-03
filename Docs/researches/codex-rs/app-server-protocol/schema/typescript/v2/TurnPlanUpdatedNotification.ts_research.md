# TurnPlanUpdatedNotification.ts Research

## 场景与职责

`TurnPlanUpdatedNotification` 是 App-Server Protocol v2 中用于实时同步 AI 执行计划更新状态的通知类型。当 AI 助手制定或更新其执行计划时，服务器通过此通知向客户端推送计划的最新状态，包括计划说明、步骤列表及各步骤的执行状态。

主要使用场景包括：
- **计划展示**：向用户展示 AI 的执行意图和步骤规划
- **实时进度**：在 AI 执行过程中实时更新计划进度
- **透明度提升**：让用户了解 AI 正在做什么以及接下来要做什么
- **用户确认**：在需要用户确认的场景下展示完整计划
- **调试分析**：帮助开发者理解 AI 的决策和执行流程

## 功能点目的

该通知的核心目的是：

1. **计划同步**：将 AI 的执行计划从服务器同步到客户端
2. **进度可视化**：通过步骤状态驱动进度条、状态图标等 UI 元素
3. **意图沟通**：通过 `explanation` 字段向用户解释 AI 的执行意图
4. **动态更新**：支持计划的动态更新（如 AI 根据执行反馈调整计划）

与其他通知的关系：
- 与 `TurnStartedNotification` 配合，在回合开始时发送初始计划
- 与 `ItemStartedNotification`、`ItemCompletedNotification` 配合，形成完整的执行事件流
- 与 `TurnCompletedNotification` 配合，标记计划执行的完成

## 具体技术实现

### TypeScript 类型定义

```typescript
export type TurnPlanUpdatedNotification = { 
  threadId: string, 
  turnId: string, 
  explanation: string | null, 
  plan: Array<TurnPlanStep>, 
};
```

### Rust 源码定义

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
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | string | 所属线程的唯一标识符 |
| `turnId` | string | 当前回合的唯一标识符 |
| `explanation` | string \| null | AI 对执行计划的说明/解释，可为 null |
| `plan` | TurnPlanStep[] | 执行计划步骤数组，每个步骤包含描述和状态 |

### TurnPlanStep 结构

```typescript
export type TurnPlanStep = { 
  step: string,      // 步骤描述
  status: TurnPlanStepStatus,  // 步骤状态
};

export type TurnPlanStepStatus = "pending" | "inProgress" | "completed";
```

### 典型数据结构示例

```json
{
  "threadId": "thread-abc123",
  "turnId": "turn-def456",
  "explanation": "我将帮您重构这段代码以提高性能",
  "plan": [
    { "step": "分析当前代码性能瓶颈", "status": "completed" },
    { "step": "设计优化方案", "status": "completed" },
    { "step": "实现代码重构", "status": "inProgress" },
    { "step": "验证优化效果", "status": "pending" }
  ]
}
```

## 关键代码路径与文件引用

### 协议定义

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:4722-4730` | Rust 结构体定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/TurnPlanUpdatedNotification.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/json/v2/TurnPlanUpdatedNotification.json` | JSON Schema 定义 |

### 服务器端处理

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 计划更新事件处理，发送通知 |
| `codex-rs/app-server-protocol/src/protocol/common.rs:890` | ServerNotification 枚举定义（`turn/plan/updated`） |

### 客户端消费

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs` | TUI 计划展示和更新处理 |
| `codex-rs/tui/src/chatwidget.rs` | TUI 计划渲染 |
| `codex-rs/app-server-protocol/schema/typescript/ServerNotification.ts:49` | TypeScript 联合类型包含此通知 |

### 测试覆盖

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/tests/suite/v2/plan_item.rs` | 计划项相关测试 |

## 依赖与外部交互

### 内部依赖

```
TurnPlanUpdatedNotification
├── thread_id: String
├── turn_id: String
├── explanation: Option<String>
├── plan: Vec<TurnPlanStep>
│   ├── step: String
│   └── status: TurnPlanStepStatus
│       ├── Pending
│       ├── InProgress
│       └── Completed
├── serde (Serialize, Deserialize)
├── schemars (JsonSchema)
└── ts_rs (TS)
```

### 协议集成

- **通知类型**：`turn/plan/updated`（定义于 `common.rs:890`）
- **传输方式**：JSON-RPC 通知，通过 WebSocket 或 stdio 传输
- **发送时机**：
  - 回合开始时发送初始计划
  - 计划步骤状态变更时发送更新
  - AI 调整计划时发送新计划

### 事件流示例

```
turn/started
  ↓
turn/plan/updated (初始计划)
  ↓
item/started (第一个步骤)
  ↓
turn/plan/updated (步骤状态更新)
  ↓
item/completed
  ↓
turn/plan/updated (步骤完成)
  ↓
...
  ↓
turn/completed
```

## 风险、边界与改进建议

### 潜在风险

1. **频繁更新**：计划步骤状态频繁变更可能导致通知风暴
2. **大计划负载**：复杂任务可能产生大量步骤，单次通知数据量大
3. **explanation 质量**：AI 生成的说明质量不稳定，可能不够清晰
4. **状态同步延迟**：通知到达顺序可能与实际执行顺序不一致

### 边界情况

| 场景 | 行为 |
|------|------|
| 无计划 | plan 数组为空，explanation 可能为 null |
| explanation 为 null | 客户端应优雅处理，不显示说明或显示默认文本 |
| 单步骤计划 | plan 数组只有一个元素 |
| 计划动态变更 | AI 可能在执行中调整计划，发送新的 plan 数组 |
| 所有步骤完成 | 所有 status 为 completed，通常在 turn/completed 前发送 |

### 改进建议

1. **增量更新**：考虑支持增量更新，只发送变更的步骤而非完整计划
2. **更新频率限制**：添加节流机制，避免过于频繁的通知
3. **计划版本**：添加版本号或时间戳，便于客户端处理乱序到达的通知
4. **步骤 ID**：为每个步骤添加唯一 ID，支持更精确的更新定位
5. **预估时间**：添加整体计划预估完成时间
6. **优先级标记**：标记关键步骤，便于 UI 突出显示
7. **可折叠步骤**：支持步骤分组，复杂计划可分层展示

### UI 设计建议

1. **进度概览**：顶部显示整体进度百分比
2. **步骤列表**：垂直列表展示各步骤，带状态图标
3. **当前步骤高亮**：inProgress 步骤使用动画或高亮效果
4. **说明展示**：explanation 可作为标题或提示展示
5. **折叠/展开**：支持折叠已完成步骤，聚焦当前任务
6. **时间估算**：如有时长估算，显示预计剩余时间

### 监控指标建议

- 计划更新通知发送频率
- 平均计划步骤数
- explanation 字段填充率
- 计划完成率
- 计划变更次数（动态调整频率）
