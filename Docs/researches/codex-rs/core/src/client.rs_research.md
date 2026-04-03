# client.rs 研究文档

## 文件信息
- **路径**: `codex-rs/core/src/client.rs`
- **大小**: ~70,704 bytes
- **所属模块**: `codex-core`

---

## 一、场景与职责

`client.rs` 是 Codex 核心库中与模型提供商 API 通信的核心模块。它提供了会话级别（Session-scoped）和轮次级别（Turn-scoped）的 API 调用抽象，负责：

1. **模型 API 客户端管理**: 封装与 OpenAI Responses API 的 HTTP 和 WebSocket 通信
2. **会话状态维护**: 管理认证、会话 ID、提供商选择、传输层回退状态
3. **流式响应处理**: 支持 SSE（Server-Sent Events）和 WebSocket 两种流式传输
4. **增量请求优化**: 在 WebSocket 连接上实现增量请求，减少重复数据传输
5. **认证恢复机制**: 处理 401 未授权错误，支持 Token 刷新和重试
6. **遥测与监控**: 集成 OpenTelemetry 进行请求追踪和性能监控

### 架构定位
```
┌─────────────────────────────────────────────────────────────┐
│                    Codex Session                            │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐      ┌─────────────────────────────┐  │
│  │  ModelClient    │─────▶│  ModelClientSession (Turn)  │  │
│  │  (Session级别)   │      │  (Turn级别，每次对话新建)    │  │
│  └─────────────────┘      └─────────────────────────────┘  │
│           │                            │                    │
│           ▼                            ▼                    │
│  ┌─────────────────┐      ┌─────────────────────────────┐  │
│  │ AuthManager     │      │ WebSocket Session Cache     │  │
│  │ Provider Info   │      │ Turn State (Sticky Routing) │  │
│  └─────────────────┘      └─────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 二、功能点目的

### 2.1 ModelClient - 会话级客户端

**目的**: 维护整个 Codex 会话期间的稳定配置和状态

**核心功能**:
| 功能 | 说明 |
|------|------|
| `new()` | 创建新的会话客户端，初始化所有会话级状态 |
| `new_session()` | 为每个对话轮次创建新的 `ModelClientSession` |
| `responses_websocket_enabled()` | 检查 WebSocket 传输是否启用 |
| `compact_conversation_history()` | 使用 Compact 端点压缩对话历史 |
| `summarize_memories()` | 调用 `/memories/trace_summarize` 端点生成记忆摘要 |

### 2.2 ModelClientSession - 轮次级会话

**目的**: 管理单次对话轮次内的 API 调用，维护 WebSocket 连接和轮次状态

**核心功能**:
| 功能 | 说明 |
|------|------|
| `stream()` | 主入口：流式调用 Responses API，自动选择 HTTP 或 WebSocket |
| `prewarm_websocket()` | WebSocket 预热，提前建立连接以优化首次请求延迟 |
| `preconnect_websocket()` | 仅建立 WebSocket 连接，不发送请求体 |
| `stream_responses_api()` | HTTP SSE 流式调用 |
| `stream_responses_websocket()` | WebSocket 流式调用 |

### 2.3 WebSocket 预热与连接管理

**预热机制**:
- 在首次真实请求前发送 `generate=false` 的 `response.create` 请求
- 等待完成后再发送真实请求，可复用同一连接和 `previous_response_id`
- 被设计为最佳努力（best-effort），失败时由正常重试逻辑处理

**连接复用**:
```rust
struct WebsocketSession {
    connection: Option<ApiWebSocketConnection>,  // 缓存的连接
    last_request: Option<ResponsesApiRequest>,   // 上次请求，用于增量计算
    last_response_rx: Option<oneshot::Receiver<LastResponse>>, // 响应接收器
    connection_reused: StdMutex<bool>,           // 标记是否复用连接
}
```

### 2.4 增量请求优化

**目的**: 在多轮对话中只发送新增内容，减少网络传输

**实现逻辑**:
1. 缓存上次请求的输入项
2. 比较当前请求与上次请求的非输入字段是否相同
3. 如果相同且输入是上次输入的扩展，则只发送增量部分
4. 使用 `previous_response_id` 让服务端重建完整上下文

```rust
fn get_incremental_items(&self, request, last_response, allow_empty_delta) -> Option<Vec<ResponseItem>>
```

### 2.5 认证恢复机制

**UnauthorizedRecovery 状态机**:
```
┌─────────────┐    ┌───────────────┐    ┌─────────────┐
│   Reload    │───▶│ Refresh Token │───▶│    Done     │
│ (重载auth)   │    │  (OAuth刷新)   │    │ (恢复完成)   │
└─────────────┘    └───────────────┘    └─────────────┘
```

**处理流程**:
1. 遇到 401 错误时启动恢复流程
2. 首先尝试从磁盘重新加载 auth 数据（检查账号是否变更）
3. 然后使用 refresh_token 调用 OAuth 刷新端点
4. 刷新成功后重试原请求
5. 支持 ChatGPT 认证模式，API Key 模式直接报错

---

## 三、具体技术实现

### 3.1 关键数据结构

#### ModelClientState - 会话级状态
```rust
#[derive(Debug)]
struct ModelClientState {
    auth_manager: Option<Arc<AuthManager>>,     // 认证管理器
    conversation_id: ThreadId,                   // 会话唯一ID
    provider: ModelProviderInfo,                 // 提供商配置
    auth_env_telemetry: AuthEnvTelemetry,        // 认证环境遥测
    session_source: SessionSource,               // 会话来源(Cli/SubAgent等)
    model_verbosity: Option<VerbosityConfig>,    // 模型输出详细程度
    enable_request_compression: bool,            // 是否启用请求压缩
    include_timing_metrics: bool,                // 是否包含时序指标
    beta_features_header: Option<String>,        // Beta功能Header
    disable_websockets: AtomicBool,              // WebSocket禁用标志
    cached_websocket_session: StdMutex<WebsocketSession>, // 缓存的WS会话
}
```

#### ModelClientSession - 轮次级状态
```rust
pub struct ModelClientSession {
    client: ModelClient,                         // 关联的会话客户端
    websocket_session: WebsocketSession,         // WebSocket会话状态
    turn_state: Arc<OnceLock<String>>,           // 轮次状态令牌(粘滞路由)
}
```

#### 认证请求遥测上下文
```rust
#[derive(Clone, Copy, Debug, Default)]
struct AuthRequestTelemetryContext {
    auth_mode: Option<&'static str>,             // "ApiKey" 或 "Chatgpt"
    auth_header_attached: bool,                  // 是否附加认证头
    auth_header_name: Option<&'static str>,      // 认证头名称
    retry_after_unauthorized: bool,              // 是否在401后重试
    recovery_mode: Option<&'static str>,         // 恢复模式
    recovery_phase: Option<&'static str>,        // 恢复阶段
}
```

### 3.2 关键流程

#### 3.2.1 流式请求主流程 (`stream` 方法)

```rust
pub async fn stream(&mut self, prompt, model_info, session_telemetry, ...)
    -> Result<ResponseStream>
{
    match wire_api {
        WireApi::Responses => {
            // 1. 检查 WebSocket 是否启用
            if self.client.responses_websocket_enabled() {
                // 2. 尝试 WebSocket 流式调用
                match self.stream_responses_websocket(...).await? {
                    WebsocketStreamOutcome::Stream(stream) => return Ok(stream),
                    WebsocketStreamOutcome::FallbackToHttp => {
                        // 3. WebSocket 失败，回退到 HTTP
                        self.try_switch_fallback_transport(...);
                    }
                }
            }
            // 4. HTTP SSE 流式调用
            self.stream_responses_api(...).await
        }
    }
}
```

#### 3.2.2 WebSocket 连接建立流程

```rust
async fn connect_websocket(&self, session_telemetry, api_provider, api_auth, ...)
    -> Result<ApiWebSocketConnection, ApiError>
{
    // 1. 构建 WebSocket 握手头
    let headers = self.build_websocket_headers(turn_state, turn_metadata_header);
    
    // 2. 构建遥测对象
    let websocket_telemetry = ModelClientSession::build_websocket_telemetry(...);
    
    // 3. 带超时的连接尝试
    let result = tokio::time::timeout(
        websocket_connect_timeout,
        ApiWebSocketResponsesClient::new(api_provider, api_auth)
            .connect(headers, default_headers(), turn_state, Some(websocket_telemetry))
    ).await;
    
    // 4. 记录遥测数据
    session_telemetry.record_websocket_connect(...);
    
    result
}
```

#### 3.2.3 增量请求准备流程

```rust
fn prepare_websocket_request(&mut self, payload, request) -> ResponsesWsRequest {
    // 1. 获取上次响应
    let Some(last_response) = self.get_last_response() else {
        return ResponsesWsRequest::ResponseCreate(payload);
    };
    
    // 2. 计算增量项
    let Some(incremental_items) = self.get_incremental_items(
        request, Some(&last_response), /*allow_empty_delta*/ true
    ) else {
        return ResponsesWsRequest::ResponseCreate(payload);
    };
    
    // 3. 构建增量请求
    ResponsesWsRequest::ResponseCreate(ResponseCreateWsRequest {
        previous_response_id: Some(last_response.response_id),
        input: incremental_items,
        ..payload
    })
}
```

#### 3.2.4 认证恢复流程

```rust
async fn handle_unauthorized(transport, auth_recovery, session_telemetry) 
    -> Result<UnauthorizedRecoveryExecution>
{
    let debug = extract_response_debug_context(&transport);
    
    if let Some(recovery) = auth_recovery && recovery.has_next() {
        let mode = recovery.mode_name();
        let phase = recovery.step_name();
        
        match recovery.next().await {
            Ok(step_result) => {
                // 记录成功恢复遥测
                session_telemetry.record_auth_recovery("recovery_succeeded", ...);
                Ok(UnauthorizedRecoveryExecution { mode, phase })
            }
            Err(RefreshTokenError::Permanent(failed)) => {
                session_telemetry.record_auth_recovery("recovery_failed_permanent", ...);
                Err(CodexErr::RefreshTokenFailed(failed))
            }
            Err(RefreshTokenError::Transient(other)) => {
                session_telemetry.record_auth_recovery("recovery_failed_transient", ...);
                Err(CodexErr::Io(other))
            }
        }
    } else {
        // 无恢复可用，直接返回错误
        Err(map_api_error(ApiError::Transport(transport)))
    }
}
```

### 3.3 协议与常量

#### HTTP Header 常量
```rust
pub const OPENAI_BETA_HEADER: &str = "OpenAI-Beta";
pub const X_CODEX_TURN_STATE_HEADER: &str = "x-codex-turn-state";
pub const X_CODEX_TURN_METADATA_HEADER: &str = "x-codex-turn-metadata";
pub const X_RESPONSESAPI_INCLUDE_TIMING_METRICS_HEADER: &str = "x-responsesapi-include-timing-metrics";
const RESPONSES_WEBSOCKETS_V2_BETA_HEADER_VALUE: &str = "responses_websockets=2026-02-06";
```

#### API 端点
```rust
const RESPONSES_ENDPOINT: &str = "/responses";
const RESPONSES_COMPACT_ENDPOINT: &str = "/responses/compact";
const MEMORIES_SUMMARIZE_ENDPOINT: &str = "/memories/trace_summarize";
```

### 3.4 遥测集成

`ApiTelemetry` 结构体实现了三个遥测 trait:
- `RequestTelemetry`: HTTP 请求级别遥测
- `SseTelemetry`: SSE 事件轮询遥测
- `WebsocketTelemetry`: WebSocket 请求/事件遥测

遥测数据包括:
- 请求尝试次数、状态码、错误信息
- 认证头附加情况、认证模式
- 恢复模式/阶段（401恢复流程中）
- 连接复用标记
- Request ID、CF-Ray 等追踪标识

---

## 四、关键代码路径与文件引用

### 4.1 内部依赖

| 依赖文件 | 用途 |
|----------|------|
| `client_common.rs` | `Prompt`、`ResponseStream`、`ToolSpec` 等共享类型 |
| `auth.rs` | `AuthManager`、`CodexAuth`、`UnauthorizedRecovery` |
| `api_bridge.rs` | `map_api_error`、`CoreAuthProvider` |
| `model_provider_info.rs` | `ModelProviderInfo`、`WireApi` |
| `response_debug_context.rs` | 错误调试信息提取 |
| `auth_env_telemetry.rs` | 认证环境遥测收集 |
| `default_client.rs` | `build_reqwest_client` |
| `tools/spec.rs` | `create_tools_json_for_responses_api` |

### 4.2 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_api` | OpenAI API 客户端（HTTP 和 WebSocket） |
| `codex_protocol` | 协议类型（`ResponseItem`、`ModelInfo` 等） |
| `codex_otel` | OpenTelemetry 遥测 |
| `tokio` | 异步运行时（`mpsc`、`oneshot`、`time`） |
| `tokio_tungstenite` | WebSocket 实现 |
| `tracing` | 结构化日志 |
| `futures` | 流处理 |

