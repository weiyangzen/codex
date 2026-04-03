# 研究文档：transcript_overlay_renders_live_tail.snap

## 场景与职责

此快照测试验证转录覆盖层的实时尾部（live tail）功能。当新内容不断产生时，覆盖层应该能够实时显示最新内容。

## 功能点目的

1. **实时内容显示**：显示不断产生的最新内容
2. **自动滚动**：自动滚动到最新内容
3. **手动覆盖**：用户可以手动滚动查看历史内容

## 具体技术实现

### 快照输出分析

```
"/ T R A N S C R I P T / / / / / / / / / "
"alpha                                   "
"                                        "
"tail                                    "
"~                                       "
"~                                       "
"───────────────────────────────── 100% ─"
" ↑/↓ to scroll   pgup/pgdn to page   hom"
" q to quit   esc to edit prev           "
"                                        "
```

关键观察：
- 显示 `alpha` 和 `tail` 内容
- 进度显示 `100%`（在底部）
- 空行用 `~` 填充

### 实时尾部实现

```rust
pub struct TranscriptOverlay {
    content: Vec<Line>,
    scroll_offset: usize,
    follow_tail: bool,  // 是否跟随尾部
}

impl TranscriptOverlay {
    fn update_content(&mut self, new_lines: Vec<Line>) {
        self.content.extend(new_lines);
        
        if self.follow_tail {
            // 自动滚动到底部
            self.scroll_offset = self.content.len();
        }
    }
    
    fn handle_scroll(&mut self, delta: i32) {
        // 用户手动滚动时，暂停自动跟随
        self.follow_tail = false;
        self.scroll_offset = (self.scroll_offset as i32 + delta).max(0) as usize;
    }
}
```

## 关键代码路径与文件引用

1. **实时尾部**：
   - `codex-rs/tui/src/pager_overlay.rs`
   - `codex-rs/tui/src/chatwidget.rs` - 活动单元格缓存

2. **动画支持**：
   - `HistoryCell::transcript_animation_tick`

## 依赖与外部交互

### 缓存机制
- 活动单元格缓存键
- 转录动画 tick

## 风险、边界与改进建议

### 潜在风险
1. **内容过多**：大量内容可能导致内存问题
2. **滚动冲突**：自动滚动和用户手动滚动的冲突

### 边界情况
1. 内容产生速度极快
2. 用户正在查看历史内容时新内容产生
3. 终端尺寸变化

### 改进建议
1. 添加内容限制，自动清理旧内容
2. 显示 "有新内容" 提示
3. 支持暂停/恢复实时更新
4. 添加内容过滤功能
