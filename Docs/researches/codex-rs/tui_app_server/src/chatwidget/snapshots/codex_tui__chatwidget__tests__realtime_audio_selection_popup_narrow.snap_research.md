# Snapshot Research: realtime_audio_selection_popup_narrow

## 场景与职责

此快照测试验证实时音频设备选择弹出框在窄屏模式（56 列宽度）下的渲染输出。与标准宽度测试不同，此测试确保弹出框在较小终端宽度下仍能正确显示，测试 UI 的自适应布局能力。

测试场景：
- 用户使用 gpt-5.2-codex 模型（支持实时语音）
- 调用 `open_realtime_audio_popup()` 打开音频设置弹出框
- 使用窄屏宽度 56 列渲染弹出框
- 验证布局在受限宽度下的正确性
- 使用 `render_bottom_popup` 捕获弹出框渲染输出

## 功能点目的

1. **响应式布局**：确保弹出框在不同终端宽度下都能正确显示
2. **窄屏兼容性**：支持在较小终端窗口中使用音频设置功能
3. **文本截断处理**：验证长文本在窄屏下的截断或换行行为
4. **用户体验一致性**：保持不同屏幕尺寸下的操作一致性

## 具体技术实现

### 关键流程

1. **窄屏测试流程**：
   ```
   创建 ChatWidget（gpt-5.2-codex）
   ↓
   open_realtime_audio_popup()
   ↓
   render_bottom_popup(&chat, 56)  // 窄屏宽度
   ↓
   快照比对
   ```

2. **与普通宽度测试的区别**：
   - 标准测试：`render_bottom_popup(&chat, 80)`
   - 窄屏测试：`render_bottom_popup(&chat, 56)`
   - 56 列宽度模拟较小终端窗口（如分屏、嵌入式终端）

### 数据结构

与标准宽度测试相同：

```rust
pub enum RealtimeAudioDeviceKind {
    Microphone,
    Speaker,
}

pub struct RealtimeAudioConfig {
    pub microphone: Option<String>,
    pub speaker: Option<String>,
}
```

### 平台限制

```rust
#[cfg(not(target_os = "linux"))]
#[tokio::test]
async fn realtime_audio_selection_popup_narrow_snapshot() {
    // 测试实现
}
```

注意：此测试仅在非 Linux 平台运行，因为 Linux 平台不支持实时音频设备选择。

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 测试定义（tui，line ~7765） |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试定义（tui_app_server，line ~8363） |
| `codex-rs/tui/src/chatwidget.rs` | `open_realtime_audio_popup()` 实现 |
| `codex-rs/tui/src/bottom_pane/mod.rs` | 弹出框渲染和布局实现 |

### 关键函数

- `ChatWidget::open_realtime_audio_popup()` - 打开音频设置弹出框
- `render_bottom_popup()` - 测试辅助函数，渲染底部弹出框
- `BottomPane::render_selection_popup()` - 渲染选择弹出框

### 测试实现

```rust
#[cfg(not(target_os = "linux"))]
#[tokio::test]
async fn realtime_audio_selection_popup_narrow_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(Some("gpt-5.2-codex")).await;
    chat.open_realtime_audio_popup();

    let popup = render_bottom_popup(&chat, 56);  // 窄屏宽度
    assert_snapshot!("realtime_audio_selection_popup_narrow", popup);
}
```

## 依赖与外部交互

### 内部依赖

- `RealtimeAudioDeviceKind` - 音频设备类型枚举
- `SelectionItem` - 弹出框选项结构
- `render_bottom_popup()` - 测试辅助函数

### 外部交互

- **终端宽度**：通过 `render_bottom_popup` 的宽度参数控制
- **布局引擎**：`ratatui` 的布局系统处理窄屏适配

## 风险、边界与改进建议

### 潜在风险

1. **文本截断**：窄屏下长文本可能被截断，影响可读性
2. **布局错位**：选项描述可能在窄屏下换行不当
3. **最小宽度限制**：过窄的宽度可能导致布局完全失效

### 边界情况

- 设备名称过长时的显示
- 描述文本换行后的对齐
- 极小宽度（< 40 列）下的行为
- 中文字符等宽字符的显示

### 改进建议

1. **布局优化**：
   - 在窄屏下考虑隐藏或缩短描述文本
   - 实现更智能的文本截断（如添加省略号）
   - 考虑垂直堆叠布局替代水平布局

2. **测试增强**：
   - 添加更多宽度变体的测试（40、60、100、120 列）
   - 测试极端宽度下的行为
   - 添加动态调整大小的测试

3. **可访问性**：
   - 确保窄屏下快捷键提示仍然可见
   - 考虑为视障用户提供替代导航方式

---

**快照内容**：
```
  Settings
  Configure settings for Codex.

› 1. Microphone  Current: System default
  2. Speaker     Current: System default

  Press enter to confirm or esc to go back
```

**说明**：显示窄屏模式（56 列）下的实时音频设置弹出框。与标准宽度测试相比，内容相同但布局需要适应更窄的宽度。此测试验证弹出框在受限宽度下仍能正确渲染，文本没有错位或截断问题。
