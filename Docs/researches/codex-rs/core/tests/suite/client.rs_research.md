# 研究文档：codex-rs/core/tests/suite/client.rs

## 1. 场景与职责

### 1.1 文件定位

`client.rs` 是 Codex 核心库（`codex-core`）的集成测试套件中的关键测试文件，位于 `codex-rs/core/tests/suite/client.rs`。它专注于测试 **ModelClient** 与 OpenAI Responses API 的交互行为，验证客户端请求构造、认证、会话恢复、消息历史管理等核心功能。

### 1.2 核心职责

该测试文件承担以下验证职责：

1. **会话恢复（Session Resume）**：验证从 rollout 文件恢复会话时，历史消息的正确重放和排序
2. **认证流程（Authentication）**：测试 API Key 认证、ChatGPT OAuth 认证及其优先级处理
3. **请求构造（Request Construction）**：验证发送给模型 API 的请求体结构，包括消息角色、指令、环境上下文等
4. **消息历史管理（History Management）**：验证多轮对话中的消息去重和正确排序
5. **模型配置传递（Model Configuration）**：测试 reasoning effort、verbosity、reasoning summary 等参数的传递
6. **错误处理（Error Handling）**：验证速率限制、上下文窗口超限等错误场景的处理

### 1.3 测试架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        client.rs 测试架构                         │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐  │
│  │  TestCodex  │───▶│  MockServer │───▶│  Wiremock matchers  │  │
│  │  (builder)  │    │  (wiremock) │    │  (SSE responses)    │  │
│  └─────────────┘    └─────────────┘    └─────────────────────┘  │
│         │                  │                                     │
│         ▼                  ▼                                     │
│  ┌─────────────┐    ┌─────────────┐                             │
│  │ ThreadManager│   │ ResponsesRequest (captured)               │
│  │ CodexThread  │   │  - body_json()                            │
│  │ ModelClient  │   │  - header()                               │
│  └─────────────┘    │  - input()                                │
│                     └─────────────┘                             │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 会话恢复测试

| 测试函数 | 目的 |
|---------|------|
| `resume_includes_initial_messages_and_sends_prior_items` | 验证恢复会话时，历史消息（user/assistant）按正确顺序发送到 API |
| `resume_replays_legacy_js_repl_image_rollout_shapes` | 验证对旧版 js_repl 图像 rollout 格式的向后兼容性 |
| `resume_replays_image_tool_outputs_with_detail` | 验证图像工具输出（含 detail 字段）在恢复时正确重放 |

**关键验证点**：
- 系统消息（system role）应从 API 历史中排除
- 消息顺序：prior_user → prior_assistant → permissions → user_instructions → environment → new_user
- 保留 message phase（如 "commentary"）

### 2.2 认证与请求头测试

| 测试函数 | 目的 |
|---------|------|
| `includes_conversation_id_and_model_headers_in_request` | 验证 session_id、originator、authorization 头的正确发送 |
| `chatgpt_auth_sends_correct_request` | 验证 ChatGPT OAuth 认证下的请求格式和特殊头（chatgpt-account-id）|
| `prefers_apikey_when_config_prefers_apikey_even_with_chatgpt_tokens` | 验证配置优先使用 API Key 时，即使有 ChatGPT token 也使用 API Key |

### 2.3 指令与上下文测试

| 测试函数 | 目的 |
|---------|------|
| `includes_base_instructions_override_in_request` | 验证 base_instructions 被包含在请求中 |
| `includes_user_instructions_message_in_request` | 验证 user_instructions 以正确的消息格式发送 |
| `includes_developer_instructions_message_in_request` | 验证 developer_instructions 被正确包含 |
| `includes_apps_guidance_as_developer_message_for_chatgpt_auth` | 验证 ChatGPT 认证时 Apps 指导作为 developer 消息发送 |
| `skills_append_to_developer_message` | 验证 Skills 内容被附加到 developer 消息 |

