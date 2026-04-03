# StatusIndicatorWidget - Details 换行渲染测试

## 场景与职责

该快照测试验证了 `StatusIndicatorWidget` 组件在处理长文本 details 时的自动换行功能。当 Agent 执行的操作需要显示额外上下文信息（如后台进程摘要）时，details 区域会将长文本智能换行显示，同时保持视觉层次清晰。

**典型使用场景：**
- 显示 unified-exec 后台进程的执行摘要
- 展示当前操作的具体上下文信息
- 在有限宽度内显示多行状态详情
- 保持主状态行的简洁性

## 功能点目的

### 核心功能
1. **智能文本换行**：根据可用宽度自动计算换行点
2. **视觉缩进**：使用前缀和缩进保持层次结构
3. **行数限制**：默认最多显示 3 行，超出部分截断
4. **首字母大写**：支持自动首字母大写格式化

### 渲染输出分析
根据快照内容：
```
"• Working (0s)                "
"  └ A man a plan a canal      "
"    panama                    "
```

- 第一行：主状态行（spinner + Working + 时间）
- 第二行：Details 第一行，带 "  └ " 前缀
- 第三行：Details 第二行，带 "    " 缩进
- 总宽度：30 字符（测试用例设置）
- 内容宽度：26 字符（30 - 4 字符前缀）

### 换行逻辑
测试用例特意选择 30 字符宽度：
- 内容 "A man a plan a canal panama" 共 27 个字符
- 可用宽度 26 字符，刚好在 "panama" 前换行
- 验证了一处换行而不产生省略号的场景

## 具体技术实现

### Details 换行核心算法

```rust
fn wrapped_details_lines(&self, width: u16) -> Vec<Line<'static>> {
    let Some(details) = self.details.as_deref() else {
        return Vec::new();
    };
    if width == 0 {
        return Vec::new();
    }

    let prefix_width = UnicodeWidthStr::width(DETAILS_PREFIX);  // "  └ " = 4 字符
    let opts = RtOptions::new(usize::from(width))
        .initial_indent(Line::from(DETAILS_PREFIX.dim()))
        .subsequent_indent(Line::from(Span::from(" ".repeat(prefix_width)).dim()))
        .break_words(/*break_words*/ true);

    let mut out = word_wrap_lines(details.lines().map(|line| vec![line.dim()]), opts);

    // 行数限制和省略号处理
    if out.len() > self.details_max_lines {
        out.truncate(self.details_max_lines);
        let content_width = usize::from(width).saturating_sub(prefix_width).max(1);
        let max_base_len = content_width.saturating_sub(1);
        if let Some(last) = out.last_mut()
            && let Some(span) = last.spans.last_mut()
        {
            let trimmed: String = span.content.as_ref().chars().take(max_base_len).collect();
            *span = format!("{trimmed}…").dim();
        }
    }

    out
}
```

### 关键常量

```rust
pub(crate) const STATUS_DETAILS_DEFAULT_MAX_LINES: usize = 3;
const DETAILS_PREFIX: &str = "  └ ";
```

### 文本格式化

```rust
pub(crate) fn update_details(
    &mut self,
    details: Option<String>,
    capitalization: StatusDetailsCapitalization,
    max_lines: usize,
) {
    self.details_max_lines = max_lines.max(1);
    self.details = details
        .filter(|details| !details.is_empty())
        .map(|details| {
            let trimmed = details.trim_start();
            match capitalization {
                StatusDetailsCapitalization::CapitalizeFirst => capitalize_first(trimmed),
                StatusDetailsCapitalization::Preserve => trimmed.to_string(),
            }
        });
}
```

### 测试实现

