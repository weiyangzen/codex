# Snapshot Research: realtime_audio_selection_popup

## 场景与职责

此快照测试验证实时音频设备选择弹出框的渲染输出。当用户使用支持实时语音的模型（如 gpt-5.2-codex）时，可以通过 `/audio` 命令打开音频设置弹出框，配置麦克风和扬声器设备。

测试场景：
- 用户使用 gpt-5.2-codex 模型（支持实时语音）
- 调用 `open_realtime_audio_popup()` 打开音频设置弹出框
- 弹出框显示两个选项：麦克风和扬声器
- 当前选择显示为 "System default"
- 使用 `render_bottom_popup` 捕获弹出框渲染输出

## 功能点目的

1. **音频设备配置**：允许用户配置实时语音通话的输入/输出设备
2. **设备状态显示**：显示当前选中的设备
3. **快速访问**：提供进入详细设备选择的入口
4. **设置集中化**：将音频相关设置整合在一个弹出框中

## 具体技术实现

### 关键流程

1. **音频设置弹出流程**：
   ```
   /audio 命令 → dispatch_command(SlashCommand::Audio)
   ↓
   open_realtime_audio_popup()
   ↓
   构建 SelectionItem 列表（Microphone, Speaker）
   ↓
   显示弹出框
   ↓
   用户选择 → 发送 OpenRealtimeAudioDeviceSelection 事件
   ```

2. **弹出框渲染**：
   - 使用 `render_bottom_popup(&chat, 80)` 捕获宽度为 80 的弹出框
   - 通过 `insta::assert_snapshot` 进行快照比对

### 数据结构

```rust
pub enum RealtimeAudioDeviceKind {
    Microphone,
    Speaker,
}

impl RealtimeAudioDeviceKind {
    pub fn title(&self) -> &'static str {
        match self {
            RealtimeAudioDeviceKind::Microphone => "Microphone",
            RealtimeAudioDeviceKind::Speaker => "Speaker",
        }
    }
}

pub struct RealtimeAudioConfig {
    pub microphone: Option<String>,
    pub speaker: Option<String>,
}
```

### 选项构建

```rust
pub(crate) fn open_realtime_audio_popup(&mut self) {
    let items = [
        RealtimeAudioDeviceKind::Microphone,
        RealtimeAudioDeviceKind::Speaker,
    ]
    .into_iter()
    .map(|kind| {
        let description = Some(format!(
            "Current: {}",
            self.current_realtime_audio_selection_label(kind)
        ));
        let actions: Vec<SelectionAction> = vec![Box::new(move |tx| {
            tx.send(AppEvent::OpenRealtimeAudioDeviceSelection { kind });
        })];
        SelectionItem {
            name: kind.title().to_string(),
            description,
            actions,
            disabled_reason: None,
        }
    })
    .collect();

    self.bottom_pane.open_selection_popup(
        "Settings".to_string(),
        Some("Configure settings for Codex.".to_string()),
        items,
    );
}
```

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 测试定义（tui，line ~7755） |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试定义（tui_app_server，line ~8353） |
| `codex-rs/tui/src/chatwidget.rs` | `open_realtime_audio_popup()` 实现 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | `open_realtime_audio_popup()` 实现 |
| `codex-rs/core/src/config.rs` | `RealtimeAudioConfig` 配置定义 |

### 关键函数

- `ChatWidget::open_realtime_audio_popup()` - 打开音频设置弹出框
- `ChatWidget::current_realtime_audio_selection_label()` - 获取当前设备选择标签
- `RealtimeAudioDeviceKind::title()` - 获取设备类型标题
- `SlashCommand::Audio` - 斜杠命令处理

### 相关事件

```rust
pub enum AppEvent {
    OpenRealtimeAudioDeviceSelection {
        kind: RealtimeAudioDeviceKind,
    },
    PersistRealtimeAudioDeviceSelection {
        kind: RealtimeAudioDeviceKind,
        name: Option<String>,
    },
    // ...
}
```

## 依赖与外部交互

### 内部依赖

- `RealtimeAudioDeviceKind` - 音频设备类型枚举
- `RealtimeAudioConfig` - 音频配置结构
- `SelectionItem`, `SelectionAction` - 弹出框选项结构
- `AppEvent` - 应用事件系统

### 外部交互

- **配置系统**：读取和保存音频设备配置
- **平台音频 API**：获取可用设备列表（非 Linux 平台）
- **实时语音服务**：应用选中的音频设备

## 风险、边界与改进建议

### 潜在风险

1. **平台兼容性**：Linux 平台不支持实时音频设备选择（`#[cfg(not(target_os = "linux"))]`）
2. **设备可用性**：配置的设备可能在运行时不可用
3. **配置同步**：配置更改需要同步到实时语音服务

### 边界情况

- 无可用的音频设备
- 配置的设备在运行时断开连接
- 用户拒绝音频权限
- 平台不支持某些音频功能

### 改进建议

1. **设备检测增强**：
   - 实时检测设备连接状态
   - 在设备断开时提供友好的提示
   - 支持热插拔设备的动态检测

2. **UI/UX 改进**：
   - 添加音频测试功能（播放测试音）
   - 显示设备音量级别
   - 支持设备别名/自定义名称

3. **测试覆盖**：
   - 添加设备不可用时的测试用例
   - 测试配置持久化
   - 测试跨平台行为一致性

---

**快照内容**：
```
  Settings
  Configure settings for Codex.

› 1. Microphone  Current: System default
  2. Speaker     Current: System default

  Press enter to confirm or esc to go back
```

**说明**：显示实时音频设置弹出框。标题为 "Settings"，副标题说明配置 Codex 设置。两个选项分别是麦克风和扬声器，都显示当前选择为 "System default"。选项 1（Microphone）被默认选中。
