# footer_status_line_overrides_shortcuts 测试研究文档

## 1. 场景与职责

该测试验证当状态行功能启用时，状态行内容会覆盖默认的快捷键提示（shortcuts hint）。这是 TUI 应用底部状态栏在 `ComposerEmpty` 模式下，状态行配置与默认快捷键提示之间的优先级处理场景。

**使用场景**：
- 用户启用了 `/statusline` 配置功能
- 聊天输入框为空（`ComposerEmpty` 模式）
- 默认情况下会显示 "? for shortcuts" 提示
- 需要验证状态行是否会覆盖此提示

## 2. 功能点目的

**测试目标**：验证当 `status_line_enabled = true` 且处于 `ComposerEmpty` 模式时，状态行内容会覆盖默认的 "? for shortcuts" 快捷键提示。

**预期行为**：
- 状态行内容 "Status line content" 显示在底部
- 默认的 "? for shortcuts" 提示被隐藏
- 验证状态行优先级高于默认快捷键提示

## 3. 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/bottom_pane/footer.rs` 行 1492-1507

### 关键测试逻辑
```rust
let props = FooterProps {
    mode: FooterMode::ComposerEmpty,  // 空输入框模式
    esc_backtrack_hint: false,
    use_shift_enter_hint: false,
    is_task_running: false,
    collaboration_modes_enabled: false,
    is_wsl: false,
    quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
    context_window_percent: None,
    context_window_used_tokens: None,
    status_line_value: Some(Line::from("Status line content".to_string())),
    status_line_enabled: true,
    active_agent_label: None,
};

snapshot_footer("footer_status_line_overrides_shortcuts", props);
```

### 默认行为对比（无状态行时）
当 `status_line_enabled = false` 时，`ComposerEmpty` 模式会显示：
```
? for shortcuts  // 默认快捷键提示
```

### 覆盖机制
```rust
fn footer_from_props_lines(...) -> Vec<Line<'static>> {
    // 状态行优先检查
    if let Some(status_line) = passive_footer_status_line(props) {
        return vec![status_line.dim()];  // 直接返回，跳过后续逻辑
    }
    
    match props.mode {
        FooterMode::ComposerEmpty => {
            // 默认情况下显示 shortcuts hint
            let state = LeftSideState {
                hint: SummaryHintKind::Shortcuts,  // "? for shortcuts"
                show_cycle_hint,
            };
            vec![left_side_line(collaboration_mode_indicator, state)]
        }
        // ...
    }
}
```

## 4. 关键代码路径与文件引用

### 核心文件
- `codex-rs/tui_app_server/src/bottom_pane/footer.rs` - 底部状态栏主实现
- `codex-rs/tui_app_server/src/bottom_pane/snapshots/codex_tui__bottom_pane__footer__tests__footer_status_line_overrides_shortcuts.snap` - 预期快照

### 关键函数
- `passive_footer_status_line()` - 行 638-659
- `shows_passive_footer_line()` - 行 665-673
- `footer_from_props_lines()` - 行 580-631
- `left_side_line()` - 行 271-300，构建左侧提示行

### 提示类型定义
```rust
enum SummaryHintKind {
    None,
    Shortcuts,       // "? for shortcuts"
    QueueMessage,    // "tab to queue message"
    QueueShort,      // "tab to queue"
}
```

## 5. 依赖与外部交互

### 快捷键系统
- `key_hint::plain(KeyCode::Char('?'))` - "?" 键提示
- `SummaryHintKind::Shortcuts` - 快捷键提示类型

### 状态交互
- `FooterMode::ComposerEmpty` - 触发 shortcuts hint 的模式
- `status_line_enabled` - 覆盖开关

### 样式处理
- 状态行使用 `.dim()` 样式渲染
- 快捷键提示也使用暗淡样式

## 6. 风险、边界与改进建议

### 潜在风险
1. **新用户引导缺失**：快捷键提示被覆盖后，新用户可能不知道如何查看帮助
2. **发现性降低**："? for shortcuts" 是发现其他功能的主要入口，隐藏后影响用户体验
3. **配置误用**：用户可能无意中启用状态行而不知道会隐藏快捷键提示

### 边界情况
1. **状态行内容提示快捷键**：如果状态行内容本身包含快捷键提示信息，可能造成重复
2. **动态状态行**：状态行内容动态变化时，用户可能错过快捷键提示
3. **终端宽度限制**：窄终端下状态行和快捷键提示的空间竞争

### 改进建议
1. **保留提示选项**：添加配置选项允许同时显示状态行和快捷键提示
2. **智能布局**：在宽度充足时，状态行显示在左侧，快捷键提示显示在右侧
3. **首次使用提示**：新用户首次使用时，即使启用了状态行也短暂显示快捷键提示
4. **增加对比测试**：
   - `footer_shortcuts_without_status_line` - 纯快捷键提示显示
   - `footer_status_line_and_shortcuts_narrow` - 窄终端下的竞争
5. **文档改进**：在状态行配置文档中明确说明会覆盖快捷键提示
6. **替代发现机制**：考虑在界面其他位置添加快捷键发现入口，如标题栏或菜单

### 用户体验建议
- 考虑在状态行右侧添加一个小提示图标，hover 或点击时显示快捷键
- 提供 `/shortcuts` 命令作为 "?" 的替代入口
