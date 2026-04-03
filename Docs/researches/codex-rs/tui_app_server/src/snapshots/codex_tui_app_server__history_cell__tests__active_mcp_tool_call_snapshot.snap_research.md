# Active MCP Tool Call Snapshot - Technical Research Document

## Snapshot File
`codex_tui_app_server__history_cell__tests__active_mcp_tool_call_snapshot.snap`

## Snapshot Content
```
• Calling search.find_docs({"query":"ratatui styling","limit":3})
```

---

## 1. 场景与职责 (Scenario & Responsibilities)

### 1.1 功能场景
此快照测试验证 **MCP（Model Context Protocol）工具调用进行中的 UI 渲染效果**。当 Codex 正在调用外部 MCP 工具时，UI 需要显示调用状态。

### 1.2 业务职责
- **进行中状态**: 显示工具调用正在进行
- **工具信息**: 显示工具名称和参数
- **用户反馈**: 让用户知道系统正在工作

### 1.3 与完成状态的区别
| 状态 | 前缀 | 示例 |
|------|------|------|
| Active | "Calling" | `• Calling search.find_docs(...)` |
| Success | "Called" | `• Called search.find_docs(...)` |
| Error | "Called" + Error | `• Called search.find_docs(...)\n  └ Error: ...` |

---

## 2. 功能点目的 (Feature Purpose)

### 2.1 核心功能
| 元素 | 内容 | 目的 |
|------|------|------|
| 状态前缀 | "Calling" | 标识调用进行中 |
| 工具名称 | `search.find_docs` | 显示被调用的工具 |
| 参数 | JSON 对象 | 显示调用参数 |

### 2.2 MCP 工具调用生命周期
1. **Calling**: 工具调用已发起，等待响应
2. **Called**: 工具调用完成，显示结果
3. **Error**: 工具调用失败，显示错误

---

## 3. 具体技术实现 (Technical Implementation)

### 3.1 数据结构
```rust
// history_cell.rs
pub struct McpToolCallCell {
    pub tool_name: String,
    pub params: serde_json::Value,
    pub status: McpToolCallStatus,
}

pub enum McpToolCallStatus {
    Active,      // 本测试场景
    Completed(Result<String, String>),
}
```

### 3.2 渲染逻辑
```rust
impl HistoryCell for McpToolCallCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        let mut lines = vec![];
        
        match self.status {
            McpToolCallStatus::Active => {
                let header = format!(
                    "• Calling {}({})",
                    self.tool_name,
                    self.params.to_string()
                );
                lines.push(Line::from(header));
            }
            McpToolCallStatus::Completed(result) => {
                // 渲染完成状态...
            }
        }
        
        lines
    }
}
```

### 3.3 测试实现
```rust
#[test]
fn active_mcp_tool_call_snapshot() {
    let cell = McpToolCallCell {
        tool_name: "search.find_docs".to_string(),
        params: json!({"query": "ratatui styling", "limit": 3}),
        status: McpToolCallStatus::Active,
    };
    
    let lines = cell.display_lines(80);
    assert_snapshot!("active_mcp_tool_call", lines_to_string(&lines));
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
| `serde_json` | JSON 参数处理 |

---

## 6. 风险、边界与改进建议 (Risks, Edge Cases & Improvements)

### 6.1 改进建议
1. **动画效果**: 添加旋转器或进度指示
2. **取消功能**: 支持取消正在进行的调用
3. **超时提示**: 长时间无响应时提示用户

### 6.2 相关测试
- `completed_mcp_tool_call_success`: 成功完成测试
- `completed_mcp_tool_call_error`: 错误完成测试

---

## 7. 相关文档链接

- [Completed MCP Tool Call Success](../codex_tui_app_server__history_cell__tests__completed_mcp_tool_call_success_snapshot.snap_research.md)
