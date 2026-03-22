# citations.rs - 研究文档

## 场景与职责

`citations.rs` 模块负责解析和处理记忆引用（memory citations），这是 Codex 记忆系统中的一个关键组件，用于追踪和引用记忆来源。

### 核心职责

1. **引用解析**: 从模型输出中解析结构化的记忆引用块
2. **Thread ID 提取**: 从引用中提取相关的 thread/rollout IDs
3. **引用条目解析**: 解析文件路径、行号范围和注释信息

### 使用场景

当模型使用记忆工具读取记忆文件时，它需要在响应中包含引用信息，以便：
- 追踪哪些记忆被实际使用
- 更新记忆使用统计（`usage_count`、`last_usage`）
- 支持记忆来源的可追溯性

## 功能点目的

### 1. `parse_memory_citation`

**目的**: 从字符串向量中解析完整的记忆引用结构

**输入**: `Vec<String>` - 可能包含引用块的字符串（通常是模型输出）

**输出**: `Option<MemoryCitation>` - 解析后的引用结构或 None

**解析的块类型**:
- `<citation_entries>...</citation_entries>`: 详细的引用条目
- `<rollout_ids>...</rollout_ids>`: Rollout ID 列表（新格式）
- `<thread_ids>...</thread_ids>`: Thread ID 列表（遗留格式）

### 2. `get_thread_id_from_citations`

**目的**: 从引用中提取 ThreadId 列表

**用途**: 用于更新记忆使用统计（`record_stage1_output_usage`）

### 3. `parse_memory_citation_entry`

**目的**: 解析单个引用条目

**格式**: `path:line_start-line_end|note=[comment]`

**示例**: `MEMORY.md:1-2|note=[summary]`

## 具体技术实现

### 数据结构

```rust
// 来自 codex_protocol::memory_citation
pub struct MemoryCitation {
    pub entries: Vec<MemoryCitationEntry>,
    pub rollout_ids: Vec<String>,
}

pub struct MemoryCitationEntry {
    pub path: String,
    pub line_start: i64,
    pub line_end: i64,
    pub note: String,
}
```

### 解析算法

```rust
pub fn parse_memory_citation(citations: Vec<String>) -> Option<MemoryCitation> {
    let mut entries = Vec::new();
    let mut rollout_ids = Vec::new();
    let mut seen_rollout_ids = HashSet::new();

    for citation in citations {
        // 1. 提取 citation_entries 块
        if let Some(entries_block) = extract_block(&citation, "<citation_entries>", "</citation_entries>") {
            entries.extend(entries_block.lines().filter_map(parse_memory_citation_entry));
        }

        // 2. 提取 rollout_ids 或 thread_ids 块（向后兼容）
        if let Some(ids_block) = extract_ids_block(&citation) {
            for id in ids_block.lines().map(str::trim).filter(|line| !line.is_empty()) {
                if seen_rollout_ids.insert(id.to_string()) {
                    rollout_ids.push(id.to_string());
                }
            }
        }
    }

    // 3. 如果没有任何内容，返回 None
    if entries.is_empty() && rollout_ids.is_empty() {
        None
    } else {
        Some(MemoryCitation { entries, rollout_ids })
    }
}
```

### 辅助函数

```rust
// 提取标记块内容
fn extract_block<'a>(text: &'a str, open: &str, close: &str) -> Option<&'a str> {
    let (_, rest) = text.split_once(open)?;
    let (body, _) = rest.split_once(close)?;
    Some(body)
}

// 提取 ID 块（支持新旧格式）
fn extract_ids_block(text: &str) -> Option<&str> {
    extract_block(text, "<rollout_ids>", "</rollout_ids>")
        .or_else(|| extract_block(text, "<thread_ids>", "</thread_ids>"))
}
```

## 关键代码路径与文件引用

### 主要函数

| 函数 | 行号 | 描述 |
|------|------|------|
| `parse_memory_citation` | 6-43 | 主解析函数 |
| `get_thread_id_from_citations` | 45-55 | ThreadId 提取 |
| `parse_memory_citation_entry` | 57-74 | 单个条目解析 |
| `extract_block` | 76-80 | 通用块提取 |
| `extract_ids_block` | 82-85 | ID 块提取（向后兼容） |

### 引用格式规范

**完整引用块示例**:
```xml
<oai-mem-citation>
<citation_entries>
MEMORY.md:1-2|note=[responsesapi citation extraction code pointer]
rollout_summaries/foo.md:10-12|note=[details]
</citation_entries>
<rollout_ids>
019c6e27-e55b-73d1-87d8-4e01f1f75043
019c7714-3b77-74d1-9866-e1f484aae2ab
</rollout_ids>
</oai-mem-citation>
```

**遗留格式（仍支持）**:
```xml
<memory_citation>
<thread_ids>
019c6e27-e55b-73d1-87d8-4e01f1f75043
</thread_ids>
</memory_citation>
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `codex_protocol::ThreadId` | Thread ID 类型 |
| `codex_protocol::memory_citation::*` | 引用数据结构 |
| `std::collections::HashSet` | 去重 |

### 调用方

| 模块 | 用途 |
|------|------|
| `memories::usage` | 记录记忆使用统计 |
| 模型输出处理 | 解析模型生成的引用 |

## 风险、边界与改进建议

### 已知风险

1. **格式严格性**:
   - 解析器对格式要求严格，任何格式偏差都会导致解析失败
   - 没有容错机制处理部分损坏的引用

2. **行号解析**:
   - 行号使用 `parse().ok()`，解析失败会静默返回 None
   - 可能导致有效条目被跳过

3. **路径处理**:
   - 路径作为纯字符串处理，没有验证或规范化
   - 可能包含相对路径或无效路径

### 边界条件

1. **空输入处理**:
   - 空字符串向量返回 `None`
   - 空块内容返回 `None`

2. **重复 ID 处理**:
   - 使用 `HashSet` 去重，保留首次出现的顺序

3. **格式变体**:
   - 支持 `rollout_ids` 和 `thread_ids` 两种标签（向后兼容）

### 改进建议

1. **错误处理**:
   - 添加结构化错误类型而非返回 `Option`
   - 提供详细的解析失败原因

2. **格式验证**:
   - 验证 ThreadId 格式（UUID）
   - 验证行号范围（`line_start <= line_end`）
   - 验证路径格式

3. **容错性**:
   - 跳过无效条目而非整个块
   - 添加警告日志记录解析问题

4. **性能优化**:
   - 对于大量引用，考虑使用迭代器而非收集到 Vec

5. **测试覆盖**:
   - 添加更多边界情况测试（空行、无效格式、超大输入等）
