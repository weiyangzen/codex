# README.md 研究文档

## 场景与职责

此文件是 `codex-utils-stream-parser` crate 的文档入口，面向开发者和使用者介绍该库的设计目标、API 和使用示例。README 明确警告该代码的复杂性，并提醒修改者需要深入理解而非盲目信任 AI 生成代码。

## 功能点目的

1. **设计意图说明**: 解释为什么需要流式解析器（处理跨 chunk 边界的标签）
2. **API 概览**: 列出 crate 提供的核心类型和函数
3. **使用示例**: 提供三个典型用例的代码示例
4. **风险提示**: 强调代码复杂性，提醒谨慎修改

## 具体技术实现

### 核心组件架构

```
┌─────────────────────────────────────────────────────────────┐
│                    StreamTextParser (trait)                  │
│  - push_str(&mut self, chunk: &str) -> StreamTextChunk<T>   │
│  - finish(&mut self) -> StreamTextChunk<T>                  │
└─────────────────────────────────────────────────────────────┘
                              ▲
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
┌───────┴───────┐    ┌───────┴───────┐    ┌───────┴───────┐
│ InlineHidden  │    │  Citation     │    │   Utf8Stream  │
│  TagParser<T> │    │ StreamParser  │    │  Parser<P>    │
│  (通用实现)    │    │ (专用包装器)   │    │ (字节流适配)   │
└───────────────┘    └───────────────┘    └───────────────┘
        ▲
        │
┌───────┴───────┐
│ TaggedLine    │
│   Parser<T>   │
│ (行级解析器)   │
└───────────────┘
```

### 关键数据结构

#### `StreamTextChunk<T>`
```rust
pub struct StreamTextChunk<T> {
    pub visible_text: String,  // 可立即渲染的文本
    pub extracted: Vec<T>,     // 提取的隐藏载荷
}
```

#### `InlineTagSpec<T>`
```rust
pub struct InlineTagSpec<T> {
    pub tag: T,                // 标签类型标识
    pub open: &'static str,    // 开始标记（如 "<oai-mem-citation>"）
    pub close: &'static str,   // 结束标记（如 "</oai-mem-citation>"）
}
```

### 解析流程

1. **标签检测状态机**:
   ```
   Normal ──"<oai-mem-"──► Pending ──"citation>"──► InsideTag ──"</oai-mem-citation>"──► Normal
   ```

2. **跨 chunk 边界处理**:
   - 当检测到可能是标签前缀的内容时，保留在 `pending` 缓冲区
   - 等待下一个 chunk 确认是否为完整标签
   - 使用 `longest_suffix_prefix_len` 算法确定需要保留的后缀长度

3. **UTF-8 边界处理** (`Utf8StreamParser`):
   - 缓存不完整的 UTF-8 序列（如 `0xC3` 等待 `0xA9`）
   - 在 `push_bytes` 中处理字节到字符串的转换
   - 错误时回滚整个 chunk

### 关键算法

#### 最长后缀前缀匹配
用于确定 `pending` 缓冲区中需要保留多少字符，以防它们是下一个标签的前缀：

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

## 关键代码路径与文件引用

### 源码文件映射

| README 提及 | 实际文件路径 | 实现细节 |
|------------|-------------|---------|
| `StreamTextParser` | `src/stream_text.rs` | trait 定义 + `StreamTextChunk` |
| `InlineHiddenTagParser` | `src/inline_hidden_tag.rs` | 通用内联标签解析器 (323 行) |
| `CitationStreamParser` | `src/citation.rs` | `<oai-mem-citation>` 专用包装 (179 行) |
| `strip_citations` | `src/citation.rs:69-76` | 一次性字符串处理辅助函数 |
| `Utf8StreamParser` | `src/utf8_stream.rs` | 字节流适配器 (333 行) |

### 调用链示例

**Citation 解析调用链**:
```
codex-rs/core/src/stream_events_utils.rs:strip_citations()
    ↓
src/citation.rs:strip_citations()
    ↓
src/citation.rs:CitationStreamParser::push_str()
    ↓
src/inline_hidden_tag.rs:InlineHiddenTagParser::push_str()
```

