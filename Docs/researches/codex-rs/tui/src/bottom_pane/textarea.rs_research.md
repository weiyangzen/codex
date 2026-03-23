# textarea.rs 深度研究文档

## 1. 场景与职责

`textarea.rs` 是 Codex TUI 的核心文本编辑组件，负责实现底部输入框（Chat Composer）的可编辑文本缓冲区。它是用户与 Codex 交互的主要输入界面，需要处理复杂的文本编辑场景：

- **多行文本编辑**：支持用户输入多行文本，处理换行、自动换行（word wrap）等场景
- **富文本元素（Text Elements）**：支持特殊的占位符元素（如图片附件、斜杠命令等），这些元素需要作为原子单元处理，不能被光标进入或分割
- **Emacs 风格快捷键**：支持 Ctrl+A/E（行首/行尾）、Ctrl+K（删除到行尾）、Ctrl+Y（粘贴kill buffer）等经典快捷键
- **跨平台兼容性**：处理 Windows AltGr 键、不同终端的 C0 控制字符等
- **Unicode 支持**：正确处理 grapheme cluster（如 emoji、组合字符）、CJK 宽字符等

### 在架构中的位置

```
ChatWidget
  └── BottomPane
        └── ChatComposer
              └── TextArea  <-- 本模块
```

`TextArea` 被 `ChatComposer` 包装，提供更高层的业务逻辑（如斜杠命令弹出框、附件管理等）。

## 2. 功能点目的

### 2.1 核心编辑功能

| 功能 | 目的 | 典型使用场景 |
|------|------|-------------|
| `insert_str` / `insert_str_at` | 在光标位置或指定位置插入文本 | 用户输入字符、粘贴文本 |
| `replace_range` | 替换指定范围的文本 | 删除选中内容并替换、元素更新 |
| `delete_backward` / `delete_forward` | 删除光标前后的字符 | Backspace / Delete 键 |
| `delete_backward_word` / `delete_forward_word` | 按单词删除 | Alt+Backspace / Alt+Delete |
| `kill_to_end_of_line` / `kill_to_beginning_of_line` | 删除到行尾/行首 | Ctrl+K / Ctrl+U |
| `yank` | 粘贴最后一次 kill 的内容 | Ctrl+Y |

### 2.2 光标移动功能

| 功能 | 目的 | 快捷键 |
|------|------|--------|
| `move_cursor_left` / `move_cursor_right` | 左右移动一个 grapheme | ← / → / Ctrl+B / Ctrl+F |
| `move_cursor_up` / `move_cursor_down` | 上下移动，保持列位置 | ↑ / ↓ / Ctrl+P / Ctrl+N |
| `move_cursor_to_beginning_of_line` | 移动到行首 | Home / Ctrl+A |
| `move_cursor_to_end_of_line` | 移动到行尾 | End / Ctrl+E |
| `beginning_of_previous_word` / `end_of_next_word` | 按单词移动 | Alt+B / Alt+F / Ctrl+← / Ctrl+→ |

### 2.3 文本元素（Text Elements）

文本元素是 `textarea.rs` 的核心创新点，用于表示需要原子化处理的特殊文本片段：

- **图片占位符**：如 `[Image #1]`，用户不能直接编辑其中的文字
- **斜杠命令**：如 `/plan`，作为整体被识别和处理
- **提及（Mentions）**：如 `$skill_name`，链接到特定技能

元素的核心约束：
1. 光标不能进入元素内部，只能位于元素边界
2. 删除操作如果触及元素，必须整体删除
3. 替换操作如果与元素重叠，必须扩展为包含整个元素

### 2.4 Kill Buffer（剪切板）

实现单条目的 kill buffer（非 Emacs 多条目 kill ring）：
- `Ctrl+K`：删除到行尾，内容存入 kill buffer
- `Ctrl+U`：删除到行首，内容存入 kill buffer  
- `Ctrl+Y`：插入 kill buffer 内容
- **重要特性**：`set_text_clearing_elements` 和 `set_text_with_elements` 会保留 kill buffer，允许用户在提交后恢复之前删除的内容

## 3. 具体技术实现

### 3.1 核心数据结构

