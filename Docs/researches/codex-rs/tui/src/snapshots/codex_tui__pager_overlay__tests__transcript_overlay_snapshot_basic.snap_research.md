# Transcript Overlay 基础快照研究文档

## 场景与职责

该快照测试验证 **TranscriptOverlay** 组件的基础渲染功能，展示在没有 Live Tail（实时尾部）的情况下，纯已提交历史记录的渲染效果。这是 TranscriptOverlay 最基本的使用场景。

### 核心职责
- 渲染静态的、已完成的对话历史记录
- 提供分页浏览和导航功能
- 显示当前滚动进度百分比
- 提供键盘快捷键提示

## 功能点目的

### 1. 基础历史记录展示
- 显示所有已完成的对话单元（HistoryCell）
- 每个单元之间保持适当的视觉间距
- 支持长文本的自动换行

### 2. 分页导航界面
- 底部状态栏显示滚动进度（100% 表示已滚动到底部）
- 提供直观的键盘快捷键提示
- 支持多种导航方式（行级、页级、跳转）

### 3. 视觉设计
- 标题使用 `/ ` 重复填充的视觉效果
- 空行使用 `~` 符号填充（类似 vim）
- 分隔线使用 `─` 字符

## 具体技术实现

### 关键数据结构

```rust
pub(crate) struct TranscriptOverlay {
    view: PagerView,                                    // 分页视图
    cells: Vec<Arc<dyn HistoryCell>>,                  // 历史记录单元
    highlight_cell: Option<usize>,                     // 高亮单元
    live_tail_key: Option<LiveTailKey>,               // Live Tail 缓存键（本测试中为 None）
    is_done: bool,
}

struct PagerView {
    renderables: Vec<Box<dyn Renderable>>,            // 可渲染对象列表
    scroll_offset: usize,                              // 滚动偏移（初始为 usize::MAX）
    title: String,                                     // 标题
    last_content_height: Option<usize>,               // 上次内容高度
    last_rendered_height: Option<usize>,              // 上次渲染高度
}
```

### 初始化流程

```rust
pub(crate) fn new(transcript_cells: Vec<Arc<dyn HistoryCell>>) -> Self {
    Self {
        view: PagerView::new(
            Self::render_cells(&transcript_cells, /*highlight_cell*/ None),
            "T R A N S C R I P T".to_string(),
            usize::MAX,  // 初始滚动到底部
        ),
        cells: transcript_cells,
        highlight_cell: None,
        live_tail_key: None,
        is_done: false,
    }
}
```

### 单元渲染流程

```rust
fn render_cells(
    cells: &[Arc<dyn HistoryCell>],
    highlight_cell: Option<usize>,
) -> Vec<Box<dyn Renderable>> {
    cells
        .iter()
        .enumerate()
        .flat_map(|(i, c)| {
            let mut v: Vec<Box<dyn Renderable>> = Vec::new();
            
            // 创建单元渲染器，应用样式
            let mut cell_renderable = if c.as_any().is::<UserHistoryCell>() {
                Box::new(CachedRenderable::new(CellRenderable {
                    cell: c.clone(),
                    style: if highlight_cell == Some(i) {
                        user_message_style().reversed()
                    } else {
                        user_message_style()
                    },
                })) as Box<dyn Renderable>
            } else {
                Box::new(CachedRenderable::new(CellRenderable {
                    cell: c.clone(),
                    style: Style::default(),
                })) as Box<dyn Renderable>
            };
            
            // 非流式续接且非第一个单元时，添加上边距
            if !c.is_stream_continuation() && i > 0 {
                cell_renderable = Box::new(InsetRenderable::new(
                    cell_renderable,
                    Insets::tlbr(/*top*/ 1, /*left*/ 0, /*bottom*/ 0, /*right*/ 0),
                ));
            }
            v.push(cell_renderable);
            v
        })
        .collect()
}
```

### 测试用例分析

```rust
#[test]
fn transcript_overlay_snapshot_basic() {
    // 1. 创建三个测试单元
    let mut overlay = TranscriptOverlay::new(vec![
        Arc::new(TestCell {
            lines: vec![Line::from("alpha")],
        }),
        Arc::new(TestCell {
            lines: vec![Line::from("beta")],
        }),
        Arc::new(TestCell {
            lines: vec![Line::from("gamma")],
        }),
    ]);
    
    // 2. 使用 40x10 的测试终端渲染
    let mut term = Terminal::new(TestBackend::new(40, 10)).expect("term");
    term.draw(|f| overlay.render(f.area(), f.buffer_mut()))
        .expect("draw");
    assert_snapshot!(term.backend());
}
```

### 快照输出解析

```
"/ T R A N S C R I P T / / / / / / / / / "  // 标题行（40字符宽）
"alpha                                   "  // 第一个单元（alpha）
"                                        "  // 间距（单元间空行）
"beta                                    "  // 第二个单元（beta）
"                                        "  // 间距
"gamma                                   "  // 第三个单元（gamma）
"───────────────────────────────── 100% ─"  // 分隔线 + 进度（100%）
" ↑/↓ to scroll   pgup/pgdn to page   hom"  // 快捷键提示（第一行）
" q to quit   esc to edit prev           "  // 快捷键提示（第二行）
"                                        "  // 空行
```

