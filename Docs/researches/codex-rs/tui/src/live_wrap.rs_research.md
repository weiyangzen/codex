# live_wrap.rs 深度研究文档

## 一、场景与职责

`live_wrap.rs` 是 Codex TUI 的**实时增量文本换行**模块，专门设计用于处理流式输出的动态换行需求。与 `wrapping.rs` 的批处理换行不同，该模块提供：

1. **增量处理**：支持流式输入，逐片段处理而非等待完整文本
2. **动态宽度调整**：支持在运行时改变目标宽度并重新换行
3. **行边界追踪**：区分显式换行（`\n`）和自动换行，支持精确的输出控制
4. **提交就绪管理**：支持按最大保留行数 drain 已完成的行，用于滚动显示

该模块是 TUI 中"打字机效果"、"实时流输出"等场景的核心基础设施。

## 二、功能点目的

### 2.1 核心功能

| 结构/函数 | 目的 |
|-----------|------|
| `Row` | 表示单个视觉行，包含文本和显式换行标记 |
| `RowBuilder` | 增量构建视觉行的状态机 |
| `take_prefix_by_width` | 按视觉宽度截取字符串前缀 |

### 2.2 RowBuilder API

| 方法 | 用途 |
|------|------|
| `new(target_width)` | 创建 builder，指定目标宽度 |
| `push_fragment(text)` | 推送文本片段（可包含 `\n`）|
| `end_line()` | 标记当前逻辑行结束 |
| `set_width(width)` | 动态改变目标宽度并重新换行 |
| `drain_rows()` | 取出所有已完成的行 |
| `rows()` | 查看已完成的行（不取出）|
| `display_rows()` | 查看所有行（包括当前未完成的）|
| `drain_commit_ready(max_keep)` | 按最大保留数 drain 行 |

### 2.3 使用场景

| 场景 | 说明 |
|------|------|
| 打字机效果 | 逐字符输出，实时换行 |
| 流式命令输出 | 命令执行时的实时输出显示 |
| 动态宽度调整 | 终端大小改变时重新换行 |
| 滚动日志 | 保留最近 N 行，旧行 drain 提交 |

## 三、具体技术实现

### 3.1 核心数据结构

```rust
/// 单个视觉行
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Row {
    pub text: String,
    /// true = 显式换行（有 \n），false = 自动换行
    pub explicit_break: bool,
}

impl Row {
    pub fn width(&self) -> usize {
        self.text.width()  // 使用 UnicodeWidthStr
    }
}
```

```rust
/// 增量换行构建器
pub struct RowBuilder {
    target_width: usize,
    current_line: String,  // 当前逻辑行的缓冲区
    rows: Vec<Row>,        // 已完成的视觉行
}
```

### 3.2 状态机设计

