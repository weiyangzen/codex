# methods.rs 研究文档

## 场景与职责

`methods.rs` 是 Codex Realtime WebSocket API 的核心实现文件，负责建立和管理与 OpenAI Realtime API 的 WebSocket 连接。它是实时语音对话功能的底层传输层，支持语音输入/输出、文本转录、会话管理等实时交互能力。

该模块在以下场景中使用：
- TUI (Terminal User Interface) 的语音模式
- App-server 的实时对话功能
- 需要低延迟语音交互的客户端应用

## 功能点目的

### 1. WebSocket 连接管理
- **目的**：建立和维护与 Realtime API 的持久 WebSocket 连接
- **功能**：支持 TLS/WSS 连接、自定义 CA 证书、连接状态管理

### 2. 双向消息传输
- **目的**：实现异步的双向通信（客户端↔服务器）
- **功能**：
  - 发送音频帧（Input Audio Buffer）
  - 发送文本消息（Conversation Item Create）
  - 接收服务器事件（音频输出、转录增量、会话更新等）
  - Handoff 消息处理（delegation 模式）

### 3. 事件解析与分发
- **目的**：将 WebSocket 原始消息解析为结构化事件
- **功能**：支持 V1 和 RealtimeV2 两种协议版本的事件解析

### 4. 活跃转录状态管理
- **目的**：维护对话过程中的输入/输出转录文本
- **功能**：合并连续的转录增量，构建完整的对话历史

## 具体技术实现

### 关键数据结构

```rust
// WebSocket 命令通道（内部使用）
enum WsCommand {
    Send { message: Message, tx_result: oneshot::Sender<Result<(), WsError>> },
    Close { tx_result: oneshot::Sender<Result<(), WsError>> },
}

// WebSocket 流包装器
struct WsStream {
    tx_command: mpsc::Sender<WsCommand>,
    pump_task: tokio::task::JoinHandle<()>,
}

// 活跃转录状态
struct ActiveTranscriptState {
    entries: Vec<RealtimeTranscriptEntry>,
}
```

### 核心流程

#### 1. 连接建立流程
```
RealtimeWebsocketClient::connect()
  ├── websocket_url_from_api_url()  // 构建 WS URL
  ├── merge_request_headers()       // 合并请求头
  ├── tokio_tungstenite::connect_async_tls_with_config()  // 建立连接
  ├── WsStream::new()               // 创建命令通道
  └── send_session_update()         // 发送初始会话配置
```

#### 2. 消息泵（Pump）循环
`WsStream::new()` 创建一个后台任务，使用 `tokio::select!` 同时处理：
- **命令接收**：处理 Send/Close 命令
- **消息接收**：处理服务器发来的消息
  - Ping/Pong：自动响应心跳
  - Text：解析为 RealtimeEvent
  - Binary：记录错误（ unexpected ）
  - Close：通知上层连接关闭

#### 3. 事件解析流程
```
RealtimeWebsocketEvents::next_event()
  ├── 从 rx_message 接收 Message
  ├── parse_realtime_event()      // 根据 parser 版本分发
  │   ├── parse_realtime_event_v1()   // V1 协议
  │   └── parse_realtime_event_v2()   // V2 协议
  └── update_active_transcript()  // 更新转录状态
```

#### 4. 转录增量合并算法
```rust
fn append_transcript_delta(entries: &mut Vec<RealtimeTranscriptEntry>, role: &str, delta: &str) {
    if let Some(last_entry) = entries.last_mut() && last_entry.role == role {
        last_entry.text.push_str(delta);  // 追加到同角色最后一条
    } else {
        entries.push(RealtimeTranscriptEntry { role: role.to_string(), text: delta.to_string() });
    }
}
```

### URL 构建规则

`websocket_url_from_api_url()` 处理多种 base URL 格式：
- `http://host` → `ws://host/v1/realtime`
- `https://host/v1` → `wss://host/v1/realtime`
- `wss://host/v1/realtime` → 保持不变

