# codex-rs/utils/stream-parser 深度研究文档

## 1. 场景与职责

### 1.1 模块定位

`codex-utils-stream-parser` 是 Codex 项目中一个**零依赖**的底层工具库，专门用于**增量式解析流式文本**。它位于 `codex-rs/utils/stream-parser` 目录，是 `utils` 子模块的一部分。

### 1.2 核心场景

该模块解决的核心问题是：**AI 模型输出的流式响应可能包含跨 chunk 边界的隐藏标记（hidden markup）**。

典型场景：
- 模型输出包含 `<oai-mem-citation>doc A</oai-mem-citation>` 这样的引用标记
- 由于流式传输，这些标记可能被拆分到多个 chunk 中：
  - Chunk 1: `Hello <oai-mem-`
  - Chunk 2: `citation>doc A</oai-mem-citation> world`
- 独立解析每个 chunk 会导致标记识别失败

### 1.3 主要职责

1. **跨 chunk 状态保持**：维护解析器状态，处理被拆分的标签
2. **可见文本提取**：返回可立即渲染的安全文本
3. **隐藏载荷提取**：单独提取隐藏标记内的内容（如引用、计划块）
4. **UTF-8 边界处理**：处理字节流中跨 chunk 的 UTF-8 码点分割

---

## 2. 功能点目的

### 2.1 功能模块概览

| 模块 | 功能 | 用途 |
|------|------|------|
| `stream_text.rs` | 定义核心 trait 和结果结构 | 统一增量解析接口 |
| `inline_hidden_tag.rs` | 通用内联隐藏标签解析器 | 基础解析能力 |
| `citation.rs` | 引用标记解析器 | 提取 `<oai-mem-citation>` 内容 |
| `proposed_plan.rs` | 计划块解析器 | 提取 `<proposed_plan>` 内容 |
| `assistant_text.rs` | 组合解析器 | 同时处理引用和计划块 |
| `utf8_stream.rs` | UTF-8 字节流适配器 | 处理原始字节流 |
| `tagged_line_parser.rs` | 行级标签解析器 | 处理独占行的标签块 |

### 2.2 各功能点详细说明

#### 2.2.1 StreamTextParser Trait（stream_text.rs）

```rust
pub trait StreamTextParser {
    type Extracted;
    fn push_str(&mut self, chunk: &str) -> StreamTextChunk<Self::Extracted>;
    fn finish(&mut self) -> StreamTextChunk<Self::Extracted>;
}
```

**目的**：定义所有增量解析器的统一接口。

**StreamTextChunk 结构**：
```rust
pub struct StreamTextChunk<T> {
    pub visible_text: String,  // 可立即渲染的文本
    pub extracted: Vec<T>,     // 提取的隐藏载荷
}
```

#### 2.2.2 InlineHiddenTagParser（inline_hidden_tag.rs）

**目的**：通用解析器，可配置解析任意开闭标签对。

**核心设计**：
- 支持多标签类型（通过泛型参数 `T: Clone + Eq`）
- 使用 `pending` 缓冲区保存未决文本
- 使用 `active` 状态跟踪当前打开的标签
- 最长前缀-后缀匹配算法处理跨 chunk 标签边界

**关键算法**：
```rust
fn longest_suffix_prefix_len(s: &str, needle: &str) -> usize
```
计算 `s` 的后缀与 `needle` 的前缀的最长匹配长度，用于确定需要保留在缓冲区中的字符数。

#### 2.2.3 CitationStreamParser（citation.rs）

**目的**：专门解析 `<oai-mem-citation>...</oai-mem-citation>` 标签。

**实现**：基于 `InlineHiddenTagParser` 的薄封装，将提取结果从 `ExtractedInlineTag<T>` 简化为 `String`。

**辅助函数**：
```rust
pub fn strip_citations(text: &str) -> (String, Vec<String>)
```
用于非流式场景的一次性处理。

#### 2.2.4 ProposedPlanParser（proposed_plan.rs）

**目的**：解析 `<proposed_plan>` 块，用于 Plan 模式。

**特点**：
- 使用 `TaggedLineParser` 作为底层（行级解析）
- 标签必须独占一行（与 `InlineHiddenTagParser` 的区别）
- 提取结果为 `ProposedPlanSegment` 枚举，保留块的开始/结束/增量信息

**辅助函数**：
```rust
pub fn strip_proposed_plan_blocks(text: &str) -> String
pub fn extract_proposed_plan_text(text: &str) -> Option<String>
```

#### 2.2.5 AssistantTextStreamParser（assistant_text.rs）

**目的**：组合解析器，在 Plan 模式下同时处理引用和计划块。

