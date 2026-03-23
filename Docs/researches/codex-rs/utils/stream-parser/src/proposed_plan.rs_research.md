# proposed_plan.rs 研究文档

## 场景与职责

`proposed_plan.rs` 实现了 `ProposedPlanParser`，专门用于解析 `<proposed_plan>...</proposed_plan>` 标签块。这是 Codex 计划模式（plan mode）的核心组件，用于从助手输出中提取结构化的计划内容。

与 `CitationStreamParser` 不同，计划块：
1. 是多行块级结构
2. 标签必须独占一行
3. 需要保留计划内容的顺序和结构

## 功能点目的

### ProposedPlanSegment
- 表示计划解析结果的段类型
- 变体:
  - `Normal(String)`: 普通文本（标签外的内容）
  - `ProposedPlanStart`: 计划块开始标记
  - `ProposedPlanDelta(String)`: 计划块内的内容增量
  - `ProposedPlanEnd`: 计划块结束标记

### ProposedPlanParser
- 核心解析器，基于 `TaggedLineParser` 实现
- 实现 `StreamTextParser` trait
- 特点:
  - 流式处理，支持跨块边界
  - 保留计划内容的顺序
  - 自动关闭未关闭的计划块

### 辅助函数
- `strip_proposed_plan_blocks(text: &str) -> String`: 去除计划块，保留其他文本
- `extract_proposed_plan_text(text: &str) -> Option<String>`: 提取计划块内的纯文本

## 具体技术实现

### 标签常量

```rust
const OPEN_TAG: &str = "<proposed_plan>";
const CLOSE_TAG: &str = "</proposed_plan>";
```

### PlanTag 枚举

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum PlanTag {
    ProposedPlan,
}
```

### ProposedPlanSegment 枚举

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProposedPlanSegment {
    Normal(String),
    ProposedPlanStart,
    ProposedPlanDelta(String),
    ProposedPlanEnd,
}
```

### ProposedPlanParser 结构

```rust
#[derive(Debug)]
pub struct ProposedPlanParser {
    parser: TaggedLineParser<PlanTag>,
}
```

### StreamTextParser 实现

```rust
impl StreamTextParser for ProposedPlanParser {
    type Extracted = ProposedPlanSegment;

    fn push_str(&mut self, chunk: &str) -> StreamTextChunk<Self::Extracted> {
        map_segments(self.parser.parse(chunk))
    }

    fn finish(&mut self) -> StreamTextChunk<Self::Extracted> {
        map_segments(self.parser.finish())
    }
}
```

### 段映射函数

```rust
fn map_segments(segments: Vec<TaggedLineSegment<PlanTag>>) -> StreamTextChunk<ProposedPlanSegment> {
    let mut out = StreamTextChunk::default();
    for segment in segments {
        let mapped = match segment {
            TaggedLineSegment::Normal(text) => ProposedPlanSegment::Normal(text),
            TaggedLineSegment::TagStart(PlanTag::ProposedPlan) => {
                ProposedPlanSegment::ProposedPlanStart
            }
            TaggedLineSegment::TagDelta(PlanTag::ProposedPlan, text) => {
                ProposedPlanSegment::ProposedPlanDelta(text)
            }
            TaggedLineSegment::TagEnd(PlanTag::ProposedPlan) => {
                ProposedPlanSegment::ProposedPlanEnd
            }
        };
        // Normal 段同时放入 visible_text
        if let ProposedPlanSegment::Normal(text) = &mapped {
            out.visible_text.push_str(text);
        }
        out.extracted.push(mapped);
    }
    out
}
```

### 辅助函数实现

```rust
/// 去除计划块，保留其他文本
pub fn strip_proposed_plan_blocks(text: &str) -> String {
    let mut parser = ProposedPlanParser::new();
    let mut out = parser.push_str(text).visible_text;
    out.push_str(&parser.finish().visible_text);
    out
}

/// 提取计划块内的纯文本
pub fn extract_proposed_plan_text(text: &str) -> Option<String> {
    let mut parser = ProposedPlanParser::new();
    let mut plan_text = String::new();
    let mut saw_plan_block = false;
    
    for segment in parser
        .push_str(text)
        .extracted
        .into_iter()
        .chain(parser.finish().extracted)
    {
        match segment {
            ProposedPlanSegment::ProposedPlanStart => {
                saw_plan_block = true;
                plan_text.clear();  // 支持多个计划块时取最后一个
            }
            ProposedPlanSegment::ProposedPlanDelta(delta) => {
                plan_text.push_str(&delta);
            }
            ProposedPlanSegment::ProposedPlanEnd | ProposedPlanSegment::Normal(_) => {}
        }
    }
    saw_plan_block.then_some(plan_text)
}
```

