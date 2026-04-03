# Chat Composer Footer Mode Ctrl+C Interrupt Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `chat_composer.rs` 模块的测试快照，用于验证**任务运行中按 Ctrl+C 时的底部栏状态**。当用户尝试中断正在运行的任务时，显示此提示。

### 业务场景
- 用户发送了一个长时间运行的命令（如编译、测试）
- 用户想要取消当前操作
- 系统需要确认用户意图（防止误触）

### Ctrl+C 处理流程
1. **第一次按 Ctrl+C**：显示 "ctrl + c again to quit" 提示
2. **第二次按 Ctrl+C**：实际中断任务
3. **超时**：如果在超时时间内没有第二次按键，提示消失

## 功能点目的

### 核心功能
1. **意图确认**：防止误触导致任务中断
2. **状态提示**：告知用户需要再次按键才能中断
3. **超时机制**：提示会在一段时间后自动消失

### 用户体验目标
- **防误触**：避免意外中断重要任务
- **清晰反馈**：用户明确知道系统已收到中断请求
- **快速响应**：熟悉用户可以快速双击 Ctrl+C 中断

## 具体技术实现

### 关键数据结构
```rust
pub(crate) struct ChatComposer {
    quit_shortcut_expires_at: Option<Instant>,  // 提示超时时间
    quit_shortcut_key: KeyBinding,  // Ctrl+C
    // ... 其他字段
}

pub(crate) enum FooterMode {
    QuitShortcutReminder,  // 显示 "again to quit" 提示
    // ... 其他模式
}
```

### 状态转换
```rust
fn handle_key_event(&mut self, key_event: KeyEvent) -> InputResult {
    match key_event {
        KeyEvent {
            code: KeyCode::Char('c'),
            modifiers: KeyModifiers::CONTROL,
            ..
        } => {
            if self.is_task_running {
                // 任务运行中，处理中断逻辑
                self.handle_interrupt()
            } else {
                // 空闲状态，处理退出逻辑
                self.handle_quit()
            }
        }
        // ...
    }
}

fn handle_interrupt(&mut self) -> InputResult {
    if let Some(expires_at) = self.quit_shortcut_expires_at {
        if Instant::now() < expires_at {
            // 第二次按键，确认中断
            self.app_event_tx.send(AppEvent::InterruptTask);
            self.quit_shortcut_expires_at = None;
        }
    } else {
        // 第一次按键，设置超时并显示提示
        self.quit_shortcut_expires_at = Some(
            Instant::now() + Duration::from_secs(2)
        );
        self.footer_mode = FooterMode::QuitShortcutReminder;
    }
    InputResult::None
}
```

### 底部栏渲染
```rust
fn quit_shortcut_reminder_line(key: KeyBinding) -> Line<'static> {
    Line::from(vec![key.into(), " again to quit".into()]).dim()
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
- **测试函数**: `footer_mode_ctrl_c_interrupt` (在 tests 模块中)
- **底部栏**: `footer.rs` 中的 `quit_shortcut_reminder_line`

### 渲染输出分析
```
"                                                                                                    "
"› Ask Codex to do anything                                                                          "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"  ctrl + c again to quit                                                                            "
```

- 第 9 行：中断提示（灰色）
- 提示覆盖其他底部栏内容

## 依赖与外部交互

### 内部依赖
- `FooterMode::QuitShortcutReminder` - 提示模式
- `quit_shortcut_reminder_line` - 提示行生成
- `AppEvent::InterruptTask` - 中断任务事件

### 外部交互
- **任务调度器**：接收中断信号，停止正在运行的任务
- **定时器**：管理提示超时

## 风险、边界与改进建议

### 潜在风险
1. **超时过短**：用户可能来不及第二次按键
2. **无法取消中断**：一旦第二次按键，无法撤销
3. **状态丢失**：中断可能导致未保存的工作丢失

### 边界情况
1. **快速连续按键**：处理按键防抖
2. **任务已完成**：按键时任务刚好完成的情况
3. **多个任务**：多个任务运行时的中断目标

### 改进建议
1. **可配置超时**：允许用户自定义超时时间
2. **中断确认**：对于破坏性操作，添加额外确认
3. **中断恢复**：支持恢复被中断的任务
4. **进度保存**：中断前自动保存进度
5. **视觉强调**：使用更醒目的颜色（如黄色）显示中断提示

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
- 底部栏: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
