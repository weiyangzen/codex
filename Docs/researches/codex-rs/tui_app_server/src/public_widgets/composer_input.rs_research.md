# composer_input.rs 研究文档

## 场景与职责

`ComposerInput` 是 `tui_app_server` crate 提供的一个公共组件，位于 `public_widgets` 模块下。它的设计目标是为其他 crate（如 `codex-cloud-tasks`）提供一个简单、可复用的文本输入组件封装。

该组件的核心职责包括：
1. **封装内部 ChatComposer**：将内部复杂的 `ChatComposer` 组件包装成一个简洁的公共 API
2. **提供标准文本输入功能**：多行输入、粘贴处理、Enter 提交、Shift+Enter 换行
3. **简化事件处理**：将底层的键盘事件转换为高级别的 `ComposerAction`（Submitted/None）
4. **支持自定义提示**：允许调用者覆盖底部提示项（footer hints）

## 功能点目的

### 1. ComposerAction 枚举
```rust
pub enum ComposerAction {
    Submitted(String),
    None,
}
```
- **Submitted(String)**：用户提交了输入（按 Enter），包含提交的文本内容
- **None**：没有发生提交，但 UI 可能需要重绘（如 `needs_redraw()` 返回 true）

### 2. ComposerInput 结构体
```rust
pub struct ComposerInput {
    inner: ChatComposer,
    _tx: tokio::sync::mpsc::UnboundedSender<AppEvent>,
    rx: tokio::sync::mpsc::UnboundedReceiver<AppEvent>,
}
```

该结构体包含：
- `inner`：内部的 `ChatComposer` 实例，负责实际的文本编辑逻辑
- `_tx`：AppEvent 发送端（使用 `_` 前缀表示保留但当前不直接使用）
- `rx`：AppEvent 接收端，用于消费 `ChatComposer` 产生的事件

### 3. 核心方法

#### new() - 构造函数
- 创建无界通道 `(tx, rx)`
- 使用 `AppEventSender::new(tx.clone())` 包装发送端
- 初始化 `ChatComposer`，启用增强键支持（Shift+Enter）
- 设置默认占位文本 "Compose new task"
- **注意**：`disable_paste_burst` 设置为 `false`，启用粘贴突发检测

#### input() - 键盘事件处理
```rust
pub fn input(&mut self, key: KeyEvent) -> ComposerAction
```
- 将键盘事件转发给 `ChatComposer::handle_key_event()`
- 根据返回的 `InputResult` 转换为 `ComposerAction`
- 调用 `drain_app_events()` 清空事件队列

#### handle_paste() - 粘贴处理
```rust
pub fn handle_paste(&mut self, pasted: String) -> bool
```
- 处理粘贴的文本内容
- 返回是否成功处理

#### 提示项管理
```rust
pub fn set_hint_items(&mut self, items: Vec<(impl Into<String>, impl Into<String>)>)
pub fn clear_hint_items(&mut self)
```
- 允许自定义底部提示项（显示为 "<key> <label>" 格式）
- 可以恢复到默认提示

#### 粘贴突发（Paste Burst）管理
```rust
pub fn is_in_paste_burst(&self) -> bool
pub fn flush_paste_burst_if_due(&mut self) -> bool
pub fn recommended_flush_delay() -> Duration
```
- 检测和处理非括号粘贴（non-bracketed paste）
- 在 Windows 等终端不支持括号粘贴的环境中特别有用

## 具体技术实现

### 关键流程

#### 1. 初始化流程
```
new()
├── 创建 unbounded_channel()
├── 创建 AppEventSender
└── 创建 ChatComposer
    ├── has_input_focus = true
    ├── enhanced_keys_supported = true
    ├── placeholder_text = "Compose new task"
    └── disable_paste_burst = false
```

#### 2. 键盘事件处理流程
```
input(key_event)
├── inner.handle_key_event(key)
│   └── 返回 (InputResult, needs_redraw)
├── 匹配 InputResult
│   ├── Submitted { text, .. } -> ComposerAction::Submitted(text)
│   └── _ -> ComposerAction::None
└── drain_app_events()
    └── while rx.try_recv().is_ok() {}
```

#### 3. 粘贴处理流程
```
handle_paste(pasted)
├── inner.handle_paste(pasted)
└── drain_app_events()
```

### 数据结构

#### AppEvent 通道
- 使用 `tokio::sync::mpsc::unbounded_channel()` 创建
- 无界通道避免阻塞，但可能消耗内存
- `ChatComposer` 通过 `AppEventSender` 发送事件
- `ComposerInput` 通过 `drain_app_events()` 消费并丢弃这些事件

#### 内部状态
- `inner: ChatComposer` - 实际的文本编辑状态机
- 包含文本缓冲区、光标位置、历史记录、附件等

### 渲染接口

`ComposerInput` 实现了与 `ratatui` 集成的渲染方法：

```rust
pub fn render_ref(&self, area: Rect, buf: &mut Buffer)
pub fn desired_height(&self, width: u16) -> u16
pub fn cursor_pos(&self, area: Rect) -> Option<(u16, u16)>
```

