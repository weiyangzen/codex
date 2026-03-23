# websocket_fallback.rs 研究文档

## 场景与职责

`websocket_fallback.rs` 是 Codex Core 集成测试套件中专门测试 **WebSocket 降级到 HTTP 回退机制**的测试文件。该文件验证了当 WebSocket 连接失败时，系统能够正确降级到 HTTP SSE（Server-Sent Events）传输，确保服务连续性。

### 核心职责

1. **验证 426 降级**：测试收到 HTTP 426 Upgrade Required 响应时的即时降级
2. **验证重试后降级**：测试重试次数耗尽后的降级行为
3. **验证错误隐藏**：测试降级过程中的错误消息隐藏
4. **验证降级粘性**：测试降级状态在回合间的持续性

---

## 功能点目的

### 1. 426 响应即时降级 (`websocket_fallback_switches_to_http_on_upgrade_required_connect`)

**目的**：验证当服务器返回 HTTP 426 Upgrade Required 时，系统立即切换到 HTTP 传输，不再重试 WebSocket。

**测试逻辑**：
- 配置 Mock 服务器对 WebSocket 连接返回 426
- 配置 Mock 服务器对 HTTP POST 返回成功响应
- 验证只尝试了一次 WebSocket 连接
- 验证使用 HTTP POST 成功完成请求

**关键断言**：
```rust
assert_eq!(websocket_attempts, 1);  // 仅一次 WebSocket 尝试
assert_eq!(http_attempts, 1);        // 切换到 HTTP
assert_eq!(response_mock.requests().len(), 1);
```

### 2. 重试耗尽后降级 (`websocket_fallback_switches_to_http_after_retries_exhausted`)

**目的**：验证当 WebSocket 连接多次失败后，系统在重试次数耗尽后降级到 HTTP。

**测试逻辑**：
- 配置 `stream_max_retries = 2`
- 让 WebSocket 连接持续失败
- 验证降级行为：
  - 1 次启动预热尝试
  - 3 次流连接尝试（初始 + 2 次重试）
  - 然后切换到 HTTP

**关键断言**：
```rust
assert_eq!(websocket_attempts, 4);  // 1 预热 + 3 流尝试
assert_eq!(http_attempts, 1);        // 最终 HTTP 成功
```

### 3. 错误消息隐藏 (`websocket_fallback_hides_first_websocket_retry_stream_error`)

**目的**：验证降级过程中的重试错误消息被适当隐藏，避免用户困惑。

**测试逻辑**：
- 配置重试次数为 2
- 验证错误消息序列：
  - Debug 模式：`["Reconnecting... 1/2", "Reconnecting... 2/2"]`
  - Release 模式：`["Reconnecting... 2/2"]`（隐藏第一次重试消息）

**关键代码**：
```rust
let expected_stream_errors = if cfg!(debug_assertions) {
    vec!["Reconnecting... 1/2", "Reconnecting... 2/2"]
} else {
    vec!["Reconnecting... 2/2"]
};
```

### 4. 降级粘性 (`websocket_fallback_is_sticky_across_turns`)

**目的**：验证一旦降级到 HTTP，后续回合继续使用 HTTP，不再尝试 WebSocket。

**测试逻辑**：
- 第一回合：触发降级（WebSocket 失败 → HTTP）
- 第二回合：验证继续使用 HTTP，不再尝试 WebSocket

**关键断言**：
```rust
assert_eq!(websocket_attempts, 4);  // 仅第一回合的尝试
assert_eq!(http_attempts, 2);        // 两个回合都使用 HTTP
```

---

## 具体技术实现

### 关键数据结构

#### `ModelClientState`（会话状态）
```rust
struct ModelClientState {
    // ...
    disable_websockets: AtomicBool,  // 降级标志
    cached_websocket_session: StdMutex<WebsocketSession>,
}
```

#### `WebsocketSession`（连接会话）
```rust
struct WebsocketSession {
    connection: Option<ApiWebSocketConnection>,
    last_request: Option<ResponsesApiRequest>,
    last_response_rx: Option<oneshot::Receiver<LastResponse>>,
    connection_reused: StdMutex<bool>,
}
```

### 降级决策流程

#### 1. 426 响应处理

