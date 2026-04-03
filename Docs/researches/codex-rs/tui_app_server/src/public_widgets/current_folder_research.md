# public_widgets 目录研究报告

## 目录结构

```
codex-rs/tui_app_server/src/public_widgets/
├── mod.rs              # 模块导出文件
└── composer_input.rs   # 公开可复用的文本输入组件
```

---

## 1. 场景与职责

### 1.1 定位与目的

`public_widgets` 目录是 `tui_app_server` crate 的**公开组件库**，旨在将内部成熟的 TUI 组件以简化的 API 暴露给其他 crate 使用。其核心设计目标是：

- **代码复用**：将 `ChatComposer` 的复杂功能封装为可重用的公共组件
- **跨 crate 共享**：允许 `codex-cloud-tasks` 等外部 crate 使用 TUI 的文本输入能力
- **API 简化**：对外隐藏内部复杂的状态机和事件系统，提供简洁的接口

### 1.2 使用场景

当前主要使用方：

| 使用方 | 用途 |
|--------|------|
| `codex-cloud-tasks` | 在 Cloud Tasks TUI 中提供任务创建输入框 |
| `codex-tui` | 内部使用（通过 `lib.rs` 重新导出） |

### 1.3 架构位置

```
┌─────────────────────────────────────────────────────────────┐
│                    调用方 (如 cloud-tasks)                    │
│                         ComposerInput                        │
└─────────────────────────────┬───────────────────────────────┘
                              │ 使用
┌─────────────────────────────▼───────────────────────────────┐
│              public_widgets/composer_input.rs                │
│                    (公开包装器层)                             │
└─────────────────────────────┬───────────────────────────────┘
                              │ 委托
┌─────────────────────────────▼───────────────────────────────┐
│              bottom_pane/ChatComposer                        │
│                    (核心实现层)                              │
└─────────────────────────────┬───────────────────────────────┘
                              │ 使用
┌─────────────────────────────▼───────────────────────────────┐
│              bottom_pane/textarea/TextArea                   │
│                    (底层文本编辑)                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 ComposerInput 功能清单

| 功能 | 目的 | 对应方法 |
|------|------|----------|
| **多行文本输入** | 支持 Shift+Enter 换行，Enter 提交 | `input()` |
| **粘贴处理** | 支持大文本粘贴检测、图片路径粘贴 | `handle_paste()` |
| **粘贴突发检测** | 处理 Windows 等非 bracketed paste 终端的快速输入 | `is_in_paste_burst()`, `flush_paste_burst_if_due()` |
| **底部提示定制** | 允许调用方自定义快捷键提示 | `set_hint_items()`, `clear_hint_items()` |
| **布局计算** | 提供高度计算和光标位置 | `desired_height()`, `cursor_pos()` |
| **渲染** | 集成 ratatui 渲染系统 | `render_ref()` |

### 2.2 功能设计哲学

1. **最小暴露原则**：仅暴露最必要的功能，隐藏内部复杂性（如 slash commands、skill popups 等）
2. **事件驱动**：通过 `ComposerAction` 枚举返回用户行为，而非直接处理业务逻辑
3. **无阻塞设计**：内部使用 channel 处理异步事件，但对外提供同步 API

---

## 3. 具体技术实现

### 3.1 核心数据结构

#### 3.1.1 ComposerInput (公开包装器)

```rust
pub struct ComposerInput {
    inner: ChatComposer,                                    // 内部实现
    _tx: tokio::sync::mpsc::UnboundedSender<AppEvent>,     // 事件发送端（保留防止关闭）
    rx: tokio::sync::mpsc::UnboundedReceiver<AppEvent>,    // 事件接收端（用于 drain）
}
```

#### 3.1.2 ComposerAction (用户行为枚举)

```rust
pub enum ComposerAction {
    Submitted(String),  // 用户提交文本
    None,               // 无提交（可能仅 UI 更新）
}
```

#### 3.1.3 InputResult (内部结果类型)

```rust
pub enum InputResult {
    Submitted { text: String, text_elements: Vec<TextElement> },
    Queued { text: String, text_elements: Vec<TextElement> },
    Command(SlashCommand),
    CommandWithArgs(SlashCommand, String, Vec<TextElement>),
    None,
}
```

### 3.2 关键流程

#### 3.2.1 初始化流程

```rust
pub fn new() -> Self {
    // 1. 创建 AppEvent channel
    let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
    let sender = AppEventSender::new(tx.clone());
    
    // 2. 创建内部 ChatComposer
    let inner = ChatComposer::new(
        /*has_input_focus*/ true,
        sender,
        /*enhanced_keys_supported*/ true,  // 启用 Shift+Enter
        "Compose new task".to_string(),     // 默认占位符
        /*disable_paste_burst*/ false,      // 启用粘贴突发检测
    );
    
    Self { inner, _tx: tx, rx }
}
```

#### 3.2.2 键盘事件处理流程

```
用户按键
    │
    ▼
