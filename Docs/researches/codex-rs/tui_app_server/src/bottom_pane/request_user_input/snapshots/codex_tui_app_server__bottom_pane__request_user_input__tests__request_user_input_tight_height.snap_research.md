# Research: request_user_input_tight_height.snap (tui_app_server)

## 场景与职责

本快照文件是 `codex-tui-app-server` crate 中 `request_user_input` 模块的 insta 快照测试结果，验证当终端高度受限时的 UI 渲染行为。

## 功能点目的

### 测试目标
验证在有限高度(10行)下，UI 能够正确渲染，合理分配空间。

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
2. **空间分配**: 优先保证问题和选项的显示

## 具体技术实现

### 布局计算

`layout_sections()` 方法:
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

### 空间压缩策略

当空间不足时，优先压缩 options 区域:
```rust
if remaining < required_extra {
    let deficit = required_extra.saturating_sub(remaining);
    let reducible = options_height.saturating_sub(min_options_height);
    let reduce_by = deficit.min(reducible);
    options_height = options_height.saturating_sub(reduce_by);
    remaining = remaining.saturating_add(reduce_by);
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/layout.rs` | 布局计算和空间分配 |

## 风险、边界与改进建议

### 潜在风险
1. **内容截断**: 高度严重不足时可能截断问题或选项文本
2. **可用性下降**: 过于紧凑的布局可能影响用户体验

### 改进建议
1. **最小高度警告**: 当高度低于推荐值时显示警告
2. **折叠模式**: 添加折叠模式，隐藏非关键元素
