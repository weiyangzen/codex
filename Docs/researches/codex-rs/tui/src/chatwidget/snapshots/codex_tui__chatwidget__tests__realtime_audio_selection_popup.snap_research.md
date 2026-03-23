# 研究报告: realtime_audio_selection_popup.snap

## 场景与职责

该快照文件是 Codex TUI（终端用户界面）的 insta 快照测试结果，用于验证实时音频设备选择弹窗的渲染输出。它捕获了当用户通过 `/audio` 或类似命令打开音频设置弹窗时，界面应该呈现的视觉效果。

此测试属于 UI 回归测试的一部分，确保：
- 弹窗标题、选项和提示文本正确渲染
- 当前选择的音频设备（麦克风/扬声器）状态正确显示
- 布局在不同终端宽度下保持一致

## 功能点目的

**实时音频设备选择功能**允许用户配置 Codex 实时语音对话的输入（麦克风）和输出（扬声器）设备。该功能：

1. **提供设备配置入口** - 通过弹窗让用户查看和修改当前音频设备设置
2. **显示当前状态** - 显示当前选择的麦克风和扬声器（默认为"System default"）
3. **支持设备选择** - 用户可以选择进入子菜单选择具体设备
4. **跨平台适配** - 在非 Linux 平台上可用（Linux 平台该功能被禁用）

## 具体技术实现

### 关键数据结构

```rust
// app_event.rs
pub(crate) enum RealtimeAudioDeviceKind {
    Microphone,
    Speaker,
}

impl RealtimeAudioDeviceKind {
    pub(crate) fn title(self) -> &'static str {
        match self {
            Self::Microphone => "Microphone",
            Self::Speaker => "Speaker",
        }
    }
}
```

### 关键流程

**1. 打开音频设置弹窗 (`open_realtime_audio_popup`)**

```rust
// chatwidget.rs:6340
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
            // ...
        }
    })
    .collect();
    // 显示选择弹窗
}
```

**2. 获取当前设备标签**

```rust
// chatwidget.rs:8064
fn current_realtime_audio_selection_label(&self, kind: RealtimeAudioDeviceKind) -> String {
    self.current_realtime_audio_device_name(kind)
        .unwrap_or_else(|| "System default".to_string())
}
```

**3. 测试渲染流程**

```rust
// tests.rs:7755-7761
async fn realtime_audio_selection_popup_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(Some("gpt-5.2-codex")).await;
    chat.open_realtime_audio_popup();
    
    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("realtime_audio_selection_popup", popup);
}
```

### 渲染输出格式

快照显示的渲染输出包含：

```
  Settings
  Configure settings for Codex.

› 1. Microphone  Current: System default
  2. Speaker     Current: System default

  Press enter to confirm or esc to go back
```

- `Settings` - 弹窗标题
- `Configure settings for Codex.` - 副标题/说明
- 带编号的选项列表 - 麦克风和扬声器
- `Current: System default` - 显示当前选择
- 底部提示 - 操作指引

## 关键代码路径与文件引用

| 文件 | 行号范围 | 描述 |
|------|----------|------|
| `codex-rs/tui/src/app_event.rs` | 35-50 | `RealtimeAudioDeviceKind` 枚举定义 |
| `codex-rs/tui/src/chatwidget.rs` | 6340-6371 | `open_realtime_audio_popup()` 方法 |
| `codex-rs/tui/src/chatwidget.rs` | 8057-8067 | 当前设备名称/标签获取方法 |
| `codex-rs/tui/src/chatwidget.rs` | 6374-6456 | 设备选择子菜单实现 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 7753-7761 | 快照测试函数 |
| `codex-rs/tui/src/audio_device.rs` | 1-176 | 音频设备枚举和选择逻辑 |

## 依赖与外部交互

### 内部依赖

1. **app_event** - `RealtimeAudioDeviceKind` 枚举和 `AppEvent::OpenRealtimeAudioDeviceSelection`
2. **bottom_pane** - 选择弹窗 UI 组件 (`SelectionItem`, `SelectionView`)
3. **audio_device** - 实际音频设备枚举和配置（非 Linux 平台）

### 外部依赖

1. **cpal** - 跨平台音频设备枚举库（仅在非 Linux 平台使用）
2. **ratatui** - TUI 渲染框架

### 平台差异

```rust
// lib.rs:70-82
#[cfg(all(not(target_os = "linux"), not(feature = "voice-input")))]
mod audio_device {
    // Linux 平台或 voice-input 特性禁用时，返回错误
    pub(crate) fn list_realtime_audio_device_names(
        kind: RealtimeAudioDeviceKind,
    ) -> Result<Vec<String>, String> {
        Err(format!("... voice input is unavailable ..."))
    }
}
```

## 风险、边界与改进建议

### 已知风险

1. **平台限制** - Linux 平台不支持实时音频设备选择，测试使用 `#[cfg(not(target_os = "linux"))]` 条件编译
2. **设备可用性** - 用户配置的音频设备可能在运行时不可用，需要处理降级逻辑
3. **配置持久化** - 设备选择需要保存到配置文件，涉及异步 I/O 操作

### 边界情况

1. **无可用设备** - 当系统没有音频设备时，需要优雅处理
2. **设备热插拔** - USB 音频设备插拔后，需要重新枚举设备
3. **权限问题** - 麦克风访问可能需要系统权限

### 改进建议

1. **增强测试覆盖** - 添加设备选择后的配置持久化验证测试
2. **错误处理可视化** - 当设备枚举失败时，在弹窗中显示更友好的错误信息
3. **实时预览** - 添加音频输入/输出测试功能，让用户确认设备工作正常
4. **设备记忆** - 当首选设备不可用时，记住用户的备选偏好

### 相关测试

- `realtime_audio_selection_popup_narrow` - 窄终端宽度下的布局测试
- `realtime_microphone_picker_popup` - 具体设备选择弹窗测试
- `realtime_audio_picker_emits_persist_event` - 设备选择持久化事件测试
