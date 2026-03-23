# custom_prompt_view.rs 深度研究

## 场景与职责

`custom_prompt_view.rs` 实现了 TUI (Terminal User Interface) 中的自定义提示词输入视图。它是一个极简的多行文本输入界面，用于收集用户的自定义审查指令（如 `/review` 命令的额外说明）。该视图作为 `BottomPaneView` 的一种实现，临时替换聊天输入框以进行专注的文本输入。

**核心职责：**
1. **多行文本输入**：提供一个简洁的多行文本输入区域
2. **模态交互**：作为模态视图，处理特定的用户输入任务
3. **回调机制**：通过回调函数将用户输入传递回上层逻辑
4. **粘贴支持**：支持文本粘贴操作

## 功能点目的

### 1. PromptSubmitted - 提交回调类型

```rust
pub(crate) type PromptSubmitted = Box<dyn Fn(String) + Send + Sync>;
```

**设计目的：**
- 使用回调模式实现松耦合
- `Send + Sync` 保证线程安全，可在异步上下文使用
- 用户提交后调用，传递输入的文本内容

### 2. CustomPromptView - 自定义提示词视图

**关键字段：**
- `title`: 视图标题，显示在输入区域上方
- `placeholder`: 占位符文本，当输入为空时显示
- `context_label`: 可选的上下文标签，显示额外信息
- `on_submit`: 提交回调函数
- `textarea`: 底层文本输入组件 (`TextArea`)
- `textarea_state`: 文本区域状态（使用 `RefCell` 支持不可变借用时的修改）
- `complete`: 标记视图是否已完成

### 3. BottomPaneView 实现

```rust
impl BottomPaneView for CustomPromptView {
    fn handle_key_event(&mut self, key_event: KeyEvent) { ... }
    fn on_ctrl_c(&mut self) -> CancellationEvent { ... }
    fn is_complete(&self) -> bool { ... }
    fn handle_paste(&mut self, pasted: String) -> bool { ... }
}
```

**目的：** 集成到 `BottomPane` 的视图栈中，统一处理输入和生命周期

### 4. Renderable 实现

```rust
impl Renderable for CustomPromptView {
    fn desired_height(&self, width: u16) -> u16 { ... }
    fn render(&self, area: Rect, buf: &mut Buffer) { ... }
    fn cursor_pos(&self, area: Rect) -> Option<(u16, u16)> { ... }
}
```

**目的：** 实现 TUI 渲染接口，支持高度计算、实际渲染和光标定位

## 具体技术实现

### 键盘事件处理

```rust
fn handle_key_event(&mut self, key_event: KeyEvent) {
    match key_event {
        // Esc - 取消并关闭
        KeyEvent { code: KeyCode::Esc, .. } => self.on_ctrl_c(),
        
        // Enter（无修饰符）- 提交
        KeyEvent { code: KeyCode::Enter, modifiers: KeyModifiers::NONE, .. } => {
            let text = self.textarea.text().trim().to_string();
            if !text.is_empty() {
                (self.on_submit)(text);
                self.complete = true;
            }
        }
        
        // 其他 Enter - 插入换行
        KeyEvent { code: KeyCode::Enter, .. } => self.textarea.input(key_event),
        
        // 其他按键 - 传递给 TextArea
        other => self.textarea.input(other),
    }
}
```

**设计要点：**
- 普通 Enter 提交，Shift/Ctrl+Enter 插入换行（支持多行输入）
- Esc 取消操作
- 空文本不触发提交

### 渲染布局

```
┌─────────────────────────────┐
│ ▌ Title                     │  <- 标题行（加粗）
│ ▌ context_label (optional)  │  <- 可选上下文标签（青色）
│ ▌                           │  <- 输入区域顶部边框
│   [多行文本输入区域]         │  <- TextArea 渲染
│ ▌                           │  <- 输入区域底部边框
│                             │  <- 空白行
│ Press Enter to confirm...   │  <- 提示行
└─────────────────────────────┘
```

