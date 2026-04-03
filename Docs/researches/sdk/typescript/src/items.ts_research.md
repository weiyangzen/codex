# items.ts 研究文档

## 场景与职责

`items.ts` 定义 TypeScript SDK 的线程项（ThreadItem）类型系统，描述 Codex Agent 在一次交互轮次（Turn）中产生的各类内容项。核心职责：

1. **内容建模**：完整描述 Agent 可能产生的所有内容类型（消息、命令、文件变更等）
2. **状态追踪**：定义每个内容项的生命周期状态（in_progress → completed/failed）
3. **与 Rust 端同步**：保持与 `codex-rs/exec/src/exec_events.rs` 中 `ThreadItemDetails` 的兼容

该模块是 SDK 数据模型的核心，所有交互结果都通过 `ThreadItem` 联合类型表达。

## 功能点目的

### 1. ThreadItem 联合类型

```typescript
export type ThreadItem =
  | AgentMessageItem      // Agent 文本/JSON 响应
  | ReasoningItem         // 推理过程摘要
  | CommandExecutionItem  // 命令执行
  | FileChangeItem        // 文件变更
  | McpToolCallItem       // MCP 工具调用
  | WebSearchItem         // 网页搜索
  | TodoListItem          // 待办列表
  | ErrorItem;            // 非致命错误
```

**设计原则**：
- **Discriminated Union**：通过 `type` 字段区分项类型
- **统一 ID**：所有项都有 `id` 字段，用于追踪和去重
- **状态外化**：状态变化通过事件（`item.started`/`item.updated`/`item.completed`）表达，而非项内状态机

### 2. 核心项类型详解

#### AgentMessageItem
```typescript
export type AgentMessageItem = {
  id: string;
  type: "agent_message";
  text: string;  // 自然语言或结构化 JSON
};
```
**触发场景**：模型生成文本响应
**特殊行为**：当使用 `outputSchema` 时，`text` 为 JSON 字符串

#### CommandExecutionItem
```typescript
export type CommandExecutionItem = {
  id: string;
  type: "command_execution";
  command: string;           // 执行的命令行
  aggregated_output: string; // stdout + stderr 聚合
  exit_code?: number;        // 退出码（undefined = 运行中）
  status: CommandExecutionStatus;  // "in_progress" | "completed" | "failed"
};
```
**生命周期**：
```
item.started   → status: "in_progress", exit_code: undefined
item.completed → status: "completed"/"failed", exit_code: set
```

#### FileChangeItem
```typescript
export type FileChangeItem = {
  id: string;
  type: "file_change";
  changes: FileUpdateChange[];  // 文件变更列表
  status: PatchApplyStatus;     // "completed" | "failed"
};

export type FileUpdateChange = {
  path: string;
  kind: PatchChangeKind;  // "add" | "delete" | "update"
};
```
**注意**：文件变更项**只有** `item.completed` 事件，无 `item.started`

#### McpToolCallItem
```typescript
export type McpToolCallItem = {
  id: string;
  type: "mcp_tool_call";
  server: string;      // MCP 服务器名称
  tool: string;        // 工具名称
  arguments: unknown;  // 调用参数
  result?: {           // 成功时存在
    content: McpContentBlock[];
    structured_content: unknown;
  };
  error?: { message: string };  // 失败时存在
  status: McpToolCallStatus;
};
```
**依赖**：`@modelcontextprotocol/sdk` 的 `ContentBlock` 类型

### 3. 状态枚举

```typescript
export type CommandExecutionStatus = "in_progress" | "completed" | "failed";
export type PatchApplyStatus = "completed" | "failed";
export type McpToolCallStatus = "in_progress" | "completed" | "failed";
export type PatchChangeKind = "add" | "delete" | "update";
```

**设计一致性**：
- 进行状态：`"in_progress"`
- 终态：`"completed"` / `"failed"`
- 无 `"declined"` 等中间状态（在 SDK 层简化）

