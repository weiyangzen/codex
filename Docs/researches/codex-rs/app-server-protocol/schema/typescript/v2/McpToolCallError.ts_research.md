# McpToolCallError.ts 研究文档

## 场景与职责

`McpToolCallError.ts` 定义了 MCP (Model Context Protocol) 工具调用错误的类型。该类型用于在工具调用失败时向客户端传递错误信息。

此文件是 TypeScript 类型定义文件，由 Rust 的 `ts-rs` 工具从 Rust 源代码自动生成，用于在客户端与 app-server 之间进行类型安全的通信。

## 功能点目的

1. **错误信息传递**: 向客户端传递工具调用失败的错误消息
2. **故障诊断**: 帮助用户和开发者理解工具调用失败的原因
3. **类型安全**: 确保错误结构的类型一致性

## 具体技术实现

### 数据结构

```typescript
export type McpToolCallError = { 
  message: string,  // 错误消息
};
```

### 关键字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `message` | `string` | 是 | 描述错误的人类可读消息 |

### 生成来源

该文件由 Rust 结构体通过 `ts-rs` 自动生成：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpToolCallError {
    pub message: String,
}
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源文件）

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 定义 Rust 类型 |
| `codex-rs/core/src/mcp_tool_call.rs` | 处理工具调用错误 |

### 下游使用（TypeScript 消费者）

- 错误提示显示
- 日志记录
- 错误处理逻辑

### 相关类型

| 类型 | 说明 |
|------|------|
| `McpToolCallResult.ts` | 工具调用结果（包含错误） |
| `McpToolCallStatus.ts` | 工具调用状态 |

## 依赖与外部交互

### 错误场景

1. **参数验证失败**: 工具参数不符合预期
2. **执行错误**: 工具执行过程中发生错误
3. **网络错误**: 与外部服务通信失败
4. **权限错误**: 没有足够的权限执行操作
5. **超时**: 工具执行超时

## 风险、边界与改进建议

### 当前限制

1. **仅文本消息**: 只有 `message` 字段，缺乏结构化错误信息
2. **无错误代码**: 无法程序化地识别错误类型
3. **无堆栈跟踪**: 缺乏调试信息

### 改进建议

1. **添加错误代码**:
   ```typescript
   {
     message: string;
     code: "INVALID_PARAMS" | "EXECUTION_ERROR" | "TIMEOUT" | "PERMISSION_DENIED" | "NETWORK_ERROR";
   }
   ```

2. **添加详细信息**:
   ```typescript
   {
     message: string;
     details?: {
       field?: string;        // 出错的字段
       expected?: string;     // 预期值
       actual?: string;       // 实际值
     };
   }
   ```

3. **添加重试信息**:
   ```typescript
   {
     message: string;
     retryable: boolean;      // 是否可以重试
     retryAfter?: number;     // 建议重试等待时间（秒）
   }
   ```

4. **添加错误链**:
   ```typescript
   {
     message: string;
     cause?: McpToolCallError;  // 原始错误
   }
   ```