input(key_event)
    │
    ├──► inner.handle_key_event(key) ──► (InputResult, needs_redraw)
    │
    ├──► 匹配 InputResult
    │       ├── Submitted { text, .. } ──► ComposerAction::Submitted(text)
    │       └── _ ──► ComposerAction::None
    │
    └──► drain_app_events() [清空 channel 避免内存泄漏]
```

#### 3.2.3 粘贴处理流程

```rust
pub fn handle_paste(&mut self, pasted: String) -> bool {
    // 1. 委托给内部 ChatComposer
    let handled = self.inner.handle_paste(pasted);
    
    // 2. 清空可能产生的事件
    self.drain_app_events();
    
    handled
}
```

### 3.3 内部依赖关系

#### 3.3.1 ChatComposer 配置

`ComposerInput` 使用 `ChatComposerConfig::default()` 初始化，包含：

```rust
pub(crate) struct ChatComposerConfig {
    pub(crate) popups_enabled: bool,        // true - 允许弹出层
    pub(crate) slash_commands_enabled: bool, // true - 启用 / 命令
    pub(crate) image_paste_enabled: bool,    // true - 支持图片粘贴
}
```

**注意**：`ComposerInput` 使用默认配置，启用所有功能。如需简化版本，可使用 `ChatComposerConfig::plain_text()`。

#### 3.3.2 事件系统

```rust
// AppEventSender - 事件发送包装器
pub(crate) struct AppEventSender {
    pub app_event_tx: UnboundedSender<AppEvent>,
}

// AppEvent - 应用级事件枚举（约 50+ 种事件）
pub(crate) enum AppEvent {
    Exit(ExitMode),
    CodexOp(Op),
    StartFileSearch(String),
    // ... 更多事件
}
```

### 3.4 渲染系统

#### 3.4.1 Renderable Trait

```rust
pub trait Renderable {
    fn render(&self, area: Rect, buf: &mut Buffer);
    fn desired_height(&self, width: u16) -> u16;
    fn cursor_pos(&self, _area: Rect) -> Option<(u16, u16)>;
}
```

#### 3.4.2 渲染调用链

```
ComposerInput::render_ref(area, buf)
    └──► ChatComposer::render(area, buf)
            └──► 1. 布局计算 (layout_areas)
            └──► 2. 渲染远程图片行
            └──► 3. 渲染 TextArea
            └──► 4. 渲染底部提示 (Footer)
```

---

## 4. 关键代码路径与文件引用

### 4.1 本目录文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `mod.rs` | 1 | 导出 `composer_input` 模块 |
| `composer_input.rs` | 135 | `ComposerInput` 公开 API 实现 |

### 4.2 核心依赖文件

| 文件路径 | 职责 |
|----------|------|
| `bottom_pane/chat_composer.rs` | `ChatComposer` 核心实现（~2000 行） |
| `bottom_pane/textarea.rs` | `TextArea` 底层文本编辑 |
| `bottom_pane/paste_burst.rs` | 粘贴突发检测逻辑 |
| `render/renderable.rs` | `Renderable` trait 定义 |
| `app_event.rs` | `AppEvent` 事件定义 |
| `app_event_sender.rs` | `AppEventSender` 实现 |

### 4.3 关键代码片段

#### 4.3.1 ComposerInput 创建 (composer_input.rs:36-48)

```rust
pub fn new() -> Self {
    let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
    let sender = AppEventSender::new(tx.clone());
    let inner = ChatComposer::new(
        /*has_input_focus*/ true,
        sender,
        /*enhanced_keys_supported*/ true,
        "Compose new task".to_string(),
        /*disable_paste_burst*/ false,
    );
    Self { inner, _tx: tx, rx }
}
```

#### 4.3.2 键盘输入处理 (composer_input.rs:62-69)

```rust
pub fn input(&mut self, key: KeyEvent) -> ComposerAction {
    let action = match self.inner.handle_key_event(key).0 {
        InputResult::Submitted { text, .. } => ComposerAction::Submitted(text),
        _ => ComposerAction::None,
    };
    self.drain_app_events();
    action
}
```

#### 4.3.3 事件清空 (composer_input.rs:126-128)

```rust
fn drain_app_events(&mut self) {
    while self.rx.try_recv().is_ok() {}
}
```

### 4.4 调用方使用示例

#### 4.4.1 cloud-tasks 使用 (codex-rs/cloud-tasks/src/new_task.rs)

```rust
use codex_tui::ComposerInput;

pub struct NewTaskPage {
    pub composer: ComposerInput,
    pub submitting: bool,
    pub env_id: Option<String>,
    pub best_of_n: usize,
}