## 具体技术实现

### 与 Rust 端的类型映射

| TypeScript (items.ts) | Rust (exec_events.rs) | 差异说明 |
|-----------------------|----------------------|----------|
| `ThreadItem` | `ThreadItem` | 结构一致 |
| `AgentMessageItem` | `AgentMessageItem` | 一致 |
| `CommandExecutionItem` | `CommandExecutionItem` | Rust 多 `"declined"` 状态 |
| `FileChangeItem` | `FileChangeItem` | 一致 |
| `McpToolCallItem` | `McpToolCallItem` | Rust 使用 `JsonValue`，TS 用 `unknown` |
| `TodoListItem` | `TodoListItem` | 一致 |
| `WebSearchItem` | `WebSearchItem` | TS 缺少 `action` 字段 |

**已知差异**：
1. `WebSearchItem` 在 TS 中缺少 `action` 字段（Rust 端有 `WebSearchAction`）
2. `CommandExecutionStatus` 在 TS 中缺少 `"declined"` 变体

### 事件聚合中的项处理

```typescript
// thread.ts 中的项收集
async run(input: Input): Promise<Turn> {
  const items: ThreadItem[] = [];
  
  for await (const event of generator) {
    if (event.type === "item.completed") {
      if (event.item.type === "agent_message") {
        finalResponse = event.item.text;  // 提取最终响应
      }
      items.push(event.item);  // 收集所有完成的项
    }
  }
  
  return { items, finalResponse, usage };
}
```

### 示例用法

```typescript
import { Codex, ThreadItem } from "@openai/codex-sdk";

function handleItem(item: ThreadItem) {
  switch (item.type) {
    case "agent_message":
      console.log(`Assistant: ${item.text}`);
      break;
      
    case "command_execution":
      const status = item.status;
      const exitInfo = item.exit_code !== undefined 
        ? `exit ${item.exit_code}` 
        : "running";
      console.log(`Command: ${item.command} [${status}, ${exitInfo}]`);
      console.log(`Output: ${item.aggregated_output}`);
      break;
      
    case "file_change":
      for (const change of item.changes) {
        console.log(`File ${change.kind}: ${change.path}`);
      }
      break;
      
    case "mcp_tool_call":
      if (item.status === "completed") {
        console.log(`Tool ${item.tool} succeeded:`, item.result);
      } else {
        console.error(`Tool ${item.tool} failed:`, item.error);
      }
      break;
      
    case "todo_list":
      for (const todo of item.items) {
        const mark = todo.completed ? "[x]" : "[ ]";
        console.log(`${mark} ${todo.text}`);
      }
      break;
  }
}
```

## 关键代码路径与文件引用

### 类型依赖图

```
items.ts
├── 导入
│   └── @modelcontextprotocol/sdk/types.js  # McpContentBlock
│
├── 导出类型
│   ├── ThreadItem (联合类型)
│   ├── AgentMessageItem
│   ├── ReasoningItem
│   ├── CommandExecutionItem + CommandExecutionStatus
│   ├── FileChangeItem + FileUpdateChange + PatchApplyStatus + PatchChangeKind
│   ├── McpToolCallItem + McpToolCallStatus
│   ├── WebSearchItem
│   ├── TodoListItem + TodoItem
│   └── ErrorItem
│
├── 被导入
│   ├── events.ts            # ItemStartedEvent, ItemUpdatedEvent, ItemCompletedEvent
│   ├── thread.ts            # 项聚合逻辑
│   ├── index.ts             # 重新导出
│   └── samples/basic_streaming.ts  # 示例处理
│
└── 与 Rust 对应
    └── codex-rs/exec/src/exec_events.rs  # ThreadItemDetails
```

### 数据流向

