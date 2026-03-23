# key_hint.rs 研究文档

## 场景与职责

`key_hint.rs` 是 Codex TUI 应用服务器中负责**键盘快捷键提示渲染**的专用模块。它提供了一个轻量级的抽象层，将 `crossterm` 的键盘事件类型（`KeyCode`, `KeyModifiers`）转换为适合 UI 显示的 `ratatui::text::Span`，用于在界面各处（页脚、弹窗、提示行等）展示快捷键帮助信息。

### 核心职责
1. **快捷键绑定抽象**：封装 `KeyCode` + `KeyModifiers` 为 `KeyBinding` 结构体
2. **事件匹配**：提供 `is_press` 方法检测按键事件是否匹配绑定
3. **跨平台显示**：根据平台（macOS/其他）显示不同的修饰符符号（⌥ vs alt）
4. **UI 集成**：实现 `From<KeyBinding> for Span` 以便直接用于 ratatui 渲染

## 功能点目的

### 1. 快捷键绑定 (`KeyBinding`)

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct KeyBinding {
    key: KeyCode,
    modifiers: KeyModifiers,
}
```

**设计意图**：
- 不可变结构（字段私有，构造通过关联函数）
- 支持常量构造（`const fn new`），允许模块级预定义快捷键
- 复制语义（`Copy`），便于在 UI 组件间传递

### 2. 事件匹配 (`is_press`)

```rust
pub fn is_press(&self, event: KeyEvent) -> bool {
    self.key == event.code
        && self.modifiers == event.modifiers
        && (event.kind == KeyEventKind::Press || event.kind == KeyEventKind::Repeat)
}
```

**关键细节**：
- 忽略 `KeyEventKind::Release`（仅响应按下和重复）
- 严格匹配修饰符（不支持"至少包含"语义）
- 用于路由决策：哪个组件处理此按键

### 3. 跨平台修饰符显示

```rust
#[cfg(test)]
const ALT_PREFIX: &str = "⌥ + ";
#[cfg(all(not(test), target_os = "macos"))]
const ALT_PREFIX: &str = "⌥ + ";
#[cfg(all(not(test), not(target_os = "macos")))]
const ALT_PREFIX: &str = "alt + ";
```

| 平台 | Alt 显示 | Ctrl 显示 | Shift 显示 |
|------|----------|-----------|------------|
| macOS | ⌥ | ctrl | shift |
| 其他 | alt | ctrl | shift |
| 测试 | ⌥（模拟 macOS） | - | - |

### 4. 特殊键名映射

```rust
let key = match key {
    KeyCode::Enter => "enter".to_string(),
    KeyCode::Char(' ') => "space".to_string(),
    KeyCode::Up => "↑".to_string(),      // Unicode 上箭头
    KeyCode::Down => "↓".to_string(),    // Unicode 下箭头
    KeyCode::Left => "←".to_string(),    // Unicode 左箭头
    KeyCode::Right => "→".to_string(),   // Unicode 右箭头
    KeyCode::PageUp => "pgup".to_string(),
    KeyCode::PageDown => "pgdn".to_string(),
    _ => format!("{key}").to_ascii_lowercase(),
};
```

**样式**：所有提示使用 `dim()` 样式（灰色/暗淡显示）

## 具体技术实现

### 构造辅助函数

```rust
pub(crate) const fn plain(key: KeyCode) -> KeyBinding {
    KeyBinding::new(key, KeyModifiers::NONE)
}

pub(crate) const fn alt(key: KeyCode) -> KeyBinding {
    KeyBinding::new(key, KeyModifiers::ALT)
}

pub(crate) const fn shift(key: KeyCode) -> KeyBinding {
    KeyBinding::new(key, KeyModifiers::SHIFT)
}

pub(crate) const fn ctrl(key: KeyCode) -> KeyBinding {
    KeyBinding::new(key, KeyModifiers::CONTROL)
}

pub(crate) const fn ctrl_alt(key: KeyCode) -> KeyBinding {
    KeyBinding::new(key, KeyModifiers::CONTROL.union(KeyModifiers::ALT))
}
```

### AltGr 检测（Windows 特殊处理）

```rust
#[cfg(windows)]
pub(crate) fn is_altgr(mods: KeyModifiers) -> bool {
    mods.contains(KeyModifiers::ALT) && mods.contains(KeyModifiers::CONTROL)
}

