# lib.rs 研究文档

## 场景与职责

`lib.rs` 是 `codex-utils-stream-parser` crate 的模块入口和公共 API 导出文件。该 crate 是一个无依赖的流式文本解析工具库，专门用于处理 AI 助手输出流中的隐藏标记（如引用、计划块等）。这些标记可能跨越数据块边界到达，需要状态机式的解析器来正确处理。

## 功能点目的

该文件的核心目的是：
1. **模块组织**：声明所有子模块，形成清晰的代码结构
2. **API 导出**：通过 `pub use` 将内部实现暴露为公共接口
3. **抽象统一**：为不同类型的流式解析器提供统一的 `StreamTextParser` trait

## 具体技术实现

### 模块结构

```
stream-parser/
├── lib.rs              # 入口，导出公共 API
├── stream_text.rs      # 核心 trait 和结果结构
├── inline_hidden_tag.rs # 通用内联标签解析器
├── citation.rs         # 引用标签解析器（基于 inline_hidden_tag）
├── proposed_plan.rs    # 计划块解析器（基于 tagged_line_parser）
├── tagged_line_parser.rs # 行级标签解析器
├── assistant_text.rs   # 组合解析器（citation + proposed_plan）
└── utf8_stream.rs      # UTF-8 字节流适配器
```

### 公共 API 导出

| 导出项 | 来源模块 | 用途 |
|--------|----------|------|
| `AssistantTextChunk` | `assistant_text` | 助手文本解析结果 |
| `AssistantTextStreamParser` | `assistant_text` | 组合解析器（引用+计划） |
| `CitationStreamParser` | `citation` | 引用标签解析器 |
| `strip_citations` | `citation` | 一次性去除引用函数 |
| `ExtractedInlineTag` | `inline_hidden_tag` | 提取的内联标签结构 |
| `InlineHiddenTagParser` | `inline_hidden_tag` | 通用内联标签解析器 |
| `InlineTagSpec` | `inline_hidden_tag` | 标签规范结构 |
| `ProposedPlanParser` | `proposed_plan` | 计划块解析器 |
| `ProposedPlanSegment` | `proposed_plan` | 计划段枚举 |
| `extract_proposed_plan_text` | `proposed_plan` | 提取计划文本函数 |
| `strip_proposed_plan_blocks` | `proposed_plan` | 去除计划块函数 |
| `StreamTextChunk` | `stream_text` | 流文本块结构 |
| `StreamTextParser` | `stream_text` | 流解析器 trait |
| `Utf8StreamParser` | `utf8_stream` | UTF-8 字节流解析器 |
| `Utf8StreamParserError` | `utf8_stream` | UTF-8 解析错误 |

## 关键代码路径与文件引用

- **文件路径**: `codex-rs/utils/stream-parser/src/lib.rs`
- **Cargo.toml**: `codex-rs/utils/stream-parser/Cargo.toml`
- **README**: `codex-rs/utils/stream-parser/README.md`
- **BUILD.bazel**: `codex-rs/utils/stream-parser/BUILD.bazel`

## 依赖与外部交互

### 内部依赖关系

```
lib.rs
├── stream_text.rs (基础 trait)
├── inline_hidden_tag.rs (通用解析器)
│   └── 依赖 stream_text.rs
├── citation.rs
│   └── 依赖 inline_hidden_tag.rs, stream_text.rs
├── tagged_line_parser.rs (行级解析器)
├── proposed_plan.rs
│   └── 依赖 tagged_line_parser.rs, stream_text.rs
├── assistant_text.rs (组合器)
│   └── 依赖 citation.rs, proposed_plan.rs, stream_text.rs
└── utf8_stream.rs (字节适配器)
    └── 依赖 stream_text.rs
```

### 外部使用者

- `codex-core` crate: 在 `codex.rs` 中使用 `AssistantTextStreamParser` 处理助手消息流
  - 文件: `codex-rs/core/src/codex.rs` (行 120, 6494, 6507, 6511)
  - 用于解析 `<oai-mem-citation>` 引用标签和 `<proposed_plan>` 计划块

## 风险、边界与改进建议

### 已知限制（来自 README）
1. 标签是字面量匹配，区分大小写
2. 不支持嵌套标签
3. 流可能返回空对象

### 风险点
1. **复杂性**: README 明确警告代码复杂，修改前需深入理解
2. **跨块边界**: 标签可能被分割在多个数据块中，状态管理必须正确
3. **UTF-8 处理**: 多字节字符可能跨块分割，需要 `Utf8StreamParser` 缓冲

### 改进建议
1. 考虑添加更多文档示例，特别是错误处理场景
2. 考虑支持大小写不敏感匹配（可选配置）
3. 考虑添加性能基准测试，确保流式处理效率
