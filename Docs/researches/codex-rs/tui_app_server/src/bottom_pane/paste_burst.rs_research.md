# paste_burst.rs 深入研究

## 场景与职责

`paste_burst.rs` 是 TUI 应用服务器中负责**粘贴爆发检测**的核心模块。该模块解决了一个特定的跨平台终端输入问题：在某些平台（特别是 Windows）上，终端粘贴操作不会作为单个"粘贴"事件传递，而是表现为快速的 `KeyCode::Char` 和 `KeyCode::Enter` 按键事件流。

### 核心问题

1. **UI 副作用抑制**：防止粘贴内容中的字符（如 `?`）触发绑定的切换功能
2. **Enter 键处理**：确保粘贴中的 Enter 被当作换行符处理，而非"提交消息"
3. **闪烁抑制**：避免先插入字符作为普通输入，然后又重新分类为粘贴导致的视觉闪烁

### 架构定位

该模块是一个**纯状态机**，不直接操作文本区域，而是由调用者（`ChatComposer`）提供事件并根据决策执行相应操作。这种设计确保了关注点分离和可测试性。

---

## 功能点目的

### 1. 粘贴爆发检测

通过时间启发式算法检测"粘贴式"输入流：
- **最小字符阈值**：`PASTE_BURST_MIN_CHARS = 3`，至少需要 3 个快速连续字符才触发
- **字符间隔阈值**：
  - 非 Windows: 8ms (`PASTE_BURST_CHAR_INTERVAL`)
  - Windows: 30ms（Windows 终端传递事件更慢）
- **空闲超时**：
  - 非 Windows: 8ms (`PASTE_BURST_ACTIVE_IDLE_TIMEOUT`)
  - Windows: 60ms

### 2. 首字符保持（Flicker Suppression）

对于 ASCII 输入，第一个快速字符会被短暂保持（不立即渲染），等待判断是否为粘贴爆发的一部分：
- 如果后续有快速字符跟随 → 开始缓冲，首字符作为粘贴的一部分
- 如果超时无后续字符 → 作为普通输入字符刷新

### 3. 回退捕获（Retro Capture）

处理已作为普通输入插入的字符被重新识别为粘贴的一部分的情况：
- 当检测到粘贴模式时，可以从文本区域"回退"已插入的前缀
- 启发式判断：如果回退内容包含空白字符或长度 ≥16 字符，则视为粘贴

### 4. Enter 抑制窗口

粘贴完成后，在短暂窗口期内（120ms）保持 Enter 键作为换行符处理：
- 支持多行粘贴的场景
- 窗口期后 Enter 恢复为提交功能

---

## 具体技术实现

### 核心数据结构

```rust
#[derive(Default)]
pub(crate) struct PasteBurst {
    last_plain_char_time: Option<Instant>,      // 最后普通字符时间
    consecutive_plain_char_burst: u16,          // 连续普通字符计数
    burst_window_until: Option<Instant>,        // Enter 抑制窗口截止时间
    buffer: String,                             // 积累的爆发缓冲区
    active: bool,                               // 是否处于活跃缓冲状态
    pending_first_char: Option<(char, Instant)>, // 保持的首字符（闪烁抑制）
}
```

### 决策枚举

```rust
pub(crate) enum CharDecision {
    BeginBuffer { retro_chars: u16 },  // 开始缓冲，可能回退已插入字符
    BufferAppend,                       // 追加到现有缓冲区
    RetainFirstChar,                    // 保持首字符（等待判断）
    BeginBufferFromPending,             // 从保持的首字符开始缓冲
}

pub(crate) enum FlushResult {
    Paste(String),  // 作为粘贴刷新
    Typed(char),    // 作为普通输入字符刷新
    None,           // 无内容刷新
}

pub(crate) struct RetroGrab {
    pub start_byte: usize,  // 回退起始字节位置
    pub grabbed: String,    // 回退的文本内容
}
```

### 关键流程

#### 1. 普通字符处理流程（ASCII）

