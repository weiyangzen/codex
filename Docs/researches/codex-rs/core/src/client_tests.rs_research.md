# client_tests.rs 研究文档

## 文件信息
- **路径**: `codex-rs/core/src/client_tests.rs`
- **大小**: ~3,837 bytes
- **所属模块**: `codex-core` (作为 `client.rs` 的测试模块)

---

## 一、场景与职责

`client_tests.rs` 是 `client.rs` 的单元测试文件，通过 `#[path = "client_tests.rs"]` 属性在 `client.rs` 的 `tests` 模块中引入。该测试文件负责验证：

1. **SubAgent Header 构建**: 验证 `build_subagent_headers` 方法正确设置 `x-openai-subagent` 头
2. **Memory 摘要空输入处理**: 验证 `summarize_memories` 对空输入的快速返回
3. **认证遥测上下文**: 验证 `AuthRequestTelemetryContext` 正确捕获认证状态和恢复信息

### 测试范围
```
┌─────────────────────────────────────────────────────────────┐
│                  client.rs 测试覆盖                          │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐   │
│  │            client_tests.rs                          │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │   │
│  │  │ SubAgent    │  │ Memory      │  │ Auth        │ │   │
│  │  │ Header      │  │ Summarize   │  │ Telemetry   │ │   │
│  │  │ (1 test)    │  │ (1 test)    │  │ (1 test)    │ │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘ │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## 二、功能点目的

### 2.1 SubAgent Header 测试

**目的**: 验证 `ModelClient::build_subagent_headers` 正确识别 SubAgent 来源并设置相应 Header

**测试场景**:
- `SessionSource::SubAgent(SubAgentSource::Other(label))` 情况
- 验证 `x-openai-subagent` 头值为传入的 label

### 2.2 Memory 摘要空输入测试

**目的**: 验证 `ModelClient::summarize_memories` 对空输入的快速路径返回

**测试场景**:
- 传入空 `Vec<ApiRawMemory>`
- 验证返回空 `Vec` 而不进行实际 API 调用

### 2.3 认证遥测上下文测试

**目的**: 验证 `AuthRequestTelemetryContext` 正确捕获和暴露认证信息

**验证内容**:
| 字段 | 验证点 |
|------|--------|
| `auth_mode` | 正确映射为字符串（"Chatgpt"/"ApiKey"） |
| `auth_header_attached` | 正确反映是否附加认证头 |
| `auth_header_name` | 正确提取头名称 |
| `retry_after_unauthorized` | 正确标记是否为 401 后重试 |
| `recovery_mode` | 正确捕获恢复模式（"managed"/"external"） |
| `recovery_phase` | 正确捕获恢复阶段（"refresh_token"等） |

---

## 三、具体技术实现

### 3.1 测试辅助函数

#### 创建测试用 ModelClient
```rust
fn test_model_client(session_source: SessionSource) -> ModelClient {
    // 使用 OSS 提供商避免需要真实 API Key
    let provider = crate::model_provider_info::create_oss_provider_with_base_url(
        "https://example.com/v1",
        crate::model_provider_info::WireApi::Responses,
    );
    
    ModelClient::new(
        None,                    // auth_manager: 无认证
        ThreadId::new(),         // 随机会话 ID
        provider,
        session_source,          // 传入的会话来源
        None,                    // model_verbosity
        false,                   // enable_request_compression
        false,                   // include_timing_metrics
        None,                    // beta_features_header
    )
}
```

#### 创建测试用 ModelInfo
```rust
fn test_model_info() -> ModelInfo {
    serde_json::from_value(json!({
        "slug": "gpt-test",
        "display_name": "gpt-test",
        "description": "desc",
        "default_reasoning_level": "medium",
        "supported_reasoning_levels": [
            {"effort": "medium", "description": "medium"}
        ],
        "shell_type": "shell_command",
        "visibility": "list",
        "supported_in_api": true,
        "priority": 1,
        "upgrade": null,
        "base_instructions": "base instructions",
        "model_messages": null,
        "supports_reasoning_summaries": false,
        "support_verbosity": false,
        "default_verbosity": null,
        "apply_patch_tool_type": null,
        "truncation_policy": {"mode": "bytes", "limit": 10000},
        "supports_parallel_tool_calls": false,
        "supports_image_detail_original": false,
        "context_window": 272000,
        "auto_compact_token_limit": null,
        "experimental_supported_tools": []
    }))
    .expect("deserialize test model info")
}
```

#### 创建测试用 SessionTelemetry
```rust
fn test_session_telemetry() -> SessionTelemetry {
    SessionTelemetry::new(
        ThreadId::new(),
        "gpt-test",              // model
        "gpt-test",              // model_provider
        None,                    // model_service_tier
        None,                    // model_reasoning_level
        None,                    // model_reasoning_summary
        "test-originator".to_string(),
        false,                   // is_baseline
        "test-terminal".to_string(),
        SessionSource::Cli,      // source
    )
}
```

### 3.2 测试用例详解

#### SubAgent Header 测试
```rust
#[test]
fn build_subagent_headers_sets_other_subagent_label() {
    // 使用自定义 label 创建 SubAgent 来源的客户端
    let client = test_model_client(SessionSource::SubAgent(SubAgentSource::Other(
        "memory_consolidation".to_string(),
    )));
    
    // 调用被测方法
    let headers = client.build_subagent_headers();
    
    // 验证 Header 值
    let value = headers
        .get("x-openai-subagent")
        .and_then(|value| value.to_str().ok());
    assert_eq!(value, Some("memory_consolidation"));
}
```

**验证逻辑**:
- `SubAgentSource::Other(label)` → `x-openai-subagent: label`
- 其他 SubAgent 来源（Review, Compact, MemoryConsolidation, ThreadSpawn）有固定映射

#### Memory 摘要空输入测试
```rust
#[tokio::test]
async fn summarize_memories_returns_empty_for_empty_input() {
    let client = test_model_client(SessionSource::Cli);
    let model_info = test_model_info();
    let session_telemetry = test_session_telemetry();

    // 传入空 Vec
    let output = client
        .summarize_memories(Vec::new(), &model_info, None, &session_telemetry)
        .await
        .expect("empty summarize request should succeed");
    
    // 验证返回空 Vec
    assert_eq!(output.len(), 0);
}
```

**代码路径**:
```rust
// client.rs 中的实现
pub async fn summarize_memories(&self, raw_memories: Vec<ApiRawMemory>, ...) 
    -> Result<Vec<ApiMemorySummarizeOutput>> 
{
    if raw_memories.is_empty() {
        return Ok(Vec::new());  // 快速返回路径
    }
    // ... 实际 API 调用
}
```

#### 认证遥测上下文测试
```rust
#[test]
fn auth_request_telemetry_context_tracks_attached_auth_and_retry_phase() {
    // 创建带有恢复状态的认证上下文
    let auth_context = AuthRequestTelemetryContext::new(
        Some(crate::auth::AuthMode::Chatgpt),
        &crate::api_bridge::CoreAuthProvider::for_test(
            Some("access-token"), 
            Some("workspace-123")
        ),
        PendingUnauthorizedRetry::from_recovery(UnauthorizedRecoveryExecution {
            mode: "managed",
            phase: "refresh_token",
        }),
    );

    // 验证所有字段
    assert_eq!(auth_context.auth_mode, Some("Chatgpt"));
    assert!(auth_context.auth_header_attached);
    assert_eq!(auth_context.auth_header_name, Some("authorization"));
    assert!(auth_context.retry_after_unauthorized);
    assert_eq!(auth_context.recovery_mode, Some("managed"));
    assert_eq!(auth_context.recovery_phase, Some("refresh_token"));
}
```

---

## 四、关键代码路径与文件引用

### 4.1 被测代码路径

| 被测代码 | 测试覆盖 |
|----------|----------|
| `client.rs` 中的 `build_subagent_headers` | `build_subagent_headers_sets_other_subagent_label` |
| `client.rs` 中的 `summarize_memories` | `summarize_memories_returns_empty_for_empty_input` |
| `client.rs` 中的 `AuthRequestTelemetryContext::new` | `auth_request_telemetry_context_tracks_attached_auth_and_retry_phase` |

### 4.2 依赖项

```rust
// 被测模块的私有项
use super::AuthRequestTelemetryContext;
use super::ModelClient;
use super::PendingUnauthorizedRetry;
use super::UnauthorizedRecoveryExecution;