```rust
/// 可编辑文本缓冲区
pub(crate) struct TextArea {
    text: String,                          // 原始 UTF-8 文本
    cursor_pos: usize,                     // 光标字节位置
    wrap_cache: RefCell<Option<WrapCache>>, // 自动换行缓存（惰性计算）
    preferred_col: Option<usize>,          // 垂直移动时保持的列位置
    elements: Vec<TextElement>,            // 原子元素列表
    next_element_id: u64,                  // 元素 ID 生成器
    kill_buffer: String,                   // 单条目剪切板
}

/// 文本元素（原子单元）
#[derive(Debug, Clone)]
struct TextElement {
    id: u64,                               // 唯一标识
    range: Range<usize>,                   // 字节范围
    name: Option<String>,                  // 可选名称（用于外部引用）
}

/// 换行缓存
#[derive(Debug, Clone)]
struct WrapCache {
    width: u16,                            // 缓存对应的宽度
    lines: Vec<Range<usize>>,              // 每行的字节范围
}

/// 状态（用于 StatefulWidgetRef）
#[derive(Debug, Default, Clone, Copy)]
pub(crate) struct TextAreaState {
    scroll: u16,                           // 第一行可见的 wrapped line 索引
}
```

### 3.2 关键算法实现

#### 3.2.1 字符边界处理

```rust
fn clamp_pos_to_char_boundary(&self, pos: usize) -> usize {
    let pos = pos.min(self.text.len());
    if self.text.is_char_boundary(pos) {
        return pos;
    }
    // 向前或向后寻找最近的字符边界，选择距离近的
    let mut prev = pos;
    while prev > 0 && !self.text.is_char_boundary(prev) {
        prev -= 1;
    }
    let mut next = pos;
    while next < self.text.len() && !self.text.is_char_boundary(next) {
        next += 1;
    }
    if pos.saturating_sub(prev) <= next.saturating_sub(pos) { prev } else { next }
}
```

#### 3.2.2 元素边界处理

```rust
fn clamp_pos_to_nearest_boundary(&self, pos: usize) -> usize {
    let pos = self.clamp_pos_to_char_boundary(pos);
    if let Some(idx) = self.find_element_containing(pos) {
        let e = &self.elements[idx];
        let dist_start = pos.saturating_sub(e.range.start);
        let dist_end = e.range.end.saturating_sub(pos);
        // 选择距离近的元素边界
        if dist_start <= dist_end {
            self.clamp_pos_to_char_boundary(e.range.start)
        } else {
            self.clamp_pos_to_char_boundary(e.range.end)
        }
    } else {
        pos
    }
}
```

#### 3.2.3 范围扩展到元素边界

```rust
fn expand_range_to_element_boundaries(&self, mut range: Range<usize>) -> Range<usize> {
    loop {
        let mut changed = false;
        for e in &self.elements {
            if e.range.start < range.end && e.range.end > range.start {
                // 有重叠，扩展范围以包含整个元素
                let new_start = range.start.min(e.range.start);
                let new_end = range.end.max(e.range.end);
                if new_start != range.start || new_end != range.end {
                    range.start = new_start;
                    range.end = new_end;
                    changed = true;
                }
            }
        }
        if !changed { break; }
    }
    range
}
```

#### 3.2.4 原子边界导航

```rust
fn prev_atomic_boundary(&self, pos: usize) -> usize {
    if pos == 0 { return 0; }
    // 如果在元素末尾或内部，跳到元素开头
    if let Some(idx) = self.elements.iter().position(|e| pos > e.range.start && pos <= e.range.end) {
        return self.elements[idx].range.start;
    }
    // 否则使用 grapheme 边界
    let mut gc = unicode_segmentation::GraphemeCursor::new(pos, self.text.len(), false);
    match gc.prev_boundary(&self.text, 0) {
        Ok(Some(b)) => {
            // 检查是否落在元素内
            if let Some(idx) = self.find_element_containing(b) {
                self.elements[idx].range.start
            } else { b }
        }
        Ok(None) => 0,
        Err(_) => pos.saturating_sub(1),
    }
}
```

#### 3.2.5 自动换行与滚动

```rust
fn wrapped_lines(&self, width: u16) -> Ref<'_, Vec<Range<usize>>> {
    // 惰性计算：只在宽度变化时重新计算
    {
        let mut cache = self.wrap_cache.borrow_mut();
        let needs_recalc = match cache.as_ref() {
            Some(c) => c.width != width,
            None => true,
        };
        if needs_recalc {
            let lines = crate::wrapping::wrap_ranges(
                &self.text,
                Options::new(width as usize).wrap_algorithm(textwrap::WrapAlgorithm::FirstFit),
            );
            *cache = Some(WrapCache { width, lines });
        }
    }
    let cache = self.wrap_cache.borrow();
    Ref::map(cache, |c| &c.as_ref().unwrap().lines)
}

/// 计算有效滚动位置，确保光标可见
fn effective_scroll(&self, area_height: u16, lines: &[Range<usize>], current_scroll: u16) -> u16 {
    let total_lines = lines.len() as u16;
    if area_height >= total_lines { return 0; }
    
    let cursor_line_idx = Self::wrapped_line_index_by_start(lines, self.cursor_pos).unwrap_or(0) as u16;
    let max_scroll = total_lines.saturating_sub(area_height);
    let mut scroll = current_scroll.min(max_scroll);
    
    // 确保光标在可见区域内
    if cursor_line_idx < scroll {
        scroll = cursor_line_idx;
    } else if cursor_line_idx >= scroll + area_height {
        scroll = cursor_line_idx + 1 - area_height;
    }
    scroll
}
```

