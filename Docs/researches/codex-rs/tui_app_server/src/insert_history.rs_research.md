# insert_history.rs 研究文档

## 场景与职责

`insert_history.rs` 是 Codex TUI 应用服务器中负责**历史记录行插入**的核心模块。在终端内联模式（inline mode）下，TUI 需要在视口（viewport）上方动态插入历史消息行，同时保持视口位置稳定。该模块通过直接操作终端的 ANSI 转义序列来实现这一功能，避免了传统的清屏重绘方式，提供了更流畅的用户体验。

### 核心职责
1. **视口上方插入内容**：在固定视口区域上方插入历史消息，不干扰当前交互区域
2. **URL 感知换行**：智能处理包含 URL 的行，保持 URL 完整性以便终端点击
3. **样式保持**：正确渲染 ratatui 的样式（颜色、加粗、斜体等）到终端
4. **光标位置中立性**：操作完成后恢复光标位置，不影响后续渲染

## 功能点目的

### 1. 历史行插入 (`insert_history_lines`)
主入口函数，接收 `Vec<Line>`（ratatui 文本行）并将其插入到视口上方：

```rust
pub fn insert_history_lines<B>(
    terminal: &mut crate::custom_terminal::Terminal<B>,
    lines: Vec<Line>,
) -> io::Result<()>
```

**关键设计决策**：
- 使用终端滚动区域（scroll region）而非清屏来移动视口
- 通过 Reverse Index (RI, ESC M) 在滚动区域顶部插入空白行
- 直接在终端后端写入，绕过 ratatui 的缓冲机制

### 2. URL 感知预处理
在插入前对行进行三类处理（第48-75行）：

| 行类型 | 处理方式 | 目的 |
|--------|----------|------|
| 纯 URL 行 | 不换行，保持原样 | 让终端自动换行，保持 URL 可点击 |
| 混合行（URL+文本） | 自适应换行 (`adaptive_wrap_line`) | URL 不截断，普通文本正常换行 |
| 普通文本行 | 标准自适应换行 | 正常文本流式布局 |

### 3. 滚动区域管理
使用 ANSI DECSTBM 序列设置滚动区域：

```
┌─Screen───────────────────────┐
│┌╌Scroll region╌╌╌╌╌╌╌╌╌╌╌╌╌╌┐│  ← 历史行插入区域
│┆                            ┆│
│█╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┘│  ← 视口顶部边界
│╭─Viewport───────────────────╮│  ← 固定视口（TUI 交互区）
││                            ││
│╰────────────────────────────╯│
└──────────────────────────────┘
```

### 4. 样式渲染 (`write_spans`)
将 ratatui 的 `Span` 样式转换为 crossterm ANSI 序列：
- 前景色/背景色 (`SetColors`)
- 文本修饰符（加粗、斜体、下划线等）通过 `ModifierDiff` 增量应用
- 行级样式合并到每个 span（支持块引用等整体着色）

## 具体技术实现

### 关键数据结构

```rust
// 自定义滚动区域命令（crossterm Command trait 实现）
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SetScrollRegion(pub std::ops::Range<u16>);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ResetScrollRegion;

// 修饰符差异计算（增量更新样式）
struct ModifierDiff {
    pub from: Modifier,
    pub to: Modifier,
}
```

### 核心流程

```
insert_history_lines
├── 1. 预处理：URL 感知换行
│   ├── line_contains_url_like(line) → 检测 URL
│   ├── line_has_mixed_url_and_non_url_tokens(line) → 检测混合行
│   └── adaptive_wrap_line() / 保持原样
├── 2. 视口位置调整（如需要）
│   ├── 设置滚动区域 [viewport_top+1 .. screen_height]
│   ├── Reverse Index (ESC M) 滚动 viewport 下方区域
│   └── 更新 viewport_area.y
├── 3. 历史行插入
│   ├── 设置滚动区域 [1 .. viewport_top]
│   ├── MoveTo(0, cursor_top)
│   ├── 对每行：
│   │   ├── Print("\r\n") 插入新行
│   │   ├── 清除 URL 换行的延续行（防止残留）
│   │   ├── SetColors（行级样式）
│   │   └── write_spans（写入带样式的 spans）
│   └── ResetScrollRegion
└── 4. 恢复状态
    ├── MoveTo(last_cursor_pos) 恢复光标
    ├── set_viewport_area() 更新视口
    └── note_history_rows_inserted() 记录历史行数
```

