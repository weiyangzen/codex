# realtime_conversation.rs 研究文档

## 场景与职责

`realtime_conversation.rs` 是 Codex 实时对话（Realtime Conversation）功能的核心实现模块。它负责管理与 OpenAI Realtime API 的 WebSocket 连接，处理音频输入/输出、文本输入、handoff 机制，以及实时事件的扇出（fanout）处理。

该模块是 Codex 实时语音交互功能的基础设施，支持两种会话模式：
- **V1 模式**：基础实时对话
- **V2 模式**：增强版实时对话，支持更复杂的响应管理和音频截断

核心职责包括：
- WebSocket 连接生命周期管理
- 音频帧的接收和转发
- 文本输入的处理和响应创建
- Handoff 机制（从实时模式切换到文本模式）
- 实时事件的解析、处理和扇出

## 功能点目的

### 1. 会话管理 (`RealtimeConversationManager`)
作为实时对话的状态管理器：
- 维护 WebSocket 连接状态
- 管理输入/输出队列（音频、文本、handoff）
- 协调输入任务和扇出任务的生命周期
- 提供优雅关闭和紧急中止机制

### 2. 会话启动流程
处理从配置到 WebSocket 连接的完整启动流程：
- 准备会话配置（模型、指令、会话模式）
- 构建启动上下文（调用 `realtime_context` 模块）
- 建立 WebSocket 连接
- 启动输入处理任务和事件扇出任务

### 3. 输入处理 (`spawn_realtime_input_task`)
在独立任务中处理所有输入源：
- **用户文本输入**：转换为对话项并触发响应创建
- **音频输入**：转发音频帧到 WebSocket
- **Handoff 输出**：从文本模式接收的输出转回实时会话
- **实时事件**：处理来自 WebSocket 的事件流

### 4. Handoff 机制
支持从实时对话到文本模式的无缝切换：
- V1 模式：立即追加模式，实时输出直接路由到文本输入
- V2 模式：最终工具调用模式，handoff 完成后发送最终响应

### 5. 音频状态管理（V2 模式）
跟踪音频输出状态以支持语音打断：
- 记录当前播放音频的 `item_id` 和 `audio_end_ms`
- 当检测到用户语音开始时，发送截断命令

## 具体技术实现

### 核心数据结构

```rust
// 会话管理器
pub(crate) struct RealtimeConversationManager {
    state: Mutex<Option<ConversationState>>,
}

// 会话状态
#[allow(dead_code)]
struct ConversationState {
    audio_tx: Sender<RealtimeAudioFrame>,      // 音频输入通道
    user_text_tx: Sender<String>,              // 文本输入通道
    writer: RealtimeWebsocketWriter,           // WebSocket 写入器
    handoff: RealtimeHandoffState,             // Handoff 状态
    input_task: JoinHandle<()>,                // 输入处理任务
    fanout_task: Option<JoinHandle<()>>,       // 事件扇出任务
    realtime_active: Arc<AtomicBool>,          // 活动标志
}

// Handoff 状态
#[derive(Clone, Debug)]
struct RealtimeHandoffState {
    output_tx: Sender<HandoffOutput>,
    active_handoff: Arc<Mutex<Option<String>>>,    // 当前 handoff ID
    last_output_text: Arc<Mutex<Option<String>>>,  // 最后输出文本
    session_kind: RealtimeSessionKind,
}

// Handoff 输出类型
#[derive(Debug, PartialEq, Eq)]
enum HandoffOutput {
    ImmediateAppend { handoff_id: String, output_text: String },
    FinalToolCall { handoff_id: String, output_text: String },
}

// 音频输出状态（V2）
#[derive(Debug, PartialEq, Eq)]
struct OutputAudioState {
    item_id: String,
    audio_end_ms: u32,
}

// 输入任务参数
struct RealtimeInputTask {
    writer: RealtimeWebsocketWriter,
    events: RealtimeWebsocketEvents,
    user_text_rx: Receiver<String>,
    handoff_output_rx: Receiver<HandoffOutput>,
    audio_rx: Receiver<RealtimeAudioFrame>,
    events_tx: Sender<RealtimeEvent>,
    handoff_state: RealtimeHandoffState,
    session_kind: RealtimeSessionKind,
}
```

