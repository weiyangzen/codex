# streamable_http_recovery.rs 研究文档

## 场景与职责

`streamable_http_recovery.rs` 是 `codex-rmcp-client` crate 的集成测试文件，专注于验证 **MCP (Model Context Protocol) 客户端在使用 Streamable HTTP 传输时的会话恢复机制**。该测试验证客户端在遇到特定 HTTP 错误（特别是 404 Not Found 表示会话过期）时，能够自动重新初始化并继续操作。

### 测试目标
- 验证会话过期（HTTP 404）时的自动恢复机制
- 验证恢复机制仅重试一次，避免无限循环
- 验证非会话错误（401, 500）不会触发恢复
- 验证恢复后客户端能继续正常工作

## 功能点目的

### 1. 会话过期恢复
Streamable HTTP 传输使用会话 ID 维护客户端-服务器状态。当服务器返回 404 Not Found 且包含会话 ID 时，表示会话已过期，客户端需要：
- 检测会话过期（通过 `SessionExpired404` 错误）
- 重新执行初始化握手
- 重试原始请求

### 2. 恢复策略限制
- **仅重试一次**：防止无限恢复循环
- **仅针对 404**：其他错误（401, 500）不触发恢复
- **仅针对会话错误**：非会话相关的 404 不触发恢复

### 3. 测试服务器控制
测试使用专门的控制端点来模拟各种故障场景：
- `POST /test/control/session-post-failure`：配置会话 POST 失败
- 可配置失败状态码和失败次数

## 具体技术实现

### 测试架构

```
┌─────────────────┐      Streamable HTTP      ┌─────────────────────┐
│   RmcpClient    │  ◄──────────────────────► │ test_streamable_http │
│                 │                           │     _server          │
│ ┌─────────────┐ │                           │ ┌─────────────────┐ │
│ │SessionRecovery│ │                           │ │ SessionFailure  │ │
│ │   Lock      │ │                           │ │    State        │ │
│ └─────────────┘ │                           │ └─────────────────┘ │
│ ┌─────────────┐ │                           │ ┌─────────────────┐ │
│ │ Initialize  │ │                           │ │  Control API    │ │
│ │   Context   │ │                           │ │  (/test/control)│ │
│ └─────────────┘ │                           │ └─────────────────┘ │
└─────────────────┘                           └─────────────────────┘
```

### 会话恢复流程

```
客户端调用工具
    │
    ▼
发送 POST /mcp (带 session-id)
    │
    ▼
服务器返回 404 (会话过期)
    │
    ▼
StreamableHttpResponseClient 返回 SessionExpired404 错误
    │
    ▼
run_service_operation 检测 is_session_expired_404
    │
    ▼
获取 session_recovery_lock（防止并发恢复）
    │
    ▼
reinitialize_after_session_expiry
    ├─ 验证服务实例未变更（Arc::ptr_eq）
    ├─ 重新创建 pending transport
    ├─ 重新执行初始化握手
    └─ 更新 ClientState
    │
    ▼
重试原始请求
    │
    ▼
返回结果
```

### 关键测试辅助函数

#### `create_client(base_url: &str) -> anyhow::Result<RmcpClient>`
```rust
async fn create_client(base_url: &str) -> anyhow::Result<RmcpClient> {
    let client = RmcpClient::new_streamable_http_client(
        "test-streamable-http",
        &format!("{base_url}/mcp"),
        Some("test-bearer".to_string()),
        None,
        None,
        OAuthCredentialsStoreMode::File,
        Arc::new(StdMutex::new(None)),
    ).await?;

    client.initialize(init_params(), Some(Duration::from_secs(5)), ...).await?;
    Ok(client)
}
```

#### `arm_session_post_failure`
```rust
async fn arm_session_post_failure(
    base_url: &str,
    status: u16,
    remaining: usize,
) -> anyhow::Result<()> {
    let response = reqwest::Client::new()
        .post(format!("{base_url}{SESSION_POST_FAILURE_CONTROL_PATH}"))
        .json(&json!({ "status": status, "remaining": remaining }))
        .send()
        .await?;
    assert_eq!(response.status(), reqwest::StatusCode::NO_CONTENT);
    Ok(())
}
```

