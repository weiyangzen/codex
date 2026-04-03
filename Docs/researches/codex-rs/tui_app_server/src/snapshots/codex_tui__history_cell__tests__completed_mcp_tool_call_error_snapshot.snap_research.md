# completed_mcp_tool_call_error_snapshot 研究文档

## 场景与职责

该测试验证 MCP (Model Context Protocol) 工具调用失败时的历史记录渲染行为。当 MCP 工具调用因网络超时、服务器错误或中断等原因失败时，TUI 需要以清晰的方式向用户展示错误信息，帮助用户理解发生了什么以及为什么操作未成功。

## 功能点目的

1. **错误状态可视化**: 将工具调用的失败状态以红色高亮显示，与成功的绿色形成对比
2. **错误信息展示**: 在工具调用详情下方显示具体的错误原因（如 "network timeout"）
3. **一致性体验**: 保持与成功调用相同的布局结构（"• Called ... └ Error: ..."），确保用户体验的一致性

**Snapshot 内容示例**:
```
• Called search.find_docs({"query":"ratatui styling","limit":3})
  └ Error: network timeout
```

## 具体技术实现

### 核心数据结构

```rust
// McpToolCallCell 结构体定义（history_cell.rs 第 1398-1406 行）
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

### 错误渲染逻辑

在 `McpToolCallCell::display_lines` 方法中（第 1484-1581 行），错误处理逻辑如下：

```rust
if let Some(result) = &self.result {
    match result {
        Ok(codex_protocol::mcp::CallToolResult { content, .. }) => {
            // 成功情况处理...
        }
        Err(err) => {
            let err_text = format_and_truncate_tool_result(
                &format!("Error: {err}"),
                TOOL_CALL_MAX_LINES,
                width as usize,
            );
            let err_line = Line::from(err_text.dim());
            let wrapped = adaptive_wrap_line(
                &err_line,
                RtOptions::new(detail_wrap_width)
                    .initial_indent("".into())
                    .subsequent_indent("    ".into()),
            );
            detail_lines.extend(wrapped.iter().map(line_to_static));
        }
    }
}
```

### 状态指示器

```rust
// 第 1487-1492 行：根据成功状态选择 bullet 颜色
let status = self.success();
let bullet = match status {
    Some(true) => "•".green().bold(),
    Some(false) => "•".red().bold(),  // 错误状态使用红色
    None => spinner(Some(self.start_time), self.animations_enabled),
};
```

### 测试代码

```rust
// 第 3303-3322 行
#[test]
fn completed_mcp_tool_call_error_snapshot() {
    let invocation = McpInvocation {
        server: "search".into(),
        tool: "find_docs".into(),
        arguments: Some(json!({
            "query": "ratatui styling",
            "limit": 3,
        })),
    };

    let mut cell = new_active_mcp_tool_call("call-3".into(), invocation, true);
    assert!(
        cell.complete(Duration::from_secs(2), Err("network timeout".into()))
            .is_none()
    );

    let rendered = render_lines(&cell.display_lines(80)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

## 关键代码路径与文件引用

| 文件路径 | 行号范围 | 说明 |
|---------|---------|------|
| `codex-rs/tui/src/history_cell.rs` | 1398-1406 | `McpToolCallCell` 结构体定义 |
| `codex-rs/tui/src/history_cell.rs` | 1484-1581 | `display_lines` 方法实现 |
| `codex-rs/tui/src/history_cell.rs` | 1545-1559 | 错误处理分支 |
| `codex-rs/tui/src/history_cell.rs` | 1440-1446 | `success()` 方法判断调用状态 |
| `codex-rs/tui/src/history_cell.rs` | 3303-3322 | 测试用例定义 |
| `codex-rs/tui/src/history_cell.rs` | 2515-2534 | `format_mcp_invocation` 格式化函数 |

## 依赖与外部交互

### 外部依赖

1. **rmcp crate**: MCP 协议实现，提供 `Content` 类型用于解析工具返回内容
2. **serde_json**: 用于序列化/反序列化工具参数和结果
3. **ratatui**: 终端 UI 渲染框架，提供 `Line`、`Span`、`Style` 等类型
4. **codex_protocol**: 内部协议库，定义 `McpInvocation` 和 `CallToolResult`

### 相关工具函数

```rust
// text_formatting.rs
pub fn format_and_truncate_tool_result(text: &str, max_lines: usize, width: usize) -> String

// wrapping.rs  
pub fn adaptive_wrap_line(line: &Line, opts: RtOptions) -> Text
```

## 风险、边界与改进建议

### 当前风险与边界

1. **错误信息截断**: 使用 `format_and_truncate_tool_result` 可能截断长错误信息，丢失关键上下文
2. **无重试机制显示**: 当前仅显示错误，未提供重试或故障排除建议
3. **网络超时特定性**: "network timeout" 是特定错误类型，但渲染逻辑对所有错误使用统一格式

### 改进建议

1. **错误分类显示**: 根据错误类型（网络、权限、参数等）显示不同的图标或颜色
   ```rust
   let bullet = match error_category {
       NetworkError => "⚠".yellow().bold(),
       PermissionError => "🚫".red().bold(),
       _ => "•".red().bold(),
   };
   ```

2. **可展开详情**: 对于长错误信息，提供折叠/展开功能

3. **操作提示**: 在错误下方添加建议操作，如：
   ```
   └ Error: network timeout
     Tip: Check your connection or try again later
   ```

4. **错误代码显示**: 如果 MCP 协议支持错误代码，一并显示便于调试

5. **时间戳记录**: 记录错误发生时间，帮助用户关联日志
