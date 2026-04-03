# StatusIndicatorWidget - Working Header 渲染快照研究文档

## 场景与职责

`StatusIndicatorWidget` 是 Codex TUI 中用于显示**实时任务状态**的组件，位于底部输入框上方。当 Agent 正在处理任务时，该组件向用户提供视觉反馈，显示当前工作状态、已用时间以及中断提示。

**核心职责：**
- 显示动态状态头部（如 "Working"）配合旋转动画
- 显示任务执行时间（秒/分钟/小时格式）
- 提供中断提示（"esc to interrupt"）
- 支持可选的内联消息和详细说明文本
- 管理计时器的暂停/恢复状态

**本快照场景：** 测试组件在默认配置下的基础渲染效果，验证标准 "Working" 头部、0秒计时和中断提示的正确显示。

---

## 功能点目的

### 1. 状态头部显示
- **目的**：告知用户 Agent 当前正在工作
- **实现**：使用 `shimmer` 效果为 "Working" 文本添加动态视觉反馈
- **可定制性**：支持通过 `update_header()` 动态更新头部文本

### 2. 计时器显示
- **目的**：让用户了解任务已执行时长
- **格式化**：`fmt_elapsed_compact()` 函数提供人类友好的时间格式
  - 0-59秒：`Xs`
  - 1-59分钟：`Xm XXs`
  - 1小时+：`Xh XXm XXs`

### 3. 中断提示
- **目的**：告知用户如何中断当前任务
- **显示**：`(0s • esc to interrupt)`
- **可控制**：可通过 `set_interrupt_hint_visible()` 隐藏

### 4. 动画效果
- **Spinner**：基于时间的旋转指示器
- **Shimmer**：文本颜色渐变动画效果
- **帧率控制**：通过 `FrameRequester` 以 ~30fps 调度渲染

---

## 具体技术实现

### 核心数据结构

```rust
pub(crate) struct StatusIndicatorWidget {
    header: String,                          // 状态头部文本
    details: Option<String>,                 // 详细说明（多行支持）
    details_max_lines: usize,                // 详情最大行数限制
    inline_message: Option<String>,          // 内联后缀消息
    show_interrupt_hint: bool,               // 是否显示中断提示
    
    elapsed_running: Duration,               // 累计运行时间
    last_resume_at: Instant,                 // 上次恢复时间点
    is_paused: bool,                         // 计时器暂停状态
    
    app_event_tx: AppEventSender,            // 应用事件发送器
    frame_requester: FrameRequester,         // 帧请求器（动画调度）
    animations_enabled: bool,                // 动画开关
}
```

### 渲染流程

```rust
fn render(&self, area: Rect, buf: &mut Buffer) {
    // 1. 调度下一帧动画（32ms ≈ 30fps）
    self.frame_requester.schedule_frame_in(Duration::from_millis(32));
    
    // 2. 计算已用时间
    let elapsed = self.elapsed_duration_at(Instant::now());
    let pretty_elapsed = fmt_elapsed_compact(elapsed.as_secs());
    
    // 3. 构建 spans 序列
    let mut spans = Vec::with_capacity(5);
    spans.push(spinner(...));                    // 旋转指示器
    spans.push(" ".into());
    spans.extend(shimmer_spans(&self.header));   // 闪烁效果头部
    spans.push(" ".into());
    spans.extend([                               // 时间 + 中断提示
        format!("({pretty_elapsed} • ").dim(),
        key_hint::plain(KeyCode::Esc).into(),
        " to interrupt)".dim(),
    ]);
    
    // 4. 截断处理并渲染
    lines.push(truncate_line_with_ellipsis_if_overflow(...));
}
```

### 计时器管理

```rust
// 暂停计时器
pub(crate) fn pause_timer_at(&mut self, now: Instant) {
    self.elapsed_running += now.saturating_duration_since(self.last_resume_at);
    self.is_paused = true;
}

// 恢复计时器
pub(crate) fn resume_timer_at(&mut self, now: Instant) {
    self.last_resume_at = now;
    self.is_paused = false;
    self.frame_requester.schedule_frame();  // 触发重绘
}
```