```
┌─────────────────────────────────────────────────────────────┐
│  RowBuilder 状态机                                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌─────────────┐    push_fragment     ┌─────────────┐     │
│   │   Empty     │ ───────────────────> │  Buffering  │     │
│   │  (初始)     │                      │  (缓冲中)   │     │
│   └─────────────┘                      └──────┬──────┘     │
│        ^                                      │            │
│        │                                      │ wrap       │
│        │            end_line/\n              ▼            │
│        └─────────────┐               ┌─────────────┐       │
│                      │               │   Wrapped   │       │
│                      └────────────── │  (已换行)   │       │
│                                      └─────────────┘       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 3.3 push_fragment 实现

```rust
pub fn push_fragment(&mut self, fragment: &str) {
    if fragment.is_empty() {
        return;
    }
    let mut start = 0usize;
    
    // 处理换行符
    for (i, ch) in fragment.char_indices() {
        if ch == '\n' {
            if start < i {
                self.current_line.push_str(&fragment[start..i]);
            }
            self.flush_current_line(/*explicit_break*/ true);
            start = i + ch.len_utf8();
        }
    }
    
    // 处理剩余内容
    if start < fragment.len() {
        self.current_line.push_str(&fragment[start..]);
        self.wrap_current_line();
    }
}
```

### 3.4 wrap_current_line 实现

```rust
fn wrap_current_line(&mut self) {
    loop {
        if self.current_line.is_empty() {
            break;
        }
        
        let (prefix, suffix, taken) = 
            take_prefix_by_width(&self.current_line, self.target_width);
        
        if taken == 0 {
            // 避免无限循环：取一个字符继续
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
            // 完全容纳，保留在缓冲区
            break;
        } else {
            // 输出前缀，继续处理后缀
            self.rows.push(Row { text: prefix, explicit_break: false });
            self.current_line = suffix.to_string();
        }
    }
}
```

### 3.5 take_prefix_by_width 实现

```rust
pub fn take_prefix_by_width(text: &str, max_cols: usize) -> (String, &str, usize) {
    if max_cols == 0 || text.is_empty() {
        return (String::new(), text, 0);
    }
    
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

### 3.6 动态宽度调整

```rust
pub fn set_width(&mut self, width: usize) {
    self.target_width = width.max(1);
    
    // 重新换行所有内容
    let mut all = String::new();
    for row in self.rows.drain(..) {
        all.push_str(&row.text);
        if row.explicit_break {
            all.push('\n');
        }
    }
    all.push_str(&self.current_line);
    self.current_line.clear();
    self.push_fragment(&all);
}
```

**注意**：重新换行是简单但有效的方法，时间复杂度 O(n)，适合中等数据量。

### 3.7 drain_commit_ready 实现

```rust
pub fn drain_commit_ready(&mut self, max_keep: usize) -> Vec<Row> {
    let display_count = self.rows.len() + 
        if self.current_line.is_empty() { 0 } else { 1 };
    
    if display_count <= max_keep {
        return Vec::new();
    }
    
    let to_commit = display_count - max_keep;
    let commit_count = to_commit.min(self.rows.len());
    
    let mut drained = Vec::with_capacity(commit_count);
    for _ in 0..commit_count {
        drained.push(self.rows.remove(0));
    }
    drained
}
```

用于滚动显示场景：保留最近 `max_keep` 行，将旧行 drain 出去提交显示。

## 四、关键代码路径与文件引用

### 4.1 调用方分布

| 文件 | 使用场景 |
|------|----------|
| `history_cell.rs` | `UnifiedExecProcessesCell` 中的命令截断 |
| `bottom_pane/unified_exec_footer.rs` | 统一执行页脚 |

### 4.2 与 history_cell.rs 的交互

```rust
// history_cell.rs
use crate::live_wrap::take_prefix_by_width;

// 在 UnifiedExecProcessesCell::display_lines 中
let (truncated, remainder, _) = take_prefix_by_width(&snippet, budget);
```

### 4.3 与 wrapping.rs 的对比

| 特性 | `live_wrap.rs` | `wrapping.rs` |
|------|----------------|---------------|
| 处理方式 | 增量、流式 | 批处理 |
| 宽度调整 | 动态支持 | 静态（每次重新调用）|
| 显式换行 | 追踪 `\n` | 支持 |
| 样式支持 | 纯文本 | 完整 ratatui 样式 |
| URL 感知 | 否 | 是 |
| 使用场景 | 实时流、打字机 | 历史渲染、Markdown |

## 五、依赖与外部交互

### 5.1 外部 crate

| Crate | 用途 |
|-------|------|
| `unicode_width` | `UnicodeWidthChar`, `UnicodeWidthStr` |

### 5.2 无 ratatui 依赖

与 `wrapping.rs` 不同，`live_wrap.rs` 是纯文本处理模块，不依赖 ratatui 的样式系统。这使得它：
- 更轻量
- 可用于非 ratatui 场景
- 需要样式时由调用方自行处理

### 5.3 依赖关系

```
live_wrap.rs
  └── unicode_width::{UnicodeWidthChar, UnicodeWidthStr}
```

## 六、风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 重新换行性能 | `set_width` 重新处理所有内容，大数据量时 O(n) | 适合中等数据量，不适合超大文本 |
| 无限循环 | 零宽字符或异常输入可能导致 `taken == 0` | 特殊处理：强制取一个字符 |
| 内存增长 | 未 drain 的行持续累积 | 调用方需定期 `drain_commit_ready` |
| 无样式支持 | 纯文本，样式信息丢失 | 由调用方在更高层处理 |

### 6.2 边界条件

1. **target_width = 0**：内部使用 `max(1)` 确保至少为 1
2. **空字符串**：`push_fragment("")` 直接返回
3. **仅换行符**：`"\n"` 产生空显式换行行
4. **超长无空格文本**：逐字符截断
5. **零宽字符**：`take_prefix_by_width` 返回 0 宽度，触发强制单字符逻辑

### 6.3 测试覆盖

模块包含 5 个单元测试：

| 测试 | 覆盖场景 |
|------|----------|
| `rows_do_not_exceed_width_ascii` | ASCII 文本换行 |
| `rows_do_not_exceed_width_emoji_cjk` | Emoji 和 CJK 宽字符 |
| `fragmentation_invariance_long_token` | 分片输入不变性 |
| `newline_splits_rows` | 显式换行处理 |
| `rewrap_on_width_change` | 动态宽度调整 |

**分片不变性测试**：
```rust
#[test]
fn fragmentation_invariance_long_token() {
    let s = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    // 完整输入
    let mut rb_all = RowBuilder::new(7);
    rb_all.push_fragment(s);
    let all_rows = rb_all.rows().to_vec();
    
    // 分片输入（每 3 字符）
    let mut rb_chunks = RowBuilder::new(7);
    for i in (0..s.len()).step_by(3) {
        rb_chunks.push_fragment(&s[i..(i+3).min(s.len())]);
    }
    let chunk_rows = rb_chunks.rows().to_vec();
    
    // 结果应相同
    assert_eq!(all_rows, chunk_rows);
}
```

### 6.4 改进建议

1. **样式支持**：考虑增加可选的样式追踪版本
2. **单词边界**：增加在单词边界换行的选项
3. **性能优化**：
   - 增量重新换行（仅重新计算受影响的行）
   - 使用 Rope 数据结构处理超大文本
4. **双向文本**：支持 RTL（从右到左）文本
5. ** grapheme cluster**：使用 `unicode_segmentation` 处理组合字符
6. **更多测试**：
   - 零宽字符测试
   - 组合字符测试
   - 边界条件测试（空输入、极大宽度等）

### 6.5 代码质量

- **简洁性**：290 行，职责清晰
- **文档**：良好的结构注释和模块文档
- **测试覆盖**：基本场景覆盖
- **零 unsafe**：纯安全 Rust
- **性能**：增量处理，避免不必要的分配

### 6.6 架构建议

当前 `live_wrap.rs` 和 `wrapping.rs` 有功能重叠，未来可考虑：

1. **统一抽象**：提取公共 trait `Wrapper`
2. **策略模式**：允许切换换行策略（字符、单词、URL 感知）
3. **组合使用**：`live_wrap` 处理流式输入，`wrapping` 处理样式和 URL

示例设计：
```rust
trait Wrapper {
    fn push(&mut self, text: &str);
    fn rows(&self) -> &[Row];
    fn drain(&mut self, max_keep: usize) -> Vec<Row>;
}

struct PlainWrapper { /* live_wrap 实现 */ }
struct StyledWrapper { /* wrapping 实现 */ }
```
