# ChatComposer Empty 快照研究文档

## 场景与职责

该快照测试验证ChatComposer在初始空状态下的UI渲染。这是最基本的渲染测试，确保：
- 输入框（textarea）正确显示占位符文本
- 页脚（footer）显示默认的快捷提示
- 右侧上下文信息（100% context left）正确显示

测试使用80列宽度，代表标准终端宽度下的渲染效果。

## 功能点目的

1. **初始状态渲染**：验证ChatComposer在没有任何用户输入时的默认外观
2. **占位符显示**：确保"Ask Codex to do anything"提示正确显示
3. **页脚快捷提示**：验证"? for shortcuts"提示在空状态下可见
4. **上下文窗口指示器**：验证右侧显示"100% context left"

## 具体技术实现

### 关键数据结构

```rust
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

pub(crate) enum FooterMode {
    QuitShortcutReminder,
    ShortcutOverlay,
    EscHint,
    ComposerEmpty,    // 本测试使用的模式
    ComposerHasDraft,
}
```

### 渲染流程

1. **ChatComposer渲染**（`render`方法）：
   - 渲染远程图片行（本例中为空）
   - 渲染textarea（显示占位符）
   - 渲染页脚区域

2. **页脚渲染决策**（`footer_mode`方法）：
   - 空状态 → `FooterMode::ComposerEmpty`
   - 显示快捷提示（"? for shortcuts"）

3. **单行页脚布局**（`single_line_footer_layout`函数）：
   - 计算左侧提示宽度
   - 计算右侧上下文宽度
   - 决定是否可以同时显示两者

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 相关功能 |
|---------|---------|
| `codex-rs/tui/src/bottom_pane/chat_composer.rs` | ChatComposer主实现 |
| `codex-rs/tui/src/bottom_pane/footer.rs` | 页脚渲染逻辑 |

### 关键代码位置

1. **空状态检测**（chat_composer.rs:725-729）：
   ```rust
   pub(crate) fn is_empty(&self) -> bool {
       self.textarea.is_empty()
           && self.attached_images.is_empty()
           && self.remote_image_urls.is_empty()
   }
   ```

2. **页脚模式决定**（chat_composer.rs:3214-3235）：
   ```rust
   fn footer_mode(&self) -> FooterMode {
       let base_mode = if self.is_empty() {
           FooterMode::ComposerEmpty
       } else {
           FooterMode::ComposerHasDraft
       };
       // ... 处理瞬态模式覆盖
   }
   ```

3. **快捷提示显示决策**（footer.rs:187-210）：
   ```rust
   pub(crate) fn footer_height(props: &FooterProps) -> u16 {
       let show_shortcuts_hint = match props.mode {
           FooterMode::ComposerEmpty => true,
           FooterMode::ComposerHasDraft => false,
           // ...
       };
       // ...
   }
   ```

4. **上下文行生成**（footer.rs:848-860）：
   ```rust
   pub(crate) fn context_window_line(percent: Option<i64>, used_tokens: Option<i64>) -> Line<'static> {
       if let Some(percent) = percent {
           let percent = percent.clamp(0, 100);
           return Line::from(vec![Span::from(format!("{percent}% context left")).dim()]);
       }
       // ...
   }
   ```

## 依赖与外部交互

### 依赖模块

- `ratatui`：终端UI渲染框架
- `crossterm`：跨平台终端控制

### 样式应用

- 使用`.dim()`样式使页脚文本呈现暗淡效果
- 使用`Line::from`构建文本行

## 风险、边界与改进建议

### 潜在风险

1. **布局偏移**：如果占位符文本长度变化，可能影响整体布局
2. **宽度计算错误**：在极窄终端下，快捷提示和上下文信息可能重叠
3. **国际化**：占位符文本需要支持本地化

### 边界情况

- 终端宽度小于提示文本长度时的处理
- 当`context_window_percent`为None时的回退显示

### 改进建议

1. **响应式布局**：在窄终端下考虑隐藏部分提示或换行显示
2. **可配置占位符**：允许用户自定义输入提示文本
3. **增强可访问性**：考虑为占位符添加颜色区分
4. **测试覆盖**：添加不同终端宽度下的渲染测试

### 相关测试

- `footer_collapse_empty_*`系列：测试不同宽度下的页脚折叠行为
- `footer_shortcuts_default`：测试页脚快捷提示
- `small`：测试小尺寸渲染

### 快照内容解读

```
"  ? for shortcuts                                                                100% context left  "
```

- 左侧：`? for shortcuts` - 提示用户按`?`键查看快捷方式
- 右侧：`100% context left` - 显示上下文窗口剩余容量
- 中间：大量空格用于分隔左右内容
