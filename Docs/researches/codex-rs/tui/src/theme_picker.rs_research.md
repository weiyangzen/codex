# theme_picker.rs 深度研究文档

## 场景与职责

`theme_picker.rs` 是 Codex TUI 中负责**语法主题选择器**的模块。它构建 `/theme` 命令的主题选择对话框，提供主题列表、实时预览和持久化功能。

### 核心职责

1. **主题列表构建**：列出所有捆绑主题和自定义 `.tmTheme` 文件
2. **实时预览**：用户导航时即时切换主题预览
3. **取消恢复**：取消选择时恢复原始主题
4. **持久化**：确认选择后将主题保存到 `config.toml`
5. **自适应布局**：根据终端宽度选择并排或堆叠预览布局

### 使用场景

- 用户执行 `/theme` 命令打开主题选择器
- 浏览和预览可用语法高亮主题
- 添加自定义 `.tmTheme` 主题文件
- 切换代码块的语法高亮风格

---

## 功能点目的

### 1. 主题预览数据结构

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum PreviewDiffKind {
    Context,   // 上下文行
    Added,     // 新增行
    Removed,   // 删除行
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct PreviewRow {
    line_no: usize,
    kind: PreviewDiffKind,
    code: &'static str,
}
```

### 2. 预览布局

- **宽屏预览** (`ThemePreviewWideRenderable`)：
  - 并排布局（side-by-side）
  - 需要侧边面板 >= 44 列
  - 垂直居中，左侧缩进 2 列
  - 8 行 Rust diff 代码示例

- **窄屏预览** (`ThemePreviewNarrowRenderable`)：
  - 堆叠布局（stacked）
  - 4 行紧凑 Rust diff 代码示例
  - 显示在列表下方

### 3. 主题选择器参数构建

```rust
pub(crate) fn build_theme_picker_params(
    current_name: Option<&str>,
    codex_home: Option<&Path>,
    terminal_width: Option<u16>,
) -> SelectionViewParams
```

功能：
- 收集所有可用主题（内置 + 自定义）
- 预选择当前主题
- 设置实时预览回调
- 设置取消恢复回调
- 配置搜索和过滤

---

## 具体技术实现

### 关键流程

#### 1. 预览渲染流程

```rust
fn render_preview(
    area: Rect,
    buf: &mut Buffer,
    preview_rows: &[PreviewRow],
    center_vertically: bool,
    left_inset: u16,
) {
    // 1. 获取语法高亮后的代码
    let preview_code = preview_rows.iter().map(|row| row.code).collect::<Vec<_>>().join("\n");
    let syntax_lines = highlight::highlight_code_to_styled_spans(&preview_code, "rust");

    // 2. 计算行号宽度
    let max_line_no = preview_rows.iter().map(|row| row.line_no).max().unwrap_or(1);
    let ln_width = line_number_width(max_line_no);

    // 3. 计算垂直居中偏移
    let top_pad = if center_vertically {
        centered_offset(area.height, content_height, PREVIEW_FRAME_PADDING)
    } else { 0 };

    // 4. 逐行渲染
    for (idx, row) in preview_rows.iter().enumerate() {
        let diff_type = preview_diff_line_type(row.kind);
        let wrapped = if let Some(syn) = syntax_lines.as_ref().and_then(|sl| sl.get(idx)) {
            // 使用语法高亮
            push_wrapped_diff_line_with_syntax_and_style_context(...)
        } else {
            // 无语法高亮
            push_wrapped_diff_line_with_style_context(...)
        };
        first_line.render(...);
    }
}
```

#### 2. 主题选择器构建流程

```rust
pub(crate) fn build_theme_picker_params(...) -> SelectionViewParams {
    // 1. 保存原始主题（用于取消恢复）
    let original_theme = highlight::current_syntax_theme();

    // 2. 获取所有可用主题
    let entries = highlight::list_available_themes(codex_home);

    // 3. 解析有效主题名
    let effective_name = if let Some(name) = current_name
        && entries.iter().any(|entry| entry.name == name)
    {
        name.to_string()
    } else {
        highlight::configured_theme_name()  // 回退到配置的主题
    };

    // 4. 构建选择项列表
    let items: Vec<SelectionItem> = entries.iter().enumerate().map(|(idx, entry)| {
        // 标记当前主题
        // 设置选择动作为发送 SyntaxThemeSelected 事件
    }).collect();

    // 5. 设置实时预览回调
    let on_selection_changed = Some(Box::new(move |idx: usize, _tx: &_| {
        if let Some(Some(name)) = preview_theme_names.get(idx) {
            if let Some(theme) = highlight::resolve_theme_by_name(name, preview_home.as_deref()) {
                highlight::set_syntax_theme(theme);
            }
        }
    }));

    // 6. 设置取消恢复回调
    let on_cancel = Some(Box::new(move |_tx: &_| {
        highlight::set_syntax_theme(original_theme.clone());
    }));

    SelectionViewParams { ... }
}
```

#### 3. 垂直居中计算

```rust
fn centered_offset(available: u16, content: u16, min_frame: u16) -> u16 {
    let free = available.saturating_sub(content);
    let frame = if free >= min_frame.saturating_mul(2) {
        min_frame
    } else { 0 };
    frame + free.saturating_sub(frame.saturating_mul(2)) / 2
}
```

### 预览代码示例

**窄屏预览**（4 行）：
```rust
fn greet(name: &str) -> String {
    format!("Hello, {}!", name)      // - 删除行
    format!("Hello, {name}!")        // + 新增行
}
```

**宽屏预览**（8 行）：
```rust
fn summarize(users: &[User]) -> String {
    let active = users.iter().filter(|u| u.is_active).count();   // - 删除
    let active = users.iter().filter(|u| u.is_active()).count(); // + 新增
    // ... 更多上下文和 diff 行
}
```

---

## 关键代码路径与文件引用

### 内部依赖

| 模块 | 路径 | 用途 |
|------|------|------|
| `bottom_pane::SelectionViewParams` | `bottom_pane/list_selection_view.rs` | 选择视图参数 |
| `bottom_pane::SelectionItem` | `bottom_pane/list_selection_view.rs` | 选择项定义 |
| `render::highlight` | `render/highlight.rs` | 语法高亮 |
| `diff_render` | `diff_render.rs` | diff 渲染工具 |
| `status::format_directory_display` | `status/mod.rs` | 目录格式化 |
| `app_event::AppEvent` | `app_event.rs` | 应用事件 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染 |
| `unicode_width` | 宽度计算 |

### 调用方

| 文件 | 用途 |
|------|------|
| `chatwidget.rs` | 处理 `/theme` 命令 |
| `bottom_pane/list_selection_view.rs` | 渲染选择视图 |

---

## 依赖与外部交互

### 与 highlight 模块的交互

```
theme_picker.rs
    ├── highlight::list_available_themes() - 获取主题列表
    ├── highlight::current_syntax_theme() - 获取当前主题
    ├── highlight::configured_theme_name() - 获取配置的主题名
    ├── highlight::resolve_theme_by_name() - 按名称解析主题
    ├── highlight::set_syntax_theme() - 设置主题（预览/恢复）
    └── highlight::highlight_code_to_styled_spans() - 语法高亮
```

### 与选择视图的交互

```
build_theme_picker_params()
    └── SelectionViewParams
            ├── items: Vec<SelectionItem> - 主题列表
            ├── on_selection_changed - 实时预览回调
            ├── on_cancel - 取消恢复回调
            ├── side_content - 宽屏预览组件
            ├── stacked_side_content - 窄屏预览组件
            └── ... 其他选择视图配置
```

### 主题持久化流程

```
用户选择主题
    ↓
SelectionItem action 发送 AppEvent::SyntaxThemeSelected
    ↓
App 处理事件，调用 ConfigEditsBuilder
    ↓
写入 [tui] theme = "..." 到 config.toml
```

---

## 风险、边界与改进建议

### 已知风险

1. **主题预览副作用**：实时预览会临时改变全局主题状态
2. **并发问题**：如果多个选择器同时打开，主题状态可能混乱
3. **自定义主题加载失败**：自定义 `.tmTheme` 文件可能解析失败

### 边界情况

1. **无可用主题**：`list_available_themes` 应始终返回至少默认主题
2. **主题名冲突**：自定义主题与内置主题同名时的处理
3. **终端宽度变化**：预览布局在终端调整大小时自动切换
4. **取消恢复失败**：原始主题可能在预览期间被外部修改

### 测试覆盖

| 测试 | 描述 |
|------|------|
| `theme_picker_uses_half_width_with_stacked_fallback_preview` | 布局配置 |
| `theme_picker_items_include_search_values_for_preview_mapping` | 预览映射 |
| `wide_preview_renders_all_lines_with_vertical_center_and_left_inset` | 宽屏预览 |
| `narrow_preview_renders_single_add_and_single_remove_in_four_lines` | 窄屏预览 |
| `deleted_preview_code_uses_dim_overlay_like_real_diff_renderer` | 样式验证 |
| `subtitle_uses_tilde_path_when_codex_home_under_home_directory` | 副标题路径 |
| `subtitle_falls_back_when_tilde_path_subtitle_is_too_wide` | 副标题回退 |
| `unavailable_configured_theme_falls_back_to_configured_or_default_selection` | 主题回退 |

### 改进建议

1. **预览隔离**：
   - 使用临时主题上下文，避免影响全局状态
   - 支持并排比较两个主题

2. **性能优化**：
   - 缓存主题预览渲染结果
   - 延迟加载自定义主题

3. **功能增强**：
   - 支持主题搜索和过滤
   - 添加主题收藏功能
   - 显示主题预览缩略图

4. **用户体验**：
   - 添加主题描述和作者信息
   - 支持导入/导出主题
   - 添加主题评分系统

5. **可访问性**：
   - 为主题提供高对比度预览
   - 支持色盲友好的主题推荐

### 代码特点

- **自适应设计**：根据终端宽度自动选择布局
- **实时反馈**：即时预览提升用户体验
- **安全回退**：多处回退逻辑确保稳定性
- **文档完善**：模块级文档详细说明设计意图

### 相关文件

- `render/highlight.rs`：语法高亮核心
- `bottom_pane/list_selection_view.rs`：选择视图实现
- `app.rs`：主题选择事件处理
- `chatwidget.rs`：`/theme` 命令处理
