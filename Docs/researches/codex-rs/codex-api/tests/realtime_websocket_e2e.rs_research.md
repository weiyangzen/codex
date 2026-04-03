# 研究文档：codex-rs/codex-api/tests/realtime_websocket_e2e.rs

## 场景与职责

`realtime_websocket_e2e.rs` 是 `codex-api` crate 的端到端（E2E）测试文件，专注于测试 **RealtimeWebsocketClient** 的完整 WebSocket 通信流程。该测试文件通过创建真实的本地 WebSocket 服务器来模拟后端服务，验证：

- WebSocket 连接的建立与会话初始化
- 双向消息流（客户端→服务器，服务器→客户端）
- 音频帧的发送与接收
- 会话事件的解析与分发
- 连接断开处理
- 并发发送/接收的线程安全
- 不同事件解析器版本（V1/RealtimeV2）的兼容性
- Handoff（任务移交）功能的特殊事件处理

这些测试确保了实时语音交互功能的稳定性和可靠性。

## 功能点目的

### 1. 会话创建与事件流测试 (`realtime_ws_e2e_session_create_and_event_flow`)
验证完整的会话生命周期：
- 客户端发送 `session.update` 初始化会话
- 服务器响应 `session.updated` 确认
- 客户端发送音频数据 (`input_audio_buffer.append`)
- 服务器返回音频输出 (`conversation.output_audio.delta`)

### 2. 并发发送与接收测试 (`realtime_ws_e2e_send_while_next_event_waits`)
验证在 `next_event()` 等待时，仍可以并发调用 `send_audio_frame()` 而不会阻塞。

### 3. 连接断开处理测试 (`realtime_ws_e2e_disconnected_emitted_once`)
验证当服务器发送 `Close` 帧时：
- 客户端正确检测连接关闭
- `next_event()` 返回 `None`（仅一次，不重复）

### 4. 未知事件忽略测试 (`realtime_ws_e2e_ignores_unknown_text_events`)
验证客户端能够：
- 忽略不识别的事件类型（如 `response.created`）
- 继续处理后续有效事件

### 5. RealtimeV2 Handoff 测试 (`realtime_ws_e2e_realtime_v2_parser_emits_handoff_requested`)
验证 RealtimeV2 解析器的特殊行为：
- 将 `conversation.item.done` + `function_call` 类型转换为 `HandoffRequested` 事件
- 正确解析 `call_id` 作为 `handoff_id`

## 具体技术实现

### 关键数据结构

```rust
// WebSocket 流类型别名
type RealtimeWsStream = tokio_tungstenite::WebSocketStream<tokio::net::TcpStream>;

// 会话配置
RealtimeSessionConfig {
    instructions: String,           // 后端提示词
    model: Option<String>,          // 模型名称
    session_id: Option<String>,     // 会话 ID
    event_parser: RealtimeEventParser,  // V1 或 RealtimeV2
    session_mode: RealtimeSessionMode,  // Conversational 或 Transcription
}

// 音频帧
RealtimeAudioFrame {
    data: String,                   // Base64 编码的音频数据
    sample_rate: u32,              // 采样率（如 48000）
    num_channels: u32,             // 声道数
    samples_per_channel: Option<u32>,
    item_id: Option<String>,
}
```

### WebSocket 测试服务器

```rust
async fn spawn_realtime_ws_server<Handler, Fut>(
    handler: Handler,
) -> (String, tokio::task::JoinHandle<()>)
where
    Handler: FnOnce(RealtimeWsStream) -> Fut + Send + 'static,
    Fut: Future<Output = ()> + Send + 'static,
{
    // 1. 绑定到随机端口
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap().to_string();

    // 2. 启动服务器任务
    let server = tokio::spawn(async move {
        let (stream, _) = listener.accept().await.unwrap();
        let ws = accept_async(stream).await.unwrap();  // WebSocket 握手
        handler(ws).await;
    });

    (addr, server)
}
```

### Provider 配置

```rust
fn test_provider(base_url: String) -> Provider {
    Provider {
        name: "test".to_string(),
        base_url,
        query_params: Some(HashMap::new()),
        headers: HeaderMap::new(),
        retry: RetryConfig {
            max_attempts: 1,
            base_delay: Duration::from_millis(1),
            retry_429: false,
            retry_5xx: false,
            retry_transport: false,
        },
        stream_idle_timeout: Duration::from_secs(5),
    }
}
```

