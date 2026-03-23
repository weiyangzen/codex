# line_truncation.rs 深度研究文档

## 一、场景与职责

`line_truncation.rs` 是 Codex TUI 的文本行截断工具模块，提供**精确控制视觉宽度**的行截断功能。该模块专门解决以下问题：

1. **固定宽度 UI 元素的文本适配**：如状态栏、按钮、列表项等需要严格控制在指定列数内
2. **Unicode 宽度正确处理**：正确处理全角字符（CJK）、emoji 等宽字符的显示宽度
3. **样式保留**：截断过程中保持 ratatui 的样式信息（颜色、修饰符）
4. **溢出提示**：支持自动添加省略号（…）提示内容被截断

该模块是 TUI 中所有"固定宽度文本显示"的基础设施，被 footer、状态指示器、选择器等组件广泛使用。

## 二、功能点目的

### 2.1 核心功能

| 函数 | 目的 |
|------|------|
| `line_width` | 计算行的视觉宽度（考虑 Unicode 宽字符）|
| `truncate_line_to_width` | 将行截断到指定宽度，保留样式 |
| `truncate_line_with_ellipsis_if_overflow` | 截断并添加省略号（仅当溢出时）|

### 2.2 使用场景

| 场景 | 使用函数 | 示例 |
|------|----------|------|
| 状态栏固定宽度 | `truncate_line_with_ellipsis_if_overflow` | 文件名显示 |
| 按钮标签 | `truncate_line_to_width` | 确认/取消按钮 |
| 列表项 | `truncate_line_with_ellipsis_if_overflow` | 会话列表 |
| 提示信息 | `truncate_line_to_width` | 快捷键提示 |

## 三、具体技术实现

### 3.1 核心数据结构

该模块无自定义结构体，主要使用 ratatui 类型：

```rust
use ratatui::text::Line;
use ratatui::text::Span;
use unicode_width::UnicodeWidthChar;
use unicode_width::UnicodeWidthStr;
```

### 3.2 line_width 实现

```rust
pub(crate) fn line_width(line: &Line<'_>) -> usize {
    line.iter()
        .map(|span| UnicodeWidthStr::width(span.content.as_ref()))
        .sum()
}
```

**关键点**：
- 使用 `unicode_width` crate 的 `UnicodeWidthStr::width()`
- 正确处理：半角字符（1 列）、全角字符（2 列）、零宽字符（0 列）
- 遍历所有 span 累加宽度

### 3.3 truncate_line_to_width 实现

```rust
pub(crate) fn truncate_line_to_width(line: Line<'static>, max_width: usize) -> Line<'static> {
    if max_width == 0 {
        return Line::from(Vec::<Span<'static>>::new());
    }

    let Line { style, alignment, spans } = line;
    let mut used = 0usize;
    let mut spans_out: Vec<Span<'static>> = Vec::with_capacity(spans.len());

    for span in spans {
        let span_width = UnicodeWidthStr::width(span.content.as_ref());

        if span_width == 0 {
            spans_out.push(span);
            continue;
        }

        if used >= max_width {
            break;
        }

        if used + span_width <= max_width {
            used += span_width;
            spans_out.push(span);
            continue;
        }

        // 部分截断：按字符逐个检查
        let style = span.style;
        let text = span.content.as_ref();
        let mut end_idx = 0usize;
        for (idx, ch) in text.char_indices() {
            let ch_width = UnicodeWidthChar::width(ch).unwrap_or(0);
            if used + ch_width > max_width {
                break;
            }
            end_idx = idx + ch.len_utf8();
            used += ch_width;
        }

        if end_idx > 0 {
            spans_out.push(Span::styled(text[..end_idx].to_string(), style));
        }

        break;
    }

    Line { style, alignment, spans: spans_out }
}
```

**算法流程**：
1. **零宽度检查**：`max_width == 0` 返回空行
2. **逐个 span 处理**：
   - 零宽 span：直接保留
   - 完全容纳：累加宽度，保留 span
   - 部分容纳：逐字符截断
   - 已满：终止循环
3. **逐字符截断**：使用 `char_indices()` 遍历，检查每个字符宽度
4. **返回新行**：保留原行样式和对齐方式

### 3.4 truncate_line_with_ellipsis_if_overflow 实现

```rust
pub(crate) fn truncate_line_with_ellipsis_if_overflow(
    line: Line<'static>,
    max_width: usize,
) -> Line<'static> {
    if max_width == 0 {
        return Line::from(Vec::<Span<'static>>::new());
    }

    // 快速路径：未溢出直接返回
    if line_width(&line) <= max_width {
        return line;
    }

    // 截断并添加省略号
    let truncated = truncate_line_to_width(line, max_width.saturating_sub(1));
    let Line { style, alignment, mut spans } = truncated;
    let ellipsis_style = spans.last().map(|span| span.style).unwrap_or_default();
    spans.push(Span::styled("…", ellipsis_style));
    Line { style, alignment, spans }
}
```

**性能优化**：
- **快速路径**：先检查宽度，未溢出时直接返回原行（零分配）
- **省略号空间**：`max_width.saturating_sub(1)` 预留省略号位置
- **样式继承**：省略号使用最后一个 span 的样式

## 四、关键代码路径与文件引用

### 4.1 调用方分布

