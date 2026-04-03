# Footer Collapse Modes Generic Research Template

## 场景与职责

该文档是底部栏折叠模式的通用研究模板，适用于以下快照文件：
- `footer_collapse_empty_full.snap`
- `footer_collapse_empty_mode_cycle_with_context.snap`
- `footer_collapse_empty_mode_cycle_without_context.snap`
- `footer_collapse_empty_mode_only.snap`
- `footer_collapse_plan_empty_full.snap`
- `footer_collapse_plan_empty_mode_cycle_with_context.snap`
- `footer_collapse_plan_empty_mode_cycle_without_context.snap`
- `footer_collapse_plan_empty_mode_only.snap`
- `footer_collapse_plan_queue_full.snap`
- `footer_collapse_plan_queue_message_without_context.snap`
- `footer_collapse_plan_queue_mode_only.snap`
- `footer_collapse_plan_queue_short_with_context.snap`
- `footer_collapse_plan_queue_short_without_context.snap`
- `footer_collapse_queue_full.snap`
- `footer_collapse_queue_message_without_context.snap`
- `footer_collapse_queue_mode_only.snap`
- `footer_collapse_queue_short_with_context.snap`
- `footer_collapse_queue_short_without_context.snap`

### 业务场景
- 终端宽度变化时，底部栏需要自适应调整
- 根据可用空间显示不同详细程度的信息
- 优先显示最重要的信息

## 功能点目的

### 核心功能
1. **自适应布局**：根据终端宽度调整显示内容
2. **优先级排序**：优先显示重要信息
3. **渐进式折叠**：空间不足时逐步隐藏次要信息

### 折叠级别
| 级别 | 显示内容 |
|------|----------|
| Full | 快捷键提示 + 协作模式 + 上下文 |
| Mode Cycle | 协作模式 + 循环提示 |
| Mode Only | 仅协作模式 |
| Queue Short | 缩短的队列提示 |
| None | 不显示左侧内容 |

## 具体技术实现

### 关键数据结构
```rust
pub(crate) enum SummaryHintKind {
    None,
    Shortcuts,
    QueueMessage,
    QueueShort,
}

pub(crate) struct LeftSideState {
    hint: SummaryHintKind,
    show_cycle_hint: bool,
}
```

### 折叠逻辑
```rust
pub(crate) fn single_line_footer_layout(
    area: Rect,
    context_width: u16,
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    show_cycle_hint: bool,
    show_shortcuts_hint: bool,
    show_queue_hint: bool,
) -> (SummaryLeft, bool) {
    // 尝试完整布局
    // 如果空间不足，逐步降级
    // 1. 隐藏快捷键提示
    // 2. 隐藏循环提示
    // 3. 仅显示模式
    // 4. 隐藏左侧内容
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **函数**: `single_line_footer_layout`

## 依赖与外部交互

### 内部依赖
- `single_line_footer_layout` - 折叠布局计算
- `left_side_line` - 左侧行生成

### 外部交互
- 无直接外部交互

## 风险、边界与改进建议

### 潜在风险
1. **信息丢失**：折叠后重要信息可能不可见
2. **频繁变化**：终端宽度频繁变化导致闪烁
3. **用户困惑**：用户可能不理解为什么显示内容变化

### 边界情况
1. **极窄终端**：宽度不足以显示任何内容
2. **快速调整**：快速调整大小时的性能
3. **特殊字符**：特殊字符的宽度计算

### 改进建议
1. **最小宽度保障**：确保至少显示最重要的信息
2. **过渡动画**：添加平滑的过渡效果
3. **用户提示**：当内容被折叠时显示指示器
4. **记住偏好**：记住用户的折叠偏好

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