### 队列容量常量
```rust
const AUDIO_IN_QUEUE_CAPACITY: usize = 256;         // 音频输入队列
const USER_TEXT_IN_QUEUE_CAPACITY: usize = 64;      // 文本输入队列
const HANDOFF_OUT_QUEUE_CAPACITY: usize = 64;       // Handoff 输出队列
const OUTPUT_EVENTS_QUEUE_CAPACITY: usize = 256;    // 输出事件队列
const REALTIME_STARTUP_CONTEXT_TOKEN_BUDGET: usize = 5_000;  // 启动上下文预算
```

### 关键流程

#### 会话启动流程
```rust
pub(crate) async fn handle_start(
    sess: &Arc<Session>,
    sub_id: String,
    params: ConversationStartParams,
) -> CodexResult<()> {
    // 1. 准备启动参数
    let prepared_start = prepare_realtime_start(sess, params).await?;
    
    // 2. 内部启动处理
    handle_start_inner(sess, &sub_id, prepared_start).await
}

async fn prepare_realtime_start(
    sess: &Arc<Session>,
    params: ConversationStartParams,
) -> CodexResult<PreparedRealtimeConversationStart> {
    // 获取配置和认证
    let config = sess.get_config().await;
    let auth = sess.services.auth_manager.auth().await;
    let realtime_api_key = realtime_api_key(auth.as_ref(), &provider)?;
    
    // 构建启动上下文
    let startup_context = match config.experimental_realtime_ws_startup_context.clone() {
        Some(ctx) => ctx,
        None => build_realtime_startup_context(sess.as_ref(), REALTIME_STARTUP_CONTEXT_TOKEN_BUDGET)
            .await
            .unwrap_or_default(),
    };
    
    // 合并指令和上下文
    let prompt = if startup_context.is_empty() { prompt } else { format!("{prompt}\n\n{startup_context}") };
    
    // 创建会话配置
    let session_config = RealtimeSessionConfig {
        instructions: prompt,
        model,
        session_id: requested_session_id.clone(),
        event_parser: match version { ... },
        session_mode: match config.realtime.session_type { ... },
    };
    
    // 构建请求头
    let extra_headers = realtime_request_headers(requested_session_id.as_deref(), realtime_api_key.as_str())?;
}
```

#### 输入任务主循环
```rust
fn spawn_realtime_input_task(input: RealtimeInputTask) -> JoinHandle<()> {
    tokio::spawn(async move {
        let mut pending_response_create = false;
        let mut response_in_progress = false;
        let mut output_audio_state: Option<OutputAudioState> = None;
        
        loop {
            tokio::select! {
                // 处理用户文本输入
                text = user_text_rx.recv() => {
                    writer.send_conversation_item_create(text).await?;
                    if matches!(session_kind, RealtimeSessionKind::V2) {
                        if response_in_progress {
                            pending_response_create = true;  // 延迟响应
                        } else {
                            writer.send_response_create().await?;
                            response_in_progress = true;
                        }
                    }
                }
                
                // 处理 handoff 输出
                handoff_output = handoff_output_rx.recv() => {
                    match handoff_output {
                        HandoffOutput::ImmediateAppend { handoff_id, output_text } => {
                            writer.send_conversation_handoff_append(handoff_id, output_text).await?;
                        }
                        HandoffOutput::FinalToolCall { handoff_id, output_text } => {
                            writer.send_conversation_handoff_append(handoff_id, output_text).await?;
                            if matches!(session_kind, RealtimeSessionKind::V2) {
                                writer.send_response_create().await?;
                            }
                        }
                    }
                }
                
                // 处理实时事件
                event = events.next_event() => {
                    match &event {
                        RealtimeEvent::ConversationItemAdded(item) => {
                            match item.get("type").and_then(Value::as_str) {
                                Some("response.created") => response_in_progress = true,
                                Some("response.done") => {
                                    response_in_progress = false;
                                    if pending_response_create {
                                        writer.send_response_create().await?;
                                        pending_response_create = false;
                                        response_in_progress = true;
                                    }
                                }
                                _ => {}
                            }
                        }
                        RealtimeEvent::InputAudioSpeechStarted(event) => {
                            // V2 模式：截断正在播放的音频
                            if let Some(state) = output_audio_state.take() {
                                writer.send_payload(json!({
                                    "type": "conversation.item.truncate",
                                    "item_id": state.item_id,
                                    "content_index": 0,
                                    "audio_end_ms": state.audio_end_ms,
                                })).await?;
                            }
                        }
                        RealtimeEvent::HandoffRequested(handoff) => {
                            *handoff_state.active_handoff.lock().await = Some(handoff.handoff_id.clone());
                        }
                        _ => {}
                    }
                    events_tx.send(event).await?;
                }
                
                // 处理音频输入
                frame = audio_rx.recv() => {
                    writer.send_audio_frame(frame).await?;
                }
            }
        }
    })
}
```

