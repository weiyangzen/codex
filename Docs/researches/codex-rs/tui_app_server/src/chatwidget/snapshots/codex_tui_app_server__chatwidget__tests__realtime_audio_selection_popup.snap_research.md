# Realtime Audio Selection Popup 研究文档

## 场景与职责

该 snapshot 测试验证实时语音对话功能的音频设备选择弹出框在标准宽度（80列）下的渲染效果。当用户触发 `/audio` 命令或相关快捷键时，系统显示此弹出框让用户配置实时语音通话的麦克风和扬声器设备。

**测试文件**: `codex-rs/tui_app_server/src/chatwidget/tests.rs`  
**Snapshot 文件**: `codex_tui_app_server__chatwidget__tests__realtime_audio_selection_popup.snap`

## 功能点目的

1. **音频设备配置**: 允许用户选择和切换实时语音通话使用的麦克风和扬声器
2. **设备状态显示**: 显示当前选中的设备（如 "System default"）
3. **入口导航**: 作为进入更详细设备选择界面的入口点
4. **实时会话准备**: 确保在开始实时语音会话前音频设备配置正确

## 具体技术实现

### 弹出框数据结构
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
        SelectionItem { ... }
    })
    .collect();
    
    let params = SelectionListParams { ... };
    self.bottom_pane.show_selection_view(params);
}
```

### 设备类型定义
```rust
pub enum RealtimeAudioDeviceKind {
    Microphone,  // 输入设备
    Speaker,     // 输出设备
}
```

### 当前选择标签生成
```rust
fn current_realtime_audio_selection_label(&self, kind: RealtimeAudioDeviceKind) -> String {
    let device = match kind {
        RealtimeAudioDeviceKind::Microphone => &self.config.realtime_audio.microphone,
        RealtimeAudioDeviceKind::Speaker => &self.config.realtime_audio.speaker,
    };
    device.clone().unwrap_or_else(|| "System default".to_string())
}
```

### 测试用例实现
```rust
#[cfg(not(target_os = "linux"))]
#[tokio::test]
async fn realtime_audio_selection_popup_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(Some("gpt-5.2-codex")).await;
    chat.open_realtime_audio_popup();
    
    let popup = render_bottom_popup(&chat, 80);  // 标准宽度 80 列
    assert_snapshot!("realtime_audio_selection_popup", popup);
}
```

## 关键代码路径与文件引用

| 文件路径 | 相关代码/函数 | 说明 |
|---------|-------------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs` | `open_realtime_audio_popup()` (L7416) | 弹出框打开函数 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | `current_realtime_audio_selection_label()` | 当前选择标签生成 |
| `codex-rs/tui_app_server/src/chatwidget/realtime.rs` | `RealtimeAudioDeviceKind` (L41) | 音频设备类型枚举 |
| `codex-rs/tui_app_server/src/app_event.rs` | `RealtimeAudioDeviceKind` | 事件类型定义 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | `realtime_audio_selection_popup_snapshot()` (L8353) | 测试函数 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | `render_bottom_popup()` (L7303) | 测试辅助函数 |

## 依赖与外部交互

### 依赖模块
- `crate::bottom_pane::SelectionListParams`: 选择列表参数
- `crate::selection_list::SelectionItem`: 选择项组件
- `codex_core::config::Config::realtime_audio`: 音频配置
- `crate::app_event::RealtimeAudioDeviceKind`: 设备类型事件

### 配置结构
```rust
pub struct RealtimeAudioConfig {
    pub microphone: Option<String>,  // 当前麦克风设备名
    pub speaker: Option<String>,     // 当前扬声器设备名
}
```

### 用户交互流程
1. 用户触发 `/audio` 命令 → 调用 `open_realtime_audio_popup()`
2. 用户选择 "Microphone" → 打开麦克风设备列表
3. 用户选择 "Speaker" → 打开扬声器设备列表
4. 用户按 Enter 确认或 Esc 返回

### 平台限制
- **Linux**: 该功能被禁用（`#[cfg(not(target_os = "linux"))]`）
- **macOS/Windows**: 完整支持音频设备选择

## 风险、边界与改进建议

### 潜在风险
1. **设备不可用**: 用户选择的设备可能在会话开始时被断开连接
2. **权限问题**: 麦克风访问需要系统权限，可能被拒绝
3. **平台差异**: Linux 不支持此功能，用户体验不一致

### 边界情况
1. **无可用设备**: 系统没有检测到任何音频设备时的处理
2. **设备名称过长**: 在窄屏下设备名称可能被截断
3. **配置持久化**: 设备选择需要保存到配置文件供下次使用
4. **实时会话中**: 在活跃实时会话期间更改设备需要重新初始化音频

### 改进建议
1. **设备检测**: 在弹出框打开时实时检测可用设备，标记不可用设备
2. **测试按钮**: 添加"测试"按钮让用户验证设备是否正常工作
3. **音量指示器**: 在麦克风选项旁显示实时音量指示
4. **默认设备智能选择**: 优先选择上次使用的设备，而非简单的 System default
5. **错误处理**: 当设备被占用或不可用时显示友好的错误信息

### 相关测试覆盖
- 标准宽度（80列）渲染测试
- 窄屏宽度（56列）渲染测试
- 麦克风设备选择器测试
- 设备选择持久化事件测试
