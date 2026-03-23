# 研究文档: request_user_input_hidden_options_footer.snap

## 场景与职责

本快照文件测试 **选项部分可见时的底部提示** 功能。当终端高度不足以显示所有选项时，系统需要在底部提示中显示当前选项位置（如 "option 4/5"），让用户了解滚动上下文。

测试用例位于 `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` 第 2759-2808 行。

## 功能点目的

### 核心功能
当选项区域发生裁剪（部分选项不可见）时：
1. **显示位置指示器**: 如 "option 4/5" 表示当前选中第4个选项，共5个
2. **保持导航提示**: 同时显示其他操作提示
3. **视觉区分**: 位置指示器使用普通样式，关键操作使用高亮

### 触发条件
```rust
let options_hidden = self.has_options()
    && sections.options_area.height > 0
    && self.options_required_height(content_area.width) > sections.options_area.height;
```

即：有选项 + 选项区域有高度 + 选项所需高度 > 实际分配高度

## 具体技术实现

### 数据结构

```rust
// FooterTip 结构
pub(super) struct FooterTip {
    pub(super) text: String,
    pub(super) highlight: bool,
}
```

### 关键流程

1. **检测选项裁剪** (`render_ui`, render.rs 第 347-356 行):
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

2. **合并提示** (`footer_tip_lines_with_prefix`, mod.rs 第 468-479 行):
   ```rust
   pub(super) fn footer_tip_lines_with_prefix(
       &self,
       width: u16,
       prefix: Option<FooterTip>,  // 位置指示器作为前缀
   ) -> Vec<Vec<FooterTip>> {
       let mut tips = Vec::new();
       if let Some(prefix) = prefix {
           tips.push(prefix);
       }
       tips.extend(self.footer_tips());
       self.wrap_footer_tips(width, tips)
   }
   ```

### 渲染输出

```
  Question 1/1 (1 unanswered)
  What would you like to do next?

    2. Run tests      Pick a crate and run its tests.
    3. Review a diff  Summarize or review current changes.
  › 4. Refactor       Tighten structure and remove dead code.

  option 4/5 | tab to add notes | enter to submit answer | esc to interrupt
```

关键观察：
- 只显示选项 2-4（共5个选项，第1个和第5个被裁剪）
- 底部提示以 "option 4/5" 开头，让用户知道当前位置和总数

## 关键代码路径与文件引用

### 主要代码文件

| 文件路径 | 职责 |
|---------|------|
| `render.rs` | 检测裁剪并生成位置提示 |
| `mod.rs` | 提示合并和换行计算 |

### 关键代码位置

1. **裁剪检测**: `render.rs:347-356`
2. **提示前缀合并**: `mod.rs:468-479`
3. **测试用例**: `mod.rs:2759-2808`

### 高度计算

```rust
// options_required_height: 选项完整显示所需高度
pub(super) fn options_required_height(&self, width: u16) -> u16 {
    let rows = self.option_rows();
    if rows.is_empty() {
        return 1;
    }
    measure_rows_height(&rows, &state, rows.len(), width.max(1))
}

// options_preferred_height: 首选高度（可能小于完整高度）
pub(super) fn options_preferred_height(&self, width: u16) -> u16 {
    // 与 required 类似，但可能返回不同值用于布局协商
}
```

## 依赖与外部交互

### 布局系统交互

```rust
// layout.rs 中的布局协商
LayoutSections {
    progress_area: Rect,   // 进度显示区域
    question_area: Rect,   // 问题文本区域
    options_area: Rect,    // 选项区域（可能被压缩）
    notes_area: Rect,      // 笔记输入区域
    footer_lines: u16,     // 底部提示行数
}
```

### 滚动状态

```rust
// ScrollState 跟踪当前选中项
struct ScrollState {
    selected_idx: Option<usize>,  // 当前选中的选项索引
    // ... 其他字段
}
```

## 风险、边界与改进建议

### 潜在风险

1. **提示过长**: 当位置提示与其他提示合并后超过宽度限制时，换行可能导致视觉混乱
2. **信息过载**: 底部提示包含太多信息（位置 + 操作 + 导航）
3. **选中项不可见**: 如果布局计算有 bug，可能导致选中项被裁剪出可视区域

### 边界情况

| 场景 | 行为 |
|------|------|
| 选中第1个选项但前面有隐藏选项 | 显示 "option 1/5"，用户知道前面还有 |
| 选中最后1个选项 | 显示 "option 5/5" |
| 所有选项可见 | 不显示位置提示 |
| 宽度极窄 | 提示换行，位置提示可能单独一行 |

### 改进建议

1. **滚动指示器**: 在选项区域添加视觉滚动条或箭头指示
2. **智能提示**: 当选项被裁剪时，在选项列表顶部/底部显示 "..." 或 "↑ more"
3. **位置提示样式**: 使用不同颜色或样式区分位置提示和操作提示
4. **快捷键**: 添加 "跳转到第一个/最后一个选项" 的快捷键

### 相关测试

```rust
// 验证选中项在滚动后仍然可见
#[test]
fn selected_long_wrapped_option_stays_visible() {
    // mod.rs:2656-2676
}
```

### 代码审查建议

当前实现中 `options_required_height` 和 `options_preferred_height` 逻辑几乎相同，可以考虑：

```rust
// 当前：两个几乎相同的方法
pub(super) fn options_required_height(&self, width: u16) -> u16 { ... }
pub(super) fn options_preferred_height(&self, width: u16) -> u16 { ... }

// 建议：统一为一个方法，参数控制行为
pub(super) fn options_height(&self, width: u16, mode: HeightMode) -> u16 { ... }
```