---

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/status_indicator_widget.rs` | 主组件实现，包含渲染逻辑和计时器管理 |
| `codex-rs/tui/src/shimmer.rs` | Shimmer 动画效果实现（颜色渐变） |
| `codex-rs/tui/src/key_hint.rs` | 键盘快捷键提示渲染（如 "esc"） |
| `codex-rs/tui/src/line_truncation.rs` | 行截断处理（带省略号） |
| `codex-rs/tui/src/wrapping.rs` | 文本换行处理（用于 details） |
| `codex-rs/tui/src/exec_cell.rs` (引用) | Spinner 动画实现 |
| `codex-rs/tui/src/app_event.rs` | 应用事件定义（如 Interrupt） |
| `codex-rs/tui/src/tui.rs` | FrameRequester 定义（帧调度） |

### 测试代码位置

```rust
// codex-rs/tui/src/status_indicator_widget.rs:319-331
#[test]
fn renders_with_working_header() {
    let (tx_raw, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx_raw);
    let w = StatusIndicatorWidget::new(tx, crate::tui::FrameRequester::test_dummy(), true);

    // Render into a fixed-size test terminal and snapshot the backend.
    let mut terminal = Terminal::new(TestBackend::new(80, 2)).expect("terminal");
    terminal
        .draw(|f| w.render(f.area(), f.buffer_mut()))
        .expect("draw");
    insta::assert_snapshot!(terminal.backend());
}
```

---

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `ratatui` | TUI 渲染框架（Buffer, Rect, Line, Span, Paragraph, WidgetRef） |
| `crossterm` | 键盘事件定义（KeyCode） |
| `unicode-width` | Unicode 字符串宽度计算 |
| `codex_protocol` | Op::Interrupt 事件类型 |

### 内部模块交互

```
StatusIndicatorWidget
├── shimmer_spans() ← shimmer.rs (动画效果)
├── spinner() ← exec_cell.rs (旋转指示器)
├── key_hint::plain() ← key_hint.rs (按键提示)
├── truncate_line_with_ellipsis_if_overflow() ← line_truncation.rs
├── word_wrap_lines() ← wrapping.rs (details 换行)
├── AppEvent::CodexOp(Op::Interrupt) ← app_event.rs
└── FrameRequester ← tui.rs (动画帧调度)
```

### 事件流

```
用户按下 Esc
    ↓
AppEvent::CodexOp(Op::Interrupt)
    ↓
status_indicator_widget.interrupt() 发送事件
    ↓
上层处理中断逻辑
```

---

## 风险、边界与改进建议

### 已知风险

1. **时间精度问题**
   - 使用 `Instant::now()` 在测试时可能不稳定
   - 解决方案：测试中冻结时间（`is_paused = true`）

2. **宽度溢出**
   - 终端宽度不足时内容被截断
   - 缓解措施：`truncate_line_with_ellipsis_if_overflow` 处理

3. **动画性能**
   - 30fps 动画在低端终端可能消耗 CPU
   - 缓解措施：`animations_enabled` 开关控制

### 边界情况

| 场景 | 行为 |
|-----|------|
| 终端宽度 < 内容长度 | 截断并显示省略号 |
| 动画被禁用 | 显示静态文本，无 shimmer/spinner |
| 中断提示被隐藏 | 仅显示 `(Xs)` 格式时间 |
| 计时器暂停 | 时间停止累加，UI 冻结 |
| 头部为空 | 跳过 shimmer 渲染 |

### 改进建议

1. **可访问性增强**
   - 添加屏幕阅读器支持（ARIA 标签等效物）
   - 为色盲用户提供非颜色指示器选项

2. **配置扩展**
   - 支持自定义刷新率（当前固定 32ms）
   - 支持自定义时间格式

3. **性能优化**
   - 考虑使用 `ratatui` 的 `Canvas` 或自定义 `Widget` 优化重绘区域
   - 仅在内容变化时请求重绘

4. **测试覆盖**
   - 添加高对比度主题下的视觉测试
   - 添加不同终端宽度下的响应式测试

5. **国际化**
   - "Working" 和 "esc to interrupt" 支持本地化
   - 时间格式遵循区域设置
