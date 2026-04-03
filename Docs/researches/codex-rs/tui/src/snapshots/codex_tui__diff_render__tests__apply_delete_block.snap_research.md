# Diff Render - 文件删除块渲染测试

## 场景与职责

该快照测试验证 TUI（终端用户界面）中**文件删除操作**的 diff 渲染效果。当 Codex 执行文件删除时，需要在终端中以清晰、美观的方式展示被删除文件的内容，让用户能够直观地看到哪些内容被移除。

此组件属于 Codex TUI 的 diff 渲染子系统，负责将 `FileChange::Delete` 类型的变更转换为可视化的终端输出。

## 功能点目的

1. **删除文件的可视化展示**：显示被删除文件的文件名和完整内容
2. **行号标记**：为每行被删除的内容显示原始行号
3. **删除标记**：使用 `-` 符号明确标识删除操作
4. **统计信息**：展示删除的行数（`+0 -3` 表示新增0行，删除3行）
5. **一致性渲染**：与添加、更新操作保持视觉风格一致

## 具体技术实现

### 核心数据结构

```rust
// FileChange 枚举定义（来自 codex_protocol）
pub enum FileChange {
    Delete {
        content: String,  // 被删除文件的完整内容
    },
    // ... Add, Update 变体
}
```

### 渲染流程

1. **内容解析**：通过 `render_change` 函数处理 `FileChange::Delete` 变体
2. **语法高亮**：调用 `highlight_code_to_styled_spans` 尝试根据文件扩展名进行语法高亮
3. **行号计算**：使用 `line_number_width(content.lines().count())` 计算行号列宽
4. **逐行渲染**：对每行内容调用 `push_wrapped_diff_line_inner_with_theme_and_color_level`
   - 行号：右对齐显示
   - 标记符：`-` 表示删除
   - 内容：原始文本（带语法高亮）
   - 样式：红色主题（`DiffLineType::Delete`）

### 样式系统

- **深色主题**：使用 `#4A221D` 红色背景
- **浅色主题**：使用 `#ffebe9` 浅红色背景
- **ANSI-16 模式**：仅使用红色前景色，无背景色

### 关键代码路径

```rust
// diff_render.rs:515-546
FileChange::Delete { content } => {
    let syntax_lines = lang.and_then(|l| highlight_code_to_styled_spans(content, l));
    let line_number_width = line_number_width(content.lines().count());
    for (i, raw) in content.lines().enumerate() {
        // 渲染每行删除内容...
        push_wrapped_diff_line_inner_with_theme_and_color_level(
            i + 1,
            DiffLineType::Delete,  // 删除类型
            raw,
            width,
            line_number_width,
            syntax_spans,
            style_context,
        );
    }
}
```

## 关键代码路径与文件引用

| 组件 | 文件路径 | 职责 |
|------|----------|------|
| Diff 渲染主模块 | `codex-rs/tui/src/diff_render.rs` | 完整的 diff 渲染实现 |
| FileChange 定义 | `codex-rs/protocol/src/protocol.rs` | 文件变更类型定义 |
| 语法高亮 | `codex-rs/tui/src/render/highlight.rs` | 代码语法高亮实现 |
| 样式工具 | `codex-rs/tui/src/terminal_palette.rs` | 终端颜色管理 |
| 测试用例 | `diff_render.rs:1591-1603` | `ui_snapshot_apply_delete_block` 测试 |

### 相关函数

- `render_change()` - 主渲染入口
- `push_wrapped_diff_line_inner_with_theme_and_color_level()` - 单行渲染核心
- `style_del()` - 删除行样式计算
- `line_number_width()` - 行号列宽计算

## 依赖与外部交互

### 外部依赖

1. **diffy**：统一 diff 格式解析（`Patch::from_str`）
2. **ratatui**：终端 UI 渲染框架
3. **unicode-width**：Unicode 字符宽度计算
4. **syntect**：语法高亮（通过 `highlight_code_to_styled_spans`）

### 内部依赖

- `codex_core::git_info::get_git_repo_root` - Git 仓库根目录检测
- `codex_core::terminal::terminal_info` - 终端信息获取
- `crate::render::highlight::*` - 语法高亮模块
- `crate::terminal_palette::*` - 终端调色板

## 风险、边界与改进建议

### 潜在风险

1. **大文件删除性能**：删除大文件时需要渲染所有行，可能导致 UI 卡顿
2. **二进制文件处理**：当前实现假设内容为文本，二进制文件删除可能产生乱码
3. **编码问题**：非 UTF-8 编码的文件内容可能导致渲染异常

### 边界情况

1. **空文件删除**：`content` 为空字符串时的渲染行为
2. **超长行**：单行内容超过终端宽度时的自动换行（通过 `wrap_styled_spans` 处理）
3. **无换行符结尾**：文件末尾无换行符时的正确处理
4. **Tab 字符**：使用 `TAB_WIDTH=4` 计算显示宽度

### 改进建议

1. **大文件优化**：对于超过一定行数的删除操作，考虑只显示前 N 行并添加省略提示
2. **二进制检测**：在渲染前检测文件类型，对二进制文件显示特殊标识而非内容
3. **折叠功能**：支持用户折叠/展开删除内容的交互功能
4. **搜索高亮**：在删除内容中支持搜索关键词高亮
5. **行数限制配置**：允许用户配置最大显示行数，避免终端被大量删除内容占据

### 测试覆盖

当前测试用例验证了：
- 基本删除渲染（3行内容）
- 行号正确性（1, 2, 3）
- 统计信息准确性（+0 -3）
- 视觉格式（缩进、标记符位置）

建议补充：
- 空文件删除测试
- 超长行换行测试
- 包含特殊字符的内容测试
