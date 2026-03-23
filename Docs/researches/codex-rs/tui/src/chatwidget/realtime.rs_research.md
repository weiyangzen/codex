# realtime.rs 研究文档

## 场景与职责

`realtime.rs` 实现了 Codex TUI 的**实时语音对话**功能（Realtime Voice Conversation）。该功能允许用户通过语音与 Codex 进行实时对话，类似于 ChatGPT 的语音模式。

**核心职责**：
1. **实时会话生命周期管理**：启动、运行、停止实时语音会话
2. **音频设备管理**：麦克风输入捕获、扬声器输出播放
3. **UI 状态同步**：实时会话状态与 TUI 界面的同步
4. **音频行为控制**：支持传统模式和播放感知模式（Playback-Aware）

**平台限制**：
- 实时语音功能在 **Linux 平台不可用**（通过 `#[cfg(not(target_os = "linux"))]` 条件编译控制）
- 需要启用 `RealtimeConversation` 特性标志

## 功能点目的

### 1. 实时会话状态管理

**会话阶段 (`RealtimeConversationPhase`)**：
- `Inactive`：未激活
- `Starting`：正在启动
- `Active`：正在运行
- `Stopping`：正在停止

**目的**：管理实时会话的生命周期，确保状态转换的正确性。

### 2. 音频行为模式

**`RealtimeAudioBehavior`**：
- `Legacy`：传统模式，麦克风始终开启
- `PlaybackAware`：播放感知模式，在播放助手音频时自动抑制麦克风输入

**目的**：
- 减少助手播放时的回声干扰
- 提高语音对话的自然度

### 3. 用户消息渲染控制

**`RenderedUserMessageEvent`**：
- 存储用户消息的渲染状态
- 用于检测是否需要重新渲染（避免重复渲染相同内容）

**`PendingSteerCompareKey`**：
- 用于比较待处理的 steer（输入引导）
- 避免昂贵的序列化操作

### 4. 本地音频管理

**非 Linux 平台功能**：
- `VoiceCapture`：麦克风音频捕获
- `RealtimeAudioPlayer`：实时音频播放
- `RecordingMeterState`：录音电平指示器

## 具体技术实现

### 关键数据结构

#### 1. 会话阶段枚举

```rust
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(super) enum RealtimeConversationPhase {
    #[default]
    Inactive,
    Starting,
    Active,
    Stopping,
}
```

#### 2. UI 状态结构体

```rust
#[derive(Default)]
pub(super) struct RealtimeConversationUiState {
    pub(super) phase: RealtimeConversationPhase,
    #[cfg(not(target_os = "linux"))]
    audio_behavior: RealtimeAudioBehavior,
    requested_close: bool,
    session_id: Option<String>,
    warned_audio_only_submission: bool,
    #[cfg(not(target_os = "linux"))]
    pub(super) meter_placeholder_id: Option<String>,
    #[cfg(not(target_os = "linux"))]
    capture_stop_flag: Option<Arc<AtomicBool>>,
    #[cfg(not(target_os = "linux"))]
    capture: Option<crate::voice::VoiceCapture>,
    #[cfg(not(target_os = "linux"))]
    audio_player: Option<crate::voice::RealtimeAudioPlayer>,
    #[cfg(not(target_os = "linux"))]
    playback_queued_samples: Arc<AtomicUsize>,
}
```

**字段说明**：
- `phase`：当前会话阶段
- `audio_behavior`：音频行为模式（传统/播放感知）
- `requested_close`：用户是否请求关闭
- `session_id`：服务器分配的会话 ID
- `warned_audio_only_submission`：是否已警告过仅音频提交
- `meter_placeholder_id`：录音电平指示器的占位符 ID
- `capture_stop_flag`：捕获停止标志（用于线程间通信）
- `capture`：语音捕获实例
- `audio_player`：音频播放器实例
- `playback_queued_samples`：播放队列样本数（用于播放感知模式）

