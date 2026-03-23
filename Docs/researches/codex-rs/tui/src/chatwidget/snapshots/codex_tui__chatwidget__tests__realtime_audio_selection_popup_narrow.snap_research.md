# 研究报告: realtime_audio_selection_popup_narrow.snap

## 场景与职责

该快照文件是 `realtime_audio_selection_popup` 的变体测试，专门验证在**窄终端宽度**（56 列）下实时音频设备选择弹窗的渲染效果。这是响应式 UI 测试的一部分，确保弹窗在较小终端窗口中仍能正确显示。

与标准宽度（80 列）版本相比，此测试关注：
- 文本截断和换行行为
- 布局自适应调整
- 关键信息（如当前设备状态）的可见性保持

## 功能点目的

**窄宽度适配**是 TUI 应用的重要特性，因为：

1. **终端多样性** - 用户可能使用分屏、小窗口或低分辨率终端
2. **可读性保证** - 即使空间受限，核心信息仍需清晰可读
3. **一致性体验** - 不同宽度下保持交互逻辑一致

## 具体技术实现

### 测试实现

```rust
// tests.rs:7763-7771
#[cfg(not(target_os = "linux"))]
#[tokio::test]
async fn realtime_audio_selection_popup_narrow_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(Some("gpt-5.2-codex")).await;
    chat.open_realtime_audio_popup();

    let popup = render_bottom_popup(&chat, 56);  // 窄宽度: 56 列
    assert_snapshot!("realtime_audio_selection_popup_narrow", popup);
}
```

### 与标准宽度版本的对比

| 特性 | 标准版 (80列) | 窄版 (56列) |
|------|---------------|-------------|
| 宽度 | 80 | 56 |
| 描述文本 | 完整显示 | 可能截断/换行 |
| 选项对齐 | 标准对齐 | 自适应调整 |

### 渲染输出

```
  Settings
  Configure settings for Codex.

› 1. Microphone  Current: System default
  2. Speaker     Current: System default

  Press enter to confirm or esc to go back
```

**注意**：在此快照中，56 列宽度仍能完整显示内容，说明该弹窗的最低宽度要求较低。

## 关键代码路径与文件引用

| 文件 | 行号范围 | 描述 |
|------|----------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 7763-7771 | 窄宽度快照测试函数 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 7753-7761 | 标准宽度版本（对比参考）|
| `codex-rs/tui/src/bottom_pane/` | - | 弹窗渲染和布局组件 |

## 依赖与外部交互

与 `realtime_audio_selection_popup` 完全相同：

1. **内部依赖** - `app_event`, `bottom_pane`, `audio_device`
2. **外部依赖** - `ratatui` 负责处理不同宽度下的布局

### 布局适配机制

```rust
// 典型的响应式布局处理（示意）
fn render_bottom_popup(&self, width: u16) -> String {
    // width 参数传递给渲染引擎
    // ratatui 根据可用空间调整文本换行和截断
}
```

## 风险、边界与改进建议

### 特定风险

1. **内容截断** - 过窄的宽度可能导致关键信息（如设备名称）被截断
2. **换行混乱** - 不当的换行可能破坏视觉层次
3. **最小宽度阈值** - 需要定义弹窗可接受的最小宽度

### 改进建议

1. **定义最小宽度** - 明确弹窗支持的最小终端宽度，低于此值显示警告
2. **动态调整** - 根据宽度动态调整布局（如隐藏描述文本）
3. **滚动支持** - 极窄宽度下支持水平滚动查看完整内容
4. **更多宽度测试** - 添加 40 列、120 列等更多宽度变体的快照测试

### 相关测试

- `realtime_audio_selection_popup` - 标准宽度版本
- `realtime_microphone_picker_popup` - 设备列表弹窗（可能涉及更复杂的窄宽适配）
