# 研究文档：completed_mcp_tool_call_success_snapshot.snap

## 场景与职责

此快照测试验证 Codex TUI 中 MCP（Model Context Protocol）工具调用成功完成时的 UI 渲染效果。MCP 是 Codex 与外部工具集成的协议，此测试确保成功的工具调用在历史记录中正确显示。

## 功能点目的

1. **MCP 工具调用展示**：显示 MCP 工具的名称和参数
2. **成功状态指示**：清晰标识工具调用已成功完成
3. **结果摘要**：展示工具返回的简要结果

## 具体技术实现

### MCP 工具调用结构

```rust
// 来自 codex_protocol::protocol::McpInvocation
pub struct McpInvocation {
    pub tool_name: String,
    pub params: serde_json::Value,
    // ...
}
```

### 快照输出分析

```
• Called search.find_docs({"query":"ratatui styling","limit":3})
  └ Found styling guidance in styles.md
```

- `• Called` - 表示工具调用操作
- `search.find_docs(...)` - 工具名称和 JSON 参数
- `└` - 树形连接符，指向结果
- `Found styling guidance in styles.md` - 工具返回的友好消息

## 关键代码路径与文件引用

1. **主要实现文件**：
   - `codex-rs/tui/src/history_cell.rs` - 包含 MCP 工具调用单元格的实现
   - 大约在第 1795 行附近（根据 assertion_line）

2. **MCP 相关类型**：
   - `codex_protocol::protocol::McpInvocation` - MCP 调用结构
   - `codex_protocol::protocol::McpAuthStatus` - MCP 认证状态

3. **测试依赖**：
   - `insta` - 快照测试框架
   - `ratatui::backend::TestBackend` - 测试后端

## 依赖与外部交互

### 核心依赖
- `codex_core::mcp::McpManager` - MCP 管理器
- `codex_app_server_protocol::McpServerStatus` - MCP 服务器状态（tui_app_server 版本）

### 渲染依赖
- `ratatui::style::Stylize` - 样式应用
- `crate::text_formatting::format_and_truncate_tool_result` - 结果格式化

## 风险、边界与改进建议

### 潜在风险
1. **JSON 参数过长**：如果工具参数很大，可能导致显示溢出
2. **特殊字符处理**：JSON 中的特殊字符需要正确转义显示

### 边界情况
1. 工具返回空结果
2. 工具返回非常大的结果（需要截断）
3. 工具返回多行结果

### 改进建议
1. 添加参数折叠功能，对于大 JSON 默认折叠
2. 支持点击展开查看完整参数
3. 添加工具执行时间显示
4. 考虑添加工具图标，区分不同类型的 MCP 工具
