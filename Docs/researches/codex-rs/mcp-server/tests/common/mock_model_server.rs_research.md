# mock_model_server.rs 研究文档

## 场景与职责

`mock_model_server.rs` 实现了模拟 OpenAI API 响应服务器的功能，用于 MCP 服务器集成测试。它使用 `wiremock` 库创建一个本地 HTTP 服务器，模拟 `/v1/responses` 端点的行为，使测试能够在不依赖真实 OpenAI API 的情况下验证 MCP 服务器的功能。

## 功能点目的

1. **API 模拟**: 模拟 OpenAI Responses API 的 SSE（Server-Sent Events）响应
2. **顺序响应**: 支持按顺序返回多个预定义的响应
3. **请求验证**: 验证 MCP 服务器发送的请求是否符合预期
4. **测试隔离**: 消除对外部网络服务的依赖，提高测试稳定性和速度

## 具体技术实现

### 核心函数

```rust
/// Create a mock server that will provide the responses, in order, for
/// requests to the `/v1/responses` endpoint.
pub async fn create_mock_responses_server(responses: Vec<String>) -> MockServer
```

该函数：
1. 启动一个本地 HTTP 服务器（随机端口）
2. 配置 `/v1/responses` 端点的 POST 请求处理
3. 按顺序返回提供的响应字符串
4. 验证请求次数与响应数量匹配

### 实现细节

```rust
pub async fn create_mock_responses_server(responses: Vec<String>) -> MockServer {
    // 1. 启动 wiremock 服务器
    let server = MockServer::start().await;
    
    let num_calls = responses.len();
    let seq_responder = SeqResponder {
        num_calls: AtomicUsize::new(0),
        responses,
    };
    
    // 2. 配置 mock 规则
    Mock::given(method("POST"))           // 只处理 POST 请求
        .and(path("/v1/responses"))        // 只处理 /v1/responses 路径
        .respond_with(seq_responder)       // 使用顺序响应器
        .expect(num_calls as u64)          // 验证请求次数
        .mount(&server)
        .await;
    
    server
}
```

### 顺序响应器

```rust
struct SeqResponder {
    num_calls: AtomicUsize,  // 原子计数器，记录调用次数
    responses: Vec<String>,  // 预定义的响应列表
}

impl Respond for SeqResponder {
    fn respond(&self, _: &wiremock::Request) -> ResponseTemplate {
        // 获取当前调用序号并递增
        let call_num = self.num_calls.fetch_add(1, Ordering::SeqCst);
        
        match self.responses.get(call_num) {
            Some(response) => ResponseTemplate::new(200)
                .insert_header("content-type", "text/event-stream")
                .set_body_raw(response.clone(), "text/event-stream"),
            None => panic!("no response for {call_num}"),  // 响应不足时 panic
        }
    }
}
```

## 关键代码路径与文件引用

### 依赖关系

```
mock_model_server.rs
├── 使用:
│   ├── wiremock::* (HTTP mock 框架)
│   └── std::sync::atomic::* (原子操作)
├── 被使用:
│   └── lib.rs (重新导出 create_mock_responses_server)
└── 测试使用:
    └── tests/suite/codex_tool.rs
```

### 调用链

```rust
// 测试代码示例
let server = create_mock_responses_server(vec![
    create_shell_command_sse_response(...)?,
    create_final_assistant_message_sse_response(...)?,
]).await;

// server.uri() 返回类似 "http://127.0.0.1:12345" 的地址
// MCP 服务器会配置为向该地址发送请求
```

### 与 core_test_support 的关系

```
mock_model_server.rs (本文件)
    └── 提供: create_mock_responses_server()
        └── 返回: MockServer
            └── 用于配置 MCP 服务器的 model provider

core_test_support::responses
    └── 提供: sse(), ev_*, 等函数
        └── 用于构建 SSE 响应字符串
            └── 传递给 create_mock_responses_server()
```

## 依赖与外部交互

### 外部 crate 依赖

1. **wiremock**: HTTP mock 服务器框架
   - `MockServer`: 本地 HTTP 服务器
   - `Mock`: Mock 规则构建器
   - `Respond`: 响应生成 trait
   - `ResponseTemplate`: HTTP 响应模板
   - `matchers::method`, `matchers::path`: 请求匹配器

2. **std::sync::atomic**: 原子操作
   - `AtomicUsize`: 线程安全的计数器
   - `Ordering::SeqCst`: 顺序一致性内存序

### 与测试代码的交互

