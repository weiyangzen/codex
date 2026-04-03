# ThreadItem.ts 研究文档

## 场景与职责

`ThreadItem` 是 Codex App-Server Protocol v2 API 中最复杂、最核心的类型之一，代表线程中的一个项目/条目。它是一个**标签联合类型（Tagged Union）**，包含多种不同类型的对话元素，构成了完整的对话历史记录。

## 功能点目的

### 支持的 Item 类型

| 类型 | 说明 | 关键字段 |
|------|------|----------|
| `userMessage` | 用户消息 | `content: Array<UserInput>` |
| `agentMessage` | AI 助手消息 | `text`, `phase`, `memoryCitation` |
| `plan` | 计划项 | `text` |
| `reasoning` | 推理过程 | `summary`, `content` |
| `commandExecution` | 命令执行 | `command`, `cwd`, `status`, `exitCode` |
| `fileChange` | 文件变更 | `changes`, `status` |
| `mcpToolCall` | MCP 工具调用 | `server`, `tool`, `arguments`, `result` |
| `dynamicToolCall` | 动态工具调用 | `tool`, `arguments`, `status` |
| `collabAgentToolCall` | 协作代理工具调用 | `tool`, `senderThreadId`, `receiverThreadIds` |
| `webSearch` | 网页搜索 | `query`, `action` |
| `imageView` | 图片查看 | `path` |
| `imageGeneration` | 图片生成 | `status`, `revisedPrompt`, `result` |
| `enteredReviewMode` | 进入审查模式 | `review` |
| `exitedReviewMode` | 退出审查模式 | `review` |
| `contextCompaction` | 上下文压缩 | - |

## 具体技术实现

### TypeScript 类型定义（简化）

```typescript
export type ThreadItem = 
  | { "type": "userMessage", id: string, content: Array<UserInput> }
  | { "type": "agentMessage", id: string, text: string, phase: MessagePhase | null, memoryCitation: MemoryCitation | null }
  | { "type": "plan", id: string, text: string }
  | { "type": "reasoning", id: string, summary: Array<string>, content: Array<string> }
  | { "type": "commandExecution", id: string, command: string, cwd: string, processId: string | null, source: CommandExecutionSource, status: CommandExecutionStatus, commandActions: Array<CommandAction>, aggregatedOutput: string | null, exitCode: number | null, durationMs: number | null }
  | { "type": "fileChange", id: string, changes: Array<FileUpdateChange>, status: PatchApplyStatus }
  // ... 其他变体
  ;
```

### Rust 源码对应

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 4117-4258) 中定义：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "camelCase")]
#[ts(tag = "type")]
#[ts(export_to = "v2/")]
pub enum ThreadItem {
    #[serde(rename_all = "camelCase")]
    #[ts(rename_all = "camelCase")]
    UserMessage { id: String, content: Vec<UserInput> },
    #[serde(rename_all = "camelCase")]
    #[ts(rename_all = "camelCase")]
    AgentMessage { id: String, text: String, phase: Option<MessagePhase>, memory_citation: Option<MemoryCitation> },
    // ... 其他变体
}
```

### ID 访问方法

```rust
impl ThreadItem {
    pub fn id(&self) -> &str {
        match self {
            ThreadItem::UserMessage { id, .. } | ThreadItem::AgentMessage { id, .. } | ... => id,
        }
    }
}
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源码）
- `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 4117-4258): Rust 类型定义

### 下游使用方
- `Turn.ts`: 包含 `items: Array<ThreadItem>`
- `ItemStartedNotification.ts`: 通知中的 item
- `ItemCompletedNotification.ts`: 通知中的 item

### 相关类型
- `UserInput.ts`: 用户输入类型
- `CommandAction.ts`: 命令动作
- `PatchApplyStatus.ts`: 补丁应用状态
- `McpToolCallStatus.ts`: MCP 工具调用状态

## 依赖与外部交互

### 使用示例

```typescript
import type { ThreadItem } from "./v2";

// 类型守卫函数
function isCommandExecution(item: ThreadItem): item is Extract<ThreadItem, { type: "commandExecution" }> {
  return item.type === "commandExecution";
}

// 处理不同类型的 items
function renderItem(item: ThreadItem): string {
  switch (item.type) {
    case "userMessage":
      return item.content.map(c => c.type === "text" ? c.text : "[media]").join("");
    case "agentMessage":
      return item.text;
    case "commandExecution":
      return `$ ${item.command}\n${item.aggregatedOutput || ""}`;
    case "fileChange":
      return `Changed ${item.changes.length} files`;
    default:
      return `[${item.type}]`;
  }
}
```

## 风险、边界与改进建议

### 边界情况

1. **类型穷尽检查**：新增类型时需要更新所有 switch 语句
2. **大数组性能**：长对话的 items 数组可能非常庞大
3. **循环引用**：items 之间理论上不应有循环引用

### 改进建议

1. **类型分组**：将相关类型分组，如 `ToolCallItem = McpToolCall | DynamicToolCall`
2. **通用字段提取**：提取 `id`, `timestamp` 等通用字段到基类型
3. **版本控制**：添加版本字段支持类型演进

### 注意事项

- 该文件为**自动生成**
- 该类型是协议核心，修改需谨慎考虑向后兼容性
- TypeScript 的 discriminated union 需要正确处理所有变体
