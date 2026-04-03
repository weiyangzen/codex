# footer_status_line_overrides_draft_idle 测试研究文档

## 1. 场景与职责

该测试验证当用户在输入框中有草稿内容（draft）但任务未运行时，状态行功能如何覆盖默认的草稿提示。这是 TUI 应用在 `ComposerHasDraft` 模式下且空闲状态时的底部状态栏渲染场景。

**使用场景**：
- 用户在聊天输入框中输入了内容（有 draft）
- 当前没有任务在运行（idle 状态）
- 用户启用了 `/statusline` 配置功能
- 需要验证状态行是否会覆盖默认的草稿相关提示

## 2. 功能点目的

**测试目标**：验证当 `status_line_enabled = true` 且处于 `ComposerHasDraft` 空闲状态时，状态行内容会覆盖默认的草稿提示信息。

**预期行为**：
- 状态行内容 "Status line content" 显示在底部
- 默认的草稿提示（如 "? for shortcuts" 或 queue hint）被隐藏
- 验证 `shows_passive_footer_line()` 在 `ComposerHasDraft` 且非运行状态下的返回值为 `true`

## 3. 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/bottom_pane/footer.rs` 行 1526-1541

### 关键测试逻辑
```rust
let props = FooterProps {
    mode: FooterMode::ComposerHasDraft,  // 有草稿模式
    esc_backtrack_hint: false,
    use_shift_enter_hint: false,
    is_task_running: false,  // 任务未运行（空闲）
    collaboration_modes_enabled: false,
    is_wsl: false,
    quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
    context_window_percent: None,
    context_window_used_tokens: None,
    status_line_value: Some(Line::from("Status line content".to_string())),
    status_line_enabled: true,
    active_agent_label: None,
};

snapshot_footer("footer_status_line_overrides_draft_idle", props);
```

### 关键决策逻辑
```rust
pub(crate) fn shows_passive_footer_line(props: &FooterProps) -> bool {
    match props.mode {
        FooterMode::ComposerEmpty => true,
        FooterMode::ComposerHasDraft => !props.is_task_running,  // 关键条件
        FooterMode::QuitShortcutReminder | FooterMode::ShortcutOverlay | FooterMode::EscHint => false,
    }
}
```

### 渲染流程
1. 检查 `mode` 为 `ComposerHasDraft` 且 `is_task_running = false`
2. `shows_passive_footer_line()` 返回 `true`
3. `passive_footer_status_line()` 返回配置的状态行内容
4. 状态行覆盖默认的草稿提示（如 shortcuts hint）

## 4. 关键代码路径与文件引用

### 核心文件
- `codex-rs/tui_app_server/src/bottom_pane/footer.rs` - 底部状态栏主实现
- `codex-rs/tui_app_server/src/bottom_pane/snapshots/codex_tui__bottom_pane__footer__tests__footer_status_line_overrides_draft_idle.snap` - 预期快照

### 关键函数
- `shows_passive_footer_line()` - 行 665-673，核心决策函数
- `passive_footer_status_line()` - 行 638-659，构建被动状态行
- `footer_from_props_lines()` - 行 580-631，构建底部内容

### 模式相关代码
```rust
FooterMode::ComposerHasDraft => {
    let state = LeftSideState {
        hint: if show_queue_hint {  // 通常在有草稿且运行中显示
            SummaryHintKind::QueueMessage
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

## 5. 依赖与外部交互

### 状态依赖
- `FooterMode::ComposerHasDraft` - 草稿模式
- `is_task_running: false` - 空闲状态

### 互斥显示
- 状态行 vs shortcuts hint（"? for shortcuts"）
- 状态行 vs queue hint（当运行中时会显示）

### 配置依赖
- `status_line_enabled` 必须设为 `true`
- `status_line_value` 必须有内容

## 6. 风险、边界与改进建议

### 潜在风险
1. **用户提示丢失**：草稿模式下用户可能需要 "? for shortcuts" 提示，被状态行覆盖后可能不知道如何操作
2. **状态切换闪烁**：从运行状态切换到空闲状态时，底部显示可能从 queue hint 突然变为状态行，造成视觉跳跃
3. **信息密度降低**：状态行可能不包含操作提示信息，降低用户体验

### 边界情况
1. **草稿为空字符串**：与 `ComposerEmpty` 的边界模糊
2. **任务刚结束**：任务结束瞬间的状态转换处理
3. **状态行内容变化**：动态更新的状态行内容是否及时反映

### 改进建议
1. **组合显示模式**：考虑在状态行右侧或下方保留关键操作提示
2. **过渡动画**：状态切换时添加平滑过渡，减少视觉跳跃
3. **增加对比测试**：
   - `footer_draft_idle_no_status_line` - 无状态行时的默认显示
   - `footer_draft_running_with_status_line` - 运行中时的行为对比
4. **用户可配置优先级**：允许用户选择状态行和操作提示的显示优先级
5. **智能提示合并**：如果状态行内容较短，在右侧保留关键提示

### 相关测试扩展
- 测试状态行内容与草稿提示同时显示的布局
- 测试从运行到空闲状态转换时的显示变化
- 测试状态行动态更新时的渲染性能