**处理流程**：
1. 首先用 `CitationStreamParser` 处理输入，提取引用
2. 如果启用 Plan 模式，将可见文本传递给 `ProposedPlanParser`
3. 合并结果到 `AssistantTextChunk`

**结构**：
```rust
pub struct AssistantTextChunk {
    pub visible_text: String,
    pub citations: Vec<String>,
    pub plan_segments: Vec<ProposedPlanSegment>,
}
```

#### 2.2.6 Utf8StreamParser（utf8_stream.rs）

**目的**：包装任意 `StreamTextParser`，使其能够处理原始字节流（`&[u8]`）。

**核心问题**：UTF-8 码点可能跨 chunk 边界（如 `é` = `0xC3 0xA9`）

**处理策略**：
- 使用 `pending_utf8` 缓冲区保存不完整码点
- 使用 `std::str::from_utf8` 尝试解码
- 错误时回滚整个 chunk，保持解析器状态一致

**错误类型**：
```rust
pub enum Utf8StreamParserError {
    InvalidUtf8 { valid_up_to: usize, error_len: usize },
    IncompleteUtf8AtEof,
}
```

#### 2.2.7 TaggedLineParser（tagged_line_parser.rs）

**目的**：处理必须独占一行的标签块（如 `<proposed_plan>`）。

**状态机**：
```rust
struct TaggedLineParser<T> {
    specs: Vec<TagSpec<T>>,      // 标签规范
    active_tag: Option<T>,       // 当前活跃标签
    detect_tag: bool,            // 是否处于标签检测模式
    line_buffer: String,         // 行缓冲区
}
```

**关键行为**：
- 缓冲每一行直到确定是否为标签行
- 标签行判定：trim 后完全匹配开标签或闭标签
- 非标签行立即作为普通文本输出

---

## 3. 具体技术实现

### 3.1 InlineHiddenTagParser 状态机

```
状态: Idle (无活跃标签)
  │
  ├─ 发现开标签 ──> 状态: Active
  │   - 开标签前文本 -> visible_text
  │   - 开标签后内容 -> 缓冲区
  │
  └─ 无开标签 ──> 状态: Idle
      - 保留最长前缀-后缀匹配长度
      - 其余 -> visible_text

状态: Active (有活跃标签)
  │
  ├─ 发现闭标签 ──> 状态: Idle
  │   - 闭标签前内容 -> extracted
  │   - 闭标签后内容 -> 缓冲区
  │
  └─ 无闭标签 ──> 状态: Active
      - 保留最长前缀-后缀匹配长度
      - 其余 -> extracted 内容
```

### 3.2 最长前缀-后缀匹配算法

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

**示例**：
- `s = "abc<oai"`, `needle = "<oai-mem-citation>"`
- 检查后缀 `"<oai"` 匹配 `needle` 前缀 `"<oai"`
- 返回 4，保留这 4 个字符在缓冲区

### 3.3 UTF-8 边界处理

```rust
// 示例: "é" 跨两个 chunk
// Chunk 1: [b'H', 0xC3]  -> 解码失败，保留 0xC3
// Chunk 2: [0xA9, b'!']  -> 与 pending 合并解码为 "é!"
```

**错误恢复**：
- 无效 UTF-8 时回滚整个 chunk（`self.pending_utf8.truncate(old_len)`）
- 保证内层解析器不会看到部分数据

### 3.4 AssistantMessageStreamParsers（core 中的使用）

在 `codex-rs/core/src/codex.rs` 中：

```rust
#[derive(Debug, Default)]
struct AssistantMessageStreamParsers {
    plan_mode: bool,
    parsers_by_item: HashMap<String, AssistantTextStreamParser>,
}
```

**设计**：
- 每个 `item_id` 对应一个独立的解析器实例
- 支持并发处理多个 assistant message items
- `finish()` 时清理已完成的解析器

---

## 4. 关键代码路径与文件引用

### 4.1 模块文件结构

```
codex-rs/utils/stream-parser/
├── Cargo.toml              # 包配置（零依赖）
├── BUILD.bazel             # Bazel 构建配置
├── README.md               # 使用文档
└── src/
    ├── lib.rs              # 模块导出
    ├── stream_text.rs      # StreamTextParser trait + StreamTextChunk
    ├── inline_hidden_tag.rs # InlineHiddenTagParser 通用解析器
    ├── citation.rs         # CitationStreamParser 引用解析
    ├── proposed_plan.rs    # ProposedPlanParser 计划块解析
    ├── assistant_text.rs   # AssistantTextStreamParser 组合解析
    ├── utf8_stream.rs      # Utf8StreamParser 字节流适配
    └── tagged_line_parser.rs # TaggedLineParser 行级解析
```

