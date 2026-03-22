# mcp_server_elicitation.rs 深入研究文档

## 场景与职责

`mcp_server_elicitation.rs` 是 Codex App Server v2 协议测试套件中的 MCP 服务器请求确认测试模块。该模块测试了完整的 MCP (Model Context Protocol) 服务器工具调用请求确认流程，包括从工具调用触发、elicitation 请求生成、客户端响应处理到最终结果返回的完整端到端流程。

该测试文件验证了 Codex 如何与外部 MCP 服务器集成，当 MCP 工具需要用户确认时，通过 elicitation 机制暂停工具执行，等待用户输入后再继续执行流程。

## 功能点目的

### 1. 完整 Elicitation 往返测试 (`mcp_server_elicitation_round_trip`)
这是该文件的核心测试，验证以下完整流程：
- 客户端启动线程并发送用户输入触发 MCP 工具调用
- MCP 服务器通过 `create_elicitation` 请求用户确认
- App Server 将 elicitation 转换为 `McpServerElicitationRequest` 发送给客户端
- 客户端响应 elicitation 请求（Accept/Decline/Cancel）
- MCP 服务器根据响应继续或终止工具执行
- 最终结果通过 function_call_output 返回给模型

## 具体技术实现

### 关键流程

#### 完整 Elicitation 流程
```
1. 预热阶段
   Client -> Responses API: "Warm up connectors."
   Responses API -> Client: assistant message "Warmup"

2. 工具调用触发
   Client -> Responses API: "Use [$calendar](app://calendar) to run the calendar tool."
   Responses API -> Client: function_call(mcp__codex_apps__calendar_confirm_action)

3. Elicitation 请求
   MCP Server -> App Server: create_elicitation(FormElicitationParams)
   App Server -> Client: McpServerElicitationRequest {
     thread_id, turn_id, server_name: "codex_apps",
     request: Form { message, requested_schema }
   }

4. 客户端响应
   Client -> App Server: McpServerElicitationRequestResponse {
     action: Accept, content: { confirmed: true }
   }

5. 继续执行
   App Server -> MCP Server: elicitation result
   MCP Server -> App Server: CallToolResult(success, [Content::text("accepted")])
   App Server -> Responses API: function_call_output(call_id, output)

6. 完成通知
   App Server -> Client: serverRequest/resolved notification
   App Server -> Client: turn/completed notification
```

### 数据结构

#### McpServerElicitationRequestParams
```rust
pub struct McpServerElicitationRequestParams {
    pub thread_id: String,
    pub turn_id: Option<String>,
    pub server_name: String,
    pub request: McpServerElicitationRequest,
}
```

#### McpServerElicitationRequest (Tagged Union)
```rust
pub enum McpServerElicitationRequest {
    Form {
        meta: Option<JsonValue>,
        message: String,
        requested_schema: McpElicitationSchema,
    },
    Url {
        meta: Option<JsonValue>,
        url: String,
    },
}
```

#### McpElicitationSchema
```rust
pub struct McpElicitationSchema {
    pub schema_uri: Option<String>,
    pub type_: McpElicitationObjectType,  // Object
    pub properties: BTreeMap<String, McpElicitationPrimitiveSchema>,
    pub required: Option<Vec<String>>,
}
```

#### McpServerElicitationRequestResponse
```rust
pub struct McpServerElicitationRequestResponse {
    pub action: McpServerElicitationAction,  // Accept, Decline, Cancel
    pub content: Option<JsonValue>,
    pub meta: Option<JsonValue>,
}
```

#### ServerRequestResolvedNotification
```rust
pub struct ServerRequestResolvedNotification {
    pub thread_id: String,
    pub request_id: RequestId,
}
```

### 测试辅助结构

#### ElicitationAppsMcpServer
实现了 `rmcp::handler::server::ServerHandler` trait 的测试 MCP 服务器：

```rust
struct ElicitationAppsMcpServer;

impl ServerHandler for ElicitationAppsMcpServer {
    fn get_info(&self) -> ServerInfo {
        ServerInfo {
            protocol_version: ProtocolVersion::V_2025_06_18,
            capabilities: ServerCapabilities::builder().enable_tools().build(),
            ..
        }
    }

    async fn list_tools(&self, ...) -> Result<ListToolsResult, rmcp::ErrorData> {
        // 返回 calendar_confirm_action 工具
        // 工具包含 connector_id 和 connector_name 的 meta 信息
    }

    async fn call_tool(&self, request: CallToolRequestParams, context: RequestContext<RoleServer>) 
        -> Result<CallToolResult, rmcp::ErrorData> {
        // 1. 构建 ElicitationSchema (要求 confirmed: boolean)
        // 2. 调用 context.peer.create_elicitation(...)
        // 3. 根据 result.action 返回不同的输出
    }
}
```