#### 3. 音频行为模式

```rust
#[cfg(not(target_os = "linux"))]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
enum RealtimeAudioBehavior {
    #[default]
    Legacy,
    PlaybackAware,
}

#[cfg(not(target_os = "linux"))]
impl RealtimeAudioBehavior {
    fn from_version(version: RealtimeConversationVersion) -> Self {
        match version {
            RealtimeConversationVersion::V1 => Self::Legacy,
            RealtimeConversationVersion::V2 => Self::PlaybackAware,
        }
    }

    fn input_behavior(self, playback_queued_samples: Arc<AtomicUsize>) -> crate::voice::RealtimeInputBehavior {
        match self {
            Self::Legacy => crate::voice::RealtimeInputBehavior::Ungated,
            Self::PlaybackAware => crate::voice::RealtimeInputBehavior::PlaybackAware {
                playback_queued_samples,
            },
        }
    }
}
```

### 核心流程

#### 1. 启动实时会话

```rust
pub(super) fn start_realtime_conversation(&mut self) {
    self.realtime_conversation.phase = RealtimeConversationPhase::Starting;
    self.realtime_conversation.requested_close = false;
    self.realtime_conversation.session_id = None;
    // ... 初始化其他字段
    
    self.submit_op(Op::RealtimeConversationStart(ConversationStartParams {
        prompt: REALTIME_CONVERSATION_PROMPT.to_string(),
        session_id: None,
    }));
}
```

**流程**：
1. 设置阶段为 `Starting`
2. 重置相关状态
3. 向核心层发送 `RealtimeConversationStart` 操作
4. 等待服务器响应

#### 2. 会话启动完成处理

```rust
pub(super) fn on_realtime_conversation_started(
    &mut self,
    ev: RealtimeConversationStartedEvent,
) {
    if !self.realtime_conversation_enabled() {
        self.request_realtime_conversation_close(/*info_message*/ None);
        return;
    }
    self.realtime_conversation.phase = RealtimeConversationPhase::Active;
    self.realtime_conversation.session_id = ev.session_id;
    #[cfg(not(target_os = "linux"))]
    {
        self.realtime_conversation.audio_behavior =
            RealtimeAudioBehavior::from_version(ev.version);
    }
    self.start_realtime_local_audio();
    self.request_redraw();
}
```

**流程**：
1. 检查功能是否启用
2. 更新阶段为 `Active`
3. 根据服务器版本设置音频行为
4. 启动本地音频设备

#### 3. 实时事件处理

```rust
pub(super) fn on_realtime_conversation_realtime(
    &mut self,
    ev: RealtimeConversationRealtimeEvent,
) {
    match ev.payload {
        RealtimeEvent::SessionUpdated { session_id, .. } => {
            self.realtime_conversation.session_id = Some(session_id);
        }
        RealtimeEvent::InputAudioSpeechStarted(_) | RealtimeEvent::ResponseCancelled(_) => {
            // 清除播放缓冲区，停止门控麦克风输入
            if let Some(player) = &self.realtime_conversation.audio_player {
                player.clear();
            }
        }
        RealtimeEvent::AudioOut(frame) => self.enqueue_realtime_audio_out(&frame),
        RealtimeEvent::Error(message) => {
            self.fail_realtime_conversation(format!("Realtime voice error: {message}"));
        }
        // ... 其他事件处理
    }
}
```

#### 4. 本地音频启动（非 Linux）

