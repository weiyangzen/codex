# Research: unified_exec_wait_status_renders_command_in_single_details_row Snapshot Test

## 场景与职责

该 snapshot 测试验证 `tui_app_server` 中 `ChatWidget` 组件在**统一执行等待状态下命令在单行详情行中正确渲染**的 UI 布局行为。具体场景包括：

1. 启动统一执行进程，使用一个长命令（`cargo test -p codex-core -- --exact some::very::long::test::name`）
2. 发送空输入进入等待状态
3. 渲染底部弹出面板（宽度 48 字符）
4. 验证命令在单行详情行中正确截断显示

此测试确保在有限宽度下，长命令能够正确截断并在单行中显示，避免破坏 UI 布局。

## 功能点目的

### 核心功能
- **命令截断显示**：在长命令超出显示宽度时正确截断
- **单行详情行**：确保命令详情始终占据单行，不影响其他 UI 元素
- **响应式布局**：适应不同终端宽度的布局调整

### 业务价值
- 确保 UI 在各种终端尺寸下都能正确显示
- 防止长命令破坏底部状态栏的布局
- 提供清晰的命令预览，即使用户输入了长命令

## 具体技术实现

### 测试设置
```rust
let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;
chat.on_task_started();

// 启动统一执行，使用长命令
begin_unified_exec_startup(
    &mut chat,
    "call-wait-ui",
    "proc-ui",
    "cargo test -p codex-core -- --exact some::very::long::test::name",
);

// 发送空输入进入等待状态
terminal_interaction(&mut chat, "call-wait-ui-stdin", "proc-ui", "");
```

### 渲染验证
```rust
// 使用 48 字符宽度渲染底部弹出面板
let rendered = render_bottom_popup(&chat, 48);
assert_snapshot!("unified_exec_wait_status_renders_command_in_single_details_row", rendered);
```

### `render_bottom_popup` 辅助函数
```rust
fn render_bottom_popup(chat: &ChatWidget, width: u16) -> String {
    let height = chat.desired_height(width);
    let backend = ratatui::backend::TestBackend::new(width, height);
    let mut terminal = ratatui::Terminal::new(backend).expect("create terminal");
    terminal.set_viewport_area(Rect::new(0, 0, width, height));
    terminal
        .draw(|f| chat.render(f.area(), f.buffer_mut()))
        .expect("draw chatwidget");
    
    // 提取底部面板的渲染内容
    let buffer = terminal.backend().buffer().clone();
    format_buffer_contents(&buffer)
}
```

### Snapshot 输出分析
生成的 snapshot 显示底部面板（宽度 48）：
```
• Waiting for background terminal (0s • esc to …
  └ cargo test -p codex-core -- --exact…


› Ask Codex to do anything

  ? for shortcuts            100% context left
```

关键元素：
- `• Waiting for background terminal (0s • esc to …`：状态头，带计时器和中断提示
- `└ cargo test -p codex-core -- --exact…`：命令详情行，使用 `…` 截断
- `› Ask Codex to do anything`：输入提示
- `? for shortcuts            100% context left`：底部状态栏

注意：长命令被截断为单行，使用 `…` 表示省略，确保 UI 布局整洁。

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs` | `ChatWidget` 主实现，包含状态管理 |
| `codex-rs/tui_app_server/src/bottom_pane/mod.rs` | 底部面板实现，包含状态指示器渲染 |
| `codex-rs/tui_app_server/src/status_indicator_widget.rs` | 状态指示器小部件实现 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试实现，包含 `unified_exec_wait_status_renders_command_in_single_details_row_snapshot` |

### 关键代码路径
```rust
// status_indicator_widget.rs: render
pub fn render(&self, area: Rect, buf: &mut Buffer) {
    // 渲染状态头
    let header = self.format_header();
    buf.set_line(area.x, area.y, &header, area.width);
    
    // 渲染详情行（如果存在）
    if let Some(details) = &self.details {
        let truncated = truncate_to_width(details, area.width.saturating_sub(4));
        let line = Line::from(vec![
            "  └ ".into(),
            truncated.into(),
        ]);
        buf.set_line(area.x, area.y + 1, &line, area.width);
    }
}

// text_formatting.rs: truncate_to_width
pub fn truncate_to_width(text: &str, max_width: u16) -> String {
    let mut result = String::new();
    let mut current_width = 0;
    
    for ch in text.chars() {
        let char_width = ch.width().unwrap_or(0) as u16;
        if current_width + char_width > max_width.saturating_sub(1) {
            result.push('…');
            break;
        }
        result.push(ch);
        current_width += char_width;
    }
    
    result
}
```

### 数据结构
```rust
// StatusIndicatorState
pub struct StatusIndicatorState {
    pub header: String,
    pub details: Option<String>,
    pub elapsed_secs: Option<u64>,
    pub show_interrupt_hint: bool,
}

// UnifiedExecWaitState
struct UnifiedExecWaitState {
    command_display: String,  // 用于显示的命令字符串
}
```

## 依赖与外部交互

### 内部依赖
- `ratatui::buffer::Buffer`：TUI 缓冲区操作
- `ratatui::layout::Rect`：布局矩形
- `unicode_width::UnicodeWidthChar`：字符宽度计算

### 外部交互
- `BottomPane::status_widget()`：获取状态指示器小部件
- `ChatWidget::desired_height()`：计算所需高度

### 渲染流程
```
TerminalInteraction (空输入)
    ↓
更新 current_status = WaitingForBackgroundTerminal
    ↓
设置 status.details = Some(command_display)
    ↓
render() 调用
    ↓
truncate_to_width(details, width - 4) → 截断命令
    ↓
渲染单行详情行
```

## 风险、边界与改进建议

### 潜在风险
1. **字符宽度计算错误**：某些 Unicode 字符的宽度计算可能不准确，导致截断位置错误
2. **ANSI 转义序列**：命令中包含的 ANSI 转义序列可能影响截断逻辑
3. **性能问题**：频繁的截断计算可能影响渲染性能

### 边界条件
- 极窄终端（< 20 字符）
- 包含多字节 Unicode 字符的命令
- 包含 ANSI 转义序列的命令
- 空命令或极短命令

### 改进建议
1. **增加 Unicode 测试**：验证各种 Unicode 字符的截断正确性
2. **增加 ANSI 序列处理**：确保 ANSI 转义序列不影响截断
3. **增加缓存机制**：对于不频繁变化的命令，缓存截断结果
4. **增加边界测试**：
   - 极窄终端宽度
   - 包含表情符号的命令
   - 包含组合字符的命令

### 相关测试
- `codex_tui_app_server__chatwidget__tests__status_widget_active.snap`：基础状态指示器测试
- `codex_tui_app_server__chatwidget__tests__status_widget_and_approval_modal.snap`：模态框叠加测试
- `codex_tui_app_server__chatwidget__tests__unified_exec_wait_status_header_updates_on_late_command_display.snap`：延迟命令显示测试