### 常量定义
```rust
const DEFAULT_READ_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(10);
const CONNECTOR_ID: &str = "calendar";
const CONNECTOR_NAME: &str = "Calendar";
const TOOL_NAME: &str = "calendar_confirm_action";
const QUALIFIED_TOOL_NAME: &str = "mcp__codex_apps__calendar_confirm_action";
const TOOL_CALL_ID: &str = "call-calendar-confirm";
const ELICITATION_MESSAGE: &str = "Allow this request?";
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/app-server/tests/suite/v2/mcp_server_elicitation.rs`: 本测试文件
- `codex-rs/app-server/tests/suite/v2/mod.rs`: v2 测试模块入口

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs`:
  - `McpServerElicitationRequestParams` (line 5170)
  - `McpServerElicitationRequest` (line 5508)
  - `McpServerElicitationAction` (line 5131)
  - `McpServerElicitationRequestResponse` (line 5562)
  - `McpElicitationSchema` (line 5194)
  - `ServerRequestResolvedNotification` (line 4942)

- `codex-rs/app-server-protocol/src/protocol/common.rs`:
  - `ServerRequest::McpServerElicitationRequest` (line 755)

### MCP 协议库 (rmcp)
- `rmcp::handler::server::ServerHandler`: MCP 服务器处理器接口
- `rmcp::model::CreateElicitationRequestParams`: Elicitation 创建参数
- `rmcp::model::ElicitationAction`: Accept/Decline/Cancel
- `rmcp::model::ElicitationSchema`: Elicitation 表单 schema
- `rmcp::transport::StreamableHttpService`: HTTP 流式传输服务

### 测试支持
- `codex-rs/app-server/tests/common/mcp_process.rs`:
  - `McpProcess::read_stream_until_request_message()`: 读取服务器请求
  - `McpProcess::send_response()`: 发送响应

- `core_test_support::responses`:
  - `start_mock_server()`: 启动模拟 Responses API 服务器
  - `mount_sse_sequence()`: 挂载 SSE 响应序列
  - `sse()`, `ev_response_created()`, `ev_function_call()`, `ev_assistant_message()`, `ev_completed()`: SSE 事件构造

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `rmcp` | MCP 协议实现，提供 ServerHandler、Elicitation 等 |
| `axum` | 测试 MCP 服务器的 HTTP 框架 |
| `tokio::net::TcpListener` | 绑定随机端口启动测试服务器 |
| `wiremock::MockServer` | 模拟 Responses API 服务器 |
| `serde_json::json!` | JSON 构造宏 |

### 内部依赖
| 模块 | 用途 |
|------|------|
| `app_test_support::McpProcess` | MCP 客户端进程管理 |
| `app_test_support::ChatGptAuthFixture` | ChatGPT 认证 fixtures |
| `app_test_support::write_chatgpt_auth` | 写入测试认证信息 |
| `app_test_support::to_response` | 响应解析 |
| `codex_app_server_protocol::*` | 协议类型 |
| `codex_core::auth::AuthCredentialsStoreMode` | 认证存储模式 |

### 测试服务器架构
```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Test Client   │────▶│  codex-app-server │────▶│  Responses API  │
│   (McpProcess)  │◀────│    (MCP Client)   │◀────│   (Mock Server) │
└─────────────────┘     └──────────────────┘     └─────────────────┘
         ▲                       │
         │                       ▼
         │              ┌──────────────────┐
         └──────────────│  Test MCP Server │
    (Elicitation Req)   │ (ElicitationApps │
    (Response)          │    McpServer)    │
                        └──────────────────┘
```

## 风险、边界与改进建议

### 已知风险

1. **多线程并发复杂性**
   - 测试使用 `#[tokio::test(flavor = "multi_thread", worker_threads = 4)]`
   - 涉及多个并发组件：MCP 客户端、MCP 服务器、Responses API 模拟
   - 时序问题可能导致间歇性失败

2. **硬编码超时**
   - `DEFAULT_READ_TIMEOUT = 10s` 可能在慢速 CI 环境不足
   - 建议根据环境动态调整

3. **SSE 序列顺序依赖**
   - 测试依赖特定的 SSE 事件顺序
   - 如果服务器实现改变事件顺序，测试会失败

### 边界情况

1. **Elicitation 超时**
   - 测试未覆盖客户端不响应 elicitation 请求的场景
   - 未测试 elicitation 超时后的行为

2. **并发 Elicitation**
   - 测试仅涉及单个 elicitation 请求
   - 多个同时进行的 elicitation 请求处理未验证

3. **错误响应**
   - 测试仅验证 Accept 流程
   - Decline 和 Cancel 的完整流程未充分测试

4. **URL Elicitation**
   - 测试仅覆盖 Form 类型的 elicitation
   - URL 类型的 elicitation 未测试

### 改进建议

1. **增加负面测试**
   ```rust
   // 建议添加
   async fn mcp_server_elicitation_decline_flow()
   async fn mcp_server_elicitation_cancel_flow()
   async fn mcp_server_elicitation_timeout()
   ```

2. **并发测试**
   ```rust
   // 建议添加
   async fn concurrent_mcp_server_elicitations()
   ```

3. **URL Elicitation 测试**
   ```rust
   // 建议添加
   async fn mcp_server_url_elicitation_round_trip()
   ```

4. **错误场景测试**
   - MCP 服务器返回错误时的处理
   - 网络中断时的恢复行为

5. **性能基准**
   - Elicitation 往返延迟测量
   - 大量工具调用时的性能表现

6. **测试可维护性**
   - 将 `start_apps_server()` 提取到共享测试库
   - 使用 builder 模式构造复杂的测试场景