#### 事件扇出处理
```rust
let fanout_task = tokio::spawn(async move {
    let mut end = RealtimeConversationEnd::TransportClosed;
    while let Ok(event) = events_rx.recv().await {
        if !fanout_realtime_active.load(Ordering::Relaxed) {
            break;
        }
        
        // 处理 handoff 路由
        let maybe_routed_text = match &event {
            RealtimeEvent::HandoffRequested(handoff) => {
                realtime_text_from_handoff_request(handoff)
            }
            _ => None,
        };
        if let Some(text) = maybe_routed_text {
            sess_for_routed_text.route_realtime_text_input(text).await;
        }
        
        // 发送事件到客户端
        sess_clone.send_event_raw(ev(EventMsg::RealtimeConversationRealtime(...))).await;
    }
    
    // 清理
    if fanout_realtime_active.swap(false, Ordering::Relaxed) {
        sess_clone.conversation.finish_if_active(&fanout_realtime_active).await;
        send_realtime_conversation_closed(&sess_clone, sub_id, end).await;
    }
});
```

### API 密钥解析
```rust
fn realtime_api_key(
    auth: Option<&CodexAuth>,
    provider: &crate::ModelProviderInfo,
) -> CodexResult<String> {
    // 优先级：配置 API Key > 实验性 Bearer Token > 认证 API Key > 环境变量
    if let Some(api_key) = provider.api_key()? {
        return Ok(api_key);
    }
    if let Some(token) = provider.experimental_bearer_token.clone() {
        return Ok(token);
    }
    if let Some(api_key) = auth.and_then(CodexAuth::api_key) {
        return Ok(api_key.to_string());
    }
    if provider.is_openai() && let Some(api_key) = read_openai_api_key_from_env() {
        return Ok(api_key);
    }
    Err(CodexErr::InvalidRequest("realtime conversation requires API key auth".to_string()))
}
```

## 关键代码路径与文件引用

### 主要入口点
| 函数 | 行号 | 用途 |
|-----|------|------|
| `handle_start()` | 407 | 处理会话启动请求 |
| `handle_audio()` | 600 | 处理音频输入 |
| `handle_text()` | 677 | 处理文本输入 |
| `handle_close()` | 694 | 处理会话关闭请求 |

### 内部实现
| 函数/结构 | 行号 | 用途 |
|----------|------|------|
| `RealtimeConversationManager` | 71 | 会话管理器结构 |
| `RealtimeConversationManager::start()` | 155 | 启动新会话 |
| `prepare_realtime_start()` | 450 | 准备启动参数 |
| `handle_start_inner()` | 508 | 内部启动逻辑 |
| `spawn_realtime_input_task()` | 698 | 输入处理任务 |
| `realtime_api_key()` | 628 | API 密钥解析 |
| `realtime_request_headers()` | 657 | 请求头构建 |
| `realtime_text_from_handoff_request()` | 616 | Handoff 文本提取 |
| `update_output_audio_state()` | 962 | 更新音频状态 |
| `audio_duration_ms()` | 987 | 计算音频时长 |

### 调用方引用
- `codex-rs/core/src/codex.rs:39-43` - 导入和调用实时对话处理函数

## 依赖与外部交互

