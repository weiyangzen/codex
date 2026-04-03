# Diff Gallery 94x35 快照研究文档

## 场景与职责

此快照测试展示了 `diff_render` 模块在 94x35 终端尺寸下的综合渲染能力。它是一个**综合性画廊测试**，同时展示多种文件变更类型的渲染效果，包括：

1. **文件添加** (`FileChange::Add`)：`assets/banner.txt` 和 `examples/new_sample.rs`
2. **文件删除** (`FileChange::Delete`)：`legacy/old_script.py` 和 `tmp/obsolete.log`
3. **文件更新** (`FileChange::Update`)：`src/lib.rs` 和 `scripts/calc.txt → scripts/calc.py`

该测试模拟了 Codex CLI 在实际使用中展示代码变更的完整场景，是 diff 渲染系统的端到端集成测试。

## 功能点目的

### 1. 多文件变更汇总展示
- **总览头部**：`"• Edited 6 files (+9 -9)"` 显示变更文件总数和统计信息
- **文件树形结构**：使用 `└` 字符展示层级关系，每个文件独立成块
- **行号统计**：每个文件显示 `(+n -m)` 格式的增删行数

### 2. 文件重命名检测
- 快照中 `scripts/calc.txt → scripts/calc.py` 展示了文件重命名/移动的渲染
- 使用 `→` 箭头符号连接源路径和目标路径
- 语法高亮基于目标文件扩展名（`.py`）

### 3. Unicode 和宽字符支持
- 快照中的注释 `Hidden by multi-width symbols` 表明系统正确处理了：
  - Emoji 字符（🚀）占用 2 个显示列
  - CJK 字符（東京、你好世界）占用 2 个显示列
  - 制表符 (`\t`) 的展开（显示为 4 个空格）

### 4. 语法高亮集成
- Rust 代码 (`src/lib.rs`, `examples/new_sample.rs`) 应用了语法高亮
- Python 代码 (`legacy/old_script.py`, `scripts/calc.py`) 有相应的高亮处理
- 纯文本文件 (`assets/banner.txt`, `tmp/obsolete.log`) 无语法高亮

## 具体技术实现

### 核心数据结构

```rust
// 文件变更枚举（来自 codex_protocol::protocol::FileChange）
pub enum FileChange {
    Add { content: String },
    Delete { content: String },
    Update { unified_diff: String, move_path: Option<PathBuf> },
}

// 内部行类型分类
pub(crate) enum DiffLineType {
    Insert,   // + 添加行
    Delete,   // - 删除行
    Context,  //   上下文行
}

// 渲染样式上下文
pub(crate) struct DiffRenderStyleContext {
    theme: DiffTheme,                    // Dark / Light
    color_level: DiffColorLevel,         // TrueColor / Ansi256 / Ansi16
    diff_backgrounds: ResolvedDiffBackgrounds,  // 解析后的背景色
}
```

### 关键渲染流程

1. **变更收集与排序** (`collect_rows`)
   ```rust
   fn collect_rows(changes: &HashMap<PathBuf, FileChange>) -> Vec<Row>
   ```
   - 遍历所有变更，计算每文件的增删行数
   - 按路径字母顺序排序，确保输出稳定

2. **分块渲染** (`render_changes_block`)
   - 生成总览头部（单文件或多文件模式）
   - 为每个文件生成独立块，包含文件头和差异内容
   - 使用 `prefix_lines` 添加 4 空格缩进

3. **统一差异解析** (`render_change` 中的 Update 处理)
   ```rust
   if let Ok(patch) = diffy::Patch::from_str(unified_diff) {
       // 解析 hunk，计算最大行号宽度
       // 按 hunk 分组进行语法高亮
       // 逐行渲染 Insert/Delete/Context
   }
   ```

4. **行包装处理** (`push_wrapped_diff_line_inner_with_theme_and_color_level`)
   - 计算 gutter 宽度（行号 + 1 空格）
   - 根据 DiffLineType 应用不同样式
   - 调用 `wrap_styled_spans` 处理长行换行

### 样式系统

