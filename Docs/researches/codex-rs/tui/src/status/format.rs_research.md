# format.rs 研究文档

## 场景与职责

`format.rs` 是 Codex TUI 状态显示模块的格式化工具组件，提供字段格式化、标签去重、行宽计算和截断等通用功能。该模块负责状态卡片中标签-值对的视觉对齐和宽度管理，确保在不同终端宽度下都能正确显示。

## 功能点目的

### 核心功能

1. **字段格式化器 (`FieldFormatter`)**: 计算标签宽度并生成对齐的键值对显示
2. **标签去重 (`push_label`)**: 确保标签列表中无重复项
3. **行宽计算 (`line_display_width`)**: 计算 ratatui `Line` 的实际显示宽度
4. **行截断 (`truncate_line_to_width`)**: 将行截断到指定宽度，支持 Unicode

## 具体技术实现

### 1. FieldFormatter 结构体

```rust
#[derive(Debug, Clone)]
pub(crate) struct FieldFormatter {
    indent: &'static str,      // 缩进字符串（默认为 " "）
    label_width: usize,        // 最大标签宽度
    value_offset: usize,       // 值的起始偏移量
    value_indent: String,      // 续行缩进字符串
}
```

#### 构造器逻辑

```rust
pub(crate) fn from_labels<S>(labels: impl IntoIterator<Item = S>) -> Self
where
    S: AsRef<str>,
{
    // 计算所有标签中的最大宽度
    let label_width = labels
        .into_iter()
        .map(|label| UnicodeWidthStr::width(label.as_ref()))
        .max()
        .unwrap_or(0);
    
    let indent_width = UnicodeWidthStr::width(Self::INDENT);  // 1
    let value_offset = indent_width + label_width + 1 + 3;      // 缩进 + 标签 + ':' + 3空格填充

    Self {
        indent: Self::INDENT,
        label_width,
        value_offset,
        value_indent: " ".repeat(value_offset),
    }
}
```

**宽度计算公式**: `value_offset = 1 (indent) + label_width + 1 (colon) + 3 (padding)`

#### 方法实现

**生成完整行**
```rust
pub(crate) fn line(&self, label: &'static str, value_spans: Vec<Span<'static>>) -> Line<'static> {
    Line::from(self.full_spans(label, value_spans))
}
```

**生成续行（用于值换行时的缩进）**
```rust
pub(crate) fn continuation(&self, mut spans: Vec<Span<'static>>) -> Line<'static> {
    let mut all_spans = Vec::with_capacity(spans.len() + 1);
    all_spans.push(Span::from(self.value_indent.clone()).dim());
    all_spans.append(&mut spans);
    Line::from(all_spans)
}
```

**计算可用值宽度**
```rust
pub(crate) fn value_width(&self, available_inner_width: usize) -> usize {
    available_inner_width.saturating_sub(self.value_offset)
}
```

**生成标签 Span**
```rust
fn label_span(&self, label: &str) -> Span<'static> {
    let mut buf = String::with_capacity(self.value_offset);
    buf.push_str(self.indent);
    buf.push_str(label);
    buf.push_str(":");
    
    // 计算填充空格数，使所有标签右对齐
    let label_width = UnicodeWidthStr::width(label);
    let padding = 3 + self.label_width.saturating_sub(label_width);
    for _ in 0..padding {
        buf.push(' ');
    }
    
    Span::from(buf).dim()  // 使用暗淡样式
}
```

### 2. 标签去重函数

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

使用 `BTreeSet` 保证 O(log n) 的查找效率，同时保持标签的字典序（虽然这里主要用去重）。

### 3. 行宽计算

```rust
pub(crate) fn line_display_width(line: &Line<'static>) -> usize {
    line.iter()
        .map(|span| UnicodeWidthStr::width(span.content.as_ref()))
        .sum()
}
```

遍历行中的所有 span，累加每个 span 内容的显示宽度（正确处理 Unicode 字符）。

