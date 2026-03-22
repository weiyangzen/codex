# GetConversationSummaryParams Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`GetConversationSummaryParams` 是 App-Server Protocol v1 API 中用于获取对话摘要的请求参数类型。它支持两种查询方式：

1. **通过 rollout 路径查询**：用于根据文件系统路径查找对应的对话摘要
2. **通过对话 ID 查询**：用于根据 `ThreadId` 直接获取特定对话的摘要

该类型主要用于客户端需要恢复或查看历史对话状态时，向服务器请求特定对话的元数据信息。

## 2. 功能点目的 (Purpose of This Type)

- **多模式查询**：提供灵活的查询方式，支持按路径或按 ID 查询
- **对话恢复**：支持客户端在重新连接后恢复之前的对话状态
- **摘要获取**：获取对话的基本信息（预览、时间戳、模型、Git 状态等）

## 3. 具体技术实现 (Technical Implementation Details)

### 数据结构

```typescript
// TypeScript 定义（由 ts-rs 生成）
export type GetConversationSummaryParams = 
  | { rolloutPath: string } 
  | { conversationId: ThreadId };
```

```rust
// Rust 定义
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(untagged)]
pub enum GetConversationSummaryParams {
    RolloutPath {
        #[serde(rename = "rolloutPath")]
        rollout_path: PathBuf,
    },
    ThreadId {
        #[serde(rename = "conversationId")]
        conversation_id: ThreadId,
    },
}
```

### 关键特性

- **Untagged Union**：使用 `#[serde(untagged)]` 实现无标签联合类型，序列化时不包含变体标签
- **字段重命名**：使用 camelCase 进行 JSON 序列化（`rolloutPath`, `conversationId`）
- **类型安全**：`ThreadId` 是强类型包装器，确保 ID 格式正确

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

| 文件路径 | 说明 |
|---------|------|
| `/codex-rs/app-server-protocol/src/protocol/v1.rs` (lines 67-78) | Rust 类型定义 |
| `/codex-rs/app-server-protocol/schema/typescript/GetConversationSummaryParams.ts` | TypeScript 类型定义（生成） |
| `/codex-rs/app-server-protocol/src/protocol/common.rs` (lines 509-512) | ClientRequest 枚举中注册为 deprecated API |

### 相关类型

- `GetConversationSummaryResponse`：对应的响应类型，包含 `ConversationSummary`
- `ConversationSummary`：实际的摘要数据结构

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 依赖项

- `std::path::PathBuf`：用于文件路径处理
- `codex_protocol::ThreadId`：对话 ID 类型
- `serde`：序列化/反序列化
- `ts_rs::TS`：TypeScript 类型生成
- `schemars::JsonSchema`：JSON Schema 生成

### 使用场景

```rust
// 示例：构造请求
let request = ClientRequest::GetConversationSummary {
    request_id: RequestId::Integer(42),
    params: GetConversationSummaryParams::ThreadId {
        conversation_id: ThreadId::from_string("67e55044-...")?,
    },
};
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险与边界

1. **已弃用状态**：该 API 已被标记为 DEPRECATED，建议使用新的 `thread/read` API 替代
2. **互斥变体**：由于是 untagged union，如果同时提供两个字段，serde 会按定义顺序匹配第一个
3. **路径验证**：`rolloutPath` 需要服务器端验证路径有效性和权限

### 改进建议

1. **迁移到新 API**：新项目应使用 v2 的 `ThreadRead` 替代
2. **添加验证**：在反序列化时添加路径存在性检查
3. **明确错误信息**：当两种查询参数都缺失时，提供更清晰的错误提示

### 测试覆盖

```rust
// 现有测试位于 common.rs
#[test]
fn serialize_get_conversation_summary() -> Result<()> {
    let request = ClientRequest::GetConversationSummary {
        request_id: RequestId::Integer(42),
        params: v1::GetConversationSummaryParams::ThreadId {
            conversation_id: ThreadId::from_string("67e55044-10b1-426f-9247-bb680e5fe0c8")?,
        },
    };
    // ...
}
```
