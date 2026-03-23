# streaming_sse.rs 研究文档

## 文件基本信息

- **路径**: `codex-rs/core/tests/common/streaming_sse.rs`
- **大小**: 约 693 行 (25357 bytes)
- **所属 crate**: `core_test_support`
- **用途**: 轻量级流式 SSE 测试服务器

---

## 场景与职责

`streaming_sse.rs` 提供了一个**轻量级、低依赖的 HTTP SSE (Server-Sent Events) 测试服务器**，作为 `wiremock` 的替代方案，专门用于需要**精确控制流式传输时序**的测试场景。

### 与 wiremock 的区别

| 特性 | wiremock (responses.rs) | streaming_sse.rs |
|------|------------------------|------------------|
| 依赖 | 重（完整 HTTP mock 框架） | 轻（仅 tokio） |
| 流控制 | 一次性返回完整响应 | 逐 chunk 控制，支持 gate 机制 |
| 并发模型 | 多线程 | 单线程异步 |
| 适用场景 | 普通 API 测试 | 流式传输、背压、超时测试 |
| 协议支持 | 完整 HTTP | 简化 HTTP (仅 SSE) |

### 核心职责

1. **逐 chunk 流控**: 每个 SSE 事件可以独立控制发送时机（通过 `gate` 机制）
2. **完成通知**: 每个响应流发送完成后通知测试代码
3. **请求捕获**: 记录所有接收到的请求体供验证
4. **轻量级**: 最小化依赖，快速启动

---

## 功能点目的

### 1. 门控流式传输 (`StreamingSseChunk`)

```rust
pub struct StreamingSseChunk {
    pub gate: Option<oneshot::Receiver<()>>,  // 发送前等待的信号
    pub body: String,                          // SSE 事件内容
}
```

**目的**: 允许测试代码精确控制每个 SSE 事件的发送时机，用于测试：
- 客户端超时处理
- 流式解析逻辑
- 背压机制
- 连接中断恢复

### 2. 服务器生命周期管理 (`StreamingSseServer`)

```rust
pub struct StreamingSseServer {
    uri: String,
    requests: Arc<TokioMutex<Vec<Vec<u8>>>>,  // 捕获的请求体
    shutdown: oneshot::Sender<()>,            // 关闭信号
    task: tokio::task::JoinHandle<()>,        // 服务器任务
}
```

**方法**:
- `uri()`: 获取服务器地址
- `requests()`: 获取所有捕获的请求
- `shutdown()`: 优雅关闭服务器

### 3. 完成通知机制

```rust
pub async fn start_streaming_sse_server(
    responses: Vec<Vec<StreamingSseChunk>>,
) -> (StreamingSseServer, Vec<oneshot::Receiver<i64>>)
```

返回的 `Receiver<i64>` 在对应响应流完成时收到 Unix 毫秒时间戳，用于：
- 验证流完成顺序
- 测量流持续时间
- 同步测试步骤

### 4. 简化 HTTP 协议实现

| 功能 | 实现 |
|------|------|
| 请求解析 | 手动解析 HTTP 请求头（无外部依赖） |
| Content-Length 处理 | 支持固定长度请求体 |
| SSE 响应 | 硬编码 SSE 头，流式发送 body |
| 错误处理 | 400/404/500 简单响应 |

---

## 具体技术实现

### HTTP 协议解析

```rust
// 读取直到 \r\n\r\n（HTTP 头结束标记）
async fn read_http_request(stream: &mut TcpStream) -> (String, Vec<u8>) {
    loop {
        let read = stream.read(&mut scratch).await.unwrap_or(0);
        buf.extend_from_slice(&scratch[..read]);
        if let Some(end) = header_terminator_index(&buf) {
            let header = String::from_utf8_lossy(&buf[..end + 4]).into_owned();
            let rest = buf[end + 4..].to_vec();
            return (header, rest);
        }
    }
}

fn header_terminator_index(buf: &[u8]) -> Option<usize> {
    buf.windows(4).position(|w| w == b"\r\n\r\n")
}
```

### 请求体读取

```rust
async fn read_request_body(
    stream: &mut TcpStream,
    headers: &str,
    body_prefix: Vec<u8>,
) -> std::io::Result<Vec<u8>> {
    let content_len = content_length(headers).unwrap_or(0);
    
    // 处理已读取的部分 body
    if body_prefix.len() >= content_len {
        return Ok(body_prefix[..content_len].to_vec());
    }
    
    // 读取剩余 body
    let remaining = content_len - body_prefix.len();
    let mut rest = vec![0u8; remaining];
    stream.read_exact(&mut rest).await?;
    
    let mut body = body_prefix;
    body.extend_from_slice(&rest);
    Ok(body)
}
```

### 门控流发送

