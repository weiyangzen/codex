# Research: request_user_input_tight_height.snap

## 场景与职责

本快照文件是 `codex-tui` crate 中 `request_user_input` 模块的 insta 快照测试结果，验证当终端高度受限时的 UI 渲染行为。在高度紧张的情况下，UI 需要合理分配空间，确保核心元素可见。

## 功能点目的

### 测试目标
验证在有限高度(10行)下，UI 能够正确渲染，合理分配空间给问题、选项和底部提示。

### 快照内容分析
```
Question 1/1 (1 unanswered)                                                                                           
Choose an option.                                                                                                      
                                                                                                                      
› 1. Option 1  First choice.                                                                                           
  2. Option 2  Second choice.                                                                                          
  3. Option 3  Third choice.                                                                                           
                                                                                                                      
tab to add notes | enter to submit answer | esc to interrupt
```

关键观察点：
1. **紧凑布局**: 高度仅10行，但所有核心元素都可见
2. **问题区域**: 问题文本完整显示
3. **选项区域**: 3个选项全部可见
4. **底部提示**: 完整显示所有操作提示

### 空间分配策略
- 优先保证问题和选项的显示
- 底部提示压缩到最少行数
- 不显示 notes 区域（需要 Tab 打开）

## 具体技术实现

### 布局计算

`layout_sections()` 方法 (layout.rs 第19-60行):
```rust
pub(super) fn layout_sections(&self, area: Rect) -> LayoutSections {
    let has_options = self.has_options();
    let notes_visible = !has_options || self.notes_ui_visible();
    let footer_pref = self.footer_required_height(area.width);
    let notes_pref_height = self.notes_input_height(area.width);
    let mut question_lines = self.wrapped_question_lines(area.width);
    let question_height = question_lines.len() as u16;

    let layout = if has_options {
        self.layout_with_options(...)
    } else {
        self.layout_without_options(...)
    };
    // ...
}
```

### 带选项的布局

`layout_with_options()` 方法 (layout.rs 第63-95行):
```rust
fn layout_with_options(
    &self,
    args: OptionsLayoutArgs,
    question_lines: &mut Vec<String>,
) -> LayoutPlan {
    // 确保至少显示一个选项
    let min_options_height = available_height.min(1);
    let max_question_height = available_height.saturating_sub(min_options_height);
    
    // 问题高度不能超过最大允许值
    if question_height > max_question_height {
        question_height = max_question_height;
        question_lines.truncate(question_height as usize);
    }
    // ...
}
```

### 空间压缩策略

`layout_with_options_normal()` 方法 (layout.rs 第99-196行):
```rust
fn layout_with_options_normal(...) -> LayoutPlan {
    // ...
    // 当 notes 隐藏时，优先保留进度、footer 和间隔的空间
    let desired_spacers = if notes_visible {
        1  // Notes 已分隔 options 和 footer
    } else {
        DESIRED_SPACERS_BETWEEN_SECTIONS  // 需要额外间隔
    };
    
    let required_extra = footer_pref
        .saturating_add(1) // progress line
        .saturating_add(desired_spacers);
    
    // 如果剩余空间不足，压缩 options 区域
    if remaining < required_extra {
        let deficit = required_extra.saturating_sub(remaining);
        let reducible = options_height.saturating_sub(min_options_height);
        let reduce_by = deficit.min(reducible);
        options_height = options_height.saturating_sub(reduce_by);
        remaining = remaining.saturating_add(reduce_by);
    }
    // ...
}
```

### 最小高度常量

```rust
const MIN_OVERLAY_HEIGHT: usize = 8;  // 覆盖层最小高度
const PROGRESS_ROW_HEIGHT: usize = 1; // 进度行高度
const MIN_COMPOSER_HEIGHT: u16 = 3;   // 输入框最小高度
```

## 关键代码路径与文件引用

| 文件路径 | 相关代码行 | 说明 |
|---------|-----------|------|
| `codex-rs/tui/src/bottom_pane/request_user_input/layout.rs` | 19-60 | `layout_sections()` 主入口 |
| `codex-rs/tui/src/bottom_pane/request_user_input/layout.rs` | 63-95 | `layout_with_options()` |
| `codex-rs/tui/src/bottom_pane/request_user_input/layout.rs` | 99-196 | `layout_with_options_normal()` |
| `codex-rs/tui/src/bottom_pane/request_user_input/layout.rs` | 224-244 | `layout_without_options_tight()` |
| `codex-rs/tui/src/bottom_pane/request_user_input/render.rs` | 26 | `MIN_OVERLAY_HEIGHT` 常量 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 44 | `MIN_COMPOSER_HEIGHT` 常量 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 2491-2506 | 本快照对应的测试用例 |

## 依赖与外部交互

### 高度计算

`desired_height()` 方法 (render.rs 第62-105行):
```rust
fn desired_height(&self, width: u16) -> u16 {
    // ...
    let mut height = question_height
        .saturating_add(options_height)
        .saturating_add(spacer_rows)
        .saturating_add(notes_height)
        .saturating_add(footer_height)
        .saturating_add(PROGRESS_ROW_HEIGHT);
    height = height.saturating_add(menu_surface_padding_height() as usize);
    height.max(MIN_OVERLAY_HEIGHT) as u16
}
```

### 测试配置

```rust
#[test]
fn request_user_input_tight_height_snapshot() {
    let (tx, _rx) = test_sender();
    let overlay = RequestUserInputOverlay::new(
        request_event("turn-1", vec![question_with_options("q1", "Area")]),
        tx,
        true,
        false,
        false,
    );
    let area = Rect::new(0, 0, 120, 10);  // 紧凑高度
    insta::assert_snapshot!(
        "request_user_input_tight_height",
        render_snapshot(&overlay, area)
    );
}
```

## 风险、边界与改进建议

### 潜在风险
1. **内容截断**: 高度严重不足时可能截断问题或选项文本
2. **可用性下降**: 过于紧凑的布局可能影响用户体验
3. **滚动冲突**: 小高度下多个可滚动区域的交互冲突

### 边界情况
1. **极小高度**: 高度小于 MIN_OVERLAY_HEIGHT 时的处理
2. **长问题文本**: 问题文本过长时的截断策略
3. **多行选项**: 选项换行后的高度计算

### 改进建议
1. **最小高度警告**: 当高度低于推荐值时显示警告
2. **自适应字体**: 在极小高度下考虑缩小字体
3. **折叠模式**: 添加折叠模式，隐藏非关键元素
4. **全屏模式**: 提供全屏模式选项，最大化可用空间
