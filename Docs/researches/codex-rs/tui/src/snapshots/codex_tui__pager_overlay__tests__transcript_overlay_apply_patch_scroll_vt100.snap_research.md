# Transcript Overlay Apply Patch Scroll VT100 研究文档

## 场景与职责

该快照测试验证 **TranscriptOverlay** 组件在处理包含 Patch（代码补丁）操作的历史记录时的渲染行为，特别是 VT100 终端的滚动清除机制。这是 TUI（终端用户界面）中用于查看完整对话历史的核心组件，通过 `Ctrl+T` 快捷键触发。

### 核心职责
- 渲染完整的对话历史记录（transcript），包括用户消息和系统响应
- 支持代码补丁（Patch）的可视化展示，显示文件变更（添加/删除行）
- 处理 VT100 终端的滚动和清屏行为，确保内容正确显示
- 提供分页浏览功能，支持键盘导航

## 功能点目的

### 1. Patch 可视化展示
- 显示文件变更摘要：`• Added foo.txt (+2 -0)`
- 展示具体的代码变更内容，使用 `+` 前缀标识新增行
- 支持多文件 Patch 的连续展示

### 2. VT100 滚动清除
- 测试验证在滚动操作后，前一页的内容被正确清除
- 防止终端缓冲区残留导致的显示混乱

### 3. 分页导航
- 底部状态栏显示当前滚动进度（0% 表示在顶部）
- 提供键盘快捷键提示（↑/↓ 滚动、pgup/pgdn 翻页、home/end 跳转）

## 具体技术实现

### 关键数据结构

```rust
// TranscriptOverlay 结构
pub(crate) struct TranscriptOverlay {
    view: PagerView,                                    // 分页视图状态
    cells: Vec<Arc<dyn HistoryCell>>,                  // 已提交的历史记录单元
    highlight_cell: Option<usize>,                     // 高亮单元索引
    live_tail_key: Option<LiveTailKey>,               // 实时尾部缓存键
    is_done: bool,
}

// PagerView 结构
struct PagerView {
    renderables: Vec<Box<dyn Renderable>>,            // 可渲染内容列表
    scroll_offset: usize,                              // 当前滚动偏移
    title: String,                                     // 标题（"/ T R A N S C R I P T /"）
    last_content_height: Option<usize>,               // 上次渲染内容高度
    pending_scroll_chunk: Option<usize>,              // 待滚动到的块
}
```

### 关键渲染流程

1. **Patch 单元渲染** (`CellRenderable`)
   - 通过 `HistoryCell::transcript_lines()` 获取行内容
   - 使用 `Paragraph` 组件配合 `Wrap { trim: false }` 进行换行
   - Patch 内容通过 `new_patch_event` 创建，包含文件变更信息

2. **滚动偏移处理** (`render_offset_content`)
   ```rust
   fn render_offset_content(
       area: Rect,
       buf: &mut Buffer,
       renderable: &dyn Renderable,
       scroll_offset: u16,
   ) -> u16
   ```
   - 创建临时缓冲区渲染完整内容
   - 根据滚动偏移复制可见区域到目标缓冲区
   - 实现平滑的滚动体验

3. **VT100 清屏机制**
   - 每次渲染前调用 `Clear.render(area, buf)` 清除区域
   - 测试验证滚动后前一页内容被正确清除

### 测试用例分析

```rust
#[test]
fn transcript_overlay_apply_patch_scroll_vt100_clears_previous_page() {
    // 1. 创建 Patch 单元（文件添加操作）
    let approval_cell = new_patch_event(approval_changes, &cwd);
    let apply_begin_cell = new_patch_event(apply_changes, &cwd);
    
    // 2. 创建执行命令单元
    let exec_cell = new_active_exec_command(...);
    exec_cell.complete_call(...);
    
    // 3. 构建 Overlay 并渲染
    let mut overlay = TranscriptOverlay::new(cells);
    overlay.render(area, &mut buf);
    
    // 4. 滚动到顶部后再次渲染
    overlay.view.scroll_offset = 0;
    overlay.render(area, &mut buf);
    
    // 5. 验证快照：确保内容正确，无残留
}
```

