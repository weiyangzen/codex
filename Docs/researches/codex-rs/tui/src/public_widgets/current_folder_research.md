# codex-rs/tui/src/public_widgets 目录研究文档

## 目录

- [1. 场景与职责](#1-场景与职责)
- [2. 功能点目的](#2-功能点目的)
- [3. 具体技术实现](#3-具体技术实现)
  - [3.1 关键流程](#31-关键流程)
  - [3.2 数据结构](#32-数据结构)
  - [3.3 协议与接口](#33-协议与接口)
- [4. 关键代码路径与文件引用](#4-关键代码路径与文件引用)
- [5. 依赖与外部交互](#5-依赖与外部交互)
- [6. 风险、边界与改进建议](#6-风险边界与改进建议)

---

## 1. 场景与职责

`public_widgets` 目录是 `codex-tui` crate 的**公共组件库**，旨在将内部成熟的 TUI 组件以简化的 API 暴露给其他 crate 使用。

### 核心定位

| 维度 | 说明 |
|------|------|
| **设计目标** | 提供可复用的文本输入组件，封装复杂的内部实现细节 |
| **主要使用方** | `codex-cloud-tasks` crate（用于创建新任务的输入界面） |
| **架构角色** | 作为 `ChatComposer` 的轻量级包装器，屏蔽内部状态机复杂性 |
| **复用范围** | 跨 crate 边界，支持多行输入、粘贴启发式、Enter 提交、Shift+Enter 换行等成熟行为 |

### 与内部组件的关系

```
┌─────────────────────────────────────────────────────────────┐
│                    外部使用者 (如 cloud-tasks)                 │
│                         ComposerInput                         │
│                    (public_widgets/composer_input.rs)        │
└─────────────────────────────┬───────────────────────────────┘
                              │ 包装/简化
┌─────────────────────────────▼───────────────────────────────┐
│                      ChatComposer                            │
│                 (bottom_pane/chat_composer.rs)               │
│  - 复杂的状态机 (UI mode + Paste burst)                      │
│  - 弹窗管理 (Command/File/Skill popup)                       │
│  - 历史导航、语音输入、图片附件等                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 ComposerInput 组件功能

`ComposerInput` 是一个**最小化的公共包装器**，提供以下核心能力：

| 功能 | 说明 | 对应方法 |
|------|------|----------|
| **多行文本输入** | 支持复杂的文本编辑，包括粘贴大段内容 | `input()`, `handle_paste()` |
| **智能提交** | Enter 键提交，Shift+Enter 换行 | `input()` |
| **粘贴爆发检测** | 处理非括号粘贴的终端输入（特别是 Windows） | `is_in_paste_burst()`, `flush_paste_burst_if_due()` |
| **底部提示定制** | 允许自定义 footer hint 显示 | `set_hint_items()`, `clear_hint_items()` |
| **布局计算** | 提供所需高度和光标位置计算 | `desired_height()`, `cursor_pos()` |
| **渲染** | 基于 ratatui 的渲染接口 | `render_ref()` |

### 2.2 设计取舍

**刻意简化的地方：**

1. **禁用复杂功能**：`ComposerInput` 使用 `ChatComposerConfig::default()`，保留了所有默认功能，但通过简化 API 屏蔽了：
   - 弹窗管理（Command/File/Skill popup）
   - 斜杠命令处理
   - 历史导航
   - 语音输入
   - 图片附件（部分场景）

2. **事件简化**：将 `ChatComposer` 返回的复杂 `InputResult` 简化为二元的 `ComposerAction`：
   ```rust
   pub enum ComposerAction {
       Submitted(String),  // 用户提交了文本
       None,               // 无提交，可能需要重绘
   }
   ```

3. **自动事件排空**：内部使用 `drain_app_events()` 自动处理 `AppEvent` 通道，使用者无需关心内部事件循环。

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 创建流程

```rust
// 1. 创建 unbounded channel 用于 AppEvent 通信
let (tx, rx) = tokio::sync::mpsc::unbounded_channel();

// 2. 创建 AppEventSender（内部事件发送器包装）
let sender = AppEventSender::new(tx.clone());

// 3. 创建内部 ChatComposer 实例
let inner = ChatComposer::new(
    /*has_input_focus*/ true,
    sender,
    /*enhanced_keys_supported*/ true,  // 启用 Shift+Enter 行为
    "Compose new task".to_string(),     // placeholder 文本
    /*disable_paste_burst*/ false,      // 启用粘贴爆发检测
);

// 4. 组装 ComposerInput
Self { inner, _tx: tx, rx }
```

#### 3.1.2 键盘输入处理流程

```
用户按键 ──► ComposerInput::input(key) ──► ChatComposer::handle_key_event(key)
                                               │
                                               ▼
                                    ┌──────────────────────┐
                                    │   解析 InputResult    │
                                    │  - Submitted { text } │──► ComposerAction::Submitted(text)
                                    │  - Queued { ... }     │
                                    │  - Command(_)         │──► ComposerAction::None
                                    │  - None               │
                                    └──────────────────────┘
                                               │
                                               ▼
                                    drain_app_events() // 排空内部事件
```

#### 3.1.3 粘贴处理流程

```
粘贴事件 ──► ComposerInput::handle_paste(text) ──► ChatComposer::handle_paste(text)
                                                          │
                                                          ▼
                                               ┌─────────────────────┐
                                               │  处理大粘贴阈值      │
                                               │  (>1000字符)        │
                                               │  - 创建占位符元素    │
                                               │  - 存储实际内容      │
                                               └─────────────────────┘
                                                          │
                                               ┌─────────────────────┐
                                               │  处理图片路径粘贴    │
                                               │  - 检测图片文件      │
                                               │  - 附加为图片元素    │
                                               └─────────────────────┘
                                                          │
                                               ┌─────────────────────┐
                                               │  普通文本粘贴        │
                                               │  - 直接插入 textarea │
                                               └─────────────────────┘
```

#### 3.1.4 粘贴爆发检测流程（Windows 终端兼容）

```
字符输入 ──► 是否粘贴爆发中? 
    │
    ├─ 是 ──► 追加到爆发缓冲区
    │
    └─ 否 ──► 是否快速连续输入?
              │
              ├─ 是 ──► 开始爆发检测 ──► 缓冲字符
              │
              └─ 否 ──► 正常输入处理

定时器触发 ──► flush_paste_burst_if_due() ──► 将缓冲区内容作为粘贴处理
```

### 3.2 数据结构

#### 3.2.1 ComposerInput 结构

```rust
pub struct ComposerInput {
    /// 内部的 ChatComposer 实例
    inner: ChatComposer,
    
    /// AppEvent 发送端（保留以防止通道关闭）
    _tx: tokio::sync::mpsc::UnboundedSender<AppEvent>,
    
    /// AppEvent 接收端（用于排空内部事件）
    rx: tokio::sync::mpsc::UnboundedReceiver<AppEvent>,
}
```

#### 3.2.2 ComposerAction 枚举

```rust
pub enum ComposerAction {
    /// 用户提交了当前文本（通常通过 Enter）
    Submitted(String),
    /// 未发生提交；如果 needs_redraw() 返回 true，UI 可能需要重绘
    None,
}
```

#### 3.2.3 内部 ChatComposer 关键状态（供参考）

```rust
pub(crate) struct ChatComposer {
    textarea: TextArea,
    textarea_state: RefCell<TextAreaState>,
    active_popup: ActivePopup,           // None | Command | File | Skill
    app_event_tx: AppEventSender,
    history: ChatComposerHistory,
    pending_pastes: Vec<(String, String)>, // (placeholder, actual_content)
    attached_images: Vec<AttachedImage>,
    paste_burst: PasteBurst,             // 粘贴爆发检测状态机
    config: ChatComposerConfig,          // 功能开关配置
    // ... 更多字段
}
```

#### 3.2.4 ChatComposerConfig（功能门控）

```rust
#[derive(Clone, Copy, Debug)]
pub(crate) struct ChatComposerConfig {
    /// 是否允许命令/文件/技能弹窗
    pub(crate) popups_enabled: bool,
    /// 是否解析 `/...` 输入为斜杠命令
    pub(crate) slash_commands_enabled: bool,
    /// 粘贴文件路径时是否可以附加本地图片
    pub(crate) image_paste_enabled: bool,
}

impl Default for ChatComposerConfig {
    fn default() -> Self {
        Self {
            popups_enabled: true,
            slash_commands_enabled: true,
            image_paste_enabled: true,
        }
    }
}
```

### 3.3 协议与接口

#### 3.3.1 公共 API 接口

| 方法 | 签名 | 用途 |
|------|------|------|
| `new` | `pub fn new() -> Self` | 创建新的输入组件 |
| `is_empty` | `pub fn is_empty(&self) -> bool` | 检查输入是否为空 |
| `clear` | `pub fn clear(&mut self)` | 清空输入文本 |
| `input` | `pub fn input(&mut self, key: KeyEvent) -> ComposerAction` | 处理键盘事件 |
| `handle_paste` | `pub fn handle_paste(&mut self, pasted: String) -> bool` | 处理粘贴内容 |
| `set_hint_items` | `pub fn set_hint_items(&mut self, items: Vec<(impl Into<String>, impl Into<String>)>)` | 设置底部提示 |
| `clear_hint_items` | `pub fn clear_hint_items(&mut self)` | 清除自定义提示 |
| `desired_height` | `pub fn desired_height(&self, width: u16) -> u16` | 计算所需高度 |
| `cursor_pos` | `pub fn cursor_pos(&self, area: Rect) -> Option<(u16, u16)>` | 获取光标位置 |
| `render_ref` | `pub fn render_ref(&self, area: Rect, buf: &mut Buffer)` | 渲染组件 |
| `is_in_paste_burst` | `pub fn is_in_paste_burst(&self) -> bool` | 检查是否在粘贴爆发中 |
| `flush_paste_burst_if_due` | `pub fn flush_paste_burst_if_due(&mut self) -> bool` | 刷新粘贴爆发 |
| `recommended_flush_delay` | `pub fn recommended_flush_delay() -> Duration` | 获取推荐刷新延迟 |

#### 3.3.2 渲染协议

`ComposerInput` 实现了 ratatui 的渲染模式：

```rust
// 使用 WidgetRef 模式进行渲染
pub fn render_ref(&self, area: Rect, buf: &mut Buffer) {
    self.inner.render(area, buf);
}
```

渲染流程内部使用 `Renderable` trait：
- `render(area, buf)`：在给定区域渲染
- `desired_height(width)`：计算所需高度（用于布局）
- `cursor_pos(area)`：计算光标屏幕位置

---

## 4. 关键代码路径与文件引用

### 4.1 本目录文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `mod.rs` | 1 | 模块导出，仅暴露 `composer_input` 子模块 |
| `composer_input.rs` | 135 | `ComposerInput` 公共组件实现 |

### 4.2 核心依赖文件

| 文件 | 职责 | 与本目录关系 |
|------|------|-------------|
| `codex-rs/tui/src/bottom_pane/chat_composer.rs` | `ChatComposer` 完整实现，约 3000+ 行 | 被 `ComposerInput` 包装使用 |
| `codex-rs/tui/src/bottom_pane/mod.rs` | `BottomPane` 模块，管理 composer 和弹窗 | 导出 `ChatComposer` 和 `InputResult` |
| `codex-rs/tui/src/bottom_pane/paste_burst.rs` | 粘贴爆发检测状态机 | 被 `ChatComposer` 使用 |
| `codex-rs/tui/src/bottom_pane/textarea.rs` | 文本区域编辑实现 | 被 `ChatComposer` 使用 |
| `codex-rs/tui/src/render/renderable.rs` | `Renderable` trait 定义 | 渲染接口契约 |
| `codex-rs/tui/src/app_event.rs` | `AppEvent` 事件定义 | 内部事件通信 |
| `codex-rs/tui/src/app_event_sender.rs` | `AppEventSender` 实现 | 事件发送包装器 |

### 4.3 调用方文件

| 文件 | 用途 |
|------|------|
| `codex-rs/cloud-tasks/src/new_task.rs` | `NewTaskPage` 使用 `ComposerInput` 作为任务输入组件 |
| `codex-rs/cloud-tasks/src/lib.rs` | 主事件循环中处理 `ComposerInput` 的粘贴爆发刷新 |
| `codex-rs/tui/src/lib.rs` | 导出 `ComposerInput` 和 `ComposerAction` 供外部使用 |
| `codex-rs/tui_app_server/src/lib.rs` | 同样导出 `ComposerInput`（tui_app_server 版本） |
| `codex-rs/tui_app_server/src/public_widgets/composer_input.rs` | tui_app_server 的并行实现 |

### 4.4 关键代码路径示例

**路径 1：键盘输入处理**
```
codex-rs/tui/src/public_widgets/composer_input.rs:62-69
    └─> ChatComposer::handle_key_event()
        └─> codex-rs/tui/src/bottom_pane/chat_composer.rs:1295-1347
            ├─> handle_key_event_without_popup() (无弹窗时)
            │   └─> handle_submission() (Enter 提交)
            │       └─> prepare_submission_text()
            └─> sync_popups() (同步弹窗状态)
```

**路径 2：粘贴处理**
```
codex-rs/tui/src/public_widgets/composer_input.rs:71-75
    └─> ChatComposer::handle_paste()
        └─> codex-rs/tui/src/bottom_pane/chat_composer.rs:776-798
            ├─> 大粘贴检测 (>1000字符)
            ├─> 图片路径检测
            └─> 普通文本插入
```

**路径 3：渲染**
```
codex-rs/tui/src/public_widgets/composer_input.rs:103-105
    └─> ChatComposer::render()
        └─> codex-rs/tui/src/bottom_pane/chat_composer.rs (渲染实现)
            └─> 使用 Renderable trait 方法
```

---

## 5. 依赖与外部交互

### 5.1 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `crossterm` | 终端事件（`KeyEvent`, `KeyCode` 等） |
| `ratatui` | TUI 渲染框架（`Buffer`, `Rect` 等） |
| `tokio` | 异步运行时（`mpsc::unbounded_channel`） |
| `std::time::Duration` | 时间间隔处理 |

### 5.2 内部模块依赖

```
public_widgets/composer_input.rs
│
├─> crate::app_event::AppEvent
├─> crate::app_event_sender::AppEventSender
├─> crate::bottom_pane::ChatComposer
├─> crate::bottom_pane::InputResult
└─> crate::render::renderable::Renderable
```

### 5.3 跨 crate 依赖

```
codex-cloud-tasks
│
├─> codex_tui::ComposerInput (外部依赖)
│   └─> 内部使用 codex-tui 的各种模块
│
└─> 使用 ComposerInput 构建 NewTaskPage
```

### 5.4 事件流交互

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   用户输入      │────►│  ComposerInput   │────►│   ChatComposer  │
│  (键盘/粘贴)    │     │                  │     │                 │
└─────────────────┘     └──────────────────┘     └────────┬────────┘
                                                         │
                              ┌──────────────────────────┘
                              ▼
                    ┌──────────────────┐
                    │  AppEventSender  │
                    │   (内部通道)      │
                    └────────┬─────────┘
                             │
                              ▼
                    ┌──────────────────┐
                    │   rx (接收端)     │◄── ComposerInput::drain_app_events()
                    └──────────────────┘
```

**注意**：`ComposerInput` 通过 `drain_app_events()` 自动排空内部事件，使用者无需处理 `AppEvent`。

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 严重程度 | 说明 |
|------|----------|------|
| **事件丢失** | 中 | `drain_app_events()` 使用 `try_recv()` 非阻塞排空，如果事件产生速度快于处理速度，可能丢失事件（但实践中极少发生） |
| **粘贴爆发延迟** | 低 | 首字符在粘贴爆发检测时会有短暂延迟（约 20ms），在慢速终端上可能感知为输入延迟 |
| **配置不一致** | 中 | `ComposerInput` 使用默认配置，如果内部 `ChatComposer` 默认行为改变，可能影响外部使用者 |
| **内存泄漏** | 低 | `_tx` 字段仅用于保持通道打开，但通道另一端如果没有正确处理，可能导致资源滞留 |

### 6.2 边界条件

| 场景 | 行为 |
|------|------|
| **空输入提交** | `ChatComposer` 会阻止空输入提交，`ComposerAction::Submitted` 不会返回空字符串 |
| **超大粘贴 (>1000字符)** | 创建占位符元素，实际内容存储在 `pending_pastes` 中，提交时展开 |
| **快速连续 Enter** | 在粘贴爆发窗口期内，Enter 被当作换行而非提交 |
| **Shift+Enter** | 在 `enhanced_keys_supported=true` 时，始终作为换行 |
| **终端不支持增强键** | 回退到普通行为，Shift+Enter 可能与普通 Enter 无法区分 |

### 6.3 改进建议

#### 6.3.1 短期改进

1. **添加配置选项暴露**
   ```rust
   // 建议：允许使用者传入自定义配置
   pub fn with_config(config: ChatComposerConfig) -> Self
   ```
   当前 `ComposerInput` 硬编码使用默认配置，某些场景可能需要禁用特定功能。

2. **添加提交前回调**
   ```rust
   // 建议：允许使用者验证/修改提交内容
   pub fn set_submission_validator<F: Fn(&str) -> bool>(validator: F)
   ```

3. **改善文档**
   - 添加使用示例代码
   - 说明 `ComposerAction::None` 时何时需要重绘

#### 6.3.2 中期改进

1. **统一 tui 和 tui_app_server 实现**
   - 当前两个 crate 有几乎相同的 `ComposerInput` 实现
   - 建议提取到公共 crate 或宏来避免代码重复

2. **添加测试覆盖**
   - 当前 `public_widgets` 目录没有独立测试
   - 建议添加集成测试验证包装行为

3. **暴露更多内部状态**
   - 如当前输入字符数、是否可提交等，便于外部 UI 状态同步

#### 6.3.3 长期改进

1. **抽象渲染接口**
   - 当前依赖 ratatui 特定类型，考虑抽象渲染接口以支持其他 TUI 框架

2. **插件化扩展**
   - 允许外部注册自定义命令处理器、自定义粘贴处理器等

### 6.4 相关文档参考

| 文档 | 位置 | 内容 |
|------|------|------|
| Chat Composer 状态机文档 | `docs/tui-chat-composer.md` | 详细的粘贴爆发检测、提交流程说明 |
| Bottom Pane AGENTS.md | `codex-rs/tui/src/bottom_pane/AGENTS.md` | 状态机变更时的文档同步要求 |
| TUI 样式指南 | `codex-rs/tui/styles.md` | 颜色、样式使用规范 |

---

## 附录：代码统计

| 指标 | 数值 |
|------|------|
| 本目录代码行数 | ~136 行（含注释） |
| 依赖的内部代码 | ~3000+ 行（ChatComposer） |
| 公共 API 方法数 | 13 个 |
| 使用方 crate 数 | 2 个（cloud-tasks, tui_app_server） |

---

*文档生成时间：2026-03-22*
*研究范围：codex-rs/tui/src/public_widgets 目录及其直接依赖*