#### `spawn_streamable_http_server`
```rust
async fn spawn_streamable_http_server() -> anyhow::Result<(Child, String)> {
    let listener = TcpListener::bind("127.0.0.1:0")?;
    let port = listener.local_addr()?.port();
    drop(listener);

    let bind_addr = format!("127.0.0.1:{port}");
    let base_url = format!("http://{bind_addr}");
    let mut child = Command::new(streamable_http_server_bin()?)
        .kill_on_drop(true)
        .env("MCP_STREAMABLE_HTTP_BIND_ADDR", &bind_addr)
        .spawn()?;

    wait_for_streamable_http_server(&mut child, &bind_addr, Duration::from_secs(5)).await?;
    Ok((child, base_url))
}
```

### 测试用例详解

#### 1. `streamable_http_404_session_expiry_recovers_and_retries_once`

验证基本的会话恢复流程：

```rust
let (_server, base_url) = spawn_streamable_http_server().await?;
let client = create_client(&base_url).await?;

// 预热：确保连接正常
let warmup = call_echo_tool(&client, "warmup").await?;
assert_eq!(warmup, expected_echo_result("warmup"));

// 配置下一次请求返回 404
arm_session_post_failure(&base_url, 404, 1).await?;

// 调用应该自动恢复并成功
let recovered = call_echo_tool(&client, "recovered").await?;
assert_eq!(recovered, expected_echo_result("recovered"));
```

#### 2. `streamable_http_401_does_not_trigger_recovery`

验证 401 错误不触发恢复：

```rust
arm_session_post_failure(&base_url, 401, 2).await?;

// 第一次调用应该失败（401）
let first_error = call_echo_tool(&client, "unauthorized").await.unwrap_err();
assert!(first_error.to_string().contains("401"));

// 第二次调用仍然失败（没有恢复发生）
let second_error = call_echo_tool(&client, "still-unauthorized").await.unwrap_err();
assert!(second_error.to_string().contains("401"));
```

#### 3. `streamable_http_404_recovery_only_retries_once`

验证恢复仅重试一次：

```rust
// 配置连续 2 次 404
arm_session_post_failure(&base_url, 404, 2).await?;

// 第一次调用应该失败（恢复后再次 404）
let error = call_echo_tool(&client, "double-404").await.unwrap_err();
assert!(error.to_string().contains("handshaking with MCP server failed")
    || error.to_string().contains("Transport channel closed"));

// 后续调用应该成功（故障配置已耗尽）
let recovered = call_echo_tool(&client, "after-double-404").await?;
assert_eq!(recovered, expected_echo_result("after-double-404"));
```

#### 4. `streamable_http_non_session_failure_does_not_trigger_recovery`

验证非会话错误（500）不触发恢复：

```rust
arm_session_post_failure(&base_url, 500, 2).await?;

// 两次调用都应该失败（500），没有恢复发生
let first_error = call_echo_tool(&client, "server-error").await.unwrap_err();
assert!(first_error.to_string().contains("500"));

let second_error = call_echo_tool(&client, "still-server-error").await.unwrap_err();
assert!(second_error.to_string().contains("500"));
```

## 关键代码路径与文件引用

### 被测试代码

| 文件 | 相关组件 | 说明 |
|------|----------|------|
| `codex-rs/rmcp-client/src/rmcp_client.rs` | `run_service_operation()` | 通用操作执行，包含恢复逻辑 |
| `codex-rs/rmcp-client/src/rmcp_client.rs` | `is_session_expired_404()` | 检测会话过期错误 |
| `codex-rs/rmcp-client/src/rmcp_client.rs` | `reinitialize_after_session_expiry()` | 会话恢复实现 |
| `codex-rs/rmcp-client/src/rmcp_client.rs` | `session_recovery_lock` | 防止并发恢复的互斥锁 |
| `codex-rs/rmcp-client/src/rmcp_client.rs` | `StreamableHttpResponseClient::post_message()` | HTTP 客户端，检测 404 |

### 会话过期检测

