# Chat Composer - Footer Mode Ctrl+C Interrupt 研究报告

## 1. 场景与职责

### UI场景
该快照展示了 **Chat Composer** 组件在 **Ctrl+C 中断提示模式** 下的渲染效果。当用户按下 Ctrl+C 且当前有任务正在运行时，系统会显示 "ctrl + c again to quit" 提示，告知用户再次按下 Ctrl+C 将中断当前任务。

### 组件职责
- **中断信号处理**: 捕获并处理 Ctrl+C 键盘事件
- **状态提示**: 在中断就绪状态下显示提示信息
- **双重确认**: 防止用户误触导致任务中断
- **视觉反馈**: 提供清晰的视觉反馈表明中断请求已接收

## 2. 功能点目的

### 核心功能
1. **中断就绪提示**: 告知用户再次 Ctrl+C 将中断任务
2. **防止误触**: 需要双重确认避免意外中断
3. **状态同步**: 与任务运行状态保持同步
4. **超时处理**: 提示在一段时间后自动消失

### 用户体验目标
- 防止用户意外中断正在进行的任务
- 提供清晰的反馈表明系统已接收中断请求
- 保持界面简洁，提示不干扰正常操作

## 3. 具体技术实现

### 关键数据结构

```rust
pub(crate) enum FooterMode {
    QuitShortcutReminder,  // 本场景使用
    ShortcutOverlay,
    EscHint,
    ComposerEmpty,
    ComposerHasDraft,
}

pub(crate) struct ChatComposer {
    quit_shortcut_expires_at: Option<Instant>,  // 提示过期时间
    quit_shortcut_key: KeyBinding,              // 当前提示的快捷键
    is_task_running: bool,                      // 任务运行状态
    footer_mode: FooterMode,
    // ... 其他字段
}

pub(crate) const QUIT_SHORTCUT_TIMEOUT: Duration = Duration::from_secs(1);
pub(crate) const DOUBLE_PRESS_QUIT_SHORTCUT_ENABLED: bool = false;
```

### Ctrl+C 处理流程

```rust
impl BottomPane {
    pub(crate) fn on_ctrl_c(&mut self) -> CancellationEvent {
        if let Some(view) = self.view_stack.last_mut() {
            // 优先处理活跃视图
            let event = view.on_ctrl_c();
            if matches!(event, CancellationEvent::Handled) {
                if view.is_complete() {
                    self.view_stack.pop();
                    self.on_active_view_complete();
                }
                self.show_quit_shortcut_hint(key_hint::ctrl(KeyCode::Char('c')));
                self.request_redraw();
            }
            event
        } else if self.composer_is_empty() {
            // 空输入时可能退出
            CancellationEvent::NotHandled
        } else {
            // 清除输入并显示提示
            self.view_stack.pop();
            self.clear_composer_for_ctrl_c();
            self.show_quit_shortcut_hint(key_hint::ctrl(KeyCode::Char('c')));
            self.request_redraw();
            CancellationEvent::Handled
        }
    }
    
    pub(crate) fn show_quit_shortcut_hint(&mut self, key: KeyBinding) {
        if !DOUBLE_PRESS_QUIT_SHORTCUT_ENABLED {
            return;
        }
        
        self.composer.show_quit_shortcut_hint(key, self.has_input_focus);
        
        // 安排提示过期后的重绘
        let frame_requester = self.frame_requester.clone();
        if let Ok(handle) = tokio::runtime::Handle::try_current() {
            handle.spawn(async move {
                tokio::time::sleep(QUIT_SHORTCUT_TIMEOUT).await;
                frame_requester.schedule_frame();
            });
        }
        
        self.request_redraw();
    }
}
```

### 提示显示

