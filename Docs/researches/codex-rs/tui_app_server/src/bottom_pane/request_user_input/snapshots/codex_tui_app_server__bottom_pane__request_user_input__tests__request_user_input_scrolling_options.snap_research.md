# Research: request_user_input_scrolling_options.snap (tui_app_server)

## 场景与职责

本快照文件是 `codex-tui-app-server` crate 中 `request_user_input` 模块的 insta 快照测试结果，验证当选项列表超出可视区域时的滚动渲染行为。

## 功能点目的

### 测试目标
验证选项列表的滚动功能，确保当前选中选项始终可见。

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

## 具体技术实现

### ScrollState 结构

```rust
#[derive(Default, Clone, Copy, PartialEq)]
pub struct ScrollState {
    pub selected_idx: Option<usize>,
    pub window_offset: usize,
}
```

### 确保可见性

`ensure_visible()` 方法:
```rust
pub fn ensure_visible(&mut self, item_count: usize, window_height: usize) {
    let Some(selected) = self.selected_idx else { return };
    
    if selected < self.window_offset {
        self.window_offset = selected;
    } else if selected >= self.window_offset + window_height {
        self.window_offset = selected.saturating_sub(window_height - 1);
    }
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/bottom_pane/scroll_state.rs` | `ScrollState` 结构和方法 |
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/render.rs` | 选项渲染和滚动处理 |

## 风险、边界与改进建议

### 潜在风险
1. **滚动跳跃**: 快速滚动时可能出现视觉跳跃
2. **选中项遮挡**: 某些情况下选中项可能被部分遮挡

### 改进建议
1. **平滑滚动**: 添加平滑滚动动画
2. **滚动指示器**: 在可滚动时显示上下箭头指示器