```rust
// codex-rs/rmcp-client/src/rmcp_client.rs 第 1123-1141 行
fn is_session_expired_404(error: &ClientOperationError) -> bool {
    let ClientOperationError::Service(rmcp::service::ServiceError::TransportSend(error)) = error
    else {
        return false;
    };

    error
        .error
        .downcast_ref::<StreamableHttpError<StreamableHttpResponseClientError>>()
        .is_some_and(|error| {
            matches!(
                error,
                StreamableHttpError::Client(
                    StreamableHttpResponseClientError::SessionExpired404
                )
            )
        })
}
```

### HTTP 404 检测

```rust
// codex-rs/rmcp-client/src/rmcp_client.rs 第 178-182 行
if response.status() == reqwest::StatusCode::NOT_FOUND && session_id.is_some() {
    return Err(StreamableHttpError::Client(
        StreamableHttpResponseClientError::SessionExpired404,
    ));
}
```

### 恢复实现

```rust
// codex-rs/rmcp-client/src/rmcp_client.rs 第 1143-1194 行
async fn reinitialize_after_session_expiry(
    &self,
    failed_service: &Arc<RunningService<RoleClient, LoggingClientHandler>>,
) -> Result<()> {
    let _recovery_guard = self.session_recovery_lock.lock().await;

    // 验证服务实例未变更（防止重复恢复）
    {
        let guard = self.state.lock().await;
        match &*guard {
            ClientState::Ready { service, .. } if !Arc::ptr_eq(service, failed_service) => {
                return Ok(());  // 另一个任务已恢复
            }
            _ => {}
        }
    }

    // 获取初始化上下文
    let initialize_context = self.initialize_context.lock().await.clone()
        .ok_or_else(|| anyhow!("MCP client cannot recover before initialize succeeds"))?;

    // 重新创建传输层
    let pending_transport = Self::create_pending_transport(
        &self.transport_recipe,
        self.request_headers.clone()
    ).await?;

    // 重新连接和初始化
    let (service, oauth_persistor, process_group_guard) = Self::connect_pending_transport(
        pending_transport,
        initialize_context.handler,
        initialize_context.timeout,
    ).await?;

    // 更新状态
    {
        let mut guard = self.state.lock().await;
        *guard = ClientState::Ready {
            _process_group_guard: process_group_guard,
            service,
            oauth: oauth_persistor.clone(),
        };
    }

    // 持久化 OAuth 令牌
    if let Some(runtime) = oauth_persistor {
        runtime.persist_if_needed().await?;
    }

    Ok(())
}
```

### 测试服务器故障注入

```rust
// codex-rs/rmcp-client/src/bin/test_streamable_http_server.rs 第 127-145 行
#[derive(Clone, Default)]
struct SessionFailureState {
    armed_failure: Arc<Mutex<Option<ArmedFailure>>>,
}

#[derive(Clone, Debug)]
struct ArmedFailure {
    status: StatusCode,
    remaining: usize,
}

// 控制端点处理
async fn arm_session_post_failure(
    State(state): State<SessionFailureState>,
    Json(request): Json<ArmSessionPostFailureRequest>,
) -> Result<StatusCode, StatusCode> {
    let status = StatusCode::from_u16(request.status).map_err(|_| StatusCode::BAD_REQUEST)?;
    *state.armed_failure.lock().await = Some(ArmedFailure { status, remaining: request.remaining });
    Ok(StatusCode::NO_CONTENT)
}

// 中间件注入故障
async fn fail_session_post_when_armed(
    State(state): State<SessionFailureState>,
    request: Request<Body>,
    next: Next,
) -> Response {
    if request.uri().path() != "/mcp" || request.method() != Method::POST 
        || !request.headers().contains_key(MCP_SESSION_ID_HEADER) {
        return next.run(request).await;
    }

    let mut armed_failure = state.armed_failure.lock().await;
    if let Some(failure) = armed_failure.as_mut() && failure.remaining > 0 {
        failure.remaining -= 1;
        let status = failure.status;
        // 返回配置的故障状态码
        let mut response = Response::new(Body::from(format!("forced session failure with status {status}")));
        *response.status_mut() = status;
        return response;
    }

    next.run(request).await
}
```

## 依赖与外部交互

### 直接依赖

