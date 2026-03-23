# Research: request_user_input_hidden_options_footer.snap

## 场景与职责

本快照文件是 `codex-tui` crate 中 `request_user_input` 模块的 insta 快照测试结果，验证当选项列表部分被隐藏时的底部栏显示行为。当选项过多或终端高度不足时，部分选项会被隐藏，此时底部栏需要显示当前选项位置指示器。

## 功能点目的

### 测试目标
验证当选项区域无法显示所有选项时，底部栏正确显示 `option X/Y` 格式的位置指示器，帮助用户了解当前选中的选项在完整列表中的位置。

### 快照内容分析
```
Question 1/1 (1 unanswered)                                                   
What would you like to do next?                                               
                                                                                
  2. Run tests      Pick a crate and run its tests.                           
  3. Review a diff  Summarize or review current changes.                      
› 4. Refactor       Tighten structure and remove dead code.                  
                                                                                
option 4/5 | tab to add notes | enter to submit answer | esc to interrupt
```

关键观察点：
1. **部分选项隐藏**: 只显示选项 2、3、4，选项 1 和 5 被隐藏
2. **位置指示器**: `option 4/5` 显示当前选中第4个选项，共5个
3. **选中状态**: `› 4. Refactor` 显示当前选中第4个选项
4. **完整底部栏**: 包含位置指示器 + 操作提示

### 触发条件
- 终端高度不足以显示所有选项
- 选项数量超过可显示区域
- 用户滚动到非首屏选项

## 具体技术实现

### 选项隐藏检测逻辑

`render_ui()` 方法中的检测 (render.rs 第347-356行):
```rust
let options_hidden = self.has_options()
    && sections.options_area.height > 0
    && self.options_required_height(content_area.width) > sections.options_area.height;
let option_tip = if options_hidden {
    let selected = self.selected_option_index().unwrap_or(0).saturating_add(1);
    let total = self.options_len();
    Some(super::FooterTip::new(format!("option {selected}/{total}")))
} else {
    None
};
```

### 选项高度计算

`options_required_height()` 方法 (mod.rs 第315-334行):
```rust
pub(super) fn options_required_height(&self, width: u16) -> u16 {
    if !self.has_options() {
        return 0;
    }

    let rows = self.option_rows();
    if rows.is_empty() {
        return 1;
    }

    let mut state = self
        .current_answer()
        .map(|answer| answer.options_state)
        .unwrap_or_default();
    if state.selected_idx.is_none() {
        state.selected_idx = Some(0);
    }

    measure_rows_height(&rows, &state, rows.len(), width.max(1))
}
```

### 底部提示组合

`footer_tip_lines_with_prefix()` 方法 (mod.rs 第469-480行):
```rust
pub(super) fn footer_tip_lines_with_prefix(
    &self,
    width: u16,
    prefix: Option<FooterTip>,
) -> Vec<Vec<FooterTip>> {
    let mut tips = Vec::new();
    if let Some(prefix) = prefix {
        tips.push(prefix);  // 添加 option X/Y 前缀
    }
    tips.extend(self.footer_tips());  // 添加其他提示
    self.wrap_footer_tips(width, tips)
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
    // ...
    let rendered_height = render_rows(...);
    let visible_height = rendered_height.min(area.height);
    let y_offset = area.height.saturating_sub(visible_height);  // 底部对齐
    // ...
}
```

## 关键代码路径与文件引用

| 文件路径 | 相关代码行 | 说明 |
|---------|-----------|------|
| `codex-rs/tui/src/bottom_pane/request_user_input/render.rs` | 347-356 | 检测选项是否被隐藏并生成位置提示 |
| `codex-rs/tui/src/bottom_pane/request_user_input/render.rs` | 357 | 组合位置提示与其他提示 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 315-334 | `options_required_height()` 计算 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 336-355 | `options_preferred_height()` 计算 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 469-480 | `footer_tip_lines_with_prefix()` |
| `codex-rs/tui/src/bottom_pane/request_user_input/render.rs` | 439-474 | 底部对齐渲染函数 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 2759-2808 | 本快照对应的测试用例 |

## 依赖与外部交互

### ScrollState 管理

```rust
struct AnswerState {
    options_state: ScrollState,  // 管理选项滚动和选中状态
    // ...
}
```

`ScrollState` 提供的方法:
- `ensure_visible()`: 确保选中项在可视区域内
- `move_up_wrap()` / `move_down_wrap()`: 上下导航

### measure_rows_height 工具函数

位于 `selection_popup_common` 模块，计算多行选项的总高度:
```rust
pub fn measure_rows_height(
    rows: &[GenericDisplayRow],
    state: &ScrollState,
    max_results: usize,
    width: u16,
) -> u16
```

## 风险、边界与改进建议

### 潜在风险
1. **位置指示器精度**: 当选项文本长度差异大时，高度计算可能有偏差
2. **滚动状态同步**: 确保 `ScrollState` 的选中索引与实际渲染一致
3. **快速滚动**: 快速滚动时可能出现闪烁或位置指示器延迟更新

### 边界情况
1. **单选项**: 只有一个选项时显示 `option 1/1` 可能显得多余
2. **全部隐藏**: 极端情况下所有选项都被隐藏
3. **动态调整**: 终端大小动态调整时的处理

### 改进建议
1. **智能隐藏**: 考虑在选项数量少时不显示位置指示器
2. **进度条**: 用进度条替代文字指示器，更直观
3. **滚动动画**: 添加平滑滚动动画提升用户体验
4. **键盘快捷键**: 添加跳转到首/尾选项的快捷键
