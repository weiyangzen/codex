# McpServerElicitationRequestResponse.ts Research Document

## 场景与职责

`McpServerElicitationRequestResponse` 是 MCP (Model Context Protocol) 服务器交互式请求响应类型，用于处理来自 MCP 服务器的用户交互式请求（Elicitation）。当 MCP 服务器需要向用户请求额外信息或确认时，通过此类型封装用户的响应。

该类型在以下场景中使用：
- MCP 服务器需要用户确认某个操作
- MCP 服务器需要用户填写表单或提供额外参数
- 用户需要接受、拒绝或取消某个交互式请求

## 功能点目的

1. **用户决策封装**: 封装用户对 MCP 服务器交互式请求的最终决策（接受、拒绝、取消）
2. **结构化内容传递**: 支持传递结构化的用户输入内容，用于表单填写等场景
3. **元数据支持**: 提供可选的客户端元数据，用于表单模式的动作处理
4. **RMCP 协议兼容**: 与 `rmcp::model::CreateElicitationResult` 兼容，实现协议层互操作

## 具体技术实现

### 数据结构定义

```typescript
import type { JsonValue } from "../serde_json/JsonValue";
import type { McpServerElicitationAction } from "./McpServerElicitationAction";

export type McpServerElicitationRequestResponse = { 
  action: McpServerElicitationAction, 
  /**
   * Structured user input for accepted elicitations, mirroring RMCP `CreateElicitationResult`.
   *
   * This is nullable because decline/cancel responses have no content.
   */
  content: JsonValue | null, 
  /**
   * Optional client metadata for form-mode action handling.
   */
  _meta: JsonValue | null, 
};
```

### 关键字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action` | `McpServerElicitationAction` | 是 | 用户对请求的操作决策，可选值为 `"accept"`、 `"decline"`、 `"cancel"` |
| `content` | `JsonValue \| null` | 是 | 结构化的用户输入内容。当用户接受请求且需要提供数据时填充；拒绝或取消时为 `null` |
| `_meta` | `JsonValue \| null` | 是 | 可选的客户端元数据，用于表单模式的动作处理。可用于传递额外的上下文信息 |

#### McpServerElicitationAction 枚举

```typescript
export type McpServerElicitationAction = "accept" | "decline" | "cancel";
```

- `accept`: 用户接受请求，可能伴随 `content` 数据
- `decline`: 用户拒绝请求，通常 `content` 为 `null`
- `cancel`: 用户取消请求，通常 `content` 为 `null`

## 关键代码路径与文件引用

- **TypeScript 源文件**: `codex-rs/app-server-protocol/schema/typescript/v2/McpServerElicitationRequestResponse.ts`
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (第 5562-5572 行)
- **相关类型**:
  - `McpServerElicitationAction.ts` - 操作类型枚举
  - `serde_json/JsonValue.ts` - JSON 值类型

### Rust 实现详情

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpServerElicitationRequestResponse {
    pub action: McpServerElicitationAction,
    /// Structured user input for accepted elicitations, mirroring RMCP `CreateElicitationResult`.
    pub content: Option<JsonValue>,
    /// Optional client metadata for form-mode action handling.
    #[serde(rename = "_meta")]
    #[ts(rename = "_meta")]
    pub meta: Option<JsonValue>,
}
```

Rust 实现提供了与 `rmcp::model::CreateElicitationResult` 的双向转换：
- `From<McpServerElicitationRequestResponse> for rmcp::model::CreateElicitationResult`
- `From<rmcp::model::CreateElicitationResult> for McpServerElicitationRequestResponse`

## 依赖与外部交互

### 依赖类型

1. **JsonValue**: 来自 `serde_json`，表示任意有效的 JSON 值
   - 支持 number、string、boolean、array、object、null
   
2. **McpServerElicitationAction**: 枚举类型，定义可能的用户操作

### 使用场景

- 在 `thread/respond` API 中作为请求体的一部分
- 与 `ElicitationRequest` 类型配对使用，形成请求-响应循环
- 在客户端 UI 中用于渲染交互式提示并收集用户输入

## 风险、边界与改进建议

### 潜在风险

1. **空内容验证**: 当 `action` 为 `"accept"` 时，`content` 应该包含有效数据，但类型系统无法强制保证这一点。需要在应用层进行验证。

2. **元数据滥用**: `_meta` 字段虽然灵活，但过度使用可能导致调试困难。建议定义明确的元数据结构。

3. **JSON 值类型安全**: `JsonValue` 类型过于宽泛，无法在编译时保证内容的正确性。

### 边界情况

1. **拒绝/取消时的内容**: 当 `action` 为 `"decline"` 或 `"cancel"` 时，`content` 必须为 `null`，但协议本身不强制这一约束。

2. **大内容处理**: `content` 可能包含大量数据，需要考虑序列化/反序列化性能。

3. **向后兼容性**: 如果未来需要添加新的 action 类型，需要确保旧客户端能正确处理未知 action。

### 改进建议

1. **类型安全增强**: 考虑使用 discriminated union 来区分不同 action 对应的内容类型：
   ```typescript
   type AcceptResponse = { action: "accept"; content: JsonValue; _meta: JsonValue | null; }
   type DeclineResponse = { action: "decline"; content: null; _meta: null; }
   type CancelResponse = { action: "cancel"; content: null; _meta: null; }
   export type McpServerElicitationRequestResponse = AcceptResponse | DeclineResponse | CancelResponse;
   ```

2. **元数据标准化**: 为 `_meta` 定义具体的结构，而不是任意的 `JsonValue`。

3. **内容大小限制**: 考虑在协议层添加内容大小限制，防止超大 payload 导致性能问题。

4. **文档完善**: 为不同的 elicitation 场景提供更详细的内容格式说明。