### URL 检测与处理

依赖 `wrapping.rs` 提供的功能：

```rust
// 检测行中是否包含 URL-like token
pub(crate) fn line_contains_url_like(line: &Line<'_>) -> bool

// 检测是否为混合行（URL + 非 URL 文本）
pub(crate) fn line_has_mixed_url_and_non_url_tokens(line: &Line<'_>) -> bool
```

URL 检测规则（见 `wrapping.rs`）：
- 绝对 URL（`https://`, `ftp://` 等）
- 裸域名（`example.com/path`, `localhost:3000`）
- IPv4 带路径（`192.168.1.1:8080/health`）
- 排除文件路径（`src/main.rs` 不被识别为 URL）

### 样式转换细节

**颜色转换**：
```rust
// ratatui Color → crossterm CColor
line.style.fg.map(Into::into).unwrap_or(CColor::Reset)
```

**修饰符差异计算**：
```rust
let removed = self.from - self.to;  // 需要清除的修饰符
let added = self.to - self.from;    // 需要添加的修饰符
```

支持的修饰符：REVERSED, BOLD, ITALIC, UNDERLINED, DIM, CROSSED_OUT, SLOW_BLINK, RAPID_BLINK

## 关键代码路径与文件引用

### 入口调用链

```
App::draw() ──► Tui::draw() ──► insert_history_lines()
     │                              │
     │                              ├── wrapping::adaptive_wrap_line
     │                              ├── custom_terminal::Terminal
     │                              └── crossterm ANSI 序列
     │
     └── App::apply_backtrack() ──► insert_history_lines()
```

### 主要调用方

| 文件 | 调用场景 |
|------|----------|
| `tui.rs:499` | 渲染待处理的历史行 (`pending_history_lines`) |
| `app.rs:1428` | 插入 UI 头部行（clear_ui_header_lines） |
| `app.rs:3557` | 插入历史单元格显示内容 |
| `app_backtrack.rs:241` | 应用回溯时恢复历史行 |
| `app_backtrack.rs:257` | 回溯时重新插入转录单元格 |

### 依赖模块

| 模块 | 用途 |
|------|------|
| `wrapping.rs` | URL 检测、自适应换行 (`adaptive_wrap_line`, `RtOptions`) |
| `custom_terminal.rs` | `Terminal` 结构体（viewport_area, backend, last_known_cursor_pos） |
| `markdown_render.rs` | 测试中使用 `render_markdown_text` 生成测试数据 |
| `test_backend.rs` | VT100 后端用于测试验证 |

### 测试覆盖

测试文件：`insert_history.rs` 内嵌 `#[cfg(test)]` 模块（第332-736行）

| 测试用例 | 验证内容 |
|----------|----------|
| `writes_bold_then_regular_spans` | 基础样式渲染 |
| `vt100_blockquote_line_emits_green_fg` | 行级样式（块引用绿色） |
| `vt100_blockquote_wrap_preserves_color_on_all_wrapped_lines` | 换行后样式保持 |
| `vt100_colored_prefix_then_plain_text_resets_color` | 颜色重置逻辑 |
| `vt100_deep_nested_mixed_list_third_level_marker_is_colored` | 嵌套列表样式 |
| `vt100_prefixed_url_keeps_prefix_and_url_on_same_row` | URL 不换行 |
| `vt100_prefixed_url_like_without_scheme_keeps_prefix_and_token_on_same_row` | 裸域名处理 |
| `vt100_prefixed_mixed_url_line_wraps_suffix_words_together` | 混合行换行 |
| `vt100_unwrapped_url_like_clears_continuation_rows` | 延续行清除 |
| `vt100_long_unwrapped_url_does_not_insert_extra_blank_gap_before_content` | 无额外空行 |

