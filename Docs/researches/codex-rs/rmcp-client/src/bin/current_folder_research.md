# Research: codex-rs/rmcp-client/src/bin

## 概述

本目录包含 `codex-rmcp-client` crate 的三个二进制可执行文件（binaries），用于提供 MCP（Model Context Protocol）测试服务器。这些二进制文件主要用于集成测试、手动验证和开发调试场景。

---

## 1. 场景与职责

### 1.1 目录定位

```
codex-rs/rmcp-client/src/bin/
├── rmcp_test_server.rs         # 基础 MCP 测试服务器（简单版）
├── test_stdio_server.rs        # STDIO 传输测试服务器（完整版）
└── test_streamable_http_server.rs  # HTTP 流传输测试服务器
```

### 1.2 核心职责

| 二进制文件 | 主要职责 | 使用场景 |
|-----------|---------|---------|
| `rmcp_test_server` | 提供基础 MCP 工具服务（echo） | 核心集成测试、简单功能验证 |
| `test_stdio_server` | 提供完整 MCP 功能（工具、资源、图片场景测试） | 资源测试、TUI 图片渲染测试 |
| `test_streamable_http_server` | 提供 HTTP Streamable 传输的 MCP 服务 | HTTP 传输测试、OAuth 测试、会话恢复测试 |

### 1.3 与库代码的关系

这些二进制文件是**测试辅助工具**，与库代码形成互补关系：

- **库代码** (`src/*.rs`): 提供 MCP 客户端实现（`RmcpClient`）
- **二进制文件** (`src/bin/*.rs`): 提供 MCP 服务器端实现，用于测试客户端

```
测试架构:
┌─────────────────┐         MCP Protocol          ┌─────────────────┐
│   RmcpClient    │  ◄────────────────────────►  │  Test Servers   │
│   (library)     │    (stdio/http/streamable)   │   (binaries)    │
└─────────────────┘                              └─────────────────┘
        ▲                                                ▲
        │                                                │
        └────────────── 集成测试使用 ─────────────────────┘
```

---

## 2. 功能点目的

### 2.1 rmcp_test_server

**目的**: 最简化的 MCP 测试服务器，用于基础功能验证。

**提供的功能**:
- 单个 `echo` 工具：回显消息并返回环境变量 `MCP_TEST_VALUE`
- STDIO 传输方式
- 支持工具列表变更通知

**使用示例**:
```bash
cargo build -p codex-rmcp-client --bin rmcp_test_server
codex mcp add test -- /path/to/rmcp_test_server
```

### 2.2 test_stdio_server

**目的**: 功能完整的 STDIO 传输测试服务器，支持工具和资源的完整 MCP 协议。

**提供的工具**:

| 工具名 | 用途 |
|-------|------|
| `echo` | 基础回显，返回 `ECHOING: {message}` |
| `echo-tool` | 测试带连字符的工具名（非合法 JS 标识符）|
| `image` | 返回图片内容块（需设置 `MCP_TEST_IMAGE_DATA_URL`）|
| `image_scenario` | TUI 图片渲染场景测试（7 种场景）|

**提供的资源**:
- `memo://codex/example-note` - 示例文本资源
- `memo://codex/{slug}` - 资源模板

**Image Scenario 测试场景**:
```rust
enum ImageScenario {
    ImageOnly,                  // 仅图片
    TextThenImage,             // 文本后接图片
    InvalidBase64ThenImage,    // 无效 base64 后接有效图片
    InvalidImageBytesThenImage, // 无效图片字节后接有效图片
    MultipleValidImages,       // 多个有效图片
    ImageThenText,             // 图片后接文本
    TextOnly,                  // 仅文本（对照组）
}
```

### 2.3 test_streamable_http_server

**目的**: 测试 HTTP Streamable 传输模式，支持会话管理和错误注入。

**核心功能**:
- HTTP Streamable MCP 服务（端口可配置，默认 3920）
- OAuth 发现端点（`/.well-known/oauth-authorization-server/mcp`）
- 会话失败注入控制（用于测试会话恢复）
- Bearer Token 认证支持

**环境变量**:

| 变量名 | 用途 |
|-------|------|
| `MCP_STREAMABLE_HTTP_BIND_ADDR` | 绑定地址（默认 `127.0.0.1:3920`）|
| `MCP_TEST_VALUE` | echo 工具返回的环境值 |
| `MCP_EXPECT_BEARER` | 启用 Bearer Token 认证验证 |

**控制端点**:
```
POST /test/control/session-post-failure
Body: { "status": 404, "remaining": 1 }
```
用于测试客户端的会话过期恢复逻辑。

---

## 3. 具体技术实现

### 3.1 共同架构模式

三个服务器共享相同的架构模式：