**布局计算：**
```rust
fn desired_height(&self, width: u16) -> u16 {
    let extra_top: u16 = if self.context_label.is_some() { 1 } else { 0 };
    1u16 + extra_top + self.input_height(width) + 3u16
}
```
- 1 行：标题
- 0/1 行：上下文标签（可选）
- `input_height`：输入区域高度（1-9 行，根据内容自适应）
- 3 行：空白分隔 + 提示行 + 底部空白

### 输入区域高度计算

```rust
fn input_height(&self, width: u16) -> u16 {
    let usable_width = width.saturating_sub(2);  // 减去 gutter 宽度
    let text_height = self.textarea.desired_height(usable_width).clamp(1, 8);
    text_height.saturating_add(1).min(9)  // +1 用于顶部边框，最大 9 行
}
```

**约束：**
- 最小高度：1 行
- 最大高度：8 行（文本）+ 1 行（边框）= 9 行
- 自动换行计算

### 光标定位

```rust
fn cursor_pos(&self, area: Rect) -> Option<(u16, u16)> {
    // 计算 TextArea 在整体布局中的偏移
    let extra_offset: u16 = if self.context_label.is_some() { 1 } else { 0 };
    let top_line_count = 1u16 + extra_offset;
    
    // 创建 TextArea 的实际渲染区域
    let textarea_rect = Rect {
        x: area.x.saturating_add(2),  // 跳过 gutter
        y: area.y.saturating_add(top_line_count).saturating_add(1),
        width: area.width.saturating_sub(2),
        height: text_area_height,
    };
    
    // 委托给 TextArea 计算光标位置
    self.textarea.cursor_pos_with_state(textarea_rect, state)
}
```

## 关键代码路径与文件引用

### 本文件内关键实现

| 函数/结构 | 行号 | 说明 |
|-----------|------|------|
| `PromptSubmitted` | 25 | 提交回调类型别名 |
| `CustomPromptView` | 28-38 | 视图结构定义 |
| `new` | 41-56 | 构造函数 |
| `BottomPaneView::handle_key_event` | 60-88 | 键盘事件处理 |
| `BottomPaneView::on_ctrl_c` | 90-93 | 取消处理 |
| `BottomPaneView::is_complete` | 95-97 | 完成状态检查 |
| `BottomPaneView::handle_paste` | 99-106 | 粘贴处理 |
| `Renderable::desired_height` | 109-112 | 高度计算 |
| `Renderable::render` | 114-214 | 渲染实现 |
| `Renderable::cursor_pos` | 216-234 | 光标定位 |
| `input_height` | 238-243 | 输入区域高度计算 |
| `gutter` | 245-247 | 左侧装饰线 |

### 依赖文件

| 文件 | 用途 |
|------|------|
| `bottom_pane_view.rs` | `BottomPaneView` trait 定义 |
| `textarea.rs` | `TextArea` 和 `TextAreaState` 组件 |
| `popup_consts.rs` | `standard_popup_hint_line` 提示行 |
| `render/renderable.rs` | `Renderable` trait 定义 |
| `CancellationEvent` | 取消事件枚举（来自 `mod.rs`） |

### 调用方

- `chatwidget.rs`: 创建 `CustomPromptView` 实例（如 `/review` 命令）
- `bottom_pane/mod.rs`: 通过 `BottomPaneView` trait 管理视图生命周期

## 依赖与外部交互

### 与 TextArea 的协作

`CustomPromptView` 是 `TextArea` 的一个包装器：
- `TextArea` 处理底层的文本编辑逻辑
- `CustomPromptView` 处理视图级别的布局和交互

**TextArea 提供的功能：**
- 文本插入、删除
- 光标移动
- 自动换行计算
- 多行支持

### 与 BottomPane 的集成

```rust
// BottomPane 中的使用模式
pub(crate) fn show_view(&mut self, view: Box<dyn BottomPaneView>) {
    self.push_view(view);
}
```