#[cfg(not(windows))]
pub(crate) fn is_altgr(_mods: KeyModifiers) -> bool {
    false
}
```

**用途**：`has_ctrl_or_alt` 函数排除 AltGr（右 Alt）组合，避免误触发

### Span 转换实现

```rust
impl From<&KeyBinding> for Span<'static> {
    fn from(binding: &KeyBinding) -> Self {
        let KeyBinding { key, modifiers } = binding;
        let modifiers = modifiers_to_string(*modifiers);
        let key = /* 特殊键名映射 */;
        Span::styled(format!("{modifiers}{key}"), key_hint_style())
    }
}
```

**使用模式**：
```rust
// 在 UI 代码中直接转换
let hint: Span = key_hint::ctrl(KeyCode::Char('c')).into();

// 或在 Line 构造中使用
let line: Line = vec![
    "Press ".dim(),
    key_hint::plain(KeyCode::Enter).into(),
    " to continue".dim(),
];
```

## 关键代码路径与文件引用

### 定义位置

```
codex-rs/tui_app_server/src/key_hint.rs
├── KeyBinding 结构体定义
├── is_press 方法
├── 构造辅助函数（plain, alt, shift, ctrl, ctrl_alt）
├── Span 转换实现
└── is_altgr / has_ctrl_or_alt 工具函数
```

### 主要使用方

| 文件 | 使用场景 |
|------|----------|
| `pager_overlay.rs` | 分页器导航提示（↑/↓/PgUp/PgDn/q 等） |
| `bottom_pane/footer.rs` | 页脚快捷键提示（shift+tab, ? 等） |
| `bottom_pane/mod.rs` | 底部面板快捷键处理 |
| `resume_picker.rs` | 会话选择器提示（Enter/Esc/Ctrl+C/Tab 等） |
| `update_prompt.rs` | 更新提示（Enter） |
| `cwd_prompt.rs` | 工作目录提示（Enter） |
| `model_migration.rs` | 模型迁移提示（↑/↓/Enter） |
| `multi_agents.rs` | 多代理导航（Alt+←/Alt+→） |
| `status_indicator_widget.rs` | 状态指示器（Esc 中断） |
| `tui/job_control.rs` | 作业控制（Ctrl+Z 挂起） |

### 典型使用模式

**页脚提示**（`footer.rs`）：
```rust
use crate::key_hint;
use crate::key_hint::KeyBinding;

// 定义快捷键常量
const MODE_CYCLE_HINT: &str = "shift+tab to cycle";

// 在 FooterProps 中使用
pub(crate) struct FooterProps {
    pub(crate) quit_shortcut_key: KeyBinding,
    // ...
}
```

**分页器**（`pager_overlay.rs`）：
```rust
const KEY_UP: KeyBinding = key_hint::plain(KeyCode::Up);
const KEY_DOWN: KeyBinding = key_hint::plain(KeyCode::Down);
const KEY_Q: KeyBinding = key_hint::plain(KeyCode::Char('q'));

const PAGER_KEY_HINTS: &[(&[KeyBinding], &str)] = &[
    (&[KEY_UP, KEY_DOWN], "to scroll"),
    (&[KEY_PAGE_UP, KEY_PAGE_DOWN], "to page"),
    (&[KEY_Q], "to quit"),
];

fn render_key_hints(area: Rect, buf: &mut Buffer, pairs: &[(&[KeyBinding], &str)]) {
    // 将 KeyBinding 转换为 Span 并渲染
}
```

**多代理导航**（`multi_agents.rs`）：
```rust
pub(crate) fn previous_agent_shortcut() -> crate::key_hint::KeyBinding {
    crate::key_hint::alt(KeyCode::Left)
}

