# 研究报告: `codex-rs/core/tests/suite/client_websockets.rs`

## 1. 场景与职责

### 1.1 文件定位

`client_websockets.rs` 是 Codex Rust 核心库 (`codex-core`) 的集成测试套件，专门负责测试 **OpenAI Responses API over WebSocket** 传输层的完整功能。该文件位于 `codex-rs/core/tests/suite/` 目录下，属于核心测试套件的一部分。

### 1.2 核心职责

该测试文件承担以下关键职责：

1. **WebSocket 连接生命周期管理测试**: 验证 WebSocket 连接的建立、复用、重连和关闭逻辑
2. **协议合规性测试**: 确保客户端正确实现 OpenAI Responses WebSocket 协议 (v2 beta: `responses_websockets=2026-02-06`)
3. **增量请求优化测试**: 验证基于 `previous_response_id` 的增量请求机制，减少重复数据传输
4. **预连接与预热机制测试**: 测试 `preconnect_websocket` 和 `prewarm_websocket` 功能
5. **错误处理与降级测试**: 验证 WebSocket 失败时的 HTTP fallback 机制
6. **遥测与指标测试**: 确保 WebSocket 调用和事件被正确记录到遥测系统
7. **速率限制与配额管理测试**: 验证服务端速率限制事件的解析和处理

### 1.3 测试架构角色