| 依赖 | 用途 |
|------|------|
| `tokio` | 异步运行时、进程管理、TCP 网络 |
| `reqwest` | HTTP 客户端（用于控制端点） |
| `serde_json` | JSON 序列化/反序列化 |
| `futures` | 异步工具（`FutureExt::boxed()`） |
| `rmcp` | MCP 协议模型和运行时 |
| `axum` | 测试服务器框架（在测试服务器二进制中） |
| `codex_rmcp_client::RmcpClient` | 被测试的客户端 |
| `codex_utils_cargo_bin` | 定位测试二进制 |

### 网络交互

| 组件 | 协议 | 说明 |
|------|------|------|
| `test_streamable_http_server` | HTTP/1.1 | MCP Streamable HTTP 服务器 |
| 控制端点 | HTTP POST | 配置故障注入 |
| MCP 端点 | HTTP POST/SSE | MCP 协议通信 |

### 环境变量

| 变量 | 用途 |
|------|------|
| `MCP_STREAMABLE_HTTP_BIND_ADDR` | 配置测试服务器绑定地址 |

## 风险、边界与改进建议

### 潜在风险

1. **竞态条件**
   - 多个并发请求同时遇到会话过期时，恢复锁确保只有一个恢复操作
   - `Arc::ptr_eq` 检查防止对已恢复服务的重复恢复

2. **恢复风暴**
   - 如果服务器持续返回 404，单次重试限制防止无限循环
   - 但快速连续的请求可能导致多次恢复尝试

3. **状态一致性**
   - 恢复期间新请求会等待锁释放
   - 恢复失败可能导致客户端处于不一致状态

### 边界情况

| 场景 | 当前处理 | 建议 |
|------|----------|------|
| 恢复期间客户端被 drop | 正常清理 | 确保锁释放 |
| 恢复后 OAuth 令牌过期 | 未测试 | 添加集成测试 |
| 网络分区（非 404） | 不触发恢复 | 考虑重试策略 |
| 服务器拒绝初始化 | 返回错误 | 添加指数退避 |
| 并发恢复请求 | 锁保护 | 考虑超时机制 |

### 改进建议

1. **可配置重试策略**
   ```rust
   pub struct RecoveryConfig {
       max_retries: u32,
       backoff_base: Duration,
       backoff_max: Duration,
   }
   ```

2. **恢复指标和监控**
   ```rust
   pub struct RecoveryMetrics {
       recovery_attempts: Counter,
       recovery_success: Counter,
       recovery_failure: Counter,
       recovery_duration: Histogram,
   }
   ```

3. **更细粒度的错误分类**
   - 区分"会话过期"和"会话不存在"
   - 区分"服务器错误"和"网络错误"
   - 为不同错误类型配置不同的恢复策略

4. **测试覆盖扩展**
   ```rust
   // 建议：测试恢复期间的并发请求
   async fn concurrent_requests_during_recovery() {
       // 一个请求触发恢复，其他请求应等待或失败优雅
   }

   // 建议：测试恢复超时
   async fn recovery_timeout() {
       // 恢复操作应有独立超时
   }

   // 建议：测试 OAuth 刷新与恢复的交互
   async fn recovery_with_oauth_refresh() {
       // 恢复期间可能需要刷新 OAuth 令牌
   }
   ```

5. **优雅降级**
   - 如果恢复失败，考虑将客户端标记为"需要重新初始化"
   - 而不是让后续请求都失败

6. **诊断信息增强**
   ```rust
   warn!(
       "MCP session expired, attempting recovery (server: {}, attempt: {})",
       server_name, attempt
   );
   ```

### 相关测试文件

- `codex-rs/rmcp-client/tests/process_group_cleanup.rs` - 进程清理测试
- `codex-rs/rmcp-client/tests/resources.rs` - 资源管理测试
- `codex-rs/core/tests/suite/rmcp_client.rs` - 核心 crate 的 MCP 客户端测试（包含 HTTP 传输测试）

### 相关配置

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| 恢复重试次数 | 1 | 硬编码在 `run_service_operation` |
| 初始化超时 | 5秒 | 测试中使用 `Duration::from_secs(5)` |
| 服务器启动超时 | 5秒 | `wait_for_streamable_http_server` |
| 进程终止宽限期 | 2秒 | `PROCESS_GROUP_TERM_GRACE_PERIOD` |
