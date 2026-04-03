# Status Indicator Widget 截断渲染研究文档

## 场景与职责

该快照测试验证 **StatusIndicatorWidget** 在终端宽度不足时的截断渲染行为。当状态行内容超出可用宽度时，组件需要优雅地截断并添加省略号，确保关键信息（如工作状态和中断提示）尽可能可见。

### 核心职责
- 显示当前工作状态（如 "Working"）
- 显示已运行时间
- 显示中断提示（"esc to interrupt"）
- 在宽度不足时智能截断

### 使用场景
- 用户调整终端窗口至极窄尺寸
- 状态信息较长（如包含 inline message）
- 确保核心信息（spinner + 时间 + 中断提示）优先显示

## 功能点目的

### 1. 智能截断
- 使用 `truncate_line_with_ellipsis_if_overflow` 函数
- 超出宽度时添加省略号（…）
- 保留行首关键信息

### 2. 核心信息优先
状态行结构（优先级从高到低）：
1. Spinner（•）- 必须显示
2. 工作状态（"Working"）- 必须显示
3. 已运行时间（"0s"）- 尽量显示
4. 中断提示（"esc to interrupt"）- 宽度允许时显示

### 3. 响应式布局
- 根据可用宽度动态调整显示内容
- 窄宽度下可能只显示部分信息

## 具体技术实现

### 关键数据结构

```rust
pub(crate) struct StatusIndicatorWidget {
    header: String,                     // 工作状态标题（默认 "Working"）
    details: Option<String>,            // 详情文本（显示在主行下方）
    details_max_lines: usize,           // 详情最大行数
    inline_message: Option<String>,     // 行内附加消息
    show_interrupt_hint: bool,          // 是否显示中断提示
    elapsed_running: Duration,          // 已运行时间
    last_resume_at: Instant,            // 上次恢复时间
    is_paused: bool,                    // 是否暂停计时
    app_event_tx: AppEventSender,       // 事件发送器
    frame_requester: FrameRequester,    // 帧请求器
    animations_enabled: bool,           // 动画是否启用
}
```

### 截断处理流程

```rust
impl Renderable for StatusIndicatorWidget {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        // ... 构建 spans ...
        
        let mut lines = Vec::new();
        // 截断第一行（状态行）
        lines.push(truncate_line_with_ellipsis_if_overflow(
            Line::from(spans),
            usize::from(area.width),
        ));
        
        // 如果有足够空间，添加详情行
        if area.height > 1 {
            let details = self.wrapped_details_lines(area.width);
            let max_details = usize::from(area.height.saturating_sub(1));
            lines.extend(details.into_iter().take(max_details));
        }
        
        Paragraph::new(Text::from(lines)).render_ref(area, buf);
    }
}
```

### 截断函数

```rust
// line_truncation.rs
pub fn truncate_line_with_ellipsis_if_overflow(line: Line<'_>, max_width: usize) -> Line<'static> {
    let width = line.width();
    if width <= max_width {
        return line.into_owned();
    }
    
    // 需要截断
    let mut spans = line.spans.into_iter().peekable();
    let mut result = Vec::new();
    let mut current_width = 0;
    
    // 尽可能添加完整的 span
    while let Some(span) = spans.next() {
        let span_width = span.width();
        if current_width + span_width > max_width.saturating_sub(1) {
            // 空间不足，添加省略号并退出
            break;
        }
        current_width += span_width;
        result.push(span);
    }
    
    // 添加省略号
    result.push("…".into());
    Line::from(result)
}
```

### 测试用例分析

```rust
#[test]
fn renders_truncated() {
    // 1. 创建 widget
    let (tx_raw, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx_raw);
    let w = StatusIndicatorWidget::new(
        tx, 
        crate::tui::FrameRequester::test_dummy(), 
        true
    );

    // 2. 使用极窄终端（20字符宽）
    let mut terminal = Terminal::new(TestBackend::new(20, 2)).expect("terminal");
    terminal
        .draw(|f| w.render(f.area(), f.buffer_mut()))
        .expect("draw");
    
    // 3. 验证快照
    insta::assert_snapshot!(terminal.backend());
}
```

### 快照输出解析

```
"• Working (0s • esc…"   // 第一行：截断状态行
"                    "   // 第二行：空行（高度为2，但无详情）
```

