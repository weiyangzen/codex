# Research: Diff Gallery 80x24 Terminal Rendering Test

## Snapshot File
`codex_tui__diff_render__tests__diff_gallery_80x24.snap`

## 场景与职责

### 测试目标
该测试验证 diff 渲染器在**标准终端尺寸（80列 x 24行）**下的渲染能力。80x24 是 Unix/Linux 终端的传统标准尺寸，也是许多终端模拟器的默认大小。

### 实际应用场景
- **默认终端窗口**：大多数终端模拟器的初始尺寸
- **SSH 远程会话**：服务器环境的常见终端尺寸
- **分屏/多窗格**：在 tmux/screen 分屏后的单窗格尺寸
- **兼容性测试**：确保在最小支持尺寸下正常显示

### 测试数据
与 `diff_gallery_120x40` 使用相同的测试数据集（`diff_gallery_changes` 函数构造），包含6个文件的混合变更：
- 2个 Update（含1个重命名）
- 2个 Add
- 2个 Delete

## 功能点目的

### 核心功能验证
1. **标准尺寸适配**：验证在 80 列宽度下的布局正确性
2. **换行处理**：验证长行在窄宽度下的硬换行
3. **内容截断/换行**：验证宽字符内容在有限空间内的显示
4. **行号列压缩**：验证行号列在有限宽度下的最小化显示

### 与 120x40 测试的对比

| 特性 | 80x24 | 120x40 |
|-----|-------|--------|
| 可用列数 | 80 | 120 |
| 内容换行 | 更多换行 | 较少换行 |
| 文件显示 | 可能截断 | 完整显示 |
| 适用场景 | 标准终端 | 大屏/全屏 |

### 渲染输出分析
```
• Edited 6 files (+9 -9)                                                        
  └ assets/banner.txt (+3 -0)                                                   
    1 +HEADER	VALUE                                                             
    2 +rocket	🚀                                                                [Hidden: (15, " ")]
    3 +city	東京                                                                [Hidden: (13, " "), (15, " ")]
```

在 80 列下：
- 文件路径显示完整（`assets/banner.txt`）
- 内容区域约 72 列（扣除缩进和行号）
- tab 字符和宽字符仍然正确处理

## 具体技术实现

### 宽度计算逻辑
```rust
fn render_changes_block(rows: Vec<Row>, wrap_cols: usize, cwd: &Path) -> Vec<RtLine<'static>> {
    // ...
    let mut lines = vec![];
    render_change(&r.change, &mut lines, wrap_cols - 4, lang.as_deref());
    // wrap_cols - 4: 扣除 "    " 缩进
    out.extend(prefix_lines(lines, "    ".into(), "    ".into()));
}
```

当 `wrap_cols = 80` 时：
- 实际内容宽度：`80 - 4 = 76` 列
- 再扣除行号和符号列（约 4-6 列），实际文本区域约 70 列

### 行号宽度动态计算
```rust
pub(crate) fn line_number_width(max_line_number: usize) -> usize {
    if max_line_number == 0 {
        1
    } else {
        max_line_number.to_string().len()
    }
}
```

在测试中，最大行号为 4（`scripts/calc.txt`），所以行号宽度为 1 列。

### 换行核心算法
```rust
fn wrap_styled_spans(spans: &[RtSpan<'static>], max_cols: usize) -> Vec<Vec<RtSpan<'static>>> {
    let mut result: Vec<Vec<RtSpan<'static>>> = Vec::new();
    let mut current_line: Vec<RtSpan<'static>> = Vec::new();
    let mut col: usize = 0;

    for span in spans {
        let style = span.style;
        let text = span.content.as_ref();
        let mut remaining = text;

        while !remaining.is_empty() {
            let mut byte_end = 0;
            let mut chars_col = 0;

            for ch in remaining.chars() {
                let w = ch.width().unwrap_or(if ch == '\t' { TAB_WIDTH } else { 0 });
                if col + chars_col + w > max_cols {
                    break;  // 需要换行
                }
                byte_end += ch.len_utf8();
                chars_col += w;
            }
            // ...
        }
    }
}
```

## 关键代码路径与文件引用

### 渲染流程（80x24 特定）
```rust
#[test]
fn ui_snapshot_diff_gallery_80x24() {
    snapshot_diff_gallery("diff_gallery_80x24", 80, 24);
}

fn snapshot_diff_gallery(name: &str, width: u16, height: u16) {
    let lines = create_diff_summary(
        &diff_gallery_changes(),
        &PathBuf::from("/"),
        usize::from(width),  // 80
    );
    snapshot_lines(name, lines, width, height);  // 80, 24
}
```

