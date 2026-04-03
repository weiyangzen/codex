# ThemePicker 研究文档

## 场景与职责

`theme_picker.rs` 实现了 Codex TUI 的 `/theme` 命令主题选择器。这是用户选择语法高亮主题的核心 UI 组件，提供：

1. **主题列表展示**：显示所有内置主题和自定义主题
2. **实时预览**：在选择时即时预览主题效果
3. **取消恢复**：取消选择时恢复原始主题
4. **配置持久化**：确认选择后将主题保存到配置
5. **自适应布局**：根据终端宽度选择并排或堆叠布局

该模块位于 `codex-rs/tui_app_server/src/theme_picker.rs`，是 TUI 交互组件的复杂示例。

## 功能点目的

### 1. 主题选择界面

构建 `SelectionViewParams` 用于 `ListSelectionView`：
- 列出所有可用主题（内置 + 自定义）
- 标记当前活动主题
- 支持搜索过滤

### 2. 实时预览系统

- **选择变更回调**：`on_selection_changed` 在光标移动时切换主题
- **预览渲染**：使用 Rust 代码 diff 示例展示语法高亮效果
- **两种预览模式**：
  - `ThemePreviewWideRenderable`：并排模式，8 行代码示例，垂直居中
  - `ThemePreviewNarrowRenderable`：堆叠模式，4 行紧凑代码示例

### 3. 取消恢复机制

- **打开时快照**：记录当前主题
- **取消时恢复**：`on_cancel` 回调恢复原始主题
- **确认时持久化**：`SyntaxThemeSelected` 事件保存到配置

### 4. 自定义主题支持

- 从 `{CODEX_HOME}/themes/*.tmTheme` 加载自定义主题
- 自定义主题标记为 "(custom)" 后缀
- 验证主题文件有效性

## 具体技术实现

### 预览代码示例

**紧凑模式（4行）：**
```rust
const NARROW_PREVIEW_ROWS: [PreviewRow; 4] = [
    PreviewRow { line_no: 12, kind: Context, code: "fn greet(name: &str) -> String {" },
    PreviewRow { line_no: 13, kind: Removed, code: "    format!(\"Hello, {}!\", name)" },
    PreviewRow { line_no: 13, kind: Added, code: "    format!(\"Hello, {name}!\")" },
    PreviewRow { line_no: 14, kind: Context, code: "}" },
];
```

**宽屏模式（8行）：**
```rust
const WIDE_PREVIEW_ROWS: [PreviewRow; 8] = [
    PreviewRow { line_no: 31, kind: Context, code: "fn summarize(users: &[User]) -> String {" },
    PreviewRow { line_no: 32, kind: Removed, code: "    let active = users.iter().filter(|u| u.is_active).count();" },
    PreviewRow { line_no: 32, kind: Added, code: "    let active = users.iter().filter(|u| u.is_active()).count();" },
    // ... 更多行
];
```

### 主题选择器参数构建

```rust
pub(crate) fn build_theme_picker_params(
    current_name: Option<&str>,
    codex_home: Option<&Path>,
    terminal_width: Option<u16>,
) -> SelectionViewParams {
    // 1. 快照当前主题
    let original_theme = highlight::current_syntax_theme();

    // 2. 获取所有可用主题
    let entries = highlight::list_available_themes(codex_home);

    // 3. 解析有效主题名
    let effective_name = if let Some(name) = current_name
        && entries.iter().any(|entry| entry.name == name)
    {
        name.to_string()
    } else {
        highlight::configured_theme_name()
    };

    // 4. 构建选择项
    let items: Vec<SelectionItem> = entries
        .iter()
        .enumerate()
        .map(|(idx, entry)| {
            let display_name = if entry.is_custom {
                format!("{} (custom)", entry.name)
            } else {
                entry.name.clone()
            };
            // ... 构建 SelectionItem
        })
        .collect();

    // 5. 设置回调
    let on_selection_changed = Some(Box::new(move |idx: usize, _tx: &_| {
        if let Some(Some(name)) = preview_theme_names.get(idx)
            && let Some(theme) = highlight::resolve_theme_by_name(name, preview_home.as_deref())
        {
            highlight::set_syntax_theme(theme);
        }
    }));

    let on_cancel = Some(Box::new(move |_tx: &_| {
        highlight::set_syntax_theme(original_theme.clone());
    }));

    SelectionViewParams {
        title: Some("Select Syntax Theme".to_string()),
        subtitle: Some(theme_picker_subtitle(codex_home_owned.as_deref(), terminal_width)),
        items,
        is_searchable: true,
        side_content: Box::new(ThemePreviewWideRenderable),
        side_content_width: SideContentWidth::Half,
        side_content_min_width: WIDE_PREVIEW_MIN_WIDTH,
        stacked_side_content: Some(Box::new(ThemePreviewNarrowRenderable)),
        on_selection_changed,
        on_cancel,
        ..Default::default()
    }
}
```

### 预览渲染

