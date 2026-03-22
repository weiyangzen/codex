# RequestId.ts Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`RequestId` 是 JSON-RPC 请求的唯一标识符，用于关联请求和响应，支持字符串或整数两种格式。

**使用场景：**
- MCP（Model Context Protocol）请求/响应关联
- 执行审批流程中的请求标识
- 任何需要请求-响应关联的异步通信

**职责：**
- 提供灵活的请求标识（字符串或整数）
- 支持 JSON-RPC 2.0 规范
- 确保请求和响应的正确关联

## 2. 功能点目的 (Purpose of This Type)

该类型的主要目的是：

1. **请求追踪**：唯一标识每个请求，便于追踪和调试
2. **响应匹配**：将响应与对应的请求关联
3. **协议兼容**：符合 JSON-RPC 2.0 规范的请求 ID 格式

**ID 格式：**
- 字符串：如 `"req-123"`, `"550e8400-e29b-41d4-a716-446655440000"`
- 整数：如 `1`, `42`, `12345`

## 3. 具体技术实现 (Technical Implementation Details)

**Rust 定义**（位于 `codex-rs/protocol/src/mcp.rs` 第 11-27 行）：

```rust
/// ID of a request, which can be either a string or an integer.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, JsonSchema, TS)]
#[serde(untagged)]
pub enum RequestId {
    String(String),
    #[ts(type = "number")]
    Integer(i64),
}

impl std::fmt::Display for RequestId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            RequestId::String(s) => f.write_str(s),
            RequestId::Integer(i) => i.fmt(f),
        }
    }
}
```

**TypeScript 生成定义：**

```typescript
export type RequestId = string | number;
```

**关键实现细节：**
- 使用 `#[serde(untagged)]` 实现无标签联合序列化
- 实现了 `Display` trait，便于日志记录
- 实现了 `Hash`，可用于哈希表键
- 整数类型使用 `i64`，TypeScript 中映射为 `number`

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

**Rust 源文件：**
- `/home/sansha/Github/codex/codex-rs/protocol/src/mcp.rs`（第 11-27 行）：主要定义

**TypeScript 生成文件：**
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/RequestId.ts`

**使用位置：**
- `ClientRequest` 和 `ServerRequest`（common.rs）
- `ElicitationRequestEvent`（approvals.rs 第 284-294 行）
- `ResolveElicitation` 操作（protocol.rs 第 374-388 行）
- 测试代码（common.rs 第 973-992 行）

**相关类型：**
- `ClientRequest`：客户端请求枚举
- `ServerRequest`：服务器请求枚举
- `JSONRPCRequest` / `JSONRPCNotification`：JSON-RPC 消息类型

## 5. 依赖与外部交互 (Dependencies and External Interactions)

**依赖 crate：**
- `serde`：序列化/反序列化
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成

**序列化格式：**
- 使用无标签联合格式：
  ```json
  "req-123"  // 字符串 ID
  ```
  或
  ```json
  42  // 整数 ID
  ```

**与 JSON-RPC 2.0 的交互：**
- 符合 JSON-RPC 2.0 规范的请求 ID 格式
- 支持通知（无 ID）和请求（有 ID）

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

**潜在风险：**
1. **ID 冲突**：如果 ID 生成不唯一，可能导致响应匹配错误
2. **类型混淆**：字符串和整数的自动转换可能导致意外行为
3. **大整数**：JavaScript 的 number 类型可能无法精确表示大整数

**边界情况：**
1. 空字符串：应该避免使用空字符串作为 ID
2. 负数：整数 ID 可以是负数
3. 零：整数 ID 可以为 0

**改进建议：**
1. **ID 生成器**：提供标准的 ID 生成器，确保唯一性
2. **UUID 支持**：推荐使用 UUID 格式的字符串 ID
3. **类型安全**：考虑添加验证确保 ID 不为空
4. **大整数处理**：在 TypeScript 端注意大整数的精度问题
5. **ID 池**：考虑实现 ID 池管理，避免 ID 冲突
6. **审计日志**：记录所有请求 ID 用于追踪和调试
