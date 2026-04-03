# Apply Update Block Wraps Long Lines Text - Technical Research Document

## Snapshot File
`codex_tui_app_server__diff_render__tests__apply_update_block_wraps_long_lines_text.snap`

## Snapshot Content
```
• Edited wrap_demo.txt (+2 -2)
    1  1
    2 -2
    2 +added long line which
        wraps and_if_there_i
       s_a_long_token_it_wil
       l_be_broken
    3  3
    4 -4
    4 +4 context line which
       also wraps across
```

---

## 1. 场景与职责 (Scenario & Responsibilities)

### 1.2 功能场景
此快照测试验证 **更新操作中长行换行的纯文本渲染效果**。与 `apply_update_block_wraps_long_lines` 不同，此测试使用纯文本快照（而非终端缓冲区快照），更易于阅读差异。

### 1.2 业务职责
- **纯文本验证**: 使用文本格式验证换行逻辑
- **可读性**: 纯文本快照更易于代码审查
- **多行变更**: 测试多个长行同时换行的场景

### 1.3 与缓冲区快照的区别
| 类型 | 格式 | 用途 |
|------|------|------|
| 缓冲区快照 | `"content "` | 验证精确渲染，包括空格填充 |
| 文本快照 | `content` | 验证内容逻辑，更易阅读 |

---

## 2. 功能点目的 (Feature Purpose)

### 2.1 核心功能
测试多种换行场景：
1. **短行**: 正常显示，不换行
2. **删除短行**: 正常显示
3. **新增长行**: 多行换行显示
4. **上下文长行**: 也正确换行

### 2.2 测试内容解析
```
    2 +added long line which
        wraps and_if_there_i
       s_a_long_token_it_wil
       l_be_broken
```

- 首行：行号 `2` + 符号 `+` + 内容开始
- 续行：缩进对齐，注意第二行有额外缩进（可能是由于 `and_if_there_i` 前的空格）

---

## 3. 具体技术实现 (Technical Implementation)

### 3.1 纯文本快照生成
```rust
// diff_render.rs:1387-1402
fn snapshot_lines_text(name: &str, lines: &[Line]) {
    let text: String = lines
        .iter()
        .map(|line| {
            line.spans
                .iter()
                .map(|span| span.content.as_ref())
                .collect::<String>()
        })
        .collect::<Vec<_>>()
        .join("\n");
    
    insta::assert_snapshot!(name, text);
}
```

### 3.2 测试实现
```rust
// diff_render.rs:1699-1727
#[test]
fn ui_snapshot_apply_update_block_wraps_long_lines_text() {
    let original = "1\n2\n3\n4\n";
    let modified = "1\nadded long line which wraps and_if_there_is_a_long_token_it_will_be_broken\n3\n4 context line which also wraps across\n";
    let patch = diffy::create_patch(original, modified).to_string();
    
    let mut changes: HashMap<PathBuf, FileChange> = HashMap::new();
    changes.insert(
        PathBuf::from("wrap_demo.txt"),
        FileChange::Update {
            unified_diff: patch,
            move_path: None,
        },
    );
    
    let lines = create_diff_summary(&changes, &PathBuf::from("/"), 30);  // 窄宽度强制换行
    snapshot_lines_text("apply_update_block_wraps_long_lines_text", &lines);
}
```

---

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 4.1 主要文件
| 文件路径 | 职责 |
|---------|------|
| `tui_app_server/src/diff_render.rs` | Diff 渲染和测试辅助函数 |

### 4.2 辅助函数
| 函数 | 位置 | 职责 |
|------|------|------|
| `snapshot_lines_text` | line 1387-1402 | 生成纯文本快照 |
| `create_diff_summary` | line 345-352 | 创建差异汇总 |

---

## 5. 依赖与外部交互 (Dependencies & External Interactions)

### 5.1 外部依赖
| Crate | 用途 |
|-------|------|
| `insta` | 快照测试框架 |

---

## 6. 风险、边界与改进建议 (Risks, Edge Cases & Improvements)

### 6.1 与缓冲区快照的互补
两种快照类型互补：
- **文本快照**: 验证内容逻辑，易于审查
- **缓冲区快照**: 验证精确渲染，包括样式和空格

### 6.2 改进建议
1. **统一测试**: 考虑使用宏同时生成两种快照
2. **差异对比**: 自动化比较两种快照的一致性

---

## 7. 相关文档链接

- [Apply Update Block Wraps Long Lines](../codex_tui_app_server__diff_render__tests__apply_update_block_wraps_long_lines.snap_research.md)
