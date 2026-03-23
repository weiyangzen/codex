# live_wrap.rs 深度研究文档

## 场景与职责

`live_wrap.rs` 实现了一个增量式文本换行（wrap）构建器 `RowBuilder`，用于实时流式文本的换行处理。主要应用场景：

1. **流式输出显示**：AI 模型生成的流式文本需要实时换行显示
2. **终端宽度自适应**：终端大小变化时重新换行
3. **大文本增量处理**：避免一次性处理大量文本，支持逐片段输入

与 `wrapping.rs` 的区别：
- `wrapping.rs`：基于 `textwrap` 的完整文本换行，适合静态内容
- `live_wrap.rs`：增量式构建，支持动态添加文本、宽度变更重排，适合流式场景

## 功能点目的

### 1. `Row` - 视觉行表示

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Row {
    pub text: String,
    /// True if this row ends with an explicit line break (as opposed to a hard wrap).
    pub explicit_break: bool,
}
```

表示一个视觉行，区分：
- **显式换行**（`explicit_break = true`）：由输入中的 `\n` 产生
- **硬换行**（`explicit_break = false`）：由宽度限制自动换行产生

### 2. `RowBuilder` - 增量换行构建器

核心结构体，维护以下状态：
```rust
pub struct RowBuilder {
    target_width: usize,      // 目标宽度
    current_line: String,     // 当前逻辑行的缓冲区
    rows: Vec<Row>,           // 已完成的视觉行
}
```

#### 主要方法

| 方法 | 用途 |
|------|------|
| `new(target_width)` | 创建构建器，确保宽度至少为 1 |
| `push_fragment(text)` | 增量添加文本片段，处理其中的 `\n` |
| `end_line()` | 标记当前逻辑行结束（等效于添加 `\n`） |
| `drain_rows()` | 取出所有已完成的行（清空内部状态） |
| `rows()` | 查看已完成的行（不取出） |
| `display_rows()` | 获取所有行，包括当前未完成的缓冲区 |
| `drain_commit_ready(max_keep)` | 取出超出保留限制的旧行 |
| `set_width(width)` | 动态变更宽度，触发全部重排 |

### 3. `take_prefix_by_width` - 按宽度取前缀

```rust
pub fn take_prefix_by_width(text: &str, max_cols: usize) -> (String, &str, usize)
```

工具函数，从文本左侧取出不超过 `max_cols` 视觉宽度的前缀，返回：
- 前缀字符串（拥有所有权）
- 剩余后缀（借用）
- 实际占用的列数

## 具体技术实现

### 增量处理流程

```
输入文本片段 → push_fragment
                    ↓
        ┌─────────────────────┐
        │ 按 \n 分割为逻辑行   │
        └─────────────────────┘
                    ↓
        ┌─────────────────────┐
        │ 逐逻辑行 wrap_current_line │
        │ (按 target_width 分割)     │
        └─────────────────────┘
                    ↓
        ┌─────────────────────┐
        │ flush_current_line   │
        │ (标记 explicit_break)│
        └─────────────────────┘
                    ↓
              输出 Row
