# citations_tests.rs - 研究文档

## 场景与职责

`citations_tests.rs` 是 `citations.rs` 模块的单元测试文件，负责验证记忆引用解析功能的正确性。

### 测试覆盖范围

1. **Thread ID 提取**: 验证从引用中提取 ThreadId 的功能
2. **遗留格式支持**: 验证对旧版 `rollout_ids` 格式的向后兼容
3. **完整引用解析**: 验证引用条目和 rollout IDs 的联合解析

## 功能点目的

### 测试用例设计

| 测试函数 | 目的 |
|----------|------|
| `get_thread_id_from_citations_extracts_thread_ids` | 验证从新格式（`thread_ids`）提取 ThreadId |
| `get_thread_id_from_citations_supports_legacy_rollout_ids` | 验证遗留格式（`rollout_ids`）支持 |
| `parse_memory_citation_extracts_entries_and_rollout_ids` | 验证完整引用结构解析 |

## 具体技术实现

### 测试 1: Thread ID 提取

```rust
#[test]
fn get_thread_id_from_citations_extracts_thread_ids() {
    let first = ThreadId::new();
    let second = ThreadId::new();

    let citations = vec![format!(
        "<memory_citation>\n<citation_entries>\nMEMORY.md:1-2|note=[x]\n</citation_entries>\n<thread_ids>\n{first}\nnot-a-uuid\n{second}\n</thread_ids>\n</memory_citation>"
    )];

    assert_eq!(get_thread_id_from_citations(citations), vec![first, second]);
}
```

**验证点**:
- 有效 UUID 被正确解析为 ThreadId
- 无效 UUID（`not-a-uuid`）被跳过
- 返回顺序与输入顺序一致

### 测试 2: 遗留格式支持

```rust
#[test]
fn get_thread_id_from_citations_supports_legacy_rollout_ids() {
    let thread_id = ThreadId::new();

    let citations = vec![format!(
        "<memory_citation>\n<rollout_ids>\n{thread_id}\n</rollout_ids>\n</memory_citation>"
    )];

    assert_eq!(get_thread_id_from_citations(citations), vec![thread_id]);
}
```

**验证点**:
- 旧版 `<rollout_ids>` 标签被正确识别
- 与新版 `<thread_ids>` 功能等效

### 测试 3: 完整引用解析

```rust
#[test]
fn parse_memory_citation_extracts_entries_and_rollout_ids() {
    let first = ThreadId::new();
    let second = ThreadId::new();
    let citations = vec![format!(
        "<citation_entries>\nMEMORY.md:1-2|note=[summary]\nrollout_summaries/foo.md:10-12|note=[details]\n</citation_entries>\n<rollout_ids>\n{first}\n{second}\n{first}\n</rollout_ids>"
    )];

    let parsed = parse_memory_citation(citations).expect("memory citation should parse");

    // 验证条目
    assert_eq!(
        parsed.entries.iter().map(|entry| (
            entry.path.clone(),
            entry.line_start,
            entry.line_end,
            entry.note.clone(),
        )).collect::<Vec<_>>(),
        vec![
            ("MEMORY.md".to_string(), 1, 2, "summary".to_string()),
            ("rollout_summaries/foo.md".to_string(), 10, 12, "details".to_string()),
        ]
    );
    
    // 验证 ID 去重
    assert_eq!(
        parsed.rollout_ids,
        vec![first.to_string(), second.to_string()]
    );
}
```

**验证点**:
- 多个引用条目被正确解析
- 路径、行号、注释分离正确
- 重复 ID 被去重

## 关键代码路径与文件引用

### 测试结构

```
citations_tests.rs
├── 导入被测函数
├── 测试 1: get_thread_id_from_citations_extracts_thread_ids (行 7-16)
├── 测试 2: get_thread_id_from_citations_supports_legacy_rollout_ids (行 18-27)
└── 测试 3: parse_memory_citation_extracts_entries_and_rollout_ids (行 29-64)
```

### 依赖

| 依赖 | 用途 |
|------|------|
| `super::*` | 被测函数 |
| `codex_protocol::ThreadId` | 测试数据生成 |
| `pretty_assertions::assert_eq` | 清晰的测试失败输出 |

## 依赖与外部交互

### 测试框架

- 使用标准 Rust 测试框架 (`#[test]`)
- 使用 `pretty_assertions` 提供清晰的 diff 输出

### 测试数据生成

- 使用 `ThreadId::new()` 生成有效的 UUID
- 使用字符串格式化构建测试输入

## 风险、边界与改进建议

### 当前覆盖缺口

1. **错误处理**:
   - 没有测试无效格式输入的处理
   - 没有测试空输入的处理

2. **边界条件**:
   - 没有测试空行处理
   - 没有测试超大输入
   - 没有测试特殊字符

3. **行号解析**:
   - 没有测试无效行号格式
   - 没有测试负数行号

### 改进建议

1. **添加负面测试**:
```rust
#[test]
fn parse_memory_citation_returns_none_for_invalid_format() {
    let citations = vec!["invalid format".to_string()];
    assert!(parse_memory_citation(citations).is_none());
}
```

2. **添加边界测试**:
```rust
#[test]
fn parse_memory_citation_handles_empty_lines() {
    let citations = vec!["<citation_entries>\n\nMEMORY.md:1-2|note=[x]\n\n</citation_entries>".to_string()];
    let parsed = parse_memory_citation(citations);
    assert_eq!(parsed.unwrap().entries.len(), 1);
}
```

3. **添加性能测试**:
   - 测试大引用列表的解析性能

4. **添加模糊测试**:
   - 使用 `proptest` 或类似工具生成随机输入
