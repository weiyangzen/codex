# 文件研究: footer_mode_ctrl_c_interrupt.snap

## 场景与职责
该快照测试验证当用户按下 Ctrl+C 尝试中断正在运行的任务时，底部状态栏(footer)正确显示"ctrl + c again to quit"提示信息的场景。这是 TUI 应用中处理任务中断时的用户交互反馈机制，确保用户在执行中断操作前得到明确的视觉确认提示。

## 功能点目的
1. **防止误操作**: 避免用户意外中断正在进行的任务
2. **二次确认机制**: 要求用户连续两次按下 Ctrl+C 才执行退出/中断操作
3. **视觉反馈**: 在 footer 区域显示明确的提示文本，告知用户需要再次按下 Ctrl+C 才能退出
4. **状态同步**: 确保 footer 模式状态与实际的 quit shortcut 计时器状态保持一致

## 具体技术实现

### 关键流程
1. 用户首次按下 Ctrl+C 时，`show_quit_shortcut_hint` 方法被调用
2. 设置 `quit_shortcut_expires_at` 为当前时间 + `QUIT_SHORTCUT_TIMEOUT`（超时时间）
3. 将 `footer_mode` 设置为 `FooterMode::QuitShortcutReminder`
4. 记录触发快捷键 `quit_shortcut_key`（此处为 Ctrl+C）
5. 渲染时，`footer_from_props_lines` 函数根据 `FooterMode::QuitShortcutReminder` 生成提示行
6. `quit_shortcut_reminder_line` 函数格式化输出 "ctrl + c again to quit"

### 数据结构
```rust
// FooterMode 枚举定义
pub(crate) enum FooterMode {
    QuitShortcutReminder,  // 显示"再次按下以退出"提示
    ShortcutOverlay,       // 显示快捷键帮助覆盖层
    EscHint,              // 显示 Esc 提示
    ComposerEmpty,        // 编辑器为空状态
    ComposerHasDraft,     // 编辑器有草稿状态
}

// FooterProps 结构体
pub(crate) struct FooterProps {
    pub(crate) mode: FooterMode,
    pub(crate) quit_shortcut_key: KeyBinding,  // 记录触发退出的快捷键
    // ... 其他字段
}
```

### 协议/命令
- **快捷键绑定**: `key_hint::ctrl(KeyCode::Char('c'))` 定义 Ctrl+C 绑定
- **超时机制**: `QUIT_SHORTCUT_TIMEOUT` 控制提示显示时长
- **渲染表达式**: `quit_shortcut_reminder_line(props.quit_shortcut_key)` 生成提示文本

## 关键代码路径与文件引用
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
  - `show_quit_shortcut_hint` 方法 (行 1248-1259)
  - `clear_quit_shortcut_hint` 方法 (行 1262-1266)
  - `quit_shortcut_hint_visible` 方法 (行 1273-1276)
- **Footer 渲染**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - `quit_shortcut_reminder_line` 函数 (行 731-733)
  - `footer_from_props_lines` 函数 (行 580-631)
- **相关测试**: `footer_mode_ctrl_c_interrupt`
- **调用链**: 
  - 按键事件 → `handle_key_event_without_popup` → `show_quit_shortcut_hint` → Footer 渲染更新

## 依赖与外部交互
1. **时间系统**: 依赖 `std::time::Instant` 和 `Duration` 实现超时机制
2. **键盘事件**: 通过 `crossterm::event::KeyEvent` 接收 Ctrl+C 按键
3. **渲染系统**: 使用 `ratatui` 库渲染 footer 提示文本
4. **状态管理**: 与 `ChatComposer` 的状态机紧密集成
5. **父级组件**: `BottomPane` 或 `ChatWidget` 负责调度重绘以处理超时消失

## 风险、边界与改进建议

### 风险点
1. **超时竞态条件**: 如果用户在超时边缘快速按键，可能出现状态不一致
2. **多快捷键冲突**: 如果同时支持 Ctrl+C 和 Ctrl+D 作为退出键，需要确保提示文本正确反映实际按键
3. **渲染闪烁**: 在快速切换 footer 模式时可能出现视觉闪烁

### 边界条件
1. **超时过期**: 当 `quit_shortcut_expires_at` 过期后，提示应自动消失
2. **焦点变化**: 当 composer 失去焦点时，提示状态需要正确处理
3. **任务状态变化**: 如果任务在显示提示期间完成，提示应立即清除

### 改进建议
1. **可配置超时**: 考虑将 `QUIT_SHORTCUT_TIMEOUT` 设为用户可配置项
2. **音效反馈**: 在显示提示时添加可选的音效反馈，增强可访问性
3. **视觉区分**: 对不同类型的退出提示（中断 vs 完全退出）使用不同的颜色或图标
4. **国际化**: 当前提示文本为硬编码英文，应支持多语言本地化
