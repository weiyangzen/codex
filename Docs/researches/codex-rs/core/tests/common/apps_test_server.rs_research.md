# apps_test_server.rs 研究文档

## 文件信息
- **路径**: `codex-rs/core/tests/common/apps_test_server.rs`
- **大小**: 12,135 bytes (306 行)
- **所属模块**: core_test_support

---

## 场景与职责

此文件实现了用于测试 Codex Apps (MCP - Model Context Protocol) 集成的 Mock 服务器。它模拟了 ChatGPT Apps/Connectors 目录服务的行为，使测试能够在不依赖真实外部服务的情况下验证 Apps 功能的正确性。

### 核心职责
1. **模拟 OAuth 元数据端点**: 提供 OAuth 授权服务器配置
2. **模拟 Connectors 目录**: 返回可发现的 Apps 列表（如 Google Calendar、Gmail）
3. **模拟 MCP JSON-RPC 服务**: 实现 MCP 协议的初始化、工具列表和工具调用
4. **支持搜索测试**: 生成大量工具用于测试工具搜索功能

---

## 功能点目的

### 1. 常量定义
```rust
const CONNECTOR_ID: &str = "calendar";
const CONNECTOR_NAME: &str = "Calendar";
const DISCOVERABLE_CALENDAR_ID: &str = "connector_2128aebfecb84f64a069897515042a44";
const DISCOVERABLE_GMAIL_ID: &str = "connector_68df038e0ba48191908c8434991bbac2";
const PROTOCOL_VERSION: &str = "2025-11-25";
const SEARCHABLE_TOOL_COUNT: usize = 100;
pub const CALENDAR_CREATE_EVENT_RESOURCE_URI: &str = "connector://calendar/tools/calendar_create_event";
```
- 定义了测试用的 Calendar connector 常量
- 提供两个可发现的连接器：Calendar 和 Gmail
- `SEARCHABLE_TOOL_COUNT` 用于生成大量工具测试搜索功能

### 2. AppsTestServer 结构体
```rust
#[derive(Clone)]
pub struct AppsTestServer {
    pub chatgpt_base_url: String,
}
```
- 简单的包装结构体，保存 Mock 服务器的 base URL
- 提供三种挂载方式：
  - `mount()`: 标准挂载
  - `mount_searchable()`: 挂载并生成 100 个可搜索工具
  - `mount_with_connector_name()`: 使用自定义连接器名称挂载

### 3. OAuth 元数据端点
```rust
async fn mount_oauth_metadata(server: &MockServer) {
    Mock::given(method("GET"))
        .and(path("/.well-known/oauth-authorization-server/mcp"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "authorization_endpoint": format!("{}/oauth/authorize", server.uri()),
            "token_endpoint": format!("{}/oauth/token", server.uri()),
            "scopes_supported": [""],
        })))
        .mount(server)
        .await;
}
```
- 实现 OAuth 2.0 授权服务器元数据端点
- 返回授权端点和令牌端点 URL
- 符合 RFC 8414 规范

### 4. Connectors 目录端点
```rust
async fn mount_connectors_directory(server: &MockServer) {
    // /connectors/directory/list - 返回 Calendar 和 Gmail
    // /connectors/directory/list_workspace - 返回空列表
}
```
- 模拟 ChatGPT 的 connectors 目录 API
- 提供两个端点：
  - `/connectors/directory/list`: 返回通用 Apps（Calendar、Gmail）
  - `/connectors/directory/list_workspace`: 返回工作区 Apps（测试中为空）

### 5. MCP JSON-RPC 服务

#### 5.1 初始化 (initialize)
```rust
"initialize" => {
    ResponseTemplate::new(200).set_body_json(json!({
        "jsonrpc": "2.0",
        "id": id,
        "result": {
            "protocolVersion": protocol_version,
            "capabilities": { "tools": { "listChanged": true } },
            "serverInfo": { "name": SERVER_NAME, "version": SERVER_VERSION }
        }
    }))
}
```
- 实现 MCP 协议的初始化握手
- 返回协议版本、能力和服务器信息
- 支持 `tools/listChanged` 能力通知

#### 5.2 工具列表 (tools/list)
```rust
"tools/list" => {
    // 返回两个工具：calendar_create_event 和 calendar_list_events
    // 每个工具包含：name, description, inputSchema, _meta
    // _meta 包含 connector_id, connector_name, connector_description, _codex_apps
}
```
- 返回 Calendar 相关的两个工具
- `inputSchema` 定义工具参数结构
- `_meta` 字段包含 Codex Apps 特定的元数据

#### 5.3 工具调用 (tools/call)
```rust
"tools/call" => {
    // 提取 tool_name, title, starts_at 参数
    // 返回调用结果，包含 text 内容和 structuredContent
}
```
- 处理工具调用请求
- 返回格式化的调用结果文本
- 保留 `_codex_apps` 元数据

