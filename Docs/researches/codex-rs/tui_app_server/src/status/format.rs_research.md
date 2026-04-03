# format.rs 研究文档

## 场景与职责

`format.rs` 提供状态卡片中字段格式化的基础设施，负责标签对齐、行宽计算和文本截断。它是 `card.rs` 和 `rate_limits.rs` 的底层支持模块，确保状态输出的视觉一致性。

### 核心职责
1. **标签对齐**: 计算所有标签的最大宽度，实现右对齐冒号
2. **值缩进**: 为续行提供一致的缩进
3. **行宽管理**: 计算 Unicode 安全行宽，处理截断

## 功能点目的

### 1. FieldFormatter - 字段格式化器

```rust
#[derive(Debug, Clone)]
pub(crate) struct FieldFormatter {
    indent: &'static str,        // 基础缩进（默认 " "）
    label_width: usize,          // 最大标签宽度
    value_offset: usize,         // 值起始位置偏移
    value_indent: String,        // 续行缩进字符串
}
```

设计目标：将状态卡片中的所有字段（Model, Directory, Permissions 等）对齐到统一的视觉列。

### 2. 行宽工具函数

- `line_display_width()` - 计算行的 Unicode 显示宽度
- `truncate_line_to_width()` - 按显示宽度截断行
- `push_label()` - 去重添加标签到列表

## 具体技术实现

### FieldFormatter 构造

```rust
pub(crate) fn from_labels<S>(labels: impl IntoIterator<Item = S>) -> Self
where
    S: AsRef<str>,
{
    let label_width = labels
        .into_iter()
        .map(|label| UnicodeWidthStr::width(label.as_ref()))
        .max()
        .unwrap_or(0);
    let indent_width = UnicodeWidthStr::width(Self::INDENT);
    let value_offset = indent_width + label_width + 1 + 3; // 1 for ':', 3 for padding

    Self {
        indent: Self::INDENT,
        label_width,
        value_offset,
        value_indent: " ".repeat(value_offset),
    }
}
```

计算逻辑：
- `indent_width`: 基础缩进宽度（1 个空格）
- `label_width`: 最长标签的显示宽度
- `value_offset`: 值起始位置 = 缩进 + 标签 + 冒号 + 3 空格填充
- `value_indent`: 用于续行的空格字符串

### 格式化方法

#### line() - 创建格式化行
```rust
pub(crate) fn line(
    &self,
    label: &'static str,
    value_spans: Vec<Span<'static>>,
) -> Line<'static> {
    Line::from(self.full_spans(label, value_spans))
}
```

#### continuation() - 续行缩进
```rust
pub(crate) fn continuation(&self, mut spans: Vec<Span<'static>>) -> Line<'static> {
    let mut all_spans = Vec::with_capacity(spans.len() + 1);
    all_spans.push(Span::from(self.value_indent.clone()).dim());
    all_spans.append(&mut spans);
    Line::from(all_spans)
}
```

#### value_width() - 可用值宽度
```rust
pub(crate) fn value_width(&self, available_inner_width: usize) -> usize {
    available_inner_width.saturating_sub(self.value_offset)
}
```

#### label_span() - 标签样式
```rust
fn label_span(&self, label: &str) -> Span<'static> {
    let mut buf = String::with_capacity(self.value_offset);
    buf.push_str(self.indent);
    buf.push_str(label);
    buf.push_str(":");
    
    let label_width = UnicodeWidthStr::width(label);
    let padding = 3 + self.label_width.saturating_sub(label_width);
    for _ in 0..padding {
        buf.push(' ');
    }
    
    Span::from(buf).dim()
}
```

### 行宽计算与截断

#### line_display_width
```rust
pub(crate) fn line_display_width(line: &Line<'static>) -> usize {
    line.iter()
        .map(|span| UnicodeWidthStr::width(span.content.as_ref()))
        .sum()
}
```

