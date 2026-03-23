# realtime.rs 研究文档

## 场景与职责

`realtime.rs` 是 Codex TUI App Server 中 `ChatWidget` 模块的子模块，负责实现**实时语音对话（Realtime Voice Conversation）**功能的 UI 状态管理。该功能允许用户通过语音与 Codex 进行实时对话，类似于 ChatGPT 的语音模式。

**核心职责**：
1. **实时对话生命周期管理**：管理从启动到结束的完整对话流程
2. **音频设备控制**：协调麦克风输入和扬声器输出（非 Linux 平台）
3. **实时事件处理**：处理来自后端的实时语音事件（音频流、转录、会话更新等）
4. **用户消息延迟处理**：在语音模式下延迟处理文本消息，提示用户使用音频

**平台限制**：
- 实时语音功能在 Linux 平台被禁用（`#[cfg(target_os = "linux")]`）
- 非 Linux 平台使用 `cpal` 库进行音频捕获和播放

## 功能点目的

### 1. 对话阶段管理 (`RealtimeConversationPhase`)

```rust
pub(super) enum RealtimeConversationPhase {
    Inactive,   // 未激活
    Starting,   // 正在启动
    Active,     // 活跃状态
    Stopping,   // 正在停止
}
```

管理实时对话的完整生命周期，确保状态转换的正确性。

### 2. UI 状态管理 (`RealtimeConversationUiState`)

维护实时对话的完整 UI 状态：
- `phase`: 当前对话阶段
- `requested_close`: 用户是否请求关闭
- `session_id`: 实时会话 ID
- `warned_audio_only_submission`: 是否已警告用户语音模式仅支持音频
- **非 Linux 平台特有**：
  - `meter_placeholder_id`: 录音电平指示器的占位符 ID
  - `capture_stop_flag`: 音频捕获停止标志
  - `capture`: 语音捕获实例
  - `audio_player`: 实时音频播放器

### 3. 用户消息渲染事件 (`RenderedUserMessageEvent`)

用于跟踪用户消息的渲染状态，避免重复渲染：
```rust
pub(super) struct RenderedUserMessageEvent {
    pub(super) message: String,
    pub(super) remote_image_urls: Vec<String>,
    pub(super) local_images: Vec<PathBuf>,
    pub(super) text_elements: Vec<TextElement>,
}
```

### 4. 待处理 Steer 比较键 (`PendingSteerCompareKey`)

用于比较待处理的用户输入，避免昂贵的序列化操作：
```rust
pub(super) struct PendingSteerCompareKey {
    pub(super) message: String,
    pub(super) image_count: usize,
}
```

## 具体技术实现

### 关键流程

#### 1. 启动实时对话 (`start_realtime_conversation`)

```rust
pub(super) fn start_realtime_conversation(&mut self) {
    // 1. 设置阶段为 Starting
    self.realtime_conversation.phase = RealtimeConversationPhase::Starting;
    // 2. 重置状态
    self.realtime_conversation.requested_close = false;
    self.realtime_conversation.session_id = None;
    self.realtime_conversation.warned_audio_only_submission = false;
    // 3. 设置底部提示覆盖
    self.set_footer_hint_override(Some(Self::realtime_footer_hint_items()));
    // 4. 发送启动命令到后端
    self.submit_op(AppCommand::realtime_conversation_start(...));
    self.request_redraw();
}
```

#### 2. 处理实时事件 (`on_realtime_conversation_realtime`)

处理来自后端的各类实时事件：

| 事件类型 | 处理逻辑 |
|---------|---------|
| `SessionUpdated` | 更新 session_id |
| `InputAudioSpeechStarted` | 中断当前音频播放（用户开始说话） |
| `InputTranscriptDelta` | 忽略（无需处理） |
| `OutputTranscriptDelta` | 忽略（无需处理） |
| `AudioOut` | 将音频帧加入播放队列 |
| `ResponseCancelled` | 中断音频播放 |
| `ConversationItemAdded` | 忽略 |
| `ConversationItemDone` | 忽略 |
| `HandoffRequested` | 忽略 |
| `Error` | 显示错误并关闭对话 |

#### 3. 本地音频管理（非 Linux）

**启动本地音频** (`start_realtime_local_audio`)：
1. 插入转录占位符（显示录音电平动画）
2. 启动 `VoiceCapture` 进行实时音频捕获
3. 创建音频播放器用于播放 AI 响应
4. 启动后台线程更新录音电平指示器

**停止本地音频** (`stop_realtime_local_audio`)：
1. 停止麦克风捕获
2. 停止扬声器播放
3. 清理占位符

#### 4. 用户消息延迟处理 (`maybe_defer_user_message_for_realtime`)

当用户在实时语音模式下尝试发送文本消息时：
1. 将消息恢复到输入框
2. 首次显示警告："Realtime voice mode is audio-only. Use /realtime to stop."
3. 后续仅请求重绘（不重复警告）
4. 返回 `None` 表示消息未被提交

### 音频设备重启

