# Research: Completed MCP Tool Call Multiple Outputs Inline Snapshot

## 场景与职责

此快照测试验证 Codex TUI 在 MCP 工具调用返回多个文本输出块时的内联展示能力。当 AI 代理调用的外部工具返回多个独立的文本结果时，UI 需要将这些结果紧凑地展示在同一行或相邻行，保持界面的整洁性。

## 功能点目的

1. **多输出块合并展示**：将同一工具调用的多个文本输出块连续展示
2. **内联紧凑布局**：在宽度允许时，将输出保持在同一视觉区域内
3. **结果状态指示**：通过绿色"•"符号标识成功完成的调用

## 具体技术实现

### 多输出渲染逻辑

```rust
// history_cell.rs:1526-1543
detail_wrap_width = (width as usize).saturating_sub(4).max(1);

if let Some(result) = &self.result {
    match result {
        Ok(codex_protocol::mcp::CallToolResult { content, .. }) => {
            if !content.is_empty() {
                for block in content {
                    let text = Self::render_content_block(block, detail_wrap_width);
                    for segment in text.split('\n') {
                        let line = Line::from(segment.to_string().dim());
                        let wrapped = adaptive_wrap_line(
                            &line,
                            RtOptions::new(detail_wrap_width)
                                .initial_indent("".into())
                                .subsequent_indent("    ".into()),
                        );
                        detail_lines.extend(wrapped.iter().map(line_to_static));
                    }
                }
            }
        }
        // ... 错误处理
    }
}
```

### 内容块渲染

```rust
// history_cell.rs:1454-1481
fn render_content_block(block: &serde_json::Value, width: usize) -> String {
    let content = match serde_json::from_value::<rmcp::model::Content>(block.clone()) {
        Ok(content) => content,
        Err(_) => {
            return format_and_truncate_tool_result(
                &block.to_string(),
                TOOL_CALL_MAX_LINES,
                width,
            );
        }
    };

    match content.raw {
        rmcp::model::RawContent::Text(text) => {
            format_and_truncate_tool_result(&text.text, TOOL_CALL_MAX_LINES, width)
        }
        rmcp::model::RawContent::Image(_) => "<image content>".to_string(),
        rmcp::model::RawContent::Audio(_) => "<audio content>".to_string(),
        rmcp::model::RawContent::Resource(resource) => {
            let uri = match resource.resource {
                rmcp::model::ResourceContents::TextResourceContents { uri, .. } => uri,
                rmcp::model::ResourceContents::BlobResourceContents { uri, .. } => uri,
            };
            format!("embedded resource: {uri}")
        }
        rmcp::model::RawContent::ResourceLink(link) => format!("link: {}", link.uri),
    }
}
```

### 测试场景

```rust
// history_cell.rs:3395-3424
#[test]
fn completed_mcp_tool_call_multiple_outputs_inline_snapshot() {
    let invocation = McpInvocation {
        server: "metrics".into(),
        tool: "summary".into(),
        arguments: Some(json!({
            "metric": "trace.latency",
            "window": "15m",
        })),
    };

    let result = CallToolResult {
        content: vec![
            text_block("Latency summary: p50=120ms, p95=480ms."),
            text_block("No anomalies detected."),  // 第二个输出块
        ],
        is_error: None,
        structured_content: None,
        meta: None,
    };

    let mut cell = new_active_mcp_tool_call("call-6".into(), invocation, true);
    assert!(
        cell.complete(Duration::from_millis(320), Ok(result))
            .is_none()
    );

    let rendered = render_lines(&cell.display_lines(120)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 输出格式

```
• Called metrics.summary({"metric":"trace.latency","window":"15m"})
  └ Latency summary: p50=120ms, p95=480ms.
    No anomalies detected.
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/history_cell.rs` | MCP 工具调用单元格，测试位于 line 3395-3424 |
| `codex-rs/tui/src/exec_cell/mod.rs` | 文本格式化与截断工具 |
| `codex-rs/tui/src/wrapping.rs` | 自适应文本换行 |
| `rmcp::model::Content` | MCP 内容模型定义 |

### 多输出处理流程

```
CallToolResult { content: [block1, block2, ...] }
    ↓
for block in content:
    render_content_block(block)
        ↓
        match block.type:
            Text → format_and_truncate_tool_result(text)
            Image → "<image content>"
            Audio → "<audio content>"
            Resource → format!("embedded resource: {uri}")
            ResourceLink → format!("link: {uri}")
        ↓
    split('\n') → 按行分割
        ↓
    adaptive_wrap_line() → 自适应换行
        ↓
    添加到 detail_lines
```

## 依赖与外部交互

### 外部依赖

- `rmcp::model::Content`: MCP 内容类型定义
- `serde_json::Value`: JSON 内容块表示
- `codex_protocol::mcp::CallToolResult`: 工具调用结果类型

### 内部工具函数

```rust
// text_formatting.rs
pub fn format_and_truncate_tool_result(
    text: &str,
    max_lines: usize,
    width: usize,
) -> String;

// wrapping.rs
pub fn adaptive_wrap_line(line: &Line, opts: RtOptions) -> Vec<Line>;
```

## 风险、边界与改进建议

### 潜在风险

1. **输出顺序混淆**：多个输出块的顺序可能被用户误解为时间顺序
2. **视觉拥挤**：过多输出块可能导致界面拥挤
3. **类型混合显示**：文本与资源链接混合展示可能不够直观

### 边界情况

1. **空内容列表**：`content: []` 的处理
2. **大量输出块**：数十个输出块的性能与展示
3. **超长单行输出**：单行超过宽度限制的换行
4. **混合内容类型**：文本、图片、资源混合的输出

### 改进建议

1. **输出块分隔**：在不同输出块之间添加视觉分隔符
2. **类型图标**：为不同内容类型添加图标（📄 文本、🖼️ 图片、🔗 链接）
3. **折叠长输出**：超过一定行数的输出提供折叠功能
4. **结构化展示**：对于结构化数据（如 JSON），提供格式化展示选项
5. **输出计数**：显示"3个输出块"的指示器
6. **复制功能**：允许单独复制某个输出块的内容

### 相关测试

- `completed_mcp_tool_call_success_snapshot`：单输出块场景
- `completed_mcp_tool_call_multiple_outputs_snapshot`：多输出换行场景
- `completed_mcp_tool_call_wrapped_outputs_snapshot`：长文本换行场景
- `completed_mcp_tool_call_image_after_text_returns_extra_cell`：图片输出场景
