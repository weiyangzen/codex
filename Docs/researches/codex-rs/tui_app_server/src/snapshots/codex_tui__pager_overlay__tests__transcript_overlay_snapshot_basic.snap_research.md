# 研究文档：transcript_overlay_snapshot_basic.snap

## 场景与职责

此快照测试验证转录覆盖层的基本显示效果。转录覆盖层（`Ctrl+T`）用于显示完整的会话历史记录。

## 功能点目的

1. **历史记录展示**：显示完整的会话历史
2. **导航支持**：支持滚动和分页浏览
3. **快捷操作**：提供编辑、退出等快捷操作

## 具体技术实现

### 快照输出分析

```
"/ T R A N S C R I P T / / / / / / / / / "
"alpha                                   "
"                                        "
"beta                                    "
"                                        "
"gamma                                   "
"───────────────────────────────── 100% ─"
" ↑/↓ to scroll   pgup/pgdn to page   hom"
" q to quit   esc to edit prev           "
"                                        "
```

界面元素：
- 标题：`/ T R A N S C R I P T /`
- 内容：`alpha`, `beta`, `gamma`
- 进度：`100%`
- 快捷键提示：滚动、退出、编辑

### 转录覆盖层实现

```rust
pub struct TranscriptOverlay {
    cells: Vec<Box<dyn HistoryCell>>,
    scroll_offset: usize,
}

impl TranscriptOverlay {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        // 收集所有单元格的转录行
        let mut all_lines = vec![];
        for cell in &self.cells {
            all_lines.extend(cell.transcript_lines(area.width));
        }
        
        // 根据滚动偏移渲染可见行
        // 渲染底部状态栏
    }
}
```

## 关键代码路径与文件引用

1. **转录覆盖层**：
   - `codex-rs/tui/src/pager_overlay.rs`
   - `codex-rs/tui_app_server/src/pager_overlay.rs`

2. **历史单元格**：
   - `codex-rs/tui/src/history_cell.rs` - `transcript_lines` 方法

## 依赖与外部交互

### 快捷键
- `↑/↓` - 上下滚动
- `pgup/pgdn` - 翻页
- `home/end` - 跳到开头/结尾
- `q` - 退出
- `esc` - 编辑上一条消息

## 风险、边界与改进建议

### 潜在风险
1. **长历史记录**：大量历史记录可能影响性能
2. **缓存失效**：活动单元格缓存可能需要频繁更新

### 边界情况
1. 空历史记录
2. 历史记录极长（>10000 条）
3. 单元格高度计算错误

### 改进建议
1. 添加历史记录搜索功能
2. 支持导出转录内容
3. 添加时间戳显示
4. 支持按类型过滤单元格