```rust
impl Renderable for ThemePreviewWideRenderable {
    fn desired_height(&self, _width: u16) -> u16 {
        u16::MAX  // 占据所有可用高度
    }

    fn render(&self, area: Rect, buf: &mut Buffer) {
        render_preview(
            area,
            buf,
            &WIDE_PREVIEW_ROWS,
            /*center_vertically*/ true,
            WIDE_PREVIEW_LEFT_INSET,
        );
    }
}

fn render_preview(
    area: Rect,
    buf: &mut Buffer,
    preview_rows: &[PreviewRow],
    center_vertically: bool,
    left_inset: u16,
) {
    // 1. 高亮预览代码
    let preview_code = preview_rows.iter().map(|row| row.code).collect::<Vec<_>>().join("\n");
    let syntax_lines = highlight::highlight_code_to_styled_spans(&preview_code, "rust");

    // 2. 计算布局
    let content_height = (preview_rows.len() as u16).min(area.height);
    let top_pad = if center_vertically {
        centered_offset(area.height, content_height, PREVIEW_FRAME_PADDING)
    } else {
        0
    };

    // 3. 渲染每行（带 diff 样式和语法高亮）
    for (idx, row) in preview_rows.iter().enumerate() {
        let diff_type = preview_diff_line_type(row.kind);
        let wrapped = if let Some(syn) = syntax_lines.as_ref().and_then(|sl| sl.get(idx)) {
            push_wrapped_diff_line_with_syntax_and_style_context(...)
        } else {
            push_wrapped_diff_line_with_style_context(...)
        };
        // 渲染...
    }
}
```

### 副标题生成

```rust
fn theme_picker_subtitle(codex_home: Option<&Path>, terminal_width: Option<u16>) -> String {
    let themes_dir = codex_home.map(|home| home.join("themes"));
    let themes_dir_display = themes_dir
        .as_deref()
        .map(|path| format_directory_display(path, /*max_width*/ None));
    let available_width = subtitle_available_width(terminal_width);

    // 如果路径以 ~ 开头且能容纳，显示自定义主题路径提示
    if let Some(path) = themes_dir_display
        && path.starts_with('~')
    {
        let subtitle = format!("Custom .tmTheme files can be added to the {path} directory.");
        if UnicodeWidthStr::width(subtitle.as_str()) <= available_width {
            return subtitle;
        }
    }

    // 否则显示默认提示
    PREVIEW_FALLBACK_SUBTITLE.to_string()
}
```

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/theme_picker.rs` (637 行)

### 依赖模块
| 模块 | 用途 |
|------|------|
| `render::highlight` | 语法高亮 |
| `diff_render` | Diff 渲染样式 |
| `bottom_pane::SelectionViewParams` | 选择视图参数 |
| `bottom_pane::SelectionItem` | 选择项定义 |
| `status::format_directory_display` | 路径格式化 |

### 调用方
- `chatwidget.rs` - 处理 `/theme` 命令
- `bottom_pane/mod.rs` - 显示主题选择器

### 关键常量
```rust
const WIDE_PREVIEW_MIN_WIDTH: u16 = 44;      // 并排模式最小宽度
const WIDE_PREVIEW_LEFT_INSET: u16 = 2;      // 宽预览左缩进
const PREVIEW_FRAME_PADDING: u16 = 1;        // 预览框架内边距
const PREVIEW_FALLBACK_SUBTITLE: &str = "Move up/down to live preview themes";
```

## 依赖与外部交互

### 外部依赖
- `ratatui` - TUI 渲染
- `unicode_width` - 字符宽度计算
- `std::path` - 路径处理

### 内部依赖
| 模块 | 用途 |
|------|------|
| `render::highlight` | 主题查询和设置 |
| `diff_render` | Diff 行渲染 |
| `bottom_pane` | 选择视图基础设施 |
| `app_event` | 主题选择事件 |

## 风险、边界与改进建议

### 潜在风险

1. **主题切换副作用**：实时预览在光标移动时立即切换全局主题状态，如果用户快速滚动可能产生闪烁。

2. **预览代码硬编码**：预览使用的 Rust 代码是硬编码的，可能无法展示某些语言的特定高亮特性。

3. **布局阈值硬编码**：`WIDE_PREVIEW_MIN_WIDTH = 44` 是经验值，可能不适合所有终端。

### 边界情况

1. **无可用主题**：如果主题列表为空，选择器将显示空列表。

2. **自定义主题无效**：无效的 `.tmTheme` 文件会被过滤掉。

3. **终端宽度变化**：副标题根据终端宽度动态调整，窄终端显示简化提示。

4. **配置主题不可用**：如果配置的主题名不存在，回退到配置/默认主题。

### 测试覆盖

模块包含全面的单元测试：
- `theme_picker_uses_half_width_with_stacked_fallback_preview` - 布局配置
- `theme_picker_items_include_search_values_for_preview_mapping` - 搜索值
- `wide_preview_renders_all_lines_with_vertical_center_and_left_inset` - 宽预览渲染
- `narrow_preview_renders_single_add_and_single_remove_in_four_lines` - 窄预览渲染
- `deleted_preview_code_uses_dim_overlay_like_real_diff_renderer` - 删除行样式
- `subtitle_*` - 副标题各种场景
- `unavailable_configured_theme_falls_back_to_configured_or_default_selection` - 回退逻辑

### 改进建议

1. **多语言预览**：允许用户选择预览代码的语言，或自动检测常用语言。

2. **预览缓存**：缓存预览渲染结果，避免每次光标移动都重新高亮。

3. **主题收藏**：允许用户标记常用主题，优先显示。

4. **主题搜索增强**：支持按颜色特征搜索（如 "dark", "high contrast"）。

5. **预览动画**：添加平滑过渡动画，减少主题切换时的闪烁感。

6. **自定义预览代码**：允许用户配置预览使用的代码片段。

7. **主题对比模式**：支持同时预览两个主题的对比效果。
