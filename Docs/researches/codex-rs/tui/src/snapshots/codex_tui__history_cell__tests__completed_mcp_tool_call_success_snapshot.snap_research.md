# Research: Completed MCP Tool Call Success Snapshot

## 场景与职责

此快照测试验证 Codex TUI 在 MCP 工具调用成功完成时的基础展示能力。作为 MCP 工具调用展示的最基本场景，它定义了成功状态的标准视觉样式和信息布局。

## 功能点目的

1. **成功状态标识**：通过绿色"•"符号明确标识调用成功
2. **调用信息展示**：清晰展示调用的服务器、工具名称和参数
3. **结果展示**：展示工具返回的文本内容
4. **紧凑布局**：在宽度允许时，将调用信息和结果紧凑展示

## 具体技术实现

### 状态指示器

```rust
// history_cell.rs:1487-1492
let status = self.success();
let bullet = match status {
    Some(true) => "•".green().bold(),   // 成功：绿色加粗
    Some(false) => "•".red().bold(),  // 失败：红色加粗
    None => spinner(Some(self.start_time), self.animations_enabled), // 进行中：动画
};
let header_text = if status.is_some() { "Called" } else { "Calling" };
```

### 调用信息格式化

```rust
// history_cell.rs:2515-2534
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

### 紧凑/展开布局决策

```rust
// history_cell.rs:1500-1520
let invocation_line = line_to_static(&format_mcp_invocation(self.invocation.clone()));
let mut compact_spans = vec![bullet.clone(), " ".into(), header_text.bold(), " ".into()];
let mut compact_header = Line::from(compact_spans.clone());
let reserved = compact_header.width();

let inline_invocation = invocation_line.width() <= (width as usize).saturating_sub(reserved);

if inline_invocation {
    // 宽度足够：内联展示
    compact_header.extend(invocation_line.spans.clone());
    lines.push(compact_header);
} else {
    // 宽度不足：换行展示
    compact_spans.pop();
    lines.push(Line::from(compact_spans));
    
    let opts = RtOptions::new((width as usize).saturating_sub(4))
        .initial_indent("".into())
        .subsequent_indent("    ".into());
    let wrapped = adaptive_wrap_line(&invocation_line, opts);
    let body_lines: Vec<Line<'static>> = wrapped.iter().map(line_to_static).collect();
    lines.extend(prefix_lines(body_lines, "  └ ".dim(), "    ".into()));
}
```

### 测试场景

```rust
// history_cell.rs:3192-3218
#[test]
fn completed_mcp_tool_call_success_snapshot() {
    let invocation = McpInvocation {
        server: "search".into(),
        tool: "find_docs".into(),
        arguments: Some(json!({
            "query": "ratatui styling",
            "limit": 3,
        })),
    };

    let result = CallToolResult {
        content: vec![text_block("Found styling guidance in styles.md")],
        is_error: None,
        structured_content: None,
        meta: None,
    };

    let mut cell = new_active_mcp_tool_call("call-2".into(), invocation, true);
    assert!(
        cell.complete(Duration::from_millis(1420), Ok(result))
            .is_none()  // 纯文本结果不产生额外单元格
    );

    let rendered = render_lines(&cell.display_lines(80)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 输出格式

```
• Called search.find_docs({"query":"ratatui styling","limit":3})
  └ Found styling guidance in styles.md
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/history_cell.rs` | MCP 单元格实现，测试位于 line 3192-3218 |
| `codex-rs/tui/src/exec_cell/mod.rs` | 工具结果格式化 |
| `codex-rs/tui/src/wrapping.rs` | 文本换行处理 |
| `codex-rs/tui/src/render/line_utils.rs` | 行工具函数（`line_to_static`, `prefix_lines`） |

### 成功场景渲染流程

```
new_active_mcp_tool_call("call-2", invocation, animations: true)
    ↓
cell.complete(duration: 1420ms, Ok(CallToolResult { content: [text_block] }))
    ↓
display_lines(width: 80)
    ↓
success() → Some(true)
    ↓
bullet = "•".green().bold()
    ↓
format_mcp_invocation() → "search.find_docs({...})"
    ↓
inline_invocation = true (宽度 80 足够)
    ↓
渲染单行："• Called search.find_docs({...})"
    ↓
渲染结果："  └ Found styling guidance in styles.md"
```

## 依赖与外部交互

### 外部依赖

- `codex_protocol::mcp::{CallToolResult, McpInvocation}`: MCP 协议类型
- `rmcp::model::Content`: MCP 内容模型
- `serde_json`: JSON 处理

### 内部工具

```rust
// exec_cell/mod.rs
pub(crate) const TOOL_CALL_MAX_LINES: usize = 5;

pub(crate) fn format_and_truncate_tool_result(
    text: &str,
    max_lines: usize,
    width: usize,
) -> String;
```

## 风险、边界与改进建议

### 潜在风险

1. **参数泄露**：敏感参数可能在调用信息中泄露
2. **长参数截断**：过长参数被截断后可能失去意义
3. **动画性能**：`animations_enabled` 为 true 时可能影响性能

### 边界情况

1. **空参数**：`arguments: None` 或 `{}` 的展示
2. **超长参数**：数百字符的 JSON 参数
3. **特殊字符**：参数中包含换行、制表符等
4. **Unicode 参数**：非 ASCII 参数的宽度计算

### 改进建议

1. **参数折叠**：默认折叠复杂参数，提供展开选项
2. **敏感参数脱敏**：自动隐藏包含敏感词的参数值
3. **参数格式化**：对 JSON 参数提供格式化展示选项
4. **工具图标**：为不同工具显示专属图标
5. **调用时间**：显示调用耗时
6. **复制功能**：提供复制调用信息的快捷键

### 相关测试

- `completed_mcp_tool_call_error_snapshot`：错误场景对比
- `completed_mcp_tool_call_multiple_outputs_snapshot`：多输出场景
- `active_mcp_tool_call_snapshot`：进行中状态