```

### 核心算法

#### `push_fragment` 处理换行

```rust
pub fn push_fragment(&mut self, fragment: &str) {
    let mut start = 0usize;
    for (i, ch) in fragment.char_indices() {
        if ch == '\n' {
            // 换行前内容追加到当前行
            if start < i {
                self.current_line.push_str(&fragment[start..i]);
            }
            // 刷新当前行，标记显式换行
            self.flush_current_line(/*explicit_break*/ true);
            start = i + ch.len_utf8();
        }
    }
    // 剩余内容追加到当前行
    if start < fragment.len() {
        self.current_line.push_str(&fragment[start..]);
        self.wrap_current_line();  // 尝试自动换行
    }
}
```

#### `wrap_current_line` 自动换行

```rust
fn wrap_current_line(&mut self) {
    loop {
        if self.current_line.is_empty() { break; }
        
        // 尝试取出不超过目标宽度的前缀
        let (prefix, suffix, taken) = take_prefix_by_width(&self.current_line, self.target_width);
        
        if taken == 0 {
            // 防止无限循环：取一个字符继续
            if let Some((i, ch)) = self.current_line.char_indices().next() {
                let len = i + ch.len_utf8();
                let p = self.current_line[..len].to_string();
                self.rows.push(Row { text: p, explicit_break: false });
                self.current_line = self.current_line[len..].to_string();
                continue;
            }
            break;
        }
        
        if suffix.is_empty() {
            // 全部内容可放入，保留在缓冲区等待更多输入
            break;
        } else {
            // 前缀作为硬换行行输出
            self.rows.push(Row { text: prefix, explicit_break: false });
            self.current_line = suffix.to_string();
        }
    }
}
```

#### `set_width` 重排

```rust
pub fn set_width(&mut self, width: usize) {
    self.target_width = width.max(1);
    
    // 收集所有内容（包括已完成的行和当前缓冲区）
    let mut all = String::new();
    for row in self.rows.drain(..) {
        all.push_str(&row.text);
        if row.explicit_break {
            all.push('\n');
        }
    }
    all.push_str(&self.current_line);
    self.current_line.clear();
    
    // 重新处理
    self.push_fragment(&all);
}
```

### `take_prefix_by_width` 实现

```rust
pub fn take_prefix_by_width(text: &str, max_cols: usize) -> (String, &str, usize) {
    let mut cols = 0usize;
    let mut end_idx = 0usize;
    
    for (i, ch) in text.char_indices() {
        let ch_width = UnicodeWidthChar::width(ch).unwrap_or(0);
        if cols.saturating_add(ch_width) > max_cols {
            break;
        }
        cols += ch_width;
        end_idx = i + ch.len_utf8();
        if cols == max_cols {
            break;
        }
    }
    
    let prefix = text[..end_idx].to_string();
    let suffix = &text[end_idx..];
    (prefix, suffix, cols)
}
```

## 关键代码路径与文件引用

### 调用方

| 文件 | 用途 |
|------|------|
| `src/markdown_stream.rs` | 流式 Markdown 渲染的文本换行 |
| `src/streaming.rs` | 流式输出的行构建 |
| `src/chatwidget.rs` | 聊天消息的行管理 |

### 依赖

| Crate/模块 | 用途 |
|------------|------|
| `unicode_width::{UnicodeWidthChar, UnicodeWidthStr}` | Unicode 宽度计算 |

## 依赖与外部交互

### 输入

- 文本片段（`&str`）：可能包含 `\n`、多字节字符
- 目标宽度（`usize`）：正整数，最小为 1

### 输出

- `Row` 结构体序列：每个包含文本内容和换行类型标记

### 关键不变式

1. **碎片化不变性**（Fragmentation Invariance）：
   - 无论文本是分多次 `push_fragment` 还是一次推送，最终产生的 `Row` 序列相同
   - 测试 `fragmentation_invariance_long_token` 验证此特性

2. **宽度约束**：
   - 所有输出的 `Row.text` 的视觉宽度 ≤ `target_width`
   - 例外：单个字符宽度超过目标宽度时，单独成行

3. **显式换行保留**：
   - 输入中的 `\n` 一定产生 `explicit_break = true` 的行
   - 即使 `\n` 出现在行首或行尾

## 风险、边界与改进建议

### 已知风险

1. **`set_width` 性能**：宽度变更时触发全部重排，O(n) 复杂度，大文本时可能卡顿
   - 当前实现：简单收集全部文本重新处理
   - 潜在优化：使用更智能的增量重排算法

2. **内存使用**：`current_line` 和 `rows` 都存储字符串，大文本时内存占用较高
   - 考虑使用 `Arc<str>` 或字符串池共享

3. **边界字符处理**：当单个字符宽度超过目标宽度时，采取"取一个字符"的兜底策略，可能导致行略微超出目标宽度

### 边界情况处理

| 情况 | 处理 |
|------|------|
| 空字符串 | 不产生行 |
| 仅空白字符 | 按实际宽度处理 |
| 连续 `\n` | 产生空行的 `Row`（`explicit_break = true`） |
| 宽度为 0 | 强制设置为 1 |
| 超大宽度 | 正常处理，可能单行输出 |
| 混合 ASCII 和 CJK | `unicode_width` 正确处理（CJK 宽度 2） |

### 测试覆盖

现有测试：

```rust
#[test]
fn rows_do_not_exceed_width_ascii() { ... }

#[test]
fn rows_do_not_exceed_width_emoji_cjk() { ... }

#[test]
fn fragmentation_invariance_long_token() { ... }

#[test]
fn newline_splits_rows() { ... }

#[test]
fn rewrap_on_width_change() { ... }
```

测试使用 `pretty_assertions::assert_eq` 提供清晰的差异输出。

### 改进建议

1. **增量重排优化**：
   ```rust
   // 仅重排受影响的行，而非全部
   pub fn set_width_optimized(&mut self, width: usize) {
       // 找到第一个需要重排的行位置
       // 仅重排该位置之后的行
   }
   ```

2. **内存优化**：
   ```rust
   pub struct Row {
       pub text: Arc<str>,  // 共享所有权
       pub explicit_break: bool,
   }
   ```

3. **更多控制选项**：
   ```rust
   pub struct WrapOptions {
       pub break_words: bool,      // 是否允许单词内断行
       pub word_separator: WordSeparator,  // 单词分隔符策略
       pub wrap_algorithm: WrapAlgorithm,  // 换行算法
   }
   ```

4. **行号追踪**：
   ```rust
   pub struct Row {
       pub text: String,
       pub explicit_break: bool,
       pub source_line: usize,  // 对应原始输入的行号
   }
   ```

5. **与 `wrapping.rs` 的统一**：
   - 考虑将 `live_wrap` 的增量能力整合到 `wrapping.rs`
   - 或提取公共的宽度计算工具到独立模块
