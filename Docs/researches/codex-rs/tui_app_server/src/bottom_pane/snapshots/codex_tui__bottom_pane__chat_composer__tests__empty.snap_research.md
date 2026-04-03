# Chat Composer Empty Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `chat_composer.rs` 模块的测试快照，用于验证**聊天输入框空状态**的渲染输出。这是用户打开 Codex TUI 后看到的默认输入界面。

### 业务场景
- 用户刚打开 Codex，准备输入第一条消息
- 用户发送消息后，输入框重置为空状态
- 用户取消正在输入的内容，回到空状态

### 空状态特征
- 显示占位符文本 "Ask Codex to do anything"
- 底部显示快捷键提示 "? for shortcuts"
- 右侧显示上下文剩余百分比 "100% context left"

## 功能点目的

### 核心功能
1. **占位符提示**：引导用户开始输入
2. **快捷键提示**：告知用户如何查看快捷键
3. **上下文指示**：显示当前会话的上下文使用情况
4. **就绪状态**：表明系统已准备好接收输入

### 用户体验目标
- **友好引导**：空状态不显得冷漠，而是积极邀请用户输入
- **信息丰富**：在不干扰的情况下提供有用的上下文信息
- **一致性**：与其他状态（有草稿、运行中）保持视觉一致

## 具体技术实现

### 关键数据结构
```rust
pub(crate) struct ChatComposer {
    textarea: TextArea,
    textarea_state: RefCell<TextAreaState>,
    placeholder_text: String,  // "Ask Codex to do anything"
    context_window_percent: Option<i64>,  // 上下文百分比
    context_window_used_tokens: Option<i64>,
    footer_mode: FooterMode,  // ComposerEmpty
    // ... 其他字段
}

pub(crate) enum FooterMode {
    QuitShortcutReminder,
    ShortcutOverlay,
    EscHint,
    ComposerEmpty,  // 空状态
    ComposerHasDraft,  // 有草稿状态
}
```

### 渲染流程
```rust
// 布局计算
fn layout_areas(&self, area: Rect) -> [Rect; 4] {
    let footer_props = self.footer_props();
    let footer_hint_height = footer_height(&footer_props);
    // ... 布局计算
    let [composer_rect, remote_images_rect, textarea_rect, popup_rect] =
        Layout::vertical([Constraint::Min(3), popup_constraint]).areas(area);
    // ...
}

// 占位符渲染
fn render_placeholder(&self, area: Rect, buf: &mut Buffer) {
    if self.textarea.is_empty() {
        Paragraph::new(self.placeholder_text.clone().dim())
            .render(area, buf);
    }
}
```

### 底部栏生成
```rust
fn footer_props(&self) -> FooterProps {
    FooterProps {
        mode: self.footer_mode,
        esc_backtrack_hint: self.esc_backtrack_hint,
        use_shift_enter_hint: self.use_shift_enter_hint,
        is_task_running: self.is_task_running,
        collaboration_modes_enabled: self.collaboration_modes_enabled,
        is_wsl: /* ... */,
        quit_shortcut_key: self.quit_shortcut_key,
        context_window_percent: self.context_window_percent,
        context_window_used_tokens: self.context_window_used_tokens,
        status_line_value: self.status_line_value.clone(),
        status_line_enabled: self.status_line_enabled,
        active_agent_label: self.active_agent_label.clone(),
    }
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
- **测试函数**: `empty` (在 tests 模块中)
- **底部栏渲染**: `footer.rs` 中的 `footer_from_props_lines`

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
"                                                                                                    "
"  ? for shortcuts                                                                100% context left  "
```

- 第 2 行：`›` 提示符 + 占位符文本（灰色）
- 第 10 行：左侧快捷键提示 + 右侧上下文信息

## 依赖与外部交互

### 内部依赖
- `TextArea` - 文本输入区域
- `FooterProps` - 底部栏属性
- `footer_height` - 底部栏高度计算
- `context_window_line` - 上下文信息行生成

### 外部交互
- **配置系统**：获取占位符文本和默认设置
- **上下文管理器**：获取当前上下文使用情况

## 风险、边界与改进建议

### 潜在风险
1. **占位符本地化**：硬编码英文占位符，不支持国际化
2. **上下文信息延迟**：上下文百分比可能不是实时的
3. **视觉疲劳**：长期使用相同的占位符可能显得单调

### 边界情况
1. **终端宽度变化**：非常窄的终端可能导致文本截断
2. **高对比度主题**：灰色占位符在某些主题下可能不可见
3. **无上下文信息**：当 `context_window_percent` 为 None 时的回退显示

### 改进建议
1. **动态占位符**：根据时间、历史记录等显示不同的提示
2. **国际化**：支持多语言占位符
3. **上下文警告**：当上下文接近上限时改变颜色（如黄色/红色）
4. **快捷示例**：在占位符中显示随机示例命令
5. **语音输入提示**：如果支持语音，显示语音输入提示

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
- 底部栏: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- 文本区域: `codex-rs/tui_app_server/src/bottom_pane/textarea.rs`