### 关键尺寸常量
```rust
// TAB 宽度
const TAB_WIDTH: usize = 4;

// 颜色定义（与尺寸无关，但影响视觉效果）
const DARK_TC_ADD_LINE_BG_RGB: (u8, u8, u8) = (33, 58, 43);    // #213A2B
const DARK_TC_DEL_LINE_BG_RGB: (u8, u8, u8) = (74, 34, 29);    // #4A221D
const LIGHT_TC_ADD_LINE_BG_RGB: (u8, u8, u8) = (218, 251, 225); // #dafbe1
const LIGHT_TC_DEL_LINE_BG_RGB: (u8, u8, u8) = (255, 235, 233); // #ffebe9
```

### 测试辅助函数
```rust
fn snapshot_lines(name: &str, lines: Vec<RtLine<'static>>, width: u16, height: u16) {
    let mut terminal = Terminal::new(TestBackend::new(width, height)).expect("terminal");
    terminal
        .draw(|f| {
            Paragraph::new(Text::from(lines))
                .wrap(Wrap { trim: false })
                .render_ref(f.area(), f.buffer_mut())
        })
        .expect("draw");
    assert_snapshot!(name, terminal.backend());
}
```

## 依赖与外部交互

### 终端尺寸检测
虽然测试使用固定尺寸，但生产代码需要检测终端尺寸：
```rust
use ratatui::layout::Rect;

// 在实际渲染中获取可用区域
fn render(&self, area: Rect, buf: &mut Buffer) {
    let width = area.width as usize;
    // ...
}
```

### 响应式处理
```rust
impl Renderable for FileChange {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        let mut lines = vec![];
        render_change(self, &mut lines, area.width as usize, /*lang*/ None);
        Paragraph::new(lines).render(area, buf);
    }

    fn desired_height(&self, width: u16) -> u16 {
        let mut lines = vec![];
        render_change(self, &mut lines, width as usize, /*lang*/ None);
        lines.len() as u16
    }
}
```

### 尺寸相关依赖
| 组件 | 用途 |
|-----|------|
| `ratatui::backend::TestBackend` | 测试用的固定尺寸后端 |
| `ratatui::layout::Rect` | 定义渲染区域 |
| `ratatui::Terminal` | 终端抽象，管理缓冲区 |

## 风险、边界与改进建议

### 已知风险

#### 1. 最小宽度限制
- **问题**：当终端宽度小于约 40 列时，行号 + 内容可能无法合理显示
- **当前行为**：`max_cols.saturating_sub(...).max(1)` 确保至少 1 列
- **建议**：添加最小宽度警告或切换到紧凑模式

```rust
// 建议添加
const MIN_RECOMMENDED_WIDTH: usize = 60;

if width < MIN_RECOMMENDED_WIDTH {
    eprintln!("Warning: Terminal width {} is narrow, some content may be wrapped", width);
}
```

#### 2. 高度限制
- **问题**：24 行高度可能无法显示所有文件变更
- **当前行为**：超出部分被截断（由 TestBackend 控制）
- **建议**：添加滚动指示器或分页支持

### 边界条件测试

| 条件 | 80x24 行为 | 建议 |
|-----|-----------|------|
| 宽度 = 80 | 标准布局 | ✅ 基准测试 |
| 宽度 < 40 | 行号可能占大部分空间 | ⚠️ 添加紧凑模式 |
| 高度 < 10 | 只能显示1-2个文件 | ⚠️ 添加分页 |
| 超长文件名 | 可能与其他元素冲突 | ✅ 当前已处理 |

### 改进建议

#### 1. 自适应缩进
```rust
fn get_indent_for_width(width: usize) -> usize {
    match width {
        0..=60 => 2,   // 超窄：最小缩进
        61..=100 => 4, // 标准：4空格缩进
        _ => 4,        // 宽屏：保持4空格
    }
}
```

#### 2. 紧凑模式（窄终端）
```rust
enum DisplayMode {
    Normal,   // 标准显示
    Compact,  // 窄终端：减少缩进、简化头部
}

fn render_changes_block(rows: Vec<Row>, wrap_cols: usize, mode: DisplayMode) {
    let indent = match mode {
        DisplayMode::Normal => "    ",
        DisplayMode::Compact => "  ",
    };
    // ...
}
```

#### 3. 文件名截断策略
```rust
fn truncate_path_for_width(path: &str, max_width: usize) -> String {
    if path.len() <= max_width {
        path.to_string()
    } else {
        format!("...{}", &path[path.len() - max_width + 3..])
    }
}
```

### 测试矩阵建议

当前只有 3 个固定尺寸测试：
- 80x24（标准）
- 94x35（中等）
- 120x40（大屏）

建议添加：
- 40x20（超窄，边界测试）
- 200x50（超宽，性能测试）
- 80x10（矮窗口，滚动测试）

### 调试技巧
```rust
// 打印实际使用的宽度分配
#[cfg(debug_assertions)]
eprintln!("Total width: {}", width);
eprintln!("Gutter width: {}", gutter_width);
eprintln!("Content width: {}", available_content_cols);
```