**生命周期：**
1. 上层逻辑创建 `CustomPromptView` 并传入回调
2. `BottomPane` 将视图压入视图栈
3. 用户输入被路由到视图处理
4. 视图标记为 `complete` 后，`BottomPane` 弹出视图
5. 回调被调用，处理用户输入

### 回调使用模式

```rust
// 典型使用场景（如 /review 命令）
let view = CustomPromptView::new(
    "Review changes".to_string(),
    "(optional) Add specific instructions".to_string(),
    Some(format!("Reviewing: {}", file_path)),
    Box::new(move |instructions| {
        // 处理用户输入的审查指令
        app_event_tx.send(AppEvent::SubmitReview { instructions });
    }),
);
bottom_pane.show_view(Box::new(view));
```

## 风险、边界与改进建议

### 潜在风险

1. **回调生命周期**：
   - 回调使用 `Box<dyn Fn>`，可能捕获环境变量
   - 如果捕获了引用，需要确保引用在回调执行时仍然有效
   - 当前实现使用 `move` 闭包和克隆数据来避免此问题

2. **RefCell 使用**：
   - `textarea_state` 使用 `RefCell`，在 `render` 中进行内部可变性操作
   - 如果在同一调用栈中多次借用可能导致 panic
   - 当前代码路径安全，但需要谨慎修改

3. **空文本提交**：
   - 当前实现忽略空文本提交
   - 用户可能困惑为什么 Enter 没有响应
   - 建议：添加视觉反馈或提示

### 边界情况

1. **极小宽度**：
   - 当宽度小于 2 时，gutter 会占用全部空间
   - `render` 中有检查 `if input_area.width >= 2`
   - 极端情况下输入区域可能不可见

2. **极长文本**：
   - 高度限制在 9 行，超出内容会被截断
   - TextArea 支持滚动，但当前实现没有显示滚动指示器

3. **粘贴内容**：
   - 粘贴处理简单地将文本插入
   - 没有处理粘贴内容的验证或格式化

### 改进建议

1. **空文本提示**：
   ```rust
   // 当前：静默忽略
   // 建议：添加视觉反馈
   if text.is_empty() {
       self.show_empty_warning = true;  // 闪烁提示或震动效果
       return;
   }
   ```

2. **字符计数**：
   - 添加字符/行数计数器
   - 帮助用户了解输入长度

3. **历史记录**：
   - 保存用户之前的输入
   - 支持 Up/Down 浏览历史

4. **语法高亮**：
   - 如果是代码相关提示，添加简单的高亮
   - 提升可读性

5. **确认对话框**：
   - 对于长文本，提交前显示确认摘要
   - 防止误提交

6. **快捷键增强**：
   - Ctrl+A/E 跳转到行首/行尾
   - Ctrl+K 删除到行尾
   - 与主输入框保持一致的快捷键

7. **自适应高度**：
   - 当前最大 9 行固定
   - 可以考虑根据屏幕高度动态调整

### 代码质量

- **优点**：
  - 代码简洁，职责单一
  - 与 `TextArea` 良好复用
  - 使用标准 TUI 渲染模式

- **可改进**：
  - 缺少单元测试（文件中没有 `#[cfg(test)]` 模块）
  - `render` 函数较长，可以拆分为子函数
  - 魔法数字（如 `2` 表示 gutter 宽度）可以定义为常量

### 与其他视图的对比

| 特性 | CustomPromptView | FeedbackNoteView |
|------|------------------|------------------|
| 用途 | 通用提示输入 | 反馈备注输入 |
| 标题 | 可配置 | 根据反馈类别固定 |
| 上下文标签 | 可选 | 无 |
| 提交触发 | Enter | Enter |
| 多行支持 | 是 | 是 |
| 测试覆盖 | 无 | 有（快照测试） |

两个视图结构相似，可以考虑提取公共组件，但当前保持独立也有合理性（不同业务语义）。