```rust
#[cfg(not(target_os = "linux"))]
fn start_realtime_local_audio(&mut self) {
    // 1. 插入录音电平占位符
    let placeholder_id = self.bottom_pane.insert_transcription_placeholder("⠤⠤⠤⠤");
    self.realtime_conversation.meter_placeholder_id = Some(placeholder_id.clone());

    // 2. 启动语音捕获
    let capture = match crate::voice::VoiceCapture::start_realtime(
        &self.config,
        self.app_event_tx.clone(),
        self.realtime_conversation.audio_behavior.input_behavior(...),
    ) { ... };

    // 3. 启动音频播放器
    self.realtime_conversation.audio_player = 
        crate::voice::RealtimeAudioPlayer::start(&self.config, ...).ok();

    // 4. 启动录音电平更新线程
    std::thread::spawn(move || {
        let mut meter = crate::voice::RecordingMeterState::new();
        loop {
            if stop_flag.load(Ordering::Relaxed) {
                break;
            }
            let meter_text = meter.next_text(peak.load(Ordering::Relaxed));
            app_event_tx.send(AppEvent::UpdateRecordingMeter { ... });
            std::thread::sleep(Duration::from_millis(60));
        }
    });
}
```

### 用户消息处理

#### 1. 实时模式下的用户消息处理

```rust
pub(super) fn maybe_defer_user_message_for_realtime(
    &mut self,
    user_message: UserMessage,
) -> Option<UserMessage> {
    if !self.realtime_conversation.is_live() {
        return Some(user_message);  // 非实时模式，正常处理
    }

    // 实时模式下，将消息恢复到输入框并提示用户
    self.restore_user_message_to_composer(user_message);
    if !self.realtime_conversation.warned_audio_only_submission {
        self.realtime_conversation.warned_audio_only_submission = true;
        self.add_info_message(
            "Realtime voice mode is audio-only. Use /realtime to stop.".to_string(),
            /*hint*/ None,
        );
    }
    None  // 阻止消息提交
}
```

**说明**：实时语音模式下，文本输入被禁用，用户需要通过语音交互。

## 关键代码路径与文件引用

### 本文件关键定义

| 定义 | 行号 | 说明 |
|------|------|------|
| `RealtimeConversationPhase` | 18-24 | 会话阶段枚举 |
| `RealtimeConversationUiState` | 27-46 | UI 状态结构体 |
| `RealtimeAudioBehavior` | 49-54 | 音频行为模式枚举 |
| `RenderedUserMessageEvent` | 95-100 | 渲染后的用户消息事件 |
| `PendingSteerCompareKey` | 103-106 | 待处理 steer 比较键 |
| `start_realtime_conversation` | 239-257 | 启动实时会话 |
| `request_realtime_conversation_close` | 259-278 | 请求关闭实时会话 |
| `on_realtime_conversation_started` | 303-325 | 会话启动完成回调 |
| `on_realtime_conversation_realtime` | 327-359 | 实时事件处理 |
| `start_realtime_local_audio` | 399-461 | 启动本地音频（非 Linux） |

### 调用方（在 chatwidget.rs 中）

| 代码位置 | 调用方式 | 用途 |
|---------|---------|------|
| `chatwidget.rs:806` | `realtime_conversation: RealtimeConversationUiState` | 状态存储 |
| `chatwidget.rs:1076` | `realtime_conversation_enabled()` | 检查功能启用 |
| `chatwidget.rs` | `start_realtime_conversation()` | 启动实时会话 |
| `chatwidget.rs` | `request_realtime_conversation_close(...)` | 关闭实时会话 |

### 依赖模块

| 模块 | 类型 | 用途 |
|------|------|------|
| `crate::voice` | 模块 | 语音捕获和播放 |
| `codex_protocol::protocol` | 协议 | 实时会话协议定义 |
| `crate::app_event::RealtimeAudioDeviceKind` | 枚举 | 音频设备类型 |

### 协议依赖

```rust
use codex_protocol::protocol::ConversationStartParams;
use codex_protocol::protocol::RealtimeAudioFrame;
use codex_protocol::protocol::RealtimeConversationClosedEvent;
use codex_protocol::protocol::RealtimeConversationRealtimeEvent;
use codex_protocol::protocol::RealtimeConversationStartedEvent;
use codex_protocol::protocol::RealtimeEvent;
```

## 依赖与外部交互

### 核心依赖