```rust
for chunk in chunks {
    // 等待 gate 信号（如果有）
    if let Some(gate) = chunk.gate {
        if gate.await.is_err() {
            return;  // gate 被关闭，终止发送
        }
    }
    
    // 发送 chunk
    if stream.write_all(chunk.body.as_bytes()).await.is_err() {
        return;  // 连接断开
    }
    let _ = stream.flush().await;
}

// 通知完成
let _ = completion.send(unix_ms_now());
```

### 状态管理

```rust
struct StreamingSseState {
    responses: VecDeque<Vec<StreamingSseChunk>>,     // 待发送的响应队列
    completions: VecDeque<oneshot::Sender<i64>>,     // 完成通知发送者队列
}

async fn take_next_stream(
    state: &TokioMutex<StreamingSseState>,
) -> Option<(Vec<StreamingSseChunk>, oneshot::Sender<i64>)> {
    let mut guard = state.lock().await;
    let chunks = guard.responses.pop_front()?;
    let completion = guard.completions.pop_front()?;
    Some((chunks, completion))
}
```

---

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 关系 |
|------|------|
| `lib.rs` | 模块导出 (`pub mod streaming_sse`) |
| `responses.rs` | 功能互补，后者使用 wiremock |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `tokio` | 异步运行时、TCP、同步原语 |
| `serde_json` | 仅用于测试中的 JSON 解析 |

### 调用方示例

```rust
// 构造带 gate 的 SSE 流
let (gate_tx, gate_rx) = oneshot::channel();
let chunks = vec![
    StreamingSseChunk {
        gate: Some(gate_rx),
        body: "event: response.output_item.done\ndata: {...}\n\n".to_string(),
    },
];

let (server, mut completions) = start_streaming_sse_server(vec![chunks]).await;

// 客户端发起请求
let response = client.post(&format!("{}/v1/responses", server.uri()))
    .send().await;

// 测试代码控制发送时机
gate_tx.send(()).unwrap();

// 等待流完成
let timestamp = completions.pop().unwrap().await.unwrap();
```

---

## 依赖与外部交互

### 1. 简化 HTTP 协议

仅实现必要的 HTTP/1.1 子集：
- **请求**: `GET /v1/models`, `POST /v1/responses`
- **响应**: 200 (SSE), 400 (Bad Request), 404 (Not Found), 500 (Internal Error)
- **头**: `Content-Type`, `Content-Length`

### 2. SSE 格式

遵循 OpenAI 的 SSE 格式：
```
event: <type>
data: <json_payload>

```

### 3. TCP 连接管理

- 每个请求新建 TCP 连接（HTTP/1.1 简化）
- 响应完成后关闭连接（`connection: close`）
- 无 keep-alive 支持

---

## 风险、边界与改进建议

### 已知风险

| 风险 | 影响 | 缓解 |
|------|------|------|
| 无 TLS 支持 | 无法测试 HTTPS 场景 | 使用 HTTP 测试或添加 TLS 支持 |
| 单线程模型 | 高并发测试受限 | 使用 wiremock 替代 |
| 无 chunked encoding | 大响应需要 Content-Length | 添加 Transfer-Encoding 支持 |
| 手动 HTTP 解析 | 可能存在边界 case 错误 | 增加 fuzz 测试 |

### 边界条件

1. **空响应队列**: 返回 500 "no responses queued"
2. **请求体超过 Content-Length**: 截断处理
3. **gate 被 drop**: 发送取消，连接保持（可能泄漏）
4. **客户端提前断开**: `write_all` 返回错误，终止发送

### 改进建议

1. **添加 keep-alive 支持**: 复用 TCP 连接提高性能
2. **支持 chunked transfer encoding**: 处理大响应流
3. **添加延迟注入**: 支持网络延迟模拟
4. **HTTP/2 支持**: 测试多路复用场景
5. **连接数限制**: 防止测试中的资源泄漏
6. **请求路由**: 支持更多端点（如 `/v1/chat/completions`）

### 测试覆盖

模块包含 11 个单元测试：
- `get_models_returns_empty_list`: 验证 models 端点
- `post_responses_streams_in_order_and_closes`: 基础 SSE 流
- `none_gate_streams_immediately`: 无 gate 时立即发送
- `post_responses_with_no_queue_returns_500`: 空队列处理
- `gated_chunks_wait_for_signal_and_preserve_order`: gate 机制
- `multiple_responses_are_fifo_and_completion_timestamps_monotonic`: FIFO 保证
- `unknown_route_returns_404`: 404 处理
- `malformed_request_returns_400`: 400 处理
- `responses_post_drains_request_body`: 请求体读取
- `read_http_request_returns_after_header_terminator`: 请求解析
- `shutdown_terminates_accept_loop`: 优雅关闭

建议补充：
- 大请求体（> 1MB）测试
- 并发连接测试
- 网络分区模拟测试