```rust
async fn handle_websocket_connect_result(
    &self,
    result: Result<ApiWebSocketConnection, ApiError>,
) -> WebsocketStreamOutcome {
    match result {
        Ok(conn) => WebsocketStreamOutcome::Stream(self.create_stream(conn)),
        Err(ApiError::HttpStatus(426)) => {
            // 426 Upgrade Required - 立即降级
            self.force_http_fallback();
            WebsocketStreamOutcome::FallbackToHttp
        }
        Err(err) if self.should_retry(&err) => {
            // 可重试错误
            self.retry_websocket_connect().await
        }
        Err(err) => {
            // 其他错误，尝试降级
            if self.retries_exhausted() {
                self.force_http_fallback();
                WebsocketStreamOutcome::FallbackToHttp
            } else {
                WebsocketStreamOutcome::Error(err)
            }
        }
    }
}
```

#### 2. 强制降级

```rust
pub(crate) fn force_http_fallback(
    &self,
    session_telemetry: &SessionTelemetry,
    _model_info: &ModelInfo,
) -> bool {
    let websocket_enabled = self.responses_websocket_enabled();
    let activated = websocket_enabled 
        && !self.state.disable_websockets.swap(true, Ordering::Relaxed);
    
    if activated {
        warn!("falling back to HTTP");
        session_telemetry.counter(
            "codex.transport.fallback_to_http",
            /*inc*/ 1,
            &[("from_wire_api", "responses_websocket")],
        );
    }
    
    // 清除缓存的 WebSocket 会话
    self.store_cached_websocket_session(WebsocketSession::default());
    activated
}
```

#### 3. WebSocket 启用检查

```rust
pub fn responses_websocket_enabled(&self) -> bool {
    if !self.state.provider.supports_websockets
        || self.state.disable_websockets.load(Ordering::Relaxed)
        || (*CODEX_RS_SSE_FIXTURE).is_some()
    {
        return false;
    }
    true
}
```

### 重试逻辑

#### 重试配置

```rust
pub struct ModelProviderInfo {
    pub supports_websockets: bool,
    pub stream_max_retries: Option<u32>,  // 流重试次数
    pub request_max_retries: Option<u32>, // 请求重试次数
    pub websocket_connect_timeout: Duration,
}
```

#### 重试决策

```rust
fn should_retry(&self, error: &ApiError) -> bool {
    match error {
        ApiError::Transport(TransportError::Timeout) => true,
        ApiError::HttpStatus(503) => true,  // Service Unavailable
        ApiError::HttpStatus(504) => true,  // Gateway Timeout
        _ => false,
    }
}
```

### 错误消息控制

#### 重试错误隐藏逻辑

```rust
// 仅在非第一次重试或 debug 模式下显示错误
fn should_emit_retry_error(&self, attempt: u32) -> bool {
    cfg!(debug_assertions) || attempt > 0
}

// 发送重试事件
if self.should_emit_retry_error(current_attempt) {
    session.send_event(
        turn_context,
        EventMsg::StreamError(StreamErrorEvent {
            message: format!("Reconnecting... {}/{}"), current_attempt + 1, max_retries),
        }),
    ).await;
}
```

---

## 关键代码路径与文件引用

### 核心实现文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/src/client.rs` | `ModelClient` 和降级逻辑实现 |
| `codex-rs/core/src/client_common.rs` | 客户端共享类型和工具 |
| `codex-rs/core/src/model_provider_info.rs` | 模型提供者配置（重试次数等） |

### WebSocket 实现

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/api/src/responses_websocket.rs` | WebSocket 客户端实现 |
| `codex-rs/api/src/transport.rs` | 传输层抽象 |

### 关键代码引用

#### WebSocket 连接建立
```rust
// codex-rs/core/src/client.rs:548-629
async fn connect_websocket(
    &self,
    session_telemetry: &SessionTelemetry,
    api_provider: codex_api::Provider,
    api_auth: CoreAuthProvider,
    turn_state: Option<Arc<OnceLock<String>>>,
    turn_metadata_header: Option<&str>,
    auth_context: AuthRequestTelemetryContext,
    request_route_telemetry: RequestRouteTelemetry,
) -> Result<ApiWebSocketConnection, ApiError> {
    let headers = self.build_websocket_headers(turn_state.as_ref(), turn_metadata_header);
    let websocket_telemetry = ...;
    let websocket_connect_timeout = self.state.provider.websocket_connect_timeout();
    
    let start = Instant::now();
    let result = tokio::time::timeout(
        websocket_connect_timeout,
        ApiWebSocketResponsesClient::new(api_provider, api_auth).connect(
            headers,
            default_headers(),
            turn_state,
            Some(websocket_telemetry),
        ),
    ).await;
    
    // 记录遥测数据...
    result
}
```

#### 降级触发
```rust
// codex-rs/core/src/client.rs:314-333
pub(crate) fn force_http_fallback(
    &self,
    session_telemetry: &SessionTelemetry,
    _model_info: &ModelInfo,
) -> bool {
    let websocket_enabled = self.responses_websocket_enabled();
    let activated = websocket_enabled 
        && !self.state.disable_websockets.swap(true, Ordering::Relaxed);
    
    if activated {
        warn!("falling back to HTTP");
        session_telemetry.counter(
            "codex.transport.fallback_to_http",
            /*inc*/ 1,
            &[("from_wire_api", "responses_websocket")],
        );
    }
    
    self.store_cached_websocket_session(WebsocketSession::default());
    activated
}
```

### 测试辅助工具

#### Mock 服务器配置
```rust
// 配置 WebSocket 失败
Mock::given(method("GET"))
    .and(path_regex(".*/responses$"))
    .respond_with(ResponseTemplate::new(426))
    .mount(&server)
    .await;

