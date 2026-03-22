# McpServerElicitationRequestParams.json 研究文档

## 场景与职责

`McpServerElicitationRequestParams` 是 Codex App-Server 协议中用于**MCP 服务器引导请求**的参数结构。当 MCP 服务器需要向用户请求额外信息（如确认、配置等）时，服务器通过此结构向客户端发送引导请求。

该类型属于 **Server → Client** 的请求流，对应 JSON-RPC 方法为 `mcpServer/elicitation/request`。

### 使用场景

1. **用户确认**：MCP 服务器需要用户确认某个操作
2. **配置收集**：收集 MCP 服务器运行所需的配置参数
3. **OAuth 流程**：引导用户完成 OAuth 认证流程

---

## 功能点目的

### 核心字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `serverName` | string | ✅ | MCP 服务器名称 |
| `threadId` | string | ✅ | 所属线程标识 |
| `turnId` | string \| null | ❌ | 所属回合标识（可能为 null） |

### 请求变体（oneOf）

该类型支持两种请求模式：

#### 1. 表单模式（Form Mode）

```json
{
  "mode": "form",
  "message": "Please confirm",
  "requestedSchema": { ... },
  "_meta": { ... }
}
```

#### 2. URL 模式（URL Mode）

```json
{
  "mode": "url",
  "message": "Please visit this URL",
  "url": "https://example.com/auth",
  "elicitationId": "unique-id",
  "_meta": { ... }
}
```

### 表单 Schema 类型

表单模式使用复杂的 JSON Schema 定义，支持：

- **字符串类型**：带格式验证（email, uri, date, date-time）
- **数字类型**：支持整数和浮点数，带范围限制
- **布尔类型**：简单 true/false
- **枚举类型**：单选或多选，支持带标题的选项

---

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpServerElicitationRequestParams {
    pub thread_id: String,
    /// Active Codex turn when this elicitation was observed, if app-server could correlate one.
    pub turn_id: Option<String>,
    pub server_name: String,
    #[serde(flatten)]
    pub request: McpServerElicitationRequest,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(tag = "mode", rename_all = "camelCase")]
#[ts(tag = "mode")]
#[ts(export_to = "v2/")]
pub enum McpServerElicitationRequest {
    Form {
        #[serde(rename = "_meta")]
        #[ts(rename = "_meta")]
        meta: Option<JsonValue>,
        message: String,
        requested_schema: McpElicitationSchema,
    },
    Url {
        #[serde(rename = "_meta")]
        #[ts(rename = "_meta")]
        meta: Option<JsonValue>,
        elicitation_id: String,
        message: String,
        url: String,
    },
}
```

### ServerRequest 注册

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs
server_request_definitions! {
    McpServerElicitationRequest => "mcpServer/elicitation/request" {
        params: v2::McpServerElicitationRequestParams,
        response: v2::McpServerElicitationRequestResponse,
    },
}
```

---

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 主类型定义（行 5170-5185） |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | McpElicitationSchema 定义（行 5191-5340） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ServerRequest 注册（行 755-758） |

### 使用方

| 文件 | 说明 |
|------|------|
| `codex-rs/core/src/mcp_tool_call.rs` | MCP 工具调用处理 |
| `codex-rs/core/src/mcp_tool_call_tests.rs` | MCP 测试 |
| `codex-rs/tui_app_server/src/bottom_pane/mcp_server_elicitation.rs` | TUI 引导 UI |
| `codex-rs/tui_app_server/src/chatwidget.rs` | 聊天组件处理 |
| `codex-rs/app-server/tests/suite/v2/mcp_server_elicitation.rs` | 集成测试 |

---

## 依赖与外部交互

### 依赖类型

```rust
use serde_json::Value as JsonValue;
use codex_protocol::approvals::ElicitationRequest as CoreElicitationRequest;
use rmcp::model::ElicitRequestFormParams;
```

### 与 RMCP 的关系

该类型与 RMCP（Rust MCP）库的 `ElicitRequestFormParams` 兼容：

```rust
impl TryFrom<CoreElicitationRequest> for McpServerElicitationRequest {
    fn try_from(value: CoreElicitationRequest) -> Result<Self, Self::Error> { ... }
}
```

---

## 风险、边界与改进建议

### 已知风险

1. **复杂 Schema**：表单 Schema 非常复杂，客户端实现难度大

2. **turnId 可能为 null**：`turnId` 为 `Option<String>`，客户端需要处理 null 情况

3. **实验性状态**：部分功能可能仍在演进中

### 边界情况

1. **无效 URL**：URL 模式下，`url` 字段的格式未验证
2. **空表单**：表单模式下，`properties` 为空对象时的行为

### 改进建议

1. **简化 Schema**：提供更简单的预定义表单类型：
   ```rust
   pub enum SimpleElicitationType {
       Confirm,           // 简单确认
       TextInput,         // 文本输入
       SingleChoice(Vec<String>),  // 单选
       MultipleChoice(Vec<String>), // 多选
   }
   ```

2. **URL 验证**：添加 URL 格式验证

3. **超时机制**：添加引导请求的超时处理

4. **国际化**：支持多语言消息
