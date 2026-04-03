# Research: Completed MCP Tool Call Error Snapshot

## 场景与职责

此快照测试验证 Codex TUI 在 MCP (Model Context Protocol) 工具调用失败时的错误展示能力。当 AI 代理调用的外部工具返回错误时，UI 需要清晰地展示错误信息，帮助用户理解调用失败的原因。

## 功能点目的

1. **错误状态可视化**：通过红色"•"符号和 "Error:" 前缀明确标识错误
2. **调用信息保留**：即使失败也展示完整的调用参数
3. **错误信息截断**：对过长的错误信息进行智能截断，避免占据过多屏幕空间

## 具体技术实现

### MCP 工具调用单元格

```rust
// history_cell.rs:1399-1406
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

### 完成调用与错误处理

```rust
// history_cell.rs:1428-1438
pub(crate) fn complete(
    &mut self,
    duration: Duration,
    result: Result<codex_protocol::mcp::CallToolResult, String>,
) -> Option<Box<dyn HistoryCell>> {
    let image_cell = try_new_completed_mcp_tool_call_with_image_output(&result)
        .map(|cell| Box::new(cell) as Box<dyn HistoryCell>);
    self.duration = Some(duration);
    self.result = Some(result);
    image_cell
}

fn success(&self) -> Option<bool> {
    match self.result.as_ref() {
        Some(Ok(result)) => Some(!result.is_error.unwrap_or(false)),
        Some(Err(_)) => Some(false),  // 错误情况返回 false
        None => None,
    }
}
```

### 错误渲染逻辑

```rust
// history_cell.rs:1484-1573 (display_lines 实现)
fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
    let status = self.success();
    let bullet = match status {
        Some(true) => "•".green().bold(),
        Some(false) => "•".red().bold(),  // 错误状态使用红色
        None => spinner(Some(self.start_time), self.animations_enabled),
    };
    let header_text = if status.is_some() { "Called" } else { "Calling" };

    // ... 调用信息渲染

    if let Some(result) = &self.result {
        match result {
            Ok(_) => { /* 成功处理 */ }
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
}
```

### 测试场景

```rust
// history_cell.rs:3303-3322
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
            .is_none()  // 错误结果不产生额外单元格
    );

    let rendered = render_lines(&cell.display_lines(80)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 输出格式

```
• Called search.find_docs({"query":"ratatui styling","limit":3})
  └ Error: network timeout
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/history_cell.rs` | MCP 工具调用单元格实现，测试用例位于 line 3303-3322 |
| `codex-rs/tui/src/exec_cell/mod.rs` | `format_and_truncate_tool_result` 工具函数 |
| `codex-rs/tui/src/text_formatting.rs` | 文本格式化与截断逻辑 |
| `codex-protocol` | MCP 协议类型定义 (`CallToolResult`, `McpInvocation`) |

### 错误处理流程

```
McpToolCallCell::complete(result: Err("network timeout"))
    ↓
self.result = Some(Err("network timeout"))
    ↓
display_lines()
    ↓
success() → Some(false)  // 识别为错误状态
    ↓
bullet = "•".red().bold()  // 红色错误指示器
    ↓
渲染错误信息:
  format_and_truncate_tool_result("Error: network timeout", ...)
    ↓
  自适应换行 + 缩进前缀
```

## 依赖与外部交互

### 外部依赖

- `codex_protocol::mcp::CallToolResult`: MCP 工具调用结果类型
- `codex_protocol::protocol::McpInvocation`: 调用信息类型
- `serde_json`: JSON 参数序列化

### 内部依赖

```rust
// 来自 exec_cell/mod.rs
pub(crate) fn format_and_truncate_tool_result(
    text: &str,
    max_lines: usize,
    width: usize,
) -> String;

// 来自 text_formatting.rs
pub fn truncate_text(text: &str, max_graphemes: usize) -> String;
```

## 风险、边界与改进建议

### 潜在风险

1. **错误信息泄露**：错误信息可能包含敏感信息（如文件路径、内部错误详情）
2. **截断导致信息丢失**：过长的错误信息被截断后可能失去诊断价值
3. **国际化问题**：错误信息硬编码为英文，不支持多语言

### 边界情况

1. **空错误信息**：`Err("")` 的展示处理
2. **多行错误信息**：包含换行符的错误信息渲染
3. **超长错误信息**：超过 `TOOL_CALL_MAX_LINES` (5行) 的截断处理
4. **特殊字符**：错误信息中包含 ANSI 转义序列的处理

### 改进建议

1. **错误分类**：根据错误类型显示不同图标（网络错误、权限错误、超时等）
2. **详情展开**：提供按键展开完整错误信息的功能
3. **错误日志链接**：添加跳转到详细日志的链接
4. **重试指示**：对于可重试的错误，显示重试按钮或提示
5. **敏感信息过滤**：自动过滤错误信息中的敏感内容（API keys、密码等）
6. **时间戳显示**：显示错误发生的时间

### 相关测试

- `completed_mcp_tool_call_success_snapshot`：成功场景对比
- `completed_mcp_tool_call_multiple_outputs_snapshot`：多输出场景
- `completed_mcp_tool_call_wrapped_outputs_snapshot`：长输出换行
