# Research: realtime_conversation.rs Test Suite

## 1. 场景与职责

### 1.1 文件定位
- **路径**: `codex-rs/core/tests/suite/realtime_conversation.rs`
- **类型**: 集成测试套件 (Integration Test Suite)
- **所属 Crate**: `codex-core` 测试模块

### 1.2 核心职责
该测试文件负责验证 **Realtime Conversation (实时对话)** 功能的完整生命周期，包括：

1. **WebSocket 连接管理**: 建立/关闭与 OpenAI Realtime API 的 WebSocket 连接
2. **音频流处理**: 双向音频数据传输 (输入/输出)
3. **文本交互**: 实时文本消息的收发
4. **会话生命周期**: 启动、运行、关闭、异常处理
5. **Handoff 机制**: 实时对话与标准对话模式之间的无缝切换
6. **启动上下文注入**: 自动注入线程历史、工作区信息作为会话上下文
7. **配置覆盖**: 支持实验性配置项的动态覆盖

### 1.3 测试场景概览
| 场景类别 | 描述 |
|---------|------|
| 基础流程 | 启动→音频输入→文本输入→关闭的完整闭环 |
| 认证场景 | API Key 回退、ChatGPT 认证集成 |
| 错误处理 | 预检失败、连接失败、非法操作顺序 |
| 会话管理 | 会话替换、多会话并发、传输层关闭 |
| 配置实验 | 基础URL覆盖、Prompt覆盖、启动上下文覆盖 |
| Handoff | 出站/入站切换、消息镜像、活动转录处理 |
| 边界条件 | 超长上下文截断、空上下文禁用 |

---

## 2. 功能点目的

### 2.1 Realtime Conversation 架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        Codex Core                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │         RealtimeConversationManager                     │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐ │   │
│  │  │  Audio In   │  │  Text In    │  │   Handoff Out   │ │   │
│  │  │   Queue     │  │   Queue     │  │     Queue       │ │   │
│  │  └──────┬──────┘  └──────┬──────┘  └────────┬────────┘ │   │
│  │         └─────────────────┴──────────────────┘          │   │
│  │                           │                             │   │
│  │                    ┌──────▼──────┐                      │   │
│  │                    │  Input Task │                      │   │
│  │                    │  (tokio)    │                      │   │
│  │                    └──────┬──────┘                      │   │
│  │                           │ WebSocket                   │   │
│  └───────────────────────────┼─────────────────────────────┘   │
│                              │                                  │
└──────────────────────────────┼──────────────────────────────────┘
                               │
                    ┌──────────▼──────────┐
                    │  OpenAI Realtime API │
                    │    (WebSocket)       │
                    └─────────────────────┘
```

### 2.2 关键功能点

#### 2.2.1 会话启动 (Conversation Start)
- **目的**: 建立 WebSocket 连接并初始化 Realtime 会话
- **关键参数**:
  - `prompt`: 后端指令/系统提示词
  - `session_id`: 可选会话标识 (用于恢复或关联)
- **配置项**:
  - `experimental_realtime_ws_base_url`: 覆盖默认 API 端点
  - `experimental_realtime_ws_backend_prompt`: 覆盖 Prompt
  - `experimental_realtime_ws_startup_context`: 自定义启动上下文

#### 2.2.2 音频处理
- **输入**: Base64 编码的 PCM 音频帧 (`RealtimeAudioFrame`)
- **输出**: 服务器返回的音频增量 (`conversation.output_audio.delta`)
- **格式**: 24kHz 采样率，单声道，16-bit PCM

#### 2.2.3 Handoff 机制
- **出站 Handoff**: Realtime 检测到需要工具调用时，将控制权移交标准对话
- **入站 Handoff**: 标准对话完成后，将结果返回 Realtime
- **消息镜像**: Assistant 消息自动同步到 Realtime 会话

#### 2.2.4 启动上下文构建
自动收集并注入以下信息作为会话启动上下文：
- 当前线程最近的用户/助手对话轮次
- 最近工作历史 (基于 State DB 的线程元数据)
- 工作区目录结构 (Git Root、当前目录、用户根目录)
- Token 预算控制 (默认 5000 tokens)

---

## 3. 具体技术实现

### 3.1 核心数据结构

#### 3.1.1 Protocol 层定义 (`codex-protocol/src/protocol.rs`)

```rust
// 操作指令
pub enum Op {
    RealtimeConversationStart(ConversationStartParams),
    RealtimeConversationAudio(ConversationAudioParams),
    RealtimeConversationText(ConversationTextParams),
    RealtimeConversationClose,
    // ...
}

