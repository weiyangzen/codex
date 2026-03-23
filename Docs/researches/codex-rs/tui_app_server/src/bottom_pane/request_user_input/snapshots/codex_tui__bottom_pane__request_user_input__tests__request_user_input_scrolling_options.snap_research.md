# Research: request_user_input_scrolling_options.snap

## 场景与职责

本快照文件是 `codex-tui` crate 中 `request_user_input` 模块的 insta 快照测试结果，验证当选项列表超出可视区域时的滚动渲染行为。当选项数量较多或终端高度不足时，需要正确显示当前选中选项并隐藏部分选项。

## 功能点目的

### 测试目标
验证选项列表的滚动功能，确保当前选中选项始终可见，且被隐藏的选项不会错误显示。

### 快照内容分析
```
Question 1/1 (1 unanswered)                                                                                           
What would you like to do next?                                                                                        
                                                                                                                      
    1. Discuss a code change (Recommended)  Walk through a plan and edit code together.                                 
    2. Run tests                            Pick a crate and run its tests.                                              
    3. Review a diff                        Summarize or review current changes.                                        
  › 4. Refactor                             Tighten structure and remove dead code.                                      
    5. Ship it                              Finalize and open a PR.                                                      
                                                                                                                      
tab to add notes | enter to submit answer | esc to interrupt
```

关键观察点：
1. **5个选项**: 完整列表包含5个选项
2. **选中第4个**: `› 4. Refactor` 显示当前选中第4个选项
3. **全部可见**: 在此高度(12行)下，所有5个选项都能显示
4. **对齐格式**: 选项标签和描述对齐，便于阅读

### 滚动触发条件
- 选项数量超过可显示区域
- 用户导航到当前可视区域外的选项
- `ScrollState` 自动调整 `window_offset` 确保选中项可见

## 具体技术实现

### ScrollState 结构

```rust
#[derive(Default, Clone, Copy, PartialEq)]
pub struct ScrollState {
    pub selected_idx: Option<usize>,  // 当前选中索引
    pub window_offset: usize,         // 可视窗口起始偏移
}
```

### 确保可见性

`ensure_visible()` 方法 (scroll_state.rs):
```rust
pub fn ensure_visible(&mut self, item_count: usize, window_height: usize) {
    let Some(selected) = self.selected_idx else {
        return;
    };
    
    // 确保选中项在可视窗口内
    if selected < self.window_offset {
        // 选中项在窗口上方，向上滚动
        self.window_offset = selected;
    } else if selected >= self.window_offset + window_height {
        // 选中项在窗口下方，向下滚动
        self.window_offset = selected.saturating_sub(window_height - 1);
    }
}
```

### 选项渲染

`render_ui()` 中的滚动处理 (render.rs 第315-327行):
```rust
if sections.options_area.height > 0 {
    // 确保选中选项在可视窗口内
    options_state.ensure_visible(option_rows.len(), sections.options_area.height as usize);
    
    render_rows_bottom_aligned(
        sections.options_area,
        buf,
        &option_rows,
        &options_state,
        option_rows.len().max(1),
        "No options",
    );
}
```

### 底部对齐渲染

`render_rows_bottom_aligned()` 函数 (render.rs 第439-474行):
```rust
fn render_rows_bottom_aligned(
    area: Rect,
    buf: &mut Buffer,
    rows: &[GenericDisplayRow],
    state: &ScrollState,
    max_results: usize,
    empty_message: &str,
) {
    // 在临时缓冲区渲染
    let scratch_area = Rect::new(0, 0, area.width, area.height);
    let mut scratch = Buffer::empty(scratch_area);
    
    // 复制原缓冲区内容
    for y in 0..area.height {
        for x in 0..area.width {
            scratch[(x, y)] = buf[(area.x + x, area.y + y)].clone();
        }
    }
    
    // 渲染选项行
    let rendered_height = render_rows(
        scratch_area,
        &mut scratch,
        rows,
        state,
        max_results,
        empty_message,
    );
    
    // 底部对齐：计算偏移量
    let visible_height = rendered_height.min(area.height);
    let y_offset = area.height.saturating_sub(visible_height);
    
    // 复制回主缓冲区（带偏移）
    for y in 0..visible_height {
        for x in 0..area.width {
            buf[(area.x + x, area.y + y_offset + y)] = scratch[(x, y)].clone();
        }
    }
}
```

### 导航处理

上下导航 (mod.rs 第1083-1106行):
```rust
KeyCode::Up | KeyCode::Char('k') => {
    let moved = if let Some(answer) = self.current_answer_mut() {
        answer.options_state.move_up_wrap(options_len);  // 向上，循环
        answer.answer_committed = false;
        true
    } else { false };
    if moved { self.sync_composer_placeholder(); }
}
KeyCode::Down | KeyCode::Char('j') => {
    let moved = if let Some(answer) = self.current_answer_mut() {
        answer.options_state.move_down_wrap(options_len);  // 向下，循环
        answer.answer_committed = false;
        true
    } else { false };
    if moved { self.sync_composer_placeholder(); }
}
```

## 关键代码路径与文件引用

| 文件路径 | 相关代码行 | 说明 |
|---------|-----------|------|
| `codex-rs/tui/src/bottom_pane/scroll_state.rs` | - | `ScrollState` 结构和方法 |
| `codex-rs/tui/src/bottom_pane/scroll_state.rs` | - | `ensure_visible()` 方法 |
| `codex-rs/tui/src/bottom_pane/scroll_state.rs` | - | `move_up_wrap()` / `move_down_wrap()` |
| `codex-rs/tui/src/bottom_pane/request_user_input/render.rs` | 315-327 | 选项渲染和滚动处理 |
| `codex-rs/tui/src/bottom_pane/request_user_input/render.rs` | 439-474 | 底部对齐渲染 |
| `codex-rs/tui/src/bottom_pane/selection_popup_common.rs` | - | `render_rows()` 函数 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 1083-1106 | 键盘导航处理 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 2706-2756 | 本快照对应的测试用例 |

## 依赖与外部交互

### 测试数据

```rust
RequestUserInputQuestion {
    id: "q1".to_string(),
    header: "Next Step".to_string(),
    question: "What would you like to do next?".to_string(),
    options: Some(vec![
        RequestUserInputQuestionOption { label: "Discuss a code change (Recommended)", ... },
        RequestUserInputQuestionOption { label: "Run tests", ... },
        RequestUserInputQuestionOption { label: "Review a diff", ... },
        RequestUserInputQuestionOption { label: "Refactor", ... },  // 选中
        RequestUserInputQuestionOption { label: "Ship it", ... },
    ]),
}
```

### 选中状态设置

测试用例中显式设置选中索引:
```rust
{
    let answer = overlay.current_answer_mut().expect("answer missing");
    answer.options_state.selected_idx = Some(3);  // 选中第4个选项(索引3)
}
```

## 风险、边界与改进建议

### 潜在风险
1. **滚动跳跃**: 快速滚动时可能出现视觉跳跃
2. **选中项遮挡**: 某些情况下选中项可能被部分遮挡
3. **性能**: 大量选项时的渲染性能

### 边界情况
1. **首/尾选项**: 循环导航时从第一个向上或最后一个向下的处理
2. **窗口大小变化**: 终端大小动态调整时的滚动位置
3. **单选项**: 只有一个选项时的滚动行为

### 改进建议
1. **平滑滚动**: 添加平滑滚动动画
2. **滚动指示器**: 在可滚动时显示上下箭头指示器
3. **快速导航**: 添加跳转到首/尾选项的快捷键(如 Home/End)
4. **搜索过滤**: 大量选项时支持搜索过滤
