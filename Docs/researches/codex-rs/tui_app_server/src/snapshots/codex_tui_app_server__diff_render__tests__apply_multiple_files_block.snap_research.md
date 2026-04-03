# Apply Multiple Files Block Diff Rendering - Technical Research Document

## Snapshot File
`codex_tui_app_server__diff_render__tests__apply_multiple_files_block.snap`

## Snapshot Content
```
"• Edited 2 files (+2 -1)                                                        "
"  └ a.txt (+1 -1)                                                               "
"    1 -one                                                                      "
"    1 +one changed                                                              "
"                                                                                "
"  └ b.txt (+1 -0)                                                               "
"    1 +new                                                                      "
```

---

## 1. 场景与职责 (Scenario & Responsibilities)

### 1.1 功能场景
此快照测试验证 **多文件变更的差异渲染效果**。当 Codex 同时修改多个文件时，系统需要以层次结构展示所有变更，并提供汇总统计。

### 1.2 业务职责
- **汇总统计**: 显示总文件数和总变更行数
- **层次展示**: 使用树形结构展示每个文件的变更
- **文件隔离**: 清晰区分不同文件的变更内容
- **统计细分**: 每个文件显示自己的变更统计

### 1.3 使用场景
1. 用户请求进行跨文件的重构操作
2. Codex 生成多个文件的变更
3. UI 以层次结构展示所有变更
4. 用户可以逐个文件确认或全部接受

---

## 2. 功能点目的 (Feature Purpose)

### 2.1 核心功能
| 元素 | 内容 | 目的 |
|------|------|------|
| 汇总头部 | "Edited 2 files (+2 -1)" | 显示总文件数和总变更 |
| 文件条目 | "└ a.txt (+1 -1)" | 树形标记 + 文件名 + 统计 |
| 文件内容 | 差异行 | 每个文件的详细变更 |
| 分隔空行 | 空行 | 区分不同文件的内容 |

### 2.2 树形结构
```
• Edited 2 files (+2 -1)           <- 汇总头部
  └ a.txt (+1 -1)                  <- 文件 1
    1 -one                         <- 文件 1 内容
    1 +one changed
                                   <- 空行分隔
  └ b.txt (+1 -0)                  <- 文件 2
    1 +new                         <- 文件 2 内容
```

### 2.3 与单文件的区别
| 场景 | Header 格式 | 缩进 |
|------|-------------|------|
| 单文件 | "Edited filename (+N -M)" | 无树形标记 |
| 多文件 | "Edited N files (+N -M)" | 使用 └ 树形标记 |

---

## 3. 具体技术实现 (Technical Implementation)

### 3.1 数据结构
```rust
// diff_render.rs:354-363
struct Row {
    path: PathBuf,
    change: FileChange,
    move_path: Option<PathBuf>,
}
```

### 3.2 多文件渲染流程
```rust
// diff_render.rs:402-464
fn render_changes_block(
    rows: Vec<Row>,
    wrap_cols: usize,
    cwd: &Path,
) -> Vec<Line> {
    let mut lines = vec![];
    
    // 计算总统计
    let total_adds: usize = rows.iter().map(|r| r.change.add_count()).sum();
    let total_dels: usize = rows.iter().map(|r| r.change.del_count()).sum();
    
    // 渲染汇总头部
    if rows.len() == 1 {
        // 单文件：显示文件名
        lines.push(render_single_file_header(&rows[0], total_adds, total_dels));
    } else {
        // 多文件：显示文件数量
        lines.push(render_multi_file_header(rows.len(), total_adds, total_dels));
    }
    
    // 渲染每个文件
    for (i, row) in rows.iter().enumerate() {
        let is_last = i == rows.len() - 1;
        render_file_change(row, &mut lines, wrap_cols, cwd, is_last);
    }
    
    lines
}
```

### 3.3 文件变更渲染
```rust
fn render_file_change(
    row: &Row,
    lines: &mut Vec<Line>,
    wrap_cols: usize,
    cwd: &Path,
    is_last: bool,
) {
    // 渲染文件头部（带树形标记）
    let tree_prefix = if is_last { "  └ " } else { "  ├ " };
    let file_header = format!(
        "{}{} (+{} -{})",
        tree_prefix,
        display_path_for(&row.path, cwd),
        row.change.add_count(),
        row.change.del_count(),
    );
    lines.push(Line::from(file_header));
    
    // 渲染文件内容（额外缩进）
    let content_indent = if is_last { "    " } else { "  │ " };
    render_change_with_indent(&row.change, lines, wrap_cols, content_indent);
    
    // 添加空行分隔（如果不是最后一个文件）
    if !is_last {
        lines.push(Line::from(""));
    }
}
```

### 3.4 测试实现
```rust
// diff_render.rs:1514-1545
#[test]
fn ui_snapshot_apply_multiple_files_block() {
    let mut changes: HashMap<PathBuf, FileChange> = HashMap::new();
    
    // 文件 1：Update 操作
    let patch1 = diffy::create_patch("one\n", "one changed\n").to_string();
    changes.insert(
        PathBuf::from("a.txt"),
        FileChange::Update {
            unified_diff: patch1,
            move_path: None,
        },
    );
    
    // 文件 2：Add 操作
    changes.insert(
        PathBuf::from("b.txt"),
        FileChange::Add {
            content: "new\n".to_string(),
        },
    );
    
    let lines = diff_summary_for_tests(&changes);
    snapshot_lines("apply_multiple_files_block", lines, 80, 10);
}
```

---

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 4.1 主要文件
| 文件路径 | 职责 |
|---------|------|
| `tui_app_server/src/diff_render.rs` | Diff 渲染主逻辑 |

### 4.2 调用链
```
create_diff_summary
  └── render_changes_block
        ├── 计算总统计
        ├── 渲染汇总头部
        └── 遍历 render_file_change
              ├── 渲染文件头部（树形标记）
              └── 渲染文件内容（带缩进）
```

---

## 5. 依赖与外部交互 (Dependencies & External Interactions)

### 5.1 外部依赖
| Crate | 用途 |
|-------|------|
| `diffy` | Diff 生成 |
| `ratatui` | TUI 渲染 |

---

## 6. 风险、边界与改进建议 (Risks, Edge Cases & Improvements)

### 6.1 已知风险
| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| 文件过多 | 大量文件导致显示过长 | 添加折叠功能 |
| 树形对齐 | 不同深度的文件对齐问题 | 统一缩进宽度 |

### 6.2 边界情况
1. **空变更列表**: 不应调用此函数
2. **混合操作类型**: Add/Delete/Update 混合显示
3. **文件重命名**: 显示旧名 → 新名

### 6.3 改进建议
1. **文件折叠**: 允许折叠/展开单个文件
2. **文件过滤**: 按操作类型过滤显示
3. **批量操作**: 支持批量接受/拒绝
4. **文件排序**: 按路径或变更大小排序

### 6.4 相关测试
- `apply_add_block`: 单文件 Add 测试
- `apply_update_block`: 单文件 Update 测试
- `diff_gallery_*`: 多文件综合测试

---

## 7. 相关文档链接

- [Apply Add Block](../codex_tui_app_server__diff_render__tests__apply_add_block.snap_research.md)
- [Apply Update Block](../codex_tui_app_server__diff_render__tests__apply_update_block.snap_research.md)
