# tui-chat-composer.md 研究文档

## 场景与职责

tui-chat-composer.md 是 Codex CLI 项目中关于 TUI 聊天编辑器（ChatComposer）状态机和粘贴相关行为的详细设计文档。该文档特别关注了 Windows 终端上的粘贴突发检测和处理。

**适用场景：**
- TUI 开发者需要理解聊天编辑器的实现
- 调试粘贴或输入相关问题
- 实现新的编辑器功能

## 功能点目的

### 1. 解决的问题

在某些终端（特别是通过 `crossterm` 的 Windows）上，_括号粘贴_ 不能可靠地作为单个粘贴事件显示。相反，粘贴多行内容可能显示为快速序列的键事件：
- `KeyCode::Char(..)` 用于文本
- `KeyCode::Enter` 用于换行

如果编辑器将这些事件视为"正常输入"，可能导致：
- 粘贴仍在流式传输时意外触发 UI 切换（如 `?`）
- `Enter` 到达时中途提交消息
- 渲染输入前缀，然后在足够多字符到达时"重新分类"为粘贴（闪烁）

**解决方案**：检测粘贴般的_突发_并将其缓冲到单个显式 `handle_paste(String)` 调用。

### 2. 高层状态机

`ChatComposer` 有效地结合了两个小状态机：

1. **UI 模式**：哪个弹出窗口（如果有）处于活动状态
   - `ActivePopup::None | Command | File | Skill`

2. **粘贴突发**：非括号粘贴的瞬态检测状态
   - 由 `PasteBurst` 实现

### 3. 键事件路由

`ChatComposer::handle_key_event` 基于 `active_popup` 分发：
- 如果弹出窗口可见，弹出窗口特定的处理程序首先处理键（导航、选择、完成）
- 否则，`handle_key_event_without_popup` 处理高级语义（Enter 提交、历史导航等）
- 处理键后，`sync_popups()` 运行，以便弹出窗口可见性/过滤器与最新文本 + 光标保持一致
- 当 slash 命令名称完成且用户键入空格时，`/command` 标记被提升为文本元素，以便它不同地渲染并原子化编辑

### 4. 历史导航（↑/↓）

由 `ChatComposerHistory` 处理，合并两个来源：

- **持久历史**（跨会话，从 `~/.codex/history.jsonl` 获取）：仅文本。它**不**携带文本元素范围或图像附件，所以召回这些条目之一仅恢复文本。

- **本地历史**（当前会话）：存储完整提交负载，包括文本元素、本地图像路径和远程图像 URL。召回本地条目重新水合占位符和附件。

这种区分保持磁盘上的历史向后兼容，避免持久化附件，同时为会话内编辑提供更丰富的召回体验。

### 5. 配置门控重用

`ChatComposer` 现在通过 `ChatComposerConfig` 支持功能门控（`codex-rs/tui/src/bottom_pane/chat_composer.rs`）。默认配置保留当前聊天行为。

**标志**：
- `popups_enabled`
- `slash_commands_enabled`
- `image_paste_enabled`

**禁用时效果**：
- `popups_enabled` 为 `false` 时，`sync_popups()` 强制 `ActivePopup::None`
- `slash_commands_enabled` 为 `false` 时，编辑器不将 `/...` 输入视为命令
- `slash_commands_enabled` 为 `false` 时，编辑器在 `prepare_submission_text` 中不扩展自定义提示
- `slash_commands_enabled` 为 `false` 时，禁用 slash 上下文粘贴突发异常
- `image_paste_enabled` 为 `false` 时，跳过文件路径粘贴图像附件
- `ChatWidget` 可能基于所选模型的 `input_modalities` 在运行时切换 `image_paste_enabled`；附加和提交路径也重新检查支持并发出警告而不是丢弃草稿

内置 slash 命令可用性集中在 `codex-rs/tui/src/bottom_pane/slash_commands.rs` 中，由编辑器和命令弹出窗口重用，以便门控保持同步。

### 6. 提交流程（Enter/Tab）

有多个提交路径，但它们共享相同的核心规则：

