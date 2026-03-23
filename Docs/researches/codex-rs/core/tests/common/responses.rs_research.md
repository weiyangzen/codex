# responses.rs 研究文档

## 文件基本信息

- **路径**: `codex-rs/core/tests/common/responses.rs`
- **大小**: 约 1629 行 (53994 bytes)
- **所属 crate**: `core_test_support`
- **用途**: OpenAI API 响应模拟与测试辅助工具

---

## 场景与职责

`responses.rs` 是 Codex 核心测试框架的**HTTP/WebSocket 模拟基础设施**，提供完整的 OpenAI API 响应模拟能力。它解决了以下测试痛点：

1. **网络隔离测试**: 无需真实 OpenAI API 密钥即可测试核心逻辑
2. **确定性响应**: 精确控制模型返回的内容，包括函数调用、工具执行、流式输出
3. **请求验证**: 捕获并验证客户端发送的请求内容
4. **并发测试**: 支持多连接、多请求的 WebSocket 实时对话测试
5. **压缩支持**: 自动处理 zstd 压缩的请求体

该模块是 `core_test_support` crate 的核心组件，被 `codex-core`、`codex-exec`、`codex-login`、`codex-app-server` 等多个 crate 的测试所依赖。

---

## 功能点目的

### 1. HTTP Mock 服务器 (`wiremock` 集成)

| 功能 | 目的 |
|------|------|
| `start_mock_server()` | 启动默认配置的 mock 服务器，自动挂载空的 models 响应 |
| `mount_sse_once()` | 单次挂载 SSE 流响应，用于简单测试场景 |
| `mount_sse_sequence()` | 顺序挂载多个 SSE 响应，用于多轮对话测试 |
| `mount_response_once()` | 挂载自定义 ResponseTemplate |
| `mount_models_once()` | 挂载 models API 响应 |

### 2. WebSocket 测试服务器

| 功能 | 目的 |
|------|------|
| `start_websocket_server()` | 启动 WebSocket 服务器，支持实时对话协议测试 |
| `WebSocketTestServer` | 管理连接、握手、请求日志，支持延迟和自定义响应头 |
| `wait_for_request()` | 异步等待特定请求到达 |
| `wait_for_handshakes()` | 等待指定数量的 WebSocket 握手完成 |

### 3. SSE 事件构造器

提供声明式 API 构造 OpenAI Responses API 的 SSE 事件：

- **生命周期事件**: `ev_response_created()`, `ev_completed()`, `ev_completed_with_tokens()`
- **消息事件**: `ev_assistant_message()`, `ev_message_item_added()`, `ev_output_text_delta()`
- **推理事件**: `ev_reasoning_item()`, `ev_reasoning_summary_text_delta()`
- **工具调用事件**: `ev_function_call()`, `ev_tool_search_call()`, `ev_custom_tool_call()`
- **Shell 事件**: `ev_local_shell_call()`, `ev_shell_command_call()`
- **Patch 应用事件**: `ev_apply_patch_call()` (支持多种输出格式)

### 4. 请求捕获与验证 (`ResponseMock`, `ResponsesRequest`)

| 方法 | 功能 |
|------|------|
| `single_request()` | 获取唯一捕获的请求（断言恰好一个） |
| `requests()` | 获取所有捕获的请求 |
| `body_json()` | 解析请求体为 JSON（自动解压缩 zstd） |
| `input()` / `inputs_of_type()` | 提取请求 input 数组 |
| `function_call_output()` | 获取特定 call_id 的函数调用输出 |
| `message_input_texts()` | 提取指定角色的消息文本 |
| `header()` / `path()` / `query_param()` | 提取请求元数据 |

### 5. 请求体不变式验证

`validate_request_body_invariants()` 函数自动验证：
- 无孤儿 `function_call_output`（必须有对应的 `function_call`）
- 无孤儿 `custom_tool_call_output`（必须有对应的 `custom_tool_call`）
- 无孤儿 `tool_search_output`（必须有对应的 `tool_search_call`）
- 对称性：每个调用必须有对应的输出，反之亦然
- `call_id` 非空检查

---

## 具体技术实现

### 核心数据结构

```rust
// 响应模拟器 - 捕获并存储请求
pub struct ResponseMock {
    requests: Arc<Mutex<Vec<ResponsesRequest>>>,
}

// 请求包装器 - 提供便捷的访问方法
pub struct ResponsesRequest(wiremock::Request);

// WebSocket 测试服务器
pub struct WebSocketTestServer {
    uri: String,
    connections: Arc<Mutex<Vec<Vec<WebSocketRequest>>>>,
    handshakes: Arc<Mutex<Vec<WebSocketHandshake>>>,
    request_log_updated: Arc<Notify>,
    shutdown: oneshot::Sender<()>,
    task: tokio::task::JoinHandle<()>,
}

// WebSocket 连接配置
pub struct WebSocketConnectionConfig {
    pub requests: Vec<Vec<Value>>,           // 每个请求对应的响应事件序列
    pub response_headers: Vec<(String, String)>,
    pub accept_delay: Option<Duration>,      // 握手延迟（用于测试超时）
    pub close_after_requests: bool,          // 是否自动关闭连接
}
```

### SSE 格式构造

```rust
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
```

### zstd 解压缩

```rust
fn decode_body_bytes(body: &[u8], content_encoding: Option<&str>) -> Vec<u8> {
    if content_encoding.is_some_and(is_zstd_encoding) {
        zstd::stream::decode_all(std::io::Cursor::new(body)).unwrap_or_else(|err| {
            panic!("failed to decode zstd request body: {err}");
        })
    } else {
        body.to_vec()
    }
}
```

