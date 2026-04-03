# StatusIndicatorWidget 研究文档

## 场景与职责

`StatusIndicatorWidget` 是 Codex TUI 中显示代理任务执行状态的核心 UI 组件。它在用户提交任务后显示在底部面板上方，提供：

- **实时状态反馈**：显示 "Working" 等动态标题
- **执行计时**：显示已用时间（如 "1m 30s"）
- **中断提示**：显示 "esc to interrupt" 提示
- **详细信息**：可选的多行详情文本（如正在执行的命令）
- **内联消息**：显示额外的上下文信息（如后台进程摘要）

该组件位于 `codex-rs/tui_app_server/src/status_indicator_widget.rs`，是 TUI 渲染系统的关键部分。

## 功能点目的

### 1. 动态状态展示

显示代理正在执行的任务状态，包括：
- 动画标题（默认 "Working"，可通过 `update_header` 修改）
- 可选的详细描述（如正在执行的命令）
- 内联消息（如后台进程信息）

### 2. 执行计时

精确跟踪任务执行时间：
- 支持暂停/恢复计时（用于等待用户输入时）
- 格式化显示：0-59秒显示为 "Xs"，60-3599秒显示为 "Xm XXs"，超过1小时显示为 "Xh XXm XXs"

### 3. 动画效果

当 `animations_enabled` 为 true 时：
- 使用 `shimmer_spans` 实现标题的闪光动画效果
- 每 32ms 请求一次重绘，形成平滑动画

### 4. 文本换行与截断

- 使用 `word_wrap_lines` 对详情文本进行智能换行
- 支持最大行数限制（默认 3 行）
- 超长文本使用省略号截断

## 具体技术实现

### 核心数据结构

```rust
pub(crate) struct StatusIndicatorWidget {
    /// 动画标题文本（默认 "Working"）
    header: String,
    /// 可选的详情文本
    details: Option<String>,
    /// 详情最大行数
    details_max_lines: usize,
    /// 可选的内联后缀消息
    inline_message: Option<String>,
    /// 是否显示中断提示
    show_interrupt_hint: bool,
    /// 累计运行时间（用于暂停/恢复）
    elapsed_running: Duration,
    /// 上次恢复计时的时间点
    last_resume_at: Instant,
    /// 计时是否暂停
    is_paused: bool,
    /// 应用事件发送器（用于发送中断命令）
    app_event_tx: AppEventSender,
    /// 帧请求器（用于动画调度）
    frame_requester: FrameRequester,
    /// 动画是否启用
    animations_enabled: bool,
}
```

### 时间格式化实现

```rust
pub fn fmt_elapsed_compact(elapsed_secs: u64) -> String {
    if elapsed_secs < 60 {
        return format!("{elapsed_secs}s");
    }
    if elapsed_secs < 3600 {
        let minutes = elapsed_secs / 60;
        let seconds = elapsed_secs % 60;
        return format!("{minutes}m {seconds:02}s");
    }
    let hours = elapsed_secs / 3600;
    let minutes = (elapsed_secs % 3600) / 60;
    let seconds = elapsed_secs % 60;
    format!("{hours}h {minutes:02}m {seconds:02}s")
}
```

### 渲染实现

```rust
impl Renderable for StatusIndicatorWidget {
    fn desired_height(&self, width: u16) -> u16 {
        1 + u16::try_from(self.wrapped_details_lines(width).len()).unwrap_or(0)
    }

    fn render(&self, area: Rect, buf: &mut Buffer) {
        if area.is_empty() {
            return;
        }

        if self.animations_enabled {
            // 调度下一帧动画
            self.frame_requester
                .schedule_frame_in(Duration::from_millis(32));
        }
        
        // 构建状态行：spinner + 标题 + 时间 + 中断提示 + 内联消息
        let mut spans = Vec::with_capacity(5);
        spans.push(spinner(Some(self.last_resume_at), self.animations_enabled));
        spans.push(" ".into());
        // ... 更多渲染逻辑
    }
}
```

