# audio_device.rs 研究文档

## 场景与职责

`audio_device.rs` 是 Codex TUI 的音频设备管理模块，负责处理实时语音对话（Realtime Conversation）功能的音频输入（麦克风）和输出（扬声器）设备选择。该模块基于 `cpal`（Cross-Platform Audio Library）实现跨平台的音频设备枚举和配置。

### 核心职责
1. **设备枚举**：列出系统上可用的麦克风和扬声器设备
2. **设备选择**：根据配置或默认策略选择合适的音频设备
3. **配置优化**：为输入设备选择最佳的采样率、声道数和采样格式
4. **错误处理**：提供清晰的设备不可用错误信息

### 使用场景
- **实时语音对话**：用户通过语音与 AI 进行实时交互
- **语音转文字**：录制用户语音并发送给转录服务
- **音频播放**：播放 AI 的语音回复

## 功能点目的

### 1. 设备类型枚举
```rust
pub(crate) enum RealtimeAudioDeviceKind {
    Microphone,
    Speaker,
}
```
定义在 `app_event.rs` 中，用于区分输入和输出设备。

### 2. 首选输入配置常量
```rust
const PREFERRED_INPUT_SAMPLE_RATE: u32 = 24_000;  // 24kHz
const PREFERRED_INPUT_CHANNELS: u16 = 1;          // 单声道
```

这些值与 OpenAI 实时 API 的推荐配置对齐：
- 24kHz 采样率是实时语音模型的推荐输入
- 单声道减少数据传输量，同时保持足够质量

### 3. 设备选择结果
```rust
pub(crate) fn select_configured_input_device_and_config(
    config: &Config,
) -> Result<(cpal::Device, cpal::SupportedStreamConfig), String>
```

返回 `cpal::Device`（设备句柄）和 `cpal::SupportedStreamConfig`（流配置），供后续音频流构建使用。

## 具体技术实现

### 关键流程

#### 1. 设备列表获取
```rust
pub(crate) fn list_realtime_audio_device_names(
    kind: RealtimeAudioDeviceKind,
) -> Result<Vec<String>, String> {
    let host = cpal::default_host();
    let mut device_names = Vec::new();
    for device in devices(&host, kind)? {
        let Ok(name) = device.name() else {
            continue;
        };
        if !device_names.contains(&name) {
            device_names.push(name);
        }
    }
    Ok(device_names)
}
```

- 使用 `cpal::default_host()` 获取平台默认音频主机
- 去重处理（某些平台可能返回重复设备）
- 忽略无法获取名称的设备

#### 2. 配置设备选择
```rust
fn select_device_and_config(
    kind: RealtimeAudioDeviceKind,
    config: &Config,
) -> Result<(cpal::Device, cpal::SupportedStreamConfig), String> {
    let host = cpal::default_host();
    let configured_name = configured_name(kind, config);
    let selected = configured_name
        .and_then(|name| find_device_by_name(&host, kind, name))
        .or_else(|| {
            let default_device = default_device(&host, kind);
            if let Some(name) = configured_name && default_device.is_some() {
                warn!("configured {} audio device `{name}` was unavailable; falling back to system default", kind.noun());
            }
            default_device
        })
        .ok_or_else(|| missing_device_error(kind, configured_name))?;

    let stream_config = match kind {
        RealtimeAudioDeviceKind::Microphone => preferred_input_config(&selected)?,
        RealtimeAudioDeviceKind::Speaker => default_config(&selected, kind)?,
    };
    Ok((selected, stream_config))
}
```

选择策略（优先级从高到低）：
1. **配置指定设备**：从 `Config` 中读取用户配置的设备名称
2. **系统默认设备**：如果配置设备不可用，回退到系统默认
3. **错误报告**：如果都不可用，返回详细错误信息

#### 3. 输入配置优化算法
```rust
pub(crate) fn preferred_input_config(
    device: &cpal::Device,
) -> Result<cpal::SupportedStreamConfig, String> {
    let supported_configs = device
        .supported_input_configs()
        .map_err(|err| format!("failed to enumerate input audio configs: {err}"))?;

    supported_configs
        .filter_map(|range| {
            let sample_format_rank = match range.sample_format() {
                cpal::SampleFormat::I16 => 0u8,
                cpal::SampleFormat::U16 => 1u8,
                cpal::SampleFormat::F32 => 2u8,
                _ => return None,
            };
            let sample_rate = preferred_input_sample_rate(&range);
            let sample_rate_penalty = sample_rate.0.abs_diff(PREFERRED_INPUT_SAMPLE_RATE);
            let channel_penalty = range.channels().abs_diff(PREFERRED_INPUT_CHANNELS);
            Some((
                (sample_rate_penalty, channel_penalty, sample_format_rank),
                range.with_sample_rate(sample_rate),
            ))
        })
        .min_by_key(|(score, _)| *score)
        .map(|(_, config)| config)
        .or_else(|| device.default_input_config().ok())
        .ok_or_else(|| "failed to get default input config".to_string())
}
```

