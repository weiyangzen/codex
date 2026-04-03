# voice.rs 研究文档

## 场景与职责

`voice.rs` 是 Codex TUI 的语音输入和实时音频播放模块，提供完整的语音交互功能：
- 录音和语音转文字（STT）
- 实时音频流输入（用于实时对话模式）
- 实时音频播放（用于 AI 语音输出）

主要使用场景：
- 用户按住语音键录音，松开后自动转录为文字
- 实时对话模式中，持续捕获麦克风输入并流式传输
- 播放 AI 生成的语音回复

## 功能点目的

### 1. 语音捕获（VoiceCapture）

**结构**：
```rust
pub struct VoiceCapture {
    stream: Option<cpal::Stream>,
    sample_rate: u32,
    channels: u16,
    data: Arc<Mutex<Vec<i16>>>,
    stopped: Arc<AtomicBool>,
    last_peak: Arc<AtomicU16>,
}
```

**功能**：
- `start()`：开始录音，使用默认输入设备
- `start_realtime()`：开始实时音频捕获，使用配置的输入设备
- `stop()`：停止录音，返回录制的音频数据

**音频格式**：
- 样本格式：i16（内部统一转换）
- 采样率：设备原生采样率（实时模式会重采样到 24kHz）
- 通道数：设备原生通道数（实时模式会转换到单声道）

### 2. 实时音频播放（RealtimeAudioPlayer）

**结构**：
```rust
pub(crate) struct RealtimeAudioPlayer {
    _stream: cpal::Stream,
    queue: Arc<Mutex<VecDeque<i16>>>,
    queued_samples: Arc<AtomicUsize>,
    output_sample_rate: u32,
    output_channels: u16,
}
```

**功能**：
- `start()`：启动音频播放流
- `enqueue_frame()`：将音频帧加入播放队列
- `clear()`：清空播放队列

**播放控制**：
- 使用 `VecDeque` 作为音频样本队列
- `queued_samples` 原子计数器跟踪队列深度（无锁读取）
- 支持样本格式转换（f32、i16、u16）

### 3. 语音转文字（Transcription）

**函数**：
```rust
pub fn transcribe_async(
    id: String,
    audio: RecordedAudio,
    context: Option<String>,
    tx: AppEventSender,
)
```

**流程**：
1. 检查录音时长（至少 1 秒）
2. 将音频编码为 WAV 格式（24kHz 单声道）
3. 创建独立的 Tokio 运行时
4. 异步发送转录请求
5. 通过 `AppEventSender` 返回结果

**认证和端点**：
- ChatGPT 模式：使用 ChatGPT 后端 API
- OpenAI API 模式：使用 `api.openai.com/v1/audio/transcriptions`
- 支持 `gpt-4o-mini-transcribe` 模型

### 4. 实时输入行为控制

**枚举**：
```rust
#[derive(Clone)]
pub(crate) enum RealtimeInputBehavior {
    Ungated,  // 无限制，始终转发输入
    PlaybackAware {
        playback_queued_samples: Arc<AtomicUsize>,
    },  // 根据播放状态智能控制
}
```

**智能打断逻辑**：
- 当 AI 正在播放语音时，忽略低音量输入（避免扬声器回声）
- 检测到高音量输入（峰值 > 4000）视为用户打断意图
- 打断后进入 900ms 宽限期，继续转发输入（捕获完整语句）

### 5. 录音电平表（RecordingMeterState）

**结构**：
```rust
pub(crate) struct RecordingMeterState {
    history: VecDeque<char>,  // 最近 4 个电平符号
    noise_ema: f64,           // 噪声指数移动平均
    env: f64,                 // 包络跟踪
}
```

**功能**：
- 实时计算音频峰值电平
- 使用攻击/释放包络跟踪
- 噪声自适应归一化
- 生成 Braille 图案电平显示（⠤⠴⠶⠷⡷⡿⣿）

## 具体技术实现

### 音频设备选择

**输入设备**：
```rust
fn select_configured_input_device_and_config(
    config: &Config,
) -> Result<(cpal::Device, cpal::SupportedStreamConfig), String>
```

**选择策略**：
1. 如果配置了特定麦克风，优先使用
2. 否则使用系统默认输入设备
3. 选择最佳配置：优先 24kHz 采样率、单声道、i16 格式

**输出设备**：
类似逻辑，使用配置的扬声器或系统默认输出设备。

### 样本格式转换

**输入转换**：
- f32 → i16：`(s.clamp(-1.0, 1.0) * i16::MAX as f32) as i16`
- u16 → i16：`(s as i32 - 32768) as i16`

**输出填充**：
- i16 → f32：`v as f32 / i16::MAX as f32`
- i16 → u16：`(v as i32 + 32768).clamp(0, u16::MAX as i32) as u16`

### PCM 重采样和通道转换

**函数**：
```rust
fn convert_pcm16(
    input: &[i16],
    input_sample_rate: u32,
    input_channels: u16,
    output_sample_rate: u32,
    output_channels: u16,
) -> Vec<i16>
```

**转换矩阵**：

| 输入通道 | 输出通道 | 操作 |
|---------|---------|------|
| 1 | 1 | 直接复制 |
| 1 | n | 复制到所有通道 |
| n | 1 | 平均混合 |
| n | n | 直接复制 |
| n | m (n>m) | 截断多余通道 |
| n | m (n<m) | 复制并填充最后一个样本 |

**重采样**：
- 使用简单线性插值（最近邻）
- 计算输出帧数：`in_frames * out_rate / in_rate`

### 实时输入门控

**函数**：
```rust
fn should_send_realtime_input(
    peak: u16,
    input_behavior: &RealtimeInputBehavior,
    allow_input_until: &mut Option<Instant>,
) -> bool
```