### 详情文本换行

```rust
fn wrapped_details_lines(&self, width: u16) -> Vec<Line<'static>> {
    let Some(details) = self.details.as_deref() else {
        return Vec::new();
    };
    
    let prefix_width = UnicodeWidthStr::width(DETAILS_PREFIX);
    let opts = RtOptions::new(usize::from(width))
        .initial_indent(Line::from(DETAILS_PREFIX.dim()))
        .subsequent_indent(Line::from(Span::from(" ".repeat(prefix_width)).dim()))
        .break_words(true);

    let mut out = word_wrap_lines(details.lines().map(|line| vec![line.dim()]), opts);
    
    // 截断到最大行数并添加省略号
    if out.len() > self.details_max_lines {
        out.truncate(self.details_max_lines);
        // 在最后一行添加省略号...
    }
    out
}
```

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/status_indicator_widget.rs` (438 行)

### 调用方
- `bottom_pane/mod.rs` - 创建和管理状态指示器
- `chatwidget.rs` - 控制状态指示器的显示/隐藏

### 依赖模块
| 模块 | 用途 |
|------|------|
| `exec_cell::spinner` | 提供旋转动画 |
| `shimmer::shimmer_spans` | 提供标题闪光效果 |
| `line_truncation` | 行截断工具 |
| `wrapping` | 文本换行 |
| `text_formatting::capitalize_first` | 首字母大写 |
| `app_event_sender` | 发送中断事件 |
| `tui::FrameRequester` | 动画帧调度 |

### 关键常量
```rust
pub(crate) const STATUS_DETAILS_DEFAULT_MAX_LINES: usize = 3;
const DETAILS_PREFIX: &str = "  └ ";
```

## 依赖与外部交互

### 外部依赖
- `crossterm::event::KeyCode` - 键码定义
- `ratatui` - TUI 渲染框架
- `unicode_width` - Unicode 字符宽度计算
- `tokio::sync::mpsc` - 异步通道（测试用）

### 内部依赖
- `AppEventSender` - 用于发送中断命令
- `FrameRequester` - 用于调度动画帧
- `Renderable` trait - 统一渲染接口

## 风险、边界与改进建议

### 潜在风险

1. **动画性能**：每 32ms 请求重绘，在高负载或慢终端上可能影响性能。

2. **时间精度**：使用 `Instant::now()` 和 `saturating_duration_since`，在系统时间调整时可能不准确。

3. **内存使用**：`wrapped_details_lines` 每次渲染都重新计算，详情文本很长时可能产生临时分配。

### 边界情况

1. **零宽度区域**：渲染前检查 `area.is_empty()`，避免空区域渲染错误。

2. **超长文本**：详情文本超过 `details_max_lines` 时截断并添加省略号。

3. **暂停/恢复计时**：支持在特定状态下暂停计时（如等待用户输入），避免显示时间包含等待时间。

### 测试覆盖

组件包含全面的单元测试：
- `fmt_elapsed_compact_formats_seconds_minutes_hours` - 时间格式化
- `renders_with_working_header` - 基本渲染（快照测试）
- `renders_truncated` - 截断渲染（快照测试）
- `renders_wrapped_details_panama_two_lines` - 换行渲染（快照测试）
- `timer_pauses_when_requested` - 计时暂停/恢复
- `details_overflow_adds_ellipsis` - 溢出省略号
- `details_args_can_disable_capitalization_and_limit_lines` - 大写控制和行数限制

### 改进建议

1. **动画帧率配置**：将 32ms 硬编码改为可配置参数。

2. **缓存详情换行结果**：如果详情文本不变，缓存换行结果避免重复计算。

3. **渐进式详情显示**：对于非常长的详情，考虑实现滚动或折叠功能。

4. **多任务状态**：当前只支持单一状态显示，考虑支持多任务并行状态展示。

5. **可访问性**：添加屏幕阅读器支持，将状态变化通知辅助技术。