```rust
impl ChatComposer {
    pub(crate) fn show_quit_shortcut_hint(&mut self, key: KeyBinding, has_focus: bool) {
        if !has_focus {
            return;
        }
        self.quit_shortcut_expires_at = Some(
            Instant::now().checked_add(QUIT_SHORTCUT_TIMEOUT).unwrap_or_else(Instant::now)
        );
        self.quit_shortcut_key = key;
    }
    
    fn footer_props(&self) -> FooterProps {
        let mode = if let Some(expires_at) = self.quit_shortcut_expires_at {
            if Instant::now() < expires_at {
                FooterMode::QuitShortcutReminder
            } else {
                self.base_footer_mode()
            }
        } else {
            self.base_footer_mode()
        };
        
        FooterProps {
            mode,
            quit_shortcut_key: self.quit_shortcut_key,
            // ... 其他字段
        }
    }
}
```

### 提示行生成

```rust
fn quit_shortcut_reminder_line(key: KeyBinding) -> Line<'static> {
    Line::from(vec![key.into(), " again to quit".into()]).dim()
}

fn footer_from_props_lines(props: &FooterProps, ...) -> Vec<Line<'static>> {
    match props.mode {
        FooterMode::QuitShortcutReminder => {
            vec![quit_shortcut_reminder_line(props.quit_shortcut_key)]
        }
        // ... 其他模式
    }
}
```

## 4. 关键代码路径与文件引用

### 主要源文件
| 文件路径 | 职责 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/tui/src/bottom_pane/mod.rs` | BottomPane Ctrl+C 处理 |
| `/home/sansha/Github/codex/codex-rs/tui/src/bottom_pane/footer.rs` | 提示渲染 |
| `/home/sansha/Github/codex/codex-rs/tui/src/bottom_pane/chat_composer.rs` | ChatComposer 状态管理 |

### 关键代码路径

1. **Ctrl+C 处理**:
   ```
   mod.rs:465-486 -> on_ctrl_c()
   ```

2. **提示显示**:
   ```
   mod.rs:656-678 -> show_quit_shortcut_hint()
   ```

3. **提示行生成**:
   ```
   footer.rs:731-733 -> quit_shortcut_reminder_line()
   footer.rs:593-595 -> footer_from_props_lines() 的 QuitShortcutReminder 分支
   ```

4. **超时常量**:
   ```
   mod.rs:120 -> QUIT_SHORTCUT_TIMEOUT
   mod.rs:127 -> DOUBLE_PRESS_QUIT_SHORTCUT_ENABLED
   ```

## 5. 依赖与外部交互

### 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `crate::key_hint::KeyBinding` | 快捷键绑定表示 |
| `crate::app_event_sender::AppEventSender` | 事件发送 |
| `std::time::{Instant, Duration}` | 超时计时 |

### 外部交互

1. **帧请求**:
   ```rust
   frame_requester.schedule_frame()
   ```
   - 提示过期后请求重绘

2. **中断信号**:
   - 第二次 Ctrl+C 触发实际中断操作
   - 通过 `CancellationEvent::NotHandled` 传递给上层处理

## 6. 风险、边界与改进建议

### 潜在风险

1. **提示被忽略**:
   - 风险: 用户可能未注意到提示就再次按下 Ctrl+C
   - 缓解: 使用更显眼的样式或动画

2. **超时过短**:
   - 风险: 1 秒超时可能太短，用户来不及反应
   - 缓解: 考虑延长至 2-3 秒

3. **功能禁用**:
   - `DOUBLE_PRESS_QUIT_SHORTCUT_ENABLED = false` 表示当前禁用此功能
   - 需要确认是否计划启用

### 边界情况

1. **快速双击**:
   - 用户极快速双击 Ctrl+C 时的处理

2. **焦点丢失**:
   - 提示显示期间失去焦点时的处理

3. **任务完成**:
   - 提示显示期间任务自然完成时的清理

### 改进建议

1. **视觉增强**:
   - 建议: 使用闪烁或颜色变化增强提示可见性

2. **可配置超时**:
   - 建议: 允许用户自定义提示显示时长

3. **声音反馈**:
   - 建议: 添加可选的提示音

4. **中断确认**:
   - 建议: 对于长时间运行的任务，显示确认对话框
