# Footer Collapse Queue Mode Only - Research Document

## 场景与职责

该快照展示了 TUI 底部状态栏在**无协作模式**且**极窄终端**（20 列）下的极端折叠状态。与 Plan 模式版本不同，此场景由于没有模式指示器，footer 左侧会完全空白。

**场景条件：**
- 终端宽度：20 列（极窄）
- 输入框有内容（"Test"）
- 任务正在运行（`is_task_running = true`）
- 协作模式未激活（`collaboration_mode_indicator = None`）
- 上下文窗口使用率：98%

**显示结果**：仅显示 "tab to queue"，无 mode 指示器，无 context

## 功能点目的

该功能展示了 footer 在**无协作模式**下的极端折叠行为：

1. **最小可用显示**：
   - 在极窄终端中保留最核心的操作提示
   - 告知用户仍可以按 Tab 键排队消息

2. **与 Plan 模式的区别**：
   - Plan 模式版本显示 "Plan mode"
   - 无模式版本显示 "tab to queue"
   - 优先级不同：操作提示 > 模式指示

**显示内容：**
```
  tab to queue
```

## 具体技术实现

### 无模式时的折叠逻辑

**`single_line_footer_layout` 中的最终回退**（footer.rs:440-471）：

```rust
// Final fallback: if queue variants (or other earlier states) could not fit
// at all, drop every hint and try to show just the mode label.
if let Some(collaboration_mode_indicator) = collaboration_mode_indicator {
    // 尝试显示 mode 标签
    // ...
}

// 如果没有模式指示器，返回 None
(SummaryLeft::None, true)
```

**关键区别**：
- 有模式时：最终回退到仅显示 mode 标签
- 无模式时：直接返回 `SummaryLeft::None`

### 实际显示分析

根据快照内容 "  tab to queue"，看起来在 20 列无模式下，系统选择了显示缩短的 queue hint，而不是完全空白。

这可能是由于：
1. 缩短版 queue hint（"tab to queue"）约 14 列，可以在 20 列内容纳
2. 系统优先保留操作提示而非完全隐藏

### 状态回退序列

**无模式时的回退**（footer.rs:348-395）：
```rust
if show_queue_hint {
    let queue_states = [
        default_state,                                    // 完整 hint
        LeftSideState { hint: SummaryHintKind::QueueMessage, show_cycle_hint: false },
        LeftSideState { hint: SummaryHintKind::QueueShort, show_cycle_hint: false },  // 缩短
    ];
    
    // Pass 1: 尝试保留 context（失败）
    // Pass 2: 丢弃 context，尝试各状态
    // 缩短版 "tab to queue" 成功
}
```

## 关键代码路径与文件引用

### 核心代码

| 代码段 | 位置 | 说明 |
|--------|------|------|
| `single_line_footer_layout` | footer.rs:308-472 | 主布局函数 |
| `left_side_line` | footer.rs:271-300 | 构建左侧行内容 |
| `SummaryHintKind::QueueShort` | footer.rs:262 | 缩短版 queue hint |

### 有模式 vs 无模式的对比

| 场景 | 20 列显示 | 原因 |
|------|-----------|------|
| 有 Plan 模式 | "Plan mode" | 最终回退到 mode 标签 |
| 无模式 | "tab to queue" | 缩短版 hint 可以容纳 |

### 测试代码

**测试设置**（chat_composer.rs:4859-4868）：
```rust
snapshot_composer_state_with_width(
    "footer_collapse_queue_mode_only",
    20,  // 20 列极窄宽度
    true,
    |composer| {
        setup_collab_footer(composer, 98, None);  // 无协作模式
        composer.set_task_running(true);
        composer.set_text_content("Test".to_string(), Vec::new(), Vec::new());
    },
);
```

## 依赖与外部交互

### 渲染决策

**`ChatComposer` 渲染逻辑**：
```rust
let (summary_left, show_context) = single_line_footer_layout(...);

match summary_left {
    SummaryLeft::Default => {
        render_footer_from_props(...);
    }
    SummaryLeft::Custom(line) => {
        render_footer_line(area, f.buffer_mut(), line);
    }
    SummaryLeft::None => {
        // 不渲染左侧内容
    }
}

if show_context && let Some(line) = &right_line {
    render_context_right(area, f.buffer_mut(), line);
}
```

### 宽度计算

**缩短版 queue hint 宽度**：
- 缩进：2 列（`FOOTER_INDENT_COLS`）
- "tab to queue"：12 列
- 总计：14 列

这刚好可以在 20 列内容纳。

## 风险、边界与改进建议

### 边界情况

1. **更窄的终端**：
   - 如果终端宽度小于 14 列，连缩短版 hint 都无法显示
   - 此时 footer 左侧会完全空白

2. **hint 文本长度**：
   - 如果 "tab to queue" 被修改为更长的文本，20 列可能无法容纳
   - 需要同步调整测试用例

### 潜在风险

1. **有模式和无模式的行为不一致**：
   - 有模式时最终显示 mode 标签
   - 无模式时最终显示 hint 或空白
   - 用户可能在切换模式时感到困惑

2. **信息丢失**：
   - 在极窄终端中，用户看不到上下文状态
   - 可能不知道当前会话的上下文使用情况

### 改进建议

1. **统一回退策略**：
   - 无论是否有模式，都遵循相同的回退优先级
   - 例如：hint → mode → 空白

2. **最小内容保证**：
   - 定义一个最小可接受的内容集合
   - 确保在任何宽度下都显示至少一条信息

3. **自适应提示**：
   - 在极窄终端中，考虑使用更简洁的提示方式
   - 例如：图标 "↹" 代替 "tab to queue"

4. **宽度警告**：
   - 当终端宽度低于某个阈值时，显示警告或建议
   - 提示用户扩大窗口以获得更好的体验

5. **测试覆盖**：
   - 添加测试验证有模式和无模式在相同宽度下的行为
   - 确保行为符合预期且一致

6. **配置选项**：
   - 允许用户选择在空间不足时优先显示哪些信息
   - 支持自定义折叠优先级