**逻辑**：
1. 如果 `Ungated`，始终返回 true
2. 如果没有播放队列，返回 true
3. 如果在宽限期内，返回 true
4. 如果峰值超过阈值（4000），设置宽限期并返回 true
5. 否则返回 false

### WAV 编码和归一化

**函数**：
```rust
fn encode_wav_normalized(audio: &RecordedAudio) -> Result<Vec<u8>, String>
```

**步骤**：
1. 如有需要，重采样到 24kHz 单声道
2. 计算音频峰值
3. 应用增益（目标峰值 90% 满量程）
4. 使用 `hound` 库编码为 WAV

### 转录 HTTP 请求

**ChatGPT 模式**：
```rust
let part = reqwest::multipart::Part::bytes(wav_bytes)
    .file_name("audio.wav")
    .mime_str("audio/wav")?;
let form = reqwest::multipart::Form::new().part("file", part);
client.post(&endpoint)
    .bearer_auth(&auth.bearer_token)
    .multipart(form)
    .header("ChatGPT-Account-Id", acc)
```

**OpenAI API 模式**：
```rust
let form = reqwest::multipart::Form::new()
    .text("model", AUDIO_MODEL)
    .part("file", part);
if let Some(context) = context {
    form = form.text("prompt", context);
}
```

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|------|------|
| `voice.rs` | 语音捕获、播放、转录实现 |
| `audio_device.rs` | 音频设备选择和配置 |

### 调用方

| 文件 | 调用点 | 用途 |
|------|--------|------|
| `bottom_pane/chat_composer.rs` | `VoiceCapture::start()` | 语音输入录音 |
| `app.rs` | `RealtimeAudioPlayer::start()` | 实时音频播放 |
| `app.rs` | `VoiceCapture::start_realtime()` | 实时对话模式 |

### 依赖关系

```
voice.rs
├── audio_device.rs          (设备选择)
├── app_event.rs             (AppEventSender, AppEvent)
├── codex_core::config       (配置)
├── codex_core::auth         (认证)
├── codex_core::default_client (HTTP 客户端)
├── codex_protocol::protocol (RealtimeAudioFrame, ConversationAudioParams)
├── cpal                     (跨平台音频 I/O)
├── hound                    (WAV 编码)
├── base64                   (音频数据编码)
└── tokio                    (异步运行时)
```

## 依赖与外部交互

### 外部 crate

| Crate | 用途 |
|-------|------|
| `cpal` | 跨平台音频输入/输出（基于系统音频 API） |
| `hound` | WAV 文件编码/解码 |
| `base64` | 音频数据 Base64 编码（用于实时传输） |
| `tokio` | 异步运行时和 HTTP 请求 |
| `reqwest` | HTTP 客户端（通过 `codex_client`） |
| `tracing` | 日志记录 |

### 内部模块

| 模块 | 用途 |
|------|------|
| `crate::app_event` | 应用事件发送和事件类型 |
| `crate::audio_device` | 音频设备选择逻辑 |
| `codex_core::config` | 音频设备配置 |
| `codex_core::auth` | 认证令牌获取 |
| `codex_protocol::protocol` | 实时音频协议类型 |

### 外部服务

| 服务 | 端点 | 用途 |
|------|------|------|
| OpenAI API | `api.openai.com/v1/audio/transcriptions` | 语音转文字 |
| ChatGPT Backend | `chatgpt.com/backend-api/transcribe` | ChatGPT 模式转录 |

## 风险、边界与改进建议

### 已知风险

1. **音频设备独占**
   - cpal 可能独占音频设备，影响其他应用
   - 缓解：使用系统默认共享模式（如果支持）

2. **采样率转换质量**
   - 当前使用简单线性插值，音质可能不如专业重采样算法
   - 缓解：对于语音应用，当前质量通常足够

3. **网络转录延迟**
   - 转录需要网络请求，可能引入延迟
   - 缓解：异步处理，不阻塞 UI

4. **权限问题**
   - 首次使用麦克风需要用户授权
   - 缓解：错误处理引导用户授权

5. **实时播放同步**
   - 播放队列可能溢出或欠载
   - 缓解：TODO 注释提到需要添加队列限制

### 边界条件

1. **极短录音**
   - 录音时长 < 1 秒时拒绝转录，避免垃圾输出

2. **空音频帧**
   - `send_realtime_audio_chunk` 检查空样本、零采样率、零通道

3. **设备不可用**
   - 配置的音频设备不可用时回退到系统默认
   - 无默认设备时返回错误

4. **认证失败**
   - `resolve_auth` 可能失败，错误通过 `AppEvent::TranscriptionFailed` 传递

### 改进建议

1. **本地转录**
   - 添加本地 Whisper 模型支持，减少网络依赖和延迟

2. **降噪处理**
   - 添加音频预处理（降噪、回声消除）
   - 改善语音质量

3. **语音活动检测（VAD）**
   - 使用专用 VAD 库（如 `webrtc-vad`）
   - 更准确地检测语音起始和结束

4. **队列管理**
   - 实现播放队列上限，防止内存溢出
   - 添加自适应缓冲区管理

5. **多设备支持**
   - 支持同时输入（多麦克风）和输出（多扬声器）
   - 设备热插拔检测

6. **音频可视化**
   - 扩展 `RecordingMeterState` 支持频谱显示
   - 实时波形显示

7. **配置扩展**
   - 添加音频质量设置（采样率、比特率）
   - 音量增益控制

8. **错误恢复**
   - 音频设备断开时自动重连
   - 网络失败时重试转录请求

9. **性能优化**
   - 使用环形缓冲区减少内存分配
   - 批量处理音频样本

10. **测试覆盖**
    - 当前测试仅覆盖格式转换和输入门控
    - 添加音频设备模拟测试
    - 添加转录流程集成测试