```
测试代码
    │
    ▼
create_mock_responses_server(vec![response1, response2])
    │
    ▼
启动 HTTP 服务器: http://127.0.0.1:<random_port>
    │
    ▼
配置 MCP 服务器使用该地址作为 model provider
    │
    ▼
MCP 服务器 ──POST /v1/responses──► MockServer
                                       │
                                       ▼
                                  SeqResponder
                                       │
                                       ▼
                               返回 response1 (第1次)
                               返回 response2 (第2次)
```

### SSE 响应格式

模拟的 OpenAI Responses API 使用 Server-Sent Events 格式：

```
event: response.created
data: {"type":"response.created","response":{"id":"resp-1"}}

event: response.output_item.done
data: {"type":"response.output_item.done","item":{...}}

event: response.completed
data: {"type":"response.completed","response":{"id":"resp-1",...}}
```

## 风险、边界与改进建议

### 风险

1. **响应耗尽 panic**:
   - 如果请求次数超过提供的响应数量，`SeqResponder` 会 panic
   - 这会导致测试失败，但错误信息可能不够清晰

2. **端口冲突**:
   - `MockServer::start()` 使用随机端口，理论上冲突概率低
   - 但在端口耗尽的环境中可能失败

3. **并发安全**:
   - `AtomicUsize` 使用 `Ordering::SeqCst`，性能略低但安全
   - 并发请求可能导致响应顺序不确定

4. **资源泄漏**:
   - `MockServer` 在测试结束后需要被 drop
   - 如果测试 panic，可能无法正确清理

### 边界情况

1. **空响应列表**:
   - `responses` 为空时，`expect(0)` 会验证没有请求被发送
   - 这可能不是预期的测试行为

2. **重复响应**:
   - 当前实现不支持循环使用响应
   - 如果需要多次返回相同响应，需要重复添加到列表

3. **请求匹配**:
   - 当前实现只匹配方法和路径，不验证请求体
   - 无法针对不同请求参数返回不同响应

4. **异步生命周期**:
   - `MockServer` 必须在异步上下文中创建
   - 不能在 `#[test]`（非 async）中使用

### 改进建议

1. **优雅的响应耗尽处理**:
   ```rust
   impl Respond for SeqResponder {
       fn respond(&self, _: &wiremock::Request) -> ResponseTemplate {
           let call_num = self.num_calls.fetch_add(1, Ordering::SeqCst);
           match self.responses.get(call_num) {
               Some(response) => ResponseTemplate::new(200)
                   .insert_header("content-type", "text/event-stream")
                   .set_body_raw(response.clone(), "text/event-stream"),
               None => {
                   eprintln!("Warning: unexpected request #{call_num}, returning 500");
                   ResponseTemplate::new(500)
                       .set_body_json(json!({"error": "no more mock responses"}))
               }
           }
       }
   }
   ```

2. **支持循环响应**:
   ```rust
   struct SeqResponder {
       num_calls: AtomicUsize,
       responses: Vec<String>,
       cycle: bool,  // 是否循环使用响应
   }
   
   impl Respond for SeqResponder {
       fn respond(&self, _: &wiremock::Request) -> ResponseTemplate {
           let call_num = self.num_calls.fetch_add(1, Ordering::SeqCst);
           let index = if self.cycle {
               call_num % self.responses.len()
           } else {
               call_num
           };
           // ...
       }
   }
   ```

3. **请求体验证**:
   ```rust
   pub async fn create_mock_responses_server_with_matcher<
       F: Fn(&wiremock::Request) -> bool + Send + Sync + 'static,
   >(
       responses: Vec<String>,
       matcher: F,
   ) -> MockServer {
       // 允许传入自定义匹配器验证请求体
   }
   ```

4. **添加超时配置**:
   ```rust
   pub struct MockServerConfig {
       pub response_delay: Option<Duration>,  // 模拟网络延迟
       pub max_requests: Option<usize>,       // 最大请求数限制
   }
   ```

5. **更好的错误信息**:
   ```rust
   impl Respond for SeqResponder {
       fn respond(&self, request: &wiremock::Request) -> ResponseTemplate {
           let call_num = self.num_calls.fetch_add(1, Ordering::SeqCst);
           
           if call_num >= self.responses.len() {
               panic!(
                   "Mock server received request #{}, but only {} responses configured. \
                    Request: {:?}",
                   call_num, self.responses.len(), request
               );
           }
           
           // ...
       }
   }
   ```

6. **支持动态响应生成**:
   ```rust
   pub async fn create_mock_responses_server_dynamic<
       F: Fn(usize, &wiremock::Request) -> String + Send + Sync + 'static,
   >(
       response_generator: F,
   ) -> MockServer {
       // 允许根据请求动态生成响应
   }
   ```
