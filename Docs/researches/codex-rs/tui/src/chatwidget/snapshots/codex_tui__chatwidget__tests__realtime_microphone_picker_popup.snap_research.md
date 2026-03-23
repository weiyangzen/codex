# 研究报告: realtime_microphone_picker_popup.snap

## 场景与职责

该快照文件验证**具体音频设备选择弹窗**的渲染效果。与 `realtime_audio_selection_popup` 不同，此弹窗显示系统中实际检测到的音频设备列表，允许用户选择特定的麦克风或扬声器。

该测试模拟场景：
- 用户已配置 "Studio Mic" 作为首选麦克风
- 但该设备当前不可用（可能未连接）
- 系统检测到其他可用设备："Built-in Mic" 和 "USB Mic"

## 功能点目的

**设备选择弹窗**是音频设置的第二层界面，提供：

1. **设备枚举** - 显示系统中所有可用的音频设备
2. **当前设备状态** - 标记当前配置的设备（即使不可用）
3. **不可用设备提示** - 当配置的设备不可用时，显示警告和重新连接建议
4. **默认选项** - 提供 "System default" 选项使用系统默认设备

## 具体技术实现

### 测试设置

```rust
// tests.rs:7773-7785
#[cfg(not(target_os = "linux"))]
#[tokio::test]
async fn realtime_microphone_picker_popup_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(Some("gpt-5.2-codex")).await;
    // 模拟已配置的设备
    chat.config.realtime_audio.microphone = Some("Studio Mic".to_string());
    // 打开设备选择弹窗，传入可用设备列表
    chat.open_realtime_audio_device_selection_with_names(
        RealtimeAudioDeviceKind::Microphone,
        vec!["Built-in Mic".to_string(), "USB Mic".to_string()],
    );

    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("realtime_microphone_picker_popup", popup);
}
```

### 设备选择弹窗实现

```rust
// chatwidget.rs:6393-6456 (非 Linux 平台)
fn open_realtime_audio_device_selection_with_names(
    &mut self,
    kind: RealtimeAudioDeviceKind,
    device_names: Vec<String>,
) {
    let current_selection = self.current_realtime_audio_device_name(kind);
    // 检查当前配置的设备是否在可用列表中
    let current_available = current_selection
        .as_deref()
        .is_some_and(|name| device_names.iter().any(|device_name| device_name == name));
    
    // 构建选项列表
    let mut items = vec![SelectionItem {
        name: "System default".to_string(),
        description: Some("Use your operating system default device.".to_string()),
        is_current: current_selection.is_none(),
        // ...
    }];
    
    // 如果当前配置的设备不可用，添加禁用选项
    if let Some(current) = current_selection.filter(|_| !current_available) {
        items.push(SelectionItem {
            name: format!("Unavailable: {current} (current)"),
            description: Some(
                "Configured device is not currently available. \
                 (disabled: Reconnect the device or choose another one.)".to_string()
            ),
            disabled: true,
            is_current: true,
            // ...
        });
    }
    
    // 添加可用设备选项
    for name in device_names {
        items.push(SelectionItem {
            name,
            description: None,
            is_current: false,
            // ...
        });
    }
    // 显示弹窗
}
```

### 渲染输出解析

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

**关键元素**：
- 标题 `Select Microphone` 明确设备类型
- 说明文本解释设置仅适用于实时语音
- 系统默认选项带描述文本
- 不可用设备标记为 `(disabled)` 并显示帮助文本
- 当前选中项用 `›` 标记

## 关键代码路径与文件引用

| 文件 | 行号范围 | 描述 |
|------|----------|------|
| `codex-rs/tui/src/chatwidget.rs` | 6393-6456 | `open_realtime_audio_device_selection_with_names` 方法 |
| `codex-rs/tui/src/chatwidget.rs` | 6374-6392 | 平台特定的设备选择入口 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 7773-7785 | 麦克风选择弹窗测试 |
| `codex-rs/tui/src/audio_device.rs` | 11-26 | `list_realtime_audio_device_names` 函数 |

## 依赖与外部交互

### 音频设备枚举

```rust
// audio_device.rs:11-26
pub(crate) fn list_realtime_audio_device_names(
    kind: RealtimeAudioDeviceKind,
) -> Result<Vec<String>, String> {
    let host = cpal::default_host();
    let mut device_names = Vec::new();
    for device in devices(&host, kind)? {
        let Ok(name) = device.name() else { continue };
        if !device_names.contains(&name) {
            device_names.push(name);
        }
    }
    Ok(device_names)
}
```

### 事件流

1. 用户选择设备 → 发送 `AppEvent::PersistRealtimeAudioDeviceSelection`
2. 应用层处理持久化 → 更新配置
3. 如实时对话进行中 → 发送 `AppEvent::RestartRealtimeAudioDevice`

## 风险、边界与改进建议

### 特定风险

1. **设备名称重复** - 代码已处理重复名称（使用 `contains` 检查）
2. **设备名称获取失败** - 使用 `let Ok(name) = ... else { continue }` 跳过
3. **热插拔检测** - 当前实现可能在设备插拔后需要重新打开弹窗

### 边界情况

1. **无可用设备** - 仅显示 "System default" 选项
2. **大量设备** - 需要滚动支持（当前未在快照中验证）
3. **特殊字符** - 设备名称包含特殊字符时的显示处理

### 改进建议

1. **设备图标** - 为不同类型设备（内置/USB/蓝牙）添加图标区分
2. **信号强度** - 显示麦克风输入电平或连接状态
3. **测试按钮** - 添加音频测试功能验证设备工作正常
4. **最近使用** - 记录并优先显示最近使用的设备
5. **搜索过滤** - 设备数量多时支持搜索

### 相关测试

- `realtime_audio_picker_emits_persist_event` - 验证设备选择后的事件发送
- `realtime_audio_selection_popup` - 第一层音频设置弹窗
