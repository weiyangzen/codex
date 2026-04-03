# Transcript Overlay Live Tail 渲染研究文档

## 场景与职责

该快照测试验证 **TranscriptOverlay** 组件的 **Live Tail（实时尾部）** 功能，即在已提交的历史记录基础上，动态追加显示当前正在进行的对话内容。这是 TUI 中实现"实时查看完整对话历史"的关键特性。

### 核心职责
- 在 Overlay 中显示已提交的对话历史（committed cells）
- 实时同步当前活动单元（active cell）的进行中内容
- 通过缓存机制优化渲染性能，避免不必要的重计算
- 自动跟随（follow）新内容，保持滚动在底部

## 功能点目的

### 1. Live Tail 实时同步
- 当用户在主界面与 AI 对话时，按 `Ctrl+T` 打开 Overlay 可看到完整历史
- Live Tail 显示当前正在生成的响应内容
- 与主界面的活动单元保持同步

### 2. 缓存优化
- 使用 `LiveTailKey` 作为缓存键，包含：
  - 终端宽度（影响换行）
  - 内容修订版本（in-place 更新时变化）
  - 流式续接标志（影响间距）
  - 动画帧计数（用于 spinner/shimmer）
- 仅当缓存键变化时才重新计算 Live Tail 内容

### 3. 自动跟随行为
- 当用户滚动到底部时，新内容自动跟随
- 当用户手动滚动到上方查看历史时，保持当前位置

## 具体技术实现

### 关键数据结构

```rust
// Live Tail 缓存键
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct LiveTailKey {
    width: u16,                    // 终端宽度
    revision: u64,                 // 内容修订版本
    is_stream_continuation: bool,  // 是否流式续接
    animation_tick: Option<u64>,   // 动画帧
}

// 来自 chatwidget 的缓存键
pub struct ActiveCellTranscriptKey {
    pub revision: u64,
    pub is_stream_continuation: bool,
    pub animation_tick: Option<u64>,
}
```

### Live Tail 同步流程

```rust
pub(crate) fn sync_live_tail(
    &mut self,
    width: u16,
    active_key: Option<ActiveCellTranscriptKey>,
    compute_lines: impl FnOnce(u16) -> Option<Vec<Line<'static>>>,
) {
    // 1. 构建新的缓存键
    let next_key = active_key.map(|key| LiveTailKey {
        width,
        revision: key.revision,
        is_stream_continuation: key.is_stream_continuation,
        animation_tick: key.animation_tick,
    });

    // 2. 缓存命中，直接返回
    if self.live_tail_key == next_key {
        return;
    }

    // 3. 记录当前是否跟随底部
    let follow_bottom = self.view.is_scrolled_to_bottom();

    // 4. 移除旧的 Live Tail
    self.take_live_tail_renderable();
    self.live_tail_key = next_key;

    // 5. 计算并添加新的 Live Tail
    if let Some(key) = next_key {
        let lines = compute_lines(width).unwrap_or_default();
        if !lines.is_empty() {
            self.view.renderables.push(Self::live_tail_renderable(
                lines,
                !self.cells.is_empty(),
                key.is_stream_continuation,
            ));
        }
    }

    // 6. 恢复跟随状态
    if follow_bottom {
        self.view.scroll_offset = usize::MAX;
    }
}
```

### 渲染流程

```rust
fn live_tail_renderable(
    lines: Vec<Line<'static>>,
    has_prior_cells: bool,
    is_stream_continuation: bool,
) -> Box<dyn Renderable> {
    let paragraph = Paragraph::new(Text::from(lines)).wrap(Wrap { trim: false });
    let mut renderable: Box<dyn Renderable> = Box::new(CachedRenderable::new(paragraph));
    
    // 如果不是流式续接且前面有单元，添加上边距
    if has_prior_cells && !is_stream_continuation {
        renderable = Box::new(InsetRenderable::new(
            renderable,
            Insets::tlbr(/*top*/ 1, /*left*/ 0, /*bottom*/ 0, /*right*/ 0),
        ));
    }
    renderable
}
```

### 测试用例分析

```rust
#[test]
fn transcript_overlay_renders_live_tail() {
    // 1. 创建一个已提交单元（"alpha"）
    let mut overlay = TranscriptOverlay::new(vec![Arc::new(TestCell {
        lines: vec![Line::from("alpha")],
    })]);
    
    // 2. 同步 Live Tail（"tail"）
    overlay.sync_live_tail(
        40,  // 宽度
        Some(ActiveCellTranscriptKey {
            revision: 1,
            is_stream_continuation: false,
            animation_tick: None,
        }),
        |_| Some(vec![Line::from("tail")]),  // Live Tail 内容
    );
    
    // 3. 渲染并验证
    let mut term = Terminal::new(TestBackend::new(40, 10)).expect("term");
    term.draw(|f| overlay.render(f.area(), f.buffer_mut()))
        .expect("draw");
    assert_snapshot!(term.backend());
}
```