```rust
// 1. 定义服务器结构体
#[derive(Clone)]
struct TestToolServer {
    tools: Arc<Vec<Tool>>,
    resources: Arc<Vec<Resource>>,         // test_stdio_server 和 test_streamable_http_server
    resource_templates: Arc<Vec<ResourceTemplate>>, // 同上
}

// 2. 实现 ServerHandler trait
impl ServerHandler for TestToolServer {
    fn get_info(&self) -> ServerInfo { ... }
    fn list_tools(&self, ...) -> impl Future<Output = Result<ListToolsResult, McpError>> { ... }
    async fn call_tool(&self, ...) -> Result<CallToolResult, McpError> { ... }
    // 可选: list_resources, read_resource 等
}

// 3. 主函数启动服务
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let service = TestToolServer::new();
    let running = service.serve(transport).await?;
    running.waiting().await?;
    task::yield_now().await;
    Ok(())
}
```

### 3.2 传输方式差异

| 服务器 | 传输方式 | 启动方式 |
|-------|---------|---------|
| `rmcp_test_server` | STDIO | `service.serve(stdio()).await?` |
| `test_stdio_server` | STDIO | `service.serve(stdio()).await?` |
| `test_streamable_http_server` | HTTP Streamable | `axum::serve(listener, router).await?` |

**STDIO 传输**:
```rust
pub fn stdio() -> (tokio::io::Stdin, tokio::io::Stdout) {
    (tokio::io::stdin(), tokio::io::stdout())
}
```

**HTTP Streamable 传输**:
```rust
let router = Router::new()
    .route(SESSION_POST_FAILURE_CONTROL_PATH, post(arm_session_post_failure))
    .route("/.well-known/oauth-authorization-server/mcp", get(oauth_metadata))
    .nest_service("/mcp", StreamableHttpService::new(...))
    .layer(middleware::from_fn_with_state(..., fail_session_post_when_armed));
```

### 3.3 工具定义与调用

**工具定义示例**（echo 工具）:
```rust
fn echo_tool() -> Tool {
    let schema: JsonObject = serde_json::from_value(json!({
        "type": "object",
        "properties": {
            "message": { "type": "string" },
            "env_var": { "type": "string" }
        },
        "required": ["message"],
        "additionalProperties": false
    })).expect("echo tool schema should deserialize");

    Tool::new(
        Cow::Borrowed("echo"),
        Cow::Borrowed("Echo back the provided message and include environment data."),
        Arc::new(schema),
    )
}
```

**工具调用处理**:
```rust
async fn call_tool(
    &self,
    request: CallToolRequestParams,
    _context: rmcp::service::RequestContext<rmcp::service::RoleServer>,
) -> Result<CallToolResult, McpError> {
    match request.name.as_ref() {
        "echo" => {
            let args: EchoArgs = /* 解析参数 */;
            let env_snapshot: HashMap<String, String> = std::env::vars().collect();
            let structured_content = json!({
                "echo": format!("ECHOING: {}", args.message),
                "env": env_snapshot.get("MCP_TEST_VALUE"),
            });
            Ok(CallToolResult {
                content: Vec::new(),
                structured_content: Some(structured_content),
                is_error: Some(false),
                meta: None,
            })
        }
        // ... 其他工具
    }
}
```

### 3.4 会话失败注入机制

用于测试客户端的会话恢复逻辑：