## 关键代码路径与文件引用

- **文件路径**: `codex-rs/utils/stream-parser/src/proposed_plan.rs`
- **依赖**:
  - `tagged_line_parser.rs`: `TaggedLineParser`, `TagSpec`, `TaggedLineSegment`
  - `stream_text.rs`: `StreamTextChunk`, `StreamTextParser`
- **被依赖**:
  - `assistant_text.rs`: `AssistantTextStreamParser` 在 plan_mode 时使用
  - `lib.rs`: 导出 `ProposedPlanParser`, `ProposedPlanSegment` 等

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
    pub fn new(plan_mode: bool) -> Self {
        Self {
            plan_mode,
            ..Self::default()
        }
    }

    fn parse_visible_text(&mut self, visible_text: String) -> AssistantTextChunk {
        if !self.plan_mode {
            return AssistantTextChunk {
                visible_text,
                ..AssistantTextChunk::default()
            };
        }
        let plan_chunk: StreamTextChunk<ProposedPlanSegment> = self.plan.push_str(&visible_text);
        AssistantTextChunk {
            visible_text: plan_chunk.visible_text,
            plan_segments: plan_chunk.extracted,
            ..AssistantTextChunk::default()
        }
    }
}
```

### 使用示例

```rust
use codex_utils_stream_parser::{ProposedPlanParser, ProposedPlanSegment, StreamTextParser};

let mut parser = ProposedPlanParser::new();

// 流式处理
let out1 = parser.push_str("Intro text\n<prop");
let out2 = parser.push_str("osed_plan>\n- step 1\n");
let out3 = parser.push_str("</proposed_plan>\nOutro");
let finish = parser.finish();

// 结果检查
assert_eq!(out1.visible_text, "Intro text\n");
assert_eq!(out2.plan_segments, vec![
    ProposedPlanSegment::ProposedPlanStart,
    ProposedPlanSegment::ProposedPlanDelta("- step 1\n".to_string()),
]);
assert_eq!(out3.visible_text, "Outro");

// 辅助函数
let text = "before\n<proposed_plan>\n- step\n</proposed_plan>\nafter";
assert_eq!(strip_proposed_plan_blocks(text), "before\nafter");
assert_eq!(extract_proposed_plan_text(text), Some("- step\n".to_string()));
```

## 风险、边界与改进建议

### 边界情况处理

| 场景 | 行为 |
|------|------|
| 跨块边界 | `<prop` + `osed_plan>` 正确处理 |
| 未关闭标签 | EOF 时自动关闭 |
| 带缩进的标签 | `  <proposed_plan>` 被视为普通文本 |
| 标签行有额外文本 | `<proposed_plan> extra` 被视为普通文本 |
| 多个计划块 | `extract_proposed_plan_text` 取最后一个 |

### 测试覆盖

| 测试 | 描述 |
|------|------|
| `streams_proposed_plan_segments_and_visible_text` | 流式段和可见文本 |
| `preserves_non_tag_lines` | 保留非标签行 |
| `closes_unterminated_plan_block_on_finish` | 未关闭块自动关闭 |
| `strips_proposed_plan_blocks_from_text` | 去除计划块 |
| `extracts_proposed_plan_text` | 提取计划文本 |

### 风险点

1. **标签独占行要求**: 与 HTML 不同，`<proposed_plan>` 必须独占一行
2. **多个计划块**: `extract_proposed_plan_text` 取最后一个，可能不符合预期
3. **内存使用**: 计划块内容累积在内存中

### 改进建议

1. **多计划块处理**: 当前 `extract_proposed_plan_text` 取最后一个，可考虑返回 `Vec<String>`
   ```rust
   pub fn extract_all_proposed_plan_texts(text: &str) -> Vec<String>
   ```

2. **结构化解析**: 当前返回纯文本，未来可能需要解析为结构化数据
   ```rust
   pub struct PlanStep {
       pub action: String,
       pub description: String,
   }
   ```

3. **错误恢复**: 当前遇到格式错误静默处理，可考虑添加错误报告

4. **性能优化**: 大计划块可能导致频繁重新分配，可考虑预分配

5. **嵌套计划块**: 当前不支持，如果需求变化需要重新设计