```
┌─────────────────────────────────────────────────────────────────┐
│                    测试架构层次                                   │
├─────────────────────────────────────────────────────────────────┤
│  client_websockets.rs (本文件)                                   │
│  ├── 集成测试用例 (30+ 个测试函数)                                │
│  ├── WebSocketTestServer (模拟服务端)                            │
│  └── WebsocketTestHarness (测试脚手架)                           │
├─────────────────────────────────────────────────────────────────┤
│  core/tests/common/responses.rs (测试基础设施)                    │
│  ├── WebSocketTestServer 实现                                    │
│  ├── SSE/HTTP 模拟服务器                                         │
│  └── 请求捕获与验证工具                                          │
├─────────────────────────────────────────────────────────────────┤
│  core/tests/common/test_codex.rs                                  │
│  ├── TestCodexBuilder (测试构建器)                               │
│  └── TestCodex (集成测试上下文)                                   │
├─────────────────────────────────────────────────────────────────┤
│  core/src/client.rs (被测系统 - SUT)                              │
│  ├── ModelClient (会话级客户端)                                  │
│  ├── ModelClientSession (回合级会话)                             │
│  └── WebSocket 连接管理逻辑                                      │
├─────────────────────────────────────────────────────────────────┤
│  codex-api/src/endpoint/responses_websocket.rs                   │
│  ├── ResponsesWebsocketClient (底层 WebSocket 客户端)            │
│  └── ResponsesWebsocketConnection (连接管理)                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 主要测试功能矩阵

| 功能类别 | 测试用例数量 | 代表测试函数 | 目的说明 |
|---------|-------------|-------------|---------|
| **基础流式请求** | 3 | `responses_websocket_streams_request` | 验证基本的 WebSocket 流式请求/响应 |
| **连接复用** | 5 | `responses_websocket_reuses_connection_*` | 验证跨回合连接复用机制 |
| **预连接/预热** | 5 | `responses_websocket_preconnect_*`, `responses_websocket_prewarm_*` | 验证预连接优化 |
| **增量请求 (V2)** | 6 | `responses_websocket_v2_*`, `responses_websocket_uses_incremental_*` | 验证增量请求协议 |
| **遥测与指标** | 4 | `responses_websocket_emits_*_events` | 验证遥测数据收集 |
| **错误处理** | 5 | `responses_websocket_*_error_*` | 验证错误恢复和降级 |
| **协议特性** | 4 | `responses_websocket_*_header_*`, `responses_websocket_*_metadata_*` | 验证协议头和行为 |

### 2.2 关键功能详解

#### 2.2.1 WebSocket V2 协议支持

测试文件针对 OpenAI Responses WebSocket V2 协议进行全面测试：

- **Beta Header**: 验证 `OpenAI-Beta: responses_websockets=2026-02-06` 正确发送
- **增量请求**: 使用 `previous_response_id` 字段只发送新增消息，而非完整历史
- **请求追踪**: 通过 `client_metadata` 传递 W3C Trace Context 实现分布式追踪

#### 2.2.2 连接生命周期优化

```rust
// 连接复用策略测试要点:
1. 同一会话的多个回合复用同一 WebSocket 连接
2. 会话结束后连接缓存到新会话
3. preconnect 建立连接但不发送请求
4. prewarm 发送 warmup 请求 (generate=false) 预热连接
```

#### 2.2.3 降级与容错

- **HTTP Fallback**: 当 WebSocket 不可用时 (如收到 426 Upgrade Required)，自动降级到 HTTP SSE
- **连接限制重连**: 当收到 `websocket_connection_limit_reached` 错误时，自动建立新连接重试
- **认证恢复**: 401 错误触发 token 刷新后重试

---

## 3. 具体技术实现

### 3.1 核心数据结构

#### 3.1.1 测试脚手架结构

```rust
/// 测试脚手架，封装 WebSocket 测试所需的所有组件
struct WebsocketTestHarness {
    _codex_home: TempDir,           // 临时配置目录
    client: ModelClient,             // 被测客户端
    conversation_id: ThreadId,       // 会话 ID
    model_info: ModelInfo,           // 模型信息
    effort: Option<ReasoningEffortConfig>,  // 推理努力程度
    summary: ReasoningSummary,       // 推理摘要配置
    session_telemetry: SessionTelemetry,  // 遥测会话
}
```

#### 3.1.2 模拟服务器配置

```rust
/// WebSocket 连接配置，定义一个连接的行为
pub struct WebSocketConnectionConfig {
    pub requests: Vec<Vec<Value>>,   // 每个请求对应的响应事件序列
    pub response_headers: Vec<(String, String)>, // 握手响应头
    pub accept_delay: Option<Duration>, // 接受延迟（用于测试超时）
    pub close_after_requests: bool,  // 请求完成后是否关闭连接
}
```

### 3.2 关键测试流程

#### 3.2.1 基础流式测试流程

```rust
async fn responses_websocket_streams_request() {
    // 1. 启动模拟 WebSocket 服务器
    let server = start_websocket_server(vec![vec![vec![
        ev_response_created("resp-1"),
        ev_completed("resp-1"),
    ]]]).await;

    // 2. 构建测试脚手架
    let harness = websocket_harness(&server).await;
    let mut client_session = harness.client.new_session();
    let prompt = prompt_with_input(vec![message_item("hello")]);

    // 3. 执行流式请求直到完成
    stream_until_complete(&mut client_session, &harness, &prompt).await;

    // 4. 验证请求内容
    let connection = server.single_connection();
    let body = connection.first().expect("missing request").body_json();
    assert_eq!(body["type"].as_str(), Some("response.create"));
    assert_eq!(body["model"].as_str(), Some(MODEL));
    assert_eq!(body["stream"], serde_json::Value::Bool(true));

    // 5. 验证握手头
    let handshake = server.single_handshake();
    assert_eq!(handshake.header(OPENAI_BETA_HEADER), 
               Some(WS_V2_BETA_HEADER_VALUE.to_string()));
}
```

#### 3.2.2 增量请求测试流程

```rust
async fn responses_websocket_uses_incremental_create_on_prefix() {
    // 配置两个请求序列：
    // - 第一个：用户消息 "hello" -> 助手回复
    // - 第二个：用户消息 "hello" + 助手回复 + "second"（增量）
    let server = start_websocket_server(vec![vec![
        vec![ev_response_created("resp-1"), ev_assistant_message("msg-1", "..."), ev_completed("resp-1")],
        vec![ev_response_created("resp-2"), ev_completed("resp-2")],
    ]]).await;

    let harness = websocket_harness(&server).await;
    let mut client_session = harness.client.new_session();
    
    // 第一轮：完整请求
    let prompt_one = prompt_with_input(vec![message_item("hello")]);
    stream_until_complete(&mut client_session, &harness, &prompt_one).await;
    
    // 第二轮：增量请求（包含前缀）
    let prompt_two = prompt_with_input(vec![
        message_item("hello"),
        assistant_message_item("msg-1", "assistant output"),
        message_item("second"),
    ]);
    stream_until_complete(&mut client_session, &harness, &prompt_two).await;

    // 验证：第二个请求使用 previous_response_id 且只发送增量输入
    let connection = server.single_connection();
    let second = connection.get(1).expect("missing request").body_json();
    assert_eq!(second["previous_response_id"].as_str(), Some("resp-1"));
    assert_eq!(second["input"], serde_json::to_value(&prompt_two.input[2..]).unwrap());
}
```

#### 3.2.3 遥测验证流程

```rust
async fn responses_websocket_emits_websocket_telemetry_events() {
    let server = start_websocket_server(...).await;
    let harness = websocket_harness(&server).await;
    
    // 重置遥测指标
    harness.session_telemetry.reset_runtime_metrics();
    
    // 执行请求
    stream_until_complete(...).await;
    
    // 验证遥测数据
    let summary = harness.session_telemetry.runtime_metrics_summary().expect("...");
    assert_eq!(summary.api_calls.count, 0);           // 无 HTTP API 调用
    assert_eq!(summary.streaming_events.count, 0);    // 无 SSE 事件
    assert_eq!(summary.websocket_calls.count, 1);     // 1 次 WebSocket 调用
    assert_eq!(summary.websocket_events.count, 2);    // 2 个 WebSocket 事件
}
```

### 3.3 协议实现细节

#### 3.3.1 WebSocket 请求消息格式

```rust
// ResponseCreateWsRequest 结构（来自 codex-api）
pub struct ResponseCreateWsRequest {
    pub client_metadata: HashMap<String, String>,  // 包含 traceparent, tracestate, turn-metadata
    pub model: String,
    pub instructions: String,
    pub input: Vec<ResponseItem>,
    pub tools: Vec<Tool>,
    pub stream: bool,
    pub previous_response_id: Option<String>,  // 增量请求关键字段
    pub generate: Option<bool>,                // warmup 时设为 false
    // ... 其他字段
}
```

#### 3.3.2 关键 HTTP Header

| Header | 说明 | 测试验证点 |
|-------|------|-----------|
| `OpenAI-Beta` | 协议版本标识 | `responses_websocket_streams_request` 验证 `responses_websockets=2026-02-06` |
| `x-client-request-id` | 客户端请求 ID | 验证与会话 ID 一致 |
| `x-codex-turn-state` | 粘性路由令牌 | 跨请求保持会话一致性 |
| `x-codex-turn-metadata` | 回合元数据 | 验证正确传递和解析 |
| `x-responsesapi-include-timing-metrics` | 时序指标开关 | 遥测测试验证 |

### 3.4 测试辅助函数

```rust
// 构建测试脚手架
async fn websocket_harness(server: &WebSocketTestServer) -> WebsocketTestHarness