## 依赖与外部交互

### 外部 crate

| Crate | 用途 |
|-------|------|
| `crossterm` | ANSI 转义序列（`queue!`, `MoveTo`, `SetColors`, `Print` 等） |
| `ratatui` | `Line`, `Span`, `Color`, `Style`, `Backend` |
| `textwrap` | 通过 `wrapping.rs` 间接使用 |

### 内部模块交互

```
insert_history.rs
    ├──► wrapping.rs ────────┐
    │   ├── line_contains_url_like
    │   ├── line_has_mixed_url_and_non_url_tokens
    │   └── adaptive_wrap_line
    │
    ├──► custom_terminal.rs ─┤
    │   ├── Terminal::viewport_area
    │   ├── Terminal::backend_mut
    │   ├── Terminal::set_viewport_area
    │   └── Terminal::note_history_rows_inserted
    │
    └──► markdown_render.rs ─┘（仅测试）
        └── render_markdown_text
```

## 风险、边界与改进建议

### 已知风险

1. **Windows WinAPI 回退**
   - `SetScrollRegion` 和 `ResetScrollRegion` 在 Windows 上 panic（第194, 214行）
   - 当前标记为 `// TODO(nornagon): is this supported on Windows?`
   - **风险**：Windows 非 ANSI 模式下会崩溃

2. **光标位置假设**
   - 函数注释说明应保证"cursor-position-neutral"，但复杂场景下可能偏离
   - 使用 `MoveTo` 而非 `set_cursor_position` 来避免更新内部状态

3. **URL 检测启发式**
   - 假阳性：非 URL 被识别为 URL → 不换行可能导致行过长
   - 假阴性：URL 未被识别 → 可能被截断

4. **滚动区域副作用**
   - 设置滚动区域会影响终端全局状态
   - 如果 panic 发生在重置前，可能导致终端状态混乱

### 边界情况

| 场景 | 处理方式 |
|------|----------|
| 视口在屏幕底部 | 使用 Reverse Index 滚动下方区域 |
| 视口不在底部 | 直接向上移动视口 |
| URL 超宽 | 依赖终端自动换行，清除延续行残留 |
| 空行 | 至少占用 1 行高度（`max(1, width)`） |
| 零宽度视口 | `wrap_width.max(1)` 防止除零 |

### 改进建议

1. **Windows 支持**
   ```rust
   // 当前：直接 panic
   // 建议：实现 WinAPI 回退或强制使用 ANSI 模式
   ```

2. **错误恢复**
   - 使用 `scopeguard` 或自定义 Drop 确保 `ResetScrollRegion` 被执行
   - 避免 panic 后终端处于异常滚动区域状态

3. **URL 检测增强**
   - 考虑引入更完整的 URL 解析库（如 `url` crate 已部分使用）
   - 支持 IPv6 括号表示法（当前明确不处理）

4. **性能优化**
   - 批量写入 ANSI 序列，减少 `queue!` 调用次数
   - 考虑使用 `write!` 直接写入而非多次 `queue!`

5. **测试覆盖**
   - 添加 Windows 模拟测试
   - 添加极端宽度（1列、1000列）测试
   - 添加 Unicode 宽字符（CJK）测试

### 相关 Issue 线索

- 文件头部的 URL 处理注释（第48-58行）说明这是迭代优化的结果
- VT100 测试使用 `vt100` crate 模拟终端，验证实际渲染输出
- `visible_history_rows` 的饱和算术（`saturating_add`）防止溢出
