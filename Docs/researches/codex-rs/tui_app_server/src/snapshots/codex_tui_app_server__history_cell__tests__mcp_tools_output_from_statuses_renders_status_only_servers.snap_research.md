# MCP Tools Output from Statuses Renders Status Only Servers - Technical Research Document

## Snapshot File
`codex_tui_app_server__history_cell__tests__mcp_tools_output_from_statuses_renders_status_only_servers.snap`

## Snapshot Content
```
/mcp

🔌  MCP Tools

  • plugin_docs
    • Auth: Unsupported
    • Command: docs-server --stdio
    • Tools: lookup
    • Resources: (none)
    • Resource templates: (none)
```

---

## 1. 场景与职责 (Scenario & Responsibilities)

### 1.1 功能场景
此快照测试验证 **`/mcp` 命令输出中仅显示状态的服务器渲染效果**。当用户执行 `/mcp` 命令查看 MCP 工具状态时，显示每个服务器的详细信息。

### 1.2 业务职责
- **服务器列表**: 显示所有 MCP 服务器
- **状态信息**: 显示认证状态、命令、工具等
- **资源信息**: 显示资源和资源模板

---

## 2. 功能点目的 (Feature Purpose)

### 2.1 核心功能
| 元素 | 内容 | 目的 |
|------|------|------|
| 标题 | `🔌  MCP Tools` | 标识 MCP 工具区域 |
| 服务器名 | `plugin_docs` | 服务器标识 |
| 认证 | `Auth: Unsupported` | 认证状态 |
| 命令 | `Command: docs-server --stdio` | 启动命令 |
| 工具 | `Tools: lookup` | 可用工具 |

---

## 3. 具体技术实现 (Technical Implementation)

### 3.1 数据结构
```rust
struct McpServerStatus {
    name: String,
    auth_status: McpAuthStatus,
    command: String,
    tools: Vec<String>,
    resources: Vec<String>,
    resource_templates: Vec<String>,
}
```

---

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 4.1 主要文件
| 文件路径 | 职责 |
|---------|------|
| `tui_app_server/src/history_cell.rs` | MCP 工具输出单元格 |

---

## 5. 依赖与外部交互 (Dependencies & External Interactions)

### 5.1 外部依赖
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染 |

---

## 6. 风险、边界与改进建议 (Risks, Edge Cases & Improvements)

### 6.1 改进建议
1. **交互操作**: 支持启用/禁用服务器
2. **配置编辑**: 支持修改服务器配置
3. **状态刷新**: 支持刷新服务器状态

---

## 7. 相关文档链接

- [MCP Tools Output Masks Sensitive Values](../codex_tui_app_server__history_cell__tests__mcp_tools_output_masks_sensitive_values.snap_research.md)
