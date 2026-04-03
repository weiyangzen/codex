# footer_status_line_enabled_no_mode_right 测试研究文档

## 1. 场景与职责

该测试验证当状态行功能启用但没有协作模式指示器显示时，底部状态栏的渲染行为。这是 TUI 应用底部状态栏在特定配置下的基础渲染场景。

**使用场景**：
- 用户启用了 `/statusline` 配置功能
- 当前没有激活的协作模式（如 Plan/Pair Programming/Execute）
- 终端宽度充足（120列），不需要截断处理

## 2. 功能点目的

**测试目标**：验证当 `status_line_enabled = true` 且没有协作模式指示器时，状态栏能够正确渲染，且右侧不会显示模式指示器。

**预期行为**：
- 状态行内容应该显示在底部
- 由于没有协作模式，右侧不应该显示模式标签
- 整体布局应该保持整洁，没有多余的视觉元素

## 3. 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/bottom_pane/footer.rs` 行 1587-1608

### 关键测试逻辑
```rust
let props = FooterProps {
    mode: FooterMode::ComposerEmpty,
    esc_backtrack_hint: false,
    use_shift_enter_hint: false,
    is_task_running: false,
    collaboration_modes_enabled: false,  // 协作模式未启用
    is_wsl: false,
    quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
    context_window_percent: Some(50),
    context_window_used_tokens: None,
    status_line_value: None,  // 状态行值为空
    status_line_enabled: true,  // 但状态行功能已启用
    active_agent_label: None,
};

snapshot_footer_with_mode_indicator(
    "footer_status_line_enabled_no_mode_right",
    120,  // 宽度充足
    &props,
    None,  // 无协作模式指示器
);
```

### 渲染流程
1. `draw_footer_frame` 函数根据 `FooterProps` 构建渲染状态
2. 由于 `status_line_enabled = true` 且 `status_line_value = None`，触发 `passive_footer_status_line` 逻辑
3. 没有协作模式指示器，右侧不渲染模式标签
4. 使用 `TestBackend` 捕获渲染输出进行快照比对

## 4. 关键代码路径与文件引用

### 核心文件
- `codex-rs/tui_app_server/src/bottom_pane/footer.rs` - 底部状态栏主实现
- `codex-rs/tui_app_server/src/bottom_pane/snapshots/codex_tui__bottom_pane__footer__tests__footer_status_line_enabled_no_mode_right.snap` - 预期快照

### 关键函数
- `snapshot_footer_with_mode_indicator()` - 行 1236-1246，测试辅助函数
- `draw_footer_frame()` - 行 1074-1234，渲染主逻辑
- `passive_footer_status_line()` - 行 638-659，被动状态行计算
- `uses_passive_footer_status_layout()` - 行 680-682，布局决策

### 相关结构体
```rust
pub(crate) struct FooterProps {
    pub(crate) mode: FooterMode,
    pub(crate) status_line_value: Option<Line<'static>>,
    pub(crate) status_line_enabled: bool,
    pub(crate) active_agent_label: Option<String>,
    // ... 其他字段
}
```

## 5. 依赖与外部交互

### 内部依赖
- `ratatui` - TUI 渲染框架，用于 `Buffer`、`Rect`、`Line`、`Span` 等类型
- `crossterm` - 终端控制，用于 `KeyCode`
- `insta` - 快照测试框架

### 模块依赖
- `crate::key_hint` - 键盘提示渲染
- `crate::line_truncation` - 行截断处理
- `crate::test_backend` - 测试后端支持

### 配置依赖
- 依赖 `status_line_enabled` 配置项
- 与 `collaboration_modes_enabled` 配置互斥展示

## 6. 风险、边界与改进建议

### 潜在风险
1. **空状态行显示**：当 `status_line_enabled = true` 但 `status_line_value = None` 时，可能显示空白行，影响用户体验
2. **配置不一致**：如果状态行启用但内容为空，用户可能困惑为何底部有一行空白

### 边界情况
1. **终端宽度变化**：当前测试使用 120 列宽度，未测试窄终端下的行为
2. **状态行内容为空字符串**：与 `None` 的处理是否一致需要验证
3. **与其他 FooterMode 的组合**：仅在 `ComposerEmpty` 模式下测试，其他模式行为未覆盖

### 改进建议
1. **添加窄宽度测试**：增加 40-60 列宽度的测试用例，验证截断行为
2. **明确空状态处理**：考虑在 `status_line_value` 为 `None` 或空字符串时显示默认提示
3. **增加状态行内容测试**：测试当 `status_line_value` 有实际内容时的渲染效果
4. **文档补充**：在代码注释中说明状态行启用但无内容时的预期行为
5. **交互测试**：考虑添加用户切换状态行配置后的实时更新测试

### 相关测试扩展建议
- `footer_status_line_enabled_with_content` - 有内容时的渲染
- `footer_status_line_enabled_narrow` - 窄终端下的截断
- `footer_status_line_toggle_during_session` - 会话中切换状态行
