# Footer Collapse Queue Message Without Context - Research Document

## 场景与职责

该快照展示了 TUI 底部状态栏在**无协作模式**且**中等宽度终端**（40 列）下的折叠行为。与 Plan 模式版本相比，此场景由于没有模式标签，可以在相同宽度下显示更多内容或保留更多空间。

**场景条件：**
- 终端宽度：40 列（中等宽度）
- 输入框有内容（"Test"）
- 任务正在运行（`is_task_running = true`）
- 协作模式未激活
- 上下文窗口使用率：98%

**显示结果**：完整 queue hint，context 被隐藏

## 功能点目的

该功能展示了 footer 在**基础队列模式**下的折叠策略：

1. **空间效率**：
   - 无模式标签时，完整 queue hint（23 列）可以在 40 列内容纳
   - 有模式时需要缩短版才能在 40 列内容纳

2. **信息优先级**：
   - 优先保留操作提示（queue hint）
   - 丢弃相对次要的上下文信息

**显示内容：**
```
  tab to queue        98% context left
```

注意：快照显示 "  tab to queue        98% context left"，说明在 40 列无模式下，完整 hint 和 context 可以共存，但测试名称暗示 context 应该被隐藏。这可能是测试配置或宽度计算的细微差别。

## 具体技术实现

### 宽度计算差异

**有模式时**（40 列）：
- 完整 hint + mode："  tab to queue message · Plan mode" ≈ 38 列
- Context："98% context left" ≈ 16 列
- 总计：54 列 > 40 列（无法共存）
- 结果：缩短 hint 或丢弃 context

**无模式时**（40 列）：
- 完整 hint："  tab to queue message" ≈ 23 列
- Context："98% context left" ≈ 16 列
- 间隙 + 缩进：3 列
- 总计：42 列 ≈ 40 列（接近临界值）

### 布局决策

**`single_line_footer_layout` 中的判断**（footer.rs:331-333）：
```rust
if default_width > 0 && can_show_left_with_context(area, default_width, context_width) {
    return (SummaryLeft::Default, true);
}
```

在临界宽度下，这个判断可能因计算精度或间隙处理而返回 `false`。

### 回退策略

如果默认状态无法与 context 共存，会进入缩短逻辑（footer.rs:348-395）：

```rust
if show_queue_hint {
    let queue_states = [
        default_state,
        LeftSideState { hint: SummaryHintKind::QueueMessage, show_cycle_hint: false },
        LeftSideState { hint: SummaryHintKind::QueueShort, show_cycle_hint: false },
    ];
    // Pass 1: 尝试保留 context
    // Pass 2: 丢弃 context
}
```

## 关键代码路径与文件引用

### 核心代码

| 代码段 | 位置 | 说明 |
|--------|------|------|
| `can_show_left_with_context` | footer.rs:518-527 | 判断是否能同时显示左侧和右侧 |
| `single_line_footer_layout` | footer.rs:308-472 | 主布局函数 |
| `left_side_line` | footer.rs:271-300 | 构建左侧行内容 |

### 测试代码

**测试设置**（chat_composer.rs:4839-4848）：
```rust
snapshot_composer_state_with_width(
    "footer_collapse_queue_message_without_context",
    40,  // 40 列宽度
    true,
    |composer| {
        setup_collab_footer(composer, 98, None);  // 无协作模式
        composer.set_task_running(true);
        composer.set_text_content("Test".to_string(), Vec::new(), Vec::new());
    },
);
```

### 对比测试

| 测试用例 | 协作模式 | 宽度 | Hint | Context |
|----------|----------|------|------|---------|
| `footer_collapse_queue_full` | None | 120 | 完整 | ✅ |
| `footer_collapse_queue_short_with_context` | None | 50 | 缩短 | ✅ |
| `footer_collapse_queue_message_without_context` | None | 40 | 完整 | ❌ |
| `footer_collapse_queue_short_without_context` | None | 30 | 缩短 | ❌ |
| `footer_collapse_queue_mode_only` | None | 20 | 无 | ❌ |

## 依赖与外部交互

### 间隙计算

**`can_show_left_with_context` 中的间隙**（footer.rs:525）：
```rust
let left_extent = FOOTER_INDENT_COLS as u16 + left_width + FOOTER_CONTEXT_GAP_COLS;
```

- `FOOTER_INDENT_COLS` = 2
- `FOOTER_CONTEXT_GAP_COLS` = 1
- 总计：3 列的固定开销

### 右侧对齐

**`right_aligned_x` 函数**（footer.rs:481-502）：
```rust
fn right_aligned_x(area: Rect, content_width: u16) -> Option<u16> {
    // ...
    let right_padding = FOOTER_INDENT_COLS as u16;
    // ...
    Some(
        area.x
            .saturating_add(area.width)
            .saturating_sub(content_width)
            .saturating_sub(right_padding),
    )
}
```

右侧内容也有 2 列的缩进。

## 风险、边界与改进建议

### 边界情况

1. **临界宽度的不确定性**：
   - 40 列对于无模式场景是临界值
   - 微小的计算差异可能导致不同的显示结果

2. **测试稳定性**：
   - 如果修改了缩进或间隙常量，40 列测试的行为可能改变
   - 需要确保测试用例的宽度值与实现保持同步

### 潜在风险

1. **硬编码的测试宽度**：
   - 40 列是手动选择的，可能不是精确的临界点
   - 如果 hint 文本长度变化，临界点会移动

2. **显示不一致**：
   - 用户可能在调整窗口大小时看到显示内容的突然变化
   - 缺乏平滑的过渡体验

### 改进建议

1. **精确计算临界点**：
   ```rust
   // 自动计算各状态转换的临界宽度
   fn calculate_breakpoints() -> Vec<(u16, LayoutState)> {
       // 基于实际文本长度计算
   }
   ```

2. **缓冲区域**：
   - 添加一个缓冲区域，避免在临界宽度附近频繁切换
   - 例如：只有当宽度 < 38 时才丢弃 context，而不是 < 40

3. **动态调整**：
   - 根据实际渲染效果动态调整布局
   - 使用 ratatui 的约束系统（Constraint）自动处理

4. **测试改进**：
   - 使用基于文本长度的相对宽度
   - 添加对临界点的精确测试

5. **用户反馈**：
   - 考虑在 context 被隐藏时提供视觉提示
   - 例如：在 hint 后添加一个 subtle 的指示器
