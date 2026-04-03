# Footer Collapse Plan Queue Mode Only - Research Document

## 场景与职责

该快照展示了 TUI 底部状态栏在**极窄终端**（20 列）下的极端折叠状态。当终端宽度非常有限时，系统会丢弃所有操作提示，仅保留最核心的协作模式指示器（Plan mode）。

**场景条件：**
- 终端宽度：20 列（极窄）
- 输入框有内容（"Test"）
- 任务正在运行（`is_task_running = true`）
- 协作模式开启且处于 Plan 模式
- 上下文窗口使用率：98%

**显示结果**：仅显示 "Plan mode"，queue hint 和 context 都被隐藏

## 功能点目的

该功能实现了 footer 的**极端折叠**策略，确保即使在极窄的终端窗口中：

1. **核心信息保留**：
   - 用户至少能知道当前处于什么协作模式
   - 避免因空间不足导致 footer 完全空白或显示混乱

2. **渐进式降级**：
   - 完整显示 → 缩短 hint → 仅 mode → 完全隐藏
   - 每个阶段都有明确的回退逻辑

**显示内容：**
```
  Plan mode
```

## 具体技术实现

### 极端折叠逻辑

**`single_line_footer_layout`** 函数的最终回退（footer.rs:396-469）：

```rust
// Final fallback: if queue variants (or other earlier states) could not fit
// at all, drop every hint and try to show just the mode label.
if let Some(collaboration_mode_indicator) = collaboration_mode_indicator {
    let mode_only_state = LeftSideState {
        hint: SummaryHintKind::None,
        show_cycle_hint: false,
    };
    let mode_only_width =
        left_side_line(Some(collaboration_mode_indicator), mode_only_state).width() as u16;
    if !context_requires_cycle_hint
        && can_show_left_with_context(area, mode_only_width, context_width)
    {
        return (
            SummaryLeft::Custom(left_side_line(...)),
            true, // show_context
        );
    }
    if left_fits(area, mode_only_width) {
        return (
            SummaryLeft::Custom(left_side_line(...)),
            false, // show_context
        );
    }
}

// 最终：完全隐藏左侧内容
(SummaryLeft::None, true)
```

### 状态定义

**`mode_only_state`**：
```rust
LeftSideState {
    hint: SummaryHintKind::None,  // 不显示任何 hint
    show_cycle_hint: false,       // 不显示 cycle hint
}
```

此时 `left_side_line` 只返回模式指示器的标签：
```rust
fn left_side_line(...) -> Line<'static> {
    match state.hint {
        SummaryHintKind::None => {}  // 不添加 hint
        // ...
    };
    
    if let Some(collaboration_mode_indicator) = collaboration_mode_indicator {
        // 只添加 mode 指示器
        line.push_span(collaboration_mode_indicator.styled_span(state.show_cycle_hint));
    }
    line
}
```

### 宽度计算

在 20 列宽度下：
- 缩进：2 列（`FOOTER_INDENT_COLS`）
- "Plan mode"：9 列
- 总计：11 列

这刚好能在 20 列内显示，因此 `left_fits` 返回 `true`。

## 关键代码路径与文件引用

### 核心代码

| 代码段 | 位置 | 说明 |
|--------|------|------|
| `mode_only_state` 定义 | footer.rs:441-444 | 仅显示 mode 的状态定义 |
| 最终回退逻辑 | footer.rs:440-469 | 尝试仅显示 mode 标签 |
| `SummaryLeft::None` | footer.rs:471 | 完全隐藏左侧内容的最终状态 |

### 相关枚举

**`SummaryLeft`**（footer.rs:302-306）：
```rust
pub(crate) enum SummaryLeft {
    Default,           // 使用默认渲染
    Custom(Line<'static>), // 自定义行内容
    None,              // 不显示左侧内容
}
```

### 测试代码

**测试设置**（chat_composer.rs:4911-4920）：
```rust
snapshot_composer_state_with_width(
    "footer_collapse_plan_queue_mode_only",
    20,  // 关键：20 列极窄宽度
    true,
    |composer| {
        setup_collab_footer(composer, 98, Some(CollaborationModeIndicator::Plan));
        composer.set_task_running(true);
        composer.set_text_content("Test".to_string(), Vec::new(), Vec::new());
    },
);
```

## 依赖与外部交互

### 渲染流程

1. **ChatComposer 构建 footer props**：
   ```rust
   let footer_props = self.footer_props();
   ```

2. **调用 `single_line_footer_layout`**：
   ```rust
   let (summary_left, show_context) = single_line_footer_layout(...);
   ```

3. **根据结果渲染**：
   ```rust
   match summary_left {
       SummaryLeft::Default => { /* 使用默认渲染 */ }
       SummaryLeft::Custom(line) => { /* 渲染自定义行 */ }
       SummaryLeft::None => { /* 不渲染左侧内容 */ }
   }
   ```

### 模式指示器样式

**`CollaborationModeIndicator::styled_span`**：
```rust
fn styled_span(self, show_cycle_hint: bool) -> Span<'static> {
    let label = self.label(show_cycle_hint);
    match self {
        CollaborationModeIndicator::Plan => Span::from(label).magenta(),
        CollaborationModeIndicator::PairProgramming => Span::from(label).cyan(),
        CollaborationModeIndicator::Execute => Span::from(label).dim(),
    }
}
```

## 风险、边界与改进建议

### 边界情况

1. **更窄的终端**：
   - 如果终端宽度小于约 11 列，连 "Plan mode" 都无法显示
   - 此时会返回 `SummaryLeft::None`，footer 左侧完全空白

2. **长模式名称**：
   - "Pair Programming mode" 比 "Plan mode" 长得多
   - 在 20 列宽度下可能无法显示，会直接返回 `None`

### 潜在风险

1. **信息丢失**：
   - 在极窄终端中，用户看不到 queue hint，可能不知道可以 Tab 排队
   - 这是一个权衡：显示混乱 vs 信息缺失

2. **不一致的体验**：
   - 不同宽度的终端显示差异很大
   - 用户可能在调整窗口大小时感到困惑

### 改进建议

1. **最小宽度保证**：
   ```rust
   const MIN_FOOTER_WIDTH: u16 = 30; // 设置一个最小合理宽度
   
   if area.width < MIN_FOOTER_WIDTH {
       // 显示一个简化的固定提示，如 "[窄]"
       // 或提示用户扩大窗口
   }
   ```

2. **缩写支持**：
   - 为长模式名称提供缩写版本
   - 例如："Pair Programming mode" → "Pair" 或 "PP"

3. **工具提示**：
   - 当 footer 被折叠时，考虑在其他位置显示完整信息
   - 例如：在状态栏或侧边栏显示 queue hint

4. **响应式断点**：
   - 定义清晰的断点：
     - > 80 列：完整显示
     - 50-80 列：缩短 hint
     - 30-50 列：仅 mode
     - < 30 列：最小化显示或提示

5. **用户配置**：
   - 允许用户设置 footer 的最小显示内容
   - 支持选择哪些信息优先级最高