### 4.3 关键代码路径

**初始化路径**:
```
ModelClient::new() 
  → 构建 ModelClientState
  → collect_auth_env_telemetry()
  → 初始化 cached_websocket_session
```

**流式请求路径**:
```
ModelClientSession::stream()
  → responses_websocket_enabled() 检查
  → stream_responses_websocket() 或 stream_responses_api()
    → build_responses_request() 构建请求体
    → build_responses_options() 构建选项
    → 发送请求并获取流
  → map_response_stream() 包装响应流
```

**WebSocket 连接路径**:
```
websocket_connection()
  → 检查现有连接是否可用
  → connect_websocket() 建立新连接
    → build_websocket_headers() 构建头
    → ApiWebSocketResponsesClient::connect()
  → 设置 connection_reused 标记
```

**认证恢复路径**:
```
stream_responses_api() 或 stream_responses_websocket()
  → 遇到 401 错误
  → handle_unauthorized()
    → UnauthorizedRecovery::next()
      → Reload 步骤 / RefreshToken 步骤
    → 记录遥测
    → 重试或返回错误
```

---

## 五、依赖与外部交互

### 5.1 与 Auth 模块的交互

```rust
// 认证恢复流程
let mut auth_recovery = auth_manager
    .as_ref()
    .map(super::auth::AuthManager::unauthorized_recovery);

// 在 401 错误时
pending_retry = PendingUnauthorizedRetry::from_recovery(
    handle_unauthorized(unauthorized_transport, &mut auth_recovery, session_telemetry).await?
);
```

