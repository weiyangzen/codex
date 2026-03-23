# assistant_text.rs 研究文档

## 场景与职责

`assistant_text.rs` 实现了 `AssistantTextStreamParser`，这是一个**组合解析器**，协调 `CitationStreamParser` 和 `ProposedPlanParser` 两个子解析器，提供统一的助手消息流处理接口。

这是 Codex 核心（`codex-core`）直接使用的解析器，用于处理：
1. `<oai-mem-citation>` 引用标签（始终处理）
2. `<proposed_plan>` 计划块（仅在 plan_mode 时处理）

## 功能点目的

### AssistantTextChunk
- 组合解析结果结构
- 字段:
  - `visible_text: String`: 可渲染的可见文本
  - `citations: Vec<String>`: 提取的引用列表
  - `plan_segments: Vec<ProposedPlanSegment>`: 计划段列表（plan_mode 时）

### AssistantTextStreamParser
- 组合解析器
- 特点:
  - 先处理引用，再处理计划块（两级管道）
  - plan_mode 可配置
  - 保持跨块状态

## 具体技术实现

### AssistantTextChunk 结构

```rust
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct AssistantTextChunk {
    pub visible_text: String,
    pub citations: Vec<String>,
    pub plan_segments: Vec<ProposedPlanSegment>,
}

impl AssistantTextChunk {
    pub fn is_empty(&self) -> bool {
        self.visible_text.is_empty() && self.citations.is_empty() && self.plan_segments.is_empty()
    }
}
```

### AssistantTextStreamParser 结构

```rust
#[derive(Debug, Default)]
pub struct AssistantTextStreamParser {
    plan_mode: bool,
    citations: CitationStreamParser,
    plan: ProposedPlanParser,
}
```

### 构造函数

```rust
impl AssistantTextStreamParser {
    pub fn new(plan_mode: bool) -> Self {
        Self {
            plan_mode,
            ..Self::default()
        }
    }
}
```

### push_str 处理流程

```rust
pub fn push_str(&mut self, chunk: &str) -> AssistantTextChunk {
    // 第一步：处理引用标签
    let citation_chunk = self.citations.push_str(chunk);
    
    // 第二步：处理计划块（使用引用处理后的可见文本）
    let mut out = self.parse_visible_text(citation_chunk.visible_text);
    
    // 合并引用结果
    out.citations = citation_chunk.extracted;
    out
}
```

### parse_visible_text 处理

```rust
fn parse_visible_text(&mut self, visible_text: String) -> AssistantTextChunk {
    // 非 plan_mode，直接返回
    if !self.plan_mode {
        return AssistantTextChunk {
            visible_text,
            ..AssistantTextChunk::default()
        };
    }
    
    // plan_mode：进一步处理计划块
    let plan_chunk: StreamTextChunk<ProposedPlanSegment> = self.plan.push_str(&visible_text);
    AssistantTextChunk {
        visible_text: plan_chunk.visible_text,
        plan_segments: plan_chunk.extracted,
        ..AssistantTextChunk::default()
    }
}
```

### finish 处理

```rust
pub fn finish(&mut self) -> AssistantTextChunk {
    // 完成引用解析
    let citation_chunk = self.citations.finish();
    
    // 处理剩余的可见文本
    let mut out = self.parse_visible_text(citation_chunk.visible_text);
    
    // plan_mode：完成计划解析
    if self.plan_mode {
        let mut tail = self.plan.finish();
        if !tail.is_empty() {
            out.visible_text.push_str(&tail.visible_text);
            out.plan_segments.append(&mut tail.extracted);
        }
    }
    
    out.citations = citation_chunk.extracted;
    out
}
```

## 关键代码路径与文件引用

- **文件路径**: `codex-rs/utils/stream-parser/src/assistant_text.rs`
- **依赖**:
  - `citation.rs`: `CitationStreamParser`
  - `proposed_plan.rs`: `ProposedPlanParser`, `ProposedPlanSegment`
  - `stream_text.rs`: `StreamTextChunk`, `StreamTextParser`
