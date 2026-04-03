# TurnStatus.ts Research Document

## 场景与职责

`TurnStatus` 是 App-Server Protocol v2 中定义回合（Turn）生命周期的核心枚举类型。它在以下场景中发挥关键作用：

1. **回合状态追踪**: 表示对话回合从创建到结束的完整生命周期状态
2. **UI 状态渲染**: 驱动客户端 UI 显示不同的视觉状态（加载中、完成、中断、失败）
3. **流程控制**: 用于判断是否可以开始新回合、是否需要恢复当前回合等逻辑决策
4. **错误处理**: 区分正常完成、用户中断和系统失败等不同终止情况
5. **历史记录展示**: 在对话历史中为每个回合显示其最终状态

## 功能点目的

该枚举类型的核心目的是：

- **生命周期建模**: 明确定义回合可能处于的四种离散状态
- **状态机基础**: 作为实现回合状态机的基础类型
- **跨层通信**: 在核心逻辑、应用服务器和客户端之间传递一致的回合状态
- **用户体验优化**: 支持基于状态的 UI 反馈（如加载动画、错误提示、重试按钮等）

### 状态定义

| 状态值 | 含义 | 典型场景 |
|-------|------|---------|
| `completed` | 回合正常完成 | AI 成功生成回复，所有工具调用完成 |
| `interrupted` | 回合被中断 | 用户主动取消、超时、或安全策略拦截 |
| `failed` | 回合执行失败 | 系统错误、API 异常、资源不足等 |
| `inProgress` | 回合进行中 | 正在等待 AI 响应或执行工具调用 |

## 具体技术实现

### TypeScript 类型定义

```typescript
export type TurnStatus = "completed" | "interrupted" | "failed" | "inProgress";
```

### Rust 源类型定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum TurnStatus {
    Completed,
    Interrupted,
    Failed,
    InProgress,
}
```

### 序列化特性

- **命名规范**: 使用 `camelCase` 进行序列化（`Completed` → `"completed"`）
- **字符串枚举**: TypeScript 端表示为字符串字面量联合类型
- **派生特性**: 实现了 `Serialize`, `Deserialize`, `Debug`, `Clone`, `PartialEq`, `JsonSchema`, `TS`

### 状态转换规则

```
                    ┌─────────────────┐
                    │   inProgress    │
                    │    (初始状态)    │
                    └────────┬────────┘
                             │
            ┌────────────────┼────────────────┐
            │                │                │
            ▼                ▼                ▼
    ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
    │  completed   │ │ interrupted  │ │    failed    │
    │   (终态)      │ │   (终态)      │ │   (终态)      │
    └──────────────┘ └──────────────┘ └──────────────┘
```

- **初始状态**: 回合创建时为 `inProgress`
- **终态**: `completed`, `interrupted`, `failed` 均为终态，不可再转换
- **转换方向**: 只能从 `inProgress` 转向三种终态之一

## 关键代码路径与文件引用

### 定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 3812-3820) | Rust 枚举定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/TurnStatus.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/json/v2/TurnStatus.json` | JSON Schema 定义 |

### 使用位置

| 文件路径 | 用途 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 作为 `Turn` 结构的 `status` 字段类型 |
| `codex-rs/app-server-protocol/schema/typescript/v2/Turn.ts` | Turn 类型引用 |
| `codex-rs/core/src/state/turn.rs` | 核心层回合状态管理 |
| `codex-rs/tui/src/history_cell.rs` | TUI 历史记录单元格状态显示 |
| `codex-rs/tui_app_server/src/history_cell.rs` | TUI 应用服务器历史记录渲染 |

### 状态判断逻辑

```rust
// 示例：检查回合是否已完成
impl TurnStatus {
    pub fn is_terminal(&self) -> bool {
        matches!(self, TurnStatus::Completed | TurnStatus::Interrupted | TurnStatus::Failed)
    }
    
    pub fn is_successful(&self) -> bool {
        matches!(self, TurnStatus::Completed)
    }
}
```

## 依赖与外部交互

### 内部依赖

- **`Turn`**: 作为 Turn 结构的核心字段
- **`TurnError`**: 当状态为 `failed` 时，关联的错误详情
- **`ThreadItem`**: 回合中包含的项目，其状态影响 TurnStatus

### 协议依赖

- 被包含在多个请求/响应类型中：
  - `TurnStartResponse`
  - `TurnSteerResponse`
  - `ThreadResumeResponse`
  - `TurnStartedNotification`
  - `TurnCompletedNotification`

### 客户端交互

- **TUI 客户端**: 根据状态显示不同的样式和图标
  - `inProgress`: 显示加载动画
  - `completed`: 显示正常文本
  - `interrupted`: 显示中断图标/样式
  - `failed`: 显示错误样式和重试按钮

## 风险、边界与改进建议

### 潜在风险

1. **状态不一致**: 如果客户端和服务器之间的状态同步出现延迟或丢包，可能导致显示的状态与实际状态不符
2. **竞态条件**: 快速连续的状态更新可能导致客户端显示过时的状态
3. **状态扩展困难**: 当前为简单枚举，添加新状态可能需要协调多处代码更新

### 边界情况

1. **瞬时状态**: `inProgress` 状态可能非常短暂（对于简单查询），客户端可能来不及渲染
2. **失败恢复**: `failed` 状态后，系统是否允许重试或恢复需要明确的业务逻辑
3. **中断时机**: 在回合的不同阶段（思考中、工具调用中、输出生成中）中断，处理方式可能不同

### 改进建议

1. **添加时间戳**: 考虑在 Turn 结构中添加状态变更时间戳，便于调试和性能分析

2. **子状态细化**: 对于 `inProgress` 状态，考虑添加子状态：
   ```rust
   pub enum TurnStatus {
       InProgress(InProgressSubState), // Planning, Executing, Generating
       Completed,
       Interrupted(InterruptReason),
       Failed(TurnError),
   }
   ```

3. **状态历史**: 对于调试和审计，考虑保留状态变更历史

4. **进度指示**: 对于长时间运行的回合，考虑添加进度百分比或阶段信息

5. **取消原因细化**: `interrupted` 状态可以细分为：
   - 用户主动取消
   - 超时取消
   - 安全策略拦截
   - 资源限制触发

### 测试覆盖

- 状态转换测试：验证正确的状态流转
- UI 渲染测试：确保各状态正确显示
- 并发测试：验证高并发场景下的状态一致性
- 建议添加：状态历史记录测试、长时间运行回合的状态稳定性测试