```rust
pub fn on_plain_char(&mut self, ch: char, now: Instant) -> CharDecision {
    self.note_plain_char(now);  // 更新计数和时间

    if self.active {
        // 已在缓冲状态，直接追加
        self.burst_window_until = Some(now + PASTE_ENTER_SUPPRESS_WINDOW);
        return CharDecision::BufferAppend;
    }

    // 检查是否有保持的首字符且时间间隔在阈值内
    if let Some((held, held_at)) = self.pending_first_char
        && now.duration_since(held_at) <= PASTE_BURST_CHAR_INTERVAL
    {
        // 开始缓冲，使用保持的首字符
        self.active = true;
        self.buffer.push(held);
        return CharDecision::BeginBufferFromPending;
    }

    // 检查是否达到最小字符阈值
    if self.consecutive_plain_char_burst >= PASTE_BURST_MIN_CHARS {
        return CharDecision::BeginBuffer { 
            retro_chars: self.consecutive_plain_char_burst.saturating_sub(1) 
        };
    }

    // 保持首字符等待后续判断
    self.pending_first_char = Some((ch, now));
    CharDecision::RetainFirstChar
}
```

#### 2. 刷新判断流程

```rust
pub fn flush_if_due(&mut self, now: Instant) -> FlushResult {
    let timeout = if self.is_active_internal() {
        PASTE_BURST_ACTIVE_IDLE_TIMEOUT
    } else {
        PASTE_BURST_CHAR_INTERVAL
    };
    
    let timed_out = self.last_plain_char_time
        .is_some_and(|t| now.duration_since(t) > timeout);
    
    if timed_out && self.is_active_internal() {
        // 缓冲状态超时，作为粘贴刷新
        self.active = false;
        let out = std::mem::take(&mut self.buffer);
        FlushResult::Paste(out)
    } else if timed_out {
        // 非缓冲状态但有保持的首字符，作为普通字符刷新
        if let Some((ch, _at)) = self.pending_first_char.take() {
            FlushResult::Typed(ch)
        } else {
            FlushResult::None
        }
    } else {
        FlushResult::None
    }
}
```

#### 3. 回退捕获决策

```rust
pub fn decide_begin_buffer(
    &mut self,
    now: Instant,
    before: &str,
    retro_chars: usize,
) -> Option<RetroGrab> {
    let start_byte = retro_start_index(before, retro_chars);
    let grabbed = before[start_byte..].to_string();
    
    // 启发式：包含空白或长度≥16视为粘贴
    let looks_pastey = grabbed.chars().any(char::is_whitespace) 
        || grabbed.chars().count() >= 16;
    
    if looks_pastey {
        self.begin_with_retro_grabbed(grabbed.clone(), now);
        Some(RetroGrab { start_byte, grabbed })
    } else {
        None
    }
}
```

### 平台差异处理

```rust
#[cfg(not(windows))]
const PASTE_BURST_CHAR_INTERVAL: Duration = Duration::from_millis(8);
#[cfg(windows)]
const PASTE_BURST_CHAR_INTERVAL: Duration = Duration::from_millis(30);

#[cfg(not(windows))]
const PASTE_BURST_ACTIVE_IDLE_TIMEOUT: Duration = Duration::from_millis(8);
#[cfg(windows)]
const PASTE_BURST_ACTIVE_IDLE_TIMEOUT: Duration = Duration::from_millis(60);
```

Windows 使用更宽松的阈值，因为 Windows 终端（特别是 VS Code 集成终端）传递粘贴事件更慢。

---

## 关键代码路径与文件引用

### 核心实现文件

| 文件 | 职责 |
|------|------|
| `codex-rs/tui_app_server/src/bottom_pane/paste_burst.rs` | 粘贴爆发检测状态机实现 |
| `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs` | 调用者，集成 PasteBurst 到输入处理 |

### 关键调用点（ChatComposer 中）

