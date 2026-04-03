# Diff Gallery 80x24 Snapshot 研究文档

## 场景与职责

此快照测试展示了 `diff_render` 模块在 80x24 终端尺寸下的完整 diff 渲染能力。它负责将代码变更以统一的 diff 格式呈现给用户，是 Codex TUI 中文件变更展示的核心组件。

该组件处理的场景包括：
- 文件添加（Add）：显示新增文件的全部内容
- 文件删除（Delete）：显示被删除文件的内容
- 文件更新（Update）：显示文件修改的 unified diff
- 文件重命名（Rename）：显示文件从旧路径移动到新路径的变更

## 功能点目的

1. **多文件变更汇总展示**：在一个视图中展示多个文件的变更概览
2. **行号对齐渲染**：为每行代码显示右对齐的行号，保持视觉一致性
3. **语法高亮支持**：根据文件扩展名自动检测语言并应用语法高亮
4. **Unicode 宽字符处理**：正确处理 emoji 和 CJK 字符的显示宽度
5. **变更统计**：显示每个文件的添加行数（+）和删除行数（-）

## 具体技术实现

### 核心数据结构

```rust
// 变更行类型分类
pub(crate) enum DiffLineType {
    Insert,   // 新增行，显示 + 号
    Delete,   // 删除行，显示 - 号
    Context,  // 上下文行，显示空格
}

// 主题适配
enum DiffTheme {
    Dark,   // 暗色主题
    Light,  // 亮色主题
}

// 颜色深度级别
enum DiffColorLevel {
    TrueColor,
    Ansi256,
    Ansi16,
}
```

### 渲染流程

1. **变更收集与排序**（`collect_rows` 函数）：
   - 遍历 `HashMap<PathBuf, FileChange>` 收集所有变更
   - 计算每个文件的添加/删除行数
   - 按路径排序确保稳定输出

2. **Header 渲染**（`render_changes_block` 函数）：
   - 单文件：显示 "Added/Deleted/Edited" + 文件名 + 统计
   - 多文件：显示 "Edited N files" + 总体统计

3. **文件详情渲染**（`render_change` 函数）：
   - 根据变更类型（Add/Delete/Update）选择不同渲染策略
   - 使用 `diffy` 库解析 unified diff
   - 调用 `highlight_code_to_styled_spans` 进行语法高亮

4. **单行渲染**（`push_wrapped_diff_line_inner_with_theme_and_color_level`）：
   - 组合行号、符号（+/-/ ）、内容
   - 应用主题颜色和背景色
   - 处理长行自动换行

### 语法高亮策略

对于 Update 类型的 diff，采用 **hunk 级高亮**而非行级高亮：
- 将整个 hunk 的内容拼接后一次性高亮
- 保持 syntect 解析器状态跨行连续
- 正确处理多行字符串、块注释等跨行语法结构

### 颜色主题系统

```rust
// 暗色主题背景色
const DARK_TC_ADD_LINE_BG_RGB: (u8, u8, u8) = (33, 58, 43);   // #213A2B 绿色
const DARK_TC_DEL_LINE_BG_RGB: (u8, u8, u8) = (74, 34, 29);   // #4A221D 红色

// 亮色主题背景色（GitHub 风格）
const LIGHT_TC_ADD_LINE_BG_RGB: (u8, u8, u8) = (218, 251, 225); // #dafbe1
const LIGHT_TC_DEL_LINE_BG_RGB: (u8, u8, u8) = (255, 235, 233); // #ffebe9
```

## 关键代码路径与文件引用

### 主要文件

- `codex-rs/tui/src/diff_render.rs`：diff 渲染的核心实现

### 关键函数

| 函数名 | 行号 | 职责 |
|--------|------|------|
| `create_diff_summary` | 345-352 | 创建 diff 摘要的主入口 |
| `render_changes_block` | 402-464 | 渲染变更块，包括 header 和文件列表 |
| `render_change` | 474-736 | 根据 FileChange 类型渲染具体变更内容 |
| `push_wrapped_diff_line_inner_with_theme_and_color_level` | 838-938 | 渲染单行的核心函数 |
| `wrap_styled_spans` | 951-1020 | 处理带样式的文本换行 |
| `resolve_diff_backgrounds` | 198-203 | 解析主题背景色 |

### 测试相关

- `diff_gallery_changes` | 1404-1458 | 构造测试用的多文件变更数据
- `snapshot_diff_gallery` | 1460-1467 | 生成快照的辅助函数
- `ui_snapshot_diff_gallery_80x24` | 1749-1752 | 80x24 尺寸的快照测试

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `diffy` | 解析 unified diff 格式 |
| `ratatui` | 终端 UI 渲染框架 |
| `unicode_width` | 计算 Unicode 字符显示宽度 |
| `syntect`（通过 `highlight_code_to_styled_spans`）| 语法高亮 |

### 内部模块交互

- `crate::render::highlight`：语法高亮功能
- `crate::terminal_palette`：终端颜色检测和调色板
- `crate::color`：颜色工具函数
- `codex_core::git_info`：Git 仓库根目录检测

## 风险、边界与改进建议

### 已知风险

1. **大文件性能问题**：
   - 超过 10,000 行或 10MB 的 diff 会跳过语法高亮
   - 风险：超大 diff 可能导致渲染卡顿

2. **Unicode 宽字符处理**：
   - emoji 和 CJK 字符需要特殊处理显示宽度
   - 某些终端可能对宽字符支持不一致

3. **Windows Terminal 颜色检测**：
   - 依赖 `WT_SESSION` 环境变量检测 Windows Terminal
   - 在某些配置下可能无法正确识别

### 边界情况

1. **空文件处理**：
   - 添加空文件：显示文件名但无内容行
   - 删除空文件：同样显示文件名但无内容

2. **重命名检测**：
   - 使用 `move_path` 字段标识重命名
   - 高亮时使用目标文件扩展名（新文件名）

3. **ANSI-16 终端降级**：
   - 仅使用前景色，不显示背景色
   - 可能降低可读性

### 改进建议

1. **性能优化**：
   - 考虑对超大 diff 实现虚拟滚动，只渲染可见区域
   - 使用增量渲染避免重复计算

2. **可访问性**：
   - 添加配置选项允许用户自定义颜色
   - 支持高对比度模式

3. **功能扩展**：
   - 支持折叠/展开单个文件的变更
   - 添加行内 diff（word-level diff）显示
   - 支持二进制文件的变更展示

4. **测试覆盖**：
   - 添加更多边界情况的测试（如空文件、全空行文件）
   - 测试不同终端模拟器的颜色渲染一致性
