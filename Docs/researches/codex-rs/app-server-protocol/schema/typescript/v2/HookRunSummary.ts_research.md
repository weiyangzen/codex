# HookRunSummary.ts Research Document

## 场景与职责

`HookRunSummary` 是 Codex App-Server Protocol v2 中用于完整描述一次 Hook 执行实例的核心数据结构。它聚合了 Hook 执行的所有关键元数据，包括基本信息、执行状态、时间戳和输出内容。

在 Codex 的 Hook 系统中，当特定事件触发时（如会话开始、用户提交提示），系统会创建一个 Hook 运行实例。`HookRunSummary` 就是这个运行实例的完整快照，用于在客户端展示 Hook 执行详情、追踪执行历史以及进行调试分析。

## 功能点目的

该类型的主要目的是：

1. **完整描述 Hook 执行**：聚合单次 Hook 执行的所有关键信息
2. **支持状态追踪**：提供执行状态、时间戳和持续时间等时序信息
3. **输出内容承载**：包含 Hook 执行产生的所有输出条目
4. **排序与展示**：通过 `displayOrder` 支持多个 Hook 的有序展示
5. **调试与审计**：为问题排查和执行审计提供完整数据

## 具体技术实现

### 数据结构定义

```typescript
export type HookRunSummary = { 
  id: string, 
  eventName: HookEventName, 
  handlerType: HookHandlerType, 
  executionMode: HookExecutionMode, 
  scope: HookScope, 
  sourcePath: string, 
  displayOrder: bigint, 
  status: HookRunStatus, 
  statusMessage: string | null, 
  startedAt: bigint, 
  completedAt: bigint | null, 
  durationMs: bigint | null, 
  entries: Array<HookOutputEntry>, 
};
```

### 关键字段说明

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | `string` | Hook 运行实例的唯一标识符 |
| `eventName` | `HookEventName` | 触发此 Hook 的事件名称（如 `"sessionStart"`、`"userPromptSubmit"`、`"stop"`） |
| `handlerType` | `HookHandlerType` | Hook 处理器类型（`"command"`、`"prompt"`、`"agent"`） |
| `executionMode` | `HookExecutionMode` | 执行模式（`"sync"` 同步或 `"async"` 异步） |
| `scope` | `HookScope` | 作用域（`"thread"` 线程级或 `"turn"` 轮次级） |
| `sourcePath` | `string` | Hook 配置源文件的路径 |
| `displayOrder` | `bigint` | 显示顺序，用于多个 Hook 的排序展示 |
| `status` | `HookRunStatus` | 当前执行状态（`"running"`、`"completed"`、`"failed"`、`"blocked"`、`"stopped"`） |
| `statusMessage` | `string \| null` | 状态附加消息，如错误详情或阻断原因 |
| `startedAt` | `bigint` | 开始时间戳（Unix 毫秒） |
| `completedAt` | `bigint \| null` | 完成时间戳（Unix 毫秒），未完成时为 null |
| `durationMs` | `bigint \| null` | 执行持续时间（毫秒），未完成时为 null |
| `entries` | `HookOutputEntry[]` | 输出条目数组，包含 Hook 执行的所有输出 |

## 关键代码路径与文件引用

- **TypeScript 源文件**: `codex-rs/app-server-protocol/schema/typescript/v2/HookRunSummary.ts`
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`

### 依赖导入

```typescript
import type { HookEventName } from "./HookEventName";
import type { HookExecutionMode } from "./HookExecutionMode";
import type { HookHandlerType } from "./HookHandlerType";
import type { HookOutputEntry } from "./HookOutputEntry";
import type { HookRunStatus } from "./HookRunStatus";
import type { HookScope } from "./HookScope";
```

### Rust 对应定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct HookRunSummary {
    pub id: String,
    pub event_name: HookEventName,
    pub handler_type: HookHandlerType,
    pub execution_mode: HookExecutionMode,
    pub scope: HookScope,
    pub source_path: PathBuf,
    pub display_order: i64,
    pub status: HookRunStatus,
    pub status_message: Option<String>,
    pub started_at: i64,
    pub completed_at: Option<i64>,
    pub duration_ms: Option<i64>,
    pub entries: Vec<HookOutputEntry>,
}
```

## 依赖与外部交互

### 相关类型

```
HookRunSummary
├── HookEventName (eventName)
├── HookHandlerType (handlerType)
├── HookExecutionMode (executionMode)
├── HookScope (scope)
├── HookRunStatus (status)
└── HookOutputEntry[] (entries)
    └── HookOutputEntryKind (entry.kind)
```

### 使用场景

1. **HookStartedNotification**: 当 Hook 开始执行时发送，包含初始的 `HookRunSummary`
   ```typescript
   export type HookStartedNotification = { 
     threadId: string, 
     turnId: string | null, 
     run: HookRunSummary, 
   };
   ```

2. **HookCompletedNotification**: 当 Hook 执行完成时发送，包含最终的 `HookRunSummary`
   ```rust
   pub struct HookCompletedNotification {
       pub thread_id: String,
       pub turn_id: Option<String>,
       pub run: HookRunSummary,
   }
   ```

### 核心协议转换

```rust
impl From<CoreHookRunSummary> for HookRunSummary {
    fn from(value: CoreHookRunSummary) -> Self {
        Self {
            id: value.id,
            event_name: value.event_name.into(),
            handler_type: value.handler_type.into(),
            execution_mode: value.execution_mode.into(),
            scope: value.scope.into(),
            source_path: value.source_path,
            display_order: value.display_order,
            status: value.status.into(),
            status_message: value.status_message,
            started_at: value.started_at,
            completed_at: value.completed_at,
            duration_ms: value.duration_ms,
            entries: value.entries.into_iter().map(Into::into).collect(),
        }
    }
}
```

## 风险、边界与改进建议

### 潜在风险

1. **数据量过大**：如果 `entries` 数组包含大量输出，可能导致消息体过大
2. **时间戳精度**：使用 `bigint` 存储毫秒时间戳，在 JavaScript 中处理时需注意精度问题
3. **路径兼容性**：`sourcePath` 是字符串类型，跨平台路径处理需要客户端注意

### 边界情况

1. **空 entries**：Hook 执行成功但没有输出时，`entries` 为空数组
2. **长时间运行**：对于长时间运行的 Hook，`durationMs` 可能很大
3. **异步执行**：异步模式下，`completedAt` 和 `durationMs` 可能在后续通知中才填充

### 改进建议

1. **分页输出**：对于大量输出的 Hook，考虑对 `entries` 进行分页或截断
2. **添加元数据字段**：考虑添加 `metadata` 字段用于存储 Hook 特定的附加信息
3. **执行统计**：添加更多执行统计信息，如 CPU 时间、内存使用等
4. **父/子关系**：支持嵌套 Hook 调用时，添加 `parentId` 字段表示父子关系
5. **重试信息**：对于自动重试的 Hook，添加 `attemptNumber` 和 `maxAttempts` 字段

### 注意事项

- 此文件是自动生成的，**不应手动修改**
- 生成工具：[ts-rs](https://github.com/Aleph-Alpha/ts-rs)
- `bigint` 类型在 JavaScript 中需要特殊处理，确保运行时环境支持
- `sourcePath` 在 Windows 和 Unix 系统上格式可能不同
