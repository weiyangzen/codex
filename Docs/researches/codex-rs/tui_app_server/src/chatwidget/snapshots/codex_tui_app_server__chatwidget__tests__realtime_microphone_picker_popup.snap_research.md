# Realtime Microphone Picker Popup 研究文档

## 场景与职责

该 snapshot 测试验证实时语音功能的麦克风设备选择器弹出框的渲染效果。当用户从音频设置菜单选择 "Microphone" 选项后，系统显示此弹出框列出所有可用的麦克风设备供用户选择。

**测试文件**: `codex-rs/tui_app_server/src/chatwidget/tests.rs`  
**Snapshot 文件**: `codex_tui_app_server__chatwidget__tests__realtime_microphone_picker_popup.snap`

## 功能点目的

1. **设备枚举展示**: 列出系统检测到的所有麦克风设备
2. **当前设备标识**: 高亮显示当前配置的麦克风设备（即使不可用）
3. **设备可用性提示**: 标记不可用设备并提供重新连接建议
4. **设备切换**: 允许用户选择不同的麦克风设备用于实时语音通话

## 具体技术实现

### 弹出框构建
```rust
#[cfg(not(target_os = "linux"))]
pub(crate) fn open_realtime_audio_device_selection_with_names(
    &mut self,
    kind: RealtimeAudioDeviceKind,
    names: Vec<String>,  // 可用设备名称列表
) {
    let current = match kind {
        RealtimeAudioDeviceKind::Microphone => &self.config.realtime_audio.microphone,
        RealtimeAudioDeviceKind::Speaker => &self.config.realtime_audio.speaker,
    };
    
    let items: Vec<SelectionItem> = names
        .into_iter()
        .map(|name| {
            let is_current = current.as_ref() == Some(&name);
            let (disabled, description) = if is_current && !available_names.contains(&name) {
                (true, Some(
                    "Configured device is not currently available. (disabled: Reconnect the device or choose another one.)"
                ))
            } else {
                (false, description_for_device(&name))
            };
            SelectionItem { name, description, disabled, ... }
        })
        .collect();
    
    self.bottom_pane.show_selection_view(params);
}
```

### 测试用例实现
```rust
#[cfg(not(target_os = "linux"))]
#[tokio::test]
async fn realtime_microphone_picker_popup_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(Some("gpt-5.2-codex")).await;
    
    // 设置当前麦克风为 "Studio Mic"
    chat.config.realtime_audio.microphone = Some("Studio Mic".to_string());
    
    // 打开设备选择器，传入可用设备列表（不包含当前设备）
    chat.open_realtime_audio_device_selection_with_names(
        RealtimeAudioDeviceKind::Microphone,
        vec!["Built-in Mic".to_string(), "USB Mic".to_string()],
    );
    
    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("realtime_microphone_picker_popup", popup);
}
```

### 设备状态处理
```rust
// 当前设备但不可用
disabled: true,
description: Some(
    "Configured device is not currently available. (disabled: Reconnect the device or choose another one.)"
),

// 普通可用设备
disabled: false,
description: Some("Use your operating system default device."),
```

## 关键代码路径与文件引用

| 文件路径 | 相关代码/函数 | 说明 |
|---------|-------------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs` | `open_realtime_audio_device_selection_with_names()` | 设备选择器打开函数 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | `RealtimeAudioDeviceKind` | 设备类型枚举 |
| `codex-rs/tui_app_server/src/app_event.rs` | `PersistRealtimeAudioDeviceSelection` | 设备选择持久化事件 |
| `codex-rs/tui_app_server/src/audio_device.rs` | `list_realtime_audio_device_names()` | 设备枚举函数 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | `realtime_microphone_picker_popup_snapshot()` (L8373) | 测试函数 |

## 依赖与外部交互

### 依赖模块
- `crate::audio_device`: 音频设备枚举和检测
- `crate::bottom_pane::SelectionListParams`: 选择列表参数
- `crate::selection_list::SelectionItem`: 选择项组件
- `codex_core::config::RealtimeAudioConfig`: 音频配置

### 设备枚举流程
1. 调用平台特定的设备枚举 API（CoreAudio on macOS, WASAPI on Windows）
2. 过滤出指定类型的设备（输入/输出）
3. 获取设备用户友好名称
4. 检测设备当前是否可用

### 持久化流程
```rust
// 用户选择设备后
AppEvent::PersistRealtimeAudioDeviceSelection {
    kind: RealtimeAudioDeviceKind::Microphone,
    name: Some("USB Mic".to_string()),
}
// → 保存到配置文件 → 下次启动时恢复
```

### 配置结构
```rust
pub struct RealtimeAudioConfig {
    pub microphone: Option<String>,
    pub speaker: Option<String>,
}
```

## 风险、边界与改进建议

### 潜在风险
1. **设备热插拔**: 用户在选择过程中拔出设备可能导致选择失败
2. **设备名称变化**: 同一设备在不同连接顺序下可能有不同名称
3. **权限问题**: 麦克风访问权限被拒绝时设备列表可能为空

### 边界情况
1. **无可用设备**: 系统没有检测到任何麦克风时的处理
2. **设备名称冲突**: 两个设备具有相同名称时的区分
3. **当前设备不存在**: 配置中保存的设备当前不在系统中的处理
4. **设备被占用**: 设备被其他应用占用时的提示

### 改进建议
1. **设备ID使用**: 使用稳定的设备ID而非名称进行持久化，避免重命名问题
2. **实时检测**: 在选择器打开期间持续检测设备状态变化
3. **默认设备标记**: 明确标记系统默认设备
4. **设备图标**: 根据设备类型显示不同图标（内置、USB、蓝牙等）
5. **音量预览**: 在设备旁显示实时音量条帮助用户确认设备正常工作
6. **最近使用**: 将最近使用的设备排在列表前面

### 相关测试覆盖
- 麦克风选择器测试（当前设备不可用场景）
- 扬声器选择器测试
- 设备选择持久化事件测试
- 音频设备枚举测试

### Snapshot 内容分析
```
  Select Microphone
  Saved devices apply to realtime voice only.

  1. System default                                Use your operating system
                                                   default device.
› 2. Unavailable: Studio Mic (current) (disabled)  Configured device is not
                                                   currently available.
                                                   (disabled: Reconnect the
                                                   device or choose another
                                                   one.)
  3. Built-in Mic
  4. USB Mic

  Press enter to confirm or esc to go back
```

**关键观察点**:
1. 当前设备 "Studio Mic" 被标记为不可用（disabled）
2. 不可用设备有详细的说明文本，解释原因和解决方案
3. 选择指示器（›）指向当前配置的设备，即使它不可用
4. 其他可用设备正常显示，无禁用标记
