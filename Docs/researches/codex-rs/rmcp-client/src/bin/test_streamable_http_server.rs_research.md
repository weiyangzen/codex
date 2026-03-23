# test_streamable_http_server.rs 研究文档

## 场景与职责

`test_streamable_http_server.rs` 是 Codex 项目中用于 MCP (Model Context Protocol) Streamable HTTP 传输的测试服务器。它是一个基于 HTTP 的 MCP 服务器，主要用于：

1. **Streamable HTTP 传输测试**：验证 MCP over HTTP 的端到端功能
2. **会话恢复测试**：支持模拟会话失效场景，测试客户端恢复能力
3. **OAuth 认证测试**：提供 OAuth 元数据端点和 Bearer Token 验证
4. **并发连接测试**：支持多客户端并发连接和会话管理

该服务器是 `codex-rs/rmcp-client/tests/streamable_http_recovery.rs` 的核心依赖，也是 `codex-rs/core/tests/suite/rmcp_client.rs` 中 HTTP 传输测试的基础。

## 功能点目的

### 1. Streamable HTTP MCP 服务

- **端点**：`/mcp` - 主要的 MCP 通信端点
- **传输**：使用 `rmcp` 库的 `StreamableHttpService`
- **会话管理**：基于 `LocalSessionManager` 的本地会话存储

### 2. 会话故障模拟

提供专门的控制端点用于测试会话恢复：

| 端点 | 方法 | 用途 |
|------|------|------|
| `/test/control/session-post-failure` | POST | 配置会话 POST 请求失败 |

**请求体**：
```json
{
    "status": 404,      // 返回的 HTTP 状态码
    "remaining": 1      // 失败次数，0 表示解除
}
```

**测试场景**：
- 404 会话过期：客户端应重新初始化会话并重试一次
- 401 未授权：不应触发恢复，应返回错误
- 500 服务器错误：不应触发恢复

### 3. OAuth 支持

- **元数据端点**：`/.well-known/oauth-authorization-server/mcp`
- **返回内容**：
  ```json
  {
      "authorization_endpoint": "http://{bind_addr}/oauth/authorize",
      "token_endpoint": "http://{bind_addr}/oauth/token",
      "scopes_supported": [""]
  }
  ```

### 4. Bearer Token 认证

- **环境变量**：`MCP_EXPECT_BEARER` - 设置期望的 Bearer Token
- **验证逻辑**：
  - 检查 `Authorization` 头
  - `/.well-known/` 路径豁免
  - 不匹配返回 401 Unauthorized

### 5. 工具与资源

提供与 STDIO 服务器类似的工具和资源：

- **工具**：`echo` - 回显消息并包含环境数据
- **资源**：`memo://codex/example-note` - 示例文本资源
- **资源模板**：`memo://codex/{slug}` - 动态资源模板

## 具体技术实现

### 关键数据结构

```rust
#[derive(Clone)]
struct TestToolServer {
    tools: Arc<Vec<Tool>>,
    resources: Arc<Vec<Resource>>,
    resource_templates: Arc<Vec<ResourceTemplate>>,
}

// 会话故障状态
#[derive(Clone, Default)]
struct SessionFailureState {
    armed_failure: Arc<Mutex<Option<ArmedFailure>>>,
}

#[derive(Clone, Debug)]
struct ArmedFailure {
    status: StatusCode,
    remaining: usize,  // 剩余失败次数
}

#[derive(Debug, Deserialize)]
struct ArmSessionPostFailureRequest {
    status: u16,
    remaining: usize,
}
```

### Axum 路由配置

```rust
let router = Router::new()
    // 故障控制端点
    .route(SESSION_POST_FAILURE_CONTROL_PATH, post(arm_session_post_failure))
    // OAuth 元数据
    .route("/.well-known/oauth-authorization-server/mcp", get(oauth_metadata))
    // MCP 服务
    .nest_service("/mcp", StreamableHttpService::new(
        || Ok(TestToolServer::new()),
        Arc::new(LocalSessionManager::default()),
        StreamableHttpServerConfig::default(),
    ))
    // 故障注入中间件
    .layer(middleware::from_fn_with_state(
        session_failure_state.clone(),
        fail_session_post_when_armed,
    ))
    // Bearer Token 中间件（可选）
    .layer(middleware::from_fn_with_state(expected, require_bearer))
    .with_state(session_failure_state);
```

