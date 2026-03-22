# codex-rs/utils/stream-parser/src 深度研究文档

## 概述

`codex-utils-stream-parser` 是一个专门用于流式文本解析的 Rust 库，位于 Codex 项目的 `codex-rs/utils/stream-parser` 目录下。该库的核心使命是解决大模型输出流中的隐藏标记（hidden markup）解析问题，特别是处理跨数据块边界分割的标签。

---

## 一、场景与职责

### 1.1 核心场景

该库主要服务于以下场景：

1. **大模型流式输出处理**：当模型输出以流（stream）形式到达时，数据可能被分割成多个 chunk。隐藏标记（如 `<oai-mem-citation>...</oai-mem-citation>`）可能被切分到不同 chunk 中（例如 `<oai-mem-` 在第一个 chunk，`citation>` 在第二个 chunk）。

2. **隐藏标记提取与剥离**：模型输出中可能包含需要提取但不显示给用户的元数据（如引用来源、计划块等）。该库负责：
   - 从可见文本中剥离这些标记
   - 提取标记内的内容供后续处理

3. **Plan 模式支持**：在 Plan 模式下，模型会输出 `<proposed_plan>...</proposed_plan>` 块，需要特殊处理以分离计划内容和普通对话内容。

4. **UTF-8 字节流处理**：处理原始字节流时，UTF-8 字符可能被切分到不同 chunk（如 `é` 的 0xC3 和 0xA9 字节）。

### 1.2 主要职责

| 职责 | 说明 |
|------|------|
| 增量解析 | 维护跨 chunk 的解析状态，正确处理被分割的标签 |
| 可见文本提取 | 返回可立即渲染给用户的安全文本 |
| 隐藏内容提取 | 提取标记内的内容作为结构化数据 |
| 错误处理 | 处理无效的 UTF-8 序列等错误情况 |
| 多标签支持 | 支持同时处理多种类型的隐藏标记 |

---

## 二、功能点目的

### 2.1 功能模块概览

```
┌─────────────────────────────────────────────────────────────────┐
│                     stream-parser 架构                          │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │   StreamText    │  │  InlineHidden   │  │    Utf8Stream   │ │
│  │     Parser      │  │   TagParser     │  │     Parser      │ │
│  │   (trait)       │  │   (generic)     │  │   (adapter)     │ │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘ │
│           │                    │                    │          │
│           ▼                    ▼                    ▼          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │  CitationStream │  │  ProposedPlan   │  │ AssistantText  │ │
│  │     Parser      │  │     Parser      │  │ StreamParser   │ │
│  │   ( concrete)   │  │   ( concrete)   │  │  (composite)   │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 各功能点详细说明

#### 2.2.1 `StreamTextParser` Trait（`stream_text.rs`）

**目的**：定义流式文本解析器的通用接口。

**核心设计**：
```rust
pub trait StreamTextParser {
    type Extracted;
    fn push_str(&mut self, chunk: &str) -> StreamTextChunk<Self::Extracted>;
    fn finish(&mut self) -> StreamTextChunk<Self::Extracted>;
}
```

**输出结构** `StreamTextChunk<T>`：
- `visible_text`: 可立即渲染的文本
- `extracted`: 提取的隐藏内容列表

#### 2.2.2 `InlineHiddenTagParser`（`inline_hidden_tag.rs`）

**目的**：通用的内联隐藏标签解析器，支持任意自定义标签。

**关键特性**：
- 支持多标签类型（通过泛型参数 `T: Clone + Eq`）
- 字面量匹配，区分大小写
- 不支持嵌套标签
- 流结束时自动关闭未闭合的标签

**核心数据结构**：
```rust
pub struct InlineHiddenTagParser<T> {
    specs: Vec<InlineTagSpec<T>>,     // 标签规范列表
    pending: String,                   // 待处理的缓冲文本
    active: Option<ActiveTag<T>>,     // 当前活跃的标签
}

