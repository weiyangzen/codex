# inline_hidden_tag.rs 研究文档

## 场景与职责

`inline_hidden_tag.rs` 实现了 `InlineHiddenTagParser<T>`，这是一个通用的流式内联标签解析器。它能够：
1. 识别并隐藏配置的内联标签（如 `<tag>...</tag>`）
2. 提取标签内的内容作为有效载荷
3. 处理标签跨数据块边界的情况

该解析器是 `CitationStreamParser` 的基础，用于处理 `<oai-mem-citation>...</oai-mem-citation>` 标签。

## 功能点目的

### ExtractedInlineTag<T>
- 表示提取的内联标签
- 字段:
  - `tag: T`: 标签类型标识
  - `content: String`: 标签内的内容

### InlineTagSpec<T>
- 标签规范，用于配置解析器
- 字段:
  - `tag: T`: 标签类型
  - `open: &'static str`: 开始标签（如 `<tag>`）
  - `close: &'static str`: 结束标签（如 `</tag>`）

### InlineHiddenTagParser<T>
- 核心解析器结构
- 支持多标签类型同时解析
- 支持非 ASCII 字符的标签
- 处理跨块边界的不完整标签

## 具体技术实现

### 核心数据结构

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExtractedInlineTag<T> {
    pub tag: T,
    pub content: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct InlineTagSpec<T> {
    pub tag: T,
    pub open: &'static str,
    pub close: &'static str,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ActiveTag<T> {
    tag: T,
    close: &'static str,
    content: String,
}

pub struct InlineHiddenTagParser<T> {
    specs: Vec<InlineTagSpec<T>>,  // 标签规范列表
    pending: String,               // 待处理缓冲区
    active: Option<ActiveTag<T>>,  // 当前激活的标签
}
```

### 关键算法

#### 1. 查找下一个开始标签

```rust
fn find_next_open(&self) -> Option<(usize, usize)> {
    self.specs
        .iter()
        .enumerate()
        .filter_map(|(idx, spec)| {
            self.pending
                .find(spec.open)
                .map(|pos| (pos, spec.open.len(), idx))
        })
        .min_by(|(pos_a, len_a, idx_a), (pos_b, len_b, idx_b)| {
            pos_a.cmp(pos_b)           // 优先位置靠前
                .then_with(|| len_b.cmp(len_a))  // 相同位置优先较长的
                .then_with(|| idx_a.cmp(idx_b))  // 最后按索引
        })
        .map(|(pos, _len, idx)| (pos, idx))
}
```

**策略**: 位置优先 > 长度优先 > 定义顺序

#### 2. 最长后缀-前缀匹配

```rust
fn longest_suffix_prefix_len(s: &str, needle: &str) -> usize {
    let max = s.len().min(needle.len().saturating_sub(1));
    for k in (1..=max).rev() {
        if needle.is_char_boundary(k) && s.ends_with(&needle[..k]) {
            return k;
        }
    }
    0
}
```

**用途**: 处理标签跨块边界的情况。例如 `"<oai-mem-"` 可能是 `<oai-mem-citation>` 的前缀，需要保留等待下一个块。

#### 3. push_str 主循环

```rust
fn push_str(&mut self, chunk: &str) -> StreamTextChunk<Self::Extracted> {
    self.pending.push_str(chunk);
    let mut out = StreamTextChunk::default();

    loop {
        // 情况1: 已有激活的标签，查找结束标签
        if let Some(close) = self.active.as_ref().map(|active| active.close) {
            if let Some(close_idx) = self.pending.find(close) {
                // 找到结束标签，提取内容
                // ...
                continue;
            }
            // 未找到结束标签，保留可能是前缀的部分
            // ...
            break;
        }

        // 情况2: 没有激活标签，查找开始标签
        if let Some((open_idx, spec_idx)) = self.find_next_open() {
            // 找到开始标签，激活新标签
            // ...
            continue;
        }

        // 情况3: 没有标签，保留可能是开始标签前缀的部分
        let keep = self.max_open_prefix_suffix_len();
        self.drain_visible_to_suffix_match(&mut out, keep);
        break;
    }

    out
}
```

### finish 处理

```rust
fn finish(&mut self) -> StreamTextChunk<Self::Extracted> {
    let mut out = StreamTextChunk::default();

    // 如果有未关闭的标签，自动关闭并提取内容
    if let Some(mut active) = self.active.take() {
        if !self.pending.is_empty() {
            active.content.push_str(&self.pending);
            self.pending.clear();
        }
        out.extracted.push(ExtractedInlineTag {
            tag: active.tag,
            content: active.content,
        });
        return out;
    }

    // 剩余内容作为可见文本
    if !self.pending.is_empty() {
        out.visible_text.push_str(&self.pending);
        self.pending.clear();
    }

    out
}
```

## 关键代码路径与文件引用

- **文件路径**: `codex-rs/utils/stream-parser/src/inline_hidden_tag.rs`
- **依赖**:
  - `stream_text.rs`: `StreamTextChunk`, `StreamTextParser`
- **被依赖**:
  - `citation.rs`: `CitationStreamParser` 基于此实现
  - `lib.rs`: 导出 `ExtractedInlineTag`, `InlineHiddenTagParser`, `InlineTagSpec`

## 依赖与外部交互

### 使用示例

```rust
use codex_utils_stream_parser::{InlineHiddenTagParser, InlineTagSpec, StreamTextParser};

#[derive(Clone, Debug, PartialEq, Eq)]
enum Tag {
    Secret,
}

let mut parser = InlineHiddenTagParser::new(vec![InlineTagSpec {
    tag: Tag::Secret,
    open: "<secret>",
    close: "</secret>",
}]);

let out = parser.push_str("a<secret>x</secret>b");
assert_eq!(out.visible_text, "ab");
assert_eq!(out.extracted.len(), 1);
assert_eq!(out.extracted[0].content, "x");
```

### 构造函数断言

```rust
pub fn new(specs: Vec<InlineTagSpec<T>>) -> Self {
    assert!(!specs.is_empty(), "InlineHiddenTagParser requires at least one tag spec");
    for spec in &specs {
        assert!(!spec.open.is_empty(), "InlineHiddenTagParser requires non-empty open delimiters");
        assert!(!spec.close.is_empty(), "InlineHiddenTagParser requires non-empty close delimiters");
    }
    // ...
}
```

## 风险、边界与改进建议

### 边界情况处理

1. **跨块标签**: `<oai-mem-` + `citation>` 正确处理
2. **未关闭标签**: EOF 时自动关闭并提取内容
3. **非 ASCII 支持**: 正确处理多字节字符（如 `<é>中</é>`）
4. **相同位置多个标签**: 优先匹配较长的标签（如 `<ab>` 优于 `<a>`）
5. **嵌套标签**: 明确不支持，按非嵌套处理

### 测试覆盖

| 测试 | 描述 |
|------|------|
| `generic_inline_parser_supports_multiple_tag_types` | 多标签类型支持 |
| `generic_inline_parser_supports_non_ascii_tag_delimiters` | 非 ASCII 字符支持 |
| `generic_inline_parser_prefers_longest_opener_at_same_offset` | 最长标签优先 |
| `generic_inline_parser_rejects_empty_open_delimiter` | 空开始标签拒绝 |
| `generic_inline_parser_rejects_empty_close_delimiter` | 空结束标签拒绝 |

### 风险点

1. **性能**: `find_next_open` 每次都要扫描整个 `pending` 缓冲区，大数据量时可能成为瓶颈
2. **内存**: `pending` 缓冲区可能无限增长（如果从未匹配到标签）
3. **复杂性**: 后缀-前缀匹配逻辑复杂，容易出错

### 改进建议

1. **性能优化**: 使用 Aho-Corasick 或类似算法加速多模式匹配
2. **内存限制**: 添加 `pending` 缓冲区大小限制，防止内存溢出
3. **流式输出**: 当前 `visible_text` 可能累积大量文本，考虑分块输出
4. **错误处理**: 当前遇到无效 UTF-8 依赖 Rust 标准库处理，可考虑更精细控制
5. **嵌套支持**: 如果需求变化，需要重新设计以支持嵌套标签
