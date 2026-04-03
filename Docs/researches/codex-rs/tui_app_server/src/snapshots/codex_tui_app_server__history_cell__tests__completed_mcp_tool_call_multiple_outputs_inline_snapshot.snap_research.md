# Completed MCP Tool Call Multiple Outputs Inline - Technical Research Document

## Snapshot File
`codex_tui_app_server__history_cell__tests__completed_mcp_tool_call_multiple_outputs_inline_snapshot.snap`

## Snapshot Content
```
• Called metrics.summary({"metric":"trace.latency","window":"15m"})
  └ Latency summary: p50=120ms, p95=480ms.
    No anomalies detected.
```

---

## 1. 场景与职责 (Scenario & Responsibilities)

### 1.1 功能场景
此快照测试验证 **MCP 工具调用返回多行输出时的内联渲染效果**。当工具结果包含多行文本时，UI 以内联方式展示所有输出行。

### 1.2 业务职责
- **多行展示**: 支持显示多行工具输出
- **内联缩进**: 保持与首行一致的缩进层次
- **清晰分隔**: 清晰展示每行输出

### 1.3 与折叠显示的区别
| 模式 | 显示 |
|------|------|
| Inline | 所有行直接显示 |
| Folded | 只显示摘要，点击展开 |

---

## 2. 功能点目的 (Feature Purpose)

### 2.1 核心功能
- 显示多行工具输出
- 保持适当的缩进对齐
- 支持长文本换行

---

## 3. 具体技术实现 (Technical Implementation)

### 3.1 渲染逻辑
```rust
fn render_tool_output(output: &str) -> Vec<Line> {
    output.lines().map(|line| {
        Line::from(format!("    {}", line))
    }).collect()
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
| `ratatui` | TUI 渲染 |

---

## 6. 风险、边界与改进建议 (Risks, Edge Cases & Improvements)

### 6.1 改进建议
1. **行数限制**: 限制默认显示行数，提供展开功能
2. **滚动支持**: 大量输出时支持滚动查看

---

## 7. 相关文档链接

- [Completed MCP Tool Call Success](../codex_tui_app_server__history_cell__tests__completed_mcp_tool_call_success_snapshot.snap_research.md)
