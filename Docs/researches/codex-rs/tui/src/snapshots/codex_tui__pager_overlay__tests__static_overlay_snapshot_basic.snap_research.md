# 静态分页覆盖层基础快照研究文档

## 场景与职责

该快照文件记录了 `codex-rs/tui` 项目中**静态分页覆盖层（Static Overlay）**的基础渲染结果。静态覆盖层是一种在备用屏幕（alternate screen）中显示静态内容的 UI 组件，支持滚动浏览、分页导航和键盘快捷键操作。它用于显示帮助文档、日志输出、配置信息等不需要实时更新的内容。

**核心职责：**
- 在备用屏幕中显示静态文本内容
- 提供分页滚动功能（行滚动、页滚动、跳转到首尾）
- 显示滚动进度百分比
- 提供键盘导航和退出功能

## 功能点目的

### 1. 内容展示
- **标题栏**：显示 `/ S T A T I C /` 标题，使用重复斜杠填充
- **内容区域**：显示多行静态文本
- **进度指示**：底部显示滚动百分比（如 "100%"）
- **填充符号**：未使用区域显示 `~` 符号（类似 Vim）

### 2. 导航功能
- **行滚动**：↑/↓ 或 k/j 逐行滚动
- **页滚动**：PageUp/PageDown 或 Space/Shift+Space 翻页
- **跳转**：Home/End 跳转到开头/结尾
- **半页滚动**：Ctrl+D/Ctrl+U 半页滚动
- **退出**：q 键退出覆盖层

### 3. 键盘提示
- **第一行**：显示导航快捷键提示
- **第二行**：显示退出提示
- **按键可视化**：使用 `key_hint` 模块渲染按键

## 具体技术实现

### 核心数据结构

**StaticOverlay** - 静态覆盖层：
```rust
pub(crate) struct StaticOverlay {
    view: PagerView,      // 分页视图
    is_done: bool,        // 是否完成（退出）
}
```

**PagerView** - 分页视图：
```rust
struct PagerView {
    renderables: Vec<Box<dyn Renderable>>,  // 可渲染内容
    scroll_offset: usize,                   // 滚动偏移量
    title: String,                          // 标题
    last_content_height: Option<usize>,     // 上次内容高度
    last_rendered_height: Option<usize>,    // 上次渲染高度
    pending_scroll_chunk: Option<usize>,    // 待滚动到的块
}
```

### 创建静态覆盖层

```rust
impl StaticOverlay {
    pub(crate) fn with_title(lines: Vec<Line<'static>>, title: String) -> Self {
        let paragraph = Paragraph::new(Text::from(lines)).wrap(Wrap { trim: false });
        Self::with_renderables(vec![Box::new(CachedRenderable::new(paragraph))], title)
    }

    pub(crate) fn with_renderables(renderables: Vec<Box<dyn Renderable>>, title: String) -> Self {
        Self {
            view: PagerView::new(renderables, title, /*scroll_offset*/ 0),
            is_done: false,
        }
    }
}
```

### 渲染流程

```rust
impl StaticOverlay {
    pub(crate) fn render(&mut self, area: Rect, buf: &mut Buffer) {
        // 分割区域：内容区 + 底部提示区
        let top_h = area.height.saturating_sub(3);
        let top = Rect::new(area.x, area.y, area.width, top_h);
        let bottom = Rect::new(area.x, area.y + top_h, area.width, 3);
        
        self.view.render(top, buf);      // 渲染内容
        self.render_hints(bottom, buf);  // 渲染提示
    }

    fn render_hints(&self, area: Rect, buf: &mut Buffer) {
        let line1 = Rect::new(area.x, area.y, area.width, 1);
        let line2 = Rect::new(area.x, area.y.saturating_add(1), area.width, 1);
        render_key_hints(line1, buf, PAGER_KEY_HINTS);
        let pairs: Vec<(&[KeyBinding], &str)> = vec![(&[KEY_Q], "to quit")];
        render_key_hints(line2, buf, &pairs);
    }
}
```

### 分页视图渲染