### 典型测试流程

```rust
#[tokio::test]
async fn realtime_ws_e2e_session_create_and_event_flow() {
    // 1. 启动测试服务器
    let (addr, server) = spawn_realtime_ws_server(|mut ws| async move {
        // 2. 验证 session.update
        let first = ws.next().await.unwrap().unwrap().into_text().unwrap();
        let first_json: Value = serde_json::from_str(&first).unwrap();
        assert_eq!(first_json["type"], "session.update");
        assert_eq!(first_json["session"]["type"], "quicksilver");

        // 3. 发送 session.updated
        ws.send(Message::Text(json!({
            "type": "session.updated",
            "session": {"id": "sess_mock", "instructions": "backend prompt"}
        }).to_string().into())).await.unwrap();

        // 4. 验证音频发送
        let second = ws.next().await.unwrap().unwrap().into_text().unwrap();
        assert_eq!(second_json["type"], "input_audio_buffer.append");

        // 5. 发送音频输出
        ws.send(Message::Text(json!({
            "type": "conversation.output_audio.delta",
            "delta": "AQID",
            "sample_rate": 48000,
            "channels": 1
        }).to_string().into())).await.unwrap();
    }).await;

    // 6. 创建客户端并连接
    let client = RealtimeWebsocketClient::new(test_provider(format!("http://{addr}")));
    let connection = client.connect(RealtimeSessionConfig { ... }, ...).await.unwrap();

    // 7. 验证事件接收
    let created = connection.next_event().await.unwrap().unwrap();
    assert_eq!(created, RealtimeEvent::SessionUpdated { ... });

    // 8. 发送音频
    connection.send_audio_frame(RealtimeAudioFrame { ... }).await.unwrap();

    // 9. 验证音频事件
    let audio_event = connection.next_event().await.unwrap().unwrap();
    assert_eq!(audio_event, RealtimeEvent::AudioOut(...));

    // 10. 清理
    connection.close().await.unwrap();
    server.await.unwrap();
}
```

### 并发测试模式

```rust
let (send_result, next_result) = tokio::join!(
    async {
        tokio::time::timeout(
            Duration::from_millis(200),
            connection.send_audio_frame(...)
        ).await
    },
    connection.next_event()
);

// 验证发送不阻塞在 next_event 上
send_result.expect("send should not block on next_event").expect("send audio");
```

## 关键代码路径与文件引用

### 被测代码路径

1. **RealtimeWebsocketClient**
   - 文件：`codex-rs/codex-api/src/endpoint/realtime_websocket/methods.rs`
   - 关键方法：
     - `connect(config, extra_headers, default_headers)` - 建立连接
   - 关键内部函数：
     - `websocket_url_from_api_url()` - WebSocket URL 构建
     - `normalize_realtime_path()` - 路径规范化

2. **RealtimeWebsocketConnection**
   - 文件：`codex-rs/codex-api/src/endpoint/realtime_websocket/methods.rs`
   - 关键方法：
     - `next_event()` - 接收事件
     - `send_audio_frame()` - 发送音频
     - `close()` - 关闭连接

3. **事件解析**
   - 文件：`codex-rs/codex-api/src/endpoint/realtime_websocket/protocol.rs`
   - 关键函数：
     - `parse_realtime_event()` - 事件解析分发
   - 文件：`codex-rs/codex-api/src/endpoint/realtime_websocket/protocol_v1.rs`
   - 文件：`codex-rs/codex-api/src/endpoint/realtime_websocket/protocol_v2.rs`

4. **WebSocket 流管理**
   - 结构：`WsStream` - 内部 WebSocket 流包装
   - 命令通道：`WsCommand` - 发送/关闭命令

### 事件类型映射

| 服务器事件 | RealtimeEventParser::V1 | RealtimeEventParser::RealtimeV2 |
|-----------|------------------------|--------------------------------|
| `session.updated` | `SessionUpdated` | `SessionUpdated` |
| `conversation.output_audio.delta` | `AudioOut` | `AudioOut` |
| `conversation.item.done` + function_call | - | `HandoffRequested` |
| `conversation.input_transcript.delta` | `InputTranscriptDelta` | `InputTranscriptDelta` |
| `response.cancelled` | - | `ResponseCancelled` |

