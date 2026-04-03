# StatusIndicatorWidget - Working Header 渲染测试

## 场景与职责

该快照测试验证了 `StatusIndicatorWidget` 组件在基础工作状态下的渲染输出。`StatusIndicatorWidget` 是 TUI（终端用户界面）中的一个核心组件，用于在 Agent 忙碌时显示实时任务状态行。它位于输入框上方，提供视觉反馈，告知用户当前系统正在执行操作。

**典型使用场景：**
- 当 Codex 正在处理用户请求时显示工作状态
- 提供可中断操作的提示（ESC 键中断）
- 显示已运行时间，帮助用户了解操作持续时间
- 在有限空间内避免垂直布局抖动

## 功能点目的

### 核心功能
1. **实时状态显示**：显示动态旋转的 spinner 和 "Working" 标题
2. **运行时间追踪**：显示任务已运行时间（如 "0s"）
3. **中断提示**：显示 "esc to interrupt" 提示用户可中断操作
4. **动画支持**：支持 shimmer 动画效果增强视觉反馈

### 渲染输出分析
根据快照内容：
```
"• Working (0s • esc to interrupt)                                               "
"                                                                                "
```

- 第一行：包含 spinner（•）、标题（Working）、运行时间（0s）和中断提示
- 第二行：空行，为 details 预留空间
- 总宽度：80 字符（标准终端宽度）

## 具体技术实现

### 关键数据结构

```rust
pub(crate) struct StatusIndicatorWidget {
    header: String,                    // 动画标题（默认 "Working"）
    details: Option<String>,           // 可选的详细信息
    details_max_lines: usize,          // 详情最大行数（默认 3）
    inline_message: Option<String>,    // 内联消息后缀
    show_interrupt_hint: bool,         // 是否显示中断提示
    elapsed_running: Duration,         // 已运行时间
    last_resume_at: Instant,           // 上次恢复时间
    is_paused: bool,                   // 计时器是否暂停
    app_event_tx: AppEventSender,      // 应用事件发送器
    frame_requester: FrameRequester,   // 帧请求器
    animations_enabled: bool,          // 动画是否启用
}
```

### 渲染流程

1. **Spinner 渲染**（`spinner()` 函数）：
   - 基于时间计算旋转帧
   - 使用 `last_resume_at` 确保动画连续性

2. **标题渲染**（`shimmer_spans()`）：
   - 如果启用了动画，使用 shimmer 效果
   - 否则直接显示静态文本

3. **时间格式化**（`fmt_elapsed_compact()`）：
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
       // ... 小时格式
   }
   ```

4. **中断提示渲染**（`key_hint::plain()`）：
   - 使用 `KeyCode::Esc` 生成按键提示
   - 以暗淡样式显示

### 测试实现

```rust
#[test]
fn renders_with_working_header() {
    let (tx_raw, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx_raw);
    let w = StatusIndicatorWidget::new(tx, crate::tui::FrameRequester::test_dummy(), true);

    // 渲染到固定大小的测试终端
    let mut terminal = Terminal::new(TestBackend::new(80, 2)).expect("terminal");
    terminal
        .draw(|f| w.render(f.area(), f.buffer_mut()))
        .expect("draw");
    insta::assert_snapshot!(terminal.backend());
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/status_indicator_widget.rs` | 主实现文件，包含组件逻辑和渲染 |
| `codex-rs/tui/src/exec_cell.rs` | `spinner()` 函数实现 |
| `codex-rs/tui/src/shimmer.rs` | `shimmer_spans()` 动画效果 |
| `codex-rs/tui/src/key_hint.rs` | 按键提示渲染 |
| `codex-rs/tui/src/line_truncation.rs` | 行截断处理 |
| `codex-rs/tui/src/wrapping.rs` | 文本换行处理 |

### 相关 Trait 实现

```rust
impl Renderable for StatusIndicatorWidget {
    fn desired_height(&self, width: u16) -> u16 {
        1 + u16::try_from(self.wrapped_details_lines(width).len()).unwrap_or(0)
    }

    fn render(&self, area: Rect, buf: &mut Buffer) {
        // ... 渲染实现
    }
}
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `ratatui` | 终端 UI 渲染框架 |
| `crossterm` | 跨平台终端控制（KeyCode） |
| `unicode-width` | Unicode 字符宽度计算 |
| `tokio` | 异步运行时（事件通道） |
| `codex_protocol` | 协议定义（Op::Interrupt） |

### 事件交互

- **发送事件**：通过 `app_event_tx` 发送 `AppEvent::CodexOp(Op::Interrupt)`
- **帧请求**：通过 `frame_requester.schedule_frame()` 请求重绘

## 风险、边界与改进建议

### 潜在风险

1. **时间精度问题**：
   - 使用 `Instant::now()` 获取当前时间，在测试中使用 `is_paused` 和固定时间来确保快照稳定性
   - 风险：系统时间调整可能影响计时器准确性

2. **宽度截断**：
   - 当终端宽度不足时，内容会被截断
   - 当前实现使用 `truncate_line_with_ellipsis_if_overflow` 处理溢出

3. **动画性能**：
   - 每 32ms 请求一次帧更新
   - 在高负载系统上可能影响性能

### 边界情况

1. **极窄终端**：
   - 测试用例 `renders_truncated` 验证 20 字符宽度下的渲染
   - 关键信息（spinner、时间）应优先保留

2. **长时间运行**：
   - 时间格式支持到小时级别（"25h 02m 03s"）
   - 超过 24 小时仍会继续计数

3. **Details 溢出**：
   - 默认最多显示 3 行 details
   - 超出部分使用省略号截断

### 改进建议

1. **可配置性**：
   - 考虑添加配置选项自定义 spinner 样式
   - 支持自定义时间格式

2. **可访问性**：
   - 考虑添加屏幕阅读器支持
   - 提供无动画模式（已通过 `animations_enabled` 支持）

3. **测试覆盖**：
   - 添加更多边界测试（如 1 字符宽度、超大时间值）
   - 测试不同 `details_max_lines` 配置

4. **国际化**：
   - 当前 "Working" 和 "esc to interrupt" 为硬编码英文
   - 建议添加本地化支持

### 相关测试

- `renders_with_working_header`：基础渲染测试
- `renders_truncated`：窄终端渲染测试
- `renders_wrapped_details_panama_two_lines`：Details 换行测试
- `timer_pauses_when_requested`：计时器暂停功能测试
- `details_overflow_adds_ellipsis`：溢出处理测试
