# Footer Collapse Plan Queue Short With Context - Research Document

## 场景与职责

该快照展示了 TUI 底部状态栏在**中等偏窄终端**（50 列）下的智能折叠策略。当终端宽度不足以显示完整的队列提示时，系统会缩短 hint 文本，同时保留右侧的上下文信息，实现信息密度与可读性的平衡。

**场景条件：**
- 终端宽度：50 列（中等偏窄）
- 输入框有内容（"Test"）
- 任务正在运行（`is_task_running = true`）
- 协作模式开启且处于 Plan 模式
- 上下文窗口使用率：98%

**显示结果**：缩短的 queue hint + Plan mode + context

## 功能点目的

该功能实现了 footer 的**智能缩短**策略：

1. **文本压缩**：
   - 完整版："tab to queue message"（19 字符）
   - 缩短版："tab to queue"（12 字符）
   - 节省 7 个字符的空间

2. **信息保留**：
   - 保留核心操作提示（Tab 键）
   - 保留核心操作（queue）
   - 保留协作模式指示
   - 保留上下文状态

**显示内容：**
```
  tab to queue · Plan mode      98% context left
```

## 具体技术实现

### 缩短版 Hint 定义

**`SummaryHintKind::QueueShort`**（footer.rs:257-263）：
```rust
enum SummaryHintKind {
    None,
    Shortcuts,
    QueueMessage,  // "tab to queue message"
    QueueShort,    // "tab to queue"
}
```

**`left_side_line` 中的处理**（footer.rs:282-289）：
```rust
match state.hint {
    SummaryHintKind::QueueMessage => {
        line.push_span(key_hint::plain(KeyCode::Tab));
        line.push_span(" to queue message".dim());
    }
    SummaryHintKind::QueueShort => {
        line.push_span(key_hint::plain(KeyCode::Tab));
        line.push_span(" to queue".dim());
    }
    // ...
}
```

### 缩短策略的应用

**`single_line_footer_layout` 中的 queue 状态序列**（footer.rs:350-360）：
```rust
let queue_states = [
    default_state,  // QueueMessage + show_cycle_hint
    LeftSideState {
        hint: SummaryHintKind::QueueMessage,
        show_cycle_hint: false,
    },
    LeftSideState {
        hint: SummaryHintKind::QueueShort,
        show_cycle_hint: false,
    },
];
```

系统会依次尝试这三个状态，直到找到能容纳的组合。

### 宽度计算

在 50 列宽度下：
- 完整版："  tab to queue message · Plan mode" ≈ 38 列
- 右侧："98% context left" ≈ 16 列
- 间隙 + 缩进：3 列
- 总计：57 列 > 50 列（无法容纳完整版）

缩短版：
- "  tab to queue · Plan mode" ≈ 31 列
- 右侧 + 间隙 + 缩进：19 列
- 总计：50 列（刚好容纳）

## 关键代码路径与文件引用

### 核心代码

| 代码段 | 位置 | 说明 |
|--------|------|------|
| `SummaryHintKind` 定义 | footer.rs:257-263 | Hint 类型枚举，包含缩短版 |
| `left_side_line` hint 处理 | footer.rs:282-289 | 根据 hint 类型构建不同文本 |
| `queue_states` 数组 | footer.rs:350-360 | 定义 queue hint 的回退序列 |
| Pass 1 逻辑 | footer.rs:365-378 | 尝试保留 context 的组合 |

### 相关常量

| 常量 | 值 | 说明 |
|------|-----|------|
| `MODE_CYCLE_HINT` | "shift+tab to cycle" | Mode cycle hint 文本 |

### 测试代码

**测试设置**（chat_composer.rs:4881-4890）：
```rust
snapshot_composer_state_with_width(
    "footer_collapse_plan_queue_short_with_context",
    50,  // 关键：50 列宽度
    true,
    |composer| {
        setup_collab_footer(composer, 98, Some(CollaborationModeIndicator::Plan));
        composer.set_task_running(true);
        composer.set_text_content("Test".to_string(), Vec::new(), Vec::new());
    },
);
```

## 依赖与外部交互

### 缩短策略的触发条件

缩短版 hint 在以下情况下被使用：
1. `show_queue_hint = true`（任务运行中）
2. 完整版 queue hint 无法与 context 同时容纳
3. 缩短版可以容纳

### 与其他 hint 的对比

| Hint 类型 | 文本 | 长度 | 使用场景 |
|-----------|------|------|----------|
| `QueueMessage` | "tab to queue message" | 19 字符 | 宽度充足 |
| `QueueShort` | "tab to queue" | 12 字符 | 宽度受限 |
| `Shortcuts` | "? for shortcuts" | 15 字符 | 空闲状态 |

## 风险、边界与改进建议

### 边界情况

1. **缩短版的可读性**：
   - "tab to queue" 相比 "tab to queue message" 语义略弱
   - 新用户可能不理解 "queue" 的含义

2. **与其他语言的兼容性**：
   - 某些语言的缩短版可能仍然很长
   - 需要为每种语言单独设计缩短策略

### 潜在风险

1. **硬编码缩短文本**：
   - 缩短逻辑是硬编码的，缺乏灵活性
   - 如果修改了完整文本，缩短版可能不会相应调整

2. **过度缩短**：
   - 目前只有一级缩短（完整 → 缩短）
   - 对于某些极端宽度，可能需要更多级别

### 改进建议

1. **动态缩短算法**：
   ```rust
   fn shorten_text(text: &str, max_width: usize) -> String {
       if text.len() <= max_width {
           return text.to_string();
       }
       // 尝试移除修饰词
       let words: Vec<&str> = text.split_whitespace().collect();
       // 保留关键动词和名词
       // ...
   }
   ```

2. **多级缩短**：
   - 完整版："tab to queue message"
   - 一级缩短："tab to queue"
   - 二级缩短："[Tab] queue"
   - 图标版："↹ ⏵"

3. **上下文感知**：
   - 根据用户的使用历史调整 hint
   - 如果用户经常使用 queue 功能，可以显示更短的 hint

4. **国际化支持**：
   - 为每种语言定义缩短规则
   - 考虑使用缩写或图标替代文本

5. **可配置性**：
   - 允许用户选择是否启用缩短
   - 允许用户自定义缩短后的文本
