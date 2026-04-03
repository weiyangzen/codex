# 研究文档：web_search_history_cell_transcript_snapshot.snap

## 场景与职责

此快照测试验证网页搜索历史记录单元格在转录视图（transcript view）中的显示效果。转录视图通常用于 `Ctrl+T` 快捷键打开的历史记录覆盖层。

## 功能点目的

1. **转录视图支持**：确保搜索记录在转录视图中正确显示
2. **一致性**：主视图和转录视图的显示保持一致
3. **简洁性**：转录视图通常更简洁

## 具体技术实现

### 与主视图的区别

```rust
// 主视图 (display_lines)
• Searched example search query with several generic words to
  exercise wrapping

// 转录视图 (transcript_lines) - 本快照
• Searched example search query with several generic words to
  exercise wrapping
```

在本例中，主视图和转录视图的显示相同，但对于某些单元格类型（如 ExecCell），转录视图可能有不同的格式。

### 转录视图实现

```rust
impl HistoryCell for WebSearchCell {
    fn transcript_lines(&self, width: u16) -> Vec<Line<'static>> {
        // 默认实现直接调用 display_lines
        self.display_lines(width)
    }
}
```

## 关键代码路径与文件引用

1. **转录视图**：
   - `codex-rs/tui/src/history_cell.rs` - `transcript_lines` 方法
   - `codex-rs/tui/src/chatwidget.rs` - 转录覆盖层

2. **覆盖层实现**：
   - `codex-rs/tui/src/pager_overlay.rs`

## 依赖与外部交互

### 转录相关
- `HistoryCell::transcript_animation_tick` - 转录动画

## 风险、边界与改进建议

### 潜在风险
1. **缓存不一致**：转录视图可能使用缓存，需要确保缓存更新
2. **宽度差异**：转录视图可能有不同的宽度

### 改进建议
1. 在转录视图中添加搜索时间戳
2. 支持点击搜索查询跳转到详细视图
3. 添加搜索结果摘要