1. **`codex_protocol`**：
   - `RealtimeConversationStartedEvent`：会话启动事件
   - `RealtimeConversationRealtimeEvent`：实时事件（音频、转录等）
   - `RealtimeConversationClosedEvent`：会话关闭事件
   - `RealtimeAudioFrame`：音频帧数据
   - `Op::RealtimeConversationStart` / `Op::RealtimeConversationClose`：操作命令

2. **`crate::voice`**（非 Linux）：
   - `VoiceCapture::start_realtime()`：启动实时语音捕获
   - `RealtimeAudioPlayer::start()`：启动音频播放
   - `RecordingMeterState`：录音电平指示器
   - `RealtimeInputBehavior`：输入行为控制

3. **Tokio/Std 线程**：
   - `std::thread::spawn`：录音电平更新线程
   - `Arc<AtomicBool>`：线程间停止标志
   - `Arc<AtomicUsize>`：播放队列样本数共享

### 与 ChatWidget 的集成

`realtime.rs` 作为 `ChatWidget` 的 `impl` 块的一部分，直接访问：
- `self.realtime_conversation`：实时会话状态
- `self.submit_op()`：提交操作到核心层
- `self.bottom_pane`：底部面板控制
- `self.app_event_tx`：应用事件发送器
- `self.config`：配置对象

## 风险、边界与改进建议

### 风险点

1. **平台差异**：
   - Linux 平台功能完全缺失，代码分散大量 `#[cfg]` 条件编译
   - 维护成本高，容易出错

2. **线程安全**：
   - 录音电平更新使用 `std::thread` 而非 Tokio 任务
   - 使用原子变量进行线程间通信，可能存在竞态条件

3. **资源泄漏**：
   - 音频设备未正确关闭可能导致资源泄漏
   - `stop_realtime_local_audio` 需要确保所有资源被释放

4. **错误处理**：
   - 音频设备启动失败仅显示错误消息，缺乏恢复机制
   - `RealtimeAudioPlayer::start().ok()` 静默忽略错误

### 边界情况

1. **会话状态不一致**：
   - 网络断开时，UI 状态可能与服务器状态不一致
   - `requested_close` 标志用于区分用户主动关闭和异常关闭

2. **音频设备热插拔**：
   - 当前实现不支持音频设备的热插拔
   - 设备断开可能导致崩溃或无声

3. **多设备选择**：
   - `restart_realtime_audio_device` 支持麦克风和扬声器切换
   - 但需要在会话激活状态下才能调用

4. **Linux 平台**：
   - 所有音频相关函数为空实现
   - 需要确保上层调用不会 panic

### 改进建议

1. **统一平台抽象**：
   ```rust
   // 建议：创建一个跨平台的音频抽象层
   pub(crate) trait AudioBackend {
       fn start_capture(&self) -> Result<Box<dyn AudioCapture>, AudioError>;
       fn start_playback(&self) -> Result<Box<dyn AudioPlayback>, AudioError>;
   }
   ```

2. **增强错误恢复**：
   - 音频设备失败时自动重试或切换到默认设备
   - 提供更详细的错误信息给用户

3. **设备热插拔支持**：
   - 监听系统音频设备变化事件
   - 自动重新初始化音频设备

4. **资源管理优化**：
   ```rust
   // 建议：使用 RAII 模式管理音频资源
   struct RealtimeAudioSession {
       capture: Option<VoiceCapture>,
       player: Option<RealtimeAudioPlayer>,
   }
   
   impl Drop for RealtimeAudioSession {
       fn drop(&mut self) {
           self.stop();
       }
   }
   ```

5. **性能优化**：
   - 录音电平更新线程使用固定频率（60ms）轮询
   - 考虑使用条件变量或异步事件驱动

6. **测试覆盖**：
   - 当前缺乏实时语音功能的单元测试
   - 建议添加模拟音频设备的测试

7. **配置扩展**：
   - 支持用户配置音频设备选择
   - 支持调整音频质量参数（采样率、缓冲区大小等）