// 启动参数
pub struct ConversationStartParams {
    pub prompt: String,
    pub session_id: Option<String>,
}

// 音频帧
pub struct RealtimeAudioFrame {
    pub data: String,              // Base64 编码
    pub sample_rate: u32,          // 通常为 24000
    pub num_channels: u16,         // 通常为 1
    pub samples_per_channel: Option<u32>,
    pub item_id: Option<String>,
}

// Realtime 事件
pub enum RealtimeEvent {
    SessionUpdated { session_id: String, instructions: Option<String> },
    InputAudioSpeechStarted(RealtimeInputAudioSpeechStarted),
    InputTranscriptDelta(RealtimeTranscriptDelta),
    OutputTranscriptDelta(RealtimeTranscriptDelta),
    AudioOut(RealtimeAudioFrame),
    ResponseCancelled(RealtimeResponseCancelled),
    ConversationItemAdded(Value),
    ConversationItemDone { item_id: String },
    HandoffRequested(RealtimeHandoffRequested),
    Error(String),
}

// 事件消息
pub enum EventMsg {
    RealtimeConversationStarted(RealtimeConversationStartedEvent),
    RealtimeConversationRealtime(RealtimeConversationRealtimeEvent),
    RealtimeConversationClosed(RealtimeConversationClosedEvent),
    // ...
}
```

#### 3.1.2 Core 层实现 (`codex-core/src/realtime_conversation.rs`)

```rust
// 会话管理器
pub(crate) struct RealtimeConversationManager {
    state: Mutex<Option<ConversationState>>,
}

// 会话状态
struct ConversationState {
    audio_tx: Sender<RealtimeAudioFrame>,
    user_text_tx: Sender<String>,
    writer: RealtimeWebsocketWriter,
    handoff: RealtimeHandoffState,
    input_task: JoinHandle<()>,
    fanout_task: Option<JoinHandle<()>>,
    realtime_active: Arc<AtomicBool>,
}

// Handoff 状态
struct RealtimeHandoffState {
    output_tx: Sender<HandoffOutput>,
    active_handoff: Arc<Mutex<Option<String>>>,
    last_output_text: Arc<Mutex<Option<String>>>,
    session_kind: RealtimeSessionKind,
}

// Handoff 输出类型
enum HandoffOutput {
    ImmediateAppend { handoff_id: String, output_text: String },
    FinalToolCall { handoff_id: String, output_text: String },
}
```

### 3.2 关键流程

#### 3.2.1 会话启动流程

```
Op::RealtimeConversationStart
         │
         ▼
┌─────────────────────┐
│   handle_start()    │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐     ┌─────────────────────┐
│ prepare_realtime_   │────▶│  realtime_api_key() │
│     start()         │     │  (认证信息获取)      │
└──────────┬──────────┘     └─────────────────────┘
           │
           ▼
┌─────────────────────┐     ┌─────────────────────┐
│ build_realtime_     │────▶│  加载最近线程历史    │
│ startup_context()   │     │  扫描工作区结构      │
└──────────┬──────────┘     └─────────────────────┘
           │
           ▼
