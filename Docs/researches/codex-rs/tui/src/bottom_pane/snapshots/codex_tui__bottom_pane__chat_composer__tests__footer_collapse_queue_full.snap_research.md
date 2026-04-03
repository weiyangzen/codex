# Footer Collapse Queue Full - Research Document

## 场景与职责

该快照展示了 TUI 底部状态栏在**无协作模式**情况下的完整显示状态。与 Plan 模式版本相比，此场景仅显示队列提示和上下文信息，不包含模式指示器。

**场景条件：**
- 终端宽度：120 列（较宽）
- 输入框有内容（"Test"）
- 任务正在运行（`is_task_running = true`）
- 协作模式未激活（`collaboration_mode_indicator = None`）
- 上下文窗口使用率：98%

**显示结果**：完整 queue hint + context，无 mode 指示器

## 功能点目的

该功能展示了 footer 在**基础队列模式**下的显示：

1. **核心操作提示**：
   - 告知用户可以按 Tab 键将消息排队
   - 这是任务运行时最重要的交互提示

2. **上下文状态**：
   - 显示剩余上下文百分比
   - 帮助用户了解当前会话状态

3. **简洁性**：
   - 无协作模式时，footer 更简洁
   - 减少视觉干扰

**显示内容：**
```
  tab to queue message                                                                                98% context left
```

## 具体技术实现

### 无模式时的布局逻辑

**`single_line_footer_layout` 入口**（footer.rs:310-333）：
```rust
pub(crate) fn single_line_footer_layout(
    area: Rect,
    context_width: u16,
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    show_cycle_hint: bool,
    show_shortcuts_hint: bool,
    show_queue_hint: bool,
) -> (SummaryLeft, bool) {
    let hint_kind = if show_queue_hint {
        SummaryHintKind::QueueMessage
    } else if show_shortcuts_hint {
        SummaryHintKind::Shortcuts
    } else {
        SummaryHintKind::None
    };
    let default_state = LeftSideState { hint: hint_kind, show_cycle_hint };
    let default_line = left_side_line(collaboration_mode_indicator, default_state);
    // ...
}
```

当 `collaboration_mode_indicator = None` 时，`left_side_line` 只构建 hint 部分。

### `left_side_line` 处理

**无模式时的行为**（footer.rs:271-300）：
```rust
fn left_side_line(
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    state: LeftSideState,
) -> Line<'static> {
    let mut line = Line::from("");
    
    // 添加 hint
    match state.hint {
        SummaryHintKind::QueueMessage => {
            line.push_span(key_hint::plain(KeyCode::Tab));
            line.push_span(" to queue message".dim());
        }
        // ...
    };

    // 只有当有模式指示器时才添加分隔符和模式标签
    if let Some(collaboration_mode_indicator) = collaboration_mode_indicator {
        if !matches!(state.hint, SummaryHintKind::None) {
            line.push_span(" · ".dim());
        }
        line.push_span(collaboration_mode_indicator.styled_span(state.show_cycle_hint));
    }

    line
}
```

### 宽度优势

无模式时的宽度需求：
- 有模式："  tab to queue message · Plan mode" ≈ 38 列
- 无模式："  tab to queue message" ≈ 23 列

节省了约 15 列的空间，使得在更窄的终端下也能显示完整内容。

## 关键代码路径与文件引用

### 核心代码

| 代码段 | 位置 | 说明 |
|--------|------|------|
| `single_line_footer_layout` | footer.rs:308-472 | 主布局函数 |
| `left_side_line` | footer.rs:271-300 | 构建左侧行内容 |
| `SummaryHintKind` 定义 | footer.rs:257-263 | Hint 类型枚举 |

### 测试代码

**测试设置**（chat_composer.rs:4824-4828）：
```rust
snapshot_composer_state_with_width("footer_collapse_queue_full", 120, true, |composer| {
    setup_collab_footer(composer, 98, None);  // None = 无协作模式
    composer.set_task_running(true);
    composer.set_text_content("Test".to_string(), Vec::new(), Vec::new());
});
```

### 与 Plan 模式的对比

| 场景 | 协作模式 | 显示内容 |
|------|----------|----------|
| `footer_collapse_queue_full` | None | "tab to queue message" + context |
| `footer_collapse_plan_queue_full` | Plan | "tab to queue message · Plan mode" + context |

## 依赖与外部交互

### 模式指示器的可选性

**`CollaborationModeIndicator` 枚举**（footer.rs:89-96）：
```rust
pub(crate) enum CollaborationModeIndicator {
    Plan,
    #[allow(dead_code)]
    PairProgramming,
    #[allow(dead_code)]
    Execute,
}
```

注意 `PairProgramming` 和 `Execute` 目前标记为 `#[allow(dead_code)]`，说明当前 UI 主要使用 Plan 模式。

### 颜色方案

**各模式的颜色**（footer.rs:117-124）：
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

1. **无模式时的折叠行为**：
   - 由于节省了模式标签的空间，无模式时的折叠阈值更低
   - 可以在更窄的终端下保留完整 hint 和 context

2. **未来模式扩展**：
   - 如果启用 Pair Programming 或 Execute 模式，需要测试其显示效果
   - "Pair Programming mode" 较长，可能需要特殊处理

### 潜在风险

1. **代码重复**：
   - 有模式和无模式的测试用例有很多重复代码
   - 维护成本较高

2. **硬编码的 hint 文本**：
   - "tab to queue message" 是硬编码的
   - 如果未来添加其他 queue 相关功能，可能需要调整文本

### 改进建议

1. **参数化测试**：
   ```rust
   #[test_case(CollaborationModeIndicator::Plan)]
   #[test_case(None)]
   fn test_footer_collapse_full(mode: Option<CollaborationModeIndicator>) {
       // 复用测试逻辑
   }
   ```

2. **动态 hint 生成**：
   - 根据可用功能动态生成 hint 文本
   - 例如：如果有多个 queue 选项，显示 "tab to queue (options)"

3. **模式指示器优化**：
   - 为长模式名称（如 "Pair Programming"）提供缩短版
   - 考虑使用图标或缩写

4. **一致性检查**：
   - 确保有模式和无模式时的折叠行为一致
   - 添加自动化测试验证折叠阈值