当 steer 模式启用时，如果任务已在运行，`Tab` 请求排队；否则立即提交。`Enter` 在此模式下始终立即提交。当输入以 `!`（shell 命令）开头时，`Tab` 不提交。

#### 正常提交/排队路径

`handle_submission` 为提交和排队调用 `prepare_submission_text`。该方法：

1. 扩展任何待处理的粘贴占位符，以便元素范围与最终文本对齐
2. 修剪空白并重新调整元素范围到修剪后的缓冲区
3. 扩展 `/prompts:` 自定义提示：
   - 命名参数使用 key=value 解析
   - 数字参数使用位置解析（`$1..$9` 和 `$ARGUMENTS`）
   - 扩展保留文本元素并产生最终提交负载
4. 修剪附件，以便仅发送在扩展中存活的占位符
5. 成功时清除待处理粘贴，如果最终文本为空且没有附件，则抑制提交

相同的准备路径被重用用于带参数的 slash 命令（例如 `/plan` 和 `/review`），以便在提取参数时保留粘贴内容和文本元素。

编辑器还将 textarea kill 缓冲区视为与可见草稿分开的编辑状态。提交或 slash 命令分派清除 textarea 后，最近的 `Ctrl+K` 负载仍可用于 `Ctrl+Y`。这支持用户杀死草稿的一部分、运行编辑器操作（如更改推理级别）、然后将该文本拉回清除的草稿的流程。

#### 数字自动提交路径

当 slash 弹出窗口打开且第一行匹配带位置参数的数字仅自定义提示时，Enter 自动提交而不调用 `prepare_submission_text`。该路径仍然：
- 在解析位置参数前扩展待处理粘贴
- 使用扩展的文本元素进行提示扩展
- 基于扩展占位符修剪附件
- 成功自动提交后清除待处理粘贴

### 7. 远程图像行（选择/删除流程）

远程图像 URL 显示为 `[Image #N]` 行在 textarea 上方，在同一编辑器框内。它们是附件行，不是可编辑的 textarea 内容。

- TUI 可以删除这些行，但不能在它们之前/之间键入
- 在 textarea 光标位置 `0` 按 `Up` 选择最后一个远程图像行
- 选中时，`Up`/`Down` 在远程图像行间移动选择
- 在最后一行按 `Down` 退出远程行选择并返回 textarea 编辑
- `Delete` 或 `Backspace` 删除选中的远程图像行

**图像编号统一**：
- 远程图像行始终占据 `[Image #1]..[Image #M]`
- 本地附加图像占位符在该偏移后开始（`[Image #M+1]..`）
- 删除远程行重新标记本地占位符，以便编号保持连续

### 8. 历史导航（Up/Down）和回溯预填充

`ChatComposerHistory` 合并两种历史：

- **持久历史**（跨会话，按需从核心获取）：仅文本
- **本地历史**（此 UI 会话）：完整草稿状态

本地历史条目捕获：
- 原始文本（包括占位符）
- 占位符的 `TextElement` 范围
- 本地图像路径
- 远程图像 URL
- 待处理的大粘贴负载（用于草稿）

持久历史条目仅恢复文本。它们故意不**重新水合附件或待处理粘贴负载。

对于非空草稿，仅当当前文本匹配最后召回的历史条目且光标在边界（行首或行尾）时，Up/Down 导航才被视为历史召回。这在保留类 shell 历史遍历的同时保持多行光标移动完整。

#### 草稿恢复（Ctrl+C）

Ctrl+C 清除编辑器但将完整草稿状态（文本元素、本地图像路径、远程图像 URL 和待处理粘贴负载）存入本地历史。立即按 Up 恢复该草稿，包括图像占位符和大粘贴占位符及其负载。

#### 提交消息召回

成功提交后，本地历史条目存储提交的文本、元素范围、本地图像路径和远程图像 URL。待处理粘贴负载在提交期间清除，所以大粘贴占位符在记录前扩展为完整文本。这意味着：
- 提交消息的 Up/Down 召回恢复远程图像行加本地图像占位符
- 召回条目将光标放在行尾以匹配典型的 shell 历史编辑
- 召回的提交历史中不期望有大粘贴占位符；文本是扩展的粘贴内容

