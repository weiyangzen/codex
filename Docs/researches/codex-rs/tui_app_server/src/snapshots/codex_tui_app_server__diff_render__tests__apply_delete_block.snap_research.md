# Apply Delete Block Diff Rendering - Technical Research Document

## Snapshot File
`codex_tui_app_server__diff_render__tests__apply_delete_block.snap`

## Snapshot Content
```
"• Deleted tmp_delete_example.txt (+0 -3)                                        "
"    1 -first                                                                    "
"    2 -second                                                                   "
"    3 -third                                                                    "
```

---

## 1. 场景与职责 (Scenario & Responsibilities)

### 1.1 功能场景
此快照测试验证 **删除文件（Delete）操作的差异渲染效果**。当 Codex 删除文件时，系统需要以清晰的格式展示被删除的文件内容，标识这是删除操作。

### 1.2 业务职责
- **删除操作标识**: 清晰标识文件被删除（Deleted）
- **内容展示**: 展示被删除文件的完整内容（用于确认）
- **行号显示**: 为删除内容添加行号
- **统计信息**: 显示删除行数（+0 -N）

### 1.3 使用场景
1. 用户请求 Codex 删除文件
2. Codex 标记文件为删除状态
3. UI 展示删除文件的差异视图
4. 用户确认后应用更改

---

## 2. 功能点目的 (Feature Purpose)

### 2.1 核心功能
| 元素 | 内容 | 目的 |
|------|------|------|
| 操作类型 | "Deleted" | 标识这是删除文件操作 |
| 文件名 | `tmp_delete_example.txt` | 显示被删除的文件名 |
| 统计 | `(+0 -3)` | 显示新增 0 行，删除 3 行 |
| 行号 | `1`, `2`, `3` | 原文件的行号 |
| 内容 | `first`, `second`, `third` | 被删除的文件内容 |

### 2.2 与 Add/Update 的区别
| 操作 | Header | 行前缀 | 颜色 |
|------|--------|--------|------|
| Add | "Added" | `+` | 绿色 |
| Update | "Edited" | `+`, `-`, ` ` | 绿/红/默认 |
| Delete | "Deleted" | `-` | 红色 |

### 2.3 视觉设计
- **红色主题**: 删除操作使用红色调（与 Git 一致）
- **暗淡效果**: 删除的内容可以使用 DIM 修饰符，表示已不存在
- **确认提示**: 删除操作通常需要用户额外确认

---

## 3. 具体技术实现 (Technical Implementation)

### 3.1 数据结构
```rust
// protocol/src/protocol.rs
pub enum FileChange {
    Add { content: String },
    Delete { content: String },  // 本测试场景
    Update { unified_diff: String, move_path: Option<PathBuf> },
}
```

### 3.2 渲染流程
```rust
// diff_render.rs:474-736
fn render_change(
    change: &FileChange,
    lines: &mut Vec<Line>,
    wrap_cols: usize,
    lang: Option<&str>,
) {
    match change {
        FileChange::Delete { content } => {
            render_delete_content(content, lines, wrap_cols, lang);
        }
        // ...
    }
}
```

### 3.3 Delete 内容渲染
```rust
// diff_render.rs:551-600
fn render_delete_content(
    content: &str,
    lines: &mut Vec<Line>,
    wrap_cols: usize,
    lang: Option<&str>,
) {
    let content_lines: Vec<&str> = content.lines().collect();
    let line_count = content_lines.len();
    
    let gutter_width = line_number_width(line_count);
    let syntax_lines = lang.and_then(|l| highlight_code_to_styled_spans(content, l));
    
    for (i, line) in content_lines.iter().enumerate() {
        let line_num = i + 1;
        
        // 构建行：行号 + -符号 + 内容
        let mut spans = vec![
            Span::styled(
                format!("{:>width$}", line_num, width = gutter_width),
                style_gutter_for(DiffLineType::Delete),
            ),
            Span::styled(" -", style_del()),
        ];
        
        // 添加内容（带语法高亮或纯文本）
        if let Some(ref syntax) = syntax_lines {
            spans.extend(syntax[i].clone());
        } else {
            spans.push(Span::from(**line));
        }
        
        lines.push(Line::from(spans));
    }
}
```

### 3.4 测试实现
```rust
// diff_render.rs:1492-1512
#[test]
fn ui_snapshot_apply_delete_block() {
    let mut changes: HashMap<PathBuf, FileChange> = HashMap::new();
    
    changes.insert(
        PathBuf::from("tmp_delete_example.txt"),
        FileChange::Delete {
            content: "first\nsecond\nthird\n".to_string(),
        },
    );
    
    let lines = diff_summary_for_tests(&changes);
    snapshot_lines("apply_delete_block", lines, 80, 10);
}
```

---

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 4.1 主要文件
| 文件路径 | 职责 |
|---------|------|
| `tui_app_server/src/diff_render.rs` | Diff 渲染主逻辑 |
| `protocol/src/protocol.rs` | FileChange 枚举定义 |

### 4.2 样式应用
```rust
// 删除行样式（红色）
fn style_del() -> Style {
    Style::default().fg(Color::Red)
}

// 行号列样式（删除）
fn style_gutter_for(kind: DiffLineType) -> Style {
    match kind {
        DiffLineType::Delete => Style::default().fg(Color::Red).dim(),
        // ...
    }
}
```

---

## 5. 依赖与外部交互 (Dependencies & External Interactions)

### 5.1 外部依赖
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染 |

---

## 6. 风险、边界与改进建议 (Risks, Edge Cases & Improvements)

### 6.1 已知风险
| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| 误删除 | 用户可能误删重要文件 | 需要额外确认，支持撤销 |
| 大文件 | 删除大文件时显示过多内容 | 限制显示行数 |

### 6.2 边界情况
1. **空文件删除**: 显示 "Deleted filename (+0 -0)"
2. **已不存在文件**: 协议层应处理此情况

### 6.3 改进建议
1. **删除确认**: 添加 "Are you sure?" 提示
2. **回收站**: 支持移动到回收站而非永久删除
3. **删除原因**: 允许添加删除原因说明

### 6.4 相关测试
- `apply_add_block`: 新增操作测试
- `apply_update_block`: 更新操作测试

---

## 7. 相关文档链接

- [Apply Add Block](../codex_tui_app_server__diff_render__tests__apply_add_block.snap_research.md) - 新增操作文档
