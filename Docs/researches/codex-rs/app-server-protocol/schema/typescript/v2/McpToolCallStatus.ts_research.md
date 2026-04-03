# McpToolCallStatus.ts 研究文档

## 场景与职责

`McpToolCallStatus.ts` 定义了 MCP (Model Context Protocol) 工具调用的状态类型。该类型表示工具调用的当前执行状态，用于客户端了解工具调用的进展。

此文件是 TypeScript 类型定义文件，由 Rust 的 `ts-rs` 工具从 Rust 源代码自动生成，用于在客户端与 app-server 之间进行类型安全的通信。

## 功能点目的

1. **状态跟踪**: 跟踪工具调用的执行状态
2. **UI 反馈**: 为用户提供工具调用的状态反馈
3. **流程控制**: 支持基于状态的处理逻辑
4. **类型安全**: 确保状态值的类型一致性

## 具体技术实现

### 数据结构

```typescript
export type McpToolCallStatus = "inProgress" | "completed" | "failed";
```

### 状态说明

| 状态值 | 说明 | 使用场景 |
|--------|------|----------|
| `"inProgress"` | 进行中 | 工具正在执行 |
| `"completed"` | 已完成 | 工具执行成功 |
| `"failed"` | 失败 | 工具执行出错 |

### 状态流转

```
[inProgress] --> [completed]
           \
            --> [failed]
```

### 生成来源

该文件由 Rust 枚举通过 `ts-rs` 自动生成：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum McpToolCallStatus {
    InProgress,
    Completed,
    Failed,
}
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源文件）

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 定义 Rust 枚举 |
| `codex-rs/core/src/mcp_tool_call.rs` | 管理工具调用状态 |

### 下游使用（TypeScript 消费者）

- VS Code 扩展的状态指示器
- TUI 的工具状态显示
- 状态管理逻辑

### 相关类型

| 类型 | 说明 |
|------|------|
| `McpToolCallResult.ts` | 工具调用结果 |
| `McpToolCallError.ts` | 工具调用错误 |
| `McpToolCallProgressNotification.ts` | 进度通知 |

## 依赖与外部交互

### 状态使用场景

| 状态 | UI 表现 | 可交互性 |
|------|---------|----------|
| `inProgress` | 加载动画/进度条 | 可能支持取消 |
| `completed` | 成功图标 | 可查看结果 |
| `failed` | 错误图标/消息 | 可重试/查看错误 |

## 风险、边界与改进建议

### 当前限制

1. **状态粒度粗**: 只有三种基本状态
2. **无取消状态**: 缺少明确的取消状态
3. **无排队状态**: 缺少等待执行的状态

### 改进建议

1. **添加更多状态**:
   ```typescript
   export type McpToolCallStatus = 
     | "pending"        // 等待执行
     | "inProgress"     // 执行中
     | "cancelling"     // 正在取消
     | "cancelled"      // 已取消
     | "completed"      // 成功完成
     | "failed";        // 执行失败
   ```

2. **添加状态详情**:
   ```typescript
   {
     status: McpToolCallStatus;
     statusDetail?: string;  // 状态详情描述
   }
   ```

3. **添加时间信息**:
   ```typescript
   {
     status: McpToolCallStatus;
     startedAt?: number;     // 开始时间戳
     completedAt?: number;   // 完成时间戳
   }
   ```
