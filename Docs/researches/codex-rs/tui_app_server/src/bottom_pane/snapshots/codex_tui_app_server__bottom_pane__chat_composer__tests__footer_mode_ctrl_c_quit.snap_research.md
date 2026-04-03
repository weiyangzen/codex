# 文件研究: footer_mode_ctrl_c_quit.snap

## 场景与职责
该快照测试验证当编辑器为空时，用户按下 Ctrl+C 触发退出提示的场景。与 `footer_mode_ctrl_c_interrupt` 不同，此测试场景针对的是正常退出应用（而非中断任务），底部状态栏显示 "ctrl + c again to quit" 提示用户再次按下以确认退出。

## 功能点目的
1. **安全退出机制**: 防止用户意外退出应用，特别是在有未保存工作的情况下
2. **一致的交互模式**: 与任务中断使用相同的"两次确认"模式，保持用户体验一致性
3. **空状态特殊处理**: 当编辑器为空时，Ctrl+C 直接触发退出提示（而非先尝试清除内容）
4. **明确的退出路径**: 通过 footer 提示明确告知用户如何完成退出操作

## 具体技术实现

### 关键流程
1. 检测编辑器为空状态：`self.is_empty()` 返回 true
2. 用户按下 Ctrl+C，进入退出提示流程
3. 调用 `show_quit_shortcut_hint(key, has_focus)` 设置提示状态
4. `footer_mode` 切换为 `FooterMode::QuitShortcutReminder`
5. 渲染时通过 `quit_shortcut_reminder_line` 生成 "ctrl + c again to quit"
6. 用户再次按下 Ctrl+C 时，实际执行退出操作

### 数据结构
```rust
// ChatComposer 中与退出提示相关的字段
pub(crate) struct ChatComposer {
    quit_shortcut_expires_at: Option<Instant>,  // 提示超时时间
    quit_shortcut_key: KeyBinding,              // 当前触发键
    footer_mode: FooterMode,                    // 当前 footer 模式
    // ...
}

// KeyBinding 结构（用于表示按键组合）
pub struct KeyBinding {
    code: KeyCode,
    modifiers: KeyModifiers,
}
```

### 协议/命令
- **退出超时常量**: `QUIT_SHORTCUT_TIMEOUT` 定义提示显示时长
- **键绑定创建**: `key_hint::ctrl(KeyCode::Char('c'))` 创建 Ctrl+C 绑定
- **渲染样式**: 使用 `.dim()` 样式使提示文本呈现暗淡效果，区别于主要内容

## 关键代码路径与文件引用
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
  - `is_empty` 方法 (行 725-729): 检查编辑器是否为空
  - `show_quit_shortcut_hint` 方法 (行 1248-1259)
  - `clear_for_ctrl_c` 方法 (行 1060-1087): 处理 Ctrl+C 清除逻辑
- **Footer 模块**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - `quit_shortcut_reminder_line` 函数 (行 731-733)
  - `FooterMode::QuitShortcutReminder` 枚举变体 (行 133-134)
- **相关测试**: `footer_mode_ctrl_c_quit`
- **调用链**: 
  - 空状态检测 → Ctrl+C 处理 → 显示退出提示 → 等待二次确认

## 依赖与外部交互
1. **编辑器状态**: 依赖 `textarea.is_empty()` 和附件状态判断空状态
2. **时间系统**: `std::time::Instant` 用于管理提示超时
3. **事件系统**: `AppEventSender` 用于发送应用级事件
4. **历史记录**: 在退出前可能需要保存当前输入到历史记录
5. **父组件协调**: `ChatWidget` 或 `BottomPane` 处理实际的退出逻辑

## 风险、边界与改进建议

### 风险点
1. **状态误判**: 如果 `is_empty()` 判断不准确，可能导致非空内容被意外清除
2. **快捷键冲突**: 某些终端可能拦截 Ctrl+C 用于复制操作
3. **超时过短**: 用户可能来不及阅读提示就超时消失

### 边界条件
1. **内容变化**: 在显示退出提示期间，如果用户开始输入，提示应立即清除
2. **焦点丢失**: 失去焦点时应清除退出提示状态
3. **多编辑器场景**: 如果有多个编辑器实例，需要确保状态隔离

### 改进建议
1. **智能检测**: 考虑检测是否有未提交的更改，而不仅仅是检查空状态
2. **自定义快捷键**: 允许用户自定义退出快捷键，避免与系统快捷键冲突
3. **渐进式提示**: 首次显示完整提示，后续显示简化版本
4. **撤销支持**: 如果用户意外退出，提供快速恢复上次会话的机制
5. **无障碍支持**: 为屏幕阅读器添加适当的 ARIA 标签或等效提示
