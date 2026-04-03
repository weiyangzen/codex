# Chat Composer - Empty State 研究报告

## 1. 场景与职责

### UI场景
该快照展示了 **Chat Composer** 组件在 **空状态（Empty State）** 下的渲染效果。这是用户刚打开 Codex 或完成一次对话后的初始状态，输入区域为空，显示占位提示文本和底部快捷提示。

### 组件职责
- **初始状态展示**: 展示友好的初始界面引导用户开始输入
- **占位提示**: 在空输入时显示提示文本（"Ask Codex to do anything"）
- **快捷提示**: 显示可用的快捷键提示（"? for shortcuts"）
- **上下文指示**: 显示当前上下文窗口使用情况（"100% context left"）

## 2. 功能点目的

### 核心功能
1. **空状态提示**: 引导用户开始输入
2. **快捷键发现**: 帮助用户发现可用的快捷键
3. **上下文监控**: 实时显示上下文窗口使用情况
4. **焦点指示**: 显示输入区域的就绪状态

### 用户体验目标
- 降低新用户的学习成本
- 提供清晰的输入引导
- 让用户了解系统状态（上下文使用情况）

## 3. 具体技术实现

### 关键数据结构

```rust
pub(crate) struct ChatComposer {
    textarea: TextArea,
    textarea_state: RefCell<TextAreaState>,
    placeholder_text: String,  // 占位提示文本
    footer_mode: FooterMode,
    context_window_percent: Option<i64>,
    context_window_used_tokens: Option<i64>,
    // ... 其他字段
}

pub(crate) enum FooterMode {
    QuitShortcutReminder,
    ShortcutOverlay,
    EscHint,
    ComposerEmpty,    // 本场景使用
    ComposerHasDraft,
}

pub(crate) struct FooterProps {
    pub(crate) mode: FooterMode,
    pub(crate) esc_backtrack_hint: bool,
    pub(crate) use_shift_enter_hint: bool,
    pub(crate) is_task_running: bool,
    pub(crate) collaboration_modes_enabled: bool,
    pub(crate) is_wsl: bool,
    pub(crate) quit_shortcut_key: KeyBinding,
    pub(crate) context_window_percent: Option<i64>,
    pub(crate) context_window_used_tokens: Option<i64>,
    pub(crate) status_line_value: Option<Line<'static>>,
    pub(crate) status_line_enabled: bool,
    pub(crate) active_agent_label: Option<String>,
}
```

### 渲染布局

```rust
fn layout_areas(&self, area: Rect) -> [Rect; 4] {
    let footer_props = self.footer_props();
    let footer_hint_height = self
        .custom_footer_height()
        .unwrap_or_else(|| footer_height(&footer_props));
    let footer_spacing = Self::footer_spacing(footer_hint_height);
    let footer_total_height = footer_hint_height + footer_spacing;
    
    // 布局：文本编辑区 + 弹出层区域
    let [composer_rect, popup_rect] =
        Layout::vertical([Constraint::Min(3), popup_constraint]).areas(area);
    
    // 文本编辑区内边距
    let mut textarea_rect = composer_rect.inset(Insets::tlbr(
        /*top*/ 1,
        LIVE_PREFIX_COLS,  // 左侧前缀列（如 ">"）
        /*bottom*/ 1,
        /*right*/ 1,
    ));
    
    // ... 远程图片行处理
    
    [composer_rect, remote_images_rect, textarea_rect, popup_rect]
}
```

### 空状态渲染

```rust
impl Renderable for ChatComposer {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        let [composer_rect, remote_images_rect, textarea_rect, popup_rect] = 
            self.layout_areas(area);
        
        // 渲染背景块
        Block::default()
            .style(user_message_style())
            .render(composer_rect, buf);
        
        // 渲染远程图片行（如果有）
        // ...
        
        // 渲染文本区域
        let mut state = self.textarea_state.borrow_mut();
        StatefulWidgetRef::render_ref(&self.textarea, textarea_rect, buf, &mut state);
        
        // 空状态时渲染占位文本
        if self.textarea.text().is_empty() && self.input_enabled {
            Paragraph::new(Line::from(self.placeholder_text.clone().dim()))
                .render(textarea_rect, buf);
        }
        
        // 渲染底部提示
        self.render_footer(popup_rect, buf);
    }
}
```

### 底部提示渲染

