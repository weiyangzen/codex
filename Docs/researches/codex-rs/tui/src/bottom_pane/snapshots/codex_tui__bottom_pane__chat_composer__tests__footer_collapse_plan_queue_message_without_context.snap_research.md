# Footer Collapse Plan Queue Message Without Context - Research Document

## 场景与职责

该快照展示了 TUI 底部状态栏在**中等宽度终端**（40 列）下的自适应折叠行为。当终端宽度不足以同时显示完整的队列提示、Plan 模式指示器和右侧上下文信息时，系统会优先保留左侧的操作提示，丢弃右侧的上下文信息。

**场景条件：**
- 终端宽度：40 列（中等宽度）
- 输入框有内容（"Test"）
- 任务正在运行（`is_task_running = true`）
- 协作模式开启且处于 Plan 模式
- 上下文窗口使用率：98%

**显示结果**：右侧的 "98% context left" 被隐藏

## 功能点目的

该功能实现了 footer 的**渐进式折叠**策略：

1. **优先级排序**：
   - 高优先级：队列操作提示（用户需要知道可以 Tab 排队）
   - 中优先级：当前协作模式（用户需要知道处于 Plan 模式）
   - 低优先级：上下文窗口状态（相对次要的信息）

2. **用户体验**：
   - 确保用户始终能看到最重要的操作提示
   - 避免内容过度拥挤导致的可读性下降

**显示内容：**
```
  tab to queue message · Plan mode
```

## 具体技术实现

### 折叠策略

**`single_line_footer_layout`** 函数中的两阶段回退（footer.rs:348-395）：

```rust
if show_queue_hint {
    // Pass 1: 尝试保持右侧上下文
    for state in queue_states {
        if can_show_left_with_context(area, width, context_width) {
            return (SummaryLeft::Custom(state_line(state)), true); // show_context = true
        }
    }

    // Pass 2: 丢弃上下文，只显示左侧
    for state in queue_states {
        if left_fits(area, width) {
            return (SummaryLeft::Custom(state_line(state)), false); // show_context = false
        }
    }
}
```

### 宽度计算

**`can_show_left_with_context`**（footer.rs:518-527）：
```rust
pub(crate) fn can_show_left_with_context(area: Rect, left_width: u16, context_width: u16) -> bool {
    let Some(context_x) = right_aligned_x(area, context_width) else {
        return true;
    };
    if left_width == 0 {
        return true;
    }
    let left_extent = FOOTER_INDENT_COLS as u16 + left_width + FOOTER_CONTEXT_GAP_COLS;
    left_extent <= context_x.saturating_sub(area.x)
}
```

在 40 列宽度下：
- 左侧内容（"  tab to queue message · Plan mode"）约 35 列
- 右侧内容（"98% context left"）约 16 列
- 加上间隙（1 列）和缩进（2 列），总计超过 40 列
- 因此 `can_show_left_with_context` 返回 `false`，进入 Pass 2

### 右侧内容渲染控制

**调用方代码**（chat_composer.rs 渲染逻辑）：
```rust
let (summary_left, show_context) = single_line_footer_layout(
    area, right_width, left_mode_indicator, show_cycle_hint, show_shortcuts_hint, show_queue_hint
);
// ... 渲染左侧内容 ...
if show_context && let Some(line) = &right_line {
    render_context_right(area, f.buffer_mut(), line);
}
```

当 `show_context = false` 时，右侧上下文不会被渲染。

## 关键代码路径与文件引用

### 核心函数

| 函数 | 位置 | 职责 |
|------|------|------|
| `single_line_footer_layout` | footer.rs:308-472 | 布局计算，返回 `(SummaryLeft, bool)`，bool 表示是否显示 context |
| `can_show_left_with_context` | footer.rs:518-527 | 判断左侧和右侧是否能同时容纳 |
| `left_fits` | footer.rs:252-255 | 判断左侧内容是否能单独容纳 |
| `render_context_right` | footer.rs:529-554 | 右侧上下文渲染 |

### 测试代码

**测试设置**（chat_composer.rs:4891-4900）：
```rust
snapshot_composer_state_with_width(
    "footer_collapse_plan_queue_message_without_context",
    40,  // 关键：40 列宽度
    true,
    |composer| {
        setup_collab_footer(composer, 98, Some(CollaborationModeIndicator::Plan));
        composer.set_task_running(true);
        composer.set_text_content("Test".to_string(), Vec::new(), Vec::new());
    },
);
```

### 相关常量

| 常量 | 值 | 说明 |
|------|-----|------|
| `FOOTER_INDENT_COLS` | 2 | 左侧缩进列数 |
| `FOOTER_CONTEXT_GAP_COLS` | 1 | 左侧内容与右侧 context 之间的间隙 |

## 依赖与外部交互

### 输入参数

**`single_line_footer_layout` 参数**：
- `area: Rect` - footer 区域
- `context_width: u16` - 右侧上下文内容的宽度
- `collaboration_mode_indicator: Option<CollaborationModeIndicator>` - 协作模式指示器
- `show_cycle_hint: bool` - 是否显示 mode cycle hint
- `show_shortcuts_hint: bool` - 是否显示 shortcuts hint
- `show_queue_hint: bool` - 是否显示 queue hint（本场景为 `true`）

### 输出

**返回值**：`(SummaryLeft, bool)`
- `SummaryLeft` - 左侧内容的选择（Default、Custom、None）
- `bool` - 是否显示右侧上下文

## 风险、边界与改进建议

### 边界情况

1. **临界宽度**：
   - 40 列是 "丢弃 context" 的测试用例
   - 50 列是 "缩短 hint + 保留 context" 的测试用例（`footer_collapse_plan_queue_short_with_context`）
   - 30 列是 "缩短 hint + 丢弃 context" 的测试用例（`footer_collapse_plan_queue_short_without_context`）

2. **内容长度变化的影响**：
   - 如果修改 "tab to queue message" 为更长的文本，40 列可能无法容纳
   - 如果修改为更短的文本，可能可以在更窄的宽度下保留 context

### 潜在风险

1. **硬编码宽度值**：
   - 测试用例使用固定的宽度值（40、50、30 等）
   - 如果 hint 文本长度变化，这些测试用例可能无法准确测试预期的边界情况

2. **缺乏动态适应**：
   - 布局决策基于预定义的宽度阈值
   - 没有考虑实际渲染时的字体或终端特性

### 改进建议

1. **基于测量的布局**：
   ```rust
   // 建议：在运行时计算实际需要的宽度
   let required_width = measure_content(&left_content) + 
                        FOOTER_CONTEXT_GAP_COLS + 
                        measure_content(&right_content) +
                        FOOTER_INDENT_COLS * 2;
   let show_context = area.width >= required_width;
   ```

2. **自适应文本**：
   - 支持多级缩短：完整版 → 缩短版 → 缩写版
   - 例如："tab to queue message" → "tab to queue" → "[Tab]"

3. **测试改进**：
   - 使用基于内容长度的相对宽度，而非固定值
   - 添加更多临界值测试

4. **配置选项**：
   - 允许用户自定义哪些信息优先级更高
   - 支持隐藏某些次要信息以节省空间
