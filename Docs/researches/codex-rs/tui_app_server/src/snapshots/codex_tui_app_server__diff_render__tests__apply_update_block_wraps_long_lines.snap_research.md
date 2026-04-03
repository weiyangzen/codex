# Apply Update Block Wraps Long Lines - Technical Research Document

## Snapshot File
`codex_tui_app_server__diff_render__tests__apply_update_block_wraps_long_lines.snap`

## Snapshot Content
```
"• Edited long_example.txt (+1 -1)                                               "
"    1  line 1                                                                   "
"    2 -short                                                                    "
"    2 +short this_is_a_very_long_modified_line_that_should_wrap_across_m        "
"       ultiple_terminal_columns_and_continue_even_further_beyond_eighty_        "
"       columns_to_force_multiple_wraps                                          "
"    3  line 3                                                                   "
```

---

## 1. 场景与职责 (Scenario & Responsibilities)

### 1.1 功能场景
此快照测试验证 **更新操作中长行的自动换行渲染效果**。当文件变更包含超出终端宽度的长行时，系统需要正确换行并保持视觉对齐。

### 1.2 业务职责
- **长行换行**: 自动将超出宽度的行分割到多行
- **视觉对齐**: 换行后的内容保持与首行对齐
- **行号处理**: 只在首行显示行号，续行使用缩进
- **符号处理**: 只在首行显示 +/- 符号

### 1.3 使用场景
1. 用户修改包含长行的文件
2. 长行内容超出终端宽度
3. UI 自动换行显示，保持可读性
4. 用户可以完整看到变更内容

---

## 2. 功能点目的 (Feature Purpose)

### 2.1 核心功能
| 元素 | 内容 | 目的 |
|------|------|------|
| 行号 | `2` | 只在首行显示 |
| 符号 | `+` | 只在首行显示 |
| 首行内容 | `short this_is_a_very...` | 尽可能填充宽度 |
| 续行 | `ultiple_terminal...` | 缩进对齐，无行号/符号 |

### 2.2 换行对齐策略
```
    2 +short this_is_a_very_long_modified_line_that_should_wrap_across_m
       ultiple_terminal_columns_and_continue_even_further_beyond_eighty_
       columns_to_force_multiple_wraps
```

- 首行：行号 + 符号 + 内容
- 续行：空格缩进（与首行内容对齐）

### 2.3 与纯文本换行的区别
| 场景 | 处理方式 |
|------|---------|
| 纯文本 | 简单按字符截断 |
| 语法高亮 | 保持样式 span，在 span 边界换行 |
| 差异行 | 保持行号/符号列对齐 |

---

## 3. 具体技术实现 (Technical Implementation)

### 3.1 换行核心函数
```rust
// diff_render.rs:951-1020
fn wrap_styled_spans(
    spans: &[RtSpan<'static>],
    max_cols: usize,
) -> Vec<Vec<RtSpan<'static>>> {
    let mut lines: Vec<Vec<RtSpan>> = vec![vec![]];
    let mut current_width = 0;
    
    for span in spans {
        let span_width = span.content.width();
        
        // 如果当前 span 能放入当前行
        if current_width + span_width <= max_cols {
            lines.last_mut().unwrap().push(span.clone());
            current_width += span_width;
        } else {
            // 需要换行
            // 1. 尝试在 span 内分割
            // 2. 如果 span 太长，强制分割
            // ...
        }
    }
    
    lines
}
```

