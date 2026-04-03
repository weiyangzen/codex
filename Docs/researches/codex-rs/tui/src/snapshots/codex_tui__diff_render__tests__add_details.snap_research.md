# Diff Render Add Details 研究文档

## 场景与职责

该组件负责在 Codex TUI 中渲染文件添加（Add）操作的差异详情。当 AI 助手创建新文件时，系统需要向用户展示文件的添加内容、行数统计和语法高亮，以便用户审查和确认变更。

## 功能点目的

差异渲染（添加详情）的核心目的：

1. **变更可视化**：清晰展示新添加的文件内容
2. **行数统计**：显示添加的行数（+N）
3. **语法高亮**：根据文件类型提供语法高亮
4. **行号显示**：显示每行的行号便于引用
5. **统一格式**：与更新、删除操作保持一致的视觉风格

## 具体技术实现

### 添加操作数据结构

```rust
// codex_protocol::protocol::FileChange
pub enum FileChange {
    Add { content: String },
    Delete { content: String },
    Update { unified_diff: String, move_path: Option<PathBuf> },
}
```

### 添加详情渲染格式

```
• Proposed Change README.md (+2 -0)                                             
    1     +first line                                                           
    2     +second line                                                          
```

### 渲染流程

```rust
fn render_change(
    change: &FileChange,
    out: &mut Vec<RtLine<'static>>,
    width: usize,
    lang: Option<&str>,
) {
    let style_context = current_diff_render_style_context();
    match change {
        FileChange::Add { content } => {
            // 1. 预高亮整个文件内容
            let syntax_lines = lang.and_then(|l| highlight_code_to_styled_spans(content, l));
            let line_number_width = line_number_width(content.lines().count());
            
            // 2. 逐行渲染
            for (i, raw) in content.lines().enumerate() {
                let syn = syntax_lines.as_ref().and_then(|sl| sl.get(i));
                if let Some(spans) = syn {
                    // 带语法高亮的渲染
                    out.extend(push_wrapped_diff_line_inner_with_theme_and_color_level(
                        i + 1,
                        DiffLineType::Insert,
                        raw,
                        width,
                        line_number_width,
                        Some(spans),
                        style_context.theme,
                        style_context.color_level,
                        style_context.diff_backgrounds,
                    ));
                } else {
                    // 无语法高亮的渲染
                    out.extend(push_wrapped_diff_line_inner_with_theme_and_color_level(
                        i + 1,
                        DiffLineType::Insert,
                        raw,
                        width,
                        line_number_width,
                        None,
                        style_context.theme,
                        style_context.color_level,
                        style_context.diff_backgrounds,
                    ));
                }
            }
        }
        // ... Delete 和 Update 处理
    }
}
```

### 行渲染结构

每行差异包含三个部分：
```
┌──────────┬──────┬──────────────────────────────────────────┐
│  gutter  │ sign │              content                     │
│ (line #) │  +   │  (plain or syntax-highlighted text)      │
└──────────┴──────┴──────────────────────────────────────────┘
```

### 样式上下文

```rust
pub(crate) struct DiffRenderStyleContext {
    theme: DiffTheme,                    // Dark 或 Light
    color_level: DiffColorLevel,         // TrueColor, Ansi256, Ansi16
    diff_backgrounds: ResolvedDiffBackgrounds,  // 添加/删除背景色
}

#[derive(Clone, Copy, Debug)]
enum DiffTheme {
    Dark,
    Light,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum DiffColorLevel {
    TrueColor,
    Ansi256,
    Ansi16,
}
```

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/tui/src/diff_render.rs` | 差异渲染核心实现（第 1-1999+ 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/diff_render.rs` | `render_change` 函数（第 474-736 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/diff_render.rs` | `FileChange::Add` 处理逻辑（第 482-513 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/diff_render.rs` | `push_wrapped_diff_line_inner_with_theme_and_color_level`（第 838-938 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/render/highlight.rs` | 语法高亮支持 |

### 颜色配置
```rust
// 暗色主题添加行背景
const DARK_TC_ADD_LINE_BG_RGB: (u8, u8, u8) = (33, 58, 43);      // #213A2B
const DARK_256_ADD_LINE_BG_IDX: u8 = 22;

