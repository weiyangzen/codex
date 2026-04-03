# 快照研究文档: list_selection_footer_note_wraps

## 场景与职责

此快照测试验证 `ListSelectionView` 的 **footer_note（页脚注释）自动换行功能**。该功能的核心职责是：**当页脚注释内容超出可用宽度时，自动换行显示，确保重要提示信息在各种终端宽度下都能完整呈现**。

测试场景：
- 创建一个带有页脚注释的选择视图
- 使用 40 列的窄终端宽度渲染
- 验证注释内容正确换行，且样式（颜色、高亮）得以保留

## 功能点目的

**Footer Note 换行** 功能的设计目的：

1. **信息完整性**: 确保重要提示、说明或警告信息不会被截断
2. **响应式布局**: 适应不同终端宽度，从窄终端（40 列）到宽终端都能良好显示
3. **样式保留**: 换行过程中保留原始文本的样式（颜色、粗细、斜体等）
4. **视觉层次**: 通过 `footer_note` 和 `footer_hint` 的区分，提供清晰的信息层级

## 具体技术实现

### 换行函数

```rust
// selection_popup_common.rs:94-107
pub(crate) fn wrap_styled_line<'a>(line: &'a Line<'a>, width: u16) -> Vec<Line<'a>> {
    use crate::wrapping::RtOptions;
    use crate::wrapping::word_wrap_line;

    let width = width.max(1) as usize;
    let opts = RtOptions::new(width)
        .initial_indent(Line::from(""))
        .subsequent_indent(Line::from(""));
    word_wrap_line(line, opts)
}
```

### 高度计算

```rust
// list_selection_view.rs:748-752
if let Some(note) = &self.footer_note {
    let note_width = width.saturating_sub(2);  // 减去两侧边距
    let note_lines = wrap_styled_line(note, note_width);
    height = height.saturating_add(note_lines.len() as u16);
}
```

### 渲染实现

```rust
// list_selection_view.rs:944-970
if let Some(lines) = note_lines {
    let note_area = Rect {
        x: note_area.x + 2,  // 左侧缩进 2 列
        y: note_area.y,
        width: note_area.width.saturating_sub(2),
        height: note_area.height,
    };
    for (idx, line) in lines.iter().enumerate() {
        if idx as u16 >= note_area.height {
            break;
        }
        let line_area = Rect {
            x: note_area.x,
            y: note_area.y + idx as u16,
            width: note_area.width,
            height: 1,
        };
        line.clone().render(line_area, buf);
    }
}
```

### 测试用例构造

```rust
// list_selection_view.rs:1234-1263
#[test]
fn snapshot_footer_note_wraps() {
    let footer_note = Line::from(vec![
        "Note: ".dim(),                                    // 灰色前缀
        "Use /setup-default-sandbox".cyan(),              // 青色高亮命令
        " to allow network access.".dim(),                // 灰色后缀
    ]);
    let view = ListSelectionView::new(
        SelectionViewParams {
            title: Some("Select Approval Mode".to_string()),
            footer_note: Some(footer_note),
            footer_hint: Some(standard_popup_hint_line()),
            // ...
        },
        tx,
    );
    assert_snapshot!(
        "list_selection_footer_note_wraps",
        render_lines_with_width(&view, 40)  // 窄宽度触发换行
    );
}
```

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/bottom_pane/list_selection_view.rs` | 页脚注释高度计算和渲染（第 748-752, 944-970 行） |
| `codex-rs/tui/src/bottom_pane/selection_popup_common.rs` | 样式化文本换行函数（第 94-107 行） |
| `codex-rs/tui/src/wrapping.rs` | 底层文本换行实现 |

### 关键函数路径

1. **测试入口**: `list_selection_view.rs:1234`
   ```rust
   #[test]
   fn snapshot_footer_note_wraps()
   ```

2. **换行函数**: `selection_popup_common.rs:98`
   ```rust
   pub(crate) fn wrap_styled_line<'a>(line: &'a Line<'a>, width: u16) -> Vec<Line<'a>>
   ```

3. **高度计算**: `list_selection_view.rs:694-756`
   ```rust
   fn desired_height(&self, width: u16) -> u16
   ```

4. **渲染实现**: `list_selection_view.rs:759-982`
   ```rust
   fn render(&self, area: Rect, buf: &mut Buffer)
   ```

### 数据结构

```rust
// list_selection_view.rs:208-235
pub(crate) struct ListSelectionView {
    footer_note: Option<Line<'static>>,   // 页脚注释（可换行）
    footer_hint: Option<Line<'static>>,   // 页脚提示（单行）
    // ...
}

