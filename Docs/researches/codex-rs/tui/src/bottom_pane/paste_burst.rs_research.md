# paste_burst.rs 深度研究文档

## 场景与职责

`paste_burst.rs` 是 Codex TUI 中处理**非括号粘贴（non-bracketed paste）**的核心状态机模块。在某些终端（特别是 Windows 上的终端）中，粘贴操作不会作为单个事件到达，而是以高速字符流的形式出现。该模块负责：

1. **检测粘贴爆发（paste burst）**：识别快速连续的字符输入流
2. **防止误触发**：避免粘贴过程中触发 UI 切换（如 `?` 键）
3. **处理多行粘贴**：确保 Enter 键在粘贴过程中被视为换行而非提交
4. **消除闪烁**：避免先显示输入再重新分类为粘贴的闪烁问题

## 功能点目的

### 1. 粘贴爆发检测
- **问题**：Windows 终端上粘贴多行文本时，crossterm 报告为 `KeyCode::Char` 和 `KeyCode::Enter` 序列
- **解决方案**：使用时间和计数启发式算法检测"粘贴样"输入流

### 2. 闪烁抑制（Flicker Suppression）
- **机制**：对 ASCII 字符，短暂持有第一个快速字符，等待确认是否为粘贴
- **目的**：避免先显示字符再将其移入粘贴缓冲区的视觉闪烁

### 3. Enter 键抑制窗口
- **功能**：在爆发结束后的一段时间内，Enter 仍被视为换行而非提交
- **目的**：处理多行粘贴中 Enter 事件与字符事件之间可能存在的时间间隙

### 4. 非 ASCII/IME 输入处理
- **区别**：非 ASCII 字符（如中文输入法）不持有第一个字符
- **原因**：IME 输入的字符爆发是合法的，持有会造成"输入丢失"的感觉

## 具体技术实现

### 核心数据结构

```rust
#[derive(Default)]
pub(crate) struct PasteBurst {
    last_plain_char_time: Option<Instant>,     // 上一个普通字符的时间
    consecutive_plain_char_burst: u16,          // 连续普通字符计数
    burst_window_until: Option<Instant>,        // Enter 抑制窗口截止时间
    buffer: String,                             // 爆发缓冲区
    active: bool,                               // 是否处于活跃爆发状态
    pending_first_char: Option<(char, Instant)>, // 待处理的第一个字符（闪烁抑制）
}
```

### 关键决策枚举

```rust
pub(crate) enum CharDecision {
    BeginBuffer { retro_chars: u16 },  // 开始缓冲，可能需要回溯捕获
    BufferAppend,                       // 追加到当前缓冲区
    RetainFirstChar,                    // 持有第一个字符（闪烁抑制）
    BeginBufferFromPending,             // 从待处理字符开始缓冲
}

pub(crate) enum FlushResult {
    Paste(String),                      // 作为粘贴刷新
    Typed(char),                        // 作为普通输入刷新
    None,                               // 无需刷新
}
```

### 时序阈值常量

```rust
// 非 Windows 平台
const PASTE_BURST_CHAR_INTERVAL: Duration = Duration::from_millis(8);
const PASTE_BURST_ACTIVE_IDLE_TIMEOUT: Duration = Duration::from_millis(8);

// Windows 平台（更慢的发送速率）
const PASTE_BURST_CHAR_INTERVAL: Duration = Duration::from_millis(30);
const PASTE_BURST_ACTIVE_IDLE_TIMEOUT: Duration = Duration::from_millis(60);

const PASTE_ENTER_SUPPRESS_WINDOW: Duration = Duration::from_millis(120);
const PASTE_BURST_MIN_CHARS: u16 = 3;  // 触发爆发的最小字符数
```

### 核心算法流程

#### 1. 普通 ASCII 字符处理 (`on_plain_char`)

```
1. 记录字符时间，更新连续计数
2. 如果已在活跃状态 → BufferAppend
3. 如果有待处理的第一个字符且时间在阈值内：
   - 激活爆发状态
   - 将待处理字符移入缓冲区
   - 返回 BeginBufferFromPending
4. 如果连续计数达到阈值 → BeginBuffer { retro_chars }
5. 否则 → 保存为待处理字符，返回 RetainFirstChar
```

