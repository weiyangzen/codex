# Snapshot Research: realtime_microphone_picker_popup

## 场景与职责

此快照测试验证实时麦克风设备选择弹出框的渲染输出，特别是当配置的设备不可用时的情况。用户进入详细的麦克风设备选择界面时，系统会显示所有可用设备，并标记当前配置但不可用的设备。

测试场景：
- 用户使用 gpt-5.2-codex 模型
- 配置中设置了麦克风为 "Studio Mic"
- 调用 `open_realtime_audio_device_selection_with_names()` 打开设备选择器
- 可用设备列表包含 "Built-in Mic" 和 "USB Mic"
- "Studio Mic" 标记为不可用（当前配置的设备未连接）
- 使用 `render_bottom_popup` 捕获弹出框渲染输出

## 功能点目的

1. **设备选择**：允许用户从可用设备列表中选择麦克风
2. **不可用设备提示**：标记当前配置但不可用的设备，帮助用户诊断问题
3. **设备状态可视化**：清晰区分可用和不可用设备
4. **故障排除指导**：为不可用设备提供原因说明和解决建议

## 具体技术实现

### 关键流程

1. **设备选择弹出流程**：
   ```
   用户选择 Microphone → OpenRealtimeAudioDeviceSelection 事件
   ↓
   open_realtime_audio_device_selection_with_names(Microphone, device_list)
   ↓
   构建 SelectionItem 列表
   ↓
   标记当前配置但不在 device_list 中的设备为不可用
   ↓
   显示弹出框
   ```

2. **不可用设备处理**：
   - 检查配置中的设备是否在可用列表中
   - 如果不在，添加一个标记为不可用的条目
   - 提供详细的不可用原因和解决建议

### 数据结构

```rust
pub enum RealtimeAudioDeviceKind {
    Microphone,
    Speaker,
}

pub struct SelectionItem {
    pub name: String,
    pub description: Option<String>,
    pub actions: Vec<SelectionAction>,
    pub disabled_reason: Option<String>,
}
```

### 不可用设备标记

```rust
// 测试中的设置
chat.config.realtime_audio.microphone = Some("Studio Mic".to_string());
chat.open_realtime_audio_device_selection_with_names(
    RealtimeAudioDeviceKind::Microphone,
    vec!["Built-in Mic".to_string(), "USB Mic".to_string()],
);
```

不可用设备的显示：
- 名称：`"Unavailable: Studio Mic (current) (disabled)"`
- 描述：多行文本说明设备不可用原因和解决建议

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 测试定义（tui，line ~7775） |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试定义（tui_app_server，line ~8373） |
| `codex-rs/tui/src/chatwidget.rs` | `open_realtime_audio_device_selection_with_names()` 实现 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | 同上 |

### 关键函数

- `ChatWidget::open_realtime_audio_device_selection_with_names()` - 打开具体设备选择弹出框
- `ChatWidget::current_realtime_audio_selection_label()` - 获取当前设备标签
- `SelectionItem` 构建逻辑 - 创建设备选项列表

### 实现细节

```rust
pub(crate) fn open_realtime_audio_device_selection_with_names(
    &mut self,
    kind: RealtimeAudioDeviceKind,
    names: Vec<String>,
) {
    let current = match kind {
        RealtimeAudioDeviceKind::Microphone => &self.config.realtime_audio.microphone,
        RealtimeAudioDeviceKind::Speaker => &self.config.realtime_audio.speaker,
    };
    
    let mut items: Vec<SelectionItem> = names
        .into_iter()
        .map(|name| SelectionItem {
            name,
            description: None,
            actions: vec![/* 选择动作 */],
            disabled_reason: None,
        })
        .collect();
    
    // 如果当前配置的设备不在列表中，添加为不可用项
    if let Some(current_name) = current {
        if !items.iter().any(|i| &i.name == current_name) {
            items.insert(0, SelectionItem {
                name: format!("Unavailable: {} (current)", current_name),
                description: Some("Configured device is not currently available.".to_string()),
                actions: vec![],
                disabled_reason: Some(
                    "Reconnect the device or choose another one.".to_string()
                ),
            });
        }
    }
    
    // 显示弹出框
    self.bottom_pane.open_selection_popup(
        format!("Select {}", kind.title()),
        Some("Saved devices apply to realtime voice only.".to_string()),
        items,
    );
}
```

## 依赖与外部交互

### 内部依赖

- `RealtimeAudioDeviceKind` - 音频设备类型
- `RealtimeAudioConfig` - 音频配置
- `SelectionItem` - 弹出框选项结构
- `AppEvent::PersistRealtimeAudioDeviceSelection` - 设备选择持久化事件

### 外部交互

- **平台音频 API**：获取可用设备列表
- **配置系统**：保存用户选择的设备
- **实时语音服务**：应用选中的设备

## 风险、边界与改进建议

### 潜在风险

1. **设备列表同步**：可用设备列表可能与实际系统状态不同步
2. **热插拔处理**：设备在弹出框打开期间连接/断开可能导致状态不一致
3. **长设备名称**：设备名称过长可能影响布局

### 边界情况

- 无任何可用设备
- 多个不可用设备
- 设备名称包含特殊字符
- 设备名称重复

### 改进建议

1. **设备管理增强**：
   - 实时检测设备连接状态变化
   - 添加设备刷新功能
   - 支持设备别名设置

2. **UI/UX 改进**：
   - 为不可用设备添加图标标识
   - 提供一键重置为系统默认的选项
   - 添加设备测试功能

3. **测试覆盖**：
   - 添加扬声器设备选择的测试
   - 测试多个不可用设备的情况
   - 测试设备选择后的持久化

---

**快照内容**：
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

**说明**：显示麦克风设备选择弹出框。标题为 "Select Microphone"，副标题说明配置仅适用于实时语音。选项包括：
1. System default - 使用操作系统默认设备
2. Unavailable: Studio Mic (current) (disabled) - 当前配置但不可用的设备，带有详细的不可用说明
3. Built-in Mic - 内置麦克风
4. USB Mic - USB 麦克风

选项 2 被选中，显示不可用状态和多行描述文本。
