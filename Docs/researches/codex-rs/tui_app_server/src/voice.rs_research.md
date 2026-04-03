# voice.rs 研究文档

## 场景与职责

`voice.rs` 是 Codex TUI 应用服务器的语音输入和实时音频处理模块，负责：

1. **语音录制**：从麦克风捕获音频，支持多种采样格式（F32、I16、U16）
2. **实时音频流**：将捕获的音频实时发送到对话系统
3. **音频播放**：接收并播放来自 AI 的实时音频响应
4. **音频转录**：将录制的音频发送到 OpenAI 的转录 API（Whisper）
5. **音频可视化**：提供录音音量指示器（ASCII 动画）
6. **音频格式转换**：在不同采样率和声道配置之间转换音频

该模块仅在非 Linux 平台且启用 `voice-input` 特性时提供完整功能。其他情况下提供存根实现。

## 功能点目的

### 1. 语音录制（VoiceCapture）

**目的**：捕获用户语音输入。

**两种模式**：
- `start()`：标准录制模式，用于后续转录
- `start_realtime()`：实时模式，音频块实时发送到对话系统

**支持的格式**：
- F32（浮点 32 位）
- I16（有符号 16 位整数）
- U16（无符号 16 位整数）

### 2. 实时音频播放（RealtimeAudioPlayer）

**目的**：播放 AI 的语音响应。

**功能**：
- 从配置选择输出设备
- 接收 Base64 编码的音频帧
- 自动转换采样率和声道配置
- 支持队列管理（可清空）

### 3. 音频转录（transcribe_async）

**目的**：将录制的音频转换为文本。

**流程**：
1. 检查音频时长（至少 1 秒）
2. 将音频编码为 WAV 格式（24kHz 单声道）
3. 根据认证模式选择端点（ChatGPT 或 OpenAI API）
4. 发送 HTTP 请求并解析响应
5. 通过 `AppEventSender` 发送结果

### 4. 录音音量指示器（RecordingMeterState）

**目的**：提供可视化的录音音量反馈。

**实现**：
- 使用 Braille 图案（`⠤⠴⠶⠷⡷⡿⣿`）显示音量级别
- 指数移动平均（EMA）降噪
- 攻击/释放包络处理
- 对数压缩实现更自然的视觉响应

### 5. 音频格式转换（convert_pcm16）

**目的**：在不同音频格式之间转换。

**支持的转换**：
- 采样率转换（简单线性插值）
- 声道转换（单声道 ↔ 立体声）
- 下混音（多声道 → 单声道取平均）

## 具体技术实现

### 数据结构

```rust
pub struct VoiceCapture {
    stream: Option<cpal::Stream>,           // CPAL 音频流
    sample_rate: u32,                       // 采样率
    channels: u16,                          // 声道数
    data: Arc<Mutex<Vec<i16>>>,            // 录制的音频数据
    stopped: Arc<AtomicBool>,              // 停止标志
    last_peak: Arc<AtomicU16>,             // 最近峰值（用于音量指示器）
}

pub struct RecordedAudio {
    pub data: Vec<i16>,                     // 音频样本
    pub sample_rate: u32,                   // 采样率
    pub channels: u16,                      // 声道数
}

pub(crate) struct RealtimeAudioPlayer {
    _stream: cpal::Stream,                  // 输出流（保持存活）
    queue: Arc<Mutex<VecDeque<i16>>>,      // 音频样本队列
    output_sample_rate: u32,                // 输出采样率
    output_channels: u16,                   // 输出声道数
}

pub(crate) struct RecordingMeterState {
    history: VecDeque<char>,                // 历史音量字符
    noise_ema: f64,                         // 噪声 EMA
    env: f64,                               // 包络值
}

struct TranscriptionAuthContext {
    mode: AuthMode,                         // 认证模式
    bearer_token: String,                   // Bearer token
    chatgpt_account_id: Option<String>,     // ChatGPT 账户 ID
    chatgpt_base_url: String,               // ChatGPT API 基础 URL
}
```

### 常量定义

