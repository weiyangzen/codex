# audio_device.rs 深度研究文档

## 场景与职责

`audio_device.rs` 负责 Codex TUI 的**实时音频设备管理**，主要用于语音输入（麦克风）和输出（扬声器）的设备选择、配置和枚举。这是实时语音对话功能的基础模块。

### 核心场景

1. **设备枚举**: 列出系统中可用的音频输入（麦克风）和输出（扬声器）设备
2. **设备选择**: 根据配置或系统默认选择合适的音频设备
3. **配置优化**: 为输入设备选择最优的采样率和通道配置
4. **回退处理**: 当配置的设备不可用时，优雅地回退到系统默认

### 职责边界

- **设备发现**: 枚举系统中的音频设备
- **配置匹配**: 根据配置选择特定设备或默认设备
- **参数优化**: 为实时语音选择最佳音频参数（24kHz 采样率、单声道）
- **错误处理**: 提供清晰的错误信息，区分配置错误和系统错误

---

## 功能点目的

### 1. 设备枚举

```rust
pub(crate) fn list_realtime_audio_device_names(
    kind: RealtimeAudioDeviceKind,
) -> Result<Vec<String>, String>
```

**功能**:
- 枚举指定类型的所有音频设备
- 去重（某些系统可能报告重复设备）
- 返回设备名称列表

### 2. 配置设备选择

```rust
pub(crate) fn select_configured_input_device_and_config(
    config: &Config,
) -> Result<(cpal::Device, cpal::SupportedStreamConfig), String>

pub(crate) fn select_configured_output_device_and_config(
    config: &Config,
) -> Result<(cpal::Device, cpal::SupportedStreamConfig), String>
```

**选择策略**:
1. 尝试使用配置中指定的设备名称
2. 如果不可用，回退到系统默认设备
3. 如果配置了设备但不可用，记录警告日志
4. 如果完全无可用设备，返回错误

### 3. 输入配置优化

```rust
pub(crate) fn preferred_input_config(
    device: &cpal::Device,
) -> Result<cpal::SupportedStreamConfig, String>
```

**优化目标**:
- **首选采样率**: 24,000 Hz（OpenAI 实时 API 推荐）
- **首选通道**: 单声道（1 通道）
- **样本格式优先级**: F32 > U16 > I16

**评分算法**:
```rust
(
    sample_rate_penalty,  // 与 24kHz 的差值
    channel_penalty,      // 与单声道的差值
    sample_format_rank,   // 格式优先级（F32=2, U16=1, I16=0）
)
```

选择总分最低的（即最接近首选参数的）配置。

### 4. 回退策略

```rust
let selected = configured_name
    .and_then(|name| find_device_by_name(&host, kind, name))  // 1. 配置的设备
    .or_else(|| {
        let default_device = default_device(&host, kind);
        if let Some(name) = configured_name && default_device.is_some() {
            warn!("configured {} audio device `{name}` was unavailable; falling back to system default", kind.noun());
        }
        default_device  // 2. 系统默认
    })
    .ok_or_else(|| missing_device_error(kind, configured_name))?;  // 3. 错误
```

---

## 具体技术实现

### 依赖关系

```rust
use codex_core::config::Config;           // 配置访问
use cpal::traits::DeviceTrait;             // CPAL 设备接口
use cpal::traits::HostTrait;               // CPAL 主机接口
use tracing::warn;                         // 日志记录
use crate::app_event::RealtimeAudioDeviceKind;  // 设备类型枚举
```

### 常量定义

```rust
const PREFERRED_INPUT_SAMPLE_RATE: u32 = 24_000;  // OpenAI 推荐
const PREFERRED_INPUT_CHANNELS: u16 = 1;          // 单声道
```

### 核心函数

#### 设备枚举

```rust
fn devices(host: &cpal::Host, kind: RealtimeAudioDeviceKind) -> Result<Vec<cpal::Device>, String> {
    match kind {
        RealtimeAudioDeviceKind::Microphone => host.input_devices(),
        RealtimeAudioDeviceKind::Speaker => host.output_devices(),
    }
    .map(|devices| devices.collect())
    .map_err(|err| format!("...", err))
}
```

使用 CPAL 的 `Host` 接口枚举输入或输出设备。

#### 设备查找

```rust
fn find_device_by_name(
    host: &cpal::Host,
    kind: RealtimeAudioDeviceKind,
    name: &str,
) -> Option<cpal::Device> {
    let devices = devices(host, kind).ok()?;
    devices.into_iter()
        .find(|device| device.name().ok().as_deref() == Some(name))
}
```

线性搜索匹配名称的设备。

#### 配置读取

```rust
fn configured_name(kind: RealtimeAudioDeviceKind, config: &Config) -> Option<&str> {
    match kind {
        RealtimeAudioDeviceKind::Microphone => config.realtime_audio.microphone.as_deref(),
        RealtimeAudioDeviceKind::Speaker => config.realtime_audio.speaker.as_deref(),
    }
}
```

从配置中读取设备名称。

#### 采样率选择

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

在支持的范围内选择最接近 24kHz 的采样率。