┌─────────────────────┐
│ conversation.start()│◀── WebSocket 连接建立
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ spawn_realtime_     │◀── 启动输入处理任务
│ input_task()        │
└─────────────────────┘
```

#### 3.2.2 输入处理循环

```rust
// spawn_realtime_input_task 中的核心循环
loop {
    tokio::select! {
        // 用户文本输入
        text = user_text_rx.recv() => {
            writer.send_conversation_item_create(text).await?;
            if session_kind == V2 && !response_in_progress {
                writer.send_response_create().await?;
            }
        }
        
        // Handoff 输出
        handoff_output = handoff_output_rx.recv() => {
            match handoff_output {
                ImmediateAppend { handoff_id, output_text } => {
                    writer.send_conversation_handoff_append(handoff_id, output_text).await?;
                }
                FinalToolCall { handoff_id, output_text } => {
                    writer.send_conversation_handoff_append(handoff_id, output_text).await?;
                    if session_kind == V2 {
                        writer.send_response_create().await?;
                    }
                }
            }
        }
        
        // WebSocket 事件
        event = events.next_event() => {
            match event {
                RealtimeEvent::HandoffRequested(handoff) => {
                    *active_handoff.lock().await = Some(handoff.handoff_id.clone());
                    // 触发标准对话流程
                    sess.route_realtime_text_input(text).await;
                }
                RealtimeEvent::AudioOut(frame) => {
                    // 转发音频到客户端
                    events_tx.send(event).await?;
                }
                // ... 其他事件处理
            }
        }
        
        // 音频输入
        frame = audio_rx.recv() => {
            writer.send_audio_frame(frame).await?;
        }
    }
}
```

### 3.3 协议交互

#### 3.3.1 WebSocket 消息类型 (Client → Server)

| 消息类型 | 用途 | 测试覆盖 |
|---------|------|---------|
| `session.update` | 更新会话配置/指令 | ✅ `conversation_start_audio_text_close_round_trip` |
| `input_audio_buffer.append` | 发送音频数据 | ✅ `conversation_start_audio_text_close_round_trip` |
| `conversation.item.create` | 创建文本消息 | ✅ `conversation_start_audio_text_close_round_trip` |
| `conversation.handoff.append` | 追加 Handoff 结果 | ✅ `conversation_mirrors_assistant_message_text_to_realtime_handoff` |
| `response.create` | 触发模型响应 (V2) | ✅ `conversation_second_start_replaces_runtime` |
| `conversation.item.truncate` | 截断音频输出 | ✅ V2 会话类型测试 |

#### 3.3.2 WebSocket 事件类型 (Server → Client)

| 事件类型 | 用途 | 测试覆盖 |
|---------|------|---------|
| `session.updated` | 会话配置确认 | ✅ 所有启动测试 |
| `conversation.output_audio.delta` | 音频输出增量 | ✅ `conversation_start_audio_text_close_round_trip` |
| `conversation.item.added` | 消息项添加通知 | ✅ `conversation_start_audio_text_close_round_trip` |
| `conversation.input_transcript.delta` | 输入转录增量 | ✅ `inbound_handoff_request_uses_active_transcript` |
| `conversation.output_transcript.delta` | 输出转录增量 | ✅ `inbound_handoff_request_uses_active_transcript` |
| `conversation.handoff.requested` | Handoff 请求 | ✅ `conversation_mirrors_assistant_message_text_to_realtime_handoff` |
| `conversation.item.done` | 消息项完成 | ✅ `conversation_handoff_persists_across_item_done_until_turn_complete` |
| `error` | 错误通知 | ✅ `conversation_start_preflight_failure_emits_realtime_error_only` |

---

## 4. 关键代码路径与文件引用

### 4.1 核心实现文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/src/realtime_conversation.rs` | Realtime 会话管理器实现 |
| `codex-rs/core/src/realtime_context.rs` | 启动上下文构建逻辑 |
| `codex-rs/protocol/src/protocol.rs` | 协议类型定义 (Op/EventMsg) |
| `codex-rs/api/src/realtime_websocket.rs` | WebSocket 客户端实现 |

### 4.2 测试支持文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/tests/common/responses.rs` | WebSocket 测试服务器 (`start_websocket_server`) |
| `codex-rs/core/tests/common/test_codex.rs` | 测试 Codex 实例构建器 |
| `codex-rs/core/tests/common/streaming_sse.rs` | 流式 SSE 测试服务器 |
| `codex-rs/core/tests/common/lib.rs` | 测试工具宏 (`skip_if_no_network!`) |

### 4.3 关键代码引用

#### 4.3.1 测试文件中的辅助函数

```rust
// realtime_conversation.rs:44-58
// WebSocket 请求内容提取辅助函数
fn websocket_request_text(request: &WebSocketRequest) -> Option<String>;
fn websocket_request_instructions(request: &WebSocketRequest) -> Option<String>;

// realtime_conversation.rs:60-86
// 等待匹配的 WebSocket 请求
async fn wait_for_matching_websocket_request<F>(...) -> WebSocketRequest;

// realtime_conversation.rs:88-113
// 子进程测试执行 (用于隔离环境变量)
fn run_realtime_conversation_test_in_subprocess(test_name: &str, ...) -> Result<()>;

// realtime_conversation.rs:114-139
// 种子线程历史数据
async fn seed_recent_thread(...) -> Result<()>;
```