### 2.4 模型配置测试

| 测试函数 | 目的 |
|---------|------|
| `includes_configured_effort_in_request` | 验证 reasoning effort（medium/high/low）正确传递 |
| `user_turn_collaboration_mode_overrides_model_and_effort` | 验证 CollaborationMode 可覆盖模型和 effort 设置 |
| `configured_reasoning_summary_is_sent` | 验证 reasoning summary 配置被发送 |
| `includes_default_verbosity_in_request` | 验证 verbosity（low/medium/high）正确传递 |

### 2.5 错误处理与边界测试

| 测试函数 | 目的 |
|---------|------|
| `token_count_includes_rate_limits_snapshot` | 验证 TokenCount 事件包含速率限制信息 |
| `usage_limit_error_emits_rate_limit_event` | 验证 429 错误触发速率限制事件 |
| `context_window_error_sets_total_tokens_to_model_window` | 验证上下文窗口超限错误设置正确的 token 计数 |
| `incomplete_response_emits_content_filter_error_message` | 验证内容过滤导致的未完成响应触发错误 |

### 2.6 历史消息去重测试

| 测试函数 | 目的 |
|---------|------|
| `history_dedupes_streamed_and_final_messages_across_turns` | 验证流式传输的增量消息和最终消息在多轮对话中正确去重 |

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 核心类型定义

```rust
// 来自 codex_protocol::protocol
pub enum Op {
    UserInput {
        items: Vec<UserInput>,
        final_output_json_schema: Option<Value>,
    },
    UserTurn {
        items: Vec<UserInput>,
        cwd: PathBuf,
        approval_policy: AskForApproval,
        sandbox_policy: SandboxPolicy,
        model: String,
        effort: Option<ReasoningEffort>,
        summary: Option<ReasoningSummary>,
        service_tier: Option<Option<ServiceTier>>,
        final_output_json_schema: Option<Value>,
        collaboration_mode: Option<CollaborationMode>,
        personality: Option<Personality>,
    },
    // ... 其他变体
}

pub enum EventMsg {
    TurnStarted(TurnStartedEvent),
    TurnComplete(TurnCompleteEvent),
    TokenCount(TokenCountEvent),
    Error(ErrorEvent),
    // ... 其他变体
}
```

#### 3.1.2 测试辅助类型

```rust
// 来自 core_test_support::test_codex
pub struct TestCodex {
    pub home: Arc<TempDir>,
    pub cwd: Arc<TempDir>,
    pub codex: Arc<CodexThread>,
    pub session_configured: SessionConfiguredEvent,
    pub config: Config,
    pub thread_manager: Arc<ThreadManager>,
}

pub struct TestCodexBuilder {
    config_mutators: Vec<Box<ConfigMutator>>,
    auth: CodexAuth,
    pre_build_hooks: Vec<Box<PreBuildHook>>,
    home: Option<Arc<TempDir>>,
    user_shell_override: Option<Shell>,
}

// 来自 core_test_support::responses
pub struct ResponsesRequest(wiremock::Request);

impl ResponsesRequest {
    pub fn body_json(&self) -> Value;
    pub fn header(&self, name: &str) -> Option<String>;
    pub fn input(&self) -> Vec<Value>;
    pub fn message_input_texts(&self, role: &str) -> Vec<String>;
    pub fn function_call_output(&self, call_id: &str) -> Value;
}
```

### 3.2 关键测试流程