#### truncate_line_to_width
```rust
pub(crate) fn truncate_line_to_width(line: Line<'static>, max_width: usize) -> Line<'static> {
    if max_width == 0 {
        return Line::from(Vec::<Span<'static>>::new());
    }

    let mut used = 0usize;
    let mut spans_out: Vec<Span<'static>> = Vec::new();

    for span in line.spans {
        let text = span.content.into_owned();
        let style = span.style;
        let span_width = UnicodeWidthStr::width(text.as_str());

        if span_width == 0 {
            spans_out.push(Span::styled(text, style));
            continue;
        }

        if used >= max_width {
            break;
        }

        if used + span_width <= max_width {
            used += span_width;
            spans_out.push(Span::styled(text, style));
            continue;
        }

        // 字符级截断
        let mut truncated = String::new();
        for ch in text.chars() {
            let ch_width = UnicodeWidthChar::width(ch).unwrap_or(0);
            if used + ch_width > max_width {
                break;
            }
            truncated.push(ch);
            used += ch_width;
        }

        if !truncated.is_empty() {
            spans_out.push(Span::styled(truncated, style));
        }
        break;
    }

    Line::from(spans_out)
}
```

### 标签去重

```rust
pub(crate) fn push_label(labels: &mut Vec<String>, seen: &mut BTreeSet<String>, label: &str) {
    if seen.contains(label) {
        return;
    }
    let owned = label.to_string();
    seen.insert(owned.clone());
    labels.push(owned);
}
```

使用 `BTreeSet` 保证 O(log n) 的去重检查，同时保持标签的插入顺序。

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/status/format.rs` - 147 行

### 调用方
| 文件 | 使用方式 |
|------|----------|
| `card.rs` | `FieldFormatter::from_labels()`, `line()`, `full_spans()`, `value_width()`, `continuation()`, `push_label()`, `line_display_width()`, `truncate_line_to_width()` |
| `rate_limits.rs` | `push_label()`（通过 `super::format::push_label`） |

### 外部依赖
| Crate | 用途 |
|-------|------|
| `ratatui` | `Line`, `Span`, `Stylize` - 终端 UI 基础类型 |
| `unicode_width` | `UnicodeWidthStr`, `UnicodeWidthChar` - Unicode 安全宽度计算 |

## 依赖与外部交互

### 与 card.rs 的协作

在 `card.rs` 中的典型使用模式：

```rust
// 1. 收集所有标签
let mut labels: Vec<String> = vec!["Model", "Directory", "Permissions", "Agents.md"]
    .into_iter()
    .map(str::to_string)
    .collect();

// 2. 条件添加可选标签
if self.model_provider.is_some() {
    push_label(&mut labels, &mut seen, "Model provider");
}

// 3. 创建格式化器
let formatter = FieldFormatter::from_labels(labels.iter().map(String::as_str));
let value_width = formatter.value_width(available_inner_width);

// 4. 格式化每一行
lines.push(formatter.line("Model", model_spans));
lines.push(formatter.line("Directory", vec![Span::from(directory_value)]));
```

### 与 rate_limits.rs 的协作

在 `rate_limits.rs` 中仅使用 `push_label()` 辅助函数来收集速率限制标签。

## 风险、边界与改进建议

### 当前限制

1. **硬编码缩进**: `INDENT` 固定为单个空格，无法动态调整
2. **固定填充**: 冒号后固定 3 空格填充，在极长标签下可能不够美观
3. **截断策略**: 简单截断，不支持省略号或智能截断

### 边界情况

1. **空标签列表**: `from_labels` 会创建 `label_width = 0` 的格式化器，仍可正常工作
2. **零宽度**: `truncate_line_to_width` 对 `max_width = 0` 返回空行
3. **全角字符**: 依赖 `unicode_width` 正确处理 CJK 等宽字符

### 潜在改进

1. **可配置缩进**: 允许调用方指定自定义缩进字符串
2. **智能截断**: 在截断点添加省略号（"..."）提示内容被截断
3. **右对齐数值**: 对于数字值，可考虑右对齐以方便比较
4. **颜色主题**: 当前标签使用 `.dim()`，可考虑支持主题配置

### 测试建议

当前模块无独立测试，依赖 `card.rs` 和 `rate_limits.rs` 的集成测试。建议添加：
- Unicode 宽度边界测试（CJK、emoji、组合字符）
- 截断行为测试
- 空输入处理测试

### 性能考虑

- `FieldFormatter::from_labels` 遍历所有标签一次，O(n) 复杂度
- `value_indent` 预计算为字符串，避免重复分配
- `truncate_line_to_width` 字符级遍历，对于极长行可能有性能影响，但 TUI 场景下通常可接受