// selection_popup_common.rs:94-107
pub(crate) fn wrap_styled_line<'a>(line: &'a Line<'a>, width: u16) -> Vec<Line<'a>>
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `wrapping` | 底层文本换行实现，支持样式保留 |
| `selection_popup_common` | 共享的换行函数 |
| `line_truncation` | 文本截断（当高度不足时） |

### 外部 Crate

| Crate | 用途 |
|-------|------|
| `ratatui::text::Line` | 样式化文本行表示 |
| `ratatui::style::Stylize` | 样式辅助方法（`.dim()`, `.cyan()` 等） |
| `textwrap` | 底层文本换行算法 |

### 样式系统

```rust
// 测试中的样式使用
"Note: ".dim()                           // 暗淡灰色
"Use /setup-default-sandbox".cyan()      // 青色高亮
" to allow network access.".dim()        // 暗淡灰色
```

## 风险边界与改进建议

### 当前风险边界

1. **高度溢出**: 如果注释内容过长且终端高度有限，可能被截断
   - 当前实现有 `idx as u16 >= note_area.height` 检查，但无优雅降级

2. **缩进丢失**: 换行后的行没有额外的缩进，可能与主内容对齐不佳

3. **宽度计算**: `width.saturating_sub(2)` 是硬编码的边距，可能与实际布局不一致

4. **样式复杂度**: 如果 `Line` 包含复杂样式（多 `Span` 跨单词边界），换行可能在样式边界处产生意外结果

### 快照观察

```
  Select Approval Mode

› 1. Read Only (current)  Codex can     # 选项行也可能换行
                          read files    # 描述换行缩进

  Note: Use /setup-default-sandbox to   # 注释第一行
  allow network access.                 # 注释第二行（换行）
  Press enter to confirm or esc to go ba # 提示行（被截断）
```

**关键观察**:
- 注释在 40 列宽度下正确换行为两行
- 样式得以保留（`Note:` 暗淡，`/setup-default-sandbox` 青色）
- 选项描述也独立换行（`Codex can read files`）
- 提示行因宽度不足被截断

### 改进建议

1. **首行缩进**: 为换行后的行添加视觉缩进，提高可读性
   ```rust
   let opts = RtOptions::new(width)
       .initial_indent(Line::from(""))
       .subsequent_indent(Line::from("  "));  // 添加缩进
   ```

2. **最大行数限制**: 添加配置限制注释最大行数，防止占用过多空间
   ```rust
   pub footer_note_max_lines: Option<u16>,
   ```

3. **截断指示**: 当内容被截断时显示省略号或"查看更多"提示

4. **动态边距**: 将边距计算与 `render_menu_surface` 的 inset 逻辑统一
   ```rust
   const MENU_SURFACE_HORIZONTAL_INSET: u16 = 4;
   ```

5. **链接检测**: 自动检测并高亮注释中的 URL、命令路径等

6. **测试增强**:
   - 测试多语言/Unicode 文本的换行
   - 测试极端宽度（10 列、200 列）
   - 测试复杂样式（多颜色、粗体混合）的保留

### 相关组件对比

| 组件 | 换行支持 | 样式保留 | 用途 |
|------|----------|----------|------|
| `footer_note` | ✅ | ✅ | 重要提示、说明 |
| `footer_hint` | ❌（单行） | ✅ | 操作提示 |
| `description` | ✅ | ✅ | 选项描述 |
| `title` | ❌ | ✅ | 标题 |

### 使用建议

1. **footer_note**: 用于需要用户注意的重要信息，如配置建议、警告等
2. **footer_hint**: 用于操作指导，保持简洁单行
3. **避免冗余**: 如果选项描述已充分说明，避免在 footer_note 中重复
