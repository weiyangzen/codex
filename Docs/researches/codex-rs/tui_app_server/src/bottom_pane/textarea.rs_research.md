# TextArea 组件研究文档

## 场景与职责

`TextArea` 是 Codex TUI 应用服务器中核心的可编辑文本缓冲区组件，位于 `codex-rs/tui_app_server/src/bottom_pane/textarea.rs`。它是聊天编辑器（`ChatComposer`）的底层文本处理引擎，负责：

1. **文本编辑管理**：管理原始 UTF-8 文本内容，支持插入、删除、替换等操作
2. **光标控制**：维护光标位置，支持精确的字形边界（grapheme boundary）导航
3. **文本元素（Text Elements）**：支持原子性的占位符元素（如图片附件标记），这些元素在编辑时作为整体处理
4. **自动换行与滚动**：根据显示宽度计算换行，支持虚拟行导航和滚动状态管理
5. **Kill-Yank 缓冲区**：实现 Emacs 风格的 `Ctrl+K`（kill）和 `Ctrl+Y`（yank）功能，维护单条剪切历史

该组件是 TUI 底部面板（Bottom Pane）的核心输入基础设施，被 `ChatComposer`、`CustomPromptView`、`FeedbackNoteView` 等多个视图复用。

## 功能点目的

### 1. 核心文本编辑
- **目的**：提供可靠的文本编辑功能，支持多字节字符（Unicode）和组合字符
- **关键特性**：
  - 基于 `unicode_segmentation` 的字形簇（grapheme cluster）边界识别
  - 基于 `unicode_width` 的显示宽度计算
  - 字符边界安全（char boundary safety）强制校验

### 2. 文本元素（Text Elements）
- **目的**：支持富文本输入中的原子性占位符（如 `[Image #1]`），这些元素：
  - 在渲染时以特殊样式（青色）显示
  - 编辑时作为原子单位处理（不可在元素内部插入光标）
  - 支持通过 ID 进行程序化更新和替换
- **应用场景**：图片附件占位符、语音转录占位符、大段粘贴内容的延迟展开

### 3. Kill-Yank 缓冲区
- **目的**：提供 Emacs 风格的行内编辑体验
- **设计决策**：
  - 单条目设计（非多环），简化实现且满足大多数场景
  - 在 `set_text_clearing_elements` 和 `set_text_with_elements` 调用时保留，允许用户在提交后恢复剪切内容

### 4. 自动换行与虚拟行导航
- **目的**：在有限宽度区域内正确显示和导航多行文本
- **关键特性**：
  - 使用 `textwrap` 库进行智能换行
  - 缓存换行结果（`WrapCache`）避免重复计算
  - 支持跨虚拟行的光标移动（保持列位置偏好）

### 5. 键盘输入处理
- **目的**：统一处理各种终端的键盘输入差异
- **支持的快捷键**：
  - 光标移动：`Ctrl+B/F/P/N`、方向键、`Alt+B/F`（按词移动）
  - 删除操作：`Ctrl+H/D`（字符）、`Alt+Backspace/D`（按词删除）、`Ctrl+W`（删除词）、`Ctrl+U/K`（删除到行首/尾）
  - 粘贴：`Ctrl+Y`（yank）
  - 特殊处理：C0 控制字符（`^B`、`^F`、`^P`、`^N`）的回退支持

## 具体技术实现

### 关键数据结构

```rust
/// 文本区域主结构
pub(crate) struct TextArea {
    text: String,                    // 原始 UTF-8 文本
    cursor_pos: usize,               // 光标字节位置
    wrap_cache: RefCell<Option<WrapCache>>,  // 换行缓存
    preferred_col: Option<usize>,    // 跨行移动时的列位置偏好
    elements: Vec<TextElement>,      // 原子性文本元素
    next_element_id: u64,            // 元素 ID 生成器
    kill_buffer: String,             // 单条剪切历史
}

/// 换行缓存
#[derive(Debug, Clone)]
struct WrapCache {
    width: u16,                      // 缓存对应的宽度
    lines: Vec<Range<usize>>,        // 每行的字节范围（包含尾随空格和哨兵字节）
}

/// 内部文本元素表示
#[derive(Debug, Clone)]
struct TextElement {
    id: u64,                         // 唯一标识
    range: Range<usize>,             // 字节范围
    name: Option<String>,            // 可选名称（用于程序化查找）
}

/// 外部协议使用的元素快照
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct TextElementSnapshot {
    pub(crate) id: u64,
    pub(crate) range: Range<usize>,
    pub(crate) text: String,         // 元素的实际文本内容
}

/// 状态（用于 StatefulWidgetRef）
#[derive(Debug, Default, Clone, Copy)]
pub(crate) struct TextAreaState {
    scroll: u16,                     // 第一行可见行的索引
}
```

