# composer_input.rs 研究文档

## 场景与职责

`composer_input.rs` 是 Codex TUI 中 `public_widgets` 模块的核心文件，提供了一个对内部 `ChatComposer` 的公共包装器。它的设计目标是让其他 crate（如 `codex-cloud-tasks` 和 `tui_app_server`）能够复用成熟的文本输入功能，而无需直接依赖复杂的内部实现细节。

该文件位于 `codex-rs/tui/src/public_widgets/composer_input.rs`，是 TUI 库对外暴露的公共 API 的一部分。

## 功能点目的

### 1. 简化接口封装
`ComposerInput` 将内部复杂的 `ChatComposer` 封装成一个简洁的、易于使用的公共接口。它隐藏了内部状态管理、事件循环和渲染细节，只暴露必要的操作。

### 2. 跨 crate 复用
文档明确说明此接口是为其他 crate 设计的，特别是：
- `codex-cloud-tasks`: 云任务管理功能
- `tui_app_server`: TUI 应用服务器

### 3. 核心输入功能
- **多行输入**: 支持 Shift+Enter 换行
- **粘贴启发式**: 处理粘贴事件，支持大文本粘贴检测
- **Enter 提交**: 标准提交行为
- **Footer 提示**: 可自定义底部提示项

### 4. 事件处理抽象
通过内部的 `AppEvent` 通道，将底层事件循环与应用层解耦，调用方只需关注高层次的 `ComposerAction`。

## 具体技术实现

### 核心数据结构

```rust
/// 输入操作返回的动作
pub enum ComposerAction {
    /// 用户提交了当前文本（通常通过 Enter）
    Submitted(String),
    /// 无提交发生
    None,
}

/// 公共包装器结构
pub struct ComposerInput {
    inner: ChatComposer,
    _tx: tokio::sync::mpsc::UnboundedSender<AppEvent>,
    rx: tokio::sync::mpsc::UnboundedReceiver<AppEvent>,
}
```

### 初始化流程

```rust
pub fn new() -> Self {
    let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
    let sender = AppEventSender::new(tx.clone());
    // enhanced_keys_supported=true 启用 Shift+Enter 换行提示/行为
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

关键点：
- 创建无界通道 (`unbounded_channel`) 用于 `AppEvent` 传递
- `enhanced_keys_supported=true` 启用高级键盘功能
- 默认 placeholder 为 "Compose new task"
- `disable_paste_burst=false` 启用粘贴突发检测

### 键盘输入处理

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

流程：
1. 将按键事件传递给内部 `ChatComposer`
2. 根据返回的 `InputResult` 决定动作
3. 清空事件队列避免积压

### 粘贴处理

```rust
pub fn handle_paste(&mut self, pasted: String) -> bool {
    let handled = self.inner.handle_paste(pasted);
    self.drain_app_events();
    handled
}
```

支持大文本粘贴检测（超过 1000 字符使用占位符）和图片路径粘贴自动转换。

### 粘贴突发检测 (Paste Burst)

```rust
pub fn is_in_paste_burst(&self) -> bool {
    self.inner.is_in_paste_burst()
}

pub fn flush_paste_burst_if_due(&mut self) -> bool {
    let flushed = self.inner.flush_paste_burst_if_due();
    self.drain_app_events();
    flushed
}

pub fn recommended_flush_delay() -> Duration {
    crate::bottom_pane::ChatComposer::recommended_paste_flush_delay()
}
```

用于处理某些终端（特别是 Windows）不支持括号粘贴时，通过检测快速连续的字符输入来识别粘贴操作。

### Footer 提示自定义

```rust
pub fn set_hint_items(&mut self, items: Vec<(impl Into<String>, impl Into<String>)>) {
    let mapped: Vec<(String, String)> = items
        .into_iter()
        .map(|(k, v)| (k.into(), v.into()))
        .collect();
    self.inner.set_footer_hint_override(Some(mapped));
}

pub fn clear_hint_items(&mut self) {
    self.inner.set_footer_hint_override(/*items*/ None);
}
```

允许调用方自定义底部提示项，格式为 `(key, label)` 元组列表。

### 渲染接口

```rust
pub fn render_ref(&self, area: Rect, buf: &mut Buffer) {
    self.inner.render(area, buf);
}

pub fn desired_height(&self, width: u16) -> u16 {
    self.inner.desired_height(width)
}