struct ActiveTag<T> {
    tag: T,
    close: &'static str,              // 闭合标签字符串
    content: String,                   // 已收集的内容
}
```

**跨 chunk 边界处理策略**：

1. **开放标签前缀匹配**：当缓冲文本的结尾可能是某个开放标签的前缀时，保留这部分文本不输出，等待下一个 chunk。

2. **最长后缀-前缀匹配算法** (`longest_suffix_prefix_len`)：
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
   该函数找出字符串 `s` 的最长后缀，该后缀同时也是 `needle` 的前缀（但不等于完整的 `needle`）。

#### 2.2.3 `CitationStreamParser`（`citation.rs`）

**目的**：专门处理 `<oai-mem-citation>...</oai-mem-citation>` 标签的便捷包装器。

**实现**：基于 `InlineHiddenTagParser<CitationTag>` 的薄封装，将提取的 `ExtractedInlineTag` 转换为纯字符串。

**常量定义**：
```rust
const CITATION_OPEN: &str = "<oai-mem-citation>";
const CITATION_CLOSE: &str = "</oai-mem-citation>";
```

**便捷函数** `strip_citations(text: &str) -> (String, Vec<String>)`：用于非流式字符串的一次性处理。

#### 2.2.4 `Utf8StreamParser`（`utf8_stream.rs`）

**目的**：适配原始字节流（`&[u8]`），处理 UTF-8 字符可能被分割到不同 chunk 的情况。

**核心机制**：
- 维护 `pending_utf8: Vec<u8>` 缓冲区
- 使用 `std::str::from_utf8` 尝试解码
- 对于不完整的 UTF-8 序列（如多字节字符的前导字节），保留在缓冲区等待下一个 chunk

**错误类型** `Utf8StreamParserError`：
- `InvalidUtf8`: 遇到无效的 UTF-8 序列
- `IncompleteUtf8AtEof`: 流结束时仍有未完成的 UTF-8 码点

**关键行为**：当遇到无效 UTF-8 时，回滚整个 chunk（`self.pending_utf8.truncate(old_len)`），确保内部解析器不会看到部分前缀。

#### 2.2.5 `ProposedPlanParser`（`proposed_plan.rs`）

**目的**：处理 Plan 模式下的 `<proposed_plan>...</proposed_plan>` 块。

**特殊之处**：基于 `TaggedLineParser` 实现，要求标签必须独占一行（行级标签而非内联标签）。

**输出段类型** `ProposedPlanSegment`：
```rust
pub enum ProposedPlanSegment {
    Normal(String),                    // 普通文本
    ProposedPlanStart,                 // 计划块开始
    ProposedPlanDelta(String),         // 计划块内容增量
    ProposedPlanEnd,                   // 计划块结束
}
```

**便捷函数**：
- `strip_proposed_plan_blocks(text: &str) -> String`: 剥离计划块
- `extract_proposed_plan_text(text: &str) -> Option<String>`: 提取计划文本

#### 2.2.6 `TaggedLineParser`（`tagged_line_parser.rs`）

**目的**：行级标签解析器，用于处理必须独占一行的标签（如 `<proposed_plan>`）。

**核心逻辑**：
- 缓冲每一行直到可以确定该行是否为标签
- 使用 `detect_tag` 标志控制标签检测状态
- 标签行要求：整行（去除空白后）完全匹配开放或闭合标签

**段合并优化** (`push_segment`)：
- 连续的 `Normal` 段会合并
- 连续的同类型 `TagDelta` 段会合并
- 减少输出段数量，提高处理效率

#### 2.2.7 `AssistantTextStreamParser`（`assistant_text.rs`）

**目的**：组合解析器，在一个 pass 中同时处理引用和计划块。

**架构**：
```rust
pub struct AssistantTextStreamParser {
    plan_mode: bool,
    citations: CitationStreamParser,    // 第一层：处理引用
    plan: ProposedPlanParser,           // 第二层：处理计划块（仅在 plan_mode 下）
}
```

**处理流程**：
1. 输入文本 → `CitationStreamParser` → 剥离引用后的可见文本 + 引用列表
2. 可见文本 → `ProposedPlanParser` → 最终可见文本 + 计划段列表

**输出结构** `AssistantTextChunk`：
```rust
pub struct AssistantTextChunk {
    pub visible_text: String,
    pub citations: Vec<String>,
    pub plan_segments: Vec<ProposedPlanSegment>,
}
```

---

## 三、具体技术实现

### 3.1 关键流程

#### 3.1.1 `InlineHiddenTagParser::push_str` 处理流程

```
┌─────────────────────────────────────────────────────────────────┐
│                     push_str 流程                               │
├─────────────────────────────────────────────────────────────────┤
│  1. 将新 chunk 追加到 pending 缓冲区                            │
│  2. 检查是否有活跃标签 (active)                                  │
│     ├─ 是：尝试查找闭合标签                                      │
│     │   ├─ 找到：提取内容，创建 ExtractedInlineTag，继续循环    │
│     │   └─ 未找到：保留可能是闭合标签前缀的后缀，其余加入内容    │
│     └─ 否：尝试查找开放标签                                      │
│         ├─ 找到：创建 ActiveTag，继续循环                        │
│         └─ 未找到：保留可能是开放标签前缀的后缀，其余作为可见文本│
│  3. 返回 StreamTextChunk                                         │
└─────────────────────────────────────────────────────────────────┘
```

#### 3.1.2 `Utf8StreamParser::push_bytes` 处理流程

```
┌─────────────────────────────────────────────────────────────────┐
│                    push_bytes 流程                              │
├─────────────────────────────────────────────────────────────────┤
│  1. 保存 old_len（当前缓冲区长度）                               │
│  2. 将新字节追加到 pending_utf8                                 │
│  3. 尝试将整个缓冲区解码为 UTF-8                                 │
│     ├─ 成功：调用内部 parser 的 push_str，清空缓冲区，返回结果  │
│     └─ 失败：检查错误类型                                        │
│         ├─ 无效序列：回滚到 old_len，返回错误                   │
│         └─ 不完整序列：提取有效部分处理，保留剩余字节            │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 关键数据结构