Query 参数处理：
- V1 协议：添加 `intent=quicksilver`
- V2 协议：不添加 intent（返回 `None`）
- 支持 model 参数传递
- 保留 provider 配置的额外 query 参数

## 关键代码路径与文件引用

### 内部模块依赖
```
methods.rs
├── methods_common.rs    # 版本无关的通用方法
├── methods_v1.rs        # V1 协议特定方法
├── methods_v2.rs        # V2 协议特定方法
├── protocol.rs          # 协议类型定义
├── protocol_common.rs   # 通用解析函数
├── protocol_v1.rs       # V1 事件解析
└── protocol_v2.rs       # V2 事件解析
```

### 外部依赖
- `tokio_tungstenite`: WebSocket 实现
- `codex_client::maybe_build_rustls_client_config_with_custom_ca`: TLS 配置
- `codex_protocol::protocol`: 共享协议类型（RealtimeEvent, RealtimeAudioFrame 等）

### 公开 API
```rust
pub struct RealtimeWebsocketClient { ... }
pub struct RealtimeWebsocketConnection { ... }
pub struct RealtimeWebsocketWriter { ... }
pub struct RealtimeWebsocketEvents { ... }
```

## 依赖与外部交互

### 与 Provider 的交互
- 使用 `Provider` 结构获取 base_url、headers、query_params
- 支持自定义请求头（包括 `x-session-id`）
- 继承 Provider 的 TLS 配置

### 与协议层的交互
- 通过 `RealtimeEventParser` 枚举选择解析器版本
- 调用 `parse_realtime_event()` 将 JSON 文本转换为 `RealtimeEvent`
- 使用 `methods_common/v1/v2` 构建版本特定的消息载荷

### 与上层（core/tui）的交互
- `RealtimeConversationManager` (core/src/realtime_conversation.rs) 使用此模块
- 通过 `RealtimeWebsocketConnection` 进行音频/文本发送和事件接收
- Handoff 机制支持将实时对话委托给普通 Codex 会话

## 风险、边界与改进建议

### 已知风险

1. **并发安全性**
   - `is_closed` 使用 `AtomicBool` 但非 lock-free，极端情况下可能有竞态
   - `active_transcript` 使用 `Mutex` 保护，但跨 await 点持有锁

2. **错误处理**
   - 二进制消息接收被视为错误，但仅记录日志不终止连接
   - WebSocket 错误转换为 `ApiError::Stream`，丢失原始错误细节

3. **资源泄漏**
   - `WsStream::Drop` 调用 `abort()` 可能留下未清理的 TLS 状态
   - 连接关闭时未显式等待 pump_task 完成

### 边界情况

1. **连接中断**
   - 服务器发送 Close 帧：正常结束，返回 `Ok(None)`
   - 网络断开：下次 `next_event()` 返回错误
   - 重复调用 `close()`：第二次返回 `Ok(())`（幂等）

2. **消息队列满**
   - 命令通道容量 32，满时 `send().await` 会阻塞
   - 未处理 `try_send` 失败情况（仅使用 `send`）

3. **协议版本差异**
   - V1 不支持 Transcription 模式（被强制转为 Conversational）
   - V2 支持两种模式，但配置差异大

### 改进建议

1. **可观测性**
   - 添加 metrics：连接建立时间、消息延迟、重连次数
   - 增加 span tracing 用于端到端调试

2. **健壮性**
   - 实现自动重连机制（指数退避）
   - 添加连接健康检查（定期 Ping）
   - 处理消息队列背压（丢弃旧音频帧而非阻塞）

3. **代码结构**
   - 将 `WsStream` 提取为独立模块，支持复用
   - 统一 V1/V2 的差异处理逻辑（当前分散在多个文件）
   - 添加协议版本协商机制（而非配置硬编码）

4. **测试覆盖**
   - 当前测试主要使用 mock server，缺少：
     - 网络分区场景测试
     - 高并发 send/recv 测试
     - TLS 证书验证测试
