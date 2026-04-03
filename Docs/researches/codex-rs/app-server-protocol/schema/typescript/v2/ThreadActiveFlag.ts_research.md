# ThreadActiveFlag.ts 研究文档

## 场景与职责

`ThreadActiveFlag` 是 Codex App-Server Protocol v2 API 中的线程活动标志枚举，用于标识线程处于活跃状态时的具体子状态。它是 `ThreadStatus` 类型的组成部分，当线程状态为 `"active"` 时，通过 `activeFlags` 数组指示当前正在进行的活动类型。

## 功能点目的

### 核心功能

| 枚举值 | 说明 |
|--------|------|
| `"waitingOnApproval"` | 线程正在等待用户批准某个操作 |
| `"waitingOnUserInput"` | 线程正在等待用户输入 |

### 设计特点

1. **多标志支持**：使用数组形式支持同时存在多个活动标志
2. **精确状态描述**：比简单的 "active" 状态更精确地描述线程正在做什么
3. **UI 驱动**：主要用于驱动客户端 UI 显示相应的等待界面

## 具体技术实现

### TypeScript 类型定义

```typescript
export type ThreadActiveFlag = "waitingOnApproval" | "waitingOnUserInput";
```

### Rust 源码对应

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 3037-3043) 中定义：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum ThreadActiveFlag {
    WaitingOnApproval,
    WaitingOnUserInput,
}
```

### 在 ThreadStatus 中的使用

```typescript
// ThreadStatus.ts
export type ThreadStatus = 
  | { "type": "notLoaded" } 
  | { "type": "idle" } 
  | { "type": "systemError" } 
  | { "type": "active", activeFlags: Array<ThreadActiveFlag> };
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源码）
- `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 3037-3043): Rust 类型定义

### 下游使用方
- `ThreadStatus.ts`: 作为 `activeFlags` 数组的元素类型

### 相关类型
- `ThreadStatus.ts`: 线程状态类型，包含 `ThreadActiveFlag`

## 依赖与外部交互

### 使用示例

```typescript
import type { ThreadStatus, ThreadActiveFlag } from "./v2";

// 活跃状态 - 等待批准
const waitingStatus: ThreadStatus = {
  type: "active",
  activeFlags: ["waitingOnApproval"]
};

// 活跃状态 - 同时等待多个操作
const multiWaitingStatus: ThreadStatus = {
  type: "active",
  activeFlags: ["waitingOnApproval", "waitingOnUserInput"]
};

// UI 渲染逻辑
function renderThreadStatus(status: ThreadStatus): string {
  if (status.type === "active") {
    if (status.activeFlags.includes("waitingOnApproval")) {
      return "Waiting for your approval...";
    }
    if (status.activeFlags.includes("waitingOnUserInput")) {
      return "Waiting for your input...";
    }
  }
  return status.type;
}
```

## 风险、边界与改进建议

### 边界情况

1. **空数组**：当 `type: "active"` 但 `activeFlags` 为空数组时，语义不明确
2. **重复标志**：数组中可能出现重复标志，需要去重处理

### 改进建议

1. **增加标志**：考虑添加更多细粒度的标志，如：
   - `"executingCommand"`: 正在执行命令
   - `"generatingResponse"`: 正在生成 AI 响应
   - `"waitingOnNetwork"`: 等待网络请求
2. **Set 语义**：考虑使用 Set 而非 Array 表示，避免重复
3. **优先级**：定义标志优先级，当多个标志存在时确定显示优先级

### 注意事项

- 该文件为**自动生成**
- 添加新标志需要同步更新 Rust 源码和客户端处理逻辑