评分系统（分数越低越好）：
1. **采样率惩罚**：与目标 24kHz 的绝对差值
2. **声道惩罚**：与目标单声道的绝对差值
3. **采样格式排序**：I16 > U16 > F32（偏好整数格式）

回退策略：
- 如果优化失败，使用设备默认配置
- 如果默认配置也失败，返回错误

#### 4. 采样率选择逻辑
```rust
fn preferred_input_sample_rate(range: &cpal::SupportedStreamConfigRange) -> cpal::SampleRate {
    let min = range.min_sample_rate().0;
    let max = range.max_sample_rate().0;
    if (min..=max).contains(&PREFERRED_INPUT_SAMPLE_RATE) {
        cpal::SampleRate(PREFERRED_INPUT_SAMPLE_RATE)
    } else if PREFERRED_INPUT_SAMPLE_RATE < min {
        cpal::SampleRate(min)
    } else {
        cpal::SampleRate(max)
    }
}
```

- 如果 24kHz 在支持范围内，直接使用
- 如果低于最小支持值，使用最小值
- 如果高于最大支持值，使用最大值

### 数据结构

#### Config 中的音频配置
```rust
// 在 codex_core::config::Config 中
pub realtime_audio: RealtimeAudioConfig,

pub struct RealtimeAudioConfig {
    pub microphone: Option<String>,  // 配置的麦克风名称
    pub speaker: Option<String>,     // 配置的扬声器名称
}
```

#### cpal 类型映射
| cpal 类型 | 用途 |
|-----------|------|
| `cpal::Host` | 音频系统抽象（CoreAudio/ALSA/WASAPI） |
| `cpal::Device` | 物理音频设备 |
| `cpal::SupportedStreamConfig` | 支持的流配置（采样率、格式、声道） |
| `cpal::SupportedStreamConfigRange` | 配置范围（支持多个采样率） |

## 关键代码路径与文件引用

### 文件依赖关系

```
audio_device.rs
    ↓ 使用
cpal crate (Cross-Platform Audio Library)
    ↓ 调用
OS Audio APIs (CoreAudio/ALSA/WASAPI)

audio_device.rs
    ↓ 使用
Config::realtime_audio (codex_core::config)
    ↓ 读取
用户配置文件
```

### 主要调用方

| 调用模块 | 路径 | 用途 |
|---------|------|------|
| `voice.rs` | `src/voice.rs` | 语音录制和实时音频流 |
| 设备选择 UI | `app.rs` / 弹窗组件 | 显示可用设备列表 |

### voice.rs 中的使用
```rust
// voice.rs 中启动实时音频
pub fn start_realtime(config: &Config, tx: AppEventSender) -> Result<Self, String> {
    let (device, config) = select_realtime_input_device_and_config(config)?;
    // ... 构建立体声音频流
}

// 默认设备选择（无配置时）
fn select_default_input_device_and_config() -> Result<(cpal::Device, cpal::SupportedStreamConfig), String> {
    let host = cpal::default_host();
    let device = host.default_input_device()
        .ok_or_else(|| "no default input device available".to_string())?;
    let config = device.default_input_config()
        .map_err(|e| format!("failed to get default input config: {e}"))?;
    Ok((device, config))
}
```

## 依赖与外部交互

### 外部 Crate 依赖

| Crate | 版本 | 用途 |
|-------|------|------|
| `cpal` | 0.15+ | 跨平台音频设备访问 |
| `tracing` | - | 日志记录（warn! 宏） |

### cpal 平台支持

| 平台 | 后端 | 状态 |
|------|------|------|
| macOS | CoreAudio | 完全支持 |
| Linux | ALSA/PulseAudio | 完全支持 |
| Windows | WASAPI | 完全支持 |

### 内部模块依赖

| 模块 | 路径 | 用途 |
|------|------|------|
| `Config` | `codex_core::config::Config` | 读取用户配置的设备名称 |
| `RealtimeAudioDeviceKind` | `crate::app_event` | 设备类型枚举 |

### 配置交互