### 3.3 键盘事件处理

`input` 方法是键盘事件的主入口，处理所有快捷键：

```rust
pub fn input(&mut self, event: KeyEvent) {
    // 忽略 Release 事件
    if !matches!(event.kind, KeyEventKind::Press | KeyEventKind::Repeat) {
        return;
    }
    match event {
        // C0 控制字符回退（某些终端发送）
        KeyEvent { code: KeyCode::Char('\u{0002}'), modifiers: NONE, .. } => self.move_cursor_left(),
        KeyEvent { code: KeyCode::Char('\u{0006}'), modifiers: NONE, .. } => self.move_cursor_right(),
        // ... 更多匹配
    }
}
```

### 3.4 渲染实现

实现 `WidgetRef` 和 `StatefulWidgetRef` trait：

```rust
impl WidgetRef for &TextArea {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        let lines = self.wrapped_lines(area.width);
        self.render_lines(area, buf, &lines, 0..lines.len());
    }
}

impl StatefulWidgetRef for &TextArea {
    type State = TextAreaState;
    fn render_ref(&self, area: Rect, buf: &mut Buffer, state: &mut Self::State) {
        let lines = self.wrapped_lines(area.width);
        let scroll = self.effective_scroll(area.height, &lines, state.scroll);
        state.scroll = scroll;
        let start = scroll as usize;
        let end = (scroll + area.height).min(lines.len() as u16) as usize;
        self.render_lines(area, buf, &lines, start..end);
    }
}
```

元素渲染使用青色（Cyan）高亮：

```rust
for elem in &self.elements {
    let overlap_start = elem.range.start.max(line_range.start);
    let overlap_end = elem.range.end.min(line_range.end);
    if overlap_start >= overlap_end { continue; }
    let styled = &self.text[overlap_start..overlap_end];
    let x_off = self.text[line_range.start..overlap_start].width() as u16;
    let style = Style::default().fg(Color::Cyan);
    buf.set_string(area.x + x_off, y, styled, style);
}
```

## 4. 关键代码路径与文件引用

### 4.1 主要调用路径

```
用户按键
  └── ChatComposer::handle_key_event
        └── TextArea::input
              ├── 字符输入 → insert_str
              ├── 删除键 → delete_backward / delete_forward
              ├── 移动键 → move_cursor_*
              └── Emacs 快捷键 → kill_to_* / yank

渲染循环
  └── ChatComposer::render
        └── TextArea::render_ref / render_ref_masked
              └── wrapped_lines → render_lines
```

### 4.2 相关文件

| 文件 | 关系 | 说明 |
|------|------|------|
| `codex-rs/tui/src/bottom_pane/chat_composer.rs` | 调用方 | 包装 TextArea，添加快捷键、弹出框、附件管理 |
| `codex-rs/tui/src/bottom_pane/mod.rs` | 调用方 | BottomPane 管理 ChatComposer |
| `codex-rs/tui/src/wrapping.rs` | 依赖 | 提供 `wrap_ranges` 用于自动换行 |
| `codex-rs/tui/src/key_hint.rs` | 依赖 | 提供 `is_altgr` 检测 Windows AltGr |
| `codex-rs/protocol/src/user_input.rs` | 依赖 | 定义 `TextElement` 和 `ByteRange` |
| `codex-rs/tui/src/render/renderable.rs` | 依赖 | 定义 `Renderable` trait（UnifiedExecFooter 使用） |

### 4.3 关键行号引用

- **数据结构定义**：行 39-82
- **输入处理**：行 291-537
- **删除操作**：行 540-647
- **光标移动**：行 649-810
- **元素管理**：行 812-999
- **边界处理**：行 1056-1159
- **单词导航**：行 1213-1266
- **换行与渲染**：行 1268-1411
- **测试**：行 1413-2449

## 5. 依赖与外部交互