### 关键流程

#### 1. 文本插入流程（`insert_str_at`）
```rust
pub fn insert_str_at(&mut self, pos: usize, text: &str) {
    let pos = self.clamp_pos_for_insertion(pos);  // 确保不插入元素内部
    self.text.insert_str(pos, text);
    self.wrap_cache.replace(None);                // 使换行缓存失效
    if pos <= self.cursor_pos {
        self.cursor_pos += text.len();            // 调整光标位置
    }
    self.shift_elements(pos, /*removed*/ 0, text.len());  // 调整元素范围
    self.preferred_col = None;
}
```

#### 2. 元素感知替换（`replace_range_raw`）
```rust
fn replace_range_raw(&mut self, range: Range<usize>, text: &str) {
    // 1. 计算长度变化
    let diff = inserted_len as isize - removed_len as isize;
    
    // 2. 执行替换
    self.text.replace_range(range, text);
    
    // 3. 更新元素位置
    self.update_elements_after_replace(start, end, inserted_len);
    
    // 4. 调整光标位置
    self.cursor_pos = if self.cursor_pos < start {
        self.cursor_pos  // 在编辑范围之前：不变
    } else if self.cursor_pos <= end {
        start + inserted_len  // 在编辑范围内：移到新文本末尾
    } else {
        ((self.cursor_pos as isize) + diff) as usize  // 在编辑范围之后：按差值调整
    };
    
    // 5. 确保光标不在元素内部
    self.cursor_pos = self.clamp_pos_to_nearest_boundary(self.cursor_pos);
}
```

#### 3. 换行计算（`wrapped_lines`）
```rust
fn wrapped_lines(&self, width: u16) -> Ref<'_, Vec<Range<usize>>> {
    // 检查缓存是否有效
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
    
    // 返回缓存的只读引用
    Ref::map(cache, |c| &c.as_ref().unwrap().lines)
}
```

#### 4. 光标位置计算（`cursor_pos_with_state`）
```rust
pub fn cursor_pos_with_state(&self, area: Rect, state: TextAreaState) -> Option<(u16, u16)> {
    let lines = self.wrapped_lines(area.width);
    let effective_scroll = self.effective_scroll(area.height, &lines, state.scroll);
    
    // 找到光标所在的换行
    let i = Self::wrapped_line_index_by_start(&lines, self.cursor_pos)?;
    let ls = &lines[i];
    
    // 计算列位置（基于显示宽度）
    let col = self.text[ls.start..self.cursor_pos].width() as u16;
    
    // 计算屏幕行位置（考虑滚动）
    let screen_row = i.saturating_sub(effective_scroll as usize).try_into().unwrap_or(0);
    
    Some((area.x + col, area.y + screen_row))
}
```