配置读取路径：
```rust
fn configured_name(kind: RealtimeAudioDeviceKind, config: &Config) -> Option<&str> {
    match kind {
        RealtimeAudioDeviceKind::Microphone => config.realtime_audio.microphone.as_deref(),
        RealtimeAudioDeviceKind::Speaker => config.realtime_audio.speaker.as_deref(),
    }
}
```

配置来源：
1. 用户配置文件（`config.toml`）
2. 命令行参数覆盖
3. 默认值为 `None`（使用系统默认）

## 风险、边界与改进建议

### 潜在风险

1. **设备热插拔**：
   - cpal 在设备枚举时获取快照，如果设备在枚举后被拔除，后续操作可能失败
   - 建议添加设备存在性验证和优雅回退

2. **权限问题**：
   - macOS 需要麦克风权限（`NSMicrophoneUsageDescription`）
   - 首次使用可能触发系统权限对话框，需要超时处理

3. **采样率转换**：
   - 当前选择最接近的采样率，但不进行重采样
   - 如果设备不支持 24kHz，实际采样率可能与模型期望不符
   - 建议在 `voice.rs` 中添加重采样逻辑

### 边界情况

1. **设备名称匹配**：
   ```rust
   fn find_device_by_name(...) -> Option<cpal::Device> {
       devices.into_iter()
           .find(|device| device.name().ok().as_deref() == Some(name))
   }
   ```
   - 使用精确字符串匹配，可能因名称变化（如语言切换）导致匹配失败
   - 建议添加模糊匹配或 ID 匹配

2. **空设备列表**：
   ```rust
   fn missing_device_error(kind: RealtimeAudioDeviceKind, configured_name: Option<&str>) -> String
   ```
   提供了四种错误消息变体，覆盖所有组合：
   - 配置麦克风 + 无默认
   - 配置扬声器 + 无默认
   - 无配置 + 无输入设备
   - 无配置 + 无输出设备

3. **格式不支持**：
   ```rust
   _ => return None,  // 未知采样格式被过滤掉
   ```
   如果设备只支持非标准格式（如 I24、I32），会被过滤，可能导致选择次优配置

### 改进建议

1. **设备 ID 持久化**：
   当前使用设备名称存储配置，但名称可能变化：
   ```rust
   // 建议添加设备 ID 支持
   pub struct AudioDeviceConfig {
       pub name: String,
       pub id: Option<String>,  // 设备唯一标识
   }
   ```

2. **采样率重采样**：
   添加软件重采样支持，确保输出始终是 24kHz：
   ```rust
   // 建议添加
   pub(crate) fn create_resampled_stream(
       device: &cpal::Device,
       target_sample_rate: u32,
   ) -> Result<AudioStream, String>
   ```

3. **设备变化监听**：
   添加设备热插拔监听：
   ```rust
   // 建议添加
   pub(crate) fn on_device_change<F: Fn()>(callback: F) -> DeviceChangeHandle
   ```

4. **配置验证**：
   在配置保存时验证设备存在性：
   ```rust
   // 建议添加
   pub(crate) fn validate_audio_config(config: &Config) -> Result<(), Vec<String>>
   ```

5. **测试覆盖**：
   当前模块没有单元测试，建议添加：
   ```rust
   #[cfg(test)]
   mod tests {
       #[test]
       fn test_preferred_sample_rate_selection() { ... }
       
       #[test]
       fn test_device_scoring() { ... }
       
       #[test]
       fn test_error_message_generation() { ... }
   }
   ```

### 性能考虑

1. **设备枚举开销**：
   - `list_realtime_audio_device_names` 每次调用都枚举所有设备
   - 建议缓存结果，或提供带缓存的包装函数

2. **配置选择算法**：
   - 使用 `filter_map` + `min_by_key`，时间复杂度 O(n)
   - 对于通常只有几个配置的设备，性能足够

### 安全考虑

1. **设备名称日志**：
   - 当前在 warn! 中记录设备名称，可能包含敏感信息
   - 建议审查日志级别和输出

2. **音频流权限**：
   - 确保音频流在不需要时正确关闭，避免持续监听
   - `voice.rs` 中的 `VoiceCapture` 实现了 `Drop`  trait 来停止流

### 平台特定考虑

1. **macOS**：
   - 需要 `NSMicrophoneUsageDescription` Info.plist 条目
   - 沙盒应用需要 `com.apple.security.device.audio-input` 权限

2. **Linux**：
   - 需要用户属于 `audio` 组或使用 PipeWire/PulseAudio
   - ALSA 设备名称可能较复杂（如 `hw:0,0`）

3. **Windows**：
   - WASAPI 设备名称可能包含厂商特定前缀
   - 需要处理设备被其他应用独占的情况
