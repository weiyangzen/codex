# Transcript Overlay 基础快照测试文档

## 场景与职责

此快照文件对应 `tui/src/pager_overlay.rs` 中的 `transcript_overlay_snapshot_basic` 测试，用于验证 TranscriptOverlay 组件的基础渲染功能。TranscriptOverlay 是 TUI 应用中的一个核心覆盖层组件，用于在备用屏幕（alternate screen）中显示完整的对话历史记录，用户可通过 `Ctrl+T` 快捷键触发。

该组件的主要职责包括：
- 在独立的全屏覆盖层中展示已提交的历史对话单元（HistoryCell）
- 支持实时追加正在进行的对话内容（live tail）
- 提供分页滚动、键盘导航等交互功能
- 保持与主视图的对话历史同步

## 功能点目的

### 基础渲染验证
此测试验证 TranscriptOverlay 在包含三个简单历史单元（alpha、beta、gamma）时的基本渲染输出。测试确保：

1. **标题渲染**：顶部显示 `/ T R A N S C R I P T /` 标题，使用重复的 `/ ` 字符填充背景
2. **内容渲染**：每个历史单元的内容正确显示在独立行
3. **进度指示器**：底部显示 `───────────────────────────────── 100% ─` 样式的进度条
4. **键盘提示**：底部区域显示操作提示（`↑/↓ to scroll`、`pgup/pgdn to page`、`q to quit` 等）

### 快照内容解析
```
"/ T R A N S C R I P T / / / / / / / / / "  <- 标题行，使用 / 字符填充
"alpha                                   "  <- 第一个历史单元内容
"                                        "  <- 空行（单元间隔）
"beta                                    "  <- 第二个历史单元内容
"                                        "  <- 空行（单元间隔）
"gamma                                   "  <- 第三个历史单元内容
"───────────────────────────────── 100% ─"  <- 进度条（100% 表示已滚动到底部）
" ↑/↓ to scroll   pgup/pgdn to page   hom"  <- 键盘提示第一行（被截断）
" q to quit   esc to edit prev           "  <- 键盘提示第二行
"                                        "  <- 空行
```

## 具体技术实现

### 核心数据结构

```rust
pub(crate) struct TranscriptOverlay {
    view: PagerView,                                    // 分页视图状态
    cells: Vec<Arc<dyn HistoryCell>>,                  // 已提交的历史单元
    highlight_cell: Option<usize>,                     // 高亮单元索引
    live_tail_key: Option<LiveTailKey>,               // 实时尾部缓存键
    is_done: bool,                                     // 是否完成标志
}

struct PagerView {
    renderables: Vec<Box<dyn Renderable>>,            // 可渲染对象列表
    scroll_offset: usize,                             // 滚动偏移量
    title: String,                                    // 标题
    last_content_height: Option<usize>,              // 上次内容高度
    pending_scroll_chunk: Option<usize>,             // 待滚动到的块
}

struct LiveTailKey {
    width: u16,                                       // 终端宽度
    revision: u64,                                    // 修订版本号
    is_stream_continuation: bool,                    // 是否流式延续
    animation_tick: Option<u64>,                     // 动画帧计数
}
```

### 渲染流程

1. **初始化** (`TranscriptOverlay::new`):
   - 接收历史单元列表 `transcript_cells`
   - 构建 `PagerView`，初始滚动偏移设为 `usize::MAX`（滚动到底部）
   - 通过 `render_cells` 将 HistoryCell 转换为 CellRenderable

2. **单元渲染** (`CellRenderable`):
   - 使用 `HistoryCell::transcript_lines()` 获取文本行
   - 应用样式（UserHistoryCell 使用 `user_message_style()`）
   - 非流式延续的单元之间添加顶部间距（`InsetRenderable`）

3. **分页视图渲染** (`PagerView::render`):
   - 清空区域 (`Clear.render`)
   - 渲染标题 (`render_header`)
   - 渲染内容 (`render_content`)：根据滚动偏移量裁剪可见区域
   - 渲染底部栏 (`render_bottom_bar`)：进度条和百分比

4. **键盘提示渲染** (`render_hints`):
   - 第一行：通用分页提示（↑/↓、pgup/pgdn、home/end）
   - 第二行：操作提示（q to quit、esc to edit prev）

### 关键算法

