# line_truncation.rs 深度研究文档

## 场景与职责

`line_truncation.rs` 提供 ratatui `Line` 类型的截断工具函数，用于处理 TUI 界面中文本行超出显示宽度的情况。主要应用于：

1. **UI 元素截断**：当文本内容超过可用显示空间时，智能截断并添加省略号
2. **列表项显示**：下拉菜单、选择列表等组件的文本截断
3. **状态栏/标题栏**：有限空间内的文本展示

该模块是文本渲染工具链的一部分，与 `wrapping.rs`（自动换行）形成互补：wrapping 用于多行文本的自动折行，而 truncation 用于单行文本的强制截断。

## 功能点目的

### 1. `line_width` - 计算行视觉宽度

```rust
pub(crate) fn line_width(line: &Line<'_>) -> usize
```

计算 ratatui `Line` 的视觉宽度（考虑 Unicode 宽字符），是截断决策的基础。

### 2. `truncate_line_to_width` - 精确截断到宽度

```rust
pub(crate) fn truncate_line_to_width(line: Line<'static>, max_width: usize) -> Line<'static>
```

核心截断函数，特点：
- 保留原始行的样式（`style`）和对齐方式（`alignment`）
- 在 span 边界处截断，不破坏样式应用范围
- 支持跨 span 的精确字符级截断（使用 `UnicodeWidthChar`）
- 处理零宽度 span 的特殊情况

### 3. `truncate_line_with_ellipsis_if_overflow` - 带省略号的智能截断

```rust
pub(crate) fn truncate_line_with_ellipsis_if_overflow(
    line: Line<'static>,
    max_width: usize,
) -> Line<'static>
```

高级封装函数，特点：
- 预扫描宽度，无溢出时直接返回原行（性能优化）
- 溢出时截断并追加省略号（`…`，U+2026）
- 省略号继承最后一个 span 的样式

## 具体技术实现

### 关键算法

#### 宽度计算

```rust
pub(crate) fn line_width(line: &Line<'_>) -> usize {
    line.iter()
        .map(|span| UnicodeWidthStr::width(span.content.as_ref()))
        .sum()
}
```

使用 `unicode_width` crate 的 `UnicodeWidthStr::width` 计算每个 span 的视觉宽度并求和。

#### 截断算法

```rust
pub(crate) fn truncate_line_to_width(line: Line<'static>, max_width: usize) -> Line<'static> {
    // 1. 解构 Line 获取所有权
    let Line { style, alignment, spans } = line;
    
    // 2. 逐 span 处理
    for span in spans {
        let span_width = UnicodeWidthStr::width(span.content.as_ref());
        
        // 情况 1：零宽度 span，保留
        if span_width == 0 {
            spans_out.push(span);
            continue;
        }
        
        // 情况 2：已用完宽度，停止
        if used >= max_width {
            break;
        }
        
        // 情况 3：完整 span 可放入
        if used + span_width <= max_width {
            used += span_width;
            spans_out.push(span);
            continue;
        }
        
        // 情况 4：需要在此 span 内截断
        // 逐字符计算宽度，找到截断点
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
    
    // 3. 重建 Line
    Line { style, alignment, spans: spans_out }
}
```

#### 带省略号的截断

```rust
pub(crate) fn truncate_line_with_ellipsis_if_overflow(...) -> Line<'static> {
    // 快速路径：无溢出直接返回
    if line_width(&line) <= max_width {
        return line;
    }
    
    // 为省略号预留 1 列空间
    let truncated = truncate_line_to_width(line, max_width.saturating_sub(1));
    
    // 追加省略号，继承最后一个 span 的样式
    let ellipsis_style = spans.last().map(|span| span.style).unwrap_or_default();
    spans.push(Span::styled("…", ellipsis_style));
    
    Line { style, alignment, spans }
}
```

### 数据结构

```rust
// ratatui Line 结构（简化）
struct Line<'a> {
    spans: Vec<Span<'a>>,
    style: Style,
    alignment: Option<Alignment>,
}

struct Span<'a> {
    content: Cow<'a, str>,
    style: Style,
}
```

## 关键代码路径与文件引用

### 调用方

| 文件 | 用途 |
|------|------|
| `src/selection_list.rs` | 选择列表项的文本截断 |
| `src/bottom_pane/mod.rs` | 底部面板的各种文本显示 |
| `src/status.rs` | 状态栏文本截断 |
| `src/chatwidget.rs` | 聊天组件的消息预览 |

### 依赖

| Crate/模块 | 用途 |
|------------|------|
| `ratatui::text::{Line, Span}` | 核心文本类型 |
| `unicode_width::{UnicodeWidthChar, UnicodeWidthStr}` | Unicode 宽度计算 |

## 依赖与外部交互

### 输入

- `Line<'static>`：拥有所有权的 ratatui 行类型
- `max_width: usize`：目标最大视觉宽度（列数）

### 输出

- `Line<'static>`：截断后的行，保持原始样式和对齐

### 边界处理

| 情况 | 处理 |
|------|------|
| `max_width == 0` | 返回空行 |
| 零宽度 span | 保留，不计入宽度 |
| 空输入行 | 返回空行 |
| 单字符超出宽度 | 截断为空（或仅省略号） |

## 风险、边界与改进建议

### 已知风险

1. **性能注释中的警告**：`truncate_line_with_ellipsis_if_overflow` 文档明确指出 "Performance should be reevaluated if using this method in loops/over larger content in the future"
   - 每次调用都遍历所有 span 计算宽度
   - 在大量文本或高频调用场景可能成为瓶颈

2. **省略号宽度假设**：假设省略号占用 1 列，对大多数终端成立，但某些特殊终端可能不同

3. **样式继承简化**：省略号仅继承最后一个 span 的样式，可能丢失复杂样式信息

### 边界情况

1. **多字节字符**：已正确处理，使用 `char_indices()` 和 `ch.len_utf8()`
2. **零宽度字符**：已处理，使用 `UnicodeWidthChar::width` 返回 0
3. **全角字符**：已处理，`unicode_width` 正确返回 2
4. **组合字符**：依赖 `unicode_width` 的实现

### 改进建议

1. **性能优化**：
   ```rust
   // 添加缓存机制，避免重复计算已知宽度
   pub(crate) struct CachedLineWidth {
       line_hash: u64,
       width: usize,
   }
   ```

2. **配置化省略号**：
   ```rust
   pub struct TruncationOptions {
       pub ellipsis: &'static str,
       pub ellipsis_width: usize,
   }
   ```

3. **更多截断策略**：
   - 头部截断（`...xyz`）用于文件路径
   - 中间截断（`ab...yz`）用于长标识符
   - 单词边界截断（不切断单词）

4. **测试增强**：
   - 添加性能基准测试
   - 测试极端 Unicode 场景（RTL 文本、表情符号序列）
   - 测试样式保留的完整性

### 相关代码对比

与 `wrapping.rs` 的区别：

| 特性 | `line_truncation.rs` | `wrapping.rs` |
|------|---------------------|---------------|
| 目的 | 单行截断 | 多行自动换行 |
| 输出 | 单行 | 多行 |
| 省略号 | 支持 | 不支持 |
| 性能关注点 | 单次截断 | 增量构建 |
| 使用场景 | UI 元素、列表 | 大段文本、代码块 |

两者可以组合使用：先 wrapping 分段，再对每段 truncation（虽然通常不需要）。
