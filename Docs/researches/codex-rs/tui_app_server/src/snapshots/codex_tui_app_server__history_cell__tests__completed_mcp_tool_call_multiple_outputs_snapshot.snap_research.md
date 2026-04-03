# Completed MCP Tool Call Multiple Outputs - Technical Research Document

## Snapshot File
`codex_tui_app_server__history_cell__tests__completed_mcp_tool_call_multiple_outputs_snapshot.snap`

## Snapshot Content
```
• Called
  └ search.find_docs({"query":"ratatui
        styling","limit":3})
    Found styling guidance in styles.md and
        additional notes in CONTRIBUTING.md.
    link: file:///docs/styles.md
```

---

## 1. 场景与职责 (Scenario & Responsibilities)

### 1.1 功能场景
此快照测试验证 **MCP 工具调用返回多行输出时的渲染效果**，特别是当参数和结果都需要换行时的处理。

### 1.2 业务职责
- **参数换行**: 长 JSON 参数正确换行
- **结果换行**: 多行结果正确显示
- **层次清晰**: 保持调用、参数、结果的层次结构

---

## 2. 功能点目的 (Feature Purpose)

### 2.1 核心功能
- 处理长参数换行
- 显示多行输出结果
- 保持视觉层次

---

## 3. 具体技术实现 (Technical Implementation)

### 3.1 渲染逻辑
```rust
fn display_lines(&self, width: u16) -> Vec<Line> {
    let mut lines = vec![];
    
    // 工具名称单独一行
    lines.push(Line::from("• Called"));
    
    // 参数换行显示
    let params = format!("  └ {}({})", self.tool_name, self.params);
    lines.extend(wrap_line_with_indent(&params, width, 4));
    
    // 结果换行显示
    for line in self.result.lines() {
        lines.push(Line::from(format!("    {}", line)));
    }
    
    lines
}
```

---

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 4.1 主要文件
| 文件路径 | 职责 |
|---------|------|
| `tui_app_server/src/history_cell.rs` | MCP 工具调用单元格 |

---

## 5. 依赖与外部交互 (Dependencies & External Interactions)

### 5.1 外部依赖
| Crate | 用途 |
|-------|------|
| `serde_json` | JSON 处理 |

---

## 6. 风险、边界与改进建议 (Risks, Edge Cases & Improvements)

### 6.1 改进建议
1. **JSON 格式化**: 美化显示 JSON 参数
2. **链接可点击**: 支持点击链接打开文件

---

## 7. 相关文档链接

- [Completed MCP Tool Call Multiple Outputs Inline](../codex_tui_app_server__history_cell__tests__completed_mcp_tool_call_multiple_outputs_inline_snapshot.snap_research.md)