#### 2. 非 ASCII 字符处理 (`on_plain_char_no_hold`)

```
1. 记录字符时间，更新连续计数
2. 如果已在活跃状态 → BufferAppend
3. 如果连续计数达到阈值 → BeginBuffer { retro_chars }
4. 否则 → None（正常插入）
```

#### 3. 回溯捕获决策 (`decide_begin_buffer`)

```rust
pub fn decide_begin_buffer(
    &mut self,
    now: Instant,
    before: &str,           // 光标前的文本
    retro_chars: usize,     // 需要回溯的字符数
) -> Option<RetroGrab> {
    let start_byte = retro_start_index(before, retro_chars);
    let grabbed = before[start_byte..].to_string();
    // 启发式：包含空白符或长度 >= 16 视为"粘贴样"
    let looks_pastey = grabbed.chars().any(char::is_whitespace) 
                       || grabbed.chars().count() >= 16;
    if looks_pastey { Some(RetroGrab { start_byte, grabbed }) } 
    else { None }
}
```

#### 4. 刷新逻辑 (`flush_if_due`)

```
1. 确定超时阈值（活跃状态用 ACTIVE_IDLE_TIMEOUT，否则用 CHAR_INTERVAL）
2. 检查是否超过超时时间
3. 如果活跃且超时 → 返回 Paste(buffer)，重置状态
4. 如果非活跃但有待处理字符且超时 → 返回 Typed(char)
5. 否则 → None
```

## 关键代码路径与文件引用

### 主要调用方

| 调用方 | 文件路径 | 用途 |
|--------|----------|------|
| `ChatComposer` | `codex-rs/tui/src/bottom_pane/chat_composer.rs` | 集成粘贴爆发检测到输入处理 |
| `BottomPane` | `codex-rs/tui/src/bottom_pane/mod.rs` | 管理爆发状态与视图交互 |
| `RequestUserInputOverlay` | `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 用户输入弹窗中的粘贴处理 |
| `McpServerElicitationOverlay` | `codex-rs/tui/src/bottom_pane/mcp_server_elicitation.rs` | MCP 服务器表单中的粘贴处理 |

### 集成点代码示例

**`chat_composer.rs` 中的 ASCII 字符处理：**
```rust
// 在 handle_input_basic 中
let decision = self.paste_burst.on_plain_char(ch, now);
match decision {
    CharDecision::RetainFirstChar => {
        // 不立即插入，等待确认
        return (InputResult::None, true);
    }
    CharDecision::BeginBufferFromPending => {
        self.paste_burst.append_char_to_buffer(ch, now);
        return (InputResult::None, true);
    }
    CharDecision::BeginBuffer { retro_chars } => {
        // 尝试回溯捕获
        if let Some(grab) = self.paste_burst.decide_begin_buffer(...) {
            // 删除已插入的前缀，开始缓冲
        }
    }
    CharDecision::BufferAppend => {
        self.paste_burst.append_char_to_buffer(ch, now);
        return (InputResult::None, true);
    }
}
```

**`chat_composer.rs` 中的 Enter 处理：**
```rust
// 在 handle_key_event_without_popup 中
if self.paste_burst.append_newline_if_active(now) {
    // 爆发活跃，将 Enter 作为换行追加到缓冲区
    return (InputResult::None, true);
}
if self.paste_burst.newline_should_insert_instead_of_submit(now) {
    // 在 Enter 抑制窗口内，插入换行
    self.textarea.insert_char('\n');
    self.paste_burst.extend_window(now);
    return (InputResult::None, true);
}
// 否则，正常提交
```

**UI Tick 刷新：**
```rust
pub fn flush_paste_burst_if_due(&mut self) -> bool {
    if let FlushResult::Paste(text) = self.paste_burst.flush_if_due(Instant::now()) {
        self.handle_paste(text);
        return true;
    }
    false
}
```

### 测试覆盖

位于文件底部的 `#[cfg(test)]` 模块包含以下测试：