#### 3.2.1 标准测试流程模式

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn example_test() {
    // 1. 网络检查（在沙箱环境中跳过）
    skip_if_no_network!();
    
    // 2. 启动 Mock 服务器
    let server = MockServer::start().await;
    
    // 3. 挂载 SSE 响应模拟
    let resp_mock = mount_sse_once(
        &server,
        sse(vec![ev_response_created("resp1"), ev_completed("resp1")]),
    ).await;
    
    // 4. 构建 TestCodex 实例
    let mut builder = test_codex()
        .with_auth(CodexAuth::from_api_key("Test API Key"))
        .with_config(|config| {
            config.user_instructions = Some("be nice".to_string());
        });
    let codex = builder.build(&server).await.expect("create conversation").codex;
    
    // 5. 提交用户输入
    codex.submit(Op::UserInput { ... }).await.unwrap();
    
    // 6. 等待特定事件
    wait_for_event(&codex, |ev| matches!(ev, EventMsg::TurnComplete(_))).await;
    
    // 7. 验证请求内容
    let request = resp_mock.single_request();
    let request_body = request.body_json();
    assert_eq!(request_body["model"].as_str(), Some("gpt-5.1"));
}
```

#### 3.2.2 会话恢复测试流程

```rust
async fn resume_test() {
    // 1. 创建临时 rollout 文件
    let tmpdir = TempDir::new().unwrap();
    let session_path = tmpdir.path().join("resume-session.jsonl");
    
    // 2. 写入历史消息到 rollout 文件
    let mut f = std::fs::File::create(&session_path).unwrap();
    writeln!(f, "{}", json!({
        "timestamp": "2024-01-01T00:00:00.000Z",
        "type": "session_meta",
        "payload": { "id": convo_id, ... }
    })).unwrap();
    // ... 写入更多历史消息
    
    // 3. 使用 resume 构建器恢复会话
    let test = builder.resume(&server, codex_home, session_path.clone()).await
        .expect("resume conversation");
    
    // 4. 提交新输入并验证历史消息被正确包含
    test.codex.submit(Op::UserInput { ... }).await.unwrap();
    
    // 5. 验证请求中包含历史消息
    let request = resp_mock.single_request();
    let input = request.body_json()["input"].as_array().expect("input array");
    // ... 验证消息顺序和内容
}
```

### 3.3 SSE 事件构造

```rust
// 基础 SSE 事件构造器
pub fn sse(events: Vec<Value>) -> String {
    let mut out = String::new();
    for ev in events {
        let kind = ev.get("type").and_then(|v| v.as_str()).unwrap();
        writeln!(&mut out, "event: {kind}").unwrap();
        if !ev.as_object().map(|o| o.len() == 1).unwrap_or(false) {
            write!(&mut out, "data: {ev}\n\n").unwrap();
        } else {
            out.push('\n');
        }
    }
    out
}

// 常用事件构造器
pub fn ev_response_created(id: &str) -> Value;
pub fn ev_completed(id: &str) -> Value;
pub fn ev_completed_with_tokens(id: &str, total_tokens: i64) -> Value;
pub fn ev_message_item_added(id: &str, text: &str) -> Value;
pub fn ev_output_text_delta(delta: &str) -> Value;
pub fn ev_function_call(call_id: &str, name: &str, arguments: &str) -> Value;
```

### 3.4 Mock 服务器辅助函数

```rust
// 挂载单次 SSE 响应
pub async fn mount_sse_once(server: &MockServer, body: String) -> ResponseMock;

// 挂载带匹配条件的 SSE 响应
pub async fn mount_sse_once_match<M>(
    server: &MockServer, 
    matcher: M, 
    body: String
) -> ResponseMock 
where M: wiremock::Match + Send + Sync + 'static;

// 挂载 SSE 响应序列（用于多轮对话）
pub async fn mount_sse_sequence(
    server: &MockServer, 
    bodies: Vec<String>
) -> ResponseMock;
```

---

## 4. 关键代码路径与文件引用

### 4.1 被测代码路径

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/src/client.rs` | ModelClient 实现，负责与模型 API 通信 |
| `codex-rs/core/src/thread_manager.rs` | ThreadManager 实现，管理线程生命周期 |
| `codex-rs/core/src/codex_thread.rs` | CodexThread 实现，提供线程级操作接口 |
| `codex-rs/core/src/codex.rs` | 核心 Codex 逻辑，处理 Op 和 EventMsg |
| `codex-rs/core/src/message_history.rs` | 消息历史管理 |
| `codex-rs/core/src/client_common.rs` | 客户端通用类型（Prompt, ResponseEvent）|

