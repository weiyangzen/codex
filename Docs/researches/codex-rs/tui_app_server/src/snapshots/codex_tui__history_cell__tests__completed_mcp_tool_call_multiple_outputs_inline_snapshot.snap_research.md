# completed_mcp_tool_call_multiple_outputs_inline_snapshot 研究文档

## 场景与职责

该测试验证 MCP 工具调用成功且返回多个输出块时的**内联渲染**行为。当工具调用的参数和输出都能在单行内完整显示时，TUI 采用紧凑的内联布局，节省垂直空间并提供更简洁的视觉体验。

## 功能点目的

1. **空间优化**: 当内容较短时，将工具调用和结果显示在同一行，减少行数占用
2. **视觉简洁**: 避免不必要的换行和缩进，保持历史记录的紧凑性
3. **内容聚合**: 将多个输出块（如多行文本）合并显示，用换行分隔

**Snapshot 内容示例**:
```
• Called metrics.summary({"metric":"trace.latency","window":"15m"})
  └ Latency summary: p50=120ms, p95=480ms.
    No anomalies detected.
```

## 具体技术实现

### 内联布局判断逻辑

```rust
// history_cell.rs 第 1500-1520 行
let invocation_line = line_to_static(&format_mcp_invocation(self.invocation.clone()));
let mut compact_spans = vec![bullet.clone(), " ".into(), header_text.bold(), " ".into()];
let mut compact_header = Line::from(compact_spans.clone());
let reserved = compact_header.width();

// 判断调用描述是否能在剩余空间内内联显示
let inline_invocation = invocation_line.width() <= (width as usize).saturating_sub(reserved);

if inline_invocation {
    compact_header.extend(invocation_line.spans.clone());
    lines.push(compact_header);
} else {
    // 换行显示...
}
```

### 多输出块处理

```rust
// history_cell.rs 第 1526-1543 行
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
```

### 内容块渲染

```rust
// history_cell.rs 第 1454-1481 行
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
        // ...
    }
}
```

### 测试代码

```rust
// history_cell.rs 第 3395-3424 行
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
            text_block("No anomalies detected."),
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

## 关键代码路径与文件引用

| 文件路径 | 行号范围 | 说明 |
|---------|---------|------|
| `codex-rs/tui/src/history_cell.rs` | 1500-1520 | 内联布局判断与渲染 |
| `codex-rs/tui/src/history_cell.rs` | 1526-1543 | 多输出块处理逻辑 |
| `codex-rs/tui/src/history_cell.rs` | 1454-1481 | `render_content_block` 方法 |
| `codex-rs/tui/src/history_cell.rs` | 1563-1570 | 详情行前缀处理 |
| `codex-rs/tui/src/history_cell.rs` | 3395-3424 | 测试用例定义 |
| `codex-rs/tui/src/text_formatting.rs` | - | `format_and_truncate_tool_result` 实现 |

## 依赖与外部交互

### 外部依赖

1. **rmcp crate**: 提供 MCP 内容模型 (`Content`, `RawContent`)
2. **serde_json**: JSON 序列化/反序列化
3. **ratatui**: UI 渲染组件
4. **textwrap**: 文本换行处理（通过 `RtOptions`）

### 关键辅助函数

```rust
// line_utils.rs
pub fn line_to_static(line: &Line) -> Line<'static>

// wrapping.rs
pub struct RtOptions {
    width: usize,
    initial_indent: Line<'static>,
    subsequent_indent: Line<'static>,
}
```

### 测试辅助函数

```rust
// 第 2604-2606 行
fn text_block(text: &str) -> serde_json::Value {
    serde_json::to_value(Content::text(text)).expect("text content should serialize")
}
```

## 风险、边界与改进建议

### 当前风险与边界

1. **宽度阈值敏感**: 内联/换行切换依赖于固定的宽度计算，可能在特定终端宽度下产生不稳定的布局
2. **内容块数量限制**: 大量输出块可能导致历史记录过长，当前实现无折叠机制
3. **文本截断**: `format_and_truncate_tool_result` 可能截断重要信息

### 边界情况

| 场景 | 当前行为 | 潜在问题 |
|------|---------|---------|
| 单个输出块极长 | 自动换行 | 可能占用过多屏幕空间 |
| 多个短输出块 | 每块一行 | 块数多时行数膨胀 |
| 混合内容类型 | 文本显示，其他标记为 `<xxx content>` | 信息丢失 |

### 改进建议

1. **智能折叠**: 当输出块超过一定数量时，提供 "显示更多/收起" 功能
   ```rust
   const MAX_VISIBLE_BLOCKS: usize = 3;
   if content.len() > MAX_VISIBLE_BLOCKS {
       // 显示前3块 + "... and N more"
   }
   ```

2. **内容类型图标**: 为不同类型的内容块添加视觉图标
   ```rust
   match content.raw {
       RawContent::Text(_) => "📝",
       RawContent::Image(_) => "🖼️",
       RawContent::Resource(_) => "📎",
   }
   ```

3. **可点击展开**: 对于被截断的内容，支持点击或快捷键展开完整内容

4. **结构化显示**: 对于 JSON 等结构化数据，提供格式化/语法高亮选项

5. **性能优化**: 对于大量输出块的场景，考虑虚拟滚动或延迟加载
