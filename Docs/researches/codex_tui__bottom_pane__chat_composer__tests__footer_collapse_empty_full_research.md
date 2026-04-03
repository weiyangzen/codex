# Chat Composer - Footer Collapse Empty Full 研究报告

## 1. 场景与职责

### UI场景
该快照展示了 **Chat Composer** 组件在 **空状态且底部提示完全展开** 时的渲染效果。这是底部提示区域（Footer）在终端宽度充足时的完整展示状态，显示了所有可用的提示信息和上下文指示。

### 组件职责
- **响应式布局**: 根据终端宽度自适应调整底部提示内容
- **信息优先级管理**: 在宽度不足时按优先级折叠提示信息
- **完整信息展示**: 在宽度充足时展示所有提示和上下文信息
- **视觉层次**: 通过样式区分不同类型的信息

## 2. 功能点目的

### 核心功能
1. **完整提示展示**: 显示快捷键提示（"? for shortcuts"）
2. **模式指示**: 显示当前协作模式（如"Plan mode"）
3. **模式切换提示**: 显示模式切换快捷键（"shift+tab to cycle"）
4. **上下文监控**: 显示上下文窗口使用情况（"100% context left"）

### 用户体验目标
- 在宽终端上充分利用空间展示有用信息
- 保持界面整洁不拥挤
- 让用户随时了解系统状态和可用操作

## 3. 具体技术实现

### 关键数据结构

```rust
pub(crate) enum CollaborationModeIndicator {
    Plan,
    PairProgramming,
    Execute,
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

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum SummaryHintKind {
    None,
    Shortcuts,      // "? for shortcuts"
    QueueMessage,   // "tab to queue message"
    QueueShort,     // "tab to queue"
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct LeftSideState {
    hint: SummaryHintKind,
    show_cycle_hint: bool,  // 是否显示 "shift+tab to cycle"
}
```

### 单行底部布局计算

```rust
pub(crate) fn single_line_footer_layout(
    area: Rect,
    context_width: u16,
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    show_cycle_hint: bool,
    show_shortcuts_hint: bool,
    show_queue_hint: bool,
) -> (SummaryLeft, bool) {
    // 确定提示类型
    let hint_kind = if show_queue_hint {
        SummaryHintKind::QueueMessage
    } else if show_shortcuts_hint {
        SummaryHintKind::Shortcuts
    } else {
        SummaryHintKind::None
    };
    
    let default_state = LeftSideState {
        hint: hint_kind,
        show_cycle_hint,
    };
    let default_line = left_side_line(collaboration_mode_indicator, default_state);
    let default_width = default_line.width() as u16;
    
    // 检查是否能同时显示左侧提示和右侧上下文
    if default_width > 0 && can_show_left_with_context(area, default_width, context_width) {
        return (SummaryLeft::Default, true);
    }
    
    // 如果不行，尝试各种折叠策略...
    // 1. 去掉 cycle hint
    // 2. 只显示模式
    // 3. 完全隐藏左侧
    
    (SummaryLeft::None, true)
}
```

### 左侧提示行生成

```rust
fn left_side_line(
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    state: LeftSideState,
) -> Line<'static> {
    let mut line = Line::from("");
    
    // 添加快捷键提示
    match state.hint {
        SummaryHintKind::None => {}
        SummaryHintKind::Shortcuts => {
            line.push_span(key_hint::plain(KeyCode::Char('?')));
            line.push_span(" for shortcuts".dim());
        }
        SummaryHintKind::QueueMessage => {
            line.push_span(key_hint::plain(KeyCode::Tab));
            line.push_span(" to queue message".dim());
        }
        SummaryHintKind::QueueShort => {
            line.push_span(key_hint::plain(KeyCode::Tab));
            line.push_span(" to queue".dim());
        }
    };
    
    // 添加模式指示
    if let Some(collaboration_mode_indicator) = collaboration_mode_indicator {
        if !matches!(state.hint, SummaryHintKind::None) {
            line.push_span(" · ".dim());
        }
        line.push_span(collaboration_mode_indicator.styled_span(state.show_cycle_hint));
    }
    
    line
}
```

### 协作模式指示样式

```rust
impl CollaborationModeIndicator {
    fn styled_span(self, show_cycle_hint: bool) -> Span<'static> {
        let label = self.label(show_cycle_hint);
        match self {
            CollaborationModeIndicator::Plan => Span::from(label).magenta(),
            CollaborationModeIndicator::PairProgramming => Span::from(label).cyan(),
            CollaborationModeIndicator::Execute => Span::from(label).dim(),
        }
    }
    
    fn label(self, show_cycle_hint: bool) -> String {
        let suffix = if show_cycle_hint {
            format!(" (shift+tab to cycle)")
        } else {
            String::new()
        };
        match self {
            CollaborationModeIndicator::Plan => format!("Plan mode{suffix}"),
            CollaborationModeIndicator::PairProgramming => format!("Pair Programming mode{suffix}"),
            CollaborationModeIndicator::Execute => format!("Execute mode{suffix}"),
        }
    }
}
```