pub(crate) fn next_agent_shortcut() -> crate::key_hint::KeyBinding {
    crate::key_hint::alt(KeyCode::Right)
}
```

## 依赖与外部交互

### 外部 crate

| Crate | 类型 | 用途 |
|-------|------|------|
| `crossterm` | 外部 | `KeyCode`, `KeyEvent`, `KeyEventKind`, `KeyModifiers` |
| `ratatui` | 外部 | `Span`, `Style`, `Stylize` trait |

### 模块依赖图

```
key_hint.rs
    ├── crossterm::event::{KeyCode, KeyEvent, KeyEventKind, KeyModifiers}
    └── ratatui::{style::*, text::Span}

使用方模块
    ├── key_hint::KeyBinding
    ├── key_hint::plain/alt/shift/ctrl/ctrl_alt
    ├── key_hint::has_ctrl_or_alt
    └── Into<Span> trait
```

### 无内部依赖

`key_hint.rs` 是一个**叶节点模块**，不依赖任何其他内部模块，便于单元测试和复用。

## 风险、边界与改进建议

### 已知限制

1. **严格修饰符匹配**
   - `is_press` 要求修饰符完全相等
   - 不支持"Ctrl+C 或 Cmd+C"的或逻辑（需定义两个绑定）

2. **平台检测编译时确定**
   - macOS 符号（⌥）在编译时决定，非运行时检测
   - 远程连接到不同平台时显示可能不匹配

3. **测试环境模拟 macOS**
   ```rust
   #[cfg(test)]
   const ALT_PREFIX: &str = "⌥ + ";
   ```
   - 测试始终使用 macOS 风格，可能掩盖跨平台问题

4. **无序列支持**
   - 不支持 Vim 风格序列（如 `gg`, `dd`）
   - 仅支持单键 + 修饰符

### 边界情况

| 场景 | 行为 |
|------|------|
| 未知 KeyCode | 使用 `format!("{key}")` 的小写形式 |
| 空修饰符 | 仅显示键名（如 "enter"） |
| 多修饰符 | 按 Ctrl → Shift → Alt 顺序显示 |
| AltGr (Windows) | `is_altgr` 返回 true，`has_ctrl_or_alt` 排除 |

### 改进建议

1. **运行时平台检测**
   ```rust
   // 当前：编译时 cfg
   // 建议：运行时检测 TERM_PROGRAM 或类似环境变量
   fn alt_prefix() -> &'static str {
       if std::env::var("TERM_PROGRAM").ok() == Some("Apple_Terminal".to_string()) {
           "⌥ + "
       } else {
           "alt + "
       }
   }
   ```

2. **宽松修饰符匹配**
   ```rust
   // 新增方法支持"至少包含"
   pub fn is_press_relaxed(&self, event: KeyEvent) -> bool {
       self.key == event.code
           && event.modifiers.contains(self.modifiers)
           && (event.kind == KeyEventKind::Press || event.kind == KeyEventKind::Repeat)
   }
   ```

3. **宏支持批量定义**
   ```rust
   // 建议添加宏
   define_keys! {
       QUIT => ctrl(KeyCode::Char('c')),
       SAVE => ctrl(KeyCode::Char('s')),
   }
   ```

4. **序列支持**
   - 如需支持 Vim 风格，可扩展为 `KeySequence` 类型
   - 或保持简单，由调用方处理序列状态机

5. **测试改进**
   - 添加跨平台显示测试
   - 测试所有特殊键名映射
   - 测试 AltGr 边界情况

### 代码风格一致性

根据 `AGENTS.md` 的 TUI 风格指南：

> - Use concise styling helpers from ratatui's Stylize trait.
> - Prefer `Span::from` or `.into()` for simple spans

`key_hint.rs` 符合该风格：
```rust
Span::styled(format!("{modifiers}{key}"), key_hint_style())
// 使用 Stylize trait 的调用方：
"Press ".dim(), key_hint::plain(KeyCode::Enter).into()
```

### 与 TUI 并行实现的关系

根据 `AGENTS.md`：
> When a change lands in `codex-rs/tui` and `codex-rs/tui_app_server` has a parallel implementation of the same behavior, reflect the change in `codex-rs/tui_app_server` too unless there is a documented reason not to.

`key_hint.rs` 是 `tui_app_server` 特有的，原 `tui` crate 可能有类似功能。如需保持行为一致，应检查两者差异。