#### 4.3.2 测试服务器使用

```rust
// 启动 WebSocket 测试服务器
let server = start_websocket_server(vec![
    vec![],  // 第一个连接: 握手
    vec![    // 第二个连接: 会话事件序列
        vec![json!({"type": "session.updated", ...})],
        vec![json!({"type": "conversation.output_audio.delta", ...})],
    ],
]).await;

// 构建测试实例
let mut builder = test_codex();
let test = builder.build_with_websocket_server(&server).await?;

// 提交操作
test.codex.submit(Op::RealtimeConversationStart(...)).await?;

// 等待事件
let event = wait_for_event_match(&test.codex, |msg| match msg {
    EventMsg::RealtimeConversationStarted(started) => Some(started.clone()),
    _ => None,
}).await;
```

---

## 5. 依赖与外部交互

### 5.1 外部依赖

| 依赖 | 用途 |
|-----|------|
| `tokio` | 异步运行时、WebSocket 任务 |
| `tokio-tungstenite` | WebSocket 服务器 (测试) |
| `wiremock` | HTTP Mock 服务器 |
| `serde_json` | JSON 序列化/反序列化 |
| `base64` | 音频数据编码 |
| `chrono` | 时间戳处理 |
| `async-channel` | 异步消息队列 |

### 5.2 内部模块依赖

```
realtime_conversation.rs (test)
    │
    ├── codex_core::realtime_conversation (被测模块)
    │       ├── codex_api::RealtimeWebsocketClient
    │       ├── codex_protocol::protocol::* (协议类型)
    │       └── crate::realtime_context (上下文构建)
    │
    ├── core_test_support::responses (测试服务器)
    │       ├── WebSocketTestServer
    │       ├── start_websocket_server()
    │       └── start_streaming_sse_server()
    │
    └── core_test_support::test_codex (测试框架)
            ├── TestCodexBuilder
            └── test_codex()
```

### 5.3 环境依赖

| 环境变量 | 用途 |
|---------|------|
| `CODEX_SANDBOX_NETWORK_DISABLED` | 网络禁用检测 (跳过测试) |
| `CODEX_REALTIME_CONVERSATION_TEST_SUBPROCESS` | 子进程测试标识 |
| `OPENAI_API_KEY` | API 密钥回退测试 |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 网络依赖风险
- **风险**: 所有测试依赖网络连接 (WebSocket)
- **缓解**: `skip_if_no_network!` 宏在沙箱环境中自动跳过
- **潜在问题**: CI 环境网络不稳定可能导致 flaky 测试

#### 6.1.2 时间敏感测试
- **风险**: `conversation_transport_close_emits_closed_event` 依赖服务器关闭时机
- **缓解**: 使用 `wait_for_event_match` 而非固定延迟

#### 6.1.3 子进程测试复杂性
- **风险**: 环境变量隔离测试使用子进程，增加调试难度
- **文件**: `conversation_start_uses_openai_env_key_fallback_with_chatgpt_auth`

### 6.2 边界条件

| 边界条件 | 测试覆盖 | 处理方式 |
|---------|---------|---------|
| 超长启动上下文 (>20KB) | ✅ `conversation_startup_context_is_truncated_and_sent_once_per_start` | 截断至 20KB |
| 空启动上下文 | ✅ `conversation_disables_realtime_startup_context_with_empty_override` | 禁用上下文注入 |
| 会话替换 | ✅ `conversation_second_start_replaces_runtime` | 优雅关闭旧会话 |
| 音频输入前未启动 | ✅ `conversation_audio_before_start_emits_error` | 返回 `BadRequest` 错误 |
| 并发 Handoff + 音频 | ✅ `inbound_handoff_request_does_not_block_realtime_event_forwarding` | 非阻塞事件转发 |

### 6.3 改进建议

#### 6.3.1 测试可维护性
1. **提取公共模式**: 多个测试使用相似的 WebSocket 事件序列，可考虑提取 fixture
2. **增强断言信息**: 部分断言失败时难以定位具体事件序列位置
3. **文档化测试意图**: 复杂 Handoff 测试需要更多注释说明预期行为

#### 6.3.2 覆盖率提升
1. **V2 协议测试**: 当前 V1 覆盖较全，V2 (`RealtimeSessionKind::V2`) 测试相对较少
2. **错误恢复**: 网络中断后的重连逻辑测试不足
3. **并发场景**: 多线程并发提交操作的边界测试