```rust
#[derive(Clone, Default)]
struct SessionFailureState {
    armed_failure: Arc<Mutex<Option<ArmedFailure>>>,
}

#[derive(Clone, Debug)]
struct ArmedFailure {
    status: StatusCode,
    remaining: usize,  // 剩余触发次数
}

// 控制端点：设置失败条件
async fn arm_session_post_failure(
    State(state): State<SessionFailureState>,
    Json(request): Json<ArmSessionPostFailureRequest>,
) -> Result<StatusCode, StatusCode> {
    let status = StatusCode::from_u16(request.status)?;
    *state.armed_failure.lock().await = Some(ArmedFailure {
        status,
        remaining: request.remaining,
    });
    Ok(StatusCode::NO_CONTENT)
}

// 中间件：在条件满足时注入失败
async fn fail_session_post_when_armed(
    State(state): State<SessionFailureState>,
    request: Request<Body>,
    next: Next,
) -> Response {
    // 检查是否是目标请求（POST /mcp 且带 session ID）
    if request.uri().path() != "/mcp" || request.method() != Method::POST {
        return next.run(request).await;
    }
    
    // 检查是否有待触发的失败
    let mut armed_failure = state.armed_failure.lock().await;
    if let Some(failure) = armed_failure.as_mut() && failure.remaining > 0 {
        failure.remaining -= 1;
        // 返回强制失败响应
        let mut response = Response::new(Body::from(format!("forced session failure")));
        *response.status_mut() = failure.status;
        return response;
    }
    
    next.run(request).await
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 文件结构

```
codex-rs/rmcp-client/
├── src/
│   ├── bin/
│   │   ├── rmcp_test_server.rs           # 基础测试服务器
│   │   ├── test_stdio_server.rs          # STDIO 完整测试服务器
│   │   └── test_streamable_http_server.rs # HTTP 测试服务器
│   ├── lib.rs                            # 库入口
│   ├── rmcp_client.rs                    # 主客户端实现
│   ├── logging_client_handler.rs         # 客户端处理器
│   ├── auth_status.rs                    # 认证状态检测
│   ├── oauth.rs                          # OAuth 凭证管理
│   ├── perform_oauth_login.rs            # OAuth 登录流程
│   ├── program_resolver.rs               # 程序路径解析
│   └── utils.rs                          # 工具函数
├── tests/
│   ├── resources.rs                      # 资源测试（使用 test_stdio_server）
│   ├── streamable_http_recovery.rs       # HTTP 恢复测试（使用 test_streamable_http_server）
│   └── process_group_cleanup.rs          # 进程清理测试
└── Cargo.toml
```

### 4.2 关键代码路径

**1. 工具调用处理链**:
```
test_stdio_server.rs:308-371
  └─ call_tool()
      ├─ "echo" / "echo-tool" → EchoArgs 解析 → 环境变量捕获 → CallToolResult
      ├─ "image" → MCP_TEST_IMAGE_DATA_URL 解析 → Content::image()
      └─ "image_scenario" → ImageScenarioArgs 解析 → image_scenario_result()
