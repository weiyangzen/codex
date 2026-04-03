# footer_status_line_overrides_context 测试研究文档

## 1. 场景与职责

该测试验证当状态行功能启用时，状态行内容会覆盖（替代）默认的上下文信息（context window 信息）显示。这是 TUI 应用底部状态栏在状态行配置与默认信息之间的优先级处理场景。

**使用场景**：
- 用户启用了 `/statusline` 配置功能
- 状态行内容需要优先于默认的上下文使用率信息显示
- 终端处于空闲状态（`ComposerEmpty` 模式）

## 2. 功能点目的

**测试目标**：验证当 `status_line_enabled = true` 且有状态行内容时，状态行会覆盖默认的上下文信息（如 "50% context left"）。

**预期行为**：
- 状态行内容 "Status line content" 显示在底部
- 默认的上下文百分比信息（50% context left）被隐藏
- 状态行优先于上下文信息的显示逻辑

## 3. 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/bottom_pane/footer.rs` 行 1492-1507

### 关键测试逻辑
```rust
let props = FooterProps {
    mode: FooterMode::ComposerEmpty,
    esc_backtrack_hint: false,
    use_shift_enter_hint: false,
    is_task_running: false,
    collaboration_modes_enabled: false,
    is_wsl: false,
    quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
    context_window_percent: Some(50),  // 有上下文百分比
    context_window_used_tokens: None,
    status_line_value: Some(Line::from("Status line content".to_string())),  // 状态行内容
    status_line_enabled: true,  // 状态行启用
    active_agent_label: None,
};

snapshot_footer("footer_status_line_overrides_context", props);
```

### 渲染流程
1. `footer_from_props_lines()` 函数检查 `passive_footer_status_line()`
2. 由于 `shows_passive_footer_line()` 返回 `true`（`ComposerEmpty` 模式）
3. `passive_footer_status_line()` 返回状态行内容，跳过默认上下文信息显示
4. 状态行内容被渲染为暗淡样式（`.dim()`）

### 覆盖逻辑
```rust
fn footer_from_props_lines(...) -> Vec<Line<'static>> {
    // 首先检查是否有被动状态行
    if let Some(status_line) = passive_footer_status_line(props) {
        return vec![status_line.dim()];  // 直接返回状态行，覆盖其他内容
    }
    // ... 其他模式的处理
}
```

## 4. 关键代码路径与文件引用

### 核心文件
- `codex-rs/tui_app_server/src/bottom_pane/footer.rs` - 底部状态栏主实现
- `codex-rs/tui_app_server/src/bottom_pane/snapshots/codex_tui__bottom_pane__footer__tests__footer_status_line_overrides_context.snap` - 预期快照

### 关键函数
- `passive_footer_status_line()` - 行 638-659，决定是否显示被动状态行
- `shows_passive_footer_line()` - 行 665-673，判断当前模式是否允许被动状态行
- `footer_from_props_lines()` - 行 580-631，构建底部状态栏内容
- `context_window_line()` - 行 848-860，构建上下文信息行（被覆盖的目标）

### 决策逻辑
```rust
pub(crate) fn shows_passive_footer_line(props: &FooterProps) -> bool {
    match props.mode {
        FooterMode::ComposerEmpty => true,  // 空闲模式允许被动状态行
        FooterMode::ComposerHasDraft => !props.is_task_running,
        FooterMode::QuitShortcutReminder | FooterMode::ShortcutOverlay | FooterMode::EscHint => false,
    }
}
```

## 5. 依赖与外部交互

### 内部依赖
- `ratatui::text::Line` - 文本行类型
- `ratatui::style::Stylize` - 样式处理

### 状态交互
- 与 `context_window_percent` 互斥显示
- 与 `context_window_used_tokens` 互斥显示
- 受 `FooterMode` 状态控制

### 配置来源
- 状态行内容由 `/statusline` 命令配置
- 通过 `status_line_value` 字段传递

## 6. 风险、边界与改进建议

### 潜在风险
1. **信息丢失**：状态行覆盖上下文信息后，用户可能无法看到重要的上下文使用率
2. **配置冲突**：如果状态行配置不当，可能导致关键信息被隐藏
3. **状态不一致**：在任务运行期间切换状态行配置可能导致显示混乱

### 边界情况
1. **状态行内容为空字符串**：当前测试使用 "Status line content"，空字符串的处理未测试
2. **状态行内容超长**：未测试状态行内容超过终端宽度时的截断行为
3. **与 Agent Label 组合**：状态行与 `active_agent_label` 同时存在时的显示优先级

### 改进建议
1. **信息合并显示**：考虑在状态行显示的同时，以某种方式保留上下文信息
2. **配置提示**：当用户启用状态行时，提示这将覆盖默认的上下文信息显示
3. **增加组合测试**：
   - 状态行 + Agent Label 同时存在
   - 状态行内容为空或仅空白字符
   - 状态行内容包含特殊字符或 ANSI 转义序列
4. **动态切换测试**：测试在会话进行中启用/禁用状态行的行为
5. **添加优先级文档**：明确说明状态行、Agent Label、上下文信息三者的显示优先级

### 相关测试建议
- `footer_status_line_and_context_both_visible` - 测试两者同时显示的场景（如果支持）
- `footer_status_line_empty_string` - 测试空字符串状态行的处理
- `footer_status_line_with_ansi_codes` - 测试包含 ANSI 转义序列的状态行