**滚动位置计算**:
```rust
fn is_scrolled_to_bottom(&self) -> bool {
    if self.scroll_offset == usize::MAX { return true; }
    let max_scroll = total_height.saturating_sub(content_height);
    self.scroll_offset >= max_scroll
}
```

**进度百分比计算**:
```rust
let percent = if total_len == 0 { 100 } else {
    let max_scroll = total_len.saturating_sub(content_area.height as usize);
    if max_scroll == 0 { 100 } else {
        ((self.scroll_offset.min(max_scroll) as f32 / max_scroll as f32) * 100.0).round() as u8
    }
};
```

## 关键代码路径与文件引用

### 主要源文件
- `codex-rs/tui/src/pager_overlay.rs` - TranscriptOverlay 和 PagerView 的实现

### 依赖模块
- `codex-rs/tui/src/history_cell.rs` - HistoryCell trait 定义
- `codex-rs/tui/src/render/renderable.rs` - Renderable trait
- `codex-rs/tui/src/render/mod.rs` - Insets 和 InsetRenderable
- `codex-rs/tui/src/style.rs` - 样式定义（user_message_style）
- `codex-rs/tui/src/key_hint.rs` - 键盘提示渲染

### 测试代码位置
```rust
#[test]
fn transcript_overlay_snapshot_basic() {
    // 位于 codex-rs/tui/src/pager_overlay.rs:892-909
}
```

### 相关快照文件
- `codex_tui__pager_overlay__tests__transcript_overlay_snapshot_basic.snap`（当前文件）
- `codex_tui__pager_overlay__tests__transcript_overlay_renders_live_tail.snap` - 实时尾部渲染
- `codex_tui__pager_overlay__tests__transcript_overlay_apply_patch_scroll_vt100.snap` - VT100 滚动

## 依赖与外部交互

### 外部依赖
- **ratatui**: 终端 UI 渲染框架，提供 `Buffer`、`Rect`、`Paragraph`、`Widget` 等
- **crossterm**: 终端事件处理，提供 `KeyCode`、`KeyEvent`
- **std::sync::Arc**: 历史单元的引用计数共享

### 内部依赖
- **HistoryCell trait**: 定义历史单元的接口（`transcript_lines`、`desired_transcript_height`、`is_stream_continuation`）
- **Renderable trait**: 定义可渲染对象的接口（`render`、`desired_height`）
- **Tui/TuiEvent**: 终端事件循环集成

### 与 App 的交互
- `App` 在 `TuiEvent::Draw` 事件中调用 `TranscriptOverlay::render`
- `App` 通过 `sync_live_tail` 同步正在进行的对话内容
- `ActiveCellTranscriptKey` 用于缓存控制，避免不必要的重渲染

## 风险、边界与改进建议

### 潜在风险

1. **滚动偏移越界**: 
   - 风险：`usize::MAX` 作为初始值可能在某些计算中导致溢出
   - 缓解：代码中使用了 `saturating_sub` 等安全算术操作

2. **内存泄漏**:
   - 风险：`live_tail_key` 和 `renderables` 缓存可能累积
   - 现状：每次 `sync_live_tail` 都会清理旧缓存

3. **性能问题**:
   - 风险：大量历史单元时每次渲染都重新计算高度
   - 缓解：`CachedRenderable` 缓存了高度计算结果

### 边界情况

1. **空内容**: 当 `cells` 为空时，进度条应显示 100%
2. **单行内容**: 内容高度小于视口高度时，滚动条应显示 100%
3. **快速滚动**: 连续按键时，`page_height` 依赖上次的 `last_content_height`
4. **终端大小变化**: 宽度变化会触发 `LiveTailKey` 更新，重新计算换行

### 改进建议

1. **增量渲染**: 当前每次滚动都重新渲染所有可见内容，可考虑脏矩形优化
2. **搜索功能**: 类似 `less` 的 `/search` 功能，高亮匹配内容
3. **持久化滚动位置**: 关闭并重新打开 overlay 时恢复上次的滚动位置
4. **鼠标支持**: 添加鼠标滚轮和点击支持
5. **行号显示**: 可选显示行号，便于引用特定对话内容

### 测试覆盖建议

1. **大内容测试**: 超过 1000 个历史单元的性能测试
2. **Unicode 测试**: 包含宽字符（如中文、emoji）的渲染测试
3. **颜色测试**: 验证不同主题下的颜色渲染
4. **并发测试**: `sync_live_tail` 与 `insert_cell` 并发调用的测试