**截断分析**：
- 原始内容：`• Working (0s • esc to interrupt)`
- 可用宽度：20 字符
- 截断后：`• Working (0s • esc…`
- 省略号位置：在 "esc" 后，" to interrupt" 被截断

## 关键代码路径与文件引用

### 核心文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/status_indicator_widget.rs` | StatusIndicatorWidget 实现 |
| `codex-rs/tui/src/line_truncation.rs` | 行截断工具函数 |

### 关键函数

1. **渲染**
   - `StatusIndicatorWidget::render()` (line 237-289)
   - `truncate_line_with_ellipsis_if_overflow()` (line_truncation.rs)

2. **构建状态行**
   - Spinner: `spinner()` (line 252)
   - Header: `shimmer_spans()` 或直接使用 (line 254-258)
   - 时间: `fmt_elapsed_compact()` (line 249, 262-268)
   - 中断提示: `key_hint::plain(KeyCode::Esc)` (line 263)

3. **测试**
   - `renders_truncated()` (line 334-345)

### 状态行构建流程

```rust
let mut spans = Vec::with_capacity(5);

// 1. Spinner
spans.push(spinner(Some(self.last_resume_at), self.animations_enabled));
spans.push(" ".into());

// 2. Header（带动画效果）
if self.animations_enabled {
    spans.extend(shimmer_spans(&self.header));
} else {
    spans.push(self.header.clone().into());
}
spans.push(" ".into());

// 3. 时间和中断提示
if self.show_interrupt_hint {
    spans.extend(vec![
        format!("({pretty_elapsed} • ").dim(),
        key_hint::plain(KeyCode::Esc).into(),
        " to interrupt)".dim(),
    ]);
} else {
    spans.push(format!("({pretty_elapsed})").dim());
}

// 4. 行内消息（如果有）
if let Some(message) = &self.inline_message {
    spans.push(" · ".dim());
    spans.push(message.clone().dim());
}
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `ratatui` | 终端 UI 框架，提供 `Line`, `Span`, `Buffer`, `Rect` |
| `unicode_width` | Unicode 宽度计算 |
| `crossterm` | 键盘事件（`KeyCode::Esc`） |

### 内部模块交互

```
status_indicator_widget.rs
├── line_truncation.rs (truncate_line_with_ellipsis_if_overflow)
├── exec_cell::spinner() (旋转动画)
├── shimmer::shimmer_spans() (闪烁效果)
├── key_hint.rs (快捷键提示)
├── text_formatting::capitalize_first() (首字母大写)
└── wrapping.rs (详情文本换行)
```

### 与 App 的交互

```rust
// App 创建并更新 StatusIndicatorWidget
let mut status_widget = StatusIndicatorWidget::new(
    app_event_tx.clone(),
    frame_requester.clone(),
    config.ui_animations,
);

// 更新状态
status_widget.update_header("Working".to_string());
status_widget.update_details(
    Some("Running cargo build".to_string()),
    StatusDetailsCapitalization::CapitalizeFirst,
    STATUS_DETAILS_DEFAULT_MAX_LINES,
);
```

## 风险、边界与改进建议

### 潜在风险

1. **截断位置不当**
   - 当前截断可能发生在关键信息中间
   - 例如 "esc" 后截断，用户可能看不到中断提示

2. **Unicode 宽度计算**
   - 多字节字符（如中文）宽度计算可能不准确
   - 可能导致显示错位

3. **动画与截断冲突**
   - `shimmer_spans` 产生动态内容
   - 截断可能破坏动画效果

### 边界情况

1. **极窄终端**
   - 宽度小于最小内容时，只显示省略号
   - 建议设置最小宽度限制

2. **空内容**
   - `header` 为空时，状态行可能以空格开头

3. **详情截断**
   - 详情行使用 `wrapped_details_lines` 处理
   - 超出 `details_max_lines` 时添加省略号

### 改进建议

1. **智能截断**
   - 优先截断低优先级部分（如 inline message）
   - 保留核心信息（spinner + header + 时间）

2. **最小宽度保证**
   - 设置组件最小宽度
   - 低于最小宽度时显示简化版本

3. **截断指示**
   - 截断时显示特殊指示（如 `<` 符号）
   - 提示用户有更多内容

4. **响应式内容**
   - 根据宽度动态调整显示内容
   - 窄宽度下隐藏次要信息

5. **测试增强**
   - 增加不同宽度的截断测试
   - 增加 Unicode 字符截断测试