```rust
impl PagerView {
    fn render(&mut self, area: Rect, buf: &mut Buffer) {
        Clear.render(area, buf);           // 清空区域
        self.render_header(area, buf);     // 渲染标题
        let content_area = self.content_area(area);
        self.update_last_content_height(content_area.height);
        let content_height = self.content_height(content_area.width);
        self.last_rendered_height = Some(content_height);
        
        // 处理待滚动请求
        if let Some(idx) = self.pending_scroll_chunk.take() {
            self.ensure_chunk_visible(idx, content_area);
        }
        
        // 限制滚动范围
        self.scroll_offset = self
            .scroll_offset
            .min(content_height.saturating_sub(content_area.height as usize));

        self.render_content(content_area, buf);     // 渲染内容
        self.render_bottom_bar(area, content_area, buf, content_height);  // 渲染底部栏
    }

    fn render_header(&self, area: Rect, buf: &mut Buffer) {
        // 使用重复的 "/ " 填充标题行
        Span::from("/ ".repeat(area.width as usize / 2))
            .dim()
            .render_ref(area, buf);
        let header = format!("/ {}", self.title);
        header.dim().render_ref(area, buf);
    }
}
```

### 键盘事件处理

```rust
impl PagerView {
    fn handle_key_event(&mut self, tui: &mut tui::Tui, key_event: KeyEvent) -> Result<()> {
        match key_event {
            e if KEY_UP.is_press(e) || KEY_K.is_press(e) => {
                self.scroll_offset = self.scroll_offset.saturating_sub(1);
            }
            e if KEY_DOWN.is_press(e) || KEY_J.is_press(e) => {
                self.scroll_offset = self.scroll_offset.saturating_add(1);
            }
            e if KEY_PAGE_UP.is_press(e) || KEY_SHIFT_SPACE.is_press(e) || KEY_CTRL_B.is_press(e) => {
                let page_height = self.page_height(tui.terminal.viewport_area);
                self.scroll_offset = self.scroll_offset.saturating_sub(page_height);
            }
            e if KEY_PAGE_DOWN.is_press(e) || KEY_SPACE.is_press(e) || KEY_CTRL_F.is_press(e) => {
                let page_height = self.page_height(tui.terminal.viewport_area);
                self.scroll_offset = self.scroll_offset.saturating_add(page_height);
            }
            e if KEY_CTRL_D.is_press(e) => {
                let area = self.content_area(tui.terminal.viewport_area);
                let half_page = (area.height as usize).saturating_add(1) / 2;
                self.scroll_offset = self.scroll_offset.saturating_add(half_page);
            }
            e if KEY_CTRL_U.is_press(e) => {
                let area = self.content_area(tui.terminal.viewport_area);
                let half_page = (area.height as usize).saturating_add(1) / 2;
                self.scroll_offset = self.scroll_offset.saturating_sub(half_page);
            }
            e if KEY_HOME.is_press(e) => {
                self.scroll_offset = 0;
            }
            e if KEY_END.is_press(e) => {
                self.scroll_offset = usize::MAX;
            }
            _ => {
                return Ok(());
            }
        }
        tui.frame_requester().schedule_frame_in(crate::tui::TARGET_FRAME_INTERVAL);
        Ok(())
    }
}
```

### 快捷键常量定义

```rust
const KEY_UP: KeyBinding = key_hint::plain(KeyCode::Up);
const KEY_DOWN: KeyBinding = key_hint::plain(KeyCode::Down);
const KEY_K: KeyBinding = key_hint::plain(KeyCode::Char('k'));
const KEY_J: KeyBinding = key_hint::plain(KeyCode::Char('j'));
const KEY_PAGE_UP: KeyBinding = key_hint::plain(KeyCode::PageUp);
const KEY_PAGE_DOWN: KeyBinding = key_hint::plain(KeyCode::PageDown);
const KEY_SPACE: KeyBinding = key_hint::plain(KeyCode::Char(' '));
const KEY_SHIFT_SPACE: KeyBinding = key_hint::shift(KeyCode::Char(' '));
const KEY_HOME: KeyBinding = key_hint::plain(KeyCode::Home);
const KEY_END: KeyBinding = key_hint::plain(KeyCode::End);
const KEY_CTRL_F: KeyBinding = key_hint::ctrl(KeyCode::Char('f'));
const KEY_CTRL_D: KeyBinding = key_hint::ctrl(KeyCode::Char('d'));
const KEY_CTRL_B: KeyBinding = key_hint::ctrl(KeyCode::Char('b'));
const KEY_CTRL_U: KeyBinding = key_hint::ctrl(KeyCode::Char('u'));
const KEY_Q: KeyBinding = key_hint::plain(KeyCode::Char('q'));
```

## 关键代码路径与文件引用

### 主要源文件