### 5.2 与 API 模块的交互

```rust
// HTTP 客户端
let client = ApiResponsesClient::new(transport, api_provider, api_auth)
    .with_telemetry(Some(request_telemetry), Some(sse_telemetry));
let stream_result = client.stream_request(request, options).await;

// WebSocket 客户端
let connection = ApiWebSocketResponsesClient::new(api_provider, api_auth)
    .connect(headers, default_headers(), turn_state, Some(websocket_telemetry))
    .await?;
```

### 5.3 与遥测系统的交互

```rust
// 记录 WebSocket 连接遥测
session_telemetry.record_websocket_connect(
    start.elapsed(),
    status,
    error_message.as_deref(),
    auth_context.auth_header_attached,
    ...
);

// 反馈标签
emit_feedback_request_tags_with_auth_env(&FeedbackRequestTags { ... }, &self.state.auth_env_telemetry);
```

### 5.4 与配置系统的交互

通过 `ModelProviderInfo` 获取提供商配置:
- `supports_websockets`: 是否支持 WebSocket
- `websocket_connect_timeout()`: WebSocket 连接超时
- `stream_idle_timeout()`: 流空闲超时
- `to_api_provider()`: 转换为 API 层提供商配置

---

## 六、风险、边界与改进建议

### 6.1 潜在风险

