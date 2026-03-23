# citation.rs 研究文档

## 场景与职责

`citation.rs` 实现了 `CitationStreamParser`，专门用于解析和处理 `<oai-mem-citation>...</oai-mem-citation>` 标签。这是 OpenAI 模型输出中用于嵌入引用/来源信息的特殊标记。

该解析器是 `InlineHiddenTagParser` 的便捷包装，提供：
1. 流式解析引用标签
2. 提取引用内容（如文档 ID、来源标识）
3. 从可见文本中去除引用标记
4. 一次性处理非流式字符串的辅助函数

## 功能点目的

### CitationStreamParser
- **目的**: 流式解析 `<oai-mem-citation>` 标签
- **特性**:
  - 字面量匹配，非嵌套
  - 自动处理未关闭标签（EOF 时自动关闭）
  - 支持跨块边界的不完整标签

### strip_citations 函数
- **目的**: 一次性处理完整字符串，提取所有引用
- **返回**: `(visible_text, citations)` 元组
- **使用场景**: 非流式处理，如后处理已完成的消息

## 具体技术实现

### 标签常量

```rust
const CITATION_OPEN: &str = "<oai-mem-citation>";
const CITATION_CLOSE: &str = "</oai-mem-citation>";
```

### CitationTag 枚举

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CitationTag {
    Citation,
}
```

用于标识标签类型，当前只有一个变体，但设计支持未来扩展。

### CitationStreamParser 结构

```rust
#[derive(Debug)]
pub struct CitationStreamParser {
    inner: InlineHiddenTagParser<CitationTag>,
}
```

### 实现细节

```rust
impl CitationStreamParser {
    pub fn new() -> Self {
        Self {
            inner: InlineHiddenTagParser::new(vec![InlineTagSpec {
                tag: CitationTag::Citation,
                open: CITATION_OPEN,
                close: CITATION_CLOSE,
            }]),
        }
    }
}

impl Default for CitationStreamParser {
    fn default() -> Self {
        Self::new()
    }
}

impl StreamTextParser for CitationStreamParser {
    type Extracted = String;  // 直接返回内容字符串

    fn push_str(&mut self, chunk: &str) -> StreamTextChunk<Self::Extracted> {
        let inner = self.inner.push_str(chunk);
        StreamTextChunk {
            visible_text: inner.visible_text,
            extracted: inner.extracted.into_iter().map(|tag| tag.content).collect(),
        }
    }

    fn finish(&mut self) -> StreamTextChunk<Self::Extracted> {
        let inner = self.inner.finish();
        StreamTextChunk {
            visible_text: inner.visible_text,
            extracted: inner.extracted.into_iter().map(|tag| tag.content).collect(),
        }
    }
}
```

### strip_citations 实现

```rust
pub fn strip_citations(text: &str) -> (String, Vec<String>) {
    let mut parser = CitationStreamParser::new();
    let mut out = parser.push_str(text);
    let tail = parser.finish();
    out.visible_text.push_str(&tail.visible_text);
    out.extracted.extend(tail.extracted);
    (out.visible_text, out.extracted)
}
```

## 关键代码路径与文件引用

- **文件路径**: `codex-rs/utils/stream-parser/src/citation.rs`
- **依赖**:
  - `inline_hidden_tag.rs`: `InlineHiddenTagParser`, `InlineTagSpec`
  - `stream_text.rs`: `StreamTextChunk`, `StreamTextParser`
- **被依赖**:
  - `assistant_text.rs`: `AssistantTextStreamParser` 内部使用
  - `utf8_stream.rs`: 测试中使用
  - `lib.rs`: 导出 `CitationStreamParser`, `strip_citations`

## 依赖与外部交互

### 在 AssistantTextStreamParser 中的使用

```rust
// assistant_text.rs
#[derive(Debug, Default)]
pub struct AssistantTextStreamParser {
    plan_mode: bool,
    citations: CitationStreamParser,
    plan: ProposedPlanParser,
}

impl AssistantTextStreamParser {
    pub fn push_str(&mut self, chunk: &str) -> AssistantTextChunk {
        let citation_chunk = self.citations.push_str(chunk);
        let mut out = self.parse_visible_text(citation_chunk.visible_text);
        out.citations = citation_chunk.extracted;
        out
    }
}
```

### 使用示例

```rust
use codex_utils_stream_parser::{CitationStreamParser, StreamTextParser};

let mut parser = CitationStreamParser::new();

// 跨块处理
let first = parser.push_str("Hello <oai-mem-");
assert_eq!(first.visible_text, "Hello ");
assert!(first.extracted.is_empty());

let second = parser.push_str("citation>doc A</oai-mem-citation> world");
assert_eq!(second.visible_text, " world");
assert_eq!(second.extracted, vec!["doc A".to_string()]);

// 一次性处理
let (visible, citations) = strip_citations(
    "a<oai-mem-citation>one</oai-mem-citation>b"
);
assert_eq!(visible, "ab");
assert_eq!(citations, vec!["one".to_string()]);
```

## 风险、边界与改进建议

### 边界情况处理

| 场景 | 行为 |
|------|------|
| 跨块边界 | `<oai-mem-` + `citation>` 正确处理 |
| 未关闭标签 | EOF 时自动关闭，提取已缓冲内容 |
| 嵌套标签 | 不支持，第一个 `</oai-mem-citation>` 关闭 |
| 部分前缀 | `<oai-mem-` 不是完整标签，保留在可见文本 |

### 测试覆盖

| 测试 | 描述 |
|------|------|
| `citation_parser_streams_across_chunk_boundaries` | 跨块边界处理 |
| `citation_parser_buffers_partial_open_tag_prefix` | 部分标签前缀缓冲 |
| `citation_parser_auto_closes_unterminated_tag_on_finish` | 未关闭标签自动关闭 |
| `citation_parser_preserves_partial_open_tag_at_eof_if_not_a_full_tag` | 非完整前缀保留 |
| `strip_citations_collects_all_citations` | 一次性提取多个引用 |
| `strip_citations_auto_closes_unterminated_citation_at_eof` | 未关闭引用处理 |
| `citation_parser_does_not_support_nested_tags` | 嵌套标签行为 |

### 风险点

1. **硬编码标签**: 标签名 `<oai-mem-citation>` 硬编码，不支持配置
2. **嵌套限制**: 嵌套引用标签会导致意外行为
3. **性能**: 依赖 `InlineHiddenTagParser` 的实现，大数据量时可能需优化

### 改进建议

1. **配置化标签名**: 允许运行时配置标签名（如果需要支持其他模型）
   ```rust
   pub fn with_custom_tags(open: &'static str, close: &'static str) -> Self
   ```

2. **错误报告**: 当前静默处理嵌套标签，可考虑警告或错误

3. **引用元数据**: 当前只提取纯文本内容，未来可能需要结构化元数据
   ```rust
   pub struct Citation {
       pub source_id: String,
       pub metadata: Option<serde_json::Value>,
   }
   ```

4. **性能优化**: 对于高频场景，考虑使用 `&str` 而非 `String` 减少分配
