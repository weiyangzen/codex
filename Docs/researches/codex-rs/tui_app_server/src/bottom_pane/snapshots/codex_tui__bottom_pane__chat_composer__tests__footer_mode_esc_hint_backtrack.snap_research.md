# Chat Composer Footer Mode Esc Hint Backtrack Snapshot 研究文档

## 场景与职责

该快照文件测试了聊天编辑器底部栏在**Esc 回退提示模式**下的显示。当用户按下 Esc 键且启用了回退功能时，显示提示告知用户可以编辑上一条消息。

### 业务场景
- 用户按下 Esc 键
- 系统检测到可以回退到上一条消息进行编辑
- 显示 "esc again to edit previous message" 提示

### 与标准 Esc 提示的区别
- 标准 Esc 提示（无回退）："esc esc to edit previous message"
- 回退 Esc 提示（本快照）："esc again to edit previous message"

## 功能点目的

### 核心功能
1. **回退提示**：告知用户可以编辑上一条消息
2. **单键提示**：使用 "again" 而非 "esc esc"，更简洁
3. **模式切换**：从当前模式切换到 EscHint 模式

## 具体技术实现

### Esc 提示行生成
```rust
fn esc_hint_line(esc_backtrack_hint: bool) -> Line<'static> {
    let esc = key_hint::plain(KeyCode::Esc);
    if esc_backtrack_hint {
        // 本快照场景
        Line::from(vec![esc.into(), " again to edit previous message".into()]).dim()
    } else {
        Line::from(vec![
            esc.into(),
            " ".into(),
            esc.into(),
            " to edit previous message".into(),
        ])
        .dim()
    }
}
```

### Footer 模式切换
```rust
pub(crate) fn esc_hint_mode(current: FooterMode, is_task_running: bool) -> FooterMode {
    if is_task_running {
        current  // 任务运行时保持当前模式
    } else {
        FooterMode::EscHint  // 切换到 Esc 提示模式
    }
}
```

## 关键代码路径

### 主要源文件
- `codex-rs/tui/src/bottom_pane/footer.rs`
- `codex-rs/tui/src/bottom_pane/chat_composer.rs`

### 相关测试
- `footer_mode_esc_hint_backtrack` - 本快照（回退提示）
- `footer_mode_esc_hint_from_overlay` - 从覆盖层返回的 Esc 提示
- `footer_esc_hint_idle` - 空闲状态 Esc 提示
- `footer_esc_hint_primed` - 准备好的 Esc 提示