```rust
const AUDIO_MODEL: &str = "gpt-4o-mini-transcribe";
const MODEL_AUDIO_SAMPLE_RATE: u32 = 24_000;  // 模型期望的采样率
const MODEL_AUDIO_CHANNELS: u16 = 1;          // 模型期望的声道数
```

### 音频捕获流程

**标准录制**：
```rust
pub fn start() -> Result<Self, String> {
    // 1. 选择默认输入设备和配置
    let (device, config) = select_default_input_device_and_config()?;
    
    // 2. 创建共享数据缓冲区
    let data = Arc::new(Mutex::new(Vec::new()));
    let last_peak = Arc::new(AtomicU16::new(0));
    
    // 3. 根据采样格式构建输入流
    let stream = build_input_stream(&device, &config, data.clone(), last_peak.clone())?;
    
    // 4. 启动流
    stream.play()?;
    
    Ok(Self { ... })
}
```

**实时录制**：
```rust
pub fn start_realtime(config: &Config, tx: AppEventSender) -> Result<Self, String> {
    // 类似标准录制，但使用 build_realtime_input_stream
    // 音频块通过 send_realtime_audio_chunk 实时发送
}
```

### 音频流构建

根据采样格式匹配构建不同的回调：

```rust
fn build_input_stream(...) -> Result<cpal::Stream, String> {
    match config.sample_format() {
        cpal::SampleFormat::F32 => {
            device.build_input_stream(
                &config.clone().into(),
                move |input: &[f32], _| {
                    let peak = peak_f32(input);
                    last_peak.store(peak, Ordering::Relaxed);
                    if let Ok(mut buf) = data.lock() {
                        for &s in input {
                            buf.push(f32_to_i16(s));
                        }
                    }
                },
                error_callback,
                None,
            )
        }
        // I16 和 U16 类似...
    }
}
```

### 实时音频发送

```rust
fn send_realtime_audio_chunk(tx: &AppEventSender, samples: Vec<i16>, sample_rate: u32, channels: u16) {
    // 1. 如果需要，转换采样率和声道
    let samples = if sample_rate == MODEL_AUDIO_SAMPLE_RATE && channels == MODEL_AUDIO_CHANNELS {
        samples
    } else {
        convert_pcm16(&samples, sample_rate, channels, MODEL_AUDIO_SAMPLE_RATE, MODEL_AUDIO_CHANNELS)
    };
    
    // 2. 编码为字节
    let mut bytes = Vec::with_capacity(samples.len() * 2);
    for sample in &samples {
        bytes.extend_from_slice(&sample.to_le_bytes());
    }
    
    // 3. Base64 编码
    let encoded = base64::engine::general_purpose::STANDARD.encode(bytes);
    
    // 4. 发送事件
    tx.realtime_conversation_audio(ConversationAudioParams {
        frame: RealtimeAudioFrame {
            data: encoded,
            sample_rate: MODEL_AUDIO_SAMPLE_RATE,
            num_channels: MODEL_AUDIO_CHANNELS,
            samples_per_channel: Some(samples_per_channel),
            item_id: None,
        },
    });
}
```

### 音频播放流程

```rust
impl RealtimeAudioPlayer {
    pub(crate) fn enqueue_frame(&self, frame: &RealtimeAudioFrame) -> Result<(), String> {
        // 1. Base64 解码
        let raw_bytes = base64::engine::general_purpose::STANDARD.decode(&frame.data)?;
        
        // 2. 转换为 i16 样本
        let mut pcm = Vec::with_capacity(raw_bytes.len() / 2);
        for pair in raw_bytes.chunks_exact(2) {
            pcm.push(i16::from_le_bytes([pair[0], pair[1]]));
        }
        
        // 3. 转换采样率和声道
        let converted = convert_pcm16(&pcm, frame.sample_rate, frame.num_channels, 
                                      self.output_sample_rate, self.output_channels);
        
        // 4. 加入队列
        let mut guard = self.queue.lock()?;
        guard.extend(converted);
        Ok(())
    }
}
```

### 音量指示器算法

