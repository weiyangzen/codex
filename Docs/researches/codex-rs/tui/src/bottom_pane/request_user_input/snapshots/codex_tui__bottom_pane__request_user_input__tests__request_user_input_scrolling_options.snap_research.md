# 研究文档: request_user_input_scrolling_options.snap

## 场景与职责

本快照文件测试 **选项列表滚动** 功能。当选项数量超过可视区域时，系统需要正确渲染滚动视图，确保选中项始终可见。

测试用例位于 `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` 第 2707-2756 行。

## 功能点目的

### 核心功能
1. **滚动视口**: 只显示部分选项，其余通过滚动访问
2. **选中项可见**: 确保当前选中项始终在可视区域内
3. **位置指示**: 在底部提示中显示当前选项位置（如 "option 4/5"）
4. **底部对齐**: 选项列表底部对齐，保持底部提示位置稳定

### 滚动交互模型

```
Question 1/1 (1 unanswered)
What would you like to do next?

    1. Discuss a code change (Recommended)  Walk through a plan and edit code together.
    2. Run tests                            Pick a crate and run its tests.
    3. Review a diff                        Summarize or review current changes.
  › 4. Refactor                             Tighten structure and remove dead code.
    5. Ship it                              Finalize and open a PR.

  option 4/5 | tab to add notes | enter to submit answer | esc to interrupt
```

注意：虽然测试数据有5个选项，但由于高度限制，可能只显示部分选项。

## 具体技术实现

### 数据结构

```rust
pub struct ScrollState {
    pub selected_idx: Option<usize>,  // 当前选中索引
    pub offset: usize,                // 滚动偏移量（可视区域起始索引）
}

impl ScrollState {
    // 确保选中项在可视区域内
    pub fn ensure_visible(&mut self, total: usize, viewport: usize) {
        if let Some(selected) = self.selected_idx {
            if selected < self.offset {
                // 选中项在视口上方，向上滚动
                self.offset = selected;
            } else if selected >= self.offset + viewport {
                // 选中项在视口下方，向下滚动
                self.offset = selected.saturating_sub(viewport).saturating_add(1);
            }
        }
    }
}
```

### 关键流程

1. **滚动检测与提示** (`render_ui`, render.rs 第 347-356 行):
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

2. **底部对齐渲染** (`render_rows_bottom_aligned`, render.rs 第 439-474 行):
   ```rust
   fn render_rows_bottom_aligned(...) {
       // 创建临时缓冲区渲染
       let mut scratch = Buffer::empty(scratch_area);
       let rendered_height = render_rows(&mut scratch, ...);
       
       // 计算底部偏移
       let visible_height = rendered_height.min(area.height);
       let y_offset = area.height.saturating_sub(visible_height);
       
       // 将渲染结果复制到实际位置（底部对齐）
       for y in 0..visible_height {
           buf[(area.x + x, area.y + y_offset + y)] = scratch[(x, y)];
       }
   }
   ```

3. **确保选中项可见** (render.rs 第 317-318 行):
   ```rust
   options_state.ensure_visible(option_rows.len(), sections.options_area.height as usize);
   ```

### 测试数据

```rust
RequestUserInputQuestion {
    question: "What would you like to do next?".to_string(),
    options: Some(vec![
        RequestUserInputQuestionOption {
            label: "Discuss a code change (Recommended)".to_string(),
            description: "Walk through a plan and edit code together.".to_string(),
        },
        RequestUserInputQuestionOption { label: "Run tests".to_string(), ... },
        RequestUserInputQuestionOption { label: "Review a diff".to_string(), ... },
        RequestUserInputQuestionOption { label: "Refactor".to_string(), ... },  // 选中
        RequestUserInputQuestionOption { label: "Ship it".to_string(), ... },
    ]),
}
```

## 关键代码路径与文件引用

### 主要代码文件

| 文件路径 | 职责 |
|---------|------|
| `render.rs` | 底部对齐渲染、滚动检测 |
| `mod.rs` | 滚动状态管理 |
| `scroll_state.rs` | `ScrollState` 实现 |

### 关键代码位置

1. **底部对齐渲染**: `render.rs:439-474`
2. **滚动检测**: `render.rs:347-356`
3. **确保可见**: `render.rs:317-318`
4. **测试用例**: `mod.rs:2707-2756`

### ScrollState 实现

```rust
// scroll_state.rs
impl ScrollState {
    pub fn move_up_wrap(&mut self, len: usize) {
        if len == 0 { return; }
        self.selected_idx = Some(match self.selected_idx {
            None => len - 1,
            Some(0) => len - 1,
            Some(i) => i - 1,
        });
    }
    
    pub fn move_down_wrap(&mut self, len: usize) {
        if len == 0 { return; }
        self.selected_idx = Some(match self.selected_idx {
            None => 0,
            Some(i) if i + 1 >= len => 0,
            Some(i) => i + 1,
        });
    }
}
```

## 依赖与外部交互

### 高度计算

```rust
// 计算选项完整高度
pub(super) fn options_required_height(&self, width: u16) -> u16 {
    let rows = self.option_rows();
    measure_rows_height(&rows, &state, rows.len(), width.max(1))
}

// 计算首选高度（用于布局协商）
pub(super) fn options_preferred_height(&self, width: u16) -> u16 {
    // 类似实现
}
```

### 布局交互

```rust
// layout.rs 中的布局协商
let max_options_height = available_height.saturating_sub(question_height);
let options_height = options
    .preferred
    .min(max_options_height)
    .max(min_options_height);
```

## 风险、边界与改进建议

### 潜在风险

1. **选中项不可见**: 如果 `ensure_visible` 逻辑有 bug，选中项可能滚出视口
2. **闪烁问题**: 快速滚动时可能出现视觉闪烁
3. **性能问题**: 每次渲染都重新计算滚动偏移可能影响性能

### 边界情况

| 场景 | 行为 |
|------|------|
| 选中第1个选项 | 视口从顶部开始 |
| 选中最后1个选项 | 视口滚动到底部 |
| 选项很少 | 不滚动，底部对齐 |
| 高度为 0 | 不渲染选项 |

### 改进建议

1. **滚动动画**: 添加平滑滚动动画效果
2. **滚动条**: 显示可视化滚动条指示位置
3. **快速滚动**: 支持 PageUp/PageDown 快速滚动
4. **搜索跳转**: 支持搜索并跳转到特定选项

### 相关测试

```rust
// 验证选中长文本选项时保持可见
#[test]
fn selected_long_wrapped_option_stays_visible() {
    // mod.rs:2656-2676
}

// 验证底部对齐布局
#[test]
fn desired_height_keeps_spacers_and_preferred_options_visible() {
    // mod.rs:2537-2563
}
```

### 代码优化建议

当前 `render_rows_bottom_aligned` 使用临时缓冲区，可以考虑直接计算偏移：

```rust
// 当前：使用临时缓冲区
let mut scratch = Buffer::empty(scratch_area);
render_rows(&mut scratch, ...);
// 复制到目标位置

// 优化：直接计算可见范围并渲染
let start_idx = state.offset;
let end_idx = (start_idx + area.height as usize).min(rows.len());
for (i, row) in rows[start_idx..end_idx].iter().enumerate() {
    render_row_at(area.x, area.y + y_offset + i as u16, row);
}
```
