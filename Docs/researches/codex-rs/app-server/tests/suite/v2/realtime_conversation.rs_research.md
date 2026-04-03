# realtime_conversation.rs 研究文档

## 场景与职责

本文件是 Codex App Server v2 API 的集成测试套件的一部分，专门测试**实时对话功能** (`thread/realtime/*`)。实时对话允许用户通过 WebSocket 与 AI 进行低延迟的语音/文本交互，支持流式音频输入输出。

测试场景覆盖：
1. **完整实时对话生命周期** - 启动、音频追加、文本追加、停止
2. **通知流验证** - 验证各种实时事件通知的正确发送
3. **功能开关控制** - 验证实时对话功能标志的生效

## 功能点目的

### 1. 实时对话生命周期管理
- **启动实时对话** (`thread/realtime/start`): 建立 WebSocket 连接，初始化会话
- **追加音频** (`thread/realtime/appendAudio`): 发送 Base64 编码的音频数据
- **追加文本** (`thread/realtime/appendText`): 发送文本输入
- **停止实时对话** (`thread/realtime/stop`): 优雅关闭连接

### 2. 事件通知系统
实时对话通过 Server-Sent Events (SSE) 风格的通知向客户端推送事件：
- `thread/realtime/started` - 实时对话已启动
- `thread/realtime/outputAudio/delta` - 音频输出数据块
- `thread/realtime/itemAdded` - 新消息项添加
- `thread/realtime/error` - 实时对话错误
- `thread/realtime/closed` - 实时对话关闭

### 3. 功能标志控制
- `realtime_conversation` 功能标志控制实时对话是否可用
- 当功能禁用时，API 应返回适当的错误

## 具体技术实现

### 关键流程

```
测试用例: realtime_conversation_streams_v2_notifications
1. 创建 mock Responses API 服务器
2. 创建 mock WebSocket 实时服务器 (返回模拟事件序列)
3. 配置 config.toml 启用实时对话功能
4. 启动线程 (thread/start)
5. 启动实时对话 (thread/realtime/start)
6. 验证收到 thread/realtime/started 通知
7. 追加音频数据 (thread/realtime/appendAudio)
8. 追加文本输入 (thread/realtime/appendText)
9. 验证收到各种通知 (outputAudio/delta, itemAdded, error, closed)
10. 验证 WebSocket 请求序列正确
```

### 核心数据结构

```rust
// 启动实时对话
ThreadRealtimeStartParams {
    thread_id: String,
    prompt: String,           // 系统提示/上下文
    session_id: Option<String>, // 可选会话 ID
}

// 音频数据块
ThreadRealtimeAudioChunk {
    data: String,             // Base64 编码音频
    sample_rate: u32,         // 采样率 (如 24000)
    num_channels: u8,         // 通道数
    samples_per_channel: Option<u32>,
    item_id: Option<String>,
}

ThreadRealtimeAppendAudioParams {
    thread_id: String,
    audio: ThreadRealtimeAudioChunk,
}

// 文本追加
ThreadRealtimeAppendTextParams {
    thread_id: String,
    text: String,
}
```

### WebSocket 协议映射

| 客户端请求 | WebSocket 消息类型 | 说明 |
|-----------|-------------------|------|
| `thread/realtime/start` | `session.update` | 初始化会话配置 |
| `thread/realtime/appendAudio` | `input_audio_buffer.append` | 音频输入 |
| `thread/realtime/appendText` | `conversation.item.create` | 文本输入 |
| - | `response.create` | 触发响应生成 |

| 服务器通知 | WebSocket 事件类型 | 说明 |
|-----------|-------------------|------|
| `thread/realtime/started` | `session.updated` | 会话已更新 |
| `thread/realtime/outputAudio/delta` | `response.output_audio.delta` | 音频输出 |
| `thread/realtime/itemAdded` | `conversation.item.added` | 消息项添加 |
| `thread/realtime/error` | `error` | 错误事件 |
| `thread/realtime/closed` | - | 连接关闭 |

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/app-server/tests/suite/v2/realtime_conversation.rs` - 本测试文件

### 测试支持库
- `codex-rs/app-server/tests/common/mcp_process.rs`
  - `send_thread_realtime_start_request()` (行584)
  - `send_thread_realtime_append_audio_request()` (行594)
  - `send_thread_realtime_append_text_request()` (行604)
  - `send_thread_realtime_stop_request()` (行614)

- `codex-rs/core_test_support/src/responses.rs`
  - `start_websocket_server()` - WebSocket 测试服务器

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/common.rs`
  - `ThreadRealtimeStart => "thread/realtime/start"` (行366)
  - `ThreadRealtimeAppendAudio => "thread/realtime/appendAudio"` (行370)
  - `ThreadRealtimeAppendText => "thread/realtime/appendText"` (行374)
  - `ThreadRealtimeStop => "thread/realtime/stop"` (行379)
  - `ThreadRealtimeStarted => "thread/realtime/started"` (行922)
  - `ThreadRealtimeOutputAudioDelta => "thread/realtime/outputAudio/delta"` (行926)
  - `ThreadRealtimeClosed => "thread/realtime/closed"` (行929)