### 快照输出解析

```
"/ T R A N S C R I P T / / / / / / / / / "  // 标题行
"alpha                                   "  // 已提交单元内容
"                                        "  // 间距（非流式续接）
"tail                                    "  // Live Tail 内容
"~                                       "  // 空行填充
"~                                       "
"───────────────────────────────── 100% ─"  // 分隔线和进度（100% = 在底部）
" ↑/↓ to scroll   pgup/pgdn to page   hom"  // 快捷键提示
" q to quit   esc to edit prev           "
"                                        "
```

## 关键代码路径与文件引用

### 核心文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/pager_overlay.rs` | TranscriptOverlay 实现，line 423-720 |
| `codex-rs/tui/src/chatwidget.rs` | ActiveCellTranscriptKey 定义 |

### 关键函数

1. **Live Tail 同步**
   - `TranscriptOverlay::sync_live_tail()` (line 581-615)
   - `TranscriptOverlay::live_tail_renderable()` (line 650-666)
   - `TranscriptOverlay::take_live_tail_renderable()` (line 646-648)

2. **缓存键管理**
   - `LiveTailKey` 结构定义 (line 440-450)
   - 与 `ActiveCellTranscriptKey` 的映射 (line 587-592)

3. **渲染**
   - `TranscriptOverlay::render()` (line 684-690)
   - `PagerView::render()` (line 164-183)

### 相关测试

```rust
// 当前测试
fn transcript_overlay_renders_live_tail()

// 相关测试
fn transcript_overlay_sync_live_tail_is_noop_for_identical_key()  // 缓存测试
fn transcript_overlay_keeps_scroll_pinned_at_bottom()             // 跟随行为测试
fn transcript_overlay_preserves_manual_scroll_position()          // 手动滚动测试
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `ratatui` | 终端 UI 渲染，提供 `TestBackend` 用于测试 |
| `insta` | 快照测试框架 |

### 内部模块交互

```
TranscriptOverlay
├── ChatWidget (提供 ActiveCellTranscriptKey)
│   └── 在 App::draw 中调用 sync_live_tail()
├── HistoryCell (已提交单元接口)
└── Renderable (渲染抽象)
    ├── CachedRenderable (高度缓存)
    └── InsetRenderable (边距处理)
```

### App 集成流程

```rust
// 在 App::draw 中
if let Some(Overlay::Transcript(overlay)) = &mut self.overlay {
    let key = self.chat_widget.active_cell_transcript_key();
    overlay.sync_live_tail(
        area.width,
        key,
        |width| self.chat_widget.compute_active_cell_transcript_lines(width),
    );
}
```

## 风险、边界与改进建议

### 潜在风险

1. **缓存键设计**
   - 如果 `ActiveCellTranscriptKey` 的 `revision` 更新不及时，Live Tail 可能显示旧内容
   - 如果 `revision` 过于频繁更新，缓存失效导致性能下降

2. **内存管理**
   - Live Tail 内容通过闭包 `compute_lines` 动态生成
   - 大量文本时可能产生临时内存分配

3. **滚动同步**
   - `usize::MAX` 作为"滚动到底部"的标记，依赖 `saturating_sub` 处理
   - 极端情况下可能溢出（虽然不太可能）

### 边界情况

1. **空 Live Tail**
   - 当 `compute_lines` 返回 `None` 或空向量时，不添加 Live Tail
   - 代码：`if !lines.is_empty()` (line 604)

2. **无已提交单元**
   - 当 `cells` 为空时，Live Tail 不添加上边距
   - 代码：`!self.cells.is_empty()` (line 607)

3. **流式续接**
   - `is_stream_continuation = true` 时，不添加额外间距
   - 用于连续流式输出，避免视觉断裂

### 改进建议

1. **缓存性能优化**
   - 考虑使用 LRU 缓存多尺寸的 Live Tail 内容
   - 终端宽度频繁变化时（如用户调整窗口），当前会频繁重计算

2. **动画优化**
   - `animation_tick` 导致频繁重渲染
   - 可考虑将动画与内容分离，仅重绘动画部分

3. **错误处理**
   - `compute_lines` 返回 `None` 时静默忽略
   - 建议添加日志或降级显示

4. **测试增强**
   - 增加流式续接场景的测试
   - 增加动画 tick 变化的测试
   - 增加宽度变化时的缓存失效测试

5. **功能扩展**
   - 支持 Live Tail 的独立滚动（与 committed cells 分离）
   - 支持暂停 Live Tail 更新（冻结查看历史）
