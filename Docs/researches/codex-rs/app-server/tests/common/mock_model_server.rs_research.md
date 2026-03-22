# mock_model_server.rs 研究文档

## 场景与职责

该文件提供了基于 `wiremock` 的模拟模型服务器功能，用于在集成测试中模拟 OpenAI Responses API 的行为。由于集成测试不应调用真实的 OpenAI API，该模块创建本地 HTTP 服务器来：
1. 按顺序返回预设的 SSE（Server-Sent Events）响应
2. 支持重复返回相同的助手消息
3. 验证请求数量和路径

这是测试 Codex 与模型交互逻辑的核心基础设施。

## 功能点目的

1. **序列响应**：按预定顺序返回多个 SSE 响应，模拟多轮对话
2. **重复响应**：对所有请求返回相同的助手消息
3. **请求验证**：可选地验证请求数量和路径匹配
4. **灵活匹配**：支持正则表达式匹配请求路径

## 具体技术实现

### 核心函数

```rust
/// 创建按顺序返回响应的 mock 服务器（带请求次数验证）
pub async fn create_mock_responses_server_sequence(responses: Vec<String>) -> MockServer;

/// 创建按顺序返回响应的 mock 服务器（无请求次数验证）
pub async fn create_mock_responses_server_sequence_unchecked(responses: Vec<String>) -> MockServer;

/// 创建重复返回相同助手消息的 mock 服务器
pub async fn create_mock_responses_server_repeating_assistant(message: &str) -> MockServer;
```

### 序列响应实现

```rust
pub async fn create_mock_responses_server_sequence(responses: Vec<String>) -> MockServer {
    let server = responses::start_mock_server().await;
    
    let num_calls = responses.len();
    let seq_responder = SeqResponder {
        num_calls: AtomicUsize::new(0),
        responses,
    };
    
    Mock::given(method("POST"))
        .and(path_regex(".*/responses$"))  // 匹配所有以 /responses 结尾的路径
        .respond_with(seq_responder)
        .expect(num_calls as u64)           // 验证请求次数
        .mount(&server)
        .await;
    
    server
}
```

### 序列响应器实现

```rust
struct SeqResponder {
    num_calls: AtomicUsize,
    responses: Vec<String>,
}

impl Respond for SeqResponder {
    fn respond(&self, _: &wiremock::Request) -> ResponseTemplate {
        let call_num = self.num_calls.fetch_add(1, Ordering::SeqCst);
        match self.responses.get(call_num) {
            Some(response) => responses::sse_response(response.clone()),
            None => panic!("no response for {call_num}"),  // 请求超出预期次数时 panic
        }
    }
}
```

### 重复响应实现

```rust
pub async fn create_mock_responses_server_repeating_assistant(message: &str) -> MockServer {
    let server = responses::start_mock_server().await;
    
    // 构建 SSE 响应体
    let body = responses::sse(vec![
        responses::ev_response_created("resp-1"),
        responses::ev_assistant_message("msg-1", message),
        responses::ev_completed("resp-1"),
    ]);
    
    Mock::given(method("POST"))
        .and(path_regex(".*/responses$"))
        .respond_with(responses::sse_response(body))
        .mount(&server)
        .await;
    
    server
}
```

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/app-server/tests/common/mock_model_server.rs`

### 导出位置
- `lib.rs`: 
```rust
pub use mock_model_server::create_mock_responses_server_repeating_assistant;
pub use mock_model_server::create_mock_responses_server_sequence;
pub use mock_model_server::create_mock_responses_server_sequence_unchecked;
```

### 依赖的上游模块
- `core_test_support::responses` - SSE 响应构建工具

### 使用示例

```rust
// 测试代码中使用示例

// 1. 序列响应
let responses = vec![
    create_shell_command_sse_response(
        vec!["echo".to_string(), "hello".to_string()],
        None,
        None,
        "call-1",
    )?,
    create_final_assistant_message_sse_response("Done")?,
];
let server = create_mock_responses_server_sequence(responses).await;

// 2. 重复响应
let server = create_mock_responses_server_repeating_assistant("Hello, how can I help?").await;