- `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `ThreadRealtimeStartParams` (行3709)
  - `ThreadRealtimeAudioChunk` (行3750)
  - `ThreadRealtimeStartedNotification` (行3770)
  - `ThreadRealtimeOutputAudioDeltaNotification` (行3787)

### 功能标志
- `codex-rs/core/src/features.rs`
  - `Feature::RealtimeConversation` - 功能标志定义

### 核心实现
- `codex-rs/core/src/realtime/` - 实时对话核心实现
- `codex-rs/app-server/src/codex_message_processor.rs` - 消息处理

## 依赖与外部交互

### 直接依赖
| 依赖 | 用途 |
|-----|------|
| `core_test_support::responses` | WebSocket 测试服务器 |
| `wiremock` | Responses API 模拟 |
| `tokio::time::timeout` | 异步超时控制 |
| `serde_json` | JSON 构造 |

### WebSocket 测试服务器配置
```rust
let realtime_server = start_websocket_server(vec![vec![
    vec![json!({"type": "session.updated", ...})],  // 第1批事件
    vec![],                                           // 第2批事件 (空)
    vec![                                             // 第3批事件
        json!({"type": "response.output_audio.delta", ...}),
        json!({"type": "conversation.item.added", ...}),
        json!({"type": "error", "message": "upstream boom"}),
    ],
]]).await;
```

### 配置示例
```toml
[realtime]
version = "v2"
type = "conversational"

[features]
realtime_conversation = true

[model_providers.mock_provider]
base_url = ".../v1"
wire_api = "responses"
```

### 网络检查
- 测试使用 `skip_if_no_network!` 宏跳过无网络环境
- 实时对话需要实际网络连接测试

## 风险、边界与改进建议

### 当前风险

1. **网络依赖**
   - 测试需要实际网络连接 (`skip_if_no_network!`)
   - 在无网络 CI 环境中被跳过，可能遗漏回归
   - 建议: 提供更完整的离线 Mock 模式

2. **时序敏感**
   - WebSocket 事件顺序对测试结果至关重要
   - 异步事件可能因调度产生 flaky 测试
   - 建议: 增加更宽松的事件顺序验证

3. **音频数据验证有限**
   - 仅验证 Base64 数据透传，不验证音频格式
   - 建议: 添加音频格式/采样率验证

### 边界情况

1. **WebSocket 连接失败**
   - 未测试连接失败后的重连逻辑
   - 建议: 添加连接失败和重试测试

2. **大数据块处理**
   - 未测试大音频数据块的分片传输
   - 建议: 添加大数据负载测试

3. **并发实时对话**
   - 未测试同一线程多个实时对话
   - 建议: 添加并发场景测试

4. **会话 ID 冲突**
   - 未测试重复使用 session_id 的行为
   - 建议: 添加会话 ID 管理测试

### 改进建议

1. **扩展测试覆盖**
   ```rust
   // 建议添加:
   - async fn realtime_conversation_handles_websocket_disconnect()  // 断线重连
   - async fn realtime_conversation_large_audio_chunks()  // 大数据块
   - async fn realtime_conversation_concurrent_sessions()  // 并发会话
   - async fn realtime_conversation_invalid_audio_format()  // 格式错误
   ```

2. **性能测试**
   - 测试音频延迟指标
   - 测试高频率音频追加的性能

3. **错误场景**
   - 后端返回错误时的客户端行为
   - 网络超时处理

4. **版本兼容性**
   - 测试 v1 和 v2 实时对话协议的差异
   - 版本协商逻辑

### 相关测试文件
- `codex-rs/app-server/tests/suite/v2/thread_start.rs` - 线程管理
- `codex-rs/core/tests/suite/realtime.rs` - 核心实时对话测试
