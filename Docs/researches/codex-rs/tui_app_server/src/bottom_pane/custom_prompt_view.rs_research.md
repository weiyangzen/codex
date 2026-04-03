# custom_prompt_view.rs 研究文档

## 场景与职责

`custom_prompt_view.rs` 是 Codex TUI 应用中用于收集用户自定义输入的通用弹窗组件。它提供了一个极简的多行文本输入界面，主要用于：

1. **自定义 Review 指令**：在代码审查流程中收集用户的具体审查要求
2. **通用文本输入**：任何需要临时收集用户多行文本输入的场景

该模块实现了 `BottomPaneView` trait，可以作为模态视图推入底部面板的视图栈中，临时替代正常的聊天输入框。

## 功能点目的

### 1. 多行文本输入（CustomPromptView）
- **目的**：提供一个简洁的、带占位符提示的多行文本输入界面
- **关键字段**：
  - `title`: 弹窗标题
  - `placeholder`: 输入框占位符文本
  - `context_label`: 可选的上下文标签（显示在标题下方）
  - `on_submit`: 提交回调函数
  - `textarea`: 底层文本输入组件
  - `textarea_state`: 文本输入状态

### 2. 键盘交互处理
- **目的**：处理常见的文本编辑快捷键
- **支持操作**：
  - `Esc`: 取消并关闭弹窗
  - `Enter`（无修饰键）：提交非空文本
  - `Enter`（有修饰键）：插入换行
  - 其他键：传递给底层 textarea 处理

### 3. 粘贴支持
- **目的**：支持从剪贴板粘贴文本
- **实现**：`handle_paste` 方法将粘贴内容插入 textarea

## 具体技术实现

### 关键数据结构

```rust
/// 提交回调类型定义
pub(crate) type PromptSubmitted = Box<dyn Fn(String) + Send + Sync>;

/// 自定义 Prompt 输入视图
pub(crate) struct CustomPromptView {
    title: String,
    placeholder: String,
    context_label: Option<String>,
    on_submit: PromptSubmitted,
    
    // UI 状态
    textarea: TextArea,
    textarea_state: RefCell<TextAreaState>,
    complete: bool,  // 标记视图是否完成
}
```

### 创建流程

```rust
impl CustomPromptView {
    pub(crate) fn new(
        title: String,
        placeholder: String,
        context_label: Option<String>,
        on_submit: PromptSubmitted,
    ) -> Self {
        Self {
            title,
            placeholder,
            context_label,
            on_submit,
            textarea: TextArea::new(),
            textarea_state: RefCell::new(TextAreaState::default()),
            complete: false,
        }
    }
}
```

### 键盘事件处理

```rust
impl BottomPaneView for CustomPromptView {
    fn handle_key_event(&mut self, key_event: KeyEvent) {
        match key_event {
            // Esc: 取消
            KeyEvent { code: KeyCode::Esc, .. } => {
                self.on_ctrl_c();
            }
            // Enter（无修饰键）：提交
            KeyEvent { 
                code: KeyCode::Enter, 
                modifiers: KeyModifiers::NONE, 
                .. 
            } => {
                let text = self.textarea.text().trim().to_string();
                if !text.is_empty() {
                    (self.on_submit)(text);
                    self.complete = true;
                }
            }
            // Enter（有修饰键）：插入换行
            KeyEvent { code: KeyCode::Enter, .. } => {
                self.textarea.input(key_event);
            }
            // 其他键：传递给 textarea
            other => {
                self.textarea.input(other);
            }
        }
    }
    
    fn on_ctrl_c(&mut self) -> CancellationEvent {
        self.complete = true;
        CancellationEvent::Handled
    }
    
    fn is_complete(&self) -> bool {
        self.complete
    }
    
    fn handle_paste(&mut self, pasted: String) -> bool {
        if pasted.is_empty() {
            return false;
        }
        self.textarea.insert_str(&pasted);
        true
    }
}
```

### 渲染实现

```rust
impl Renderable for CustomPromptView {
    fn desired_height(&self, width: u16) -> u16 {
        let extra_top: u16 = if self.context_label.is_some() { 1 } else { 0 };
        1u16 + extra_top + self.input_height(width) + 3u16
    }
    
    fn render(&self, area: Rect, buf: &mut Buffer) {
        // 1. 渲染标题行
        // 2. 渲染可选的上下文标签
        // 3. 渲染输入区域（带左侧装饰 gutter）
        // 4. 渲染占位符（当文本为空时）
        // 5. 渲染底部提示行
    }
    
    fn cursor_pos(&self, area: Rect) -> Option<(u16, u16)> {
        // 计算 textarea 内的光标位置
    }
}
```

