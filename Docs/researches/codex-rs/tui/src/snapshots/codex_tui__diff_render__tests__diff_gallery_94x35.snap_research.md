# Diff Gallery 94x35 Snapshot 研究文档

## 场景与职责

此快照测试展示了 `diff_render` 模块在 94x35 终端尺寸下的 diff 渲染效果。与 80x24 版本相比，更宽的终端（94列）和更高的行数（35行）允许展示更多内容，特别是长行代码的完整显示。

该组件负责在 Codex TUI 中向用户展示代码变更，是代码审查和变更确认的核心界面元素。

## 功能点目的

1. **宽终端优化展示**：利用 94 列宽度展示更长的代码行
2. **多文件变更概览**：同时展示 6 个文件的变更情况
3. **语法高亮渲染**：对 Rust、Python 等语言代码进行语法高亮
4. **Unicode 字符正确处理**：正确处理 emoji（🚀✨）和 CJK 字符（你好世界、東京）
5. **变更类型完整覆盖**：涵盖 Add、Delete、Update（含 Rename）三种变更类型

## 具体技术实现

### 布局计算

```rust
// 可用内容宽度计算
let available_content_cols = width.saturating_sub(prefix_cols + 1).max(1);
```

在 94x35 终端中：
- 行号 gutter 宽度：根据最大行号动态计算（本例中为 2 列）
- 符号列（+/-/ ）：1 列
- 实际内容宽度：约 90 列

### 语法高亮实现

```rust
// 检测文件语言
fn detect_lang_for_path(path: &Path) -> Option<String> {
    let ext = path.extension()?.to_str()?;
    Some(ext.to_string())
}

// 重命名文件使用目标扩展名
let lang_path = r.move_path.as_deref().unwrap_or(&r.path);
let lang = detect_lang_for_path(lang_path);
```

### Unicode 宽字符处理

```rust
// 使用 unicode_width 计算显示宽度
let w = ch.width().unwrap_or(if ch == '\t' { TAB_WIDTH } else { 0 });
```

对于宽字符（如 CJK 字符占 2 列），系统会记录 "Hidden by multi-width symbols" 信息用于测试验证。

### 样式系统

```rust
// 解析后的背景色
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
struct ResolvedDiffBackgrounds {
    add: Option<Color>,  // 新增行背景
    del: Option<Color>,  // 删除行背景
}
```

## 关键代码路径与文件引用

### 核心渲染路径

```
create_diff_summary
  └── render_changes_block
       ├── render_path (渲染文件路径，含重命名箭头 →)
       ├── render_line_count_summary (渲染 +N -M 统计)
       └── render_change (根据类型渲染变更内容)
            ├── FileChange::Add (新增文件)
            │    └── highlight_code_to_styled_spans
            ├── FileChange::Delete (删除文件)
            │    └── highlight_code_to_styled_spans
            └── FileChange::Update (更新文件)
                 ├── diffy::Patch::from_str (解析 diff)
                 ├── exceeds_highlight_limits (检查大小限制)
                 └── highlight_code_to_styled_spans (hunk 级高亮)
```

### 关键文件与行号

| 文件 | 行号范围 | 说明 |
|------|----------|------|
| `diff_render.rs` | 474-736 | `render_change` 主函数 |
| `diff_render.rs` | 838-938 | 单行渲染核心逻辑 |
| `diff_render.rs` | 1404-1458 | 测试数据构造 `diff_gallery_changes` |
| `diff_render.rs` | 1754-1757 | 94x35 快照测试 |

### 测试数据详情

测试数据包含 6 个文件的变更：

1. **src/lib.rs** (Update)：Rust 代码修改，展示多行变更和 CJK/emoji 支持
2. **scripts/calc.txt → scripts/calc.py** (Update + Rename)：Python 文件重命名并修改
3. **assets/banner.txt** (Add)：新增文本文件，含 tab 分隔和 emoji
4. **examples/new_sample.rs** (Add)：新增 Rust 文件
5. **tmp/obsolete.log** (Delete)：删除日志文件（在 94x35 中可见）
6. **legacy/old_script.py** (Delete)：删除 Python 文件

## 依赖与外部交互

### 核心依赖

| 依赖 | 版本 | 用途 |
|------|------|------|
| `ratatui` | 0.29+ | 终端 UI 渲染 |
| `diffy` | 0.4+ | Diff 解析 |
| `unicode-width` | 0.2+ | Unicode 字符宽度计算 |
| `syntect` | 通过 highlight 模块 | 语法高亮 |

### 颜色系统交互

```rust
// 从终端检测颜色能力
fn diff_color_level() -> DiffColorLevel {
    diff_color_level_for_terminal(
        stdout_color_level(),
        terminal_info().name,
        std::env::var_os("WT_SESSION").is_some(),
        has_force_color_override(),
    )
}
```

### 主题集成

支持从语法主题读取 diff 背景色配置：
- `markup.inserted` / `diff.inserted` → 新增行背景
- `markup.deleted` / `diff.deleted` → 删除行背景

## 风险、边界与改进建议

### 当前限制

1. **行宽限制**：
   - 即使 94 列宽度，某些长行仍需要换行
   - 换行后的缩进使用 2 空格，可能不够明显

2. **语法高亮限制**：
   - 超过 10,000 行或 10MB 的 diff 跳过高亮
   - 某些边缘语言可能没有语法定义

3. **重命名检测**：
   - 依赖 `move_path` 字段，如果未设置则显示为普通更新

### 潜在问题

1. **性能问题**：
   ```rust
   // 大 diff 的 hunk 处理
   for h in patch.hunks() {
       // 每个 hunk 都进行语法高亮
       let hunk_syntax_lines = diff_lang.and_then(|language| {
           let hunk_text: String = h.lines().iter()...
       });
   }
   ```
   大量 hunks 时可能影响渲染性能

2. **颜色一致性**：
   - 不同终端对 ANSI-256 颜色的渲染可能有差异
   - TrueColor 支持检测可能不准确

### 改进建议

1. **交互增强**：
   - 添加文件折叠功能，允许用户收起/展开单个文件
   - 支持在 diff 中搜索
   - 点击行号跳转到编辑器

2. **渲染优化**：
   - 实现虚拟列表，只渲染可见区域的 diff 行
   - 缓存语法高亮结果

3. **可配置性**：
   - 允许用户自定义颜色方案
   - 配置 tab 宽度（当前硬编码为 4）
   - 配置是否显示行号

4. **可访问性**：
   - 添加对色盲友好的配色方案
   - 支持屏幕阅读器

5. **功能扩展**：
   - 支持 side-by-side diff 视图
   - 显示变更的字符级 diff（word diff）
   - 集成 git blame 信息显示
