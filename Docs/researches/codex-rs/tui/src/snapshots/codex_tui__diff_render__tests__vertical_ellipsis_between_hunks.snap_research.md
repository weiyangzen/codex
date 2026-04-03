# Vertical Ellipsis Between Hunks Snapshot 研究文档

## 场景与职责

此快照测试验证了**多 hunk diff 的分隔显示**。当文件的变更是非连续的（即中间有未变更的上下文），diff 会包含多个 hunks，需要在 hunks 之间显示视觉分隔符（`⋮` 垂直省略号）。

测试场景：
- 文件 `example.txt` 有两处独立的变更
- 第一处：第 2 行被修改
- 第二处：第 9 行被修改
- 中间第 3-8 行是未变更的上下文，被省略显示

## 功能点目的

### 多 Hunk 展示

```
• Proposed Change example.txt (+2 -2)
    1      line 1
    2     -line 2
    2     +line two changed
    3      line 3
    4      line 4
    5      line 5
    ⋮               ← 垂直省略号，表示有省略的行
    6      line 6
    7      line 7
    8      line 8
    9     -line 9
    9     +line nine changed
    10     line 10
```

### 视觉设计意图

1. **节省空间**：省略中间未变更的行，避免冗长输出
2. **保持上下文**：显示省略前后的行号，帮助定位
3. **视觉分隔**：使用 `⋮`（U+22EE，垂直省略号）作为清晰的视觉标记

## 具体技术实现

### Hunk 分隔逻辑

```rust
let mut is_first_hunk = true;
for h in patch.hunks() {
    if !is_first_hunk {
        // 非第一个 hunk，添加分隔符
        let spacer = format!("{:width$} ", "", width = line_number_width.max(1));
        let spacer_span = RtSpan::styled(
            spacer,
            style_gutter_for(
                DiffLineType::Context,
                style_context.theme,
                style_context.color_level,
            ),
        );
        out.push(RtLine::from(vec![spacer_span, "⋮".dim()]));
    }
    is_first_hunk = false;
    
    // 渲染 hunk 内容...
}
```

### 行号 gutter 样式

分隔符使用 `Context` 类型的 gutter 样式：
- 暗色主题：简单 `DIM` 修饰符
- 亮色主题：带背景色的 gutter

```rust
fn style_gutter_for(kind: DiffLineType, theme: DiffTheme, color_level: DiffColorLevel) -> Style {
    match (theme, kind, RichDiffColorLevel::from_diff_color_level(color_level)) {
        // ...
        _ => style_gutter_dim(),  // Context 类型使用 dim 样式
    }
}
```

### Hunk 语法高亮

每个 hunk 独立进行语法高亮，保持解析器状态：

```rust
// 将每个 hunk 作为整体高亮，保持解析器状态
let hunk_syntax_lines = diff_lang.and_then(|language| {
    let hunk_text: String = h
        .lines()
        .iter()
        .map(|line| match line {
            diffy::Line::Insert(text)
            | diffy::Line::Delete(text)
            | diffy::Line::Context(text) => *text,
        })
        .collect();
    let syntax_lines = highlight_code_to_styled_spans(&hunk_text, language)?;
    (syntax_lines.len() == h.lines().len()).then_some(syntax_lines)
});
```

**注意**：跨 hunk 的解析器状态不保持，因为 hunks 之间有省略行，语法状态会在上下文边界重新同步。

## 关键代码路径与文件引用

### 核心代码

| 代码 | 文件 | 行号 | 说明 |
|------|------|------|------|
| Hunk 分隔逻辑 | `diff_render.rs` | 592-604 | 非第一个 hunk 前添加 `⋮` |
| Hunk 高亮 | `diff_render.rs` | 609-621 | 每个 hunk 独立语法高亮 |
| 行渲染 | `diff_render.rs` | 623-731 | 遍历 hunk 行并渲染 |

### 测试构造

```rust
// 构造测试数据：两处独立的变更
let original = "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\n";
let modified = "line 1\nline two changed\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline nine changed\nline 10\n";
let patch = diffy::create_patch(original, modified).to_string();

changes.insert(
    PathBuf::from("example.txt"),
    FileChange::Update {
        unified_diff: patch,
        move_path: None,
    },
);
```

生成的 diff 包含两个 hunks：
- Hunk 1：覆盖第 1-5 行（变更在第 2 行）
- Hunk 2：覆盖第 6-10 行（变更在第 9 行）

## 依赖与外部交互

### Diff 解析

- `diffy::Patch::hunks()`：返回 diff 中的所有 hunks
- `diffy::Hunk::old_range()` / `new_range()`：获取 hunk 的行范围
- `diffy::Hunk::lines()`：获取 hunk 中的行列表

### 样式系统

- `style_gutter_for(DiffLineType::Context, ...)`：省略号使用上下文样式
- `"⋮".dim()`：省略号使用 dim（暗淡）样式

## 风险、边界与改进建议

### 边界情况

1. **相邻 Hunks**：
   - 如果两个 hunks 之间只有很少的上下文行
   - 可能不需要显示省略号
   - 当前实现始终显示省略号

2. **文件开头/结尾的 Hunks**：
   - 第一个 hunk 前不显示省略号
   - 最后一个 hunk 后不显示省略号
   - 这是正确行为

3. **单行 Hunks**：
   - 如果 hunk 只有一行变更
   - 省略号仍然显示，可能显得冗余

4. **大量 Hunks**：
   - 文件有数十个 hunks 时
   - 大量省略号可能影响可读性

### 潜在问题

1. **行号连续性**：
   ```
   5      line 5
   ⋮
   6      line 6
   ```
   行号 5 和 6 是连续的，但中间有省略
   用户可能误解为有行被删除

2. **语法高亮状态重置**：
   - 每个 hunk 独立高亮
   - 跨 hunk 的多行字符串可能高亮不正确
   - 示例：
     ```rust
     let s = "start  // hunk 1
     ...省略的行...
     end";     // hunk 2，可能无法正确识别为字符串结束
     ```

3. **省略号位置**：
   - 当前在行号 gutter 后显示
   - 可能与某些字体的行号对齐不一致

### 改进建议

1. **智能省略**：
   - 如果 hunks 间距小于阈值（如 3 行），不显示省略号
   - 显示完整的上下文行

2. **省略信息增强**：
   ```
   5      line 5
   ⋮  (3 lines omitted)
   9      line 9
   ```
   显示省略的行数，帮助用户理解

3. **可折叠 Hunks**：
   - 允许用户折叠/展开单个 hunk
   - 使用 `▶` / `▼` 指示可折叠状态

4. **语法高亮优化**：
   - 尝试保持跨 hunk 的解析器状态
   - 或使用更智能的启发式方法

5. **配置选项**：
   - 允许用户配置上下文行数
   - 允许禁用省略号（显示完整文件）

6. **视觉改进**：
   - 使用虚线或点线连接省略号
   - 添加悬停提示显示省略的内容概览
