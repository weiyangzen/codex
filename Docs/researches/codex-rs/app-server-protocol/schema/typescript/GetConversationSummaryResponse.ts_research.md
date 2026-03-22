# GetConversationSummaryResponse Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`GetConversationSummaryResponse` 是 `GetConversationSummary` 请求的响应类型，用于返回对话的摘要信息。该响应对应于 App-Server Protocol v1 API，已被标记为 DEPRECATED。

主要使用场景：
- 客户端请求历史对话的元数据
- 对话列表展示（显示预览、时间戳、模型信息等）
- 对话恢复前的信息确认

## 2. 功能点目的 (Purpose of This Type)

- **封装响应数据**：将 `ConversationSummary` 包装为统一的响应格式
- **类型安全**：确保响应结构的一致性
- **API 兼容性**：保持 v1 API 的向后兼容性

## 3. 具体技术实现 (Technical Implementation Details)

### 数据结构

```typescript
// TypeScript 定义（由 ts-rs 生成）
import type { ConversationSummary } from "./ConversationSummary";

export type GetConversationSummaryResponse = { summary: ConversationSummary };
```

```rust
// Rust 定义
#[derive(Serialize, Deserialize, Debug, Clone, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
pub struct GetConversationSummaryResponse {
    pub summary: ConversationSummary,
}
```

### 嵌套类型 ConversationSummary

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
pub struct ConversationSummary {
    pub conversation_id: ThreadId,
    pub path: PathBuf,
    pub preview: String,
    pub timestamp: Option<String>,
    pub updated_at: Option<String>,
    pub model_provider: String,
    pub cwd: PathBuf,
    pub cli_version: String,
    pub source: SessionSource,
    pub git_info: Option<ConversationGitInfo>,
}
```

### 关键字段说明

| 字段 | 类型 | 说明 |
|-----|------|------|
| `conversation_id` | `ThreadId` | 对话唯一标识 |
| `path` | `PathBuf` | 对话存储路径 |
| `preview` | `String` | 对话内容预览 |
| `timestamp` | `Option<String>` | 创建时间戳 |
| `updated_at` | `Option<String>` | 最后更新时间 |
| `model_provider` | `String` | 使用的模型提供商 |
| `cwd` | `PathBuf` | 工作目录 |
| `cli_version` | `String` | CLI 版本 |
| `source` | `SessionSource` | 对话来源 |
| `git_info` | `Option<ConversationGitInfo>` | Git 状态信息 |

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

| 文件路径 | 说明 |
|---------|------|
| `/codex-rs/app-server-protocol/src/protocol/v1.rs` (lines 80-99) | Rust 类型定义 |
| `/codex-rs/app-server-protocol/schema/typescript/GetConversationSummaryResponse.ts` | TypeScript 类型定义（生成） |
| `/codex-rs/app-server-protocol/src/protocol/common.rs` | ClientRequest 枚举注册 |

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 依赖项

- `ConversationSummary`：核心摘要数据结构
- `ThreadId`：对话 ID 类型
- `SessionSource`：会话来源枚举
- `ConversationGitInfo`：Git 信息结构

### 相关 API

- `GetConversationSummaryParams`：对应的请求参数
- `thread/read` (v2)：推荐的新 API

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险与边界

1. **已弃用**：该响应类型对应的 API 已被弃用，未来可能移除
2. **时间戳格式**：`timestamp` 和 `updated_at` 使用字符串而非标准时间类型，可能导致解析问题
3. **可选字段**：多个字段为 `Option` 类型，客户端需要处理缺失情况

### 改进建议

1. **迁移到 v2 API**：使用 `ThreadReadResponse` 替代
2. **时间戳标准化**：建议使用 Unix 时间戳或 ISO 8601 格式
3. **添加版本信息**：在响应中包含 API 版本信息便于调试

### 向后兼容性

由于该类型已被弃用，建议：
- 新代码使用 v2 API
- 维护旧代码时添加迁移计划
- 监控该 API 的使用情况，为移除做准备