#### 3.2.1 标签规范

```rust
pub struct InlineTagSpec<T> {
    pub tag: T,                    // 标签类型标识
    pub open: &'static str,        // 开放标签字符串（如 "<tag>"）
    pub close: &'static str,       // 闭合标签字符串（如 "</tag>"）
}
```

#### 3.2.2 提取的内联标签

```rust
pub struct ExtractedInlineTag<T> {
    pub tag: T,                    // 标签类型
    pub content: String,           // 标签内的内容
}
```

### 3.3 协议与约定

#### 3.3.1 标签匹配规则

1. **字面量匹配**：标签匹配是区分大小写的字面量匹配，不使用正则表达式
2. **非嵌套**：标签不支持嵌套，遇到第一个匹配的闭合标签即结束
3. **自动关闭**：流结束时如果标签未闭合，自动将已收集的内容作为提取结果

#### 3.3.2 跨边界处理约定

1. **前缀保留**：当缓冲文本结尾可能是标签的前缀时，保留该部分不输出
2. **最长匹配**：当多个标签规范匹配时，优先选择：
   - 位置最靠前的
   - 相同位置时，开放标签更长的（避免 `<a>` 匹配 `<ab>` 的前缀）

---

## 四、关键代码路径与文件引用

### 4.1 文件结构

```
codex-rs/utils/stream-parser/src/
├── lib.rs                    # 模块导出和公共接口
├── stream_text.rs            # StreamTextParser trait 和 StreamTextChunk
├── inline_hidden_tag.rs      # InlineHiddenTagParser 通用内联标签解析器
├── citation.rs               # CitationStreamParser 引用解析器
├── utf8_stream.rs            # Utf8StreamParser UTF-8 字节流适配器
├── proposed_plan.rs          # ProposedPlanParser 计划块解析器
├── tagged_line_parser.rs     # TaggedLineParser 行级标签解析器
└── assistant_text.rs         # AssistantTextStreamParser 组合解析器
```

### 4.2 关键代码路径

#### 4.2.1 引用提取路径

```
codex-rs/core/src/stream_events_utils.rs:9
    strip_citations(text) 
    └── codex-rs/utils/stream-parser/src/citation.rs:69
        CitationStreamParser::new()
        └── InlineHiddenTagParser::new(vec![InlineTagSpec { ... }])
```

#### 4.2.2 流式助手消息解析路径

```
codex-rs/core/src/codex.rs:120
    use codex_utils_stream_parser::AssistantTextStreamParser
    
    AssistantMessageStreamParsers::parser_mut(item_id)
    └── AssistantTextStreamParser::new(plan_mode)
        ├── CitationStreamParser::new()
        └── ProposedPlanParser::new()
            └── TaggedLineParser::new(vec![TagSpec { ... }])
```

#### 4.2.3 Plan 块处理路径

```
codex-rs/core/src/stream_events_utils.rs:28
    use codex_utils_stream_parser::strip_proposed_plan_blocks
    
    strip_hidden_assistant_markup(text, plan_mode)
    └── strip_proposed_plan_blocks(&without_citations)
        └── ProposedPlanParser::new()
```