#### 6.3.3 性能优化
1. **测试执行时间**: 部分测试使用 `Duration::from_secs(10)` 超时，可考虑分级超时策略
2. **资源清理**: 确保所有测试正确调用 `server.shutdown().await`

#### 6.3.4 架构建议
1. **协议版本协商**: 建议增加自动协议版本检测，减少配置负担
2. **上下文注入策略**: 可考虑更细粒度的上下文控制 (如按会话类型)
3. **可观测性**: 增加 Realtime 会话状态机的事件追踪

---

## 7. 附录

### 7.1 测试列表 (22 个)

| # | 测试名称 | 类别 | 关键验证点 |
|---|---------|------|-----------|
| 1 | `conversation_start_audio_text_close_round_trip` | 基础流程 | 完整生命周期 |
| 2 | `conversation_start_uses_openai_env_key_fallback_with_chatgpt_auth` | 认证 | 环境变量回退 |
| 3 | `conversation_transport_close_emits_closed_event` | 生命周期 | 传输关闭事件 |
| 4 | `conversation_audio_before_start_emits_error` | 错误处理 | 非法操作顺序 |
| 5 | `conversation_start_preflight_failure_emits_realtime_error_only` | 错误处理 | 预检失败 |
| 6 | `conversation_start_connect_failure_emits_realtime_error_only` | 错误处理 | 连接失败 |
| 7 | `conversation_text_before_start_emits_error` | 错误处理 | 非法操作顺序 |
| 8 | `conversation_second_start_replaces_runtime` | 会话管理 | 会话替换 |
| 9 | `conversation_uses_experimental_realtime_ws_base_url_override` | 配置 | URL 覆盖 |
| 10 | `conversation_uses_experimental_realtime_ws_backend_prompt_override` | 配置 | Prompt 覆盖 |
| 11 | `conversation_uses_experimental_realtime_ws_startup_context_override` | 配置 | 上下文覆盖 |
| 12 | `conversation_disables_realtime_startup_context_with_empty_override` | 配置 | 禁用上下文 |
| 13 | `conversation_start_injects_startup_context_from_thread_history` | 上下文 | 历史注入 |
| 14 | `conversation_startup_context_falls_back_to_workspace_map` | 上下文 | 工作区回退 |
| 15 | `conversation_startup_context_is_truncated_and_sent_once_per_start` | 上下文 | 截断逻辑 |
| 16 | `conversation_mirrors_assistant_message_text_to_realtime_handoff` | Handoff | 消息镜像 |
| 17 | `conversation_handoff_persists_across_item_done_until_turn_complete` | Handoff | 跨项持久化 |
| 18 | `inbound_handoff_request_starts_turn` | Handoff | 入站触发 |
| 19 | `inbound_handoff_request_uses_active_transcript` | Handoff | 活动转录 |
| 20 | `inbound_handoff_request_clears_active_transcript_after_each_handoff` | Handoff | 转录清理 |
| 21 | `inbound_conversation_item_does_not_start_turn_and_still_forwards_audio` | Handoff | 非阻塞音频 |
| 22 | `delegated_turn_user_role_echo_does_not_redelegate_and_still_forwards_audio` | Handoff | 防循环 |
| 23 | `inbound_handoff_request_does_not_block_realtime_event_forwarding` | Handoff | 并发处理 |
| 24 | `inbound_handoff_request_steers_active_turn` | Handoff | 活动轮次控制 |
| 25 | `inbound_handoff_request_starts_turn_and_does_not_block_realtime_audio` | Handoff | 音频非阻塞 |

### 7.2 相关配置项

```rust
// Config 中的 Realtime 相关配置
pub struct Config {
    // 实验性配置
    pub experimental_realtime_ws_base_url: Option<String>,
    pub experimental_realtime_ws_backend_prompt: Option<String>,
    pub experimental_realtime_ws_startup_context: Option<String>,
    pub experimental_realtime_ws_model: Option<String>,
    
    // 正式配置
    pub realtime: RealtimeConfig,
}

pub struct RealtimeConfig {
    pub version: RealtimeWsVersion,  // V1 or V2
    pub session_type: RealtimeWsMode, // Conversational or Transcription
}
```

---

*文档生成时间: 2026-03-23*
*基于代码版本: codex-rs/main*
