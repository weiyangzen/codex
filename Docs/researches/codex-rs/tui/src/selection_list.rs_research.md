# selection_list.rs 研究文档

## 场景与职责

`selection_list.rs` 是 Codex TUI 的选择列表渲染辅助模块，提供统一的选项行渲染功能。该模块是一个轻量级的 UI 工具模块，用于在各类选择弹窗（如确认对话框、配置选择等）中渲染带编号的选项行。

该模块的设计目标是提供一致的视觉风格，确保所有选择界面具有相同的交互模式和外观。

## 功能点目的

### 1. 选项行渲染
- 渲染带编号的选择选项（如 `› 1. Option A` 或 `  2. Option B`）
- 支持选中状态和非选中状态的样式区分
- 支持禁用/置灰状态的选项显示

### 2. 响应式文本包装
- 使用 ratatui 的 `Wrap` 功能处理长文本自动换行
- 确保选项内容在有限宽度内正确显示

## 具体技术实现

### 关键函数

```rust
/// 渲染标准选项行
pub(crate) fn selection_option_row(
    index: usize,           // 选项索引（从 0 开始）
    label: String,          // 显示文本
    is_selected: bool,      // 是否选中
) -> Box<dyn Renderable>

/// 渲染带禁用状态的选项行
pub(crate) fn selection_option_row_with_dim(
    index: usize,
    label: String,
    is_selected: bool,
    dim: bool,              // 是否置灰
) -> Box<dyn Renderable>
```

### 实现细节

```rust
pub(crate) fn selection_option_row_with_dim(
    index: usize,
    label: String,
    is_selected: bool,
    dim: bool,
) -> Box<dyn Renderable> {
    // 前缀格式：选中为 "› 1. "，未选中为 "  1. "
    let prefix = if is_selected {
        format!("› {}. ", index + 1)
    } else {
        format!("  {}. ", index + 1)
    };
    
    // 样式设置
    let style = if is_selected {
        Style::default().cyan()      // 选中：青色高亮
    } else if dim {
        Style::default().dim()       // 禁用：暗淡
    } else {
        Style::default()             // 正常：默认样式
    };
    
    let prefix_width = UnicodeWidthStr::width(prefix.as_str()) as u16;
    let mut row = RowRenderable::new();
    row.push(prefix_width, prefix.set_style(style));
    
    // 标签使用 Paragraph 包装以支持自动换行
    row.push(
        u16::MAX,
        Paragraph::new(label)
            .style(style)
            .wrap(Wrap { trim: false }),
    );
    row.into()
}
```

### 样式约定

| 状态 | 前缀 | 颜色 |
|------|------|------|
| 选中 | `› N. ` | Cyan (青色) |
| 未选中 | `  N. ` | 默认 |
| 禁用 | `  N. ` | Dim (暗淡) |

## 关键代码路径与文件引用

### 本文件关键函数

| 函数 | 行号 | 职责 |
|------|------|------|
| `selection_option_row` | 10 | 标准选项行渲染 |
| `selection_option_row_with_dim` | 18 | 支持禁用状态的选项行渲染 |

### 依赖模块

| 模块 | 路径 | 用途 |
|------|------|------|
| `Renderable` | `crate::render::renderable` | 渲染 trait |
| `RowRenderable` | `crate::render::renderable` | 行渲染器 |
| `ratatui::style` | 外部 crate | 样式定义 |
| `ratatui::widgets` | 外部 crate | Paragraph、Wrap |
| `unicode_width` | 外部 crate | 计算 Unicode 显示宽度 |

### 调用方

| 文件 | 用途 |
|------|------|
| `cwd_prompt.rs` | 工作目录选择提示 |
| `model_migration.rs` | 模型迁移提示 |
| `onboarding/trust_directory.rs` | 目录信任确认 |
| `update_prompt.rs` | 更新提示 |

## 依赖与外部交互

### 渲染架构集成

```
selection_option_row
    ↓ returns Box<dyn Renderable>
ColumnRenderable (或其他容器)
    ↓
ratatui::buffer::Buffer
    ↓
Terminal
```

### 与 Renderable 系统的协作

该模块返回 `Box<dyn Renderable>`，与 TUI 的统一渲染架构集成：

```rust
// 使用示例（来自 trust_directory.rs）
for (idx, (text, selection)) in options.iter().enumerate() {
    column.push(selection_option_row(
        idx,
        text.to_string(),
        self.highlighted == *selection,
    ));
}
```

## 风险、边界与改进建议

### 风险分析

1. **功能单一**
   - 模块非常简单（仅 46 行），功能高度聚焦
   - 风险极低，但扩展性有限

2. **硬编码样式**
   - 选中颜色固定为 Cyan
   - 如需主题定制，需要修改代码

### 边界情况

| 场景 | 处理方式 |
|------|----------|
| 空标签 | 正常渲染空 Paragraph |
| 极长标签 | 通过 Wrap 自动换行 |
| 宽字符 | 使用 UnicodeWidthStr 正确计算宽度 |

### 改进建议

1. **主题支持**
   - 将颜色提取到主题配置中，支持自定义
   - 考虑使用 `crate::style` 模块中的主题颜色

2. **功能扩展**
   - 添加图标支持（如选中/未选中的图标）
   - 支持快捷键提示（如 `› 1. [Y]es`）

3. **代码组织**
   - 当前实现合理，无需拆分
   - 可考虑添加单元测试验证渲染输出

### 与其他模块的关系

该模块是 `render` 模块系统的消费者，提供了高层级的选择列表行抽象。它与 `renderable.rs` 中定义的 `RowRenderable` 紧密协作，是 TUI 渲染层的一部分。