### 4.2 协议定义路径

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/protocol/src/protocol.rs` | Op 枚举、EventMsg 枚举定义 |
| `codex-rs/protocol/src/models.rs` | ResponseItem、ContentItem 等模型类型 |
| `codex-rs/protocol/src/config_types.rs` | ReasoningEffort、ReasoningSummary 等配置类型 |
| `codex-rs/protocol/src/user_input.rs` | UserInput 类型定义 |

### 4.3 测试支持代码路径

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/tests/common/test_codex.rs` | TestCodex、TestCodexBuilder 实现 |
| `codex-rs/core/tests/common/responses.rs` | Mock 响应辅助函数、ResponsesRequest |
| `codex-rs/core/tests/common/lib.rs` | 通用测试辅助函数、wait_for_event |
| `codex-rs/core/tests/suite/mod.rs` | 测试模块聚合 |

### 4.4 关键调用链

```
TestCodexBuilder::build()
  └── ThreadManager::start_thread() / resume_thread_from_rollout()
        └── CodexThread::new()
              └── Codex::new()
                    └── ModelClient::new()

CodexThread::submit(Op::UserInput)
  └── Codex::submit()
        └── 构造 Prompt
        └── ModelClientSession::stream()
              └── 发送 HTTP 请求到 MockServer

wait_for_event(&codex, predicate)
  └── CodexThread::next_event()
        └── 从事件流接收 EventMsg
```

---

## 5. 依赖与外部交互

### 5.1 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `wiremock` | HTTP 模拟服务器，用于模拟 Responses API |
| `tokio` | 异步运行时，测试使用多线程模式 |
| `serde_json` | JSON 序列化/反序列化 |
| `tempfile` | 临时目录和文件创建 |
| `uuid` | UUID 生成（用于会话 ID）|
| `futures` | 异步流处理 |
| `pretty_assertions` | 更好的断言失败输出 |

### 5.2 内部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_core` | 被测核心库 |
| `codex_protocol` | 协议类型定义（Op, EventMsg 等）|
| `codex_otel` | 遥测和追踪 |
| `core_test_support` | 测试支持库 |

### 5.3 环境依赖

| 环境变量 | 用途 |
|---------|------|
| `CODEX_SANDBOX_NETWORK_DISABLED` | 网络禁用标志，设置时跳过测试 |
| `CODEX_HOME` | Codex 配置主目录（测试时指向临时目录）|

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 网络依赖风险

```rust
// 所有测试都依赖网络检查宏
skip_if_no_network!();
```

- **风险**：在沙箱环境或无网络环境中测试被跳过，可能导致回归未被发现
- **缓解**：CI 环境中确保网络可用，或在沙箱中运行时使用 mock 替代