### 故障注入中间件

```rust
async fn fail_session_post_when_armed(
    State(state): State<SessionFailureState>,
    request: Request<Body>,
    next: Next,
) -> Response {
    // 仅针对 /mcp 的 POST 请求且有 session ID
    if request.uri().path() != "/mcp"
        || request.method() != Method::POST
        || !request.headers().contains_key(MCP_SESSION_ID_HEADER)
    {
        return next.run(request).await;
    }

    let mut armed_failure = state.armed_failure.lock().await;
    if let Some(failure) = armed_failure.as_mut() && failure.remaining > 0 {
        failure.remaining -= 1;
        // 返回配置的故障状态码
        let mut response = Response::new(Body::from(format!(
            "forced session failure with status {}", failure.status
        )));
        *response.status_mut() = failure.status;
        return response;
    }

    drop(armed_failure);
    next.run(request).await
}
```

### 绑定地址解析

```rust
fn parse_bind_addr() -> Result<SocketAddr, Box<dyn std::error::Error>> {
    let default_addr = "127.0.0.1:3920";
    let bind_addr = std::env::var("MCP_STREAMABLE_HTTP_BIND_ADDR")
        .or_else(|_| std::env::var("BIND_ADDR"))
        .unwrap_or_else(|_| default_addr.to_string());
    Ok(bind_addr.parse()?)
}
```

### 带重试的绑定逻辑

```rust
const MAX_BIND_RETRIES: u32 = 20;
const BIND_RETRY_DELAY: Duration = Duration::from_millis(50);

let mut bind_retries = 0;
let listener = loop {
    match tokio::net::TcpListener::bind(&bind_addr).await {
        Ok(listener) => break listener,
        Err(err) if err.kind() == ErrorKind::PermissionDenied => {
            eprintln!("failed to bind to {bind_addr}: {err}");
            return Ok(());
        }
        Err(err) if err.kind() == ErrorKind::AddrInUse && bind_retries < MAX_BIND_RETRIES => {
            bind_retries += 1;
            sleep(BIND_RETRY_DELAY).await;
        }
        Err(err) => return Err(err.into()),
    }
};
```

## 关键代码路径与文件引用

### 当前文件
- **路径**：`codex-rs/rmcp-client/src/bin/test_streamable_http_server.rs`
- **行数**：419 行

### 调用方（测试代码）

1. **会话恢复测试**
   - 文件：`codex-rs/rmcp-client/tests/streamable_http_recovery.rs`
   - 测试函数：
     - `streamable_http_404_session_expiry_recovers_and_retries_once`
     - `streamable_http_401_does_not_trigger_recovery`
     - `streamable_http_404_recovery_only_retries_once`
     - `streamable_http_non_session_failure_does_not_trigger_recovery`

2. **核心集成测试**
   - 文件：`codex-rs/core/tests/suite/rmcp_client.rs`
   - 测试函数：
     - `streamable_http_tool_call_round_trip` (行 682-855)
     - `streamable_http_with_oauth_round_trip` (行 857-1000+)

### 测试辅助函数

```rust
// streamable_http_recovery.rs
fn streamable_http_server_bin() -> Result<PathBuf, CargoBinError> {
    codex_utils_cargo_bin::cargo_bin("test_streamable_http_server")
}

async fn arm_session_post_failure(
    base_url: &str,
    status: u16,
    remaining: usize,
) -> anyhow::Result<()> {
    let response = reqwest::Client::new()
        .post(format!("{base_url}{SESSION_POST_FAILURE_CONTROL_PATH}"))
        .json(&json!({"status": status, "remaining": remaining}))
        .send()
        .await?;
    assert_eq!(response.status(), reqwest::StatusCode::NO_CONTENT);
    Ok(())
}
```

## 依赖与外部交互

### 编译依赖

```toml
[dependencies]
axum = { workspace = true, features = ["http1", "tokio"] }
rmcp = { workspace = true, features = [
    "server",
    "transport-streamable-http-server",
] }
serde = { workspace = true, features = ["derive"] }
serde_json = { workspace = true }
tokio = { workspace = true, features = ["io-std", "time", "net", ...] }
```

### 运行时环境变量

