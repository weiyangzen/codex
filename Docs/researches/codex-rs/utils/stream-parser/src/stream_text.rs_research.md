# stream_text.rs 研究文档

## 场景与职责

`stream_text.rs` 定义了 `codex-utils-stream-parser` crate 的核心抽象：`StreamTextParser` trait 和 `StreamTextChunk` 结构。这是整个库的基础，所有具体的流式解析器都基于这个统一的接口实现。

该设计解决了流式数据处理中的核心问题：当数据以分块方式到达时，如何：
1. 立即输出可安全渲染的可见文本
2. 同时提取隐藏的有效载荷（如引用、计划等）
3. 保持跨块的状态一致性

## 功能点目的

### StreamTextChunk<T>
- **目的**: 表示一次解析操作的结果
- **字段**:
  - `visible_text`: 可立即渲染的文本（已去除隐藏标签）
  - `extracted: Vec<T>`: 从输入中提取的隐藏有效载荷
- **方法**:
  - `is_empty()`: 检查是否无可见文本和提取内容

### StreamTextParser Trait
- **目的**: 定义流式解析器的统一接口
- **关联类型**: `Extracted` - 提取的有效载荷类型
- **方法**:
  - `push_str(&mut self, chunk: &str) -> StreamTextChunk<Self::Extracted>`: 处理新的文本块
  - `finish(&mut self) -> StreamTextChunk<Self::Extracted>`: 刷新缓冲区，结束解析

## 具体技术实现

### StreamTextChunk 结构

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StreamTextChunk<T> {
    /// Text safe to render immediately.
    pub visible_text: String,
    /// Hidden payloads extracted from the chunk.
    pub extracted: Vec<T>,
}
```

### Default 实现

```rust
impl<T> Default for StreamTextChunk<T> {
    fn default() -> Self {
        Self {
            visible_text: String::new(),
            extracted: Vec::new(),
        }
    }
}
```

### StreamTextParser Trait 定义

```rust
pub trait StreamTextParser {
    type Extracted;
    fn push_str(&mut self, chunk: &str) -> StreamTextChunk<Self::Extracted>;
    fn finish(&mut self) -> StreamTextChunk<Self::Extracted>;
}
```

## 关键代码路径与文件引用

- **文件路径**: `codex-rs/utils/stream-parser/src/stream_text.rs`
- **使用位置**:
  - `inline_hidden_tag.rs`: `impl StreamTextParser for InlineHiddenTagParser<T>`
  - `citation.rs`: 通过 `InlineHiddenTagParser` 间接实现
  - `proposed_plan.rs`: `impl StreamTextParser for ProposedPlanParser`
  - `assistant_text.rs`: 组合多个解析器
  - `utf8_stream.rs`: 包装任何 `StreamTextParser` 实现
  - `codex-rs/core/src/codex.rs`: 使用 `AssistantTextStreamParser`

## 依赖与外部交互

### 内部依赖
- 无直接依赖（基础定义文件）
- 被所有其他解析器模块依赖

### 外部使用模式

在 `codex.rs` 中的典型使用模式：

```rust
// 定义解析器集合
#[derive(Debug, Default)]
struct AssistantMessageStreamParsers {
    plan_mode: bool,
    parsers_by_item: HashMap<String, AssistantTextStreamParser>,
}

type ParsedAssistantTextDelta = AssistantTextChunk;

impl AssistantMessageStreamParsers {
    fn parser_mut(&mut self, item_id: &str) -> &mut AssistantTextStreamParser {
        let plan_mode = self.plan_mode;
        self.parsers_by_item
            .entry(item_id.to_string())
            .or_insert_with(|| AssistantTextStreamParser::new(plan_mode))
    }

    fn parse_delta(&mut self, item_id: &str, delta: &str) -> ParsedAssistantTextDelta {
        self.parser_mut(item_id).push_str(delta)
    }

    fn finish_item(&mut self, item_id: &str) -> ParsedAssistantTextDelta {
        let Some(mut parser) = self.parsers_by_item.remove(item_id) else {
            return ParsedAssistantTextDelta::default();
        };
        parser.finish()
    }
}
```

## 风险、边界与改进建议

### 设计优点
1. **统一接口**: 所有解析器遵循相同模式，易于组合
2. **零拷贝潜力**: 当前使用 `String`，未来可考虑 `Cow<str>` 优化
3. **类型安全**: 关联类型 `Extracted` 确保类型正确

### 边界情况
1. **空块处理**: `push_str("")` 应返回空结果
2. **多次 finish**: 实现应确保 `finish()` 后状态正确重置
3. **错误传播**: 当前 trait 不处理错误，由具体实现决定

### 改进建议
1. **生命周期优化**: 考虑使用 `&str` 而非 `String` 减少分配
   ```rust
   // 可能的优化
   pub struct StreamTextChunk<'a, T> {
       pub visible_text: Cow<'a, str>,
       pub extracted: Vec<T>,
   }
   ```

2. **错误处理**: 考虑添加错误类型到 trait
   ```rust
   type Error;
   fn push_str(&mut self, chunk: &str) -> Result<StreamTextChunk<Self::Extracted>, Self::Error>;
   ```

3. **异步支持**: 未来可能需要 `async fn` 支持背压

4. **组合器**: 添加标准组合器如 `map`, `and_then` 等