pub fn cursor_pos(&self, area: Rect) -> Option<(u16, u16)> {
    self.inner.cursor_pos(area)
}
```

遵循 ratatui 的渲染模式，支持：
- 引用渲染 (`render_ref`)
- 动态高度计算
- 光标位置报告

### 事件排空

```rust
fn drain_app_events(&mut self) {
    while self.rx.try_recv().is_ok() {}
}
```

关键设计：每次操作后清空事件队列，防止事件积压。由于 `ComposerInput` 是简化包装器，它不需要处理这些事件，只需确保队列不阻塞。

## 关键代码路径与文件引用

### 直接依赖

| 文件路径 | 用途 |
|---------|------|
| `crate::bottom_pane::ChatComposer` | 内部核心实现 |
| `crate::bottom_pane::InputResult` | 输入结果枚举 |
| `crate::app_event::AppEvent` | 应用事件类型 |
| `crate::app_event_sender::AppEventSender` | 事件发送器 |
| `crate::render::renderable::Renderable` | 渲染 trait |

### 相关实现位置

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/chat_composer.rs` | `ChatComposer` 完整实现（约 2000+ 行） |
| `codex-rs/tui/src/bottom_pane/mod.rs` | `BottomPane` 模块，包含 `InputResult` 定义 |
| `codex-rs/tui/src/app_event.rs` | `AppEvent` 枚举定义（约 484 行） |
| `codex-rs/tui/src/app_event_sender.rs` | `AppEventSender` 实现 |
| `codex-rs/tui/src/render/renderable.rs` | `Renderable` trait 定义 |

### 跨 crate 使用

| 文件路径 | 用途 |
|---------|------|
| `codex-rs/tui_app_server/src/public_widgets/composer_input.rs` | `tui_app_server` 的并行实现 |
| `codex-rs/cloud-tasks/` | 云任务功能使用此接口 |

## 依赖与外部交互

### 外部 crate 依赖

```rust
use crossterm::event::KeyEvent;    // 终端事件
use ratatui::buffer::Buffer;        // 渲染缓冲区
use ratatui::layout::Rect;          // 布局矩形
use std::time::Duration;            // 时间间隔
use tokio::sync::mpsc;              // 异步通道
```

### 内部模块依赖

```rust
use crate::app_event::AppEvent;
use crate::app_event_sender::AppEventSender;
use crate::bottom_pane::ChatComposer;
use crate::bottom_pane::InputResult;
use crate::render::renderable::Renderable;
```

### 架构关系

```
调用方 (如 cloud-tasks)
    |
    v
ComposerInput (public_widgets)
    |
    v
ChatComposer (bottom_pane)
    |
    +--> TextArea (文本编辑)
    +--> Footer (底部提示)
    +--> Popups (弹出窗口)
    +--> VoiceState (语音输入)
    +--> PasteBurst (粘贴检测)
```

## 风险、边界与改进建议

### 当前风险

1. **事件丢弃**: `drain_app_events()` 直接丢弃所有事件，如果调用方需要响应某些 `AppEvent`（如语音转录完成），这种设计会导致问题。

2. **硬编码配置**: 
   - placeholder 文本 "Compose new task" 是硬编码的
   - `enhanced_keys_supported` 固定为 `true`
   - `disable_paste_burst` 固定为 `false`

3. **并行实现同步**: `tui_app_server` 有完全相同的代码副本，需要保持同步，增加维护成本。

### 边界情况

1. **空输入处理**: `is_empty()` 仅检查内部状态，不触发重新计算。

2. **粘贴大文本**: 超过 `LARGE_PASTE_CHAR_THRESHOLD` (1000字符) 时使用占位符，需要调用方处理 `pending_pastes`。

3. **并发安全**: 使用 `tokio::sync::mpsc` 无界通道，理论上可能内存溢出（如果生产者远快于消费者）。

### 改进建议

1. **配置化构造器**: 添加 `ComposerInput::with_config()` 允许自定义 placeholder 和功能开关。

2. **事件回调机制**: 提供可选的事件回调接口，让调用方能够处理感兴趣的 `AppEvent`。

3. **统一实现**: 考虑将 `tui` 和 `tui_app_server` 的公共代码提取到共享 crate，避免重复。

4. **文档完善**: 添加更多使用示例，特别是关于 paste burst 和 footer hint 的用法。

5. **测试覆盖**: 当前文件没有单元测试，建议添加基础的功能测试。

### 代码规范遵循

根据 `AGENTS.md` 的要求，该代码：
- 遵循了 `format!` 内联变量规范
- 使用了方法引用而非闭包
- 避免了 `bool` 参数的模糊性（通过 `/*param_name*/` 注释）
- 遵循了 TUI 样式约定（使用 `Stylize` trait）