### 滚动进度计算

```rust
fn render_bottom_bar(&self, ..., total_len: usize) {
    let percent = if total_len == 0 {
        100
    } else {
        let max_scroll = total_len.saturating_sub(content_area.height as usize);
        if max_scroll == 0 {
            100
        } else {
            (((self.scroll_offset.min(max_scroll)) as f32 / max_scroll as f32) * 100.0).round() as u8
        }
    };
    // 渲染: "───────────────────────────────── 100% ─"
}
```

## 关键代码路径与文件引用

### 核心文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/pager_overlay.rs` | TranscriptOverlay 和 PagerView 实现 |

### 关键函数

1. **初始化**
   - `TranscriptOverlay::new()` (line 457-469)
   - `PagerView::new()` (line 146-155)

2. **单元渲染**
   - `TranscriptOverlay::render_cells()` (line 471-507)
   - `CellRenderable::render()` (line 410-421)

3. **主渲染**
   - `TranscriptOverlay::render()` (line 684-690)
   - `PagerView::render()` (line 164-183)
   - `PagerView::render_header()` (line 185-191)
   - `PagerView::render_content()` (line 193-227)
   - `PagerView::render_bottom_bar()` (line 229-259)

4. **提示渲染**
   - `TranscriptOverlay::render_hints()` (line 668-682)
   - `render_key_hints()` (line 114-132)

### 快捷键定义

```rust
const PAGER_KEY_HINTS: &[(&[KeyBinding], &str)] = &[
    (&[KEY_UP, KEY_DOWN], "to scroll"),
    (&[KEY_PAGE_UP, KEY_PAGE_DOWN], "to page"),
    (&[KEY_HOME, KEY_END], "to jump"),
];

// 在 render_hints 中
let mut pairs: Vec<(&[KeyBinding], &str)> = vec![(&[KEY_Q], "to quit")];
if self.highlight_cell.is_some() {
    pairs.push((&[KEY_ESC, KEY_LEFT], "to edit prev"));
    pairs.push((&[KEY_RIGHT], "to edit next"));
    pairs.push((&[KEY_ENTER], "to edit message"));
} else {
    pairs.push((&[KEY_ESC], "to edit prev"));
}
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `ratatui` | 终端 UI 框架，提供 `Terminal`, `TestBackend`, `Buffer`, `Rect` 等 |
| `insta` | 快照测试 |
| `crossterm` | 键盘事件定义（`KeyCode`, `KeyEvent`） |

### 内部模块依赖

```
pager_overlay.rs
├── history_cell.rs (HistoryCell trait)
│   ├── transcript_lines() - 获取单元文本行
│   ├── desired_transcript_height() - 获取单元高度
│   └── is_stream_continuation() - 是否流式续接
├── render/
│   ├── renderable.rs (Renderable trait)
│   └── insets.rs (InsetRenderable, Insets)
├── style.rs (user_message_style)
├── key_hint.rs (KeyBinding, 快捷键提示)
└── tui.rs (Tui, TuiEvent)
```

### TestCell 测试桩

```rust
#[derive(Debug)]
struct TestCell {
    lines: Vec<Line<'static>>,
}

impl HistoryCell for TestCell {
    fn display_lines(&self, _width: u16) -> Vec<Line<'static>> {
        self.lines.clone()
    }
    fn transcript_lines(&self, _width: u16) -> Vec<Line<'static>> {
        self.lines.clone()
    }
}
```

## 风险、边界与改进建议

### 潜在风险

1. **初始滚动位置**
   - 使用 `usize::MAX` 作为"底部"标记，依赖 `saturating_sub` 处理
   - 如果内容高度计算有误，可能导致显示异常

2. **间距计算**
   - 单元间间距通过 `InsetRenderable` 实现
   - 第一个单元和流式续接单元的间距处理容易出错

3. **高度缓存**
   - `CachedRenderable` 缓存高度，但宽度变化时可能失效
   - 当前实现检查 `last_width`，但并发修改可能有风险

### 边界情况

1. **空内容**
   - `total_len == 0` 时，进度显示 100%
   - 空行使用 `~` 填充（vim 风格）

2. **单行内容**
   - 当 `max_scroll == 0`（内容高度 <= 视口高度），进度显示 100%

3. **高亮单元**
   - 本测试未测试高亮功能（`highlight_cell: None`）
   - 高亮时用户消息使用反转样式（`reversed()`）

### 改进建议

1. **可配置初始位置**
   - 当前固定初始滚动到底部
   - 建议支持配置初始位置（顶部、底部、特定单元）

2. **进度显示优化**
   - 当前仅显示百分比
   - 建议增加 "行号/总行数" 或 "已看/未看" 指示

3. **搜索高亮**
   - 当前 `highlight_cell` 仅用于编辑功能
   - 建议支持搜索结果高亮

4. **单元折叠**
   - 长对话历史可支持单元折叠/展开
   - 减少滚动负担

5. **测试覆盖**
   - 增加空内容测试
   - 增加单行内容测试
   - 增加高亮单元测试
   - 增加流式续接测试