### 3.2 差异行换行渲染
```rust
// diff_render.rs:838-938
fn push_wrapped_diff_line_inner_with_theme_and_color_level(
    line_number: usize,
    kind: DiffLineType,
    content: &str,
    wrap_cols: usize,
    line_number_width: usize,
    syntax_spans: Option<&[RtSpan]>,
    style_context: DiffRenderStyleContext,
    diff_backgrounds: ResolvedDiffBackgrounds,
) -> Vec<Line> {
    // 构建 gutter（行号列）
    let gutter = format!("{:>width$} ", line_number, width = line_number_width);
    let prefix_cols = line_number_width + 1;  // 行号 + 空格
    
    // 构建符号列
    let sign = match kind {
        DiffLineType::Insert => "+",
        DiffLineType::Delete => "-",
        DiffLineType::Context => " ",
    };
    let prefix_cols = prefix_cols + 1;  // + 符号
    
    // 计算内容可用宽度
    let content_width = wrap_cols.saturating_sub(prefix_cols);
    
    // 获取内容 spans
    let content_spans = syntax_spans.map_or_else(
        || vec![Span::from(content).into()],
        |s| s.to_vec(),
    );
    
    // 换行处理
    let wrapped = wrap_styled_spans(&content_spans, content_width);
    
    // 构建输出行
    let mut lines = vec![];
    for (i, content_line) in wrapped.iter().enumerate() {
        let mut spans = vec![];
        
        if i == 0 {
            // 首行：行号 + 符号 + 内容
            spans.push(Span::styled(&gutter, gutter_style));
            spans.push(Span::styled(sign, sign_style));
        } else {
            // 续行：缩进对齐
            let indent = " ".repeat(prefix_cols);
            spans.push(Span::from(indent));
        }
        
        spans.extend(content_line.clone());
        lines.push(Line::from(spans));
    }
    
    lines
}
```

### 3.3 测试实现
```rust
// diff_render.rs:1547-1575
#[test]
fn ui_snapshot_apply_update_block_wraps_long_lines() {
    let original = "line 1\nshort\nline 3\n";
    let modified = "line 1\nshort this_is_a_very_long_modified_line_that_should_wrap_across_multiple_terminal_columns_and_continue_even_further_beyond_eighty_columns_to_force_multiple_wraps\nline 3\n";
    let patch = diffy::create_patch(original, modified).to_string();
    
    let mut changes: HashMap<PathBuf, FileChange> = HashMap::new();
    changes.insert(
        PathBuf::from("long_example.txt"),
        FileChange::Update {
            unified_diff: patch,
            move_path: None,
        },
    );
    
    let lines = create_diff_summary(&changes, &PathBuf::from("/"), 80);
    snapshot_lines("apply_update_block_wraps_long_lines", lines, 80, 10);
}
```

---

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 4.1 主要文件
| 文件路径 | 职责 |
|---------|------|
| `tui_app_server/src/diff_render.rs` | Diff 渲染和换行逻辑 |

### 4.2 关键函数
| 函数 | 位置 | 职责 |
|------|------|------|
| `wrap_styled_spans` | line 951-1020 | 样式化文本换行 |
| `push_wrapped_diff_line_inner_with_theme_and_color_level` | line 838-938 | 差异行渲染 |

---

## 5. 依赖与外部交互 (Dependencies & External Interactions)

### 5.1 外部依赖
| Crate | 用途 |
|-------|------|
| `unicode-width` | Unicode 字符宽度计算 |
| `ratatui` | TUI 渲染 |

---

## 6. 风险、边界与改进建议 (Risks, Edge Cases & Improvements)

### 6.1 已知风险
| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| 宽字符 | CJK、emoji 等宽字符可能导致错位 | 使用 unicode-width 计算 |
| 极长 token | 无空格的长字符串难以换行 | 强制字符截断 |

### 6.2 边界情况
1. **空内容**: 返回单行空 span
2. **单个字符超宽**: 强制单独成行
3. **Tab 字符**: 按 TAB_WIDTH (4) 计算宽度

### 6.3 改进建议
1. **智能换行点**: 在单词边界换行而非字符边界
2. **水平滚动**: 提供水平滚动替代换行
3. **折叠显示**: 超长行默认折叠，点击展开

### 6.4 相关测试
- `apply_update_block_wraps_long_lines_text`: 纯文本版本
- `syntax_highlighted_insert_wraps`: 语法高亮版本

---

## 7. 相关文档链接

- [Apply Update Block](../codex_tui_app_server__diff_render__tests__apply_update_block.snap_research.md)