```rust
// 在 chat_composer.rs 中
use crate::bottom_pane::paste_burst::FlushResult;

// 处理普通字符输入
match self.paste_burst.on_plain_char(ch, now) {
    CharDecision::RetainFirstChar => { /* 不立即插入 */ }
    CharDecision::BeginBufferFromPending => { /* 开始缓冲 */ }
    CharDecision::BeginBuffer { retro_chars } => { /* 可能回退捕获 */ }
    CharDecision::BufferAppend => { /* 追加到缓冲区 */ }
}

// UI tick 时检查刷新
match self.paste_burst.flush_if_due(now) {
    FlushResult::Paste(text) => { /* 作为粘贴处理 */ }
    FlushResult::Typed(ch) => { /* 作为普通字符插入 */ }
    FlushResult::None => {}
}

// 非字符输入前刷新缓冲区
if let Some(text) = self.paste_burst.flush_before_modified_input() {
    // 处理积累的缓冲内容
}
```

### 测试覆盖

模块包含全面的单元测试：
- `ascii_first_char_is_held_then_flushes_as_typed`：首字符保持和超时刷新
- `ascii_two_fast_chars_start_buffer_from_pending_and_flush_as_paste`：双字符触发粘贴
- `flush_before_modified_input_includes_pending_first_char`：非字符输入前刷新
- `decide_begin_buffer_only_triggers_for_pastey_prefixes`：回退捕获启发式
- `newline_suppression_window_outlives_buffer_flush`：Enter 抑制窗口

---

## 依赖与外部交互

### 内部依赖

| 依赖 | 用途 |
|------|------|
| `std::time::{Duration, Instant}` | 时间测量和阈值判断 |

### 调用方依赖

| 调用方 | 交互方式 |
|--------|----------|
| `ChatComposer` | 通过 `on_plain_char`, `flush_if_due`, `flush_before_modified_input` 等方法调用 |

### 无外部 crate 依赖

该模块是纯粹的标准库实现，不依赖任何外部 crate，确保了轻量级和可移植性。

---

## 风险、边界与改进建议

### 已知风险

1. **时间敏感性**
   - 依赖系统时间 `Instant`，在系统时间跳跃时可能行为异常
   - 高负载下可能导致误判（快速打字被识别为粘贴）

2. **平台差异复杂性**
   - Windows 和非 Windows 使用不同阈值，增加了测试复杂度
   - 某些终端模拟器可能有特殊行为未被覆盖

3. **IME/非 ASCII 输入**
   - `on_plain_char_no_hold` 路径不保持首字符，可能导致 IME 输入的闪烁
   - 非 ASCII 字符的回退捕获可能不准确

### 边界条件

| 边界 | 处理 |
|------|------|
| 空输入 | 状态机保持空闲状态 |
| 单字符快速输入 | 首字符保持后作为普通输入刷新 |
| 恰好 3 个快速字符 | 触发回退捕获，可能回退 2 个字符 |
| 极长粘贴 | 缓冲区持续增长，直到空闲超时 |
| 混合输入（粘贴+打字） | 取决于时间间隔，可能分割为多次粘贴 |

### 改进建议

1. **自适应阈值**
   - 基于用户打字速度历史动态调整阈值
   - 首次使用时进行校准

2. **更智能的回退启发式**
   - 考虑更多粘贴特征（如多行、特定字符模式）
   - 使用机器学习模型区分粘贴和快速打字

3. **配置化**
   - 允许用户通过配置调整阈值
   - 提供禁用选项（某些终端支持 bracketed paste）

4. **性能优化**
   - 当前使用 `String` 作为缓冲区，对于极长粘贴可考虑使用 `Vec<u8>` 或 rope 结构
   - 减少 `Instant::now()` 调用次数

5. **更好的 IME 支持**
   - 与 IME 状态集成，避免在 IME 组合期间触发粘贴检测
   - 检测 IME 提交事件，重置状态机

### 相关文档

- `docs/tui-chat-composer.md`：更高级别的 ChatComposer 集成视图
- 模块内文档字符串：详细的调用契约和状态说明
