# Completed MCP Tool Call Error Snapshot - Technical Research Document

## Snapshot File
`codex_tui_app_server__history_cell__tests__completed_mcp_tool_call_error_snapshot.snap`

## Snapshot Content
```
• Called search.find_docs({"query":"ratatui styling","limit":3})
  └ Error: network timeout
```

---

## 1. 场景与职责 (Scenario & Responsibilities)

### 1.1 功能场景
此快照测试验证 **MCP 工具调用失败时的 UI 渲染效果**。当 MCP 工具调用返回错误时，UI 需要清晰显示错误信息。

### 1.2 业务职责
- **错误标识**: 清晰标识工具调用失败
- **错误信息**: 显示具体的错误原因
- **视觉区分**: 使用红色等颜色标识错误

### 1.3 与成功状态的区别
| 状态 | 显示 |
|------|------|
| Success | `• Called tool(...)\n  └ Result: ...` |
| Error | `• Called tool(...)\n  └ Error: ...` |

---

## 2. 功能点目的 (Feature Purpose)

### 2.1 核心功能
| 元素 | 内容 | 目的 |
|------|------|------|
| 调用记录 | "Called search.find_docs(...)" | 记录调用尝试 |
| 错误标识 | "Error:" | 标识错误状态 |
| 错误信息 | "network timeout" | 具体错误原因 |

### 2.2 错误处理流程
1. 发起工具调用
2. 接收错误响应
3. 在历史记录中显示错误
4. 允许用户重试或继续

---

## 3. 具体技术实现 (Technical Implementation)

### 3.1 渲染逻辑
```rust
impl HistoryCell for McpToolCallCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        let mut lines = vec![];
        
        // 始终显示调用记录
        let header = format!("• Called {}({})", self.tool_name, self.params);
        lines.push(Line::from(header));
        
        match &self.status {
            McpToolCallStatus::Completed(Ok(result)) => {
                lines.push(Line::from(vec![
                    "  └ ".into(),
                    Span::from(format!("Result: {}", result)).green(),
                ]));
            }
            McpToolCallStatus::Completed(Err(error)) => {
                lines.push(Line::from(vec![
                    "  └ ".into(),
                    Span::from(format!("Error: {}", error)).red(),
                ]));
            }
            _ => {}
        }
        
        lines
    }
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
| `ratatui` | 样式渲染 |

---

## 6. 风险、边界与改进建议 (Risks, Edge Cases & Improvements)

### 6.1 改进建议
1. **重试按钮**: 提供快速重试功能
2. **错误详情**: 展开查看完整错误堆栈
3. **错误分类**: 区分网络错误、权限错误等

---

## 7. 相关文档链接

- [Active MCP Tool Call](../codex_tui_app_server__history_cell__tests__active_mcp_tool_call_snapshot.snap_research.md)
- [Completed MCP Tool Call Success](../codex_tui_app_server__history_cell__tests__completed_mcp_tool_call_success_snapshot.snap_research.md)