#### 6.1.2 并发测试风险

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
```

- **风险**：多线程测试可能引入竞态条件，导致 flaky 测试
- **缓解**：使用 `wait_for_event` 而非固定延迟，确保事件顺序确定性

#### 6.1.3 临时目录清理风险

```rust
let tmpdir = TempDir::new().unwrap();
```

- **风险**：测试 panic 时临时目录可能未清理
- **缓解**：使用 `Arc<TempDir>` 确保生命周期管理，依赖 OS 临时目录清理

### 6.2 边界情况

#### 6.2.1 消息历史边界

| 边界情况 | 处理策略 |
|---------|---------|
| 空历史（新会话） | 只发送系统指令和当前输入 |
| 超长历史 | 依赖服务器的上下文窗口限制，客户端不主动截断 |
| 损坏的 rollout 文件 | 解析错误由 serde_json 处理，测试使用有效 JSON |

#### 6.2.2 认证边界

| 边界情况 | 处理策略 |
|---------|---------|
| API Key 和 OAuth 同时存在 | 根据配置优先级选择 |
| 过期的 OAuth token | 由 AuthManager 处理刷新，测试使用固定 token |
| 缺失认证信息 | 测试使用 `CodexAuth::from_api_key("dummy")` 确保不失败 |

### 6.3 改进建议

#### 6.3.1 测试覆盖率改进

1. **WebSocket 测试扩展**
   - 当前主要测试 SSE 路径
   - 建议增加 WebSocket 连接、重连、降级测试

2. **错误场景覆盖**
   - 增加网络超时、DNS 失败、TLS 错误等场景
   - 增加服务器返回非预期 JSON 的容错测试

3. **并发场景测试**
   - 测试多线程同时提交 Op 的线程安全性
   - 测试快速连续提交的场景

#### 6.3.2 代码结构改进

1. **测试数据工厂模式**
   ```rust
   // 建议：提取通用的 rollout 数据构造器
   struct RolloutFixtureBuilder;
   impl RolloutFixtureBuilder {
       fn with_user_message(text: &str) -> Self;
       fn with_assistant_message(text: &str) -> Self;
       fn with_image_output(url: &str) -> Self;
       fn build(self) -> TempDir;
   }
   ```

2. **断言辅助函数提取**
   - 当前多个测试有重复的断言逻辑
   - 建议提取 `assert_message_order!`、`assert_has_header!` 等宏

3. **参数化测试**
   - 使用 `rstest` 或类似框架对相似测试进行参数化
   - 减少代码重复，提高维护性

#### 6.3.3 性能优化

1. **MockServer 复用**
   - 当前每个测试启动新的 MockServer
   - 考虑使用 `lazy_static` 或 `once_cell` 复用服务器实例

2. **并行测试优化**
   - 确保测试间无共享状态
   - 使用唯一的临时目录和会话 ID 避免冲突

### 6.4 维护注意事项

1. **协议变更同步**
   - 当 `codex_protocol` 中的 Op/EventMsg 变更时，需同步更新测试
   - 建议添加协议版本检查

2. **模型版本更新**
   - 测试硬编码了模型名称（如 "gpt-5.1"）
   - 建议从配置或环境变量读取，便于模型升级

3. **SSE 事件格式变更**
   - OpenAI Responses API 的事件格式可能变更
   - 建议添加事件格式验证测试

---

## 7. 附录：关键代码片段

### 7.1 消息顺序验证模式

```rust
// 验证消息在 input 数组中的顺序
let pos_prior_user = messages
    .iter()
    .position(|(role, text)| role == "user" && text == "resumed user message")
    .expect("prior user message");
let pos_new_user = messages
    .iter()
    .position(|(role, text)| role == "user" && text == "hello")
    .expect("new user message");

assert!(pos_prior_user < pos_new_user);
```

### 7.2 认证 JSON 构造

```rust
fn write_auth_json(
    codex_home: &TempDir,
    openai_api_key: Option<&str>,
    chatgpt_plan_type: &str,
    access_token: &str,
    account_id: Option<&str>,
) -> String {
    // 构造 JWT payload
    let payload = json!({
        "email": "user@example.com",
        "https://api.openai.com/auth": {
            "chatgpt_plan_type": chatgpt_plan_type,
            "chatgpt_account_id": account_id.unwrap_or("acc-123")
        }
    });
    // ... 构造并写入 auth.json
}
```

### 7.3 速率限制头解析

```rust
let response = ResponseTemplate::new(200)
    .insert_header("x-codex-primary-used-percent", "12.5")
    .insert_header("x-codex-secondary-used-percent", "40.0")
    .insert_header("x-codex-primary-window-minutes", "10")
    .insert_header("x-codex-primary-reset-at", "1704069000")
    .set_body_raw(sse_body, "text/event-stream");
```

---

*文档生成时间：2026-03-23*
*基于代码版本：codex-rs/core/tests/suite/client.rs (2653 lines)*