### 4.3 核心算法代码位置

| 算法 | 文件 | 行号 |
|------|------|------|
| 最长后缀-前缀匹配 | `inline_hidden_tag.rs` | 200-208 |
| 开放标签查找 | `inline_hidden_tag.rs` | 72-88 |
| 跨 chunk 边界处理 | `inline_hidden_tag.rs` | 124-174 |
| UTF-8 不完整序列处理 | `utf8_stream.rs` | 66-109 |
| 行级标签检测 | `tagged_line_parser.rs` | 46-82 |
| 段合并优化 | `tagged_line_parser.rs` | 169-199 |

---

## 五、依赖与外部交互

### 5.1 内部依赖

该 crate 是 `codex-utils` 的一部分，**零外部依赖**（`Cargo.toml` 仅包含 `pretty_assertions` 作为 dev-dependency）。

### 5.2 外部使用者

#### 5.2.1 `codex-core`

**位置**：`codex-rs/core/src/codex.rs`

**使用方式**：
```rust
use codex_utils_stream_parser::AssistantTextChunk;
use codex_utils_stream_parser::AssistantTextStreamParser;
use codex_utils_stream_parser::ProposedPlanSegment;
use codex_utils_stream_parser::extract_proposed_plan_text;
use codex_utils_stream_parser::strip_citations;
```

**场景**：
- `AssistantMessageStreamParsers` 管理每个 item 的解析器实例
- 在流式响应中增量解析助手消息
- 提取引用和计划段

#### 5.2.2 `stream_events_utils`

**位置**：`codex-rs/core/src/stream_events_utils.rs`

**使用方式**：
```rust
use codex_utils_stream_parser::strip_citations;
use codex_utils_stream_parser::strip_proposed_plan_blocks;
```

**场景**：
- `strip_hidden_assistant_markup`: 剥离隐藏标记获取可见文本
- `strip_hidden_assistant_markup_and_parse_memory_citation`: 同时提取引用
- `record_stage1_output_usage_for_completed_item`: 记录引用使用情况

### 5.3 依赖关系图

