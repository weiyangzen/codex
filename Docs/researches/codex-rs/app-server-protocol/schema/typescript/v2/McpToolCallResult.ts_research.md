# McpToolCallResult.ts 研究文档

## 场景与职责

`McpToolCallResult.ts` 定义了 MCP (Model Context Protocol) 工具调用结果的类型。该类型包含工具调用的输出内容，支持标准文本内容和结构化内容两种形式。

此文件是 TypeScript 类型定义文件，由 Rust 的 `ts-rs` 工具从 Rust 源代码自动生成，用于在客户端与 app-server 之间进行类型安全的通信。

## 功能点目的

1. **结果传递**: 传递工具调用的输出结果
2. **双格式支持**: 支持标准内容数组和结构化内容
3. **灵活性**: 适应不同工具的输出格式需求
4. **模型消费**: 结果可直接用于模型上下文

## 具体技术实现

### 数据结构

```typescript
export type McpToolCallResult = { 
  content: Array<JsonValue>,              // 标准内容项数组
  structuredContent: JsonValue | null,    // 结构化内容（可选）
};
```

### 关键字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `content` | `JsonValue[]` | 是 | 工具调用的标准输出内容，通常是文本或图像项的数组 |
| `structuredContent` | `JsonValue \| null` | 是 | 结构化数据输出，可用于程序化处理，null 表示无结构化输出 |

### 内容项格式

典型的 `content` 数组项可能包含：
```typescript
// 文本内容
{ type: "text", text: "操作成功完成" }

// 图像内容
{ type: "image", data: "base64encoded...", mimeType: "image/png" }

// 资源引用
{ type: "resource", resource: { uri: "...", mimeType: "..." } }
```

### 生成来源

该文件由 Rust 结构体通过 `ts-rs` 自动生成：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpToolCallResult {
    pub content: Vec<JsonValue>,
    pub structured_content: Option<JsonValue>,
}
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源文件）

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 定义 Rust 类型 |
| `codex-rs/core/src/mcp_tool_call.rs` | 生成工具调用结果 |
| `codex-rs/protocol/src/mcp.rs` | MCP 协议定义 |

### 下游使用（TypeScript 消费者）

- VS Code 扩展的工具输出显示
- TUI 的工具结果渲染
- 模型上下文构建

### 相关类型

| 类型 | 说明 |
|------|------|
| `JsonValue.ts` | 通用 JSON 值类型 |
| `McpToolCallError.ts` | 工具调用错误 |
| `McpToolCallStatus.ts` | 工具调用状态 |

## 依赖与外部交互

### 结果处理流程

```
MCP Server -> App Server: 工具执行结果
App Server -> Client: McpToolCallResult
Client: 渲染 content 数组
Client: 如有需要，处理 structuredContent
```

### 使用场景

1. **命令执行**: 返回命令输出和退出码
2. **文件操作**: 返回文件内容或操作确认
3. **API 调用**: 返回 API 响应数据
4. **搜索查询**: 返回搜索结果列表

## 风险、边界与改进建议

### 当前限制

1. **内容类型不明确**: `content` 数组项的具体结构未在类型中明确
2. **大小限制**: 大内容可能影响传输性能
3. **二进制数据处理**: Base64 编码增加数据大小

### 改进建议

1. **明确内容类型**:
   ```typescript
   type ContentItem = 
     | { type: "text"; text: string }
     | { type: "image"; data: string; mimeType: string }
     | { type: "resource"; uri: string; mimeType?: string };
   
   {
     content: ContentItem[];
     structuredContent: JsonValue | null;
   }
   ```

2. **添加元数据**:
   ```typescript
   {
     content: JsonValue[];
     structuredContent: JsonValue | null;
     metadata?: {
       durationMs?: number;      // 执行耗时
       size?: number;            // 内容大小
       truncated?: boolean;      // 是否被截断
     };
   }
   ```

3. **支持流式结果**:
   ```typescript
   {
     content: JsonValue[];
     structuredContent: JsonValue | null;
     isComplete: boolean;        // 是否完整结果
     chunkIndex?: number;        // 分块索引
   }
   ```

### 示例使用场景

```typescript
// 命令执行结果
const commandResult: McpToolCallResult = {
  content: [
    { type: "text", text: "total 128\ndrwxr-xr-x  5 user group  160 Jan 15 10:30 ." }
  ],
  structuredContent: {
    exitCode: 0,
    command: "ls -la",
    workingDir: "/home/user/project"
  }
};

// API 调用结果
const apiResult: McpToolCallResult = {
  content: [
    { type: "text", text: "用户创建成功" }
  ],
  structuredContent: {
    id: "user-123",
    name: "John Doe",
    createdAt: "2024-01-15T10:30:00Z"
  }
};
```