#### 5. 元素边界扩展（`expand_range_to_element_boundaries`）
```rust
fn expand_range_to_element_boundaries(&self, mut range: Range<usize>) -> Range<usize> {
    // 循环扩展直到没有变化
    loop {
        let mut changed = false;
        for e in &self.elements {
            if e.range.start < range.end && e.range.end > range.start {
                // 范围与元素相交，扩展到包含整个元素
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

### 键盘输入处理

输入处理在 `input` 方法中实现，主要逻辑：

1. **过滤释放事件**：只处理 `Press` 和 `Repeat` 事件
2. **C0 控制字符回退**：处理某些终端发送的 `^B`、`^F`、`^P`、`^N` 控制字符
3. **AltGr 检测**：Windows 平台上将 `Alt+Control` 组合视为普通字符输入
4. **快捷键映射**：
   - `Ctrl+H` / `Backspace`：`delete_backward(1)`
   - `Ctrl+D` / `Delete`：`delete_forward(1)`
   - `Alt+Backspace` / `Ctrl+W` / `Alt+H`：`delete_backward_word()`
   - `Alt+D` / `Alt+Delete`：`delete_forward_word()`
   - `Ctrl+U`：`kill_to_beginning_of_line()`
   - `Ctrl+K`：`kill_to_end_of_line()`
   - `Ctrl+Y`：`yank()`
   - `Ctrl+A` / `Home`：`move_cursor_to_beginning_of_line()`
   - `Ctrl+E` / `End`：`move_cursor_to_end_of_line()`

### 词边界检测

```rust
const WORD_SEPARATORS: &str = "`~!@#$%^&*()-=+[{]}\\|;:'\",.<>/?";

fn is_word_separator(ch: char) -> bool {
    WORD_SEPARATORS.contains(ch)
}
```

词导航算法：
1. 跳过空白字符
2. 根据第一个非空白字符是否为分隔符确定词类型
3. 继续移动直到遇到不同类型的字符或空白

## 关键代码路径与文件引用

### 核心实现
- **主文件**：`codex-rs/tui_app_server/src/bottom_pane/textarea.rs`（约 2450 行）
- **模块声明**：`codex-rs/tui_app_server/src/bottom_pane/mod.rs`（第 109 行）

### 调用方
1. **`ChatComposer`**：`codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
   - 第 209-210 行：导入 `TextArea` 和 `TextAreaState`
   - 第 484-485 行：`textarea: TextArea` 和 `textarea_state: RefCell<TextAreaState>`
   - 主要调用：`insert_str`、`set_text_clearing_elements`、`text`、`cursor_pos` 等

2. **`CustomPromptView`**：`codex-rs/tui_app_server/src/bottom_pane/custom_prompt_view.rs`
   - 第 21-22 行：导入 `TextArea` 和 `TextAreaState`
   - 第 35-36 行：作为视图状态的一部分

3. **`FeedbackNoteView`**：`codex-rs/tui_app_server/src/bottom_pane/feedback_view.rs`
   - 第 29-30 行：导入 `TextArea` 和 `TextAreaState`
   - 第 58-59 行：用于反馈备注输入

### 依赖模块
1. **`wrapping`**：`codex-rs/tui_app_server/src/wrapping.rs`
   - 提供 `wrap_ranges` 函数用于换行计算
   - URL 感知的自适应换行逻辑

2. **`key_hint`**：`codex-rs/tui_app_server/src/key_hint.rs`
   - 提供 `is_altgr` 函数用于 Windows AltGr 检测

3. **协议类型**：`codex-rs/protocol/src/user_input.rs`
   - `TextElement`：协议级别的文本元素定义
   - `ByteRange`：字节范围定义

### 外部依赖
- `crossterm`：键盘事件类型
- `ratatui`：渲染基础设施（`Buffer`、`Rect`、`Style`、`WidgetRef`、`StatefulWidgetRef`）
- `textwrap`：文本换行算法
- `unicode_segmentation`：字形簇边界检测
- `unicode_width`：字符显示宽度计算

## 依赖与外部交互

### 与 `ChatComposer` 的交互

```rust
// ChatComposer 使用 TextArea 作为核心编辑组件
pub(crate) struct ChatComposer {
    textarea: TextArea,
    textarea_state: RefCell<TextAreaState>,
    // ...
}
```

关键交互点：
1. **文本获取**：`self.textarea.text()` 获取当前文本
2. **元素获取**：`self.textarea.text_elements()` 获取协议格式的元素列表
3. **光标位置**：`self.textarea.cursor_pos_with_state(area, state)` 用于渲染光标
4. **粘贴处理**：`self.textarea.insert_str(&pasted)` 插入粘贴内容
5. **元素插入**：`self.textarea.insert_element(&placeholder)` 插入图片占位符

### 与协议层的交互

通过 `TextElement` 和 `ByteRange` 类型与 `codex_protocol` 交互：