```
┌─────────────────────────────────────────────────────────────────┐
│                     依赖关系图                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌─────────────────────┐                                       │
│   │  codex-utils-stream │◄────── 零外部依赖                     │
│   │     -parser         │                                       │
│   └──────────┬──────────┘                                       │
│              │                                                  │
│              ▼                                                  │
│   ┌─────────────────────┐     ┌─────────────────────┐          │
│   │     codex-core      │◄────┤  stream_events_utils│          │
│   │   (codex.rs)        │     │                     │          │
│   └─────────────────────┘     └─────────────────────┘          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 六、风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 标签前缀冲突

**风险**：如果普通文本恰好以标签的前缀结尾，该部分会被缓冲等待，直到下一个 chunk 到达才能确定。

**示例**：文本 `"Hello <oai-mem-"` 会缓冲整个 `"<oai-mem-"`，直到下一个 chunk 到达。

**缓解**：这是设计上的权衡，确保不会错误地将标签的一部分作为可见文本输出。

#### 6.1.2 嵌套标签不支持

**风险**：如果模型输出嵌套的引用标签，解析行为可能不符合预期。

**测试验证**（`citation.rs:171-178`）：
```rust
#[test]
fn citation_parser_does_not_support_nested_tags() {
    let (visible, citations) = strip_citations(
        "a<oai-mem-citation>x<oai-mem-citation>y</oai-mem-citation>z</oai-mem-citation>b",
    );
    // 结果：visible = "az</oai-mem-citation>b", citations = ["x<oai-mem-citation>y"]
}
```

#### 6.1.3 内存使用

**风险**：`InlineHiddenTagParser` 维护 `pending` 字符串缓冲区，在极端情况下（如非常大的 chunk 且包含大量标签前缀）可能占用较多内存。

### 6.2 边界情况

#### 6.2.1 已处理的边界情况

| 边界情况 | 处理方式 |
|---------|---------|
| 标签被切分到多个 chunk | 通过 `pending` 缓冲区和前缀匹配处理 |
| UTF-8 字符被切分 | `Utf8StreamParser` 缓冲不完整序列 |
| 流结束时标签未闭合 | `finish()` 自动关闭并提取内容 |
| 无效 UTF-8 序列 | 返回 `InvalidUtf8` 错误，回滚 chunk |
| 空开放/闭合标签 | 构造函数断言失败（panic） |
| 多标签规范冲突 | 优先匹配位置靠前、标签更长的 |

#### 6.2.2 未覆盖的边界情况

1. **重叠标签**：如果两个不同类型的标签在文本中重叠（虽然模型不太可能生成）
2. **超大内容**：标签内包含极大内容时的内存效率
3. **特殊 Unicode**：组合字符、零宽字符等在标签边界的情况

### 6.3 改进建议

#### 6.3.1 性能优化

1. **零拷贝优化**：当前实现使用 `String` 缓冲，对于超大流可以考虑使用 `rope` 数据结构或流式处理

2. **预分配策略**：对于已知平均 chunk 大小的场景，可以预分配 `pending` 缓冲区

3. **SIMD 加速**：对于标签查找，可以使用 SIMD 指令加速（如 `memchr` crate）

#### 6.3.2 功能扩展

1. **嵌套标签支持**：如果业务需要，可以扩展支持有限层级的嵌套标签

2. **正则表达式标签**：当前仅支持字面量匹配，可以考虑支持简单的通配符或正则

3. **异步流适配器**：提供与 `tokio::io::AsyncRead` 或 `futures::Stream` 的集成

#### 6.3.3 可观测性

1. **调试日志**：在解析状态转换时添加 `trace!` 日志，便于调试复杂的跨 chunk 边界问题

2. **Metrics**：暴露解析统计信息（处理的 chunk 数、提取的标签数等）

#### 6.3.4 代码质量

1. **模糊测试**：使用 `cargo-fuzz` 对解析器进行模糊测试，发现边界情况

2. **基准测试**：添加 `criterion` 基准测试，确保性能回归可检测

3. **文档示例**：README 中的示例可以扩展更多边界情况

### 6.4 维护注意事项

根据 `README.md` 的免责声明：

> **Disclaimer**: This code is pretty complex and Codex did not manage to write it so before updating the code, make sure to deeply understand it and don't blindly trust Codex on it.

**关键提醒**：
1. 修改前务必深入理解跨 chunk 边界处理的逻辑
2. 任何修改都应伴随全面的单元测试
3. 特别注意 `longest_suffix_prefix_len` 和标签前缀匹配逻辑
4. 测试应包含标签被切分到多个 chunk 的各种情况

---

## 七、测试覆盖

### 7.1 单元测试分布

| 模块 | 测试文件 | 测试数量 |
|------|---------|---------|
| `inline_hidden_tag.rs` | 模块内 `#[cfg(test)]` | 5 |
| `citation.rs` | 模块内 `#[cfg(test)]` | 7 |
| `utf8_stream.rs` | 模块内 `#[cfg(test)]` | 6 |
| `proposed_plan.rs` | 模块内 `#[cfg(test)]` | 5 |
| `tagged_line_parser.rs` | 模块内 `#[cfg(test)]` | 2 |
| `assistant_text.rs` | 模块内 `#[cfg(test)]` | 2 |

### 7.2 关键测试场景

1. **跨 chunk 边界**：所有解析器都测试了标签/字符被切分到多个 chunk 的情况
2. **UTF-8 处理**：`utf8_stream.rs` 测试了多字节字符切分、无效序列、流结束时不完整序列
3. **错误恢复**：`utf8_stream.rs` 测试了无效 UTF-8 后的状态恢复
4. **自动关闭**：测试了流结束时未闭合标签的处理

---

## 八、总结

`codex-utils-stream-parser` 是一个设计精良、职责单一的流式文本解析库。其核心创新在于优雅地处理了流式数据中的跨 chunk 边界问题，确保隐藏标记能够被正确提取而不影响可见文本的及时渲染。

该库采用分层架构：
- **基础层**：`StreamTextParser` trait 定义接口
- **通用层**：`InlineHiddenTagParser` 提供可复用的内联标签解析
- **适配层**：`Utf8StreamParser` 处理字节流到字符串的转换
- **专用层**：`CitationStreamParser`、`ProposedPlanParser` 提供特定功能
- **组合层**：`AssistantTextStreamParser` 整合多种解析需求

零外部依赖的设计使其具有良好的可移植性和编译性能，是 Codex 项目中处理模型输出的关键基础设施组件。