// 协议类型
use codex_otel::SessionTelemetry;
use codex_protocol::ThreadId;
use codex_protocol::openai_models::ModelInfo;
use codex_protocol::protocol::SessionSource;
use codex_protocol::protocol::SubAgentSource;

// 测试工具
use pretty_assertions::assert_eq;
use serde_json::json;
```

### 4.3 辅助方法使用

测试使用了 `api_bridge` 模块的测试辅助方法：
```rust
// CoreAuthProvider::for_test 是测试专用构造函数
CoreAuthProvider::for_test(
    Some("access-token"),    // token
    Some("workspace-123")    // account_id
)
```

---

## 五、依赖与外部交互

### 5.1 与 model_provider_info 的交互

```rust
let provider = crate::model_provider_info::create_oss_provider_with_base_url(
    "https://example.com/v1",
    crate::model_provider_info::WireApi::Responses,
);
```

使用 OSS 提供商避免测试需要真实 OpenAI 认证。

### 5.2 与 codex_protocol 的交互

```rust
use codex_protocol::protocol::{SessionSource, SubAgentSource};
```

用于构造不同来源的会话上下文。

### 5.3 与 codex_otel 的交互

```rust
use codex_otel::SessionTelemetry;
```

用于构造遥测上下文。

---

## 六、风险、边界与改进建议

### 6.1 当前测试覆盖分析

| 功能模块 | 覆盖状态 | 说明 |
|----------|----------|------|
| `ModelClient::new` | ⚠️ 间接覆盖 | 通过辅助函数使用，无直接测试 |
| `ModelClient::new_session` | ❌ 未覆盖 | 核心方法无测试 |
| `ModelClient::compact_conversation_history` | ❌ 未覆盖 | 无测试 |
| `ModelClient::responses_websocket_enabled` | ❌ 未覆盖 | 无测试 |
| `ModelClient::current_client_setup` | ❌ 未覆盖 | 无测试 |
| `ModelClient::connect_websocket` | ❌ 未覆盖 | 无测试 |
| `ModelClient::force_http_fallback` | ❌ 未覆盖 | 无测试 |
| `ModelClientSession::stream` | ❌ 未覆盖 | 核心流式方法无测试 |
| `ModelClientSession::prewarm_websocket` | ❌ 未覆盖 | 无测试 |
| `ModelClientSession::stream_responses_api` | ❌ 未覆盖 | 无测试 |
| `ModelClientSession::stream_responses_websocket` | ❌ 未覆盖 | 无测试 |
| 增量请求逻辑 | ❌ 未覆盖 | `get_incremental_items` 等无测试 |
| 认证恢复流程 | ⚠️ 部分覆盖 | 仅测试了遥测上下文构造 |
| `handle_unauthorized` | ❌ 未覆盖 | 核心恢复逻辑无测试 |

### 6.2 测试局限性

当前测试存在以下局限：

1. **无网络交互测试**: 所有测试都是单元测试，不涉及实际 HTTP/WebSocket 调用
2. **无认证恢复流程测试**: 仅测试了遥测上下文，未测试完整恢复流程
3. **无流式响应测试**: `ResponseStream` 的创建和消费未测试
4. **无错误处理测试**: 各种错误场景（超时、网络错误、API 错误）未覆盖

### 6.3 改进建议

#### 1. 添加 WebSocket 预热测试
```rust
#[tokio::test]
async fn prewarm_websocket_establishes_connection() {
    // 使用 mock WebSocket 服务器
    let mock_server = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = mock_server.local_addr().unwrap();
    
    let client = create_test_client_with_ws_url(format!("ws://{}/ws", addr));
    let mut session = client.new_session();
    
    // 预热应成功建立连接
    session.prewarm_websocket(/* ... */).await.unwrap();
    
    // 验证连接已缓存
    assert!(session.websocket_session.connection.is_some());
}
```

#### 2. 添加增量请求测试
```rust
#[test]
fn get_incremental_items_returns_none_when_properties_differ() {
    let mut session = create_test_session();
    
    // 设置上次请求
    session.websocket_session.last_request = Some(ResponsesApiRequest {
        model: "gpt-4".to_string(),
        // ...
    });
    
    // 当前请求使用不同模型
    let current_request = ResponsesApiRequest {
        model: "gpt-5".to_string(),  // 不同模型
        // ...
    };
    
    // 应返回 None（不能增量）
    let incremental = session.get_incremental_items(&current_request, None, false);
    assert!(incremental.is_none());
}

