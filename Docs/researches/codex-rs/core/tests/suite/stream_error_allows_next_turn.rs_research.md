# stream_error_allows_next_turn.rs 研究文档

## 场景与职责

`stream_error_allows_next_turn.rs` 是 Codex Core 的集成测试套件，专注于验证流式响应错误后的恢复能力。该测试确保当 SSE 流返回错误（如 HTTP 500）时，Codex 能够正确清理状态并允许后续对话轮次继续执行。

### 核心职责
1. **错误恢复验证**：验证流错误后系统能够正确恢复
2. **状态清理验证**：验证错误后运行任务被正确清理，不会阻塞后续提交
3. **会话连续性**：验证同一会话可以在错误后继续新的对话轮次

## 功能点目的

### 流错误后恢复 (`continue_after_stream_error`)
- **目的**：确保当 OpenAI API 返回错误时，Codex 不会进入死锁状态，后续用户输入仍能正常处理
- **验证点**：
  - 第一个请求返回 HTTP 500 错误
  - 系统发出 `Error` 事件
  - 系统发出 `TurnComplete` 事件释放会话
  - 第二个请求能够正常提交并成功完成

### 关键测试逻辑
```rust
// 1. 第一个请求返回 500 错误
codex.submit(Op::UserInput { text: "first message", ... }).await?;
wait_for_event(&codex, |ev| matches!(ev, EventMsg::Error(_))).await;
wait_for_event(&codex, |ev| matches!(ev, EventMsg::TurnComplete(_))).await;

// 2. 第二个请求应该成功
codex.submit(Op::UserInput { text: "follow up", ... }).await?;
wait_for_event(&codex, |ev| matches!(ev, EventMsg::TurnComplete(_))).await;
```

## 具体技术实现

### Mock 服务器配置

#### 错误响应配置
```rust
let fail = ResponseTemplate::new(500)
    .insert_header("content-type", "application/json")
    .set_body_string(
        serde_json::json!({
            "error": {"type": "bad_request", "message": "synthetic client error"}
        }).to_string(),
    );

Mock::given(method("POST"))
    .and(path("/v1/responses"))
    .and(body_string_contains("first message"))
    .respond_with(fail)
    .up_to_n_times(2)
    .mount(&server)
    .await;
```

#### 成功响应配置
```rust
let ok = ResponseTemplate::new(200)
    .insert_header("content-type", "text/event-stream")
    .set_body_raw(
        sse(vec![
            ev_response_created("resp_ok2"),
            ev_completed("resp_ok2"),
        ]),
        "text/event-stream",
    );

Mock::given(method("POST"))
    .and(path("/v1/responses"))
    .and(body_string_contains("follow up"))
    .respond_with(ok)
    .expect(1)
    .mount(&server)
    .await;
```

### 模型提供商配置
```rust
let provider = ModelProviderInfo {
    name: "mock-openai".into(),
    base_url: Some(format!("{}/v1", server.uri())),
    env_key: Some("PATH".into()), // 使用 PATH 环境变量作为占位
    env_key_instructions: None,
    experimental_bearer_token: None,
    wire_api: WireApi::Responses,
    query_params: None,
    http_headers: None,
    env_http_headers: None,
    request_max_retries: Some(1),
    stream_max_retries: Some(1),
    stream_idle_timeout_ms: Some(2_000),
    websocket_connect_timeout_ms: None,
    requires_openai_auth: false,
    supports_websockets: false,
};
```

### 关键设计决策
1. **禁用重试**：`request_max_retries: Some(1)` 确保错误请求只执行一次
2. **PATH 环境变量**：用作 `env_key` 的占位符，避免需要真实 API 密钥
3. **WireApi::Responses**：使用 Responses API 而非 Chat Completions API

## 关键代码路径与文件引用

### 被测代码路径
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/src/codex.rs` | Codex 核心逻辑，处理事件循环和状态管理 |
| `codex-rs/core/src/client.rs` | HTTP 客户端，处理 API 请求和错误 |
| `codex-rs/core/src/stream_processor.rs` | 流处理器，处理 SSE 事件 |

### 测试依赖路径
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/tests/common/responses.rs` | SSE 事件构造器 (`ev_completed`, `ev_response_created`) |
| `codex-rs/core/tests/common/test_codex.rs` | `TestCodex` 测试辅助结构 |
| `codex-rs/core/tests/common/lib.rs` | `wait_for_event` 和 `skip_if_no_network!` |

### 关键类型引用
```rust
// codex_core
pub struct ModelProviderInfo {
    pub name: String,
    pub base_url: Option<String>,
    pub env_key: Option<String>,
    pub wire_api: WireApi,
    pub request_max_retries: Option<u32>,
    pub stream_max_retries: Option<u32>,
    pub stream_idle_timeout_ms: Option<u64>,
    pub supports_websockets: bool,
    ...
}

pub enum WireApi {
    Responses,
    ChatCompletions,
}

// codex_protocol
pub enum Op {
    UserInput {
        items: Vec<UserInput>,
        final_output_json_schema: Option<Value>,
    },
    ...
}

pub enum EventMsg {
    Error(ErrorEvent),
    TurnComplete(TurnCompleteEvent),
    ...
}
```

## 依赖与外部交互

### 外部依赖
1. **wiremock**: HTTP Mock 服务器
2. **tokio**: 异步运行时 (`multi_thread` flavor)
3. **serde_json**: JSON 处理

### 关键特性
- `#[tokio::test(flavor = "multi_thread", worker_threads = 2)]`: 使用多线程运行时模拟真实环境

### 环境要求
- 网络访问（通过 `skip_if_no_network!` 宏在沙箱中跳过）

## 风险、边界与改进建议

### 已知风险
1. **竞态条件**：测试依赖事件顺序（Error -> TurnComplete），如果内部处理顺序改变可能导致测试失败
2. **超时风险**：`wait_for_event` 默认 1 秒超时，在慢速 CI 环境可能失败
3. **Mock 匹配依赖**：使用 `body_string_contains` 匹配请求体，如果序列化格式改变可能失败

### 边界情况
1. **重试逻辑**：测试配置 `request_max_retries: Some(1)`，验证重试后仍失败的情况
2. **并发提交**：测试顺序提交，未测试错误后立即并发提交的场景
3. **WebSocket 路径**：测试仅覆盖 SSE 路径，未覆盖 WebSocket 错误恢复

### 改进建议
1. **参数化测试**：添加参数化测试覆盖不同错误代码（502, 503, 504）
2. **并发测试**：添加测试验证错误后并发提交的处理
3. **WebSocket 覆盖**：添加 WebSocket 错误恢复测试
4. **状态验证**：添加内部状态验证，确保错误后没有残留任务
5. **日志验证**：验证错误事件包含预期的错误信息

### 潜在缺陷
1. **硬编码事件顺序**：测试假设 Error 在 TurnComplete 之前，但某些实现可能同时发出
2. **无错误内容验证**：未验证 Error 事件的具体错误消息
3. **无重试次数验证**：未验证重试逻辑确实执行了预期次数