#### 1. WebSocket 连接状态竞争
**风险**: 多线程环境下 `cached_websocket_session` 的 `StdMutex` 可能导致阻塞
```rust
cached_websocket_session: StdMutex<WebsocketSession>,  // 使用 StdMutex
```
**缓解**: 锁持有时间较短，且主要在异步边界使用

#### 2. 增量请求正确性
**风险**: 增量请求依赖客户端状态与服务端状态的一致性，如果服务端状态丢失可能导致上下文错误
```rust
fn get_incremental_items(...) -> Option<Vec<ResponseItem>> {
    // 如果 previous_response_id 在服务端过期，增量请求会失败
}
```

#### 3. 认证恢复无限循环
**风险**: 虽然代码中有 `has_next()` 检查，但复杂的恢复逻辑可能导致意外行为
**缓解**: 使用 `PendingUnauthorizedRetry` 跟踪重试状态

#### 4. Turn State 生命周期
**风险**: `turn_state` 是 `OnceLock<String>`，一旦设置后不能修改，跨轮次复用会导致路由错误
```rust
/// Create a fresh `ModelClientSession` for each Codex turn.
/// Reusing it across turns would replay the previous turn's sticky-routing token...
```

### 6.2 边界条件

| 边界条件 | 处理策略 |
|----------|----------|
| WebSocket 连接超时 | 使用 `websocket_connect_timeout` 配置，超时后触发回退 |
| 空输入 | `compact_conversation_history` 和 `summarize_memories` 直接返回空 Vec |
| 不支持 verbosity 的模型 | 记录警告，忽略 verbosity 设置 |
| 不支持 reasoning 的模型 | 返回 `None`，不设置 reasoning 字段 |
| 401 恢复耗尽 | 返回 `RefreshTokenFailedError`，携带具体失败原因 |