#### 回溯预填充

回溯选择从转录中读取 `UserHistoryCell` 数据。编辑器预填充现在重用所选消息的文本元素、本地图像路径和远程图像 URL，以便在回滚到先前用户消息时重新水合图像占位符和附件。

#### 外部编辑器编辑

当编辑器内容从外部编辑器替换时，编辑器重建文本元素并仅保留占位符仍出现在新文本中的附件。然后图像占位符被规范化为 `[Image #M]..[Image #N]`，其中 `M` 在远程图像行数之后开始，以便在编辑后保持附件映射一致。

### 9. 粘贴突发：概念和假设

突发检测器故意保守：它只处理"普通"字符输入（无 Ctrl/Alt 修饰符）。其他所有内容都刷新和/或清除突发窗口，以便快捷方式保持其正常含义。

#### 概念性 `PasteBurst` 状态

- **Idle**：无缓冲区，无待处理字符
- **待处理第一个字符**（仅 ASCII）：非常短暂地持有一个快速字符，以避免如果流变成粘贴则渲染它然后立即移除
- **活动缓冲区**：一旦突发被分类为粘贴样，将内容累积到 `String` 缓冲区
- **Enter 抑制窗口**：在突发活动后短暂将 `Enter` 视为"换行"，以便多行粘贴保持分组，即使有微小间隙

#### ASCII vs 非 ASCII（IME）输入

非 ASCII 字符经常来自 IME，可以合法地快速到达。在这种情况下持有第一个字符可能感觉像丢失输入。

因此编辑器区分：
- **ASCII 路径**：允许持有第一个快速字符（`PasteBurst::on_plain_char`）
- **非 ASCII 路径**：从不持有第一个字符（`PasteBurst::on_plain_char_no_hold`），但仍允许突发检测。当在此路径上检测到突发时，已插入的前缀可能从 textarea 中追溯移除并移入粘贴缓冲区。

为避免将 IME 突发误分类为粘贴，非 ASCII 追溯捕获路径运行额外的启发式（`PasteBurst::decide_begin_buffer`）以确定追溯抓取的前缀是否"看起来像粘贴"（例如包含空白或很长）。

#### 禁用突发检测

`ChatComposer` 支持 `disable_paste_burst` 作为逃生舱口。

启用时：
- 突发检测器被绕过新输入（无闪烁抑制持有和突发缓冲决策）
- 键流被视为正常输入（包括正常 slash 命令行为）
- 启用标志将任何持有/缓冲的突发文本通过正常粘贴路径（`ChatComposer::handle_paste`）刷新，然后清除突发时间和 Enter 抑制窗口，以便瞬态突发状态不能泄漏到后续输入

#### Enter 处理

当粘贴突发缓冲活动时，Enter 被视为"追加 `\n` 到突发"而不是"提交消息"。这防止多行粘贴作为 `Enter` 键事件发出时的中途提交。

编辑器还在 slash 命令上下文（弹出窗口打开或第一行以 `/` 开头）内禁用基于突发的 Enter 抑制，以便命令分派可预测。

### 10. PasteBurst：事件级行为（速查表）

本节详细说明 `ChatComposer` 如何解释 `PasteBurst` 决策。旨在使状态转换可审查，无需"在脑中运行代码"。

#### 纯 ASCII `KeyCode::Char(c)`（无 Ctrl/Alt 修饰符）

`ChatComposer::handle_input_basic` 调用 `PasteBurst::on_plain_char(c, now)` 并切换返回的 `CharDecision`：

- `RetainFirstChar`：还**不**将 `c` 插入 textarea。UI tick 稍后可能通过 `PasteBurst::flush_if_due` 将其作为正常输入字符刷新。
- `BeginBufferFromPending`：第一个 ASCII 字符已被持有/缓冲；通过 `PasteBurst::append_char_to_buffer` 追加 `c`。
- `BeginBuffer { retro_chars }`：尝试追溯捕获已插入的前缀：
  - 调用 `PasteBurst::decide_begin_buffer(now, before_cursor, retro_chars)`；
  - 如果返回 `Some(grab)`，从 textarea 删除 `grab.start_byte..cursor` 然后追加 `c` 到缓冲区；
  - 如果返回 `None`，回退到正常插入。
