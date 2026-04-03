# TurnPlanStepStatus.ts Research

## 场景与职责

`TurnPlanStepStatus` 是 App-Server Protocol v2 中用于表示 AI 执行计划步骤状态的枚举类型。它定义了计划步骤可能处于的三种状态：等待执行、正在执行和已完成，为客户端提供了清晰的状态追踪机制。

主要使用场景包括：
- **状态追踪**：追踪 AI 执行计划中每个步骤的实时状态
- **UI 渲染**：驱动进度条、状态图标等 UI 元素的展示
- **流程控制**：根据步骤状态决定用户交互逻辑（如是否允许跳过）
- **进度计算**：计算整体计划完成百分比
- **调试分析**：分析 AI 执行效率和步骤耗时

## 功能点目的

该枚举的核心目的是：

1. **标准化状态定义**：提供统一的步骤状态分类，确保客户端和服务器理解一致
2. **简化状态机**：使用简单的三态模型（pending/inProgress/completed）覆盖主要场景
3. **支持进度追踪**：通过状态流转实现执行进度的可视化
4. **驱动 UI 更新**：为客户端提供明确的信号来更新界面

状态流转模型：
```
┌─────────┐     ┌─────────────┐     ┌───────────┐
│ pending │ --> │ inProgress  │ --> │ completed │
└─────────┘     └─────────────┘     └───────────┘
    ^
    │
    └── 初始状态
```

与其他类型的关系：
- 作为 `TurnPlanStep.status` 字段的类型
- 与 `TurnPlanUpdatedNotification` 配合使用，传递计划状态更新
- 从核心层的 `CorePlanStepStatus` 转换而来

## 具体技术实现

### TypeScript 类型定义

```typescript
export type TurnPlanStepStatus = "pending" | "inProgress" | "completed";
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum TurnPlanStepStatus {
    Pending,
    InProgress,
    Completed,
}
```

### 状态值说明

| 状态值 | TypeScript 字符串 | Rust 变体 | 说明 |
|--------|------------------|-----------|------|
| 等待中 | `"pending"` | `Pending` | 步骤尚未开始执行 |
| 进行中 | `"inProgress"` | `InProgress` | 步骤正在执行中 |
| 已完成 | `"completed"` | `Completed` | 步骤执行完成 |

### 从核心类型转换

```rust
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

`CorePlanStepStatus` 来自 `codex_protocol::plan_tool` 模块，定义为：
```rust
pub enum StepStatus {
    Pending,
    InProgress,
    Completed,
}
```

### 派生特性

- `Copy`: 允许值复制而非移动，提高性能
- `Eq`: 支持相等性比较
- `PartialEq`: 支持部分相等性比较
- `Clone`: 支持显式克隆

## 关键代码路径与文件引用

### 协议定义

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:4740-4747` | Rust 枚举定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs:4758-4766` | From 转换实现 |
| `codex-rs/app-server-protocol/schema/typescript/v2/TurnPlanStepStatus.ts` | TypeScript 类型定义 |

### 核心层关联

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:50` | `CorePlanStepStatus` 导入（别名为 `StepStatus`） |

### 客户端使用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs` | 导入并使用 `TurnPlanStepStatus` |
| `codex-rs/tui/src/chatwidget.rs` | TUI 状态处理 |

### 协议集成

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/typescript/v2/TurnPlanStep.ts` | 使用 TurnPlanStepStatus |
| `codex-rs/app-server-protocol/schema/typescript/v2/TurnPlanUpdatedNotification.ts` | 包含使用此类型的 plan 字段 |

## 依赖与外部交互

### 内部依赖

```
TurnPlanStepStatus
├── Pending
├── InProgress
├── Completed
├── CorePlanStepStatus (From 转换)
├── serde (Serialize, Deserialize)
├── schemars (JsonSchema)
└── ts_rs (TS)
```

### 序列化行为

- **Rust -> JSON**: `Pending` -> `"pending"`, `InProgress` -> `"inProgress"`, `Completed` -> `"completed"`
- **JSON -> Rust**: 反向转换，使用 camelCase 命名规范

### 使用场景

```typescript
// 计算完成进度
const completedCount = plan.filter(p => p.status === "completed").length;
const progress = completedCount / plan.length * 100;

// 判断是否全部完成
const allCompleted = plan.every(p => p.status === "completed");

// 获取当前执行的步骤
const currentStep = plan.find(p => p.status === "inProgress");
```

## 风险、边界与改进建议

### 潜在风险

1. **状态缺失**：当前三态模型无法表示失败、跳过、取消等状态
2. **状态回退**：不支持从 completed 回退到 pending（重试场景）
3. **并发状态**：不支持多个步骤同时 inProgress 的场景（依赖并行执行能力）

### 边界情况

| 场景 | 当前行为 | 建议 |
|------|---------|------|
| 步骤执行失败 | 可能保持 inProgress 或标记为 completed | 需要 failed 状态 |
| 步骤被跳过 | 可能直接标记为 completed | 需要 skipped 状态 |
| 步骤被取消 | 可能保持当前状态 | 需要 cancelled 状态 |
| 步骤重试 | 不支持状态回退 | 需要 retry 机制或状态重置 |

### 改进建议

1. **扩展状态枚举**：
   ```typescript
   export type TurnPlanStepStatus = 
     | "pending" 
     | "inProgress" 
     | "completed" 
     | "failed"      // 执行失败
     | "skipped"     // 被跳过
     | "cancelled";  // 被取消
   ```

2. **添加状态元数据**：
   ```typescript
   export type TurnPlanStepStatus = 
     | { type: "pending" }
     | { type: "inProgress"; startedAt: number }
     | { type: "completed"; completedAt: number }
     | { type: "failed"; error: string };
   ```

3. **状态流转验证**：添加状态机验证，防止非法状态转换

4. **状态历史记录**：记录状态变更历史，便于调试和分析

### UI 设计建议

| 状态 | 建议图标 | 建议颜色 |
|------|---------|---------|
| pending | ⏳ 或 ○ | 灰色 |
| inProgress | ⏳ 或 ⟳（动画） | 蓝色 |
| completed | ✓ 或 ● | 绿色 |
| failed（建议添加） | ✗ | 红色 |
| skipped（建议添加） | → 或 ⊘ | 橙色 |

### 兼容性考虑

- 添加新状态时保持向后兼容
- 旧客户端遇到未知状态时可降级处理（如显示为 pending）
- 在协议文档中明确说明状态扩展策略