| 测试名称 | 验证行为 |
|----------|----------|
| `ascii_first_char_is_held_then_flushes_as_typed` | ASCII 首字符持有后作为普通输入刷新 |
| `ascii_two_fast_chars_start_buffer_from_pending` | 两个快速 ASCII 字符启动缓冲 |
| `flush_before_modified_input_includes_pending_first_char` | 修改输入前刷新包含待处理字符 |
| `decide_begin_buffer_only_triggers_for_pastey_prefixes` | 回溯捕获仅对"粘贴样"前缀触发 |
| `newline_suppression_window_outlives_buffer_flush` | Enter 抑制窗口在缓冲区刷新后仍然有效 |

## 依赖与外部交互

### 依赖模块

| 模块 | 关系 | 说明 |
|------|------|------|
| `std::time::{Duration, Instant}` | 核心依赖 | 时间测量基础 |
| `chat_composer.rs` | 主要调用方 | 集成到输入处理流程 |
| `bottom_pane/mod.rs` | 容器 | 管理爆发状态生命周期 |

### 与 `ChatComposer` 的契约

`PasteBurst` 是纯状态机，不直接修改 UI。调用方必须：

1. **对每个普通 `KeyCode::Char`**：调用 `on_plain_char` 或 `on_plain_char_no_hold`
2. **根据决策执行操作**：
   - `RetainFirstChar`：不插入字符
   - `BeginBufferFromPending`：追加到缓冲区
   - `BeginBuffer { retro_chars }`：可能回溯删除已插入文本
   - `BufferAppend`：追加到缓冲区
3. **定期调用 `flush_if_due`**：在 UI tick 中检查是否需要刷新
4. **非字符输入前**：调用 `flush_before_modified_input` 避免状态泄漏
5. **修改输入后**：调用 `clear_window_after_non_char` 重置分类窗口

### 平台差异

```rust
#[cfg(not(windows))]
const PASTE_BURST_CHAR_INTERVAL: Duration = Duration::from_millis(8);
#[cfg(windows)]
const PASTE_BURST_CHAR_INTERVAL: Duration = Duration::from_millis(30);
```

Windows 使用更长的阈值，因为 Windows 终端（特别是 VS Code 集成终端）的粘贴事件发送更慢。

## 风险、边界与改进建议

### 已知风险

1. **时间敏感**
   - `flush_if_due` 使用 `>` 而非 `>=` 比较，测试和 UI tick 需要超过阈值至少 1ms
   - 使用 `recommended_flush_delay()` 获取安全的延迟值

2. **清除与刷新的区别**
   - `clear_window_after_non_char` 清除时间戳但不刷新缓冲区
   - 如果在缓冲区非空时调用，可能导致缓冲区永远无法刷新
   - 必须先调用 `flush_before_modified_input`

3. **IME 输入误分类**
   - 快速 IME 输入可能被误分类为粘贴
   - 通过 `decide_begin_buffer` 的启发式（空白符/长度检查）缓解

### 边界条件

| 场景 | 行为 |
|------|------|
| 单字符快速输入 | 作为普通输入处理（闪烁抑制后刷新） |
| 粘贴短单词（<16字符，无空白） | 可能不被识别为粘贴 |
| 在爆发中按非字符键 | 刷新缓冲区，清除爆发状态 |
| 禁用粘贴爆发 | 直接通过 `handle_paste` 刷新任何待处理内容 |
| 多行粘贴中的 Enter | 转换为 `\n` 追加到缓冲区 |

### 改进建议

1. **自适应阈值**
   - 当前阈值是固定的，可以考虑根据用户输入历史自适应调整
   - 对于已知快速输入的用户，可以提高阈值

2. **更精确的 IME 检测**
   - 当前依赖启发式（空白符/长度），可以探索更精确的 IME 状态检测

3. **可配置性**
   - 考虑将阈值暴露为配置选项，供高级用户调整
   - 特别是 Windows 用户的阈值可能需要根据终端类型进一步细分

4. **测试覆盖**
   - 增加对边缘情况的单元测试（如恰好阈值边界的情况）
   - 增加对多平台行为的模拟测试

5. **文档化状态机**
   - 考虑使用状态机图（如 Mermaid）可视化状态转换
   - 当前文档虽详细，但图形化表示可能更易于理解

### 相关文档

- `docs/tui-chat-composer.md`：ChatComposer 状态机的完整文档
- `codex-rs/tui/src/bottom_pane/chat_composer.rs`：主要集成代码
- `codex-rs/tui/src/bottom_pane/mod.rs`：BottomPane 容器