这些方法直接委托给内部的 `ChatComposer`。

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/public_widgets/composer_input.rs`

### 依赖文件

#### 直接依赖
| 文件路径 | 用途 |
|---------|------|
| `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs` | `ChatComposer` 内部实现 |
| `codex-rs/tui_app_server/src/bottom_pane/mod.rs` | `InputResult` 导出 |
| `codex-rs/tui_app_server/src/app_event.rs` | `AppEvent` 定义 |
| `codex-rs/tui_app_server/src/app_event_sender.rs` | `AppEventSender` 定义 |
| `codex-rs/tui_app_server/src/render/renderable.rs` | `Renderable` trait |

#### 外部 crate 依赖
| Crate | 用途 |
|-------|------|
| `crossterm` | `KeyEvent` 键盘事件 |
| `ratatui` | `Buffer`, `Rect` 渲染 |
| `tokio` | `mpsc` 异步通道 |

### 导出位置
在 `lib.rs` 中导出：
```rust
pub use public_widgets::composer_input::ComposerAction;
pub use public_widgets::composer_input::ComposerInput;
```

## 依赖与外部交互

### 与 ChatComposer 的关系

`ComposerInput` 是 `ChatComposer` 的简化封装：

| 特性 | ChatComposer | ComposerInput |
|------|-------------|---------------|
| 功能丰富度 | 完整（弹出框、斜杠命令、历史等） | 精简（仅文本输入） |
| API 复杂度 | 复杂，需要理解内部状态 | 简单，高级别 Action |
| 适用场景 | TUI 主界面 | 外部 crate 复用 |
| 事件处理 | 完整 AppEvent 处理 | 仅消费，不处理 |

### 调用方

根据代码注释，主要调用方包括：
- `codex-cloud-tasks`：云任务功能中使用

### 生命周期管理

```
ComposerInput 创建
├── ChatComposer 初始化
│   └── 内部创建 TextArea、History 等
└── AppEvent 通道创建

使用时
├── 键盘事件 -> ChatComposer 处理
├── 可能产生 AppEvent
└── drain_app_events() 清空队列

销毁时
├── Drop ChatComposer
└── Drop 通道
```

## 风险、边界与改进建议

### 风险点

#### 1. 事件丢失风险
```rust
fn drain_app_events(&mut self) {
    while self.rx.try_recv().is_ok() {}
}
```
- 当前实现只是简单地丢弃所有 AppEvent
- 如果 `ChatComposer` 产生了重要的 AppEvent（如错误、状态变更），这些事件会被静默丢弃
- **风险**：调用方无法感知内部状态变化或错误

#### 2. 无界通道内存风险
- 使用 `unbounded_channel()` 创建通道
- 如果 `drain_app_events()` 不被及时调用，事件可能累积
- 在极端情况下可能导致内存增长

#### 3. 粘贴突发检测配置
- `disable_paste_burst` 硬编码为 `false`
- 在某些终端环境中，粘贴突发检测可能产生意外行为
- 没有提供给调用方覆盖此配置的选项

### 边界情况

#### 1. 空输入处理
```rust
pub fn is_empty(&self) -> bool {
    self.inner.is_empty()
}
```
- 正确委托给内部实现
- 包含文本、附件、远程图片的综合判断

#### 2. 多行输入
- 支持 Shift+Enter 换行（通过 `enhanced_keys_supported=true`）
- 但 `ComposerAction::Submitted` 只返回单个 `String`
- 多行文本以换行符分隔

#### 3. 光标位置
```rust
pub fn cursor_pos(&self, area: Rect) -> Option<(u16, u16)>
```
- 返回 `Option`，在输入被禁用或录音时可能返回 `None`

### 改进建议

#### 1. 事件处理改进
```rust
// 建议：暴露重要事件或提供事件回调
pub enum ComposerAction {
    Submitted(String),
    Event(AppEvent),  // 新增：暴露重要事件
    None,
}

// 或者提供回调机制
pub fn set_event_callback<F>(&mut self, callback: F) 
where F: Fn(AppEvent) + Send + 'static
```

#### 2. 配置暴露
```rust
// 建议：允许调用方配置 paste_burst 行为
pub fn new_with_config(disable_paste_burst: bool) -> Self
```

#### 3. 错误处理
- 当前 API 没有错误返回机制
- 建议添加 `Result` 类型或错误回调

#### 4. 文档完善
- 添加更多使用示例
- 说明 `ComposerInput` 与 `ChatComposer` 的功能差异
- 说明何时应该使用此组件

#### 5. 测试覆盖
- 当前没有看到针对 `ComposerInput` 的单元测试
- 建议添加：
  - 基本输入/提交测试
  - 粘贴处理测试
  - 提示项设置/清除测试
  - 边界情况测试（空输入、超长文本等）

### 代码风格建议

1. **注释中的拼写**：`/*has_input_focus*/` 等注释参数格式一致，符合项目规范
2. **方法链**：`self.inner.set_footer_hint_override(Some(mapped))` 可以提取中间变量提高可读性
3. **文档**：模块级文档清晰说明了设计目的和使用场景