### 4. 行截断实现

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

        // 零宽度 span 直接保留
        if span_width == 0 {
            spans_out.push(Span::styled(text, style));
            continue;
        }

        // 已用完宽度则停止
        if used >= max_width {
            break;
        }

        // 完整 span 可容纳
        if used + span_width <= max_width {
            used += span_width;
            spans_out.push(Span::styled(text, style));
            continue;
        }

        // 需要截断 span 内的字符
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

**截断策略**:
1. 优先保留完整 span
2. 当 span 超出剩余宽度时，按字符逐个截断
3. 正确处理 Unicode 字符宽度（使用 `UnicodeWidthChar`）
4. 保留原始样式

## 关键代码路径与文件引用

### 上游调用方

| 模块 | 路径 | 用途 |
|------|------|------|
| `card.rs` | `./card.rs` | 使用 `FieldFormatter` 渲染状态卡片 |
| `rate_limits.rs` | `./rate_limits.rs` | 使用 `line_display_width` 计算行宽 |

### 使用示例（来自 card.rs）

```rust
// 创建格式化器
let formatter = FieldFormatter::from_labels(labels.iter().map(String::as_str));
let value_width = formatter.value_width(available_inner_width);

// 渲染行
lines.push(formatter.line("Model", model_spans));
lines.push(formatter.line("Directory", vec![Span::from(directory_value)]));

// 续行（当值需要换行时）
lines.push(formatter.continuation(vec![resets_span]));
```

## 依赖与外部交互

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `ratatui` | `Line`, `Span` 类型 |
| `unicode_width` | `UnicodeWidthStr`, `UnicodeWidthChar` 用于正确处理 Unicode 宽度 |
| `std::collections::BTreeSet` | 标签去重 |

### 关键 trait 使用

```rust
use ratatui::prelude::*;      // Line, Span
use ratatui::style::Stylize;  // .dim() 等方法
```

## 风险、边界与改进建议

### 边界情况

1. **max_width = 0**: `truncate_line_to_width` 返回空行
2. **空标签列表**: `from_labels` 返回 `label_width = 0`，但仍能正常工作
3. **零宽度字符**: 截断逻辑正确处理零宽度 Unicode 字符
4. **全角字符**: 使用 `unicode_width` crate 正确处理 CJK 字符宽度

### 潜在风险

1. **性能问题**: 
   - `from_labels` 遍历两次标签（一次计算宽度，一次使用）
   - `truncate_line_to_width` 逐个字符处理，对于长文本可能较慢
   - 每次渲染都重新创建 `FieldFormatter`

2. **内存分配**:
   - `value_indent` 字符串重复分配空格
   - `label_span` 每次调用都创建新字符串

3. **样式丢失风险**:
   - 截断时只保留样式，不处理其他 span 属性

### 改进建议

1. **性能优化**:
   ```rust
   // 使用 SmallVec 避免小容量 Vec 的堆分配
   use smallvec::SmallVec;
   
   // 预计算容量
   let mut buf = String::with_capacity(self.value_offset);
   ```

2. **缓存优化**:
   - 如果标签集合不变，可缓存 `FieldFormatter`
   - 考虑使用 `Arc<str>` 共享标签字符串

3. **功能扩展**:
   - 支持右对齐值
   - 支持多列布局
   - 添加截断指示器（如 "..."）

4. **代码简化**:
   - `push_label` 可使用 `Entry` API:
   ```rust
   if seen.insert(label.to_string()) {
       labels.push(label.to_string());
   }
   ```

### 代码度量

- 代码行数: 147 行
- 公共结构体: 1 个 (`FieldFormatter`)
- 公共函数: 4 个 (`push_label`, `line_display_width`, `truncate_line_to_width`, `FieldFormatter` 方法)
- 复杂度: 低-中等（主要是 `truncate_line_to_width` 的字符级处理）

### 测试建议

当前模块没有独立测试，依赖 `card.rs` 和 `tests.rs` 的集成测试。建议添加：

1. 单元测试 `FieldFormatter::from_labels` 的各种边界情况
2. `truncate_line_to_width` 的 Unicode 测试用例
3. 极端宽度（0、1、超大值）的测试