#[test]
fn get_incremental_items_returns_delta_when_input_extended() {
    let mut session = create_test_session();
    
    // 设置上次请求（输入: [A, B]）
    session.websocket_session.last_request = Some(create_request_with_input(vec![item_a, item_b]));
    
    // 当前请求（输入: [A, B, C]）
    let current_request = create_request_with_input(vec![item_a, item_b, item_c]);
    
    // 应返回增量 [C]
    let incremental = session.get_incremental_items(&current_request, None, false);
    assert_eq!(incremental, Some(vec![item_c]));
}
```

#### 3. 添加认证恢复流程测试
```rust
#[tokio::test]
async fn handle_unauthorized_triggers_token_refresh() {
    // Mock AuthManager 和 token 刷新
    let mut mock_auth_manager = MockAuthManager::new();
    mock_auth_manager
        .expect_unauthorized_recovery()
        .return_once(|| {
            let mut recovery = MockUnauthorizedRecovery::new();
            recovery.expect_has_next().return_const(true);
            recovery.expect_next().return_once(|| {
                Ok(UnauthorizedRecoveryStepResult {
                    auth_state_changed: Some(true),
                })
            });
            recovery
        });
    
    // 构造 401 错误
    let transport_error = TransportError::Http {
        status: StatusCode::UNAUTHORIZED,
        // ...
    };
    
    // 应触发恢复流程
    let result = handle_unauthorized(
        transport_error,
        &mut Some(mock_auth_manager.unauthorized_recovery()),
        &test_session_telemetry(),
    ).await;
    
    assert!(result.is_ok());
}
```

#### 4. 添加流式响应测试
```rust
#[tokio::test]
async fn map_response_stream_forwards_events() {
    // 创建模拟 API 流
    let (api_tx, api_rx) = tokio::sync::mpsc::channel(10);
    let api_stream = tokio_stream::wrappers::ReceiverStream::new(api_rx);
    
    // 包装为 ResponseStream
    let (mut response_stream, _last_response_rx) = 
        map_response_stream(api_stream, test_session_telemetry());
    
    // 发送事件
    api_tx.send(Ok(ResponseEvent::OutputItemDone(item.clone()))).await.unwrap();
    
    // 验证事件被转发
    let event = response_stream.next().await.unwrap().unwrap();
    assert!(matches!(event, ResponseEvent::OutputItemDone(_)));
}
```

#### 5. 添加 SubAgent Header 全覆盖
```rust
#[test]
fn build_subagent_headers_maps_all_sources() {
    let test_cases = vec![
        (SubAgentSource::Review, "review"),
        (SubAgentSource::Compact, "compact"),
        (SubAgentSource::MemoryConsolidation, "memory_consolidation"),
        (SubAgentSource::ThreadSpawn { .. }, "collab_spawn"),
        (SubAgentSource::Other("custom".to_string()), "custom"),
    ];
    
    for (source, expected) in test_cases {
        let client = test_model_client(SessionSource::SubAgent(source));
        let headers = client.build_subagent_headers();
        let value = headers.get("x-openai-subagent").and_then(|v| v.to_str().ok());
        assert_eq!(value, Some(expected));
    }
}
```

### 6.4 测试基础设施建议

#### 1. Mock 服务器
```rust
// 使用 wiremock 或类似库模拟 API 服务器
use wiremock::{MockServer, Mock, ResponseTemplate};

async fn setup_mock_api_server() -> MockServer {
    let server = MockServer::start().await;
    
    Mock::given(method("POST"))
        .and(path("/responses"))
        .respond_with(ResponseTemplate::new(200)
            .set_body_json(json!({ /* SSE 事件 */ })))
        .mount(&server)
        .await;
    
    server
}
```

#### 2. 测试配置
```rust
// 使用测试专用的配置，避免依赖环境变量
struct TestConfig {
    provider: ModelProviderInfo,
    auth_manager: Option<Arc<AuthManager>>,
}

impl TestConfig {
    fn oss_provider() -> Self {
        Self {
            provider: create_oss_provider_with_base_url(
                "http://localhost:9999/v1",
                WireApi::Responses,
            ),
            auth_manager: None,
        }
    }
}
```

#### 3. 快照测试
对于复杂的 JSON 序列化，考虑使用 `insta` 进行快照测试：
```rust
#[test]
fn responses_request_serialization_snapshot() {
    let request = create_test_request();
    let json = serde_json::to_value(&request).unwrap();
    insta::assert_json_snapshot!(json);
}
```
