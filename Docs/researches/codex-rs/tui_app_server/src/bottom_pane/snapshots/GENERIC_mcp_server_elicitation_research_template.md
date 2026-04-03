# MCP Server Elicitation Generic Research Template

## 场景与职责

该文档是 MCP 服务器请求视图的通用研究模板，适用于以下快照文件：
- `mcp_server_elicitation_approval_form_with_session_persist.snap`
- `mcp_server_elicitation_approval_form_without_schema.snap`
- `mcp_server_elicitation_boolean_form.snap`

### 业务场景
- MCP 服务器需要用户输入或确认
- 显示不同类型的表单（参数摘要、会话持久化、布尔选择等）
- 用户需要批准或拒绝请求

### 表单类型
| 类型 | 描述 |
|------|------|
| Param Summary | 显示操作参数摘要 |
| Session Persist | 询问是否持久化会话 |
| Without Schema | 无模式定义的表单 |
| Boolean Form | 布尔值选择表单 |

## 功能点目的

### 核心功能
1. **表单显示**：根据请求类型显示不同的表单
2. **参数展示**：显示操作参数供用户确认
3. **用户决策**：提供批准或拒绝的选项

### 用户体验目标
- **透明度**：用户清楚知道将要执行什么操作
- **灵活输入**：支持不同类型的输入
- **快速决策**：提供明确的批准/拒绝选项

## 具体技术实现

### 关键数据结构
```rust
pub(crate) struct McpServerElicitationView {
    form_type: FormType,
    params: Vec<(String, String)>,
    // ...
}

pub(crate) enum FormType {
    ParamSummary,
    SessionPersist,
    Boolean,
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/mcp_server_elicitation.rs`

## 依赖与外部交互

### 内部依赖
- `McpServerElicitationView` - MCP 服务器请求视图

### 外部交互
- **MCP 客户端**：接收服务器请求
- **MCP 服务器**：发送请求并等待响应

## 风险、边界与改进建议

### 潜在风险
1. **参数篡改**：显示的参数与实际执行的参数不一致
2. **信息泄露**：敏感参数可能被显示

### 改进建议
1. **敏感参数隐藏**：自动隐藏或脱敏敏感信息
2. **操作预览**：显示操作执行后的预期效果

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/mcp_server_elicitation.rs`
