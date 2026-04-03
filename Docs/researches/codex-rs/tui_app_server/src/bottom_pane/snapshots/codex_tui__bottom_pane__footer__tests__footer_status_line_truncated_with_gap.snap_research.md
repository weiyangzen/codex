# footer_status_line_truncated_with_gap 测试研究文档

## 1. 场景与职责

该测试验证当状态行内容过长且终端宽度有限时，状态行会被截断并在右侧保留模式指示器。这是 TUI 应用底部状态栏在窄终端环境下的自适应布局场景。

**使用场景**：
- 用户启用了 `/statusline` 配置功能
- 状态行内容较长
- 终端宽度有限（40列）
- 需要同时显示状态行和协作模式指示器（Plan mode）
- 验证截断和布局的优先级处理

## 2. 功能点目的

**测试目标**：验证在窄终端（40列）下，状态行内容会被截断（显示省略号），同时保留右侧的模式指示器，并在两者之间保持适当间隙。

**预期行为**：
- 状态行内容被截断为 "Status line content that …"
- 右侧显示 "Plan mode"
- 状态行和模式指示器之间保持最小间隙
- 验证 `truncate_line_with_ellipsis_if_overflow` 函数的正确性

## 3. 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/bottom_pane/footer.rs` 行 1610-1632

### 关键测试逻辑
```rust
let props = FooterProps {
    mode: FooterMode::ComposerEmpty,
    esc_backtrack_hint: false,
    use_shift_enter_hint: false,
    is_task_running: false,
    collaboration_modes_enabled: true,
    is_wsl: false,
    quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
    context_window_percent: Some(50),
    context_window_used_tokens: None,
    status_line_value: Some(Line::from(
        "Status line content that should truncate before the mode indicator".to_string()
    )),  // 长状态行内容
    status_line_enabled: true,
    active_agent_label: None,
};

snapshot_footer_with_mode_indicator(
    "footer_status_line_truncated_with_gap",
    40,  // 窄终端宽度
    &props,
    Some(CollaborationModeIndicator::Plan),  // 协作模式指示器
);
```

### 截断逻辑
```rust
let mut truncated_status_line = if status_line_active
    && matches!(props.mode, FooterMode::ComposerEmpty | FooterMode::ComposerHasDraft)
{
    passive_status_line
        .as_ref()
        .map(|line| line.clone().dim())
        .map(|line| truncate_line_with_ellipsis_if_overflow(line, available_width))
} else {
    None
};
```

### 布局计算
```rust
let right_line = if status_line_active {
    let full = mode_indicator_line(collaboration_mode_indicator, show_cycle_hint);
    let compact = mode_indicator_line(collaboration_mode_indicator, false);
    let full_width = full.as_ref().map(|line| line.width() as u16).unwrap_or(0);
    if can_show_left_with_context(area, left_width, full_width) {
        full
    } else {
        compact  // 空间不足时使用紧凑模式
    }
} else {
    // ...
};
```

## 4. 关键代码路径与文件引用

### 核心文件
- `codex-rs/tui_app_server/src/bottom_pane/footer.rs` - 底部状态栏主实现
- `codex-rs/tui_app_server/src/bottom_pane/snapshots/codex_tui__bottom_pane__footer__tests__footer_status_line_truncated_with_gap.snap` - 预期快照
- `codex-rs/tui_app_server/src/line_truncation.rs` - 行截断工具

### 关键函数
- `truncate_line_with_ellipsis_if_overflow()` - 行截断函数
- `max_left_width_for_right()` - 行 504-516，计算左侧最大宽度
- `can_show_left_with_context()` - 行 518-527，判断是否能同时显示
- `right_aligned_x()` - 行 481-502，计算右侧内容位置

### 间隙常量
```rust
const FOOTER_CONTEXT_GAP_COLS: u16 = 1;  // 左右内容之间的最小间隙
const FOOTER_INDENT_COLS: usize = 2;      // 左侧缩进
```

## 5. 依赖与外部交互

### 截断依赖
- `crate::line_truncation::truncate_line_with_ellipsis_if_overflow` - 截断实现
- 使用 "…"（Unicode 省略号）作为截断标记

### 布局依赖
- `max_left_width_for_right()` - 计算左侧内容的最大允许宽度
- `right_aligned_x()` - 计算右侧内容的起始位置

### 模式指示器
- `CollaborationModeIndicator::Plan` - 计划模式
- `mode_indicator_line()` - 构建模式指示器行

## 6. 风险、边界与改进建议

### 潜在风险
1. **信息截断过度**：过长的状态行在窄终端下可能只显示少量信息
2. **省略号识别**：用户可能不理解 "…" 表示内容被截断
3. **间隙计算错误**：间隙计算不当可能导致内容重叠或空间浪费

### 边界情况
1. **极限窄终端**：40列以下的终端（如 20-30 列）的行为未测试
2. **状态行刚好填满**：状态行长度刚好等于可用宽度的边界情况
3. **模式指示器过长**：如果模式名称很长（如 "Pair Programming mode"），截断行为如何

### 改进建议
1. **添加工具提示**：当状态行被截断时，hover 显示完整内容
2. **动态优先级**：在极端窄终端下，考虑隐藏模式指示器以保留更多状态行空间
3. **增加边界测试**：
   - `footer_status_line_very_narrow` - 30列以下的行为
   - `footer_status_line_exact_fit` - 刚好填满的边界
   - `footer_status_line_long_mode_name` - 长模式名称的处理
4. **可配置截断位置**：允许用户选择从左侧或右侧截断
5. **响应式布局**：根据终端宽度动态调整左右内容的优先级

### 性能考虑
- 截断计算在每次渲染时执行，频繁调整终端大小时可能影响性能
- 建议对截断结果进行缓存，仅在内容或宽度变化时重新计算

### 可访问性改进
- 考虑为屏幕阅读器提供完整的状态行内容，不受截断影响
- 添加键盘快捷键展开被截断的状态行
