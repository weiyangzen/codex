# Research: Active MCP Tool Call Display

## 场景与职责

该快照测试验证 Codex TUI 中正在进行中的 MCP（Model Context Protocol）工具调用的显示格式。当 AI 助手调用外部 MCP 工具（如搜索、文档查找等）时，需要在历史记录中显示调用状态，让用户了解当前正在执行的操作。

## 功能点目的

1. **实时状态显示**: 显示正在进行的 MCP 工具调用，使用动画 spinner 表示活动状态
2. **调用信息展示**: 展示服务器名称、工具名称和参数
3. **格式一致性**: 保持与已完成工具调用相似的格式，仅状态指示器不同
4. **视觉层次**: 使用颜色和缩进区分调用状态、服务器/工具名和参数

## 具体技术实现

### 核心结构
```rust
#[derive(Debug)]
pub(crate) struct McpToolCallCell {
    call_id: String,
    invocation: McpInvocation,
    start_time: Instant,
    duration: Option<Duration>,
    result: Option<Result<codex_protocol::mcp::CallToolResult, String>>,
    animations_enabled: bool,
}
```

### 显示格式
```
• Calling search.find_docs({"query":"ratatui styling","limit":3})
```

格式分解：
- `•`: 动画 spinner（当 `animations_enabled=true` 且调用未完成时）
- `Calling`: 状态文本（未完成时为 "Calling"，完成后为 "Called"）
- `search`: MCP 服务器名称（青色）
- `.`: 分隔符
- `find_docs`: 工具名称（青色）
- `(...)`: 参数 JSON（暗淡色）

### 格式化函数
```rust
fn format_mcp_invocation<'a>(invocation: McpInvocation) -> Line<'a> {
    let args_str = invocation
        .arguments
        .as_ref()
        .map(|v: &serde_json::Value| {
            serde_json::to_string(v).unwrap_or_else(|_| v.to_string())
        })
        .unwrap_or_default();

    let invocation_spans = vec![
        invocation.server.clone().cyan(),
        ".".into(),
        invocation.tool.cyan(),
        "(".into(),
        args_str.dim(),
        ")".into(),
    ];
    invocation_spans.into()
}
```

### 测试代码位置
- 文件: `codex-rs/tui/src/history_cell.rs`
- 测试函数: `active_mcp_tool_call_snapshot`
- 行号: 约 3175-3189

```rust
#[test]
fn active_mcp_tool_call_snapshot() {
    let invocation = McpInvocation {
        server: "search".into(),
        tool: "find_docs".into(),
        arguments: Some(json!({
            "query": "ratatui styling",
            "limit": 3,
        })),
    };

    let cell = new_active_mcp_tool_call("call-1".into(), invocation, true);
    let rendered = render_lines(&cell.display_lines(80)).join("\n");

    insta::assert_snapshot!(rendered);
}
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/history_cell.rs` | `McpToolCallCell` 实现和显示逻辑 |
| `codex-rs/tui/src/history_cell.rs:1398-1581` | `McpToolCallCell` 结构体及 `HistoryCell` trait 实现 |
| `codex-rs/tui/src/history_cell.rs:1484-1573` | `display_lines` 方法，处理渲染逻辑 |
| `codex-rs/tui/src/history_cell.rs:2515-2534` | `format_mcp_invocation` 函数 |
| `codex-rs/tui/src/history_cell.rs:1583-1589` | `new_active_mcp_tool_call` 构造函数 |

### 依赖模块
- `codex_protocol::protocol::McpInvocation`: MCP 调用参数结构
- `rmcp::model::Content`: MCP 内容模型（用于解析结果）
- `base64`: 处理图像内容的 base64 解码
- `image`: 图像解码和显示

## 依赖与外部交互

### 输入
- `call_id`: 唯一调用标识符
- `McpInvocation`: 包含服务器名、工具名和参数
- `animations_enabled`: 是否启用动画效果

### 输出
- 渲染后的终端行：`• Calling search.find_docs({"query":"ratatui styling","limit":3})`
- 状态指示器使用 spinner（动画点）表示进行中的状态
- 服务器和工具名使用青色高亮

### 状态流转
```
Active (Calling + spinner) 
  ├── Success → Called + 绿色 bullet + 结果
  ├── Error → Called + 红色 bullet + 错误信息
  └── Interrupted → Called + 红色 bullet + "interrupted"
```

## 风险、边界与改进建议

### 潜在风险
1. **参数过长**: 如果参数 JSON 很长，可能超出终端宽度，需要换行处理
2. **特殊字符**: 参数中的特殊字符可能影响显示
3. **动画性能**: 大量并行的 MCP 调用可能导致 spinner 动画性能问题

### 边界情况
1. **无参数调用**: `arguments` 为 `None` 时显示空括号 `()`
2. **长参数换行**: 当内联显示超出宽度时，自动转为多行显示（`inline_invocation` 检查）
3. **图像输出**: 工具返回图像时，创建额外的 `CompletedMcpToolCallWithImageOutput` cell

### 改进建议
1. **参数折叠**: 对于非常长的参数，考虑折叠显示，用户可展开查看完整内容
2. **调用耗时**: 在完成后显示调用耗时（已有实现，但可优化格式）
3. **重试指示**: 支持显示调用重试次数
4. **取消操作**: 提供用户取消长时间运行的 MCP 调用的方式
5. **工具图标**: 为常用工具提供图标标识，增强视觉识别
