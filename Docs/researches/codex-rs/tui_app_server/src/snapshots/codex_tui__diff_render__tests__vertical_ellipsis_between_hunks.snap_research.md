# 研究文档: vertical_ellipsis_between_hunks

## 场景与职责

该测试验证 **TUI 差异渲染器在处理多个 diff hunk 时的垂直省略号显示**。当文件变更大且分散时，统一差异格式（unified diff）会将变更分组为多个 "hunk"（块），每个 hunk 包含变更行及其周围的上下文行。

为了在终端有限的空间内清晰地展示这些分离的变更块，渲染器在两个 hunk 之间插入一个垂直省略号行（`⋮`），表示中间有未显示的代码行被跳过。

这是代码审查 UI 中的重要视觉提示，帮助用户理解代码的结构和变更的分布。

## 功能点目的

1. **多 hunk 分隔**: 当 diff 包含多个分离的变更块时，清晰分隔它们
2. **视觉提示**: 使用 `⋮`（U+22EE，垂直省略号）字符提示用户有代码被省略
3. **行号对齐**: 省略号行与差异内容的行号 gutter 对齐
4. **保持上下文**: 每个 hunk 保留足够的上下文行（默认 3 行）以便理解变更

测试场景：
- 文件 `example.txt` 有 10 行
- 第 2 行被修改（`line 2` → `line two changed`）
- 第 9 行被修改（`line 9` → `line nine changed`）
- 两个变更相距较远，形成两个独立的 hunk
- 中间的第 3-8 行作为上下文，但在 hunk 之间被省略

## 具体技术实现

### 测试数据准备

