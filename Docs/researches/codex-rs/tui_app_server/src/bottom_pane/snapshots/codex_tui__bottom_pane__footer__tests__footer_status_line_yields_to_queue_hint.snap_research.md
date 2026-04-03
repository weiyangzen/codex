# footer_status_line_yields_to_queue_hint 测试研究文档

## 1. 场景与职责

该测试验证当任务正在运行且有草稿内容时，queue hint（队列提示）会优先于状态行显示。这是 TUI 应用在任务运行期间的底部状态栏优先级处理场景。

**使用场景**：
- 用户在聊天输入框中输入了内容（有 draft）
- 当前有任务正在运行（`is_task_running = true`）
- 用户启用了 `/statusline` 配置功能
- 需要验证 queue hint 与状态行的显示优先级

## 2. 功能点目的

**测试目标**：验证当 `status_line_enabled = true` 但处于 `ComposerHasDraft` 且任务运行状态时，queue hint（"tab to queue message"）会优先显示，状态行被隐藏。

**预期行为**：
- 显示 queue hint："tab to queue message"
- 右侧显示上下文信息："100% context left"
- 状态行内容被隐藏（让位于 queue hint）
- 验证 `shows_passive_footer_line()` 在运行状态下的返回值为 `false`

## 3. 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/bottom_pane/footer.rs` 行 1509-1524

### 关键测试逻辑
```rust
let props = FooterProps {
    mode: FooterMode::ComposerHasDraft,  // 有草稿模式
    esc_backtrack_hint: false,
    use_shift_enter_hint: false,
    is_task_running: true,  // 任务正在运行
    collaboration_modes_enabled: false,
    is_wsl: false,
    quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
    context_window_percent: None,
    context_window_used_tokens: None,
    status_line_value: Some(Line::from("Status line content".to_string())),
    status_line_enabled: true,  // 状态行启用
    active_agent_label: None,
};

snapshot_footer("footer_status_line_yields_to_queue_hint", props);
```

### 优先级决策逻辑
```rust
pub(crate) fn shows_passive_footer_line(props: &FooterProps) -> bool {
    match props.mode {
        FooterMode::ComposerEmpty => true,
        FooterMode::ComposerHasDraft => !props.is_task_running,  // 关键：运行中返回 false
        FooterMode::QuitShortcutReminder | FooterMode::ShortcutOverlay | FooterMode::EscHint => false,
    }
}
```

### Queue Hint 渲染
```rust
FooterMode::ComposerHasDraft => {
    let state = LeftSideState {
        hint: if show_queue_hint {  // 运行中时为 true
            SummaryHintKind::QueueMessage  // "tab to queue message"
        } else if show_shortcuts_hint {
            SummaryHintKind::Shortcuts
        } else {
            SummaryHintKind::None
        },
        show_cycle_hint,
    };
    vec![left_side_line(collaboration_mode_indicator, state)]
}
```

## 4. 关键代码路径与文件引用

### 核心文件
- `codex-rs/tui_app_server/src/bottom_pane/footer.rs` - 底部状态栏主实现
- `codex-rs/tui_app_server/src/bottom_pane/snapshots/codex_tui__bottom_pane__footer__tests__footer_status_line_yields_to_queue_hint.snap` - 预期快照

### 关键函数
- `shows_passive_footer_line()` - 行 665-673，核心决策函数
- `footer_from_props_lines()` - 行 580-631，构建底部内容
- `left_side_line()` - 行 271-300，构建左侧提示
- `context_window_line()` - 行 848-860，构建右侧上下文信息

### 提示类型
```rust
enum SummaryHintKind {
    None,
    Shortcuts,
    QueueMessage,  // "tab to queue message"
    QueueShort,    // "tab to queue"（短版本）
}
```

## 5. 依赖与外部交互

### 任务状态
- `is_task_running` - 任务运行状态标志
- 影响 `shows_passive_footer_line()` 的返回值

### Queue 系统
- `SummaryHintKind::QueueMessage` - 完整队列提示
- `SummaryHintKind::QueueShort` - 短版本（空间不足时使用）
- `KeyCode::Tab` - 触发队列操作的按键

### 上下文信息
- `context_window_line()` - 右侧显示的上下文使用率
- 默认显示 "100% context left"

## 6. 风险、边界与改进建议

### 潜在风险
1. **状态信息丢失**：任务运行时状态行被隐藏，用户可能错过重要状态更新
2. **频繁切换**：任务频繁启动/停止时，底部显示频繁切换，造成视觉干扰
3. **Queue Hint 误解**：新用户可能不理解 "queue message" 的含义

### 边界情况
1. **任务即将完成**：任务快结束时切换显示可能造成闪烁
2. **多个任务排队**：当前测试仅涉及单个运行任务，多任务场景未覆盖
3. **Queue Hint 截断**：窄终端下 "tab to queue message" 可能被截断为 "tab to queue"

### 改进建议
1. **状态行降级显示**：考虑在 queue hint 右侧以紧凑形式显示关键状态信息
2. **平滑过渡**：任务状态变化时添加短暂过渡动画，减少闪烁感
3. **增加测试覆盖**：
   - `footer_queue_hint_narrow` - 窄终端下的截断行为
   - `footer_multiple_tasks_running` - 多任务运行场景
   - `footer_task_starting_transition` - 任务启动过渡
4. **可配置优先级**：允许高级用户配置状态行和 queue hint 的优先级
5. **Queue Hint 优化**：
   - 添加图标指示队列状态
   - 显示当前队列中的消息数量

### 用户体验改进
- 在 queue hint 旁边添加一个小指示器，提示用户可以在设置中查看状态行
- 考虑在任务完成后短暂显示状态行，让用户了解错过的信息
- 提供 `/queue` 命令查看队列状态，减少对 queue hint 的依赖

### 性能考虑
- 任务状态变化时频繁重新计算底部布局
- 建议对布局计算结果进行适当缓存
