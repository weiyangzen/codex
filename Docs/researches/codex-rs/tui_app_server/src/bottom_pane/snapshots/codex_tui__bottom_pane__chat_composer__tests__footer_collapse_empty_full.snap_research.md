# Chat Composer Footer Collapse Empty Full Snapshot 研究文档

## 场景与职责

该快照文件测试了聊天编辑器底部栏（footer）在**空输入状态下的完整显示模式**。展示了当终端宽度充足时，footer 显示完整提示信息的状态。

### 业务场景
- 编辑器为空，终端宽度充足（120字符）
- 显示完整的快捷操作提示和上下文信息
- 测试 footer 布局在充足空间下的渲染

## 功能点目的

### 核心功能
1. **完整提示显示**：显示 "? for shortcuts"
2. **上下文指示**：显示 "100% context left"
3. **布局适应**：在充足宽度下左右对齐显示

### UI 设计特点
- 左侧：快捷操作提示
- 右侧：上下文剩余百分比
- 中间：充足间距

## 具体技术实现

### Footer 布局计算
```rust
pub(crate) fn single_line_footer_layout(
    area: Rect,
    context_width: u16,
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    show_cycle_hint: bool,
    show_shortcuts_hint: bool,
    show_queue_hint: bool,
) -> (SummaryLeft, bool) {
    // 计算左侧内容和右侧上下文是否可以同时显示
}
```

### 宽度计算
```rust
pub(crate) fn can_show_left_with_context(area: Rect, left_width: u16, context_width: u16) -> bool {
    let Some(context_x) = right_aligned_x(area, context_width) else {
        return true;
    };
    if left_width == 0 {
        return true;
    }
    let left_extent = FOOTER_INDENT_COLS as u16 + left_width + FOOTER_CONTEXT_GAP_COLS;
    left_extent <= context_x.saturating_sub(area.x)
}
```

## 关键代码路径

### 主要源文件
- `codex-rs/tui/src/bottom_pane/footer.rs`
- `codex-rs/tui/src/bottom_pane/chat_composer.rs`

### 相关测试
- `footer_collapse_empty_full` - 本快照（宽度120）
- `footer_collapse_empty_mode_cycle_with_context` - 中等宽度（60）
- `footer_collapse_empty_mode_cycle_without_context` - 窄宽度（44）
- `footer_collapse_empty_mode_only` - 最窄宽度（26）