// 亮色主题添加行背景
const LIGHT_TC_ADD_LINE_BG_RGB: (u8, u8, u8) = (218, 251, 225);  // #dafbe1
const LIGHT_256_ADD_LINE_BG_IDX: u8 = 194;
```

## 依赖与外部交互

### 依赖模块
- `diffy` - 差异计算和补丁解析
- `crate::render::highlight` - 语法高亮
- `crate::terminal_palette` - 终端颜色调色板
- `codex_protocol::protocol::FileChange` - 文件变更协议

### 语法高亮交互
```rust
// 检测文件语言
fn detect_lang_for_path(path: &Path) -> Option<String> {
    let ext = path.extension()?.to_str()?;
    Some(ext.to_string())
}

// 高亮代码到样式化 spans
fn highlight_code_to_styled_spans(
    code: &str,
    lang: &str,
) -> Option<Vec<Vec<RtSpan<'static>>>>
```

### 样式系统
```rust
// 添加行样式
fn style_add(
    theme: DiffTheme,
    color_level: DiffColorLevel,
    diff_backgrounds: ResolvedDiffBackgrounds,
) -> Style {
    match (theme, color_level, diff_backgrounds.add) {
        (_, DiffColorLevel::Ansi16, _) => Style::default().fg(Color::Green),
        (DiffTheme::Light, _, Some(bg)) => Style::default().bg(bg),
        (DiffTheme::Dark, _, Some(bg)) => Style::default().fg(Color::Green).bg(bg),
        _ => Style::default().fg(Color::Green),
    }
}
```

## 风险、边界与改进建议

### 边界情况

1. **空文件**：添加空文件时的显示处理
2. **大文件**：添加数千行大文件时的性能问题
3. **无扩展名文件**：无法检测语言时的降级处理
4. **二进制文件**：二进制内容的显示限制

### 潜在风险

1. **渲染性能**：大文件语法高亮可能导致卡顿
2. **内存占用**：大量差异行可能占用过多内存
3. **颜色对比度**：某些终端主题下颜色可能不清晰
4. **换行处理**：长行的自动换行可能影响可读性

### 改进建议

1. **大文件优化**：
   ```rust
   // 建议对大文件进行截断显示
   const MAX_DIFF_LINES: usize = 1000;
   const MAX_DIFF_BYTES: usize = 100_000;
   
   fn should_truncate_diff(content: &str) -> bool {
       content.lines().count() > MAX_DIFF_LINES ||
       content.len() > MAX_DIFF_BYTES
   }
   ```

2. **折叠支持**：
   ```rust
   // 建议添加代码折叠功能
   struct FoldableDiffSection {
       start_line: usize,
       end_line: usize,
       is_folded: bool,
       summary: String,  // "+50 lines"
   }
   ```

3. **增量高亮**：
   ```rust
   // 建议对可见区域进行增量高亮
   fn highlight_visible_region(
       content: &str,
       lang: &str,
       viewport_start: usize,
       viewport_end: usize,
   ) -> Vec<Vec<RtSpan>> {
       // 只高亮可见区域...
   }
   ```

4. **主题适配**：
   ```rust
   // 建议支持更多主题配置
   struct DiffThemeConfig {
       add_line_bg: Color,
       add_sign_fg: Color,
       add_content_fg: Color,
       gutter_bg: Option<Color>,
       gutter_fg: Color,
   }
   ```

5. **行内差异**：
   ```rust
   // 建议对修改的行显示行内差异
   fn render_inline_diff(old_line: &str, new_line: &str) -> Vec<RtSpan> {
       // 高亮具体修改的字符...
   }
   ```

### 相关测试
- `ui_snapshot_apply_add_block` - 添加块快照测试
- `ui_snapshot_diff_gallery_80x24` - 差异画廊测试
- `ansi16_insert_delete_no_background` - ANSI16 模式测试
- `syntax_highlighted_insert_wraps` - 语法高亮换行测试