### WebSocket 服务器核心循环

```rust
async fn websocket_handler(
    listener: TcpListener,
    connections: Arc<Mutex<VecDeque<WebSocketConnectionConfig>>>,
    // ...
) {
    loop {
        let accept_res = tokio::select! {
            _ = &mut shutdown_rx => return,
            accept_res = listener.accept() => accept_res,
        };
        
        // 1. 获取下一个连接配置
        let connection = connections.lock().unwrap().pop_front();
        
        // 2. 应用握手延迟（用于测试）
        if let Some(delay) = connection.accept_delay {
            tokio::time::sleep(delay).await;
        }
        
        // 3. 执行 WebSocket 握手，记录请求头
        let ws_stream = accept_hdr_async_with_config(stream, callback, config).await;
        
        // 4. 处理请求-响应序列
        for request_events in connection.requests {
            // 接收请求
            let message = ws_stream.next().await;
            // 记录请求
            // 发送响应事件序列
            for event in &request_events {
                ws_stream.send(Message::Text(payload.into())).await;
            }
        }
        
        // 5. 可选关闭或保持连接
    }
}
```

### 请求体验证（Match trait 实现）

```rust
impl Match for ResponseMock {
    fn matches(&self, request: &wiremock::Request) -> bool {
        self.requests.lock().unwrap().push(ResponsesRequest(request.clone()));
        // 每次捕获请求时验证不变式
        validate_request_body_invariants(request);
        true
    }
}
```

---

## 关键代码路径与文件引用

### 内部依赖

| 依赖 | 用途 |
|------|------|
| `lib.rs` | 模块导出，测试初始化 |
| `test_codex.rs` | `ApplyPatchModelOutput` 枚举定义 |
| `streaming_sse.rs` | 流式 SSE 服务器（替代 wiremock 的场景） |

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `wiremock` | HTTP mock 服务器基础设施 |
| `tokio-tungstenite` | WebSocket 服务器实现 |
| `zstd` | 请求体解压缩 |
| `serde_json` | JSON 序列化/反序列化 |
| `base64` | 推理内容编码 |
| `codex_protocol` | OpenAI API 模型定义 |

### 调用方（测试文件示例）

```rust
// codex-rs/core/tests/suite/client.rs
use core_test_support::responses::{
    mount_sse_once, ev_function_call, ev_completed, sse
};

let mock = mount_sse_once(&server, sse(vec![
    ev_function_call("call-1", "shell", r#"{"command":["ls"]}"#),
    ev_completed("resp-1"),
])).await;

// 验证请求
codex.submit(Op::UserTurn { ... }).await?;
let request = mock.single_request();
assert!(request.has_function_call("call-1"));
```

---

## 依赖与外部交互

### 1. OpenAI Responses API 协议

该模块深度绑定 OpenAI Responses API 的事件格式：

- **事件类型**: `response.created`, `response.completed`, `response.output_item.done`
- **输出项类型**: `message`, `function_call`, `custom_tool_call`, `tool_search_call`, `local_shell_call`, `reasoning`
- **输入项类型**: `message`, `function_call_output`, `custom_tool_call_output`, `tool_search_output`

### 2. wiremock 集成

利用 `wiremock` 的 `Match` 和 `Respond` trait 实现：
- `Match`: 捕获所有匹配请求，存储用于后续验证
- `Respond`: 自定义响应逻辑（如序列响应、动态响应）

### 3. WebSocket 实时协议

支持 Codex 的 WebSocket 实时对话协议：
- 请求/响应消息格式为 JSON
- 支持文本和二进制帧
- 支持 permessage-deflate 扩展

### 4. 压缩协商

自动检测 `content-encoding: zstd` 请求头，透明解压缩请求体。

---

## 风险、边界与改进建议

### 已知风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| `unwrap()` 在解码失败时 panic | 测试崩溃 | 确保测试数据格式正确 |
| 全局 `Mutex` 可能阻塞 | 并发测试性能 | 使用 `parking_lot` 或细粒度锁 |
| WebSocket 服务器无超时 | 测试挂起 | 调用方使用 `tokio::time::timeout` |
| 硬编码的 OpenAI 协议 | 协议变更时失效 | 与 `codex_protocol` 保持同步 |

### 边界条件

1. **空响应队列**: `start_streaming_sse_server` 传入空 Vec 时，所有请求返回 500
2. **请求数不匹配**: `mount_sse_sequence` 在请求数超过预期时会 panic
3. **zstd 检测**: 仅检测 `zstd` 编码，不支持其他压缩格式
4. **WebSocket 握手延迟**: `accept_delay` 仅影响握手，不影响消息处理

### 改进建议

1. **增强错误处理**: 将 `unwrap()` 替换为 `Result` 返回，允许调用方决定失败策略
2. **支持更多压缩格式**: 添加 gzip、br 支持
3. **请求匹配器**: 提供内置的请求匹配器（如 JSON 子集匹配）
4. **性能优化**: 使用 `RwLock` 替代 `Mutex` 提高并发读取性能
5. **协议版本化**: 添加 API 版本字段，支持多版本协议测试
6. **文档示例**: 为复杂场景（如多轮函数调用）提供更多示例代码

### 测试覆盖

该模块本身包含单元测试（`mod tests`），覆盖：
- SSE 格式构造
- 请求体验证逻辑
- `output_value_to_text` 辅助函数

建议补充：
- WebSocket 服务器的边界条件测试
- zstd 解压缩错误处理测试
- 并发请求顺序保证测试