```rust
// 深色主题背景色
const DARK_TC_ADD_LINE_BG_RGB: (u8, u8, u8) = (33, 58, 43);   // #213A2B
const DARK_TC_DEL_LINE_BG_RGB: (u8, u8, u8) = (74, 34, 29);   // #4A221D

// 浅色主题背景色（GitHub 风格）
const LIGHT_TC_ADD_LINE_BG_RGB: (u8, u8, u8) = (218, 251, 225); // #dafbe1
const LIGHT_TC_DEL_LINE_BG_RGB: (u8, u8, u8) = (255, 235, 233); // #ffebe9
```

## 关键代码路径与文件引用

### 主要文件
- `/codex-rs/tui_app_server/src/diff_render.rs` - 核心 diff 渲染实现
- `/codex-rs/tui_app_server/src/render/highlight.rs` - 语法高亮集成
- `/codex-rs/tui_app_server/src/terminal_palette.rs` - 终端颜色检测

### 关键函数

| 函数名 | 行号 | 职责 |
|--------|------|------|
| `create_diff_summary` | ~345 | 入口函数，生成 diff 摘要 |
| `render_changes_block` | ~402 | 渲染变更块，处理多文件布局 |
| `render_change` | ~474 | 根据 FileChange 类型渲染差异 |
| `push_wrapped_diff_line_inner_with_theme_and_color_level` | ~838 | 核心行渲染，处理样式和换行 |
| `wrap_styled_spans` | ~951 | 样式跨度的智能换行 |
| `diff_gallery_changes` | ~1404 (test) | 测试数据生成 |
| `snapshot_diff_gallery` | ~1460 (test) | 画廊测试执行 |

### 测试相关
- 测试函数：`ui_snapshot_diff_gallery_94x35` (tui/src/diff_render.rs:1755)
- 快照文件：`codex_tui__diff_render__tests__diff_gallery_94x35.snap`
- 终端尺寸：94 列 x 35 行

## 依赖与外部交互

### 外部 crate
- `diffy` - 统一差异格式解析（Patch/Hunk/Line）
- `ratatui` - 终端 UI 渲染框架
- `unicode-width` - Unicode 字符显示宽度计算
- `syntect`（通过 highlight.rs）- 语法高亮

### 协议依赖
- `codex_protocol::protocol::FileChange` - 文件变更数据结构
- `codex_core::terminal::*` - 终端信息检测

### 环境交互
- 检测终端背景色（`default_bg()`）决定使用 Dark/Light 主题
- 检测颜色支持级别（`stdout_color_level()`）决定调色板
- Windows Terminal 特殊处理（`WT_SESSION` 环境变量）

## 风险、边界与改进建议

### 已知风险

1. **宽字符截断风险**
   - 快照中 `Hidden by multi-width symbols` 注释表明某些字符可能显示异常
   - CJK 字符和 Emoji 在特定终端可能导致布局错乱

2. **语法高亮性能**
   - 大文件 diff 可能触发 `exceeds_highlight_limits` 跳过高亮
   - 当前阈值：总字节数或总行数超过限制时禁用逐行高亮

3. **主题一致性**
   - 依赖终端报告的 background color，某些终端可能报告不准确
   - ANSI-16 模式下背景色被禁用，仅使用前景色

### 边界情况

1. **空文件处理**
   - Add/Delete 空文件时行号宽度计算（`line_number_width(0)` 返回 1）

2. **极长行处理**
   - `wrap_styled_spans` 处理超过可用宽度的行
   - 续行使用双空格缩进对齐（`"{:gutter_width$}  "`）

3. **多 hunk 分隔**
   - 当 diff 包含多个 hunk 时，使用 `⋮` 符号分隔（见 vertical_ellipsis 快照）

### 改进建议

1. **性能优化**
   - 考虑对超大 diff 使用虚拟滚动，避免一次性渲染所有行
   - 缓存语法高亮结果，避免重复解析

2. **可访问性**
   - 增加对色盲用户的支持（使用不同图案或文字标识而非仅颜色）
   - 提供高对比度模式选项

3. **功能扩展**
   - 支持行内差异高亮（word-level diff）
   - 支持折叠/展开特定文件的变更
   - 添加行号跳转功能

4. **测试覆盖**
   - 增加对更多终端模拟器的测试
   - 添加性能基准测试，确保大 diff 渲染不会阻塞
   - 测试各种 Unicode 边缘情况（组合字符、RTL 文本等）