| 变量名 | 用途 | 优先级 |
|--------|------|--------|
| `MCP_STREAMABLE_HTTP_BIND_ADDR` | 绑定地址 | 最高 |
| `BIND_ADDR` | 绑定地址（兼容） | 中 |
| `MCP_EXPECT_BEARER` | 期望的 Bearer Token | - |
| `MCP_TEST_VALUE` | echo 工具回显 | - |

### 网络端点

| 路径 | 方法 | 用途 |
|------|------|------|
| `/mcp` | POST/GET/DELETE | MCP Streamable HTTP 端点 |
| `/.well-known/oauth-authorization-server/mcp` | GET | OAuth 元数据 |
| `/test/control/session-post-failure` | POST | 故障注入控制 |

### 输入输出

- **输入**：HTTP 请求（MCP JSON-RPC 消息）
- **输出**：HTTP 响应（MCP JSON-RPC 响应或 SSE 流）
- **日志**：STDERR 输出 `"starting rmcp streamable http test server on http://{bind_addr}/mcp"`

## 风险、边界与改进建议

### 当前风险

1. **端口冲突**：虽然实现了重试逻辑，但在高并发测试环境下仍可能失败
2. **会话状态丢失**：使用 `LocalSessionManager`，进程重启会丢失所有会话
3. **故障注入范围有限**：仅支持 POST 请求，不支持 GET（SSE）流故障

### 边界情况

1. **绑定重试**：
   - 最大 20 次重试
   - 每次间隔 50ms
   - 权限错误立即失败

2. **故障注入**：
   - 仅针对带 `mcp-session-id` 头的 POST 请求
   - 计数器归零后自动解除
   - 支持通过 `remaining: 0` 手动解除

3. **认证**：
   - `/.well-known/` 路径始终豁免
   - 严格字节级比较 Bearer Token
   - 无 Token 时跳过认证层

4. **会话管理**：
   - 依赖 `rmcp` 库的 `LocalSessionManager`
   - 会话 ID 由服务器生成
   - 404 表示会话不存在或已过期

### 改进建议

1. **功能扩展**：
   - 添加 SSE 流故障注入（如连接中断、延迟）
   - 支持动态工具/资源注册（测试运行时变更）
   - 添加请求/响应日志端点（便于调试）

2. **可观测性**：
   - 添加 `/health` 健康检查端点
   - 添加 `/metrics` 指标端点
   - 添加请求日志中间件

3. **配置化**：
   - 支持配置文件控制工具/资源
   - 支持命令行参数覆盖环境变量
   - 支持 TLS/HTTPS 模式

4. **测试覆盖**：
   - 添加并发会话测试
   - 添加大负载消息测试
   - 添加网络分区模拟

5. **代码质量**：
   - 提取故障注入逻辑到独立模块
   - 添加 OpenAPI/Swagger 文档
   - 考虑使用状态机管理会话生命周期

### 相关测试覆盖

| 测试文件 | 测试函数 | 覆盖场景 |
|----------|----------|----------|
| `streamable_http_recovery.rs` | `streamable_http_404_session_expiry_recovers_and_retries_once` | 404 恢复 |
| `streamable_http_recovery.rs` | `streamable_http_401_does_not_trigger_recovery` | 401 不恢复 |
| `streamable_http_recovery.rs` | `streamable_http_404_recovery_only_retries_once` | 单次重试 |
| `streamable_http_recovery.rs` | `streamable_http_non_session_failure_does_not_trigger_recovery` | 非会话错误 |
| `rmcp_client.rs` | `streamable_http_tool_call_round_trip` | 基础 HTTP 调用 |
| `rmcp_client.rs` | `streamable_http_with_oauth_round_trip` | OAuth 流程 |

### 维护建议

该文件是 Streamable HTTP 传输测试的核心基础设施：

1. **修改注意事项**：
   - 故障注入逻辑变更需同步更新 `streamable_http_recovery.rs` 的测试预期
   - OAuth 元数据格式变更需检查客户端解析逻辑
   - 端点路径变更需同步更新所有测试

2. **调试技巧**：
   - 设置 `RUST_LOG=debug` 查看详细日志
   - 使用 `MCP_STREAMABLE_HTTP_BIND_ADDR` 固定端口便于抓包
   - 通过 `/test/control/session-post-failure` 手动触发故障

3. **性能考虑**：
   - 当前实现适合集成测试，不适合压力测试
   - 如需高并发测试，考虑使用外部会话存储（Redis）