### 4.2 核心调用链

#### 4.2.1 流式响应处理链（codex.rs）

```
codex-rs/core/src/codex.rs:6491
AssistantMessageStreamParsers::new(plan_mode)
    │
    ├─> seed_item_text(item_id, text)  // 初始文本
    │   └─> AssistantTextStreamParser::push_str()
    │       ├─> CitationStreamParser::push_str()
    │       │   └─> InlineHiddenTagParser::push_str()
    │       └─> (plan_mode) ProposedPlanParser::push_str()
    │           └─> TaggedLineParser::parse()
    │
    ├─> parse_delta(item_id, delta)    // 增量文本
    │   └─> (同上)
    │
    └─> finish_item(item_id)           // 完成处理
        └─> AssistantTextStreamParser::finish()
```

#### 4.2.2 非流式处理链（stream_events_utils.rs）

```
codex-rs/core/src/stream_events_utils.rs:33
strip_hidden_assistant_markup(text, plan_mode)
    ├─> strip_citations(text)           // citation.rs:69
    │   └─> CitationStreamParser 一次性处理
    │
    └─> (plan_mode) strip_proposed_plan_blocks()
        └─> ProposedPlanParser 一次性处理
```

### 4.3 关键代码行号

| 功能 | 文件 | 行号 |
|------|------|------|
| StreamTextParser trait | stream_text.rs | 27-35 |
| InlineHiddenTagParser 状态机 | inline_hidden_tag.rs | 118-198 |
| 最长前缀-后缀匹配 | inline_hidden_tag.rs | 200-208 |
| CitationStreamParser | citation.rs | 22-62 |
| ProposedPlanParser | proposed_plan.rs | 28-84 |
| AssistantTextStreamParser | assistant_text.rs | 23-73 |
| Utf8StreamParser | utf8_stream.rs | 44-178 |
| TaggedLineParser | tagged_line_parser.rs | 22-167 |
| AssistantMessageStreamParsers | codex.rs | 6491-6538 |
| PlanDeltaEvent 发送 | codex.rs | 6569-6576 |

---

## 5. 依赖与外部交互

### 5.1 内部依赖关系

```
lib.rs
    ├─> stream_text.rs (基础 trait)
    ├─> inline_hidden_tag.rs (依赖 stream_text)
    ├─> citation.rs (依赖 inline_hidden_tag, stream_text)
    ├─> proposed_plan.rs (依赖 tagged_line_parser, stream_text)
    ├─> assistant_text.rs (依赖 citation, proposed_plan, stream_text)
    ├─> utf8_stream.rs (依赖 stream_text)
    └─> tagged_line_parser.rs (无依赖)
```

### 5.2 外部依赖

**零运行时依赖**：`Cargo.toml` 中仅声明 `pretty_assertions` 为 dev-dependency。

**下游使用者**：

| 使用者 | 用途 |
|--------|------|
| `codex-core` | 流式解析 assistant message |
| `codex-protocol` | 定义 PlanDeltaEvent 等协议类型 |
| `codex-tui-app-server` | 处理 PlanDeltaEvent |

### 5.3 与 core 模块的交互

**导入点**（codex.rs）：
```rust
use codex_utils_stream_parser::AssistantTextChunk;
use codex_utils_stream_parser::AssistantTextStreamParser;
use codex_utils_stream_parser::ProposedPlanSegment;
use codex_utils_stream_parser::extract_proposed_plan_text;
use codex_utils_stream_parser::strip_citations;
```

**导入点**（stream_events_utils.rs）：
```rust
use codex_utils_stream_parser::strip_citations;
use codex_utils_stream_parser::strip_proposed_plan_blocks;
```

### 5.4 与 protocol 模块的交互

`PlanDeltaEvent` 定义在 `codex-rs/protocol/src/protocol.rs:1654`：
```rust
pub struct PlanDeltaEvent {
    pub thread_id: String,
    pub turn_id: String,
    pub item_id: String,
    pub delta: String,
}
```

由 `ProposedPlanSegment::ProposedPlanDelta` 转换后发送。

---

## 6. 风险、边界与改进建议

### 6.1 已知限制（README 中明确说明）

1. **标签字面量匹配**：区分大小写，不支持正则
2. **无嵌套标签支持**：`<a><b>x</b></a>` 会被错误解析
3. **可能返回空对象**：流式处理中某些 chunk 可能不产生输出

### 6.2 边界情况分析

#### 6.2.1 标签边界情况