// 带运行时指标的配置
async fn websocket_harness_with_runtime_metrics(
    server: &WebSocketTestServer,
    runtime_metrics_enabled: bool,
) -> WebsocketTestHarness

// 流式请求直到完成
async fn stream_until_complete(
    client_session: &mut ModelClientSession,
    harness: &WebsocketTestHarness,
    prompt: &Prompt,
)

// 带服务层级的流式请求
async fn stream_until_complete_with_service_tier(...)

// 带回合元数据的流式请求
async fn stream_until_complete_with_turn_metadata(...)

// 消息构建辅助函数
fn message_item(text: &str) -> ResponseItem
fn assistant_message_item(id: &str, text: &str) -> ResponseItem
fn prompt_with_input(input: Vec<ResponseItem>) -> Prompt
```

---

## 4. 关键代码路径与文件引用

### 4.1 被测系统 (SUT) 代码路径

| 文件路径 | 职责 | 与本测试的关联 |
|---------|------|---------------|
| `codex-rs/core/src/client.rs` | `ModelClient` 和 `ModelClientSession` 实现 | 主要被测对象，包含 WebSocket 连接管理和请求逻辑 |
| `codex-rs/core/src/client_common.rs` | `Prompt`, `ResponseStream`, `ResponseEvent` 定义 | 测试数据结构和事件类型 |
| `codex-rs/core/src/model_provider_info.rs` | `ModelProviderInfo`, `WireApi` | 提供商配置和 WebSocket 能力检测 |
| `codex-rs/codex-api/src/endpoint/responses_websocket.rs` | `ResponsesWebsocketClient`, `ResponsesWebsocketConnection` | 底层 WebSocket 客户端实现 |
| `codex-rs/codex-api/src/common.rs` | `ResponseCreateWsRequest`, `ResponsesWsRequest` | WebSocket 请求数据结构 |

### 4.2 测试基础设施代码路径

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/tests/common/responses.rs` | `WebSocketTestServer`, `WebSocketHandshake`, `WebSocketRequest`, SSE/HTTP 模拟 |
| `codex-rs/core/tests/common/test_codex.rs` | `TestCodexBuilder`, `TestCodex`, 测试构建器 |
| `codex-rs/core/tests/common/lib.rs` | 共享测试工具，`wait_for_event`, `load_default_config_for_test` |