- `BufferAppend`：追加 `c` 到活动缓冲区。

#### 纯非 ASCII `KeyCode::Char(c)`（无 Ctrl/Alt 修饰符）

`ChatComposer::handle_non_ascii_char` 使用稍微不同的流程：

- 首先用 `PasteBurst::flush_before_modified_input` 刷新任何待处理的瞬态 ASCII 状态（包括单个持有的 ASCII 字符）
- 如果突发已活动，`PasteBurst::try_append_char_if_active(c, now)` 直接追加 `c`
- 否则调用 `PasteBurst::on_plain_char_no_hold(now)`：
  - `BufferAppend`：追加 `c` 到活动缓冲区
  - `BeginBuffer { retro_chars }`：运行 `decide_begin_buffer(..)` 并且，如果开始缓冲，从 textarea 删除追溯抓取的前缀并追加 `c`
  - `None`：正常将 `c` 插入 textarea

此路径上的额外 `decide_begin_buffer` 启发式是故意的：IME 输入可以作为快速突发到达，所以代码仅当前缀"看起来像粘贴"（空白或足够长的运行）时才追溯抓取，以避免将 IME 组合误分类为粘贴。

#### `KeyCode::Enter`：换行 vs 提交

有两个不同的"Enter 变成换行"机制：

- **在突发上下文中**（`paste_burst.is_active()`）：`append_newline_if_active(now)` 追加 `\n` 到突发缓冲区，以便多行粘贴保持缓冲为单个显式粘贴。
- **突发活动后立即**（enter 抑制窗口）：`newline_should_insert_instead_of_submit(now)` 将 `\n` 插入 textarea 并调用 `extend_window(now)`，以便稍晚的 Enter 继续表现为"换行"而不是"提交"。

两者在 slash 命令上下文（命令弹出窗口活动或第一行以 `/` 开头）内禁用，以便 Enter 保持其正常的"提交/执行"语义。

#### 非字符键 / Ctrl+修饰输入

非字符输入不能跨不相关操作泄漏突发状态：

- 如果有缓冲的突发文本，调用者应在调用 `clear_window_after_non_char` 前刷新它（参见"值得指出的陷阱"），通常通过 `PasteBurst::flush_before_modified_input`
- `PasteBurst::clear_window_after_non_char` 清除"最近突发"窗口，以便下一个键击不会被错误地分组到先前的粘贴

#### 值得指出的陷阱

- `PasteBurst::clear_window_after_non_char` 清除 `last_plain_char_time`。如果在 `buffer` 非空时调用它且_尚未刷新_，`flush_if_due()` 不再有用于超时的 timestamp，所以缓冲的文本可能永不刷新。将 `clear_window_after_non_char` 视为"刷新后丢弃分类上下文"，而不是"刷新"。
- `PasteBurst::flush_if_due` 使用严格的 `>` 比较，所以测试和 UI tick 应至少跨越阈值 1ms（参见 `PasteBurst::recommended_flush_delay`）。

### 11. 值得注意的交互/不变量

- 编辑器经常使用光标位置切片 `textarea.text()`；所有切片代码必须首先将光标钳位到 UTF-8 字符边界。
- `sync_popups()` 必须在任何可能影响弹出窗口可见性或过滤的更改后运行：插入、删除、刷新突发、应用粘贴占位符等。
- 通过 `?` 的快捷方式覆盖切换被限制在 `!is_in_paste_burst()` 上，以便粘贴不能在流式传输时翻转 UI 模式。
- 提及弹出窗口选择有两个负载：可见的 `$name` 文本和隐藏的 `mention_paths[name] -> canonical target` 链接。通用 `set_text_content` 路径故意为新鲜草稿清除链接；恢复重新水合被阻止/中断提交的路径必须使用提及保留设置器，以便重试保持最初选择的目标。

### 12. 固定行为的测试

