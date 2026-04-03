# Realtime Audio Selection Popup Narrow 研究文档

## 场景与职责

该 snapshot 测试验证实时语音对话功能的音频设备选择弹出框在窄屏（56列）下的渲染效果。这是响应式布局测试的一部分，确保在较小终端宽度下弹出框仍能正确显示且布局合理。

**测试文件**: `codex-rs/tui_app_server/src/chatwidget/tests.rs`  
**Snapshot 文件**: `codex_tui_app_server__chatwidget__tests__realtime_audio_selection_popup_narrow.snap`

## 功能点目的

1. **响应式布局验证**: 确保音频设备选择弹出框在窄屏（56列）下正确渲染
2. **文本截断处理**: 验证长文本（如设备描述）在窄屏下的截断和换行行为
3. **用户体验一致性**: 保证在不同终端尺寸下用户都能正常使用音频配置功能
4. **布局回归检测**: 通过 snapshot 捕获窄屏布局，防止未来的布局更改破坏窄屏显示

## 具体技术实现

### 窄屏测试实现
```rust
#[cfg(not(target_os = "linux"))]
#[tokio::test]
async fn realtime_audio_selection_popup_narrow_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(Some("gpt-5.2-codex")).await;
    chat.open_realtime_audio_popup();
    
    let popup = render_bottom_popup(&chat, 56);  // 窄屏宽度 56 列
    assert_snapshot!("realtime_audio_selection_popup_narrow", popup);
}
```

### 与标准宽度的对比
| 维度 | 标准宽度 (80列) | 窄屏 (56列) |
|------|----------------|------------|
| 设备描述显示 | "Current: System default" 完整显示 | 同上，但空间更紧凑 |
| 标题内边距 | 标准内边距 | 压缩内边距 |
| 选择指示器 | "›" 前缀正常显示 | "›" 前缀正常显示 |

### 渲染辅助函数
```rust
fn render_bottom_popup(chat: &ChatWidget, width: u16) -> String {
    let height = chat.desired_height(width);
    let area = Rect::new(0, 0, width, height);
    let mut buf = Buffer::empty(area);
    chat.render(area, &mut buf);
    
    // 提取所有行并去除尾部空格
    let mut lines: Vec<String> = (0..area.height)
        .map(|row| {
            let mut line = String::new();
            for col in 0..area.width {
                let symbol = buf[(area.x + col, area.y + row)].symbol();
                line.push_str(if symbol.is_empty() { " " } else { symbol });
            }
            line.trim_end().to_string()
        })
        .collect();
    
    // 去除首尾空行
    while lines.first().map_or(false, |l| l.is_empty()) {
        lines.remove(0);
    }
    while lines.last().map_or(false, |l| l.is_empty()) {
        lines.pop();
    }
    lines.join("\n")
}
```

## 关键代码路径与文件引用

| 文件路径 | 相关代码/函数 | 说明 |
|---------|-------------|------|
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | `realtime_audio_selection_popup_narrow_snapshot()` (L8363) | 窄屏测试函数 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | `render_bottom_popup()` (L7303) | 渲染辅助函数 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | `open_realtime_audio_popup()` (L7416) | 弹出框打开函数 |
| `codex-rs/tui_app_server/src/selection_list.rs` | `SelectionList` 渲染逻辑 | 响应式布局实现 |

## 依赖与外部交互

### 依赖模块
- `ratatui::layout::Rect`: 布局矩形计算
- `ratatui::buffer::Buffer`: 渲染缓冲区
- `crate::bottom_pane`: 底部面板渲染
- `crate::selection_list`: 选择列表组件

### 布局约束
- 最小宽度要求：约 40 列（保证基本可读性）
- 标题区域：固定高度
- 选择项区域：根据选项数量动态扩展
- 底部提示：固定格式 "Press enter to confirm or esc to go back"

### 响应式行为
1. **文本截断**: 过长的设备名称使用省略号截断
2. **内边距调整**: 窄屏下减少水平内边距
3. **描述换行**: 描述文本在必要时换行显示

## 风险、边界与改进建议

### 潜在风险
1. **过度截断**: 在极窄宽度下（<40列），设备名称可能被过度截断导致无法识别
2. **布局错位**: 选择指示器（›）在窄屏下可能与文本重叠
3. **换行混乱**: 描述文本的自动换行可能在不恰当的位置断开

### 边界情况
1. **超窄屏幕**: 宽度小于 40 列时的降级处理
2. **超长设备名**: 设备名称超过可用宽度时的截断策略
3. **多字节字符**: 包含 CJK 字符的设备名在宽度计算中的处理
4. **颜色代码**: ANSI 颜色代码是否影响宽度计算

### 改进建议
1. **最小宽度保护**: 设置弹出框的最小宽度，低于此宽度时显示警告或启用横向滚动
2. **智能截断**: 优先截断描述文本而非设备名称，或使用中省略号（"..."）
3. **设备名缩写**: 对常见设备类型使用缩写（如 "Built-in" → "Int"）
4. **垂直布局**: 在极窄宽度下考虑改为垂直堆叠布局
5. **宽度自适应**: 根据内容动态调整弹出框宽度，而非固定比例

### 相关测试覆盖
- 标准宽度（80列）渲染测试
- 窄屏宽度（56列）渲染测试 - 本测试
- 麦克风设备选择器测试（也使用 80列）
- 不同设备状态的组合测试

### Snapshot 内容分析
```
  Settings
  Configure settings for Codex.

› 1. Microphone  Current: System default
  2. Speaker     Current: System default

  Press enter to confirm or esc to go back
```

与标准宽度相比，窄屏版本保持了相同的结构和内容，说明当前实现具有良好的响应式适应能力。主要区别在于可用水平空间的减少，但尚未触发截断或换行逻辑。