支持在实时对话中动态切换音频设备：
```rust
pub(crate) fn restart_realtime_audio_device(&mut self, kind: RealtimeAudioDeviceKind) {
    match kind {
        RealtimeAudioDeviceKind::Microphone => { /* 重启麦克风 */ },
        RealtimeAudioDeviceKind::Speaker => { /* 重启扬声器 */ },
    }
}
```

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/tui_app_server/src/chatwidget/realtime.rs` (463 行)

### 父模块
- `codex-rs/tui_app_server/src/chatwidget.rs`
  - 定义 `realtime_conversation: RealtimeConversationUiState` 字段
  - 定义 `last_rendered_user_message_event: Option<RenderedUserMessageEvent>` 字段

### 音频相关依赖
- `codex-rs/tui_app_server/src/voice.rs`
  - `VoiceCapture`: 语音捕获实现
  - `RealtimeAudioPlayer`: 实时音频播放
  - `RecordingMeterState`: 录音电平指示器状态

### 协议定义
- `codex-rs/protocol/src/protocol.rs`
  - `ConversationStartParams` (行 129-134)
  - `RealtimeAudioFrame` (行 136-145)
  - `RealtimeEvent` (行 176-193)
  - `RealtimeConversationStartedEvent`
  - `RealtimeConversationRealtimeEvent`
  - `RealtimeConversationClosedEvent`

### 应用命令
- `codex-rs/tui_app_server/src/app_command.rs`
  - `AppCommand::realtime_conversation_start`
  - `AppCommand::realtime_conversation_close`

### 应用事件
- `codex-rs/tui_app_server/src/app_event.rs`
  - `AppEvent::UpdateRecordingMeter`
  - `RealtimeAudioDeviceKind` (Microphone, Speaker)

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|-----|------|
| `std::time::Duration` | 音频线程睡眠间隔（非 Linux） |
| `std::sync::atomic::{AtomicBool, Ordering}` | 音频停止标志 |
| `codex_protocol::protocol::*` | 实时对话协议类型 |
| `crate::voice::*` | 音频捕获和播放（非 Linux） |
| `crate::app_command::AppCommand` | 向后端发送命令 |
| `crate::app_event::AppEvent` | 发送 UI 更新事件 |

### 与后端的交互
1. **启动**：发送 `realtime_conversation_start` 命令
2. **关闭**：发送 `realtime_conversation_close` 命令
3. **接收**：通过事件通道接收 `RealtimeConversationRealtimeEvent`

### 与 UI 的交互
1. **底部提示**：通过 `set_footer_hint_override` 显示 `/realtime` 快捷键
2. **录音指示器**：通过 `UpdateRecordingMeter` 事件更新录音电平
3. **消息显示**：通过 `add_info_message` / `add_error_message` 显示状态

## 风险、边界与改进建议

### 当前风险

1. **平台差异代码复杂**
   - 大量使用 `#[cfg(not(target_os = "linux"))]` 和 `#[cfg(target_os = "linux")]`
   - 容易导致代码维护困难和测试覆盖不足
   - 建议：考虑将平台相关代码抽象到单独的模块

2. **音频线程管理**
   - 录音电平更新使用 `std::thread::spawn` 创建后台线程
   - 线程 panic 可能导致状态不一致
   - 建议：使用 `tokio::task` 或添加线程错误处理

3. **音频设备错误处理**
   - 设备启动失败会导致整个实时对话失败
   - 建议：添加更细粒度的错误恢复，如自动重试或降级到文本模式

4. **会话 ID 管理**
   - `session_id` 可能在 `SessionUpdated` 事件到达前被使用
   - 建议：添加会话 ID 有效性检查

### 边界情况

1. **快速启动/停止**
   - 如果用户在启动过程中立即请求停止，需要正确处理中间状态
   - 当前实现通过 `requested_close` 标志处理

2. **音频设备热插拔**
   - 设备在对话过程中被拔出可能导致崩溃
   - 建议：添加设备状态监控和优雅降级

3. **网络中断**
   - 实时对话依赖 WebSocket 连接，网络中断需要恢复机制
   - 当前通过 `Error` 事件处理，但无自动重连

### 改进建议

1. **添加音频设备选择 UI**
   ```rust
   pub(crate) fn open_audio_device_selector(&mut self) {
       // 显示可用设备列表供用户选择
   }
   ```

2. **添加实时转录显示**
   - 当前仅显示录音电平，不显示实时转录文本
   - 可以添加 `InputTranscriptDelta` 的处理来显示用户说话内容

3. **优化内存使用**
   - 音频帧可能占用大量内存，考虑添加缓冲区大小限制

4. **添加性能指标**
   - 记录音频延迟、丢帧率等指标用于调试

5. **统一平台抽象**
   ```rust
   // 建议创建平台抽象层
   trait AudioBackend {
       fn start_capture(&self) -> Result<CaptureHandle, Error>;
       fn start_playback(&self) -> Result<PlaybackHandle, Error>;
   }
   ```

### 相关测试
- `codex-rs/tui_app_server/src/chatwidget/tests.rs`
  - 包含实时对话状态转换的测试
  - 测试 `should_render_realtime_user_message_event` 逻辑

### 相关文档
- `docs/tui-chat-composer.md` - 聊天编辑器状态机文档
- `codex-rs/tui_app_server/src/voice.rs` - 音频实现细节
