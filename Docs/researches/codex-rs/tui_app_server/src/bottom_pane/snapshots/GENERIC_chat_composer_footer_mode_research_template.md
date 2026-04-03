# Chat Composer Footer Mode Generic Research Template

## 场景与职责

该文档是聊天输入框底部栏模式的通用研究模板，适用于以下快照文件：
- `footer_mode_ctrl_c_quit.snap`
- `footer_mode_esc_hint_backtrack.snap`
- `footer_mode_esc_hint_from_overlay.snap`
- `footer_mode_hidden_while_typing.snap`
- `footer_mode_overlay_then_external_esc_hint.snap`

### 业务场景
- 输入框的不同状态显示不同的底部栏
- 根据用户操作和系统状态调整显示
- 提供上下文相关的提示

### 底部栏模式
| 模式 | 描述 |
|------|------|
| Ctrl+C Quit | 显示退出提示 |
| Esc Hint | 显示 Esc 提示 |
| Hidden While Typing | 输入时隐藏 |
| Overlay | 显示覆盖层 |

## 功能点目的

### 核心功能
1. **状态提示**：根据当前状态显示相关提示
2. **上下文感知**：根据用户操作调整显示
3. **防干扰**：输入时隐藏提示，减少干扰

### 用户体验目标
- **及时反馈**：用户操作后立即显示相关提示
- **不干扰**：避免在不需要时显示提示
- **一致性**：相似状态下显示一致的提示

## 具体技术实现

### 关键数据结构
```rust
pub(crate) enum FooterMode {
    QuitShortcutReminder,
    EscHint,
    ShortcutOverlay,
    ComposerEmpty,
    ComposerHasDraft,
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
- **底部栏**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`

## 依赖与外部交互

### 内部依赖
- `FooterMode` - 底部栏模式
- `ChatComposer` - 聊天输入框

### 外部交互
- 无直接外部交互

## 风险、边界与改进建议

### 潜在风险
1. **提示过多**：频繁的提示变化可能干扰用户
2. **状态混乱**：复杂状态下提示可能不清晰

### 改进建议
1. **提示优先级**：定义清晰的提示优先级
2. **用户偏好**：允许用户自定义提示行为

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