| 文件路径 | 职责 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/tui/src/pager_overlay.rs` | 分页覆盖层的完整实现 |

### 关键函数路径

```
pager_overlay.rs:1093
└── fn static_overlay_snapshot_basic()  [测试函数]
    ├── StaticOverlay::with_title(
    │       vec!["one".into(), "two".into(), "three".into()],
    │       "S T A T I C".to_string()
    │   )  [line 728]
    │   └── PagerView::new(renderables, title, 0)  [line 734]
    ├── term.draw(|f| overlay.render(f.area(), f.buffer_mut()))  [line 1101]
    │   └── StaticOverlay::render(area, buf)  [line 748]
    │       ├── PagerView::render(top, buf)  [line 752]
    │       │   ├── render_header()  [line 185]
    │       │   ├── render_content()  [line 193]
    │       │   └── render_bottom_bar()  [line 229]
    │       └── render_hints(bottom, buf)  [line 740]
    └── assert_snapshot!(term.backend())  [line 1103]
```

### 测试配置

```rust
#[test]
fn static_overlay_snapshot_basic() {
    let mut overlay = StaticOverlay::with_title(
        vec!["one".into(), "two".into(), "three".into()],
        "S T A T I C".to_string(),
    );
    let mut term = Terminal::new(TestBackend::new(40, 10)).expect("term");
    term.draw(|f| overlay.render(f.area(), f.buffer_mut()))
        .expect("draw");
    assert_snapshot!(term.backend());
}
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `ratatui` | 终端 UI 渲染框架 |
| `crossterm` | 键盘事件处理 |

### 内部模块交互

```
pager_overlay.rs
├── chatwidget::ActiveCellTranscriptKey  [转录键]
├── history_cell::{HistoryCell, UserHistoryCell}  [历史单元格]
├── key_hint::{KeyBinding, plain, shift, ctrl}  [按键提示]
├── render::{Insets, renderable::*}  [渲染工具]
├── style::user_message_style  [用户消息样式]
└── tui::{Tui, TuiEvent}  [TUI 核心]
```

### 与 TranscriptOverlay 的对比

| 特性 | StaticOverlay | TranscriptOverlay |
|-----|---------------|-------------------|
| 内容类型 | 静态文本 | 动态历史单元格 |
| 实时更新 | 否 | 是（Live Tail）|
| 标题 | 可自定义 | 固定 "T R A N S C R I P T" |
| 编辑功能 | 无 | 支持（edit prev/next）|
| 使用场景 | 帮助文档、日志 | 会话历史 |

## 风险、边界与改进建议

### 已知风险

1. **内容溢出**
   - 单行内容超过终端宽度时可能显示不正确
   - 风险：长行被截断或换行异常
   - 缓解：使用 `Wrap { trim: false }` 进行自动换行

2. **滚动位置丢失**
   - 终端尺寸变化时，滚动偏移量可能需要调整
   - 风险：用户可能丢失阅读位置
   - 建议：监听尺寸变化事件，智能调整滚动位置

3. **快捷键冲突**
   - `q` 键用于退出，可能与内容搜索冲突
   - 风险：用户无法输入字母 q
   - 缓解：仅在覆盖层激活时捕获 q 键

### 边界情况

1. **空内容**
   - 当 `renderables` 为空时的行为
   - 当前：显示空内容和 100% 进度

2. **单行内容**
   - 内容高度小于视口高度
   - 当前：显示 100% 进度

3. **极长内容**
   - 内容高度超过 `usize::MAX`
   - 风险：溢出 panic
   - 当前：未明确处理

4. **终端尺寸变化**
   - 渲染过程中终端大小改变
   - 当前：下次渲染时适应新尺寸

### 改进建议

1. **搜索功能**
   - 添加 `/` 搜索功能（类似 Vim/less）
   - 支持 `n`/`N` 跳转到下一个/上一个匹配

2. **行号显示**
   - 可选显示行号
   - 便于引用特定行

3. **语法高亮**
   - 对于代码内容，支持语法高亮
   - 使用与 Markdown 渲染相同的语法高亮器

4. **书签功能**
   - 允许用户设置书签
   - 支持跳转到书签

5. **复制功能**
   - 支持选择并复制文本
   - 集成系统剪贴板

6. **进度条增强**
   - 添加可视化进度条
   - 显示当前行号/总行数

7. **鼠标支持**
   - 支持鼠标滚轮滚动
   - 支持点击跳转

8. **多缓冲区**
   - 支持在多个静态内容间切换
   - 类似 Vim 的 buffer 列表