### 4.3 核心调用链

```
测试用例 (client_websockets.rs)
    ↓
websocket_harness() → 创建 ModelClient
    ↓
client.new_session() → ModelClientSession
    ↓
stream_until_complete() → client_session.stream()
    ↓
core/src/client.rs: ModelClientSession::stream()
    ↓
stream_responses_websocket() / stream_responses_api()
    ↓
codex-api: ResponsesWebsocketClient::connect()
    ↓
tokio_tungstenite::connect_async_tls_with_config()
```

### 4.4 增量请求决策逻辑

```rust
// core/src/client.rs: ModelClientSession::prepare_websocket_request()
fn prepare_websocket_request(&mut self, payload: ResponseCreateWsRequest, request: &ResponsesApiRequest) 
    -> ResponsesWsRequest {
    
    // 1. 获取上一轮响应
    let Some(last_response) = self.get_last_response() else {
        return ResponsesWsRequest::ResponseCreate(payload);  // 无上一轮，完整请求
    };
    
    // 2. 检查是否可以增量
    let Some(incremental_items) = self.get_incremental_items(request, Some(&last_response), true) else {
        return ResponsesWsRequest::ResponseCreate(payload);  // 不能增量，完整请求
    };
    
    // 3. 构建增量请求
    ResponsesWsRequest::ResponseCreate(ResponseCreateWsRequest {
        previous_response_id: Some(last_response.response_id),
        input: incremental_items,  // 只发送增量部分
        ..payload
    })
}
```

---

## 5. 依赖与外部交互

### 5.1 直接依赖 crate

| Crate | 用途 | 版本约束 |
|-------|------|---------|
| `tokio` | 异步运行时 | `multi_thread` 测试运行时 |
| `tokio-tungstenite` | WebSocket 客户端/服务器 | 用于 `WebSocketTestServer` |
| `serde_json` | JSON 序列化/反序列化 | 请求/响应体处理 |
| `wiremock` | HTTP 模拟服务器 | SSE/HTTP 测试场景 |
| `tempfile` | 临时目录 | 测试隔离 |
| `tracing` / `tracing-test` | 日志和追踪 | 测试可观测性 |
| `opentelemetry_sdk` | 遥测 SDK | `InMemoryMetricExporter` 用于验证指标 |
| `pretty_assertions` | 测试断言美化 | 差异对比 |
| `futures` | 异步流处理 | `StreamExt` |

### 5.2 内部 crate 依赖

| Crate | 说明 |
|-------|------|
| `codex_core` | 被测系统主体 |
| `codex_api` | WebSocket 客户端实现 |
| `codex_protocol` | 协议类型定义 (`ResponseItem`, `EventMsg` 等) |
| `codex_otel` | 遥测和指标 (`SessionTelemetry`, `MetricsClient`) |
| `core_test_support` | 测试共享库 (通过 `tests/common/` 模块) |

### 5.3 外部服务交互

