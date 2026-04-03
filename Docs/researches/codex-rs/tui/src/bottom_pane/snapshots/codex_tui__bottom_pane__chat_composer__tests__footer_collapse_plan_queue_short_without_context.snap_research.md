# Footer Collapse Plan Queue Short Without Context - Research Document

## 场景与职责

该快照展示了 TUI 底部状态栏在**较窄终端**（30 列）下的双重折叠策略。当终端宽度不足以同时显示缩短版的队列提示、Plan 模式指示器和右侧上下文信息时，系统会同时应用文本缩短和丢弃上下文两种优化手段。

**场景条件：**
- 终端宽度：30 列（较窄）
- 输入框有内容（"Test"）
- 任务正在运行（`is_task_running = true`）
- 协作模式开启且处于 Plan 模式
- 上下文窗口使用率：98%

**显示结果**：缩短的 queue hint + Plan mode，context 被隐藏

## 功能点目的

该功能实现了 footer 的**组合折叠**策略：

1. **双重优化**：
   - 缩短 hint 文本（"tab to queue message" → "tab to queue"）
   - 丢弃右侧上下文信息

2. **渐进式降级**：
   - 首先尝试完整显示（失败）
   - 然后尝试缩短 hint + context（失败）
   - 最后使用缩短 hint + 丢弃 context（成功）

**显示内容：**
```
  tab to queue · Plan mode
```

## 具体技术实现

### 两阶段回退策略

**Pass 1：尝试保留 context**（footer.rs:365-378）
```rust
for state in queue_states {
    let width = state_width(state);
    if width > 0 && can_show_left_with_context(area, width, context_width) {
        return (SummaryLeft::Custom(state_line(state)), true); // show_context = true
    }
}
```

在 30 列宽度下，所有 queue 状态都无法与 context 同时容纳，Pass 1 失败。

**Pass 2：丢弃 context**（footer.rs:382-395）
```rust
for state in queue_states {
    let width = state_width(state);
    if width > 0 && left_fits(area, width) {
        return (SummaryLeft::Custom(state_line(state)), false); // show_context = false
    }
}
```

缩短版 "tab to queue" + "Plan mode" 约 28 列，可以在 30 列内容纳。

### 状态序列

**`queue_states` 数组**（footer.rs:350-360）：
```rust
let queue_states = [
    // 1. 完整 queue hint + cycle hint
    default_state,
    // 2. 完整 queue hint，无 cycle hint
    LeftSideState {
        hint: SummaryHintKind::QueueMessage,
        show_cycle_hint: false,
    },
    // 3. 缩短 queue hint，无 cycle hint
    LeftSideState {
        hint: SummaryHintKind::QueueShort,
        show_cycle_hint: false,
    },
];
```

在 30 列宽度下，前两个状态都无法容纳，只有第三个状态（缩短版）成功。

### 宽度计算

**各状态宽度估算**（含缩进）：

| 状态 | 内容 | 估算宽度 | 30 列能否容纳 |
|------|------|----------|---------------|
| default_state | "tab to queue message · Plan mode (shift+tab to cycle)" | ~55 列 | ❌ |
| 无 cycle | "tab to queue message · Plan mode" | ~38 列 | ❌ |
| 缩短版 | "tab to queue · Plan mode" | ~28 列 | ✅ |

## 关键代码路径与文件引用

### 核心代码

| 代码段 | 位置 | 说明 |
|--------|------|------|
| `queue_states` 定义 | footer.rs:350-360 | 定义三种 queue hint 状态 |
| Pass 1 循环 | footer.rs:365-378 | 尝试保留 context |
| Pass 2 循环 | footer.rs:382-395 | 丢弃 context 后的尝试 |
| `left_fits` | footer.rs:252-255 | 检查内容是否适合区域 |

### 辅助函数

**`state_width` 闭包**（footer.rs:342）：
```rust
let state_width = |state: LeftSideState| -> u16 { state_line(state).width() as u16 };
```

**`state_line` 闭包**（footer.rs:335-341）：
```rust
let state_line = |state: LeftSideState| -> Line<'static> {
    if state == default_state {
        default_line.clone()
    } else {
        left_side_line(collaboration_mode_indicator, state)
    }
};
```

### 测试代码

**测试设置**（chat_composer.rs:4901-4910）：
```rust
snapshot_composer_state_with_width(
    "footer_collapse_plan_queue_short_without_context",
    30,  // 关键：30 列宽度
    true,
    |composer| {
        setup_collab_footer(composer, 98, Some(CollaborationModeIndicator::Plan));
        composer.set_task_running(true);
        composer.set_text_content("Test".to_string(), Vec::new(), Vec::new());
    },
);
```

## 依赖与外部交互

### 去重逻辑

代码中使用了去重逻辑避免重复尝试相同状态（footer.rs:367-369, 384-386）：
```rust
let mut previous_state: Option<LeftSideState> = None;
for state in queue_states {
    if previous_state == Some(state) {
        continue;  // 跳过重复状态
    }
    previous_state = Some(state);
    // ...
}
```

这是因为 `default_state` 可能已经等同于 "无 cycle hint" 状态（当 `show_cycle_hint = false` 时）。

### 与 40 列测试的对比

| 测试用例 | 宽度 | 显示内容 |
|----------|------|----------|
| `footer_collapse_plan_queue_message_without_context` | 40 列 | "tab to queue message · Plan mode" |
| `footer_collapse_plan_queue_short_without_context` | 30 列 | "tab to queue · Plan mode" |

40 列足够显示完整 hint，30 列需要缩短版。

## 风险、边界与改进建议

### 边界情况

1. **临界宽度**：
   - 约 38 列是完整 hint 与缩短版的分界线
   - 这个值取决于 "Plan mode" 的长度和缩进大小

2. **模式名称长度影响**：
   - "Plan mode"（9 字符）较短
   - "Pair Programming mode"（21 字符）较长
   - 后者在 30 列下可能需要进一步缩短或隐藏

### 潜在风险

1. **硬编码的缩短阈值**：
   - 缩短版 "tab to queue" 是硬编码的
   - 没有根据实际宽度动态计算缩短程度

2. **状态爆炸**：
   - 如果有更多的 hint 类型和模式，状态组合会快速增长
   - 维护成本增加

3. **测试覆盖**：
   - 目前的测试用例覆盖了特定宽度（30、40、50、120）
   - 缺乏对临界宽度的精确测试

### 改进建议

1. **动态缩短算法**：
   ```rust
   fn calculate_optimal_layout(
       available_width: u16,
       hint: &str,
       mode: &str,
       context: &str,
   ) -> Layout {
       // 1. 尝试完整显示
       // 2. 尝试缩短 hint
       // 3. 尝试隐藏 context
       // 4. 尝试组合优化
       // 返回最优布局
   }
   ```

2. **宽度缓存**：
   - 缓存各状态的计算宽度，避免重复测量
   - 在文本内容不变时复用缓存值

3. **更细粒度的缩短**：
   - 支持多级缩短：完整 → 半缩短 → 最小
   - 使用动态规划找到最优缩短组合

4. **可视化测试工具**：
   - 提供一个工具，可以在不同宽度下预览 footer 显示效果
   - 帮助开发者理解折叠行为

5. **自动化临界值检测**：
   - 自动计算各状态转换的临界宽度
   - 生成对应的测试用例