### 输入高度计算

```rust
impl CustomPromptView {
    fn input_height(&self, width: u16) -> u16 {
        let usable_width = width.saturating_sub(2);
        let text_height = self.textarea.desired_height(usable_width).clamp(1, 8);
        text_height.saturating_add(1).min(9)
    }
}
```

### 装饰元素

```rust
fn gutter() -> Span<'static> {
    "▌ ".cyan()  // 左侧青色装饰条
}
```

## 关键代码路径与文件引用

### 当前文件关键路径
- `CustomPromptView::new()` (行 41-56): 创建视图
- `BottomPaneView::handle_key_event()` (行 60-87): 键盘事件处理
- `BottomPaneView::on_ctrl_c()` (行 90-93): 取消处理
- `BottomPaneView::handle_paste()` (行 99-105): 粘贴处理
- `Renderable::render()` (行 114-214): 渲染逻辑
- `Renderable::desired_height()` (行 109-112): 高度计算
- `Renderable::cursor_pos()` (行 216-234): 光标位置计算
- `input_height()` (行 238-242): 输入区域高度计算
- `gutter()` (行 245-247): 装饰元素

### 调用方
- `codex-rs/tui_app_server/src/chatwidget.rs`:
  - 在 review 流程中创建 `CustomPromptView`
  - 传递自定义的标题、占位符和提交回调
  - 通过 `bottom_pane.show_view()` 显示视图

### 被调用方
- `codex-rs/tui_app_server/src/bottom_pane/textarea.rs`:
  - `TextArea`: 底层文本输入组件
  - `TextAreaState`: 文本输入状态
- `codex-rs/tui_app_server/src/bottom_pane/popup_consts.rs`:
  - `standard_popup_hint_line()`: 标准底部提示
- `codex-rs/tui_app_server/src/bottom_pane/bottom_pane_view.rs`:
  - `BottomPaneView` trait 定义

## 依赖与外部交互

### 依赖模块
| 模块 | 用途 |
|------|------|
| `textarea` | 多行文本输入组件 |
| `popup_consts` | 弹窗常量（底部提示） |
| `bottom_pane_view` | 底部面板视图 trait |
| `render::renderable` | 渲染 trait |

### 与 ChatWidget 的交互
1. **创建时机**：当需要收集用户自定义输入时（如 review 流程）
2. **回调执行**：用户提交后，`on_submit` 回调被调用，通常：
   - 发送 `AppEvent` 继续后续流程
   - 或直接修改应用状态
3. **生命周期**：视图完成后（`is_complete() == true`），从视图栈中移除

## 风险、边界与改进建议

### 风险点

1. **回调生命周期**
   - 风险：`on_submit` 回调使用 `Box<dyn Fn>`，如果捕获了非 Send/Sync 类型可能导致线程安全问题
   - 现状：trait 约束要求 `Send + Sync`，但实现者仍需注意
   - 建议：确保回调不持有锁或引用可能失效的状态

2. **空文本提交**
   - 现状：空文本（trim 后）不会触发提交，但用户无明确反馈
   - 建议：添加视觉反馈（如输入框闪烁）提示用户需要输入内容

3. **高度限制**
   - 现状：输入区域高度限制为 8 行（+1 行边距）
   - 风险：长文本输入时可能感觉局促
   - 建议：考虑根据屏幕高度动态调整限制

### 边界情况

1. **极窄屏幕**：宽度小于 2 时，输入区域不渲染
2. **空占位符**：占位符为空时，不显示任何提示
3. **多行提交**：用户可通过 Shift+Enter 等方式插入换行
4. **粘贴大文本**：直接插入，无长度限制（依赖底层 textarea 处理）

### 改进建议

1. **输入验证**
   - 添加可选的输入验证回调，在提交前检查输入有效性
   - 验证失败时显示错误提示

2. **历史记录**
   - 为此类自定义输入添加历史记录，支持 Up/Down 浏览

3. **自动完成**
   - 对于特定场景（如 review），提供常用指令的自动完成

4. **富文本支持**
   - 考虑支持简单的语法高亮或 Markdown 预览

5. **快捷键增强**
   - 添加 Ctrl+Enter 作为提交快捷键（与主输入框一致）
   - 添加 Ctrl+A/E 等 Emacs 风格快捷键

6. **测试覆盖**
   - 当前文件无单元测试，建议添加：
     - 键盘事件处理测试
     - 渲染输出快照测试
     - 回调调用验证测试