- **被依赖**:
  - `codex-rs/core/src/codex.rs`: 主要使用者
  - `lib.rs`: 导出 `AssistantTextChunk`, `AssistantTextStreamParser`

## 依赖与外部交互

### 在 codex-core 中的使用

```rust
// codex-rs/core/src/codex.rs
use codex_utils_stream_parser::AssistantTextStreamParser;

#[derive(Debug, Default)]
struct AssistantMessageStreamParsers {
    plan_mode: bool,
    parsers_by_item: HashMap<String, AssistantTextStreamParser>,
}

type ParsedAssistantTextDelta = AssistantTextChunk;

impl AssistantMessageStreamParsers {
    fn new(plan_mode: bool) -> Self {
        Self {
            plan_mode,
            parsers_by_item: HashMap::new(),
        }
    }

    fn parser_mut(&mut self, item_id: &str) -> &mut AssistantTextStreamParser {
        let plan_mode = self.plan_mode;
        self.parsers_by_item
            .entry(item_id.to_string())
            .or_insert_with(|| AssistantTextStreamParser::new(plan_mode))
    }

    fn seed_item_text(&mut self, item_id: &str, text: &str) -> ParsedAssistantTextDelta {
        if text.is_empty() {
            return ParsedAssistantTextChunk::default();
        }
        self.parser_mut(item_id).push_str(text)
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

    fn drain_finished(&mut self) -> Vec<(String, ParsedAssistantTextDelta)> {
        let parsers_by_item = std::mem::take(&mut self.parsers_by_item);
        parsers_by_item
            .into_iter()
            .map(|(item_id, mut parser)| (item_id, parser.finish()))
            .collect()
    }
}
```

### 处理流程

```
输入 chunk
    ↓
CitationStreamParser (始终)
    ↓ 输出 visible_text (已去除引用标签)
    ↓
ProposedPlanParser (仅 plan_mode)
    ↓ 输出最终 visible_text 和 plan_segments
    ↓
AssistantTextChunk {
    visible_text,
    citations,      // 来自 CitationStreamParser
    plan_segments,  // 来自 ProposedPlanParser
}
```

## 风险、边界与改进建议

### 边界情况处理

| 场景 | 行为 |
|------|------|
| 引用跨块 | 由 `CitationStreamParser` 处理 |
| 计划块跨块 | 由 `ProposedPlanParser` 处理 |
| 引用在计划块内 | 先去除引用，再处理计划块 |
| plan_mode 切换 | 每个 `AssistantTextStreamParser` 实例固定 |

### 测试覆盖

| 测试 | 描述 |
|------|------|
| `parses_citations_across_seed_and_delta_boundaries` | 跨种子和增量边界解析引用 |
| `parses_plan_segments_after_citation_stripping` | 引用去除后解析计划段 |

### 风险点

1. **处理顺序依赖**: 必须先处理引用再处理计划块，因为计划块可能包含引用
   ```
   <proposed_plan>
   - step <oai-mem-citation>doc</oai-mem-citation>
   </proposed_plan>
   ```

2. **状态管理**: 两个子解析器都有内部状态，需要同时正确管理

3. **plan_mode 不可变**: 创建后不能切换模式，需要新实例

4. **内存累积**: `plan_segments` 累积所有段，长会话可能占用大量内存

### 改进建议

1. **流式段处理**: 当前 `plan_segments` 累积所有段，可考虑回调式处理
   ```rust
   pub fn push_str_with_callback<F>(&mut self, chunk: &str, mut callback: F)
   where
       F: FnMut(ProposedPlanSegment),
   ```

2. **模式切换**: 支持运行时切换 plan_mode（如果需要）

3. **错误处理**: 当前依赖子解析器的错误处理，可考虑统一错误类型

4. **性能优化**: 减少中间 `String` 分配，使用 `Cow<str>`

5. **可观测性**: 添加调试日志，便于排查解析问题
   ```rust
   #[cfg(feature = "debug")]
   log::debug!("Citation parsed: {:?}", citation_chunk);
   ```

6. **测试覆盖**: 当前测试较少，建议添加：
   - 大规模数据测试
   - 并发测试（多 item_id）
   - 边界条件测试（空输入、极大输入）