`PasteBurst` 逻辑目前通过 `ChatComposer` 集成测试练习。

测试文件：`codex-rs/tui/src/bottom_pane/chat_composer.rs`

- `non_ascii_burst_handles_newline`
- `ascii_burst_treats_enter_as_newline`
- `question_mark_does_not_toggle_during_paste_burst`
- `burst_paste_fast_small_buffers_and_flushes_on_stop`
- `burst_paste_fast_large_inserts_placeholder_on_flush`

本文档指出一些额外的契约（如"刷新前清除"），这些尚未由专门的 `PasteBurst` 单元测试完全固定。

## 具体技术实现

### 粘贴突发检测算法

```
接收字符输入
    ↓
检查修饰符（Ctrl/Alt）
    ↓
如果有修饰符：刷新当前突发并正常处理
    ↓
检查字符类型（ASCII/非 ASCII）
    ↓
如果是 ASCII：
    - 短暂持有第一个字符
    - 如果快速连续到达更多字符，开始缓冲
    ↓
如果是非 ASCII：
    - 立即插入
    - 如果检测到突发，追溯移除并缓冲
    ↓
缓冲期间：
    - 累积字符
    - Enter 转换为换行
    ↓
超时或特定键：
    - 刷新缓冲为粘贴
```

### 状态转换

```
[Idle] --快速字符--> [Pending] --更多字符--> [Buffering] --超时--> [Flush]
              |                              |
              --无更多字符--> [Insert]       --Enter--> [Append Newline]
```

## 关键代码路径与文件引用

### 相关文件位置

| 文件路径 | 说明 |
|---------|------|
| `/home/sansha/Github/codex/docs/tui-chat-composer.md` | 本文档 |
| `/home/sansha/Github/codex/codex-rs/tui/src/bottom_pane/chat_composer.rs` | ChatComposer 实现 |
| `/home/sansha/Github/codex/codex-rs/tui/src/bottom_pane/paste_burst.rs` | PasteBurst 实现 |
| `/home/sansha/Github/codex/codex-rs/tui/src/bottom_pane/slash_commands.rs` | Slash 命令 |

### 关键类型

**ChatComposerConfig**：
```rust
struct ChatComposerConfig {
    popups_enabled: bool,
    slash_commands_enabled: bool,
    image_paste_enabled: bool,
}
```

**ActivePopup**：
```rust
enum ActivePopup {
    None,
    Command,
    File,
    Skill,
}
```

**CharDecision**：
```rust
enum CharDecision {
    RetainFirstChar,
    BeginBufferFromPending,
    BeginBuffer { retro_chars: usize },
    BufferAppend,
    None,
}
```

## 依赖与外部交互

### 外部依赖

1. **crossterm**
   - 终端事件处理
   - 跨平台键码

### 内部依赖

1. **核心模块**
   - 历史管理
   - 图像处理
   - 提示扩展

2. **TUI 组件**
   - TextArea 组件
   - 弹出窗口系统

## 风险、边界与改进建议

### 潜在风险

1. **IME 兼容性**
   - 复杂的 IME 交互可能导致输入丢失
   - 建议：添加更多 IME 场景测试

2. **性能问题**
   - 大粘贴的缓冲可能导致内存问题
   - 建议：添加缓冲区大小限制

3. **状态复杂性**
   - 多个状态机交互复杂
   - 建议：添加状态机不变量检查

### 边界情况

1. **非常大的粘贴**
   - 缓冲区大小限制
   - 占位符处理

2. **快速输入**
   - 快速打字可能被误检测为粘贴
   - 建议：优化启发式

3. **多字节字符**
   - UTF-8 边界处理
   - 光标位置计算

### 改进建议

1. **配置选项**
   - 可配置的突发检测阈值
   - 禁用特定功能的选项

2. **可访问性**
   - 屏幕阅读器支持
   - 键盘导航改进

3. **测试覆盖**
   - 添加专门的 PasteBurst 单元测试
   - 添加模糊测试

4. **性能优化**
   - 大文本的高效处理
   - 减少不必要的重渲染

5. **用户体验**
   - 粘贴进度指示
   - 更好的错误消息