// 配置 HTTP 成功
let response_mock = mount_sse_once(
    &server,
    sse(vec![ev_response_created("resp-1"), ev_completed("resp-1")]),
).await;
```

#### 请求计数
```rust
let requests = server.received_requests().await.unwrap_or_default();
let websocket_attempts = requests
    .iter()
    .filter(|req| req.method == Method::GET && req.url.path().ends_with("/responses"))
    .count();
let http_attempts = requests
    .iter()
    .filter(|req| req.method == Method::POST && req.url.path().ends_with("/responses"))
    .count();
```

---

## 依赖与外部交互

### 外部依赖

1. **tokio_tungstenite**：WebSocket 客户端实现
2. **wiremock**：HTTP/WebSocket Mock 服务器
3. **tokio**：异步运行时和超时控制

### 内部依赖

1. **codex_api**：WebSocket 和 HTTP API 客户端
2. **codex_protocol**：协议类型定义
3. **core_test_support**：测试支持库

### 传输层交互

```
┌─────────────────┐
│   ModelClient   │
├─────────────────┤
│ WebSocket Layer │ ←→ tokio_tungstenite
├─────────────────┤
│   HTTP Layer    │ ←→ reqwest
├─────────────────┤
│  Telemetry      │ ←→ OpenTelemetry
└─────────────────┘
```

### 配置交互

| 配置项 | 描述 | 默认值 |
|-------|------|-------|
| `supports_websockets` | 是否启用 WebSocket | `false` |
| `stream_max_retries` | 流重试次数 | `2` |
| `request_max_retries` | 请求重试次数 | `0` |
| `websocket_connect_timeout` | WebSocket 连接超时 | 10s |

---

## 风险、边界与改进建议

### 已知风险

1. **降级延迟**：重试次数过多可能导致用户体验下降
2. **状态丢失**：降级可能导致 WebSocket 特定的状态丢失
3. **遥测准确性**：降级过程中的遥测数据可能不完整

### 边界情况

1. **降级后恢复**：当前实现一旦降级就不自动恢复 WebSocket
2. **部分成功**：WebSocket 连接成功但流中断的处理
3. **并发降级**：多个并发请求的降级竞争条件
4. **内存泄漏**：降级后 WebSocket 资源的清理

### 改进建议

1. **智能恢复**：
   - 定期尝试恢复 WebSocket 连接
   - 基于成功率动态调整重试策略
   - 提供手动恢复 WebSocket 的 API

2. **降级优化**：
   - 减少首次连接的重试次数
   - 实现指数退避策略
   - 根据错误类型调整降级策略

3. **可观测性**：
   - 添加降级原因指标
   - 记录降级历史
   - 提供降级状态查询接口

4. **测试扩展**：
   - 测试降级后的性能差异
   - 测试长时间运行后的降级行为
   - 测试网络分区恢复后的行为

### 配置建议

推荐的降级配置：
```rust
ModelProviderInfo {
    supports_websockets: true,
    stream_max_retries: Some(2),      // 平衡可靠性和延迟
    request_max_retries: Some(0),     // 请求不重试，依赖流重试
    websocket_connect_timeout: Duration::from_secs(10),
    // ...
}
```

### 错误处理改进

当前错误消息：
```
Reconnecting... 1/2
Reconnecting... 2/2
```

建议改进：
```
WebSocket connection failed, retrying (1/2)...
WebSocket unavailable, switching to HTTP...
```

### 相关 TODO

文件中未明确标记 TODO，但代码中有相关注释：
```rust
// If we don't treat 426 specially, the sampling loop would retry the WebSocket
// handshake before switching to the HTTP transport.
```

这表明 426 处理是一个重要的优化点。
