# 研究文档：static_overlay_snapshot_basic.snap

## 场景与职责

此快照测试验证静态内容覆盖层的基本显示效果。覆盖层用于显示静态内容（如帮助信息、版本信息等）。

## 功能点目的

1. **静态内容展示**：显示不随时间变化的内容
2. **全屏覆盖**：覆盖整个终端界面
3. **导航支持**：支持滚动和分页导航

## 具体技术实现

### 快照输出分析

```
"/ S T A T I C / / / / / / / / / / / / / "
"one                                     "
"two                                     "
"three                                   "
"~                                       "
"~                                       "
"───────────────────────────────── 100% ─"
" ↑/↓ to scroll   pgup/pgdn to page   hom"
" q to quit                              "
"                                        "
```

界面元素：
- 标题栏：`/ S T A T I C /`（带空格填充）
- 内容区：显示静态文本
- `~`：表示空行（类似 vim）
- 进度条：`100%` 表示已到达底部
- 快捷键提示：滚动和退出操作

### 覆盖层实现

```rust
// codex-rs/tui/src/pager_overlay.rs
pub struct StaticOverlay {
    content: Vec<String>,
    scroll_offset: usize,
}

impl StaticOverlay {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        // 渲染标题
        // 渲染内容（考虑滚动偏移）
        // 渲染底部状态栏
    }
}
```

## 关键代码路径与文件引用

1. **覆盖层实现**：
   - `codex-rs/tui/src/pager_overlay.rs`
   - `codex-rs/tui_app_server/src/pager_overlay.rs`

2. **相关组件**：
   - `ratatui::widgets::Paragraph` - 文本渲染
   - `ratatui::widgets::Wrap` - 文本换行

## 依赖与外部交互

### UI 依赖
- `ratatui::backend::TestBackend` - 测试后端
- `crossterm::event` - 键盘事件

## 风险、边界与改进建议

### 潜在风险
1. **内容过长**：超出屏幕的内容需要滚动
2. **宽度不足**：窄终端可能导致显示问题

### 边界情况
1. 空内容
2. 内容正好一屏
3. 终端尺寸变化

### 改进建议
1. 添加搜索功能
2. 支持内容复制
3. 添加行号显示
4. 支持语法高亮