## 依赖与外部交互

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `tokio_tungstenite` | WebSocket 客户端/服务器实现 |
| `tokio::net::TcpListener` | TCP 监听 |
| `futures::SinkExt/StreamExt` | 异步流操作 |
| `serde_json` | JSON 序列化/反序列化 |

### WebSocket 协议细节

**客户端发送的消息类型：**
```json
{
  "type": "session.update",
  "session": {
    "type": "quicksilver",
    "instructions": "backend prompt",
    "audio": {
      "input": {
        "format": {"type": "audio/pcm", "rate": 24000}
      }
    }
  }
}
```

```json
{
  "type": "input_audio_buffer.append",
  "audio": "AQID"
}
```

**服务器发送的消息类型：**
```json
{
  "type": "session.updated",
  "session": {"id": "sess_mock", "instructions": "backend prompt"}
}
```

```json
{
  "type": "conversation.output_audio.delta",
  "delta": "AQID",
  "sample_rate": 48000,
  "channels": 1
}
```

### 内部模块依赖

```rust
use codex_api::RealtimeAudioFrame;
use codex_api::RealtimeEvent;
use codex_api::RealtimeEventParser;
use codex_api::RealtimeSessionConfig;
use codex_api::RealtimeSessionMode;
use codex_api::RealtimeWebsocketClient;
use codex_api::provider::Provider;
use codex_api::provider::RetryConfig;
use codex_protocol::protocol::RealtimeHandoffRequested;
```

## 风险、边界与改进建议

### 潜在风险

1. **端口冲突**
   - 使用 `127.0.0.1:0` 随机端口，但在高并发测试时仍可能冲突
   - 建议添加重试逻辑

2. **时序敏感**
   - 测试依赖特定的消息顺序
   - 网络延迟可能导致测试不稳定

3. **资源泄漏**
   - 如果测试 panic，服务器任务可能未正确清理
   - 建议添加 `Drop` 实现或作用域守卫

4. **TLS 未测试**
   - 测试仅使用 `ws://`（非加密）
   - 生产环境使用 `wss://`，行为可能有差异

### 边界情况

1. **大音频帧处理**
   - 测试使用小音频数据 `"AQID"`
   - 未测试大音频帧的分片处理

2. **快速重连**
   - 未测试连接断开后立即重连的场景

3. **并发事件风暴**
   - 未测试服务器发送大量事件的背压处理

4. **部分 JSON 消息**
   - WebSocket 可能将大 JSON 分片发送
   - 测试未覆盖这种边界情况

### 改进建议

1. **增加超时测试**
   ```rust
   #[tokio::test]
   async fn realtime_ws_e2e_handles_server_timeout() {
       // 验证服务器无响应时的超时处理
   }
   ```

2. **增加错误恢复测试**
   ```rust
   #[tokio::test]
   async fn realtime_ws_e2e_recovers_from_connection_reset() {
       // 验证连接重置后的恢复行为
   }
   ```

3. **增加压力测试**
   ```rust
   #[tokio::test]
   async fn realtime_ws_e2e_handles_high_frequency_events() {
       // 发送大量事件验证性能
   }
   ```

4. **增加 TLS 测试**
   - 使用自签名证书测试 `wss://` 连接

5. **资源管理改进**
   ```rust
   struct TestServerGuard {
       handle: JoinHandle<()>,
   }
   
   impl Drop for TestServerGuard {
       fn drop(&mut self) {
           self.handle.abort();
       }
   }
   ```

6. **日志验证**
   - 添加 `tracing` 捕获，验证关键日志输出

### 相关文件变更注意事项

- 修改 `RealtimeEvent` 枚举需要更新所有事件匹配测试
- 修改 WebSocket URL 构建逻辑需要更新 `websocket_url_from_api_url` 测试
- 修改事件解析器需要同步更新 V1/V2 的测试用例
- 修改音频格式配置需要更新 `session.update` 的验证逻辑

### 测试架构建议

考虑将测试服务器逻辑提取为可复用的测试工具：

```rust
// 建议新增：codex-rs/codex-api/tests/common/mod.rs
pub struct MockRealtimeServer {
    // 预配置的响应序列
    // 断言辅助方法
    // 自动清理
}
```
