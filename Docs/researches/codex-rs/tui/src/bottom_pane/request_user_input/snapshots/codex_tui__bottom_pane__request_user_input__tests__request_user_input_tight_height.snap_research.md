# 研究文档: request_user_input_tight_height.snap

## 场景与职责

本快照文件测试 **紧凑高度布局** 下的 UI 渲染。当终端高度受限时，系统需要合理分配空间，确保核心信息（问题、选项、操作提示）仍然可见。

测试用例位于 `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` 第 2492-2506 行。

## 功能点目的

### 核心功能
1. **空间压缩**: 在有限高度内显示必要信息
2. **优先级分配**: 确保问题文本和选项优先显示
3. **底部提示保留**: 即使空间紧张也保留操作提示
4. **笔记区隐藏**: 空间不足时优先隐藏笔记输入区

### 紧凑布局策略

```
  Question 1/1 (1 unanswered)
  Choose an option.

  › 1. Option 1  First choice.
    2. Option 2  Second choice.
    3. Option 3  Third choice.

  tab to add notes | enter to submit answer | esc to interrupt
```

注意：与标准布局相比，紧凑布局减少了垂直间距。

## 具体技术实现

### 布局计算

```rust
// layout.rs:63-170
fn layout_with_options(...) -> LayoutPlan {
    // 最小选项高度为 1
    let min_options_height = available_height.min(1);
    let max_question_height = available_height.saturating_sub(min_options_height);
    
    // 如果问题文本过长，截断以适应空间
    if question_height > max_question_height {
        question_height = max_question_height;
        question_lines.truncate(question_height as usize);
    }
    
    // 计算选项区域高度
    let max_options_height = available_height.saturating_sub(question_height);
    let mut options_height = options
        .preferred
        .min(max_options_height)
        .max(min_options_height);
    
    // 空间不足时，压缩选项区域以容纳页脚
    let desired_spacers = if notes_visible { 1 } else { DESIRED_SPACERS_BETWEEN_SECTIONS };
    let required_extra = footer_pref.saturating_add(1).saturating_add(desired_spacers);
    if remaining < required_extra {
        let deficit = required_extra.saturating_sub(remaining);
        let reducible = options_height.saturating_sub(min_options_height);
        let reduce_by = deficit.min(reducible);
        options_height = options_height.saturating_sub(reduce_by);
    }
}
```

### 关键常量

```rust
// mod.rs:46
pub(super) const DESIRED_SPACERS_BETWEEN_SECTIONS: u16 = 2;

// 当笔记可见时，只需要 1 个间距
// 当笔记隐藏时，需要 2 个间距来分隔选项和页脚
```

### 紧凑布局处理

```rust
// layout.rs:224-244
fn layout_without_options_tight(...) -> LayoutPlan {
    let max_question_height = available_height;
    let adjusted_question_height = question_height.min(max_question_height);
    question_lines.truncate(adjusted_question_height as usize);
    
    LayoutPlan {
        question_height: adjusted_question_height,
        progress_height: 0,      // 紧凑模式隐藏进度
        spacer_after_question: 0, // 无间距
        options_height: 0,
        spacer_after_options: 0,
        notes_height: 0,
        footer_lines: 0,         // 紧凑模式隐藏页脚
    }
}
```

### 测试参数

```rust
let area = Rect::new(0, 0, 120, 10);  // 高度只有 10 行
```

## 关键代码路径与文件引用

### 主要代码文件

| 文件路径 | 职责 |
|---------|------|
| `layout.rs` | 紧凑布局计算 |
| `render.rs` | 根据布局渲染 |
| `mod.rs` | 高度计算辅助方法 |

### 关键代码位置

1. **紧凑布局计算**: `layout.rs:63-170`
2. **无选项紧凑布局**: `layout.rs:224-244`
3. **布局结构**: `layout.rs:329-338` (`LayoutPlan`)
4. **测试用例**: `mod.rs:2492-2506`

### LayoutPlan 结构

```rust
#[derive(Clone, Copy, Debug)]
struct LayoutPlan {
    progress_height: u16,         // 进度行高度
    question_height: u16,         // 问题文本高度
    spacer_after_question: u16,   // 问题后间距
    options_height: u16,          // 选项区域高度
    spacer_after_options: u16,    // 选项后间距
    notes_height: u16,            // 笔记区域高度
    footer_lines: u16,            // 页脚行数
}
```

## 依赖与外部交互

### 高度需求计算

```rust
// mod.rs:314-354
pub(super) fn options_required_height(&self, width: u16) -> u16 {
    // 计算显示所有选项所需的高度
}

pub(super) fn options_preferred_height(&self, width: u16) -> u16 {
    // 计算首选高度（可能小于完整高度）
}

pub(super) fn footer_required_height(&self, width: u16) -> u16 {
    // 计算页脚所需行数
    self.footer_tip_lines(width).len() as u16
}
```

### 渲染协调

```rust
// render.rs:62-105
desired_height 计算所有组件的总高度需求
render 根据实际分配的空间进行渲染
```

## 风险、边界与改进建议

### 潜在风险

1. **信息丢失**: 过度压缩可能导致问题文本被截断
2. **可用性下降**: 紧凑布局下操作提示可能难以阅读
3. **布局抖动**: 窗口大小变化时布局可能不稳定

### 边界情况

| 场景 | 行为 |
|------|------|
| 高度 < 问题文本高度 | 截断问题文本 |
| 高度 < 最小选项高度 | 尝试显示至少 1 行选项 |
| 高度 < 页脚高度 | 压缩或隐藏页脚 |
| 高度 = 0 | 不渲染任何内容 |

### 改进建议

1. **最小高度保障**: 设置绝对最小高度，低于此值显示简化界面
2. **重叠渲染**: 极端情况下考虑重叠渲染而非截断
3. **响应式字体**: 小高度时使用更紧凑的字体
4. **折叠模式**: 提供手动折叠/展开功能

### 相关测试

```rust
// 验证布局分配
#[test]
fn layout_allocates_all_wrapped_options_when_space_allows() {
    // mod.rs:2509-2534
}

// 验证首选高度
#[test]
fn desired_height_keeps_spacers_and_preferred_options_visible() {
    // mod.rs:2537-2563
}
```

### 代码审查建议

当前 `layout_with_options` 方法较长（约 100 行），可以提取子方法：

```rust
fn layout_with_options(&self, args: OptionsLayoutArgs, ...) -> LayoutPlan {
    let normal_height = self.calculate_normal_height(&args);
    let adjusted_height = self.adjust_for_footer(normal_height, &args);
    self.allocate_remaining_space(adjusted_height, &args)
}
```