```
┌─────────────────────────────────────────┐
│  Codex CLI (Rust)                       │
│  - EventProcessorWithJsonOutput         │
│  - 构建 ThreadItem 结构                  │
└─────────────────┬───────────────────────┘
                  │ JSON 序列化
┌─────────────────▼───────────────────────┐
│  JSONL 流                               │
│  {"type":"item.completed","item":{...}} │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│  thread.ts                              │
│  - JSON.parse()                         │
│  - 类型断言 as ThreadEvent              │
│  - 提取 event.item (ThreadItem)         │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│  User Application                       │
│  - switch (item.type) 处理              │
│  - 类型收窄访问特定字段                  │
└─────────────────────────────────────────┘
```

## 依赖与外部交互

### 外部依赖

| 包 | 模块 | 用途 |
|----|------|------|
| `@modelcontextprotocol/sdk` | `types.js` | `McpContentBlock` 类型 |

### 内部依赖

无其他内部模块依赖（纯类型定义）。

### 外部契约

| 消费者 | 消费内容 | 用途 |
|--------|----------|------|
| `events.ts` | `ThreadItem` | 事件载荷类型 |
| `thread.ts` | 所有项类型 | 聚合和返回结果 |
| `index.ts` | 所有项类型 | 重新导出供外部使用 |
| `samples/basic_streaming.ts` | `ThreadItem` | 示例事件处理 |

## 风险、边界与改进建议

### 类型一致性风险

1. **与 Rust 端不同步**
   - 已知差异：`WebSearchItem.action` 字段缺失
   - 影响：用户无法获知搜索动作类型（`cached`/`live`）
   - 建议：同步 Rust 端的 `action` 字段

2. **MCP 类型耦合**
   - 当前：依赖 `@modelcontextprotocol/sdk` 的 `ContentBlock`
   - 风险：MCP SDK 版本升级可能破坏类型兼容
   - 缓解：`package.json` 中锁定版本范围

### 边界条件

| 场景 | 行为 |
|------|------|
| 未知项类型 | TypeScript 编译错误（Discriminated Union 保护） |
| 空 `changes` 数组 | 有效状态，表示无文件变更 |
| `exit_code` 为负数 | 有效（Unix 信号导致的退出码） |
| `aggregated_output` 很大 | 内存占用，无流式分块 |

### 改进建议

1. **补齐缺失字段**
   ```typescript
   export type WebSearchItem = {
     id: string;
     type: "web_search";
     query: string;
     action: "cached" | "live";  // 补充此字段
   };
   ```

2. **命令输出分块**
   - 当前：`aggregated_output` 为完整字符串
   - 建议：增加输出增量事件，支持大输出流式显示

3. **文件变更详情**
   - 当前：仅包含变更类型和路径
   - 建议：可选地包含 diff 内容（需 CLI 支持）

4. **工具调用参数类型安全**
   - 当前：`arguments: unknown`
   - 建议：提供泛型版本 `McpToolCallItem<T>`
   ```typescript
   export type McpToolCallItem<T = unknown> = {
     // ...
     arguments: T;
   };
   ```

5. **项优先级/排序**
   - 当前：依赖 CLI 输出顺序
   - 建议：增加 `timestamp` 或 `sequence` 字段

### 测试覆盖

`items.ts` 本身无直接测试，通过以下方式验证：

1. **类型检查**：`tsc --noEmit` 验证类型定义
2. **集成测试**：`tests/run.test.ts` 验证项内容
3. **示例验证**：`samples/basic_streaming.ts` 展示处理方式

### 与事件类型的关系

```
events.ts                    items.ts
──────────                   ────────
ItemStartedEvent ───────┐
ItemUpdatedEvent ───────┼──► 包含 ThreadItem 作为 payload
ItemCompletedEvent ─────┘

ThreadEvent (union) ───────► 其中 3 个变体使用 ThreadItem
```

**设计一致性**：事件类型与项类型分离，允许：
- 事件元数据扩展（如添加 `timestamp`）而不影响项定义
- 同一项在多个事件中引用（如 `item.updated` 多次后 `item.completed`）