### 宽度计算和布局判断

```rust
pub(crate) fn can_show_left_with_context(
    area: Rect, 
    left_width: u16, 
    context_width: u16
) -> bool {
    let Some(context_x) = right_aligned_x(area, context_width) else {
        return true;
    };
    if left_width == 0 {
        return true;
    }
    let left_extent = FOOTER_INDENT_COLS as u16 + left_width + FOOTER_CONTEXT_GAP_COLS;
    left_extent <= context_x.saturating_sub(area.x)
}

pub(crate) fn right_aligned_x(area: Rect, content_width: u16) -> Option<u16> {
    if area.is_empty() {
        return None;
    }
    
    let right_padding = FOOTER_INDENT_COLS as u16;
    let max_width = area.width.saturating_sub(right_padding);
    
    if content_width == 0 || max_width == 0 {
        return None;
    }
    
    if content_width >= max_width {
        return Some(area.x.saturating_add(right_padding));
    }
    
    Some(
        area.x
            .saturating_add(area.width)
            .saturating_sub(content_width)
            .saturating_sub(right_padding)
    )
}
```

## 4. 关键代码路径与文件引用

### 主要源文件
| 文件路径 | 职责 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/tui/src/bottom_pane/footer.rs` | 底部提示完整实现 |
| `/home/sansha/Github/codex/codex-rs/tui/src/bottom_pane/chat_composer.rs` | ChatComposer 集成 |

### 关键代码路径

1. **单行布局计算**:
   ```
   footer.rs:310-472 -> single_line_footer_layout()
   ```

2. **左侧提示行生成**:
   ```
   footer.rs:271-300 -> left_side_line()
   ```

3. **模式指示样式**:
   ```
   footer.rs:101-125 -> CollaborationModeIndicator 实现
   ```

4. **上下文右对齐**:
   ```
   footer.rs:481-527 -> right_aligned_x(), max_left_width_for_right(), can_show_left_with_context()
   ```

5. **上下文行生成**:
   ```
   footer.rs:848-860 -> context_window_line()
   ```

## 5. 依赖与外部交互

### 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `crate::key_hint` | 快捷键提示生成 |
| `crate::ui_consts::FOOTER_INDENT_COLS` | 底部缩进常量 |
| `crate::status::format_tokens_compact` | Token 格式化 |
| `ratatui::layout::Rect` | 布局区域 |
| `ratatui::text::Line` | 文本行 |
| `ratatui::style::Stylize` | 样式trait |

### 外部交互

1. **模式更新**:
   ```rust
   pub fn set_collaboration_mode_indicator(&mut self, indicator: Option<CollaborationModeIndicator>)
   ```
   - 从应用状态接收当前协作模式

2. **上下文更新**:
   ```rust
   pub(crate) fn set_context_window(&mut self, percent: Option<i64>, used_tokens: Option<i64>)
   ```
   - 接收上下文窗口使用情况

## 6. 风险、边界与改进建议

### 潜在风险

1. **布局抖动**:
   - 风险: 终端宽度微小变化可能导致频繁布局切换
   - 缓解: 添加布局切换的缓冲阈值

2. **信息截断**:
   - 风险: 极端窄终端可能导致重要信息丢失
   - 缓解: 确保最低限度的关键信息展示

3. **颜色可读性**:
   - 风险: 某些终端主题下颜色可能难以区分
   - 缓解: 提供高对比度模式选项

### 边界情况

1. **零宽度上下文**:
   - 当 `context_window_percent` 和 `used_tokens` 都为 None 时
   - 默认显示 "100% context left"

2. **无协作模式**:
   - `collaboration_mode_indicator` 为 None 时
   - 仅显示快捷键提示

3. **任务运行中**:
   - `is_task_running = true` 时
   - 可能切换为队列提示（"tab to queue"）

### 改进建议

1. **动画过渡**:
   - 建议: 布局变化时添加平滑过渡动画

2. **自定义布局**:
   - 建议: 允许用户自定义底部显示的信息项

3. **智能折叠**:
   - 建议: 根据用户使用频率智能决定折叠优先级

4. **多行支持**:
   - 建议: 极宽终端支持双行底部展示更多信息

5. **触摸支持**:
   - 建议: 为触摸设备添加可点击的提示按钮