**Plan 模式解析调用链**:
```
codex-rs/core/src/stream_events_utils.rs:strip_proposed_plan_blocks()
    ↓
src/proposed_plan.rs:strip_proposed_plan_blocks()
    ↓
src/proposed_plan.rs:ProposedPlanParser::push_str()
    ↓
src/tagged_line_parser.rs:TaggedLineParser::parse()
```

## 依赖与外部交互

### 内部模块依赖

```
lib.rs
├── stream_text.rs (基础 trait 和数据结构)
├── inline_hidden_tag.rs (依赖: stream_text)
├── citation.rs (依赖: inline_hidden_tag, stream_text)
├── tagged_line_parser.rs (行级解析器)
├── proposed_plan.rs (依赖: tagged_line_parser, stream_text)
├── assistant_text.rs (依赖: citation, proposed_plan, stream_text)
└── utf8_stream.rs (依赖: stream_text, citation[测试])
```

### 外部消费者

| 使用者 | 文件 | 使用场景 |
|--------|------|---------|
| `codex-core` | `src/stream_events_utils.rs:9,28` | 剥离模型输出中的引用标记 |
| `codex-core` | `src/stream_events_utils.rs:33-56` | 剥离 plan 模式下的 `<proposed_plan>` 块 |

### 使用模式

**非流式处理**（完整字符串）:
```rust
let (visible, citations) = strip_citations(text);
```

**流式处理**（SSE 流）:
```rust
let mut parser = CitationStreamParser::new();
for chunk in sse_stream {
    let result = parser.push_str(&chunk);
    render(&result.visible_text);
    process_citations(&result.extracted);
}
let tail = parser.finish();
```

## 风险、边界与改进建议

### 已知限制（文档中已声明）

1. **字面量匹配**: 标签匹配是字面量和大小写敏感的
2. **无嵌套支持**: 不支持嵌套标签（如 `<a><a>x</a></a>`）
3. **空对象**: 流可能返回空对象（需要调用方处理）

### 代码复杂性风险

README 明确警告：
> "This code is pretty complex and Codex did not manage to write it"

复杂点分析：
1. **状态机逻辑**: `InlineHiddenTagParser` 维护 `pending`、`active` 等多个状态
2. **边界条件**: 跨 chunk 的标签分割处理（如 `<oai-mem-` + `citation>`）
3. **回退机制**: 当标签不完整时的多种回退策略

### 边界条件

| 场景 | 行为 |
|------|------|
| 未闭合标签 | `finish()` 时自动闭合，返回已缓冲内容 |
| 部分标签前缀 | 保留在 pending，可能作为普通文本输出 |
| 重叠标签 | 不支持嵌套，第一个匹配的标签优先 |
| 空 chunk | 返回空 `StreamTextChunk` |
| 无效 UTF-8 | `Utf8StreamParser` 返回错误并回滚 |

### 改进建议

1. **文档完善**:
   - 添加更多边界条件的文档说明
   - 提供状态机图示
   - 解释 `longest_suffix_prefix_len` 算法的数学原理

2. **API 增强**:
   - 添加 `try_push_str` 返回 `Result` 的变体
   - 支持自定义标签匹配策略（正则表达式？）
   - 添加统计信息（处理的 chunk 数、提取的标签数）

3. **性能优化**:
   - 使用 `String::with_capacity` 预分配缓冲区
   - 考虑使用 `memchr` 进行快速字符串搜索
   - 评估 `smallvec` 减少小 `extracted` 的分配

4. **测试覆盖**:
   - 添加模糊测试（fuzzing）验证边界条件
   - 添加性能基准测试
   - 测试极端输入（超大 chunk、超长标签）

5. **安全加固**:
   - 限制 `pending` 缓冲区最大大小（防止内存耗尽攻击）
   - 验证标签内容长度限制
   - 添加 `#[must_use]` 到关键类型