### 内部模块依赖
```rust
use crate::CodexAuth;
use crate::api_bridge::map_api_error;
use crate::auth::read_openai_api_key_from_env;
use crate::codex::Session;
use crate::config::{RealtimeWsMode, RealtimeWsVersion};
use crate::default_client::default_headers;
use crate::error::{CodexErr, Result as CodexResult};
use crate::realtime_context::build_realtime_startup_context;
```

### 外部 crate 依赖
```rust
use async_channel::{Receiver, Sender, TrySendError};
use base64::Engine;
use codex_api::{RealtimeAudioFrame, RealtimeEvent, RealtimeSessionConfig, RealtimeWebsocketClient, ...};
use codex_protocol::protocol::{ConversationAudioParams, ConversationStartParams, ConversationTextParams, ...};
use http::{HeaderMap, HeaderValue, header::AUTHORIZATION};
use serde_json::{Value, json};
use tokio::sync::Mutex;
use tokio::task::JoinHandle;
```

### WebSocket 连接
通过 `codex_api::RealtimeWebsocketClient` 建立连接：
```rust
let client = RealtimeWebsocketClient::new(api_provider);
let connection = client.connect(session_config, extra_headers, default_headers()).await?;
let writer = connection.writer();
let events = connection.events();
```

## 风险、边界与改进建议

### 已知边界条件
1. **队列满处理**：音频队列满时丢弃帧（非阻塞），文本队列满时阻塞等待
2. **会话冲突**：启动新会话时自动停止旧会话
3. **响应冲突**：V2 模式下检测到 `active response` 错误时延迟响应创建
4. **音频截断**：仅在 V2 模式且 `item_id` 匹配时执行截断

### 潜在风险
1. **任务泄漏**：`fanout_task` 在异常情况下可能未被正确清理
2. **死锁风险**：多处使用 `Mutex` 和 `async_channel`，需警惕死锁
3. **内存增长**：事件队列在无消费者时可能无限增长（实际有容量限制）
4. **竞态条件**：`realtime_active` 原子标志与任务状态可能存在竞态

### 改进建议

#### 1. 错误处理增强
```rust
// 当前：简单记录错误并 break
Err(err) => {
    let mapped_error = map_api_error(err);
    warn!("failed to send input text: {mapped_error}");
    let _ = events_tx.send(RealtimeEvent::Error(mapped_error.to_string())).await;
    break;
}

// 建议：分类处理，部分错误可恢复
Err(err) => {
    match classify_error(&err) {
        ErrorClass::Recoverable => {
                            // 重试或继续
                        }
        ErrorClass::Fatal => {
                            // 通知上层并优雅关闭
                            shutdown_gracefully().await;
                            break;
                        }
    }
}
```

#### 2. 指标和可观测性
- 队列深度指标（audio_tx, user_text_tx, events_tx）
- 事件处理延迟直方图
- 会话持续时间统计
- Handoff 成功/失败率

#### 3. 配置化
```rust
// 当前：硬编码常量
const AUDIO_IN_QUEUE_CAPACITY: usize = 256;

// 建议：配置化
struct RealtimeConversationConfig {
    audio_queue_capacity: usize,
    text_queue_capacity: usize,
    startup_context_token_budget: usize,
    enable_v2_audio_truncation: bool,
}
```

#### 4. 测试覆盖
- 单元测试位于 `realtime_conversation_tests.rs`
- 当前覆盖：handoff 文本提取、handoff 状态管理
- 缺口：WebSocket 连接管理、音频状态跟踪、完整会话生命周期

#### 5. 代码结构优化
`spawn_realtime_input_task` 函数超过 250 行，建议拆分：
```rust
// 建议：拆分为子函数
impl RealtimeInputTask {
    async fn handle_user_text(&mut self, text: String) -> Result<(), Error>;
    async fn handle_handoff_output(&mut self, output: HandoffOutput) -> Result<(), Error>;
    async fn handle_realtime_event(&mut self, event: RealtimeEvent) -> Result<(), Error>;
    async fn handle_audio_frame(&mut self, frame: RealtimeAudioFrame) -> Result<(), Error>;
}
```

### 安全考虑
1. **API 密钥**：通过 Header 传递，需确保不记录到日志
2. **音频数据**：Base64 编码传输，注意内存使用
3. **输入验证**：对 `handoff_id` 和 `output_text` 长度应有限制