impl NewTaskPage {
    pub fn new(env_id: Option<String>, best_of_n: usize) -> Self {
        let mut composer = ComposerInput::new();
        composer.set_hint_items(vec![
            ("⏎", "send"),
            ("Shift+⏎", "newline"),
            ("Ctrl+O", "env"),
            ("Ctrl+N", "attempts"),
            ("Ctrl+C", "quit"),
        ]);
        Self { composer, submitting: false, env_id, best_of_n }
    }
}
```

#### 4.4.2 事件循环集成 (codex-rs/cloud-tasks/src/lib.rs:928-933)

```rust
// Micro‑flush pending first key held by paste‑burst.
if let Some(page) = app.new_task.as_mut() {
    if page.composer.flush_paste_burst_if_due() { needs_redraw = true; }
    if page.composer.is_in_paste_burst() {
        let _ = frame_tx.send(Instant::now() + codex_tui::ComposerInput::recommended_flush_delay());
    }
}
```

---

## 5. 依赖与外部交互

### 5.1 crate 依赖关系

```
tui_app_server/public_widgets
    │
    ├──► 内部依赖
    │       ├── bottom_pane/ChatComposer
    │       ├── bottom_pane/InputResult
    │       ├── render/renderable::Renderable
    │       ├── app_event::AppEvent
    │       └── app_event_sender::AppEventSender
    │
    └──► 外部 crate 依赖
            ├── crossterm (KeyEvent)
            ├── ratatui (Buffer, Rect)
            └── tokio (mpsc channel)
```

### 5.2 与 tui crate 的关系

`tui` 和 `tui_app_server` 两个 crate 都包含 `public_widgets` 模块，且代码**完全一致**：

```
codex-rs/tui/src/public_widgets/
codex-rs/tui_app_server/src/public_widgets/
```

这是有意的设计，确保两个 crate 的 API 保持一致。`tui_app_server` 是主要实现位置，`tui` 可能是遗留或镜像。

### 5.3 公开 API 导出

在 `tui_app_server/src/lib.rs` 中重新导出：

```rust
pub use public_widgets::composer_input::ComposerAction;
pub use public_widgets::composer_input::ComposerInput;
```

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 事件泄露风险

```rust
fn drain_app_events(&mut self) {
    while self.rx.try_recv().is_ok() {}
}
```

- **风险**：简单丢弃所有事件，如果内部组件依赖事件反馈可能有问题
- **现状**：当前 `ComposerInput` 使用场景简单，内部不产生关键事件

#### 6.1.2 内存泄漏风险

- `_tx` 字段仅用于保持 channel 不关闭，但没有实际发送需求
- 可考虑使用 `std::mem::forget` 或更轻量的方式

#### 6.1.3 功能耦合

- `ComposerInput` 使用 `ChatComposerConfig::default()`，启用了所有功能
- 对于简单输入场景（如 cloud-tasks），slash commands 和 popups 可能多余

### 6.2 边界情况

| 场景 | 行为 |
|------|------|
| 大文本粘贴 (>1000 字符) | 显示占位符，实际内容存储在 `pending_pastes` 中 |
| 图片路径粘贴 | 自动检测并作为附件添加 |
| Windows 终端快速输入 | PasteBurst 检测防止误判为快捷键 |
| 非 UTF-8 输入 | TextArea 内部处理，按字符边界截断 |

### 6.3 改进建议

#### 6.3.1 短期改进

1. **添加配置选项**
   ```rust
   impl ComposerInput {
       pub fn new_plain() -> Self { /* 使用 ChatComposerConfig::plain_text() */ }
   }
   ```

2. **改进事件处理**
   - 考虑使用 `Option<AppEventSender>` 避免不必要的 channel 创建
   - 或提供不依赖事件系统的轻量版本

3. **文档完善**
   - 添加使用示例
   - 说明 `set_hint_items` 的格式要求

#### 6.3.2 中期改进

1. **功能裁剪**
   - 为不同使用场景提供预配置：
     - `ComposerInput::new_simple()` - 纯文本输入
     - `ComposerInput::new_rich()` - 完整功能

2. **错误处理**
   - 当前 `input()` 返回 `ComposerAction`，可考虑添加错误变体

3. **测试覆盖**
   - 当前目录无测试文件
   - 建议添加单元测试验证包装器行为

#### 6.3.3 长期考虑

1. **crate 拆分**
   - 如果更多 crate 需要使用，考虑将 `public_widgets` 拆分为独立 crate
   - 避免 `tui_app_server` 的重量级依赖

2. **API 演进**
   - 考虑支持异步事件回调
   - 支持自定义验证器

### 6.4 相关 TODO/FIXME

搜索未发现本目录有 TODO/FIXME 注释，但依赖的 `ChatComposer` 中有大量复杂逻辑，潜在问题包括：

- 多线程安全（`RefCell<TextAreaState>`）
- 粘贴突发检测的时序边界
- 大文本粘贴的内存占用

---

## 7. 总结

`public_widgets` 目录是 `tui_app_server` 对外暴露的**轻量级组件库**，目前仅包含 `ComposerInput` 一个组件。它通过包装复杂的 `ChatComposer` 实现，为外部 crate 提供了简洁的文本输入能力。

**核心价值**：
- 代码复用：避免重复实现粘贴检测、多行编辑等功能
- API 稳定：对外隐藏内部变化，保持向后兼容
- 集成简单：几行代码即可集成到 ratatui 应用

**使用建议**：
- 对于简单输入场景，当前实现已足够
- 如需更多控制，考虑直接使用 `ChatComposer` 或 `TextArea`
- 注意事件处理和粘贴突发检测的集成细节