```rust
#[test]
fn renders_wrapped_details_panama_two_lines() {
    let (tx_raw, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx_raw);
    let mut w = StatusIndicatorWidget::new(tx, crate::tui::FrameRequester::test_dummy(), false);
    w.update_details(
        Some("A man a plan a canal panama".to_string()),
        StatusDetailsCapitalization::CapitalizeFirst,
        STATUS_DETAILS_DEFAULT_MAX_LINES,
    );
    w.set_interrupt_hint_visible(false);

    // 冻结时间相关渲染以保持快照稳定
    w.is_paused = true;
    w.elapsed_running = Duration::ZERO;

    // 前缀 4 列，宽度 30 产生内容宽度 26
    // 刚好比整个短语（27 列）少一列，强制一次换行而不产生省略号
    let mut terminal = Terminal::new(TestBackend::new(30, 3)).expect("terminal");
    terminal
        .draw(|f| w.render(f.area(), f.buffer_mut()))
        .expect("draw");
    insta::assert_snapshot!(terminal.backend());
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/status_indicator_widget.rs` | 主实现文件 |
| `codex-rs/tui/src/wrapping.rs` | `word_wrap_lines()` 和 `RtOptions` 实现 |
| `codex-rs/tui/src/text_formatting.rs` | `capitalize_first()` 实现 |
| `codex-rs/tui/src/line_truncation.rs` | 行截断工具 |

### Wrapping 模块依赖

```rust
// wrapping.rs
pub struct RtOptions {
    width: usize,
    initial_indent: Line<'static>,
    subsequent_indent: Line<'static>,
    break_words: bool,
}

pub fn word_wrap_lines(
    lines: impl Iterator<Item = Vec<Span<'static>>>,
    opts: RtOptions,
) -> Vec<Line<'static>> {
    // 使用 textwrap 库进行智能换行
}
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `textwrap` | 智能文本换行算法 |
| `unicode-width` | 准确计算 Unicode 字符宽度 |
| `ratatui` | Line、Span、Buffer 等渲染类型 |

### 样式应用

- **前缀样式**：`.dim()` - 暗淡灰色
- **内容样式**：`.dim()` - 与前缀一致
- **缩进**：使用空格字符串保持对齐

## 风险、边界与改进建议

### 潜在风险

1. **Unicode 宽度计算**：
   - 使用 `UnicodeWidthStr::width()` 计算显示宽度
   - 风险：某些特殊字符（如零宽字符、组合字符）可能计算不准确
   - 可能导致换行位置偏移

2. **单词截断**：
   - `break_words: true` 允许在单词中间断开
   - 对于中文等无空格语言，可能产生不自然的断行

3. **性能考虑**：
   - 每次渲染都重新计算换行
   - 对于非常长的 details 文本，可能影响渲染性能

### 边界情况

1. **零宽度终端**：
   - 代码检查 `width == 0` 直接返回空
   - 防止除以零或无效计算

2. **超长单词**：
   - 单个单词超过可用宽度时强制截断
   - 测试用例 `details_overflow_adds_ellipsis` 验证

3. **多行 Details**：
   - 输入文本包含换行符时，每行独立处理
   - 总结果仍受 `details_max_lines` 限制

4. **行数限制边界**：
   ```rust
   // 测试用例验证 1 行限制
   w.update_details(..., 1);
   ```

### 改进建议

1. **缓存优化**：
   - 缓存 details 的换行结果，避免重复计算
   - 仅在 details 或宽度变化时重新计算

2. **更好的中文支持**：
   - 考虑使用 `textwrap` 的 `WordSeparator` 自定义
   - 对 CJK 字符使用不同的断行策略

3. **可配置前缀**：
   - 当前前缀 "  └ " 为硬编码
   - 建议添加配置选项支持不同视觉风格

4. **省略号位置优化**：
   - 当前在最后一行末尾添加省略号
   - 考虑在中间截断时添加省略号（如 "beginning…end"）

5. **富文本支持**：
   - 当前 details 仅支持纯文本
   - 可考虑支持简单的样式标记

### 相关测试

- `renders_wrapped_details_panama_two_lines`：基础换行测试
- `details_overflow_adds_ellipsis`：溢出省略号测试
- `details_args_can_disable_capitalization_and_limit_lines`：参数验证测试

### 样式约定参考

根据项目 `styles.md`：
- 使用 `"  └ ".dim()` 作为前缀
- 使用空格缩进保持对齐
- 内容使用暗淡样式与主状态行区分