```rust
impl RecordingMeterState {
    pub(crate) fn next_text(&mut self, peak: u16) -> String {
        const SYMBOLS: [char; 7] = ['⠤', '⠴', '⠶', '⠷', '⡷', '⡿', '⣿'];
        const ALPHA_NOISE: f64 = 0.05;   // 噪声 EMA 系数
        const ATTACK: f64 = 0.80;        // 攻击系数
        const RELEASE: f64 = 0.25;       // 释放系数
        
        // 1. 归一化峰值
        let latest_peak = peak as f64 / (i16::MAX as f64);
        
        // 2. 包络处理（攻击/释放）
        if latest_peak > self.env {
            self.env = ATTACK * latest_peak + (1.0 - ATTACK) * self.env;
        } else {
            self.env = RELEASE * latest_peak + (1.0 - RELEASE) * self.env;
        }
        
        // 3. 噪声 EMA
        let rms_approx = self.env * 0.7;
        self.noise_ema = (1.0 - ALPHA_NOISE) * self.noise_ema + ALPHA_NOISE * rms_approx;
        
        // 4. 计算级别（对数压缩）
        let ref_level = self.noise_ema.max(0.01);
        let fast_signal = 0.8 * latest_peak + 0.2 * self.env;
        let raw = (fast_signal / (ref_level * 2.0)).max(0.0);
        let k = 1.6f64;
        let compressed = (raw.ln_1p() / k.ln_1p()).min(1.0);
        
        // 5. 映射到符号
        let idx = (compressed * (SYMBOLS.len() as f64 - 1.0))
            .round()
            .clamp(0.0, SYMBOLS.len() as f64 - 1.0) as usize;
        
        // 6. 更新历史并返回
        self.history.push_back(SYMBOLS[idx]);
        if self.history.len() > 4 {
            self.history.pop_front();
        }
        self.history.iter().collect()
    }
}
```

### 转录流程

```rust
pub fn transcribe_async(id: String, audio: RecordedAudio, context: Option<String>, tx: AppEventSender) {
    std::thread::spawn(move || {
        // 1. 检查最小时长
        if duration_seconds < MIN_DURATION_SECONDS {
            tx.send(AppEvent::TranscriptionFailed { id, error: "too short".to_string() });
            return;
        }
        
        // 2. 编码为 WAV
        let wav_bytes = encode_wav_normalized(&audio)?;
        
        // 3. 创建 Tokio 运行时并执行请求
        let rt = tokio::runtime::Runtime::new()?;
        let result = rt.block_on(async { transcribe_bytes(wav_bytes, context, duration_seconds).await });
        
        // 4. 发送结果
        match result {
            Ok(text) => tx.send(AppEvent::TranscriptionComplete { id, text }),
            Err(e) => tx.send(AppEvent::TranscriptionFailed { id, error: e }),
        }
    });
}
```

### 音频格式转换

```rust
fn convert_pcm16(
    input: &[i16],
    input_sample_rate: u32,
    input_channels: u16,
    output_sample_rate: u32,
    output_channels: u16,
) -> Vec<i16> {
    // 1. 计算输出帧数
    let out_frames = if input_sample_rate == output_sample_rate {
        in_frames
    } else {
        // 简单线性重采样
        (((in_frames as u64) * (output_sample_rate as u64)) / (input_sample_rate as u64)).max(1)
    };
    
    // 2. 声道转换
    match (in_channels, out_channels) {
        (1, 1) => out.push(src[0]),  // 单声道到单声道
        (1, n) => {                  // 单声道到多声道：复制
            for _ in 0..n { out.push(src[0]); }
        }
        (n, 1) if n >= 2 => {        // 多声道到单声道：取平均
            let sum: i32 = src.iter().map(|s| *s as i32).sum();
            out.push((sum / (n as i32)) as i16);
        }
        (n, m) if n == m => out.extend_from_slice(src),  // 相同声道数
        // ... 其他组合
    }
}
```

## 关键代码路径与文件引用

### 依赖模块