```

**2. 资源处理链**:
```
test_stdio_server.rs:259-306
  ├─ list_resources() → ListResourcesResult
  ├─ list_resource_templates() → ListResourceTemplatesResult
  └─ read_resource() → ReadResourceResult (memo://codex/example-note)
```

**3. HTTP 服务器中间件链**:
```
test_streamable_http_server.rs:341-348
  └─ require_bearer() [条件启用]
      └─ fail_session_post_when_armed()
          └─ StreamableHttpService::new()
              └─ TestToolServer handler
```

**4. 会话恢复测试路径**:
```
tests/streamable_http_recovery.rs:192-206
  └─ streamable_http_404_session_expiry_recovers_and_retries_once()
      ├─ spawn_streamable_http_server() → 启动服务器
      ├─ create_client() → 创建 RmcpClient
      ├─ arm_session_post_failure(404, 1) → 注入一次 404
      └─ call_echo_tool() → 验证自动恢复
```

### 4.3 外部引用

**被测试代码引用**:
- `codex-rs/core/tests/common/lib.rs:287-289`: `stdio_server_bin()` 函数返回 `test_stdio_server` 或 `rmcp_test_server` 路径
- `codex-rs/core/tests/suite/rmcp_client.rs`: 大量使用 `rmcp_test_server` 进行集成测试
- `codex-rs/rmcp-client/tests/*.rs`: 使用对应测试服务器

**库代码使用**:
- `codex-rs/tui/src/history_cell.rs`: 使用 `image_scenario` 工具测试图片渲染
- `codex-rs/tui_app_server/src/history_cell.rs`: 同上

---

## 5. 依赖与外部交互

### 5.1 直接依赖

```toml
# Cargo.toml 关键依赖
[dependencies]
rmcp = { workspace = true, features = [
    "auth",
    "base64",
    "client",
    "macros",
    "schemars",
    "server",
    "transport-child-process",
    "transport-streamable-http-client-reqwest",
    "transport-streamable-http-server",
] }
axum = { workspace = true, features = ["http1", "tokio"] }
tokio = { workspace = true, features = [...] }
serde = { workspace = true, features = ["derive"] }
serde_json = { workspace = true }
```

### 5.2 rmcp crate 使用

**ServerHandler trait**:
```rust
use rmcp::handler::server::ServerHandler;
use rmcp::model::*;

impl ServerHandler for TestToolServer {
    fn get_info(&self) -> ServerInfo;
    fn list_tools(&self, ...) -> impl Future<Output = Result<ListToolsResult, McpError>>;
    async fn call_tool(&self, ...) -> Result<CallToolResult, McpError>;
    // ... 其他可选方法
}
```

**ServiceExt 扩展**:
```rust
use rmcp::ServiceExt;
let running = service.serve(stdio()).await?;
running.waiting().await?;
```

### 5.3 与客户端的交互

**STDIO 传输**:
```
┌─────────────┐      stdin/stdout       ┌─────────────┐
│ RmcpClient  │ ◄─────────────────────► │ Test Server │
│             │   (JSON-RPC messages)   │             │
└─────────────┘                         └─────────────┘
```

**HTTP Streamable 传输**:
```
┌─────────────┐      HTTP POST/SSE      ┌─────────────┐
│ RmcpClient  │ ◄─────────────────────► │ Test Server │
│             │  /mcp (MCP_SESSION_ID)  │  (axum)     │
└─────────────┘                         └─────────────┘
```

### 5.4 环境变量交互

| 环境变量 | 读取方 | 用途 |
|---------|-------|------|
| `MCP_TEST_VALUE` | test_stdio_server, test_streamable_http_server | echo 工具返回的环境快照 |
| `MCP_TEST_IMAGE_DATA_URL` | test_stdio_server | image 工具的图片数据源 |
| `MCP_STREAMABLE_HTTP_BIND_ADDR` | test_streamable_http_server | HTTP 服务器绑定地址 |
| `MCP_EXPECT_BEARER` | test_streamable_http_server | 启用 Bearer Token 验证 |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

**1. 环境变量依赖**:
- 风险：测试服务器依赖特定环境变量，未设置时行为不一致
- 示例：`image` 工具在 `MCP_TEST_IMAGE_DATA_URL` 未设置时返回错误
- 缓解：代码中有明确的错误提示

**2. 端口冲突（HTTP 服务器）**:
- 风险：`test_streamable_http_server` 默认使用 3920 端口，可能冲突
- 缓解：支持 `MCP_STREAMABLE_HTTP_BIND_ADDR` 自定义端口，有重试逻辑

**3. 并发测试限制**:
- 风险：部分测试使用固定端口或全局状态，不能并发执行
- 示例：`streamable_http_recovery.rs` 使用 `#[tokio::test(flavor = "multi_thread", worker_threads = 1)]`

### 6.2 边界情况

**1. 工具名规范**:
- `echo-tool` 工具专门测试带连字符的工具名（非合法 JS 标识符）
- 确保客户端能正确处理这类工具名

**2. 图片内容处理**:
- `image_scenario` 工具提供 7 种场景覆盖边界情况
- 包括无效 base64、无效图片字节、多图片等边界

**3. 会话过期恢复**:
- HTTP 服务器支持注入 404 错误模拟会话过期
- 客户端应能自动重新初始化会话并重试

### 6.3 改进建议

**1. 配置化增强**:
```rust
// 建议：支持配置文件而非仅环境变量
#[derive(Deserialize)]
struct ServerConfig {
    tools: Vec<ToolConfig>,
    resources: Vec<ResourceConfig>,
    bind_addr: Option<SocketAddr>,
}
```

**2. 健康检查端点**:
```rust
// 建议：HTTP 服务器添加健康检查
.route("/health", get(|| async { StatusCode::OK }))
```

**3. 日志级别控制**:
- 当前：使用 `eprintln!` 输出启动信息
- 建议：集成 `tracing` 支持结构化日志和级别控制

**4. 文档生成**:
```rust
// 建议：自动生成 OpenAPI/MCP 能力文档
#[derive(clap::Parser)]
struct Args {
    #[arg(long)]
    dump_schema: Option<PathBuf>,
}
```

**5. 测试覆盖率**:
- 当前：主要覆盖正常路径
- 建议：增加错误路径测试（如无效 JSON、超时、连接断开）

### 6.4 维护注意事项

**代码同步**:
- `test_stdio_server.rs` 和 `test_streamable_http_server.rs` 有大量重复代码（TestToolServer 实现）
- 建议：提取公共模块减少重复

**协议版本**:
- 当前使用 `rmcp` crate 的默认协议版本
- MCP 协议演进时需同步更新

**安全考虑**:
- 测试服务器不应用于生产环境
- `test_streamable_http_server` 的 OAuth 端点是模拟实现

---

## 附录：快速参考

### 构建命令
```bash
# 构建所有二进制文件
cargo build -p codex-rmcp-client --bins

# 单独构建
cargo build -p codex-rmcp-client --bin rmcp_test_server
cargo build -p codex-rmcp-client --bin test_stdio_server
cargo build -p codex-rmcp-client --bin test_streamable_http_server
```

### 运行测试
```bash
# 运行 rmcp-client 测试
cargo test -p codex-rmcp-client

# 运行核心集成测试（使用测试服务器）
cargo test -p codex-core rmcp_client
```

### 手动测试 TUI 图片渲染
```bash
# 1. 构建并注册
cargo build -p codex-rmcp-client --bin test_stdio_server
codex mcp add mcpimg -- /abs/path/to/test_stdio_server

# 2. TUI 中调用
# mcpimg.image_scenario({"scenario":"text_then_image","caption":"Hello"})
```
