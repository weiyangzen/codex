# McpServerElicitationRequestParams 研究文档

## 场景与职责

`McpServerElicitationRequestParams` 是 app-server v2 API 中 ServerRequest 的 `mcpServer/elicitation/request` 方法的参数类型。它封装了 MCP (Model Context Protocol) 服务器向客户端发起引导请求所需的全部上下文信息。

该类型是 MCP 协议与 Codex 应用服务器之间的桥梁，负责：
1. 传递 MCP 服务器的引导请求内容
2. 关联 Codex 线程/回合上下文
3. 支持两种引导模式：表单模式(Form) 和 URL 模式(Url)

## 功能点目的

### 核心功能
1. **线程上下文关联**：通过 `thread_id` 和 `turn_id` 将 MCP 引导请求关联到 Codex 会话
2. **服务器标识**：通过 `server_name` 标识发起请求的 MCP 服务器
3. **双模式支持**：
   - **Form 模式**：展示结构化表单收集用户输入
   - **Url 模式**：引导用户访问外部 URL（如 OAuth 授权页面）

### 使用场景
- MCP 工具需要额外用户确认或输入时
- MCP 服务器需要用户进行 OAuth 授权时
- MCP 工具需要用户从选项中选择配置时

## 具体技术实现

### 数据结构定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs (lines 5167-5185)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpServerElicitationRequestParams {
    pub thread_id: String,
    /// Active Codex turn when this elicitation was observed, if app-server could correlate one.
    ///
    /// This is nullable because MCP models elicitation as a standalone server-to-client request
    /// identified by the MCP server request id. It may be triggered during a turn, but turn
    /// context is app-server correlation rather than part of the protocol identity of the
    /// elicitation itself.
    pub turn_id: Option<String>,
    pub server_name: String,
    #[serde(flatten)]
    pub request: McpServerElicitationRequest,
}
```

### 引导请求体枚举

```rust
// lines 5504-5528
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(tag = "mode", rename_all = "camelCase")]
#[ts(tag = "mode")]
#[ts(export_to = "v2/")]
pub enum McpServerElicitationRequest {
    #[serde(rename_all = "camelCase")]
    #[ts(rename_all = "camelCase")]
    Form {
        #[serde(rename = "_meta")]
        #[ts(rename = "_meta")]
        meta: Option<JsonValue>,
        message: String,
        requested_schema: McpElicitationSchema,
    },
    #[serde(rename_all = "camelCase")]
    #[ts(rename_all = "camelCase")]
    Url {
        #[serde(rename = "_meta")]
        #[ts(rename = "_meta")]
        meta: Option<JsonValue>,
        message: String,
        url: String,
        elicitation_id: String,
    },
}
```

### 生成的 TypeScript 类型

```typescript
// schema/typescript/v2/McpServerElicitationRequestParams.ts
export type McpServerElicitationRequestParams = { 
    threadId: string, 
    turnId: string | null,  // 可为 null，因为 MCP 引导是独立的
    serverName: string, 
} & (
    { "mode": "form", _meta: JsonValue | null, message: string, requestedSchema: McpElicitationSchema } 
    | 
    { "mode": "url", _meta: JsonValue | null, message: string, url: string, elicitationId: string }
);
```

### 表单模式 Schema 结构

```rust
// McpElicitationSchema (lines 5191-5205)
pub struct McpElicitationSchema {
    #[serde(rename = "$schema", skip_serializing_if = "Option::is_none")]
    pub schema_uri: Option<String>,
    #[serde(rename = "type")]
    pub type_: McpElicitationObjectType,  // "object"
    pub properties: BTreeMap<String, McpElicitationPrimitiveSchema>,
    pub required: Option<Vec<String>>,
}
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
  - 行 5167-5185：`McpServerElicitationRequestParams` 结构体
  - 行 5504-5528：`McpServerElicitationRequest` 枚举

### 协议注册
```rust
// codex-rs/app-server-protocol/src/protocol/common.rs (lines 754-758)
server_request_definitions! {
    /// Request input for an MCP server elicitation.
    McpServerElicitationRequest => "mcpServer/elicitation/request" {
        params: v2::McpServerElicitationRequestParams,
        response: v2::McpServerElicitationRequestResponse,
    },
}
```