```
┌─────────────────────────────────────────────────────────────┐
│                    外部交互图                                │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌──────────────┐      WebSocket       ┌──────────────┐   │
│   │   测试用例    │ ◄──────────────────► │ 模拟服务器    │   │
│   │              │   ws://127.0.0.1:xxx  │ (tokio-      │   │
│   │              │                       │  tungstenite)│   │
│   └──────┬───────┘                       └──────────────┘   │
│          │                                                  │
│          │ 调用                                              │
│          ▼                                                  │
│   ┌──────────────┐                                          │
│   │  ModelClient │                                          │
│   │  (被测系统)   │                                          │
│   └──────┬───────┘                                          │
│          │                                                  │
│          │ 调用                                              │
│          ▼                                                  │
│   ┌──────────────┐                                          │
│   │ Responses-   │                                          │
│   │ Websocket-   │                                          │
│   │ Client       │                                          │
│   └──────────────┘                                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 5.4 测试隔离机制

1. **临时目录隔离**: 每个测试使用 `TempDir::new()` 创建独立配置目录
2. **随机端口**: `WebSocketTestServer` 绑定到 `127.0.0.1:0` 获取随机可用端口
3. **网络跳过**: `skip_if_no_network!()` 宏在沙箱环境中跳过测试
4. **资源清理**: `WebSocketTestServer::shutdown()` 确保连接关闭

---

## 6. 风险、边界与改进建议

### 6.1 当前风险点

#### 6.1.1 测试稳定性风险

| 风险 | 描述 | 缓解措施 |
|-----|------|---------|
| 网络依赖 | 测试需要真实网络栈 (`skip_if_no_network!`) | 在 CI 中确保网络可用，本地开发可跳过 |
| 时序敏感 | `tokio::time::sleep` 用于等待异步事件 | 使用 `wait_for_event` 替代固定延迟 |
| 端口冲突 | 虽然使用随机端口，但仍存在理论冲突可能 | 重试机制或端口范围限制 |

#### 6.1.2 测试覆盖盲区

```rust
// 当前未充分覆盖的场景:
1. TLS 证书验证失败场景
2. 代理服务器环境下的 WebSocket 连接
3. 极高的并发连接压力测试
4. 网络分区后的恢复行为
5. 自定义 CA 证书的 WebSocket TLS 握手
```

### 6.2 边界条件

#### 6.2.1 已测试的边界

- **空输入**: `prompt_with_input(vec![])` 场景
- **超长消息**: 通过大量文本测试消息分片
- **快速连续请求**: 验证连接复用和队列行为
- **连接超时**: `websocket_connect_timeout_ms` 配置测试

#### 6.2.2 边界处理代码

```rust
// core/src/client.rs: 连接超时处理
let websocket_connect_timeout = self.state.provider.websocket_connect_timeout();
let result = match tokio::time::timeout(
    websocket_connect_timeout,
    ApiWebSocketResponsesClient::new(api_provider, api_auth).connect(...)
).await {
    Ok(result) => result,
    Err(_) => Err(ApiError::Transport(TransportError::Timeout)),
};
```

### 6.3 改进建议

#### 6.3.1 测试架构改进

1. **参数化测试**: 使用 `rstest` 或类似框架减少重复代码
   ```rust
   // 建议: 使用参数化测试替代多个相似测试
   #[rstest]
   #[case(true, true)]   // v2 + incremental
   #[case(true, false)]  // v2 only
   #[case(false, true)]  // incremental only
   #[case(false, false)] // baseline
   async fn test_websocket_variants(#[case] v2: bool, #[case] incremental: bool) { ... }
   ```

2. **属性测试**: 使用 `proptest` 生成随机输入验证鲁棒性

3. **性能基准**: 添加 `criterion` 基准测试验证连接复用性能提升

#### 6.3.2 可观测性改进

```rust
// 建议: 添加更详细的测试事件日志
#[derive(Debug)]
enum TestEvent {
    WebSocketConnected { connection_id: u64 },
    RequestSent { request_id: String, size_bytes: usize },
    ResponseReceived { event_type: String },
    ConnectionReused { connection_id: u64 },
    FallbackToHttp { reason: String },
}
```

#### 6.3.3 文档与注释

1. **协议文档**: 添加 OpenAI Responses WebSocket 协议规范链接
2. **时序图**: 为复杂场景（如增量请求）添加 ASCII 时序图
3. **故障模式**: 记录每个测试验证的故障模式和恢复策略

### 6.4 技术债务追踪

| 项目 | 位置 | 优先级 |
|-----|------|-------|
| `TODO (pakrym): is this the right place for timeout?` | `responses_websocket.rs:165` | 中 |
| `WebSocket prewarm is treated as the first websocket connection attempt` | `client.rs:16` | 低 |
| `SSE fixtures` 支持有限 | `client.rs:1008` | 低 |

---

## 7. 附录

### 7.1 相关文档链接

- OpenAI Responses API 文档: https://platform.openai.com/docs/api-reference/responses
- WebSocket Protocol (RFC 6455): https://tools.ietf.org/html/rfc6455
- W3C Trace Context: https://www.w3.org/TR/trace-context/

### 7.2 测试运行命令

```bash
# 运行所有 WebSocket 测试
cargo test -p codex-core responses_websocket

# 运行特定测试
cargo test -p codex-core responses_websocket_streams_request

# 带日志输出运行
cargo test -p codex-core responses_websocket -- --nocapture

# 使用 nextest 运行
cargo nextest run -p codex-core responses_websocket
```

### 7.3 文件变更历史

| 日期 | 变更 | 作者 |
|-----|------|------|
| 2026-03-23 | 初始研究文档创建 | Kimi Code CLI |

---

*文档结束*
