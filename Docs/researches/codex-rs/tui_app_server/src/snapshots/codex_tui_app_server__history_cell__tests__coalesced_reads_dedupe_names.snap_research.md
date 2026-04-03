# Coalesced Reads Dedupe Names - Technical Research Document

## Snapshot File
`codex_tui_app_server__history_cell__tests__coalesced_reads_dedupe_names.snap`

## Snapshot Content
```
• Explored
  └ Read auth.rs, shimmer.rs
```

---

## 1. 场景与职责 (Scenario & Responsibilities)

### 1.1 功能场景
此快照测试验证 **文件读取合并时的去重功能**。当 Codex 多次读取相同文件时，UI 应该去重显示，避免重复列出同一文件。

### 1.2 业务职责
- **去重显示**: 相同文件只显示一次
- **合并展示**: 将多个读取操作合并为单个 "Explored" 条目
- **清晰可读**: 去重后的列表更加简洁

### 1.3 与不去重的区别
| 场景 | 显示 |
|------|------|
| 不去重 | `Read auth.rs\nRead auth.rs\nRead shimmer.rs` |
| 去重 | `Read auth.rs, shimmer.rs` |

---

## 2. 功能点目的 (Feature Purpose)

### 2.1 核心功能
- 检测重复的文件读取
- 合并显示唯一文件列表
- 保持文件读取的原始顺序

### 2.2 去重策略
```rust
// 输入: ["auth.rs", "auth.rs", "shimmer.rs", "auth.rs"]
// 输出: ["auth.rs", "shimmer.rs"]
// 保持首次出现的顺序
```

---

## 3. 具体技术实现 (Technical Implementation)

### 3.1 去重逻辑
```rust
fn dedupe_file_reads(reads: Vec<String>) -> Vec<String> {
    let mut seen = HashSet::new();
    reads
        .into_iter()
        .filter(|file| seen.insert(file.clone()))
        .collect()
}
```

### 3.2 测试实现
```rust
#[test]
fn coalesced_reads_dedupe_names() {
    let reads = vec![
        "auth.rs".to_string(),
        "auth.rs".to_string(),  // 重复
        "shimmer.rs".to_string(),
    ];
    
    let deduped = dedupe_file_reads(reads);
    assert_eq!(deduped, vec!["auth.rs", "shimmer.rs"]);
    
    // 渲染并快照
    let cell = FileReadCell::new(deduped);
    assert_snapshot!("coalesced_reads_dedupe_names", render_cell(&cell));
}
```

---

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 4.1 主要文件
| 文件路径 | 职责 |
|---------|------|
| `tui_app_server/src/history_cell.rs` | 文件读取单元格 |

---

## 5. 依赖与外部交互 (Dependencies & External Interactions)

### 5.1 标准库依赖
| 模块 | 用途 |
|------|------|
| `std::collections::HashSet` | 去重 |

---

## 6. 风险、边界与改进建议 (Risks, Edge Cases & Improvements)

### 6.1 边界情况
1. **空列表**: 不显示任何文件
2. **全部重复**: 只显示唯一文件
3. **大小写敏感**: `Auth.rs` 和 `auth.rs` 视为不同文件

### 6.2 改进建议
1. **大小写不敏感**: 在大小写不敏感的文件系统上去重
2. **路径规范化**: 解析相对路径和绝对路径的等价性

---

## 7. 相关文档链接

- [Coalesces Reads Across Multiple Calls](../codex_tui_app_server__history_cell__tests__coalesces_reads_across_multiple_calls.snap_research.md)