### 相关类型定义
| 类型 | 文件 | 行号 | 说明 |
|------|------|------|------|
| `McpServerElicitationRequestResponse` | v2.rs | 5559-5572 | 对应的响应类型 |
| `McpElicitationSchema` | v2.rs | 5191-5205 | 表单模式 Schema |
| `McpElicitationPrimitiveSchema` | v2.rs | 5214-5222 | 原始字段类型 |
| `McpServerElicitationAction` | v2.rs | 5127-5135 | 响应动作枚举 |

### 核心转换逻辑
```rust
// lines 5530-5557
impl TryFrom<CoreElicitationRequest> for McpServerElicitationRequest {
    type Error = serde_json::Error;
    fn try_from(value: CoreElicitationRequest) -> Result<Self, Self::Error> {
        match value {
            CoreElicitationRequest::Form { meta, message, requested_schema } => {
                Ok(Self::Form { meta, message, requested_schema: serde_json::from_value(requested_schema)? })
            }
            CoreElicitationRequest::Url { meta, message, url, elicitation_id } => {
                Ok(Self::Url { meta, message, url, elicitation_id })
            }
        }
    }
}
```

### 生成的 TypeScript 文件
- `codex-rs/app-server-protocol/schema/typescript/v2/McpServerElicitationRequestParams.ts`
- `codex-rs/app-server-protocol/schema/typescript/v2/McpElicitationSchema.ts`（依赖）
- `codex-rs/app-server-protocol/schema/typescript/v2/McpServerElicitationRequestResponse.ts`（配对）

## 依赖与外部交互

### 内部依赖
1. **ts-rs**：`#[ts(export_to = "v2/")]` 生成 TypeScript 类型
2. **schemars**：`#[derive(JsonSchema)]` 生成 JSON Schema
3. **serde**：序列化/反序列化，使用 `#[serde(flatten)]` 和 `#[serde(tag = "mode")]`

### 上游依赖
```rust
// 来自 codex_protocol::approvals
pub enum CoreElicitationRequest {
    Form { meta, message, requested_schema },
    Url { meta, message, url, elicitation_id },
}
```

### 数据流
```
MCP Server (rmcp)
    ↓
rmcp::model::ElicitationRequest
    ↓
codex_protocol::approvals::CoreElicitationRequest
    ↓
McpServerElicitationRequestParams (v2 API)
    ↓
Client (TypeScript)
    ↓
McpServerElicitationRequestResponse
    ↓
rmcp::model::CreateElicitationResult
    ↓
MCP Server
```

## 风险、边界与改进建议

### 潜在风险
1. **turn_id 可为 null**：虽然文档说明这是设计决策，但客户端需要正确处理 null 情况
2. **扁平序列化**：`#[serde(flatten)]` 可能导致某些 JSON Schema 验证器无法正确解析
3. **模式复杂性**：`McpElicitationSchema` 支持多种字段类型，客户端需要完整实现

### 边界情况
1. **空表单**：`properties` 为空时，客户端应如何展示？
2. **URL 模式无回调**：用户完成 URL 操作后，如何通知 MCP 服务器？
3. **并发引导**：同一服务器同时发起多个引导请求的处理

### 改进建议
1. **添加验证**：
   ```rust
   impl McpServerElicitationRequestParams {
       pub fn validate(&self) -> Result<(), ValidationError> {
           match &self.request {
               McpServerElicitationRequest::Form { requested_schema, .. } => {
                   if requested_schema.properties.is_empty() {
                       return Err(ValidationError::EmptyForm);
                   }
               }
               McpServerElicitationRequest::Url { url, .. } => {
                   if !url.starts_with("http") {
                       return Err(ValidationError::InvalidUrl);
                   }
               }
           }
           Ok(())
       }
   }
   ```

2. **添加超时字段**：考虑添加 `timeout_secs` 字段控制引导超时

3. **增强文档**：添加更多使用示例，特别是 URL 模式的回调机制

### 测试覆盖
相关测试位于 `v2.rs` 测试模块（行 7157+）：
- `test_elicitation_request_form_conversion`：表单模式转换测试
- `test_elicitation_request_url_conversion`：URL 模式转换测试
- `test_elicitation_schema_parsing`：Schema 解析测试

### API 稳定性
- 此类型属于稳定 API（无 `#[experimental]` 标记）
- 作为 ServerRequest 的核心方法，变更需要谨慎
- 建议通过添加可选字段而非修改现有结构来扩展