### 5.1 外部 crate

| Crate | 用途 |
|-------|------|
| `crossterm` | 键盘事件类型（`KeyCode`, `KeyEvent`, `KeyModifiers`） |
| `ratatui` | TUI 渲染（`Buffer`, `Rect`, `Style`, `WidgetRef`） |
| `textwrap` | 自动换行算法 |
| `unicode-segmentation` | Grapheme cluster 处理 |
| `unicode-width` | 计算字符串显示宽度 |
| `codex_protocol` | `TextElement`, `ByteRange` 类型 |

### 5.2 协议交互

`TextArea` 通过 `text_elements()` 方法将内部元素转换为协议类型：

```rust
pub fn text_elements(&self) -> Vec<UserTextElement> {
    self.elements.iter().map(|e| {
        let placeholder = self.text.get(e.range.clone()).map(str::to_string);
        UserTextElement::new(ByteRange { start: e.range.start, end: e.range.end }, placeholder)
    }).collect()
}
```

这些元素随用户输入一起发送到后端，用于：
- 历史记录恢复时重建元素
- 附件（图片、技能提及）的持久化

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 字符边界安全

**风险**：所有字符串操作必须保证在 UTF-8 字符边界上。如果光标落在字符中间，会导致 panic。

**缓解措施**：
- `clamp_pos_to_char_boundary` 强制将任意位置对齐到边界
- 所有公共方法都经过边界处理

**潜在问题**：`replace_range_raw` 使用 `assert!` 检查范围，但调用方 `replace_range` 已经过扩展处理。

#### 6.1.2 元素重叠

**风险**：如果两个元素范围重叠，会导致不一致的行为。

**缓解措施**：
- `add_element_range` 检查重叠并拒绝
- `shift_elements` 处理元素位移时保持顺序

#### 6.1.3 性能问题

**风险**：大文本时 `wrapped_lines` 可能频繁重新计算。

**缓解措施**：
- 使用 `RefCell<Option<WrapCache>>` 缓存换行结果
- 只有宽度变化时才重新计算

**潜在改进**：使用增量更新而非全量重新计算。

#### 6.1.4 Kill Buffer 持久化

**风险**：`set_text_clearing_elements` 保留 kill buffer 的设计可能导致意外的粘贴行为。

**文档说明**：模块文档明确说明这是有意设计，但调用方需要理解这一行为。

### 6.2 边界情况

| 场景 | 行为 | 测试覆盖 |
|------|------|----------|
| 空文本 | 光标固定在 0 | 是 |
| 光标在元素边界 | 允许停留 | 是 |
| 光标在元素内部 | 强制移到最近边界 | 是 |
| 删除范围与元素重叠 | 扩展为删除整个元素 | 是 |
| 宽字符（CJK） | 正确处理显示宽度 | 是（fuzz 测试） |
| Emoji ZWJ 序列 | 作为单个 grapheme 处理 | 是（fuzz 测试） |
| 终端发送 C0 控制字符 | 识别为 Ctrl+B/F/P/N | 是 |

### 6.3 改进建议

#### 6.3.1 多条目 Kill Ring

当前只有单条目 kill buffer，可以考虑实现 Emacs 风格的多条目 kill ring（Ctrl+Y 后接 Alt+Y 循环历史）。

#### 6.3.2 增量换行

大文本时，每次宽度变化都重新计算所有换行。可以实现增量更新，只重新计算受影响的部分。

#### 6.3.3 选择/高亮支持

当前不支持文本选择。如果需要实现 Shift+方向键选择或鼠标选择，需要：
- 添加 `selection_range: Option<Range<usize>>` 字段
- 处理 Shift+移动键的修饰符
- 在渲染时高亮选区

#### 6.3.4 撤销/重做

当前没有撤销功能。可以实现基于编辑操作的历史栈。

#### 6.3.5 搜索/替换

可以添加在当前缓冲区中搜索的功能（类似 Emacs Ctrl+S）。

### 6.4 测试策略

当前测试覆盖非常全面：
- **单元测试**：每个公共方法的基本功能
- **边界测试**：空文本、边界位置、宽字符
- **集成测试**：键盘事件序列模拟
- **Fuzz 测试**：随机操作序列验证不变量（500 轮 × 60 步）

**测试文件位置**：行 1413-2449

**关键不变量验证**（fuzz 测试）：
1. 光标始终在 `[0, text.len()]` 范围内
2. 元素内的文本始终匹配初始 payload
3. 光标永远不会严格位于元素内部
4. 渲染和光标位置计算不会 panic