```rust
let mut changes: HashMap<PathBuf, FileChange> = HashMap::new();
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

### 渲染流程

1. **解析 Patch** (行 548):
   ```rust
   if let Ok(patch) = diffy::Patch::from_str(unified_diff) {
   ```

2. **遍历 Hunks** (行 592-732):
   ```rust
   let mut is_first_hunk = true;
   for h in patch.hunks() {
       if !is_first_hunk {
           // 在非第一个 hunk 前插入省略号
           let spacer = format!("{:width$} ", "", width = line_number_width.max(1));
           let spacer_span = RtSpan::styled(
               spacer,
               style_gutter_for(DiffLineType::Context, style_context.theme, style_context.color_level),
           );
           out.push(RtLine::from(vec![spacer_span, "⋮".dim()]));
       }
       is_first_hunk = false;
       // ... 渲染 hunk 内容
   }
   ```

### 输出格式解析

```
"• Proposed Change example.txt (+2 -2)                                           "  <- 标题
"    1      line 1                                                               "  <- Hunk 1 上下文
"    2     -line 2                                                               "  <- Hunk 1 删除
"    2     +line two changed                                                     "  <- Hunk 1 插入
"    3      line 3                                                               "  <- Hunk 1 上下文
"    4      line 4                                                               "  <- Hunk 1 上下文
"    5      line 5                                                               "  <- Hunk 1 上下文
"    ⋮                                                                           "  <- 垂直省略号（分隔）
"    6      line 6                                                               "  <- Hunk 2 上下文
"    7      line 7                                                               "  <- Hunk 2 上下文
"    8      line 8                                                               "  <- Hunk 2 上下文
"    9     -line 9                                                               "  <- Hunk 2 删除
"    9     +line nine changed                                                    "  <- Hunk 2 插入
"    10     line 10                                                              "  <- Hunk 2 上下文
```

格式说明：
- `⋮`: 垂直省略号（dim 样式，表示被省略的代码）
- 省略号行使用与上下文行相同的 gutter 样式
- 省略号位于行号 gutter 之后，与差异内容左对齐

### Hunk 结构

由 `diffy` crate 生成的 patch 包含：
```
@@ -1,5 +1,5 @@          <- Hunk 1 header
 line 1
-line 2
+line two changed
 line 3
 line 4
 line 5
@@ -6,5 +6,5 @@          <- Hunk 2 header
 line 6
 line 7
 line 8
-line 9
+line nine changed
 line 10
```

## 关键代码路径与文件引用

### 主要文件

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/diff_render.rs` | 差异渲染核心实现 |

### 关键代码位置

| 元素 | 行号 | 说明 |
|------|------|------|
| Hunk 分隔逻辑 | 592-604 | 在非第一个 hunk 前插入省略号 |
| 省略号行构建 | 594-603 | 创建 spacer + ⋮ 的行 |
| Hunk 内容渲染 | 606-731 | 遍历 hunk 行并渲染 |
| 语法高亮处理 | 609-621 | 对整个 hunk 进行语法高亮 |

### 相关代码片段

```rust
// 行 592-604: Hunk 分隔逻辑
let mut is_first_hunk = true;
for h in patch.hunks() {
    if !is_first_hunk {
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
    // ...
}
```

### 样式应用

- **Spacer**: 使用 `style_gutter_for(DiffLineType::Context, ...)`，与上下文行 gutter 样式一致
- **省略号**: 使用 `.dim()` 修饰符，使其视觉上不突兀

## 依赖与外部交互

### 外部 crate

| Crate | 用途 |
|-------|------|
| `diffy` | 统一差异格式解析，提供 `Patch`, `Hunk`, `Line` 类型 |
| `ratatui` | TUI 渲染框架 |

### diffy 类型

```rust
// Patch: 包含多个 Hunk
pub struct Patch<'a> { ... }

// Hunk: 一个变更块
pub struct Hunk<'a, T: ?Sized> {
    old_range: Range,
    new_range: Range,
    lines: Vec<Line<'a, T>>,
}

// Line: 单行差异
pub enum Line<'a, T: ?Sized> {
    Insert(&'a T),
    Delete(&'a T),
    Context(&'a T),
}
```

### 内部依赖

```rust
use diffy::Hunk;
```

## 风险、边界与改进建议

### 潜在风险

1. **省略号数量**: 如果文件有大量分散的变更，可能出现多个省略号行
   - 当前无最大数量限制
   - 极端情况下可能影响可读性

2. **上下文行数**: 默认上下文行数为 3，可能不足以理解某些变更
   - 当前为硬编码，用户无法调整

3. **Unicode 支持**: `⋮` 字符在某些终端或字体中可能显示不正确
   - 需要确保终端支持 Unicode
   - 考虑提供 ASCII 回退选项（如 `...`）

### 边界情况

| 场景 | 当前处理 |
|------|----------|
| 单个 hunk | 不显示省略号（`is_first_hunk` 保护）|
| 相邻 hunk（上下文重叠）| diffy 会合并为一个 hunk，不会出现省略号 |
| 行号宽度变化 | spacer 宽度基于 `line_number_width.max(1)` |
| ANSI-16 终端 | 省略号使用 dim 样式，无背景色 |

### 改进建议

1. **可配置上下文行数**:
   ```rust
   // 在配置中添加选项
   pub struct DiffConfig {
       pub context_lines: usize,  // 默认 3
   }
   ```

2. **ASCII 回退模式**:
   ```rust
   fn ellipsis_char(supports_unicode: bool) -> &'static str {
       if supports_unicode { "⋮" } else { "..." }
   }
   ```

3. **折叠/展开交互**:
   - 允许用户点击省略号展开被隐藏的代码
   - 或使用快捷键展开所有省略区域

4. **显示省略行数**:
   ```rust
   // 当前: "    ⋮"
   // 改进: "    ⋮ (3 lines skipped)"
   ```

5. **添加更多测试场景**:
   ```rust
   // 三个或更多 hunk
   #[test]
   fn ui_snapshot_three_hunks_with_ellipses() { ... }
   
   // 相邻 hunk（应合并）
   #[test]
   fn ui_snapshot_adjacent_hunks_no_ellipsis() { ... }
   
   // 文件开头/结尾的变更
   #[test]
   fn ui_snapshot_hunk_at_file_boundaries() { ... }
   ```

6. **性能优化**: 对于超大文件（如 10K+ 行），考虑：
   - 虚拟滚动（只渲染可见 hunk）
   - 延迟加载省略区域的语法高亮

### 相关测试

| 测试 | 描述 |
|------|------|
| `apply_update_block` | 单 hunk 更新（无省略号）|
| `vertical_ellipsis_between_hunks` | 多 hunk 分隔（本测试）|
| `apply_update_block_wraps_long_lines` | 长行换行 |
| `large_update_diff_skips_highlighting` | 大 diff 性能优化 |

### 视觉设计参考

其他工具的类似设计：
- **GitHub**: 使用灰色背景的分隔线
- **GitLab**: 使用 `...` 和展开按钮
- **VS Code**: 使用折叠指示器
- **delta**: 使用自定义分隔样式

Codex 的 `⋮` 设计简洁且符合 Unicode 标准，但可考虑添加交互功能以提升用户体验。