| 模块 | 文件 | 用途 |
|------|------|------|
| `audio_device` | `audio_device.rs` | 音频设备选择和配置 |
| `app_event` | `app_event.rs` | 应用事件定义 |
| `app_event_sender` | `app_event_sender.rs` | 事件发送器 |

### 调用方

| 文件 | 用途 |
|------|------|
| `chatwidget.rs` | 启动/停止语音录制 |
| `app.rs` | 处理转录结果事件 |

### 外部 Crate

| Crate | 用途 |
|-------|------|
| `cpal` | 跨平台音频 I/O |
| `hound` | WAV 文件编码/解码 |
| `base64` | Base64 编码/解码 |
| `reqwest` | HTTP 客户端 |
| `tokio` | 异步运行时 |

### 协议类型

| 类型 | 来源 | 用途 |
|------|------|------|
| `ConversationAudioParams` | `codex_protocol` | 实时音频参数 |
| `RealtimeAudioFrame` | `codex_protocol` | 实时音频帧 |

## 依赖与外部交互

### 音频设备交互

- 通过 CPAL 枚举和选择音频设备
- 支持配置指定的输入/输出设备
- 回退到系统默认设备

### 网络交互

**转录 API**：
- ChatGPT 模式：`{chatgpt_base_url}/transcribe`
- OpenAI API 模式：`https://api.openai.com/v1/audio/transcriptions`

**认证**：
- 从 `codex_home/auth.json` 读取认证信息
- 支持多种认证模式（OAuth、API Key 等）

### 文件系统交互

- 读取认证文件
- 无持久化音频数据（纯内存处理）

## 风险、边界与改进建议

### 已知风险

1. **音频质量**：
   - 简单线性重采样可能产生混叠
   - 下混音算法简单（取平均），可能不是最佳

2. **性能**：
   - 转录在单独线程中运行，创建新的 Tokio 运行时
   - 大量并发转录可能导致资源耗尽

3. **错误处理**：
   - 某些错误仅记录日志，用户可能不知情
   - 音频设备断开时无自动重连

4. **平台差异**：
   - Linux 平台无语音支持（存根实现）
   - 不同平台的默认设备选择行为可能不同

### 边界条件

1. **音频时长**：
   - 最小 1 秒限制，短音频被拒绝
   - 无最大时长限制，长音频可能内存不足

2. **采样率转换**：
   - 仅支持 24kHz 输出（模型期望）
   - 极端采样率比率可能导致质量问题

3. **队列管理**：
   - `RealtimeAudioPlayer` 队列无上限，可能内存溢出
   - TODO 注释提到需要添加队列限制

4. **并发**：
   - `VoiceCapture` 数据使用 `std::sync::Mutex`，可能阻塞音频回调
   - 建议使用 `parking_lot` 或 lock-free 结构

### 改进建议

1. **音频质量**：
   - 使用高质量重采样算法（如 libsamplerate）
   - 添加低通滤波器防止混叠
   - 实现更高级的下混音算法（如考虑声道间相位）

2. **性能优化**：
   - 复用 Tokio 运行时，避免每次转录创建新运行时
   - 使用对象池减少内存分配
   - 考虑使用 `ringbuf` 进行无锁音频数据传输

3. **错误恢复**：
   - 实现音频设备热插拔检测和自动重连
   - 添加网络错误重试机制
   - 提供更详细的错误信息给用户

4. **功能增强**：
   - 支持语音活动检测（VAD），自动停止录制
   - 添加降噪处理
   - 支持多语言转录配置

5. **安全性**：
   - 验证转录 API 的 TLS 证书
   - 添加请求超时
   - 限制音频数据大小防止 DoS

6. **可观测性**：
   - 添加音频处理指标（延迟、丢帧率）
   - 记录音频设备信息用于调试
   - 支持音频录制调试模式

7. **测试**：
   - 添加模拟音频设备的单元测试
   - 测试各种采样率转换场景
   - 添加网络故障注入测试

8. **跨平台**：
   - 调查 Linux 平台 CPAL 支持状态
   - 提供 ALSA/PulseAudio 后端选项