## 关键代码路径与文件引用

### 核心文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/pager_overlay.rs` | TranscriptOverlay 和 PagerView 的主要实现 |
| `codex-rs/tui/src/history_cell.rs` | HistoryCell trait 和 Patch 单元实现 |
| `codex-rs/tui/src/render/renderable.rs` | Renderable trait 定义 |

### 关键函数

1. **渲染入口**
   - `TranscriptOverlay::render()` (line 684-690)
   - `PagerView::render()` (line 164-183)

2. **内容渲染**
   - `PagerView::render_content()` (line 193-227)
   - `render_offset_content()` (line 781-806)

3. **Patch 单元创建**
   - `history_cell::new_patch_event()` (在测试中调用)

4. **滚动处理**
   - `PagerView::handle_key_event()` (line 261-303)
   - 支持 ↑/↓、PgUp/PgDn、Home/End、Ctrl+F/B/D/U 等快捷键

### 快捷键定义

```rust
const KEY_UP: KeyBinding = key_hint::plain(KeyCode::Up);
const KEY_DOWN: KeyBinding = key_hint::plain(KeyCode::Down);
const KEY_PAGE_UP: KeyBinding = key_hint::plain(KeyCode::PageUp);
const KEY_PAGE_DOWN: KeyBinding = key_hint::plain(KeyCode::PageDown);
const KEY_HOME: KeyBinding = key_hint::plain(KeyCode::Home);
const KEY_END: KeyBinding = key_hint::plain(KeyCode::End);
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `ratatui` | 终端 UI 渲染框架，提供 `Buffer`, `Rect`, `Paragraph`, `Widget` 等 |
| `crossterm` | 跨平台终端事件处理（键盘输入） |
| `codex_protocol` | 协议定义，包含 `FileChange`, `ReviewDecision` 等 |

### 内部模块交互

```
pager_overlay.rs
├── history_cell.rs (HistoryCell trait, Patch 单元)
├── render/renderable.rs (Renderable trait)
├── render/insets.rs (InsetRenderable, 边距处理)
├── chatwidget.rs (ActiveCellTranscriptKey)
├── key_hint.rs (快捷键提示)
└── style.rs (样式定义)
```

### 与 App 的交互

- `App` 在 `TuiEvent::Draw` 事件中调用 `TranscriptOverlay::sync_live_tail()`
- 实时同步当前活动单元（active cell）的内容到 Overlay
- 通过 `ActiveCellTranscriptKey` 缓存优化，避免不必要的重渲染

## 风险、边界与改进建议

### 潜在风险

1. **VT100 兼容性**
   - 不同终端对清屏序列的支持可能不一致
   - 建议：增加更多终端类型的测试覆盖

2. **滚动性能**
   - 大量历史记录时，每次滚动都重新渲染可能影响性能
   - 当前使用 `CachedRenderable` 缓存高度计算，但内容仍需重新渲染

3. **内存占用**
   - `cells` 向量保存所有历史记录的 Arc 引用
   - 长时间运行的会话可能导致内存增长

### 边界情况

1. **空内容处理**
   - 当没有历史记录时，显示 "~" 填充符（line 218-226）
   - 进度百分比计算避免除以零（line 242-252）

2. **超宽内容**
   - 使用 `Wrap { trim: false }` 处理长行
   - 标题使用 `/ ` 重复填充（line 186-190）

3. **并发修改**
   - `insert_cell()` 和 `sync_live_tail()` 可能在渲染期间被调用
   - 使用 `follow_bottom` 标记保持滚动位置

### 改进建议

1. **虚拟滚动优化**
   - 对于大量历史记录，考虑只渲染可见区域
   - 预估内容高度而非全部计算

2. **搜索功能**
   - 当前仅支持浏览，建议增加内容搜索（/ 键触发）

3. **导出功能**
   - 支持将 transcript 导出为文件（如 Markdown 格式）

4. **语法高亮**
   - Patch 代码块可增加语法高亮支持

5. **测试覆盖**
   - 增加多文件 Patch 的渲染测试
   - 增加极端尺寸（极小/极大）终端的测试