// 3. 配置指向 mock 服务器
write_mock_responses_config_toml(
    codex_home.path(),
    &server.uri(),
    &features,
    10000,
    Some(false),
    "mock",
    "prompt",
)?;
```

## 依赖与外部交互

### 外部 crate 依赖
- `wiremock::{Mock, MockServer, Respond, ResponseTemplate}` - HTTP mock 框架
- `wiremock::matchers::{method, path_regex}` - 请求匹配器
- `std::sync::atomic::{AtomicUsize, Ordering}` - 原子计数

### Codex 内部依赖
```
mock_model_server.rs
└── core_test_support::responses
    ├── start_mock_server()          启动基础 mock 服务器
    ├── sse()                        构建 SSE 响应体
    ├── sse_response()               创建 SSE ResponseTemplate
    ├── ev_response_created()        响应创建事件
    ├── ev_assistant_message()       助手消息事件
    └── ev_completed()               响应完成事件
```

### 请求-响应流程

```
测试代码
    │
    ├──► create_mock_responses_server_sequence(responses)
    │       │
    │       ├──► responses::start_mock_server() 启动 wiremock 服务器
    │       │
    │       ├──► 创建 SeqResponder（带原子计数器）
    │       │
    │       └──► Mock::given(...).mount(&server) 配置路由
    │
    ├──► 配置 codex-app-server 指向 mock server URI
    │
    └──► 触发被测代码
            │
            └──► POST /v1/responses ──► SeqResponder.respond()
                                            │
                                            ├──► 原子递增计数器
                                            ├──► 按索引获取响应
                                            └──► 返回 SSE ResponseTemplate
```

## 风险、边界与改进建议

### 风险
1. **panic 风险**：`SeqResponder` 在请求超出预期次数时会 panic，可能导致测试不稳定
2. **竞态条件**：`AtomicUsize` 使用 `SeqCst` 顺序一致性，虽然安全但性能开销较大
3. **路径匹配宽松**：`.*/responses$` 正则可能匹配到意外的路径
4. **无请求验证**：除了 `create_mock_responses_server_sequence` 的 `expect`，其他函数不验证请求内容

### 边界
- 仅支持 POST 方法
- 仅支持路径以 `/responses` 结尾的端点
- 序列响应器不支持并发请求（计数器可能竞争）
- 不支持动态响应生成（基于请求内容）
- 不支持模拟错误响应（如 429、500 等）

### 改进建议

1. **优雅处理超额请求**：
```rust
impl Respond for SeqResponder {
    fn respond(&self, _: &wiremock::Request) -> ResponseTemplate {
        let call_num = self.num_calls.fetch_add(1, Ordering::SeqCst);
        match self.responses.get(call_num) {
            Some(response) => responses::sse_response(response.clone()),
            None => {
                eprintln!("warning: unexpected request #{}", call_num);
                ResponseTemplate::new(500).set_body_string("No more responses configured")
            }
        }
    }
}
```

2. **支持动态响应**：
```rust
pub async fn create_mock_responses_server_with_handler<F>(
    handler: F
) -> MockServer 
where 
    F: Fn(&Request) -> String + Send + Sync + 'static 
{ ... }
```

3. **错误场景模拟**：
```rust
pub async fn create_mock_responses_server_with_error(
    status: u16,
    error_body: &str,
) -> MockServer { ... }
```

4. **请求内容验证**：
```rust
pub struct ValidatedMock {
    server: MockServer,
    expected_requests: Vec<ExpectedRequest>,
}

impl ValidatedMock {
    pub fn verify(&self) -> Result<()> { ... }
}
```

5. **并发安全改进**：
```rust
// 使用 Mutex 保护响应列表，支持更复杂的调度策略
struct ConcurrentSeqResponder {
    responses: Mutex<VecDeque<String>>,
}
```

6. **路径匹配精确化**：
```rust
// 支持精确路径匹配
pub async fn create_mock_responses_server_sequence_with_path(
    path: &str,  // 精确路径而非正则
    responses: Vec<String>,
) -> MockServer { ... }
```