| 场景 | 行为 | 风险等级 |
|------|------|----------|
| 开标签跨 chunk | 正确缓冲，等待完整标签 | 低 |
| 闭标签跨 chunk | 正确缓冲，等待完整标签 | 低 |
| 标签内容跨 chunk | 正确累积内容 | 低 |
| 未闭合标签 EOF | `finish()` 自动闭合，返回已收集内容 | 中 |
| 嵌套标签 | 第一层闭合即结束，内层标签作为内容 | 高 |
| 相同前缀标签 | 优先匹配最长开标签 | 低 |

#### 6.2.2 UTF-8 边界情况

| 场景 | 行为 | 风险等级 |
|------|------|----------|
| 多字节码点跨 chunk | 正确缓冲，等待完整码点 | 低 |
| 无效 UTF-8 序列 | 返回错误，回滚 chunk | 低 |
| EOF 时部分码点 | 返回 `IncompleteUtf8AtEof` 错误 | 中 |

#### 6.2.3 行级解析边界情况

| 场景 | 行为 | 风险等级 |
|------|------|----------|
| 标签行有额外文本 | 视为普通文本（非标签） | 低 |
| 标签后无换行 EOF | `finish()` 处理 | 中 |
| 开闭标签不匹配 | 按普通文本处理 | 中 |

### 6.3 潜在风险

#### 6.3.1 内存风险

- **pending 缓冲区无限增长**：如果恶意输入长时间不包含标签边界，缓冲区会持续累积
- **缓解**：实际场景中模型输出有长度限制，且 `finish()` 会清理

#### 6.3.2 解析错误风险

- **嵌套标签误解析**：如果模型输出嵌套引用，解析结果不符合预期
- **标签前缀冲突**：多个标签有相同前缀时，匹配顺序依赖实现细节

### 6.4 改进建议

#### 6.4.1 功能增强

1. **嵌套标签支持**：
   ```rust
   // 当前：不支持嵌套
   // 建议：添加嵌套层级跟踪
   struct ActiveTag<T> {
       tag: T,
       close: &'static str,
       content: String,
       depth: usize,  // 新增
   }
   ```

2. **配置化缓冲区大小限制**：
   ```rust
   pub struct InlineHiddenTagParser<T> {
       max_pending_len: usize,  // 新增：防止内存无限增长
       // ...
   }
   ```

3. **流式 UTF-8 错误恢复策略**：
   - 当前：遇到无效 UTF-8 回滚整个 chunk
   - 建议：支持替换字符模式（�）继续解析

#### 6.4.2 性能优化

1. **避免 String 分配**：
   - 当前：频繁使用 `String::new()` 和 `push_str`
   - 建议：使用 `SmallString` 或对象池减少分配

2. **Aho-Corasick 多模式匹配**：
   - 当前：每个标签单独 `find()`
   - 建议：多标签场景使用 AC 自动机一次扫描

#### 6.4.3 可观测性增强

1. **解析统计**：
   ```rust
   pub struct ParserStats {
       pub chunks_processed: usize,
       pub bytes_processed: usize,
       pub tags_extracted: usize,
       pub max_pending_len: usize,
   }
   ```

2. **Tracing 集成**：
   - 添加 `tracing` feature，记录解析事件

#### 6.4.4 测试覆盖

当前测试覆盖良好，但可补充：
- 模糊测试（fuzzing）验证边界情况
- 性能基准测试（criterion）
- 多线程并发测试（验证 `!Sync` 类型安全）

### 6.5 代码质量评估

| 维度 | 评分 | 说明 |
|------|------|------|
| 正确性 | 高 | 边界情况处理完善，测试覆盖率高 |
| 性能 | 中 | 有优化空间（String 分配、多模式匹配） |
| 可维护性 | 高 | 代码结构清晰，文档充分 |
| 安全性 | 高 | 无 unsafe 代码，错误处理完善 |
| 零依赖 | 优秀 | 符合工具库定位 |

---

## 7. 总结

`codex-utils-stream-parser` 是一个设计精良的底层工具库，解决了流式 AI 响应解析的核心问题。其关键价值在于：

1. **状态保持**：跨 chunk 维护解析状态，处理标签边界分割
2. **零依赖**：自包含实现，降低依赖复杂度
3. **组合设计**：通过 trait 和泛型实现灵活组合
4. **生产验证**：在 codex-core 中承担关键路径

主要使用场景：
- **实时流式响应**：TUI 中逐字显示 assistant message
- **Plan 模式**：提取和显示计划块
- **引用提取**：收集模型引用的记忆文档

风险提示：
- 嵌套标签场景需要调用方确保模型输出格式
- 超长无边界输入可能导致内存累积（需配合超时机制）