### 6.3 改进建议

#### 1. 连接池优化
当前每个 `ModelClientSession` 维护自己的 WebSocket 连接。考虑：
- 实现连接池复用跨轮次（需解决 turn_state 隔离问题）
- 或者明确文档化连接生命周期

#### 2. 增量请求增强
```rust
// 当前：仅比较非输入字段
// 建议：增加版本号或哈希校验，确保服务端状态一致
fn get_incremental_items(&self, request, last_response, expected_version) -> Option<...>
```

#### 3. 错误分类细化
当前的 `map_api_error` 已经比较完善，但可以考虑：
- 区分可重试的 WebSocket 错误和致命错误
- 为不同提供商的错误添加特定处理

#### 4. 遥测增强
- 添加增量请求命中率指标
- 记录 WebSocket 连接复用率
- 追踪认证恢复成功率按阶段细分

#### 5. 代码结构优化
`client.rs` 约 1800 行，功能密集。考虑：
- 将 `ApiTelemetry` 实现提取到单独文件
- 将 WebSocket 相关逻辑提取到 `client/websocket.rs`
- 将 HTTP 流式逻辑提取到 `client/http.rs`

### 6.4 测试覆盖

现有测试文件:
- `client_tests.rs`: 主要测试 `ModelClient` 的辅助方法
- `client_common_tests.rs`: 测试 `Prompt` 和工具序列化

建议增加:
- WebSocket 连接失败回退的集成测试
- 增量请求正确性的单元测试
- 认证恢复流程的 mock 测试