| 文件 | 使用场景 |
|------|----------|
| `status_indicator_widget.rs` | 状态指示器文本截断 |
| `bottom_pane/footer.rs` | 底部栏信息截断 |
| `bottom_pane/selection_popup_common.rs` | 选择弹出框项截断 |
| `bottom_pane/multi_select_picker.rs` | 多选选择器项截断 |
| `bottom_pane/chat_composer.rs` | 聊天输入框提示截断 |

### 4.2 典型使用模式

```rust
// footer.rs 示例
use crate::line_truncation::truncate_line_with_ellipsis_if_overflow;

let status_line = truncate_line_with_ellipsis_if_overflow(
    Line::from(format!("Editing: {}", filename)),
    available_width as usize
);
```

```rust
// 直接截断（无省略号）
use crate::line_truncation::truncate_line_to_width;

let truncated = truncate_line_to_width(line, 20);
```

### 4.3 依赖模块

| 模块 | 依赖内容 |
|------|----------|
| 无内部依赖 | 纯工具模块，仅依赖外部 crate |

## 五、依赖与外部交互

### 5.1 外部 crate

| Crate | 用途 |
|-------|------|
| `ratatui` | `Line`, `Span` 类型 |
| `unicode_width` | `UnicodeWidthChar`, `UnicodeWidthStr` |

### 5.2 依赖关系

```
line_truncation.rs
  ├── ratatui::text::{Line, Span}
  └── unicode_width::{UnicodeWidthChar, UnicodeWidthStr}
```

### 5.3 Unicode 宽度规则

| 字符类型 | 示例 | 宽度 |
|----------|------|------|
| ASCII | `a`, `1`, `!` | 1 |
| 拉丁扩展 | `é`, `ñ` | 1 |
| CJK | `你`, `好` | 2 |
| Emoji | `😀`, `🎉` | 2 |
| 零宽字符 | `\u{200B}` | 0 |
| 控制字符 | `\n`, `\t` | 0 或 1 |

## 六、风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 零宽字符处理 | 零宽字符宽度为 0，可能被意外保留 | 显式检查 `span_width == 0` |
| 组合字符 | 组合标记（如重音符号）宽度计算可能不准确 | 依赖 `unicode_width` crate 的实现 |
| 终端差异 | 不同终端对宽字符的显示可能不同 | 使用标准 East Asian Width 属性 |
| 性能 | 逐字符遍历在极长文本时可能有开销 | 通常用于短文本（UI 元素），影响有限 |

### 6.2 边界条件

1. **max_width = 0**：返回空行
2. **空行**：返回空行
3. **零宽 span**：直接保留，不占用宽度预算
4. **字符边界**：使用 `char_indices()` 确保 UTF-8 安全
5. **部分字符**：截断到字符边界，不截断多字节字符中间

### 6.3 测试覆盖

当前模块**无显式单元测试**，依赖使用方的集成测试验证。

**建议增加测试**：

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::style::Stylize;

    #[test]
    fn line_width_ascii() {
        let line = Line::from("hello");
        assert_eq!(line_width(&line), 5);
    }

    #[test]
    fn line_width_cjk() {
        let line = Line::from("你好");
        assert_eq!(line_width(&line), 4); // 每个 CJK 字符宽度为 2
    }

    #[test]
    fn truncate_preserve_style() {
        let line = Line::from(vec!["hello ".red(), "world".blue()]);
        let truncated = truncate_line_to_width(line, 8);
        assert_eq!(truncated.spans.len(), 2);
        assert_eq!(truncated.spans[0].style.fg, Some(Color::Red));
    }

    #[test]
    fn truncate_with_ellipsis() {
        let line = Line::from("hello world");
        let truncated = truncate_line_with_ellipsis_if_overflow(line, 8);
        assert!(truncated.spans.last().unwrap().content.contains('…'));
    }

    #[test]
    fn truncate_cjk_boundary() {
        let line = Line::from("你好世界");
        // 宽度为 8，截断到 3 应该只保留 "你"（宽度 2）
        let truncated = truncate_line_to_width(line, 3);
        assert_eq!(line_width(&truncated), 2);
    }
}
```

### 6.4 改进建议

1. **增加单元测试**：覆盖 ASCII、CJK、emoji、组合字符等场景
2. **性能优化**：对于纯 ASCII 文本使用快速路径
3. **单词边界截断**：增加在单词边界截断的选项（避免截断单词中间）
4. **尾部截断**：当前是头部保留、尾部截断，可增加头部截断选项
5. **多行截断**：扩展到多行文本的截断支持
6. **HTML 实体**：如需要，支持 `&hellip;` 等实体替代省略号

### 6.5 代码质量

- **简洁性**：100 行，职责单一
- **零 unsafe**：纯安全 Rust
- **无分配**（快速路径）：未溢出时直接返回原行
- **UTF-8 安全**：使用 `char_indices()` 和 `len_utf8()`

### 6.6 与相关模块的对比

| 模块 | 用途 | 区别 |
|------|------|------|
| `line_truncation.rs` | 硬截断到固定宽度 | 精确控制，可能截断单词 |
| `wrapping.rs` | 智能换行 | 保持单词完整，考虑 URL |
| `live_wrap.rs` | 实时增量换行 | 流式处理，支持动态宽度 |

这三个模块形成完整的文本布局工具链：
- **wrapping**：内容展示（聊天历史）
- **live_wrap**：实时流（打字机效果）
- **line_truncation**：固定宽度 UI（状态栏、按钮）
