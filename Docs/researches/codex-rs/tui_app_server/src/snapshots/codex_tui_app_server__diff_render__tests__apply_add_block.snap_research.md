# Apply Add Block Diff Rendering - Technical Research Document

## Snapshot File
`codex_tui_app_server__diff_render__tests__apply_add_block.snap`

## Snapshot Content
```
"• Added new_file.txt (+2 -0)                                                    "
"    1 +alpha                                                                    "
"    2 +beta                                                                     "
```

---

## 1. 场景与职责 (Scenario & Responsibilities)

### 1.1 功能场景
此快照测试验证 **新增文件（Add）操作的差异渲染效果**。当 Codex 创建新文件时，系统需要以清晰的格式展示文件内容，标识这是新增操作。

### 1.2 业务职责
- **新增操作标识**: 清晰标识文件是新增的（Added）
- **内容展示**: 展示新文件的完整内容
- **行号显示**: 为新增内容添加行号
- **统计信息**: 显示新增行数（+N -0）

### 1.3 使用场景
1. 用户请求 Codex 创建新文件
2. Codex 生成文件内容
3. UI 展示新增文件的差异视图
4. 用户确认后应用更改

---

## 2. 功能点目的 (Feature Purpose)

### 2.1 核心功能
| 元素 | 内容 | 目的 |
|------|------|------|
| 操作类型 | "Added" | 标识这是新增文件操作 |
| 文件名 | `new_file.txt` | 显示新增的文件名 |
| 统计 | `(+2 -0)` | 显示新增 2 行，删除 0 行 |
| 行号 | `1`, `2` | 新文件的行号 |
| 内容 | `alpha`, `beta` | 新增的文件内容 |

### 2.2 与 Update 的区别
| 操作 | Header | 行前缀 |
|------|--------|--------|
| Add | "Added filename (+N -0)" | `+`（所有行）|
| Update | "Edited filename (+N -M)" | `+`, `-`, ` `（空格）|
| Delete | "Deleted filename (+0 -N)" | `-`（所有行）|

### 2.3 视觉设计
- **绿色主题**: 新增操作使用绿色调（与 Git 一致）
- **行号右对齐**: 保持与 Update 操作一致的行号格式
- **简洁头部**: 单行头部，无树形缩进（单文件时）

---

## 3. 具体技术实现 (Technical Implementation)

### 3.1 数据结构
```rust
// protocol/src/protocol.rs
pub enum FileChange {
    Add { content: String },
    Delete { content: String },
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
        FileChange::Add { content } => {
            // 渲染 Add 操作
            render_add_content(content, lines, wrap_cols, lang);
        }
        FileChange::Delete { content } => {
            render_delete_content(content, lines, wrap_cols, lang);
        }
        FileChange::Update { unified_diff, move_path } => {
            render_update_diff(unified_diff, lines, wrap_cols, lang);
        }
    }
}
```

### 3.3 Add 内容渲染
```rust
// diff_render.rs:500-550
fn render_add_content(
    content: &str,
    lines: &mut Vec<Line>,
    wrap_cols: usize,
    lang: Option<&str>,
) {
    let content_lines: Vec<&str> = content.lines().collect();
    let line_count = content_lines.len();
    
    // 计算行号宽度
    let gutter_width = line_number_width(line_count);
    
    // 应用语法高亮（如果可能）
    let syntax_lines = lang.and_then(|l| highlight_code_to_styled_spans(content, l));
    
    for (i, line) in content_lines.iter().enumerate() {
        let line_num = i + 1;
        
        // 构建行：行号 + +符号 + 内容
        let mut spans = vec![
            Span::styled(
                format!("{:>width$}", line_num, width = gutter_width),
                style_gutter_for(DiffLineType::Insert),
            ),
            Span::styled(" +", style_add()),
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
// diff_render.rs:1470-1490
#[test]
fn ui_snapshot_apply_add_block() {
    let mut changes: HashMap<PathBuf, FileChange> = HashMap::new();
    
    changes.insert(
        PathBuf::from("new_file.txt"),
        FileChange::Add {
            content: "alpha\nbeta\n".to_string(),
        },
    );
    
    let lines = diff_summary_for_tests(&changes);
    snapshot_lines("apply_add_block", lines, 80, 10);
}
```

---

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 4.1 主要文件
| 文件路径 | 职责 |
|---------|------|
| `tui_app_server/src/diff_render.rs` | Diff 渲染主逻辑 |
| `protocol/src/protocol.rs` | FileChange 枚举定义 |
| `tui_app_server/src/render/highlight.rs` | 语法高亮 |

### 4.2 调用链
```
create_diff_summary
  └── render_changes_block
        └── render_change
              └── FileChange::Add
                    ├── line_number_width        // 计算行号宽度
                    ├── highlight_code_to_styled_spans  // 语法高亮
                    └── push_wrapped_diff_line   // 渲染行
```

### 4.3 样式应用
```rust
// 新增行样式（绿色）
fn style_add() -> Style {
    Style::default().fg(Color::Green)
}

// 行号列样式
fn style_gutter_for(kind: DiffLineType) -> Style {
    match kind {
        DiffLineType::Insert => Style::default().fg(Color::Green).dim(),
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
| `syntect` | 语法高亮（可选）|

### 5.2 内部模块依赖
```rust
use crate::render::highlight::highlight_code_to_styled_spans;
use codex_protocol::protocol::FileChange;
```

---

## 6. 风险、边界与改进建议 (Risks, Edge Cases & Improvements)

### 6.1 已知风险
| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| 大文件 | 新增文件可能很大 | 限制显示行数，提供展开功能 |
| 二进制文件 | 不应通过 Add 渲染 | 在协议层过滤 |

### 6.2 边界情况
1. **空文件**: 显示 "Added filename (+0 -0)"，无内容行
2. **单行文件**: 正常显示，行号为 1
3. **无换行符结尾**: 最后一行也正确显示

### 6.3 改进建议
1. **文件类型图标**: 根据扩展名显示不同图标
2. **文件大小显示**: 在头部显示文件大小
3. **预览限制**: 大文件默认只显示前 50 行
4. **编码检测**: 显示文件编码信息

### 6.4 相关测试
- `apply_delete_block`: 删除操作测试
- `apply_update_block`: 更新操作测试
- `apply_multiple_files_block`: 多文件操作测试

---

## 7. 相关文档链接

- [Apply Update Block](../codex_tui_app_server__diff_render__tests__apply_update_block.snap_research.md) - 更新操作文档
- [Apply Delete Block](../codex_tui_app_server__diff_render__tests__apply_delete_block.snap_research.md) - 删除操作文档
