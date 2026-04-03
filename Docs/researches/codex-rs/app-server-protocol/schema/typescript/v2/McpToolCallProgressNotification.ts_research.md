# McpToolCallProgressNotification.ts 研究文档

## 场景与职责

`McpToolCallProgressNotification.ts` 定义了 MCP (Model Context Protocol) 工具调用进度通知的类型。该类型用于在长时间运行的工具调用过程中向客户端发送进度更新。

此文件是 TypeScript 类型定义文件，由 Rust 的 `ts-rs` 工具从 Rust 源代码自动生成，用于在客户端与 app-server 之间进行类型安全的通信。

## 功能点目的

1. **进度反馈**: 向用户展示长时间运行工具的执行进度
2. **状态更新**: 通知客户端工具调用的当前状态
3. **用户体验**: 防止用户认为应用卡住或无响应
4. **上下文关联**: 关联到特定的线程、回合和项目

## 具体技术实现

### 数据结构

```typescript
export type McpToolCallProgressNotification = { 
  threadId: string,   // 线程 ID
  turnId: string,     // 回合 ID
  itemId: string,     // 项目 ID
  message: string,    // 进度消息
};
```

### 关键字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `threadId` | `string` | 是 | 关联的线程 ID |
| `turnId` | `string` | 是 | 关联的回合 ID |
| `itemId` | `string` | 是 | 关联的项目 ID（工具调用项） |
| `message` | `string` | 是 | 描述当前进度的消息 |

### 生成来源

该文件由 Rust 结构体通过 `ts-rs` 自动生成：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpToolCallProgressNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub item_id: String,
    pub message: String,
}
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源文件）

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 定义 Rust 类型 |
| `codex-rs/core/src/mcp_tool_call.rs` | 发送进度通知 |

### 下游使用（TypeScript 消费者）

- VS Code 扩展的进度条显示
- TUI 的状态更新
- 日志记录

### 相关类型

| 类型 | 说明 |
|------|------|
| `McpToolCallStatus.ts` | 工具调用状态 |
| `McpToolCallResult.ts` | 工具调用结果 |

## 依赖与外部交互

### 进度通知流程

```
MCP Server -> App Server: 进度更新
App Server -> Client: McpToolCallProgressNotification
Client: 更新 UI 显示进度消息
```

### 使用场景

1. **长时间计算**: "正在处理数据... (50%)"
2. **批量操作**: "已处理 10/100 项"
3. **网络请求**: "正在下载文件..."
4. **编译构建**: "正在编译模块 X..."

## 风险、边界与改进建议

### 当前限制

1. **无百分比**: 缺乏量化的进度百分比
2. **无预估时间**: 没有剩余时间估计
3. **消息格式**: 仅文本消息，缺乏结构化数据

### 改进建议

1. **添加进度百分比**:
   ```typescript
   {
     threadId: string;
     turnId: string;
     itemId: string;
     message: string;
     progress?: number;        // 0-100 的百分比
   }
   ```

2. **添加阶段信息**:
   ```typescript
   {
     // ...
     stage?: string;           // 当前阶段标识
     stageMessage?: string;    // 阶段描述
     totalStages?: number;     // 总阶段数
     currentStage?: number;    // 当前阶段索引
   }
   ```

3. **添加时间信息**:
   ```typescript
   {
     // ...
     elapsedMs?: number;       // 已用时间
     estimatedRemainingMs?: number;  // 预估剩余时间
   }
   ```

4. **支持取消**:
   ```typescript
   {
     // ...
     cancellable: boolean;     // 是否可以取消
   }
   ```

### 示例使用场景

```typescript
// 进度通知示例
const progressNotification: McpToolCallProgressNotification = {
  threadId: "thread-123",
  turnId: "turn-456",
  itemId: "item-789",
  message: "正在分析代码结构..."
};

// 带百分比的增强版本（建议）
const enhancedProgress = {
  threadId: "thread-123",
  turnId: "turn-456",
  itemId: "item-789",
  message: "正在分析代码结构",
  progress: 45,
  stage: "analysis",
  elapsedMs: 5000,
  estimatedRemainingMs: 6000
};
```