```rust
fn render_footer(&self, area: Rect, buf: &mut Buffer) {
    let footer_props = self.footer_props();
    
    match footer_props.mode {
        FooterMode::ComposerEmpty => {
            // 空状态：显示快捷键提示和上下文
            let left_line = left_side_line(
                self.collaboration_mode_indicator,
                LeftSideState {
                    hint: SummaryHintKind::Shortcuts,  // "? for shortcuts"
                    show_cycle_hint: self.collaboration_modes_enabled,
                }
            );
            
            // 右侧上下文指示
            let right_line = context_window_line(
                self.context_window_percent,
                self.context_window_used_tokens,
            );
            
            // 渲染左右布局
            render_footer_line(area, buf, left_line);
            render_context_right(area, buf, &right_line);
        }
        // ... 其他模式
    }
}
```

### 上下文窗口行生成

```rust
pub(crate) fn context_window_line(
    percent: Option<i64>, 
    used_tokens: Option<i64>
) -> Line<'static> {
    if let Some(percent) = percent {
        let percent = percent.clamp(0, 100);
        return Line::from(vec![
            Span::from(format!("{percent}% context left")).dim()
        ]);
    }
    
    if let Some(tokens) = used_tokens {
        let used_fmt = format_tokens_compact(tokens);
        return Line::from(vec![
            Span::from(format!("{used_fmt} used")).dim()
        ]);
    }
    
    Line::from(vec![Span::from("100% context left").dim()])
}
```

## 4. 关键代码路径与文件引用

### 主要源文件
| 文件路径 | 职责 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/tui/src/bottom_pane/chat_composer.rs` | ChatComposer 主实现 |
| `/home/sansha/Github/codex/codex-rs/tui/src/bottom_pane/footer.rs` | 底部提示渲染 |

### 关键代码路径

1. **布局计算**:
   ```
   chat_composer.rs:658-700 -> layout_areas()
   ```

2. **渲染实现**:
   ```
   chat_composer.rs:1700+ (假设) -> impl Renderable for ChatComposer
   ```

3. **底部提示渲染**:
   ```
   footer.rs:229-250 -> render_footer_from_props()
   footer.rs:580-631 -> footer_from_props_lines()
   ```

4. **上下文行生成**:
   ```
   footer.rs:848-860 -> context_window_line()
   ```

## 5. 依赖与外部交互

### 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `crate::bottom_pane::footer::FooterMode` | 底部模式枚举 |
| `crate::status::format_tokens_compact` | Token 数量格式化 |
| `crate::style::user_message_style` | 用户消息样式 |
| `ratatui::widgets::Block` | UI 块组件 |

### 外部交互

1. **上下文更新**:
   ```rust
   pub(crate) fn set_context_window(&mut self, percent: Option<i64>, used_tokens: Option<i64>)
   ```
   - 从后端接收上下文窗口使用情况
   - 触发重新渲染

2. **占位文本设置**:
   ```rust
   pub fn new(..., placeholder_text: String, ...) -> Self
   ```
   - 初始化时设置占位文本

## 6. 风险、边界与改进建议

### 潜在风险

1. **占位文本遮挡**:
   - 风险: 长占位文本可能超出输入区域
   - 缓解: 使用截断或换行处理

2. **上下文信息过时**:
   - 风险: 显示的上下文使用率可能不是实时的
   - 缓解: 定期同步或推送更新

3. **焦点状态混淆**:
   - 风险: 用户可能不确定当前是否有输入焦点
   - 缓解: 使用光标或边框样式指示焦点

### 边界情况

1. **极窄终端**:
   - 当终端宽度很小时，左右布局可能无法同时显示
   - 需要优先级处理（优先显示左侧提示）

2. **上下文满载**:
   - 当 `percent` 为 0 时，应显示警告样式

3. **禁用输入**:
   - `input_enabled = false` 时不显示占位文本

### 改进建议

1. **动态占位文本**:
   - 当前: 固定文本
   - 建议: 根据上下文动态变化（如"Ask about the current file"）

2. **快捷示例**:
   - 建议: 在占位文本中显示一个可点击的示例查询

3. **语音输入提示**:
   - 建议: 当语音功能可用时显示"Hold Space to talk"提示

4. **上下文警告**:
   - 建议: 当上下文接近满载时改变颜色（黄色/红色）

5. **多语言支持**:
   - 建议: 占位文本支持国际化