### 6. 可搜索工具生成
```rust
if self.searchable && let Some(tools) = response.pointer_mut("/result/tools").and_then(Value::as_array_mut) {
    for index in 2..SEARCHABLE_TOOL_COUNT {
        tools.push(json!({
            "name": format!("calendar_timezone_option_{index}"),
            "description": format!("Read timezone option {index}."),
            // ...
        }));
    }
}
```
- 当 `searchable=true` 时，生成 98 个额外的时区工具
- 用于测试工具搜索和过滤功能
- 工具名称格式：`calendar_timezone_option_{index}`

---

## 具体技术实现

### 架构设计
```
AppsTestServer
    ├── mount_oauth_metadata()      # OAuth 配置
    ├── mount_connectors_directory() # Apps 目录
    └── mount_streamable_http_json_rpc() # MCP 协议
            └── CodexAppsJsonRpcResponder
                    ├── initialize
                    ├── notifications/initialized
                    ├── tools/list
                    ├── tools/call
                    └── notifications/*
```

### wiremock 使用
- 使用 `wiremock::Mock` 定义请求匹配规则
- 使用 `wiremock::Respond` trait 实现动态响应
- 支持路径匹配、方法匹配和正则表达式路径匹配

### JSON-RPC 2.0 实现
- 遵循 JSON-RPC 2.0 规范
- 支持请求/响应的 id 关联
- 错误处理返回标准错误对象：
```rust
json!({
    "jsonrpc": "2.0",
    "id": id,
    "error": { "code": -32601, "message": format!("method not found: {method}") }
})
```

---

## 关键代码路径与文件引用

### 引用关系
```
apps_test_server.rs
    ├── 被 lib.rs 引用: pub mod apps_test_server
    ├── 被 tests/suite/apps_test.rs 使用 (如果有)
    └── 被 tests/suite/search_tool.rs 使用 (用于搜索测试)
```

### 使用示例
在测试代码中：
```rust
use core_test_support::apps_test_server::AppsTestServer;

#[tokio::test]
async fn test_apps_integration() {
    let server = MockServer::start().await;
    let apps = AppsTestServer::mount(&server).await.unwrap();
    
    // 使用 apps.chatgpt_base_url 进行测试
    // 测试代码可以调用 MCP 工具
}
```

---

## 依赖与外部交互

### 内部依赖
| 依赖 | 用途 |
|-----|------|
| `wiremock` | Mock HTTP 服务器 |
| `serde_json` | JSON 序列化 |
| `serde_json::json!` | 便捷 JSON 构造 |

### 协议依赖
| 协议/规范 | 说明 |
|----------|------|
| MCP (Model Context Protocol) | OpenAI 的模型上下文协议 |
| JSON-RPC 2.0 | 远程调用协议 |
| OAuth 2.0 | 授权框架 |

---

## 风险、边界与改进建议

### 潜在风险

1. **协议版本硬编码**
   - `PROTOCOL_VERSION` 硬编码为 "2025-11-25"
   - 如果 MCP 协议升级，可能需要同步更新

2. **工具 schema 硬编码**
   - 工具的 `inputSchema` 是硬编码的 JSON
   - 如果实际工具定义变更，测试可能失效

3. **搜索工具数量固定**
   - `SEARCHABLE_TOOL_COUNT = 100` 是固定值
   - 可能不足以测试大规模搜索场景

### 边界条件

1. **仅支持 Calendar 场景**
   - 当前仅模拟 Calendar connector
   - 不支持其他类型的 Apps（如 GitHub、Slack 等）

2. **有限的错误模拟**
   - 主要模拟成功场景
   - 缺乏对错误情况（如认证失败、网络错误）的模拟

3. **无状态实现**
   - 每次调用都是独立的
   - 不维护会话状态或工具调用历史

### 改进建议

1. **参数化工具生成**
   ```rust
   pub async fn mount_with_tools(server: &MockServer, tools: Vec<Tool>) -> Result<Self>
   ```
   允许测试指定自定义工具集。

2. **错误场景支持**
   ```rust
   pub async fn mount_with_error_rate(server: &MockServer, error_rate: f32) -> Result<Self>
   ```
   模拟随机失败以测试错误处理。

3. **多 Connector 支持**
   ```rust
   pub async fn mount_connectors(server: &MockServer, connectors: Vec<Connector>) -> Result<Self>
   ```
   支持同时模拟多个不同类型的 Apps。

4. **动态响应**
   使用状态机实现有状态的 Mock：
   ```rust
   struct CodexAppsJsonRpcResponder {
       state: Arc<Mutex<AppState>>,
   }
   ```

5. **配置提取**
   将硬编码的常量提取到配置结构体：
   ```rust
   pub struct AppsTestConfig {
       pub protocol_version: String,
       pub server_name: String,
       pub tools: Vec<Tool>,
   }
   ```

---

## 相关文件
- `codex-rs/core/tests/common/lib.rs` - 模块导出
- `codex-rs/protocol/src/mcp.rs` - MCP 协议定义
- `codex-rs/core/src/mcp_tool_call.rs` - MCP 工具调用实现
- `codex-rs/core/tests/suite/search_tool.rs` - 搜索工具测试
