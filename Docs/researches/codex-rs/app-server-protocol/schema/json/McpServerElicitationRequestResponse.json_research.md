# McpServerElicitationRequestResponse.json 研究文档

## 场景与职责

`McpServerElicitationRequestResponse` 是 Codex App-Server 协议中用于**响应 MCP 服务器引导请求**的结构。当客户端处理完 MCP 服务器的引导请求后，通过此结构返回用户响应。

该类型属于 **Client → Server** 的响应流，是 `McpServerElicitationRequest` 请求的预期响应类型。

### 使用场景

1. **表单提交**：用户填写表单后的提交响应
2. **URL 模式完成**：用户完成 OAuth 等外部流程后的响应
3. **拒绝/取消**：用户拒绝或取消引导请求

---

## 功能点目的

### 核心字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action` | McpServerElicitationAction | ✅ | 用户操作 |
| `content` | any | ❌ | 表单提交的内容（accept 时） |
| `_meta` | any | ❌ | 客户端元数据 |

### 操作类型（McpServerElicitationAction）

| 值 | 描述 |
|------|------|
| `"accept"` | 用户接受并提交 |
| `"decline"` | 用户拒绝 |
| `"cancel"` | 用户取消 |

---

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum McpServerElicitationAction {
    Accept,
    Decline,
    Cancel,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpServerElicitationRequestResponse {
    #[serde(rename = "_meta")]
    #[ts(rename = "_meta")]
    pub meta: Option<JsonValue>,
    pub action: McpServerElicitationAction,
    /// Structured user input for accepted elicitations, mirroring RMCP `CreateElicitationResult`.
    /// This is nullable because decline/cancel responses have no content.
    pub content: Option<JsonValue>,
}
```

### 与 RMCP 的转换

```rust
impl From<McpServerElicitationRequestResponse> for rmcp::model::CreateElicitationResult {
    fn from(value: McpServerElicitationRequestResponse) -> Self {
        Self {
            action: value.action.into(),
            content: value.content,
        }
    }
}

impl From<rmcp::model::CreateElicitationResult> for McpServerElicitationRequestResponse {
    fn from(value: rmcp::model::CreateElicitationResult) -> Self {
        Self {
            action: value.action.into(),
            content: value.content,
            meta: None,
        }
    }
}
```

---

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 主类型定义（行 5562-5572） |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | McpServerElicitationAction 枚举（行 5127-5153） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ServerRequest 注册（行 755-758） |

### 使用方

| 文件 | 说明 |
|------|------|
| `codex-rs/tui_app_server/src/bottom_pane/mcp_server_elicitation.rs` | TUI 引导响应处理 |
| `codex-rs/tui_app_server/src/app/app_server_requests.rs` | 应用服务器请求处理 |
| `codex-rs/core/src/mcp_tool_call.rs` | MCP 工具调用处理 |

---

## 依赖与外部交互

### 依赖类型

```rust
use serde_json::Value as JsonValue;
use rmcp::model::CreateElicitationResult;
```

### 序列化特性

- `action` 使用 camelCase 序列化
- `content` 为 `Option<JsonValue>`，decline/cancel 时为 null
- `_meta` 字段用于客户端传递额外上下文

---

## 风险、边界与改进建议

### 已知风险

1. **内容验证**：`content` 是任意 JSON，服务器需要验证其符合请求的 schema

2. **action 与 content 一致性**：`action` 为 decline/cancel 时，`content` 应为 null，但协议不强制

### 边界情况

1. **空 content**：accept 时 `content` 为空对象 `{}`
2. **无效 action**：未知的 action 值

### 改进建议

1. **内容验证**：在响应类型中添加 schema 验证：
   ```rust
   pub struct McpServerElicitationRequestResponse {
       pub action: McpServerElicitationAction,
       pub content: Option<JsonValue>,
       #[serde(skip)]
       pub schema: Option<JsonSchema>,  // 用于验证
   }
   ```

2. **强类型内容**：对于常见表单类型，提供强类型的 content 结构

3. **错误详情**：decline/cancel 时支持提供原因：
   ```rust
   pub struct McpServerElicitationRequestResponse {
       pub action: McpServerElicitationAction,
       pub content: Option<JsonValue>,
       pub reason: Option<String>,  // decline/cancel 原因
   }
   ```