```rust
pub fn text_elements(&self) -> Vec<UserTextElement> {
    self.elements
        .iter()
        .map(|e| {
            let placeholder = self.text.get(e.range.clone()).map(str::to_string);
            UserTextElement::new(
                ByteRange {
                    start: e.range.start,
                    end: e.range.end,
                },
                placeholder,
            )
        })
        .collect()
}
```

### 渲染集成

实现 `ratatui` 的 `WidgetRef` 和 `StatefulWidgetRef` trait：

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
        // 处理滚动和渲染
    }
}
```

## 风险、边界与改进建议

### 已知风险

1. **字符边界安全**
   - 风险：如果外部传入非字符边界的位置，可能导致 panic
   - 缓解：所有公共方法都通过 `clamp_pos_to_char_boundary` 进行安全处理
   - 代码：`fn clamp_pos_to_char_boundary(&self, pos: usize) -> usize`

2. **换行缓存一致性**
   - 风险：文本修改后忘记使缓存失效可能导致渲染错误
   - 缓解：所有修改方法都调用 `self.wrap_cache.replace(None)`
   - 注意：使用 `RefCell` 允许在不可变引用时更新缓存

3. **元素重叠**
   - 风险：不当的 API 使用可能导致元素范围重叠
   - 缓解：`add_element_range` 检查重叠并拒绝添加
   - 降级策略：`expand_range_to_element_boundaries` 确保替换操作包含完整元素

4. **Kill 缓冲区内存**
   - 风险：大量 kill 操作可能累积大字符串
   - 缓解：单条目设计天然限制内存使用

### 边界情况

1. **零宽度字符**
   - 零宽度连接符（如 ZWJ 序列 `👩‍💻`）在光标移动时作为单个字形处理
   - 测试覆盖：`fuzz_textarea_randomized` 包含 ZWJ 序列测试

2. **极宽字符**
   - CJK 字符（宽度 2）和 Emoji（宽度 2）在列计算时正确处理
   - 换行算法使用 `unicode_width` 确保显示宽度准确

3. **空内容和边界**
   - 空字符串：光标固定在位置 0
   - 在文本末尾：所有导航方法安全返回末尾位置

4. **并发访问**
   - `RefCell` 在运行时检查借用规则，不当使用会导致 panic
   - 当前设计确保渲染和编辑不会同时发生

### 改进建议

1. **性能优化**
   - 考虑使用 `im` 或 `rpds` 实现持久化数据结构，支持更高效的撤销/重做
   - 大型文档（>10k 行）时，换行缓存可能占用大量内存，考虑 LRU 策略

2. **功能扩展**
   - 多条目 kill 环（Emacs 风格）可通过扩展 `kill_buffer` 为 `VecDeque` 实现
   - 支持矩形选择/块编辑模式

3. **代码质量**
   - `wrapped_lines` 中的 `#[expect(clippy::unwrap_used)]` 可以移除，使用更安全的模式
   - 部分方法（如 `replace_element_by_id`）在非 Linux 平台上有不同行为，文档化这些差异

4. **测试覆盖**
   - 当前测试非常全面（约 100 个测试用例），包括：
     - 单元测试：基本编辑、光标移动、删除操作
     - 属性测试：`fuzz_textarea_randomized` 使用随机输入验证不变量
   - 建议添加：
     - 多线程并发测试（如果未来支持）
     - 极端大文件性能测试

5. **可访问性**
   - 当前光标位置计算基于显示宽度，对屏幕阅读器友好
   - 考虑添加 Braille 显示支持的特殊模式

### 相关测试

```rust
// 主要测试模块位于文件末尾（第 1413-2449 行）
#[cfg(test)]
mod tests {
    // 关键测试：
    - insert_and_replace_update_cursor_and_text
    - delete_backward_and_forward_edges
    - delete_backward_word_and_kill_line_variants
    - yank_restores_last_kill
    - kill_buffer_persists_across_set_text
    - cursor_left_and_right_handle_graphemes
    - wrapped_navigation_across_visual_lines
    - fuzz_textarea_randomized  // 500 次迭代的随机测试
}
```