---

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `app_event.rs` | `RealtimeAudioDeviceKind` 枚举定义 |

### 外部依赖

| 类型 | 来源 | 用途 |
|------|------|------|
| `Config` | `codex_core::config` | 访问音频设备配置 |
| `cpal::Device` / `DeviceTrait` | `cpal` | 音频设备抽象 |
| `cpal::Host` / `HostTrait` | `cpal` | 音频主机抽象 |
| `cpal::SupportedStreamConfig` | `cpal` | 音频流配置 |

### 调用路径

```
初始化实时语音
  → select_configured_input_device_and_config(config)
    → select_device_and_config(Microphone, config)
      → configured_name() [读取配置]
      → find_device_by_name() [查找配置的设备]
      → 或 default_device() [回退到默认]
      → preferred_input_config() [优化输入配置]
        → supported_input_configs() [枚举支持配置]
        → 评分选择最优配置
      → 返回 (Device, SupportedStreamConfig)

设备选择器 UI
  → list_realtime_audio_device_names(kind)
    → devices() [枚举设备]
    → 收集名称并去重
```

---

## 依赖与外部交互

### 与 CPAL 的交互

CPAL (Cross-Platform Audio Library) 是 Rust 的跨平台音频库：

```rust
let host = cpal::default_host();  // 获取平台默认主机
let devices = host.input_devices()?;  // 枚举输入设备
let default = host.default_input_device();  // 获取默认设备
```

CPAL 抽象了不同平台（Windows/macOS/Linux）的音频 API 差异。

### 与配置的交互

```rust
// 配置结构（codex_core）
pub struct Config {
    pub realtime_audio: RealtimeAudioConfig,
}

pub struct RealtimeAudioConfig {
    pub microphone: Option<String>,  // 配置的麦克风名称
    pub speaker: Option<String>,     // 配置的扬声器名称
}
```

### 与 app_event 的交互

```rust
pub(crate) enum RealtimeAudioDeviceKind {
    Microphone,
    Speaker,
}
```

统一处理两种设备类型。

---

## 风险、边界与改进建议

### 潜在风险

1. **设备热插拔**:
   - CPAL 在设备枚举时快照设备列表
   - 设备在枚举后拔出可能导致后续操作失败
   - 需要上层处理设备断开的情况

2. **配置过时**:
   - 配置中存储的设备名称可能在系统变更后失效
   - 回退到默认设备可能不是用户期望的行为

3. **采样率转换**:
   - 如果设备不支持 24kHz，选择最接近的采样率
   - 可能需要额外的重采样，增加延迟

4. **权限问题**:
   - 麦克风访问需要用户授权（尤其在 macOS 上）
   - 模块本身不处理权限请求

### 边界条件

| 场景 | 处理 |
|------|------|
| 无可用设备 | 返回错误，提示"no input/output audio device available" |
| 配置的设备不存在 | 记录警告，回退到默认设备 |
| 无默认设备 | 返回错误，包含配置的设备名称 |
| 配置为空 | 直接使用默认设备 |
| 不支持首选采样率 | 选择最接近的可用采样率 |
| 设备名称获取失败 | 跳过该设备（在枚举中）|

### 改进建议

1. **设备监控**:
   ```rust
   pub struct AudioDeviceMonitor {
       last_devices: Vec<String>,
   }
   impl AudioDeviceMonitor {
       pub fn check_changes(&self) -> Option<DeviceChangeEvent> { ... }
   }
   ```

2. **缓存和重用**:
   - 缓存设备枚举结果，避免频繁 I/O
   - 提供设备变更通知机制

3. **更智能的回退**:
   ```rust
   enum DeviceSelectionStrategy {
       ConfiguredOnly,      // 严格使用配置的设备
       PreferConfigured,    // 优先配置，回退到默认
       PreferQuality,       // 选择质量最好的设备
   }
   ```

4. **配置验证**:
   ```rust
   pub fn validate_config(config: &Config) -> Result<(), Vec<DeviceConfigError>> {
       // 检查配置的设备是否存在
       // 返回详细的验证错误
   }
   ```

5. **平台特定优化**:
   - macOS: 处理权限请求
   - Windows: 处理 WASAPI 独占模式
   - Linux: 处理 PulseAudio/ALSA 选择

6. **测试**:
   - 添加 mock CPAL 后端用于测试
   - 测试各种设备配置场景
   - 测试错误处理路径

### 代码统计

- 总行数: 176 行
- 公共函数: 5 个
- 私有函数: 7 个
- 依赖 crate: 3 个（codex_core, cpal, tracing）

### 设计评价

**优点**:
- 清晰的错误消息，区分不同失败场景
- 合理的回退策略
- 针对实时语音优化的配置选择

**可改进**:
- 缺少设备变更监控
- 缺少配置验证
- 错误类型使用 `String` 而非结构化错误

### 相关配置

```toml
# config.toml
[realtime_audio]
microphone = "Built-in Microphone"
speaker = "Built-in Output"
```

配置项：
- `realtime_audio.microphone`: 首选麦克风设备名称
- `realtime_audio.speaker`: 首选扬声器设备名称
