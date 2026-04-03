# Research: Completed MCP Tool Call Multiple Outputs Snapshot

## 场景与职责

此快照测试验证 Codex TUI 在 MCP 工具调用返回多个输出块且需要换行展示时的处理能力。当工具返回包含资源链接的多个输出时，UI 需要正确处理文本和链接的混合展示，并在有限宽度下进行适当的换行。

## 功能点目的

1. **混合内容展示**：同时展示文本输出和资源链接
2. **智能换行**：在窄宽度下正确处理长文本和链接的换行
3. **链接可视化**：清晰标识资源链接的类型和目标

## 具体技术实现

### 资源链接内容块处理

```rust
// history_cell.rs:1469-1479
rmcp::model::RawContent::Resource(resource) => {
    let uri = match resource.resource {
        rmcp::model::ResourceContents::TextResourceContents { uri, .. } => uri,
        rmcp::model::ResourceContents::BlobResourceContents { uri, .. } => uri,
    };
    format!("embedded resource: {uri}")
}
rmcp::model::RawContent::ResourceLink(link) => format!("link: {}", link.uri),
```

### 测试场景

```rust
// history_cell.rs:3325-3361
#[test]
fn completed_mcp_tool_call_multiple_outputs_snapshot() {
    let invocation = McpInvocation {
        server: "search".into(),
        tool: "find_docs".into(),
        arguments: Some(json!({
            "query": "ratatui styling",
            "limit": 3,
        })),
    };

    let result = CallToolResult {
        content: vec![
            text_block("Found styling guidance in styles.md and additional notes in CONTRIBUTING.md."),
            resource_link_block(  // 资源链接输出块
                "file:///docs/styles.md",
                "styles.md",
                Some("Styles"),
                Some("Link to styles documentation"),
            ),
        ],
        is_error: None,
        structured_content: None,
        meta: None,
    };

    let mut cell = new_active_mcp_tool_call("call-4".into(), invocation, true);
    cell.complete(Duration::from_millis(640), Ok(result));

    // 使用较窄宽度 (48) 强制换行
    let rendered = render_lines(&cell.display_lines(48)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 辅助函数

```rust
// history_cell.rs:2608-2625
fn resource_link_block(
    uri: &str,
    name: &str,
    title: Option<&str>,
    description: Option<&str>,
) -> serde_json::Value {
    serde_json::to_value(Content::resource_link(rmcp::model::RawResource {
        uri: uri.to_string(),
        name: name.to_string(),
        title: title.map(str::to_string),
        description: description.map(str::to_string),
        mime_type: None,
        size: None,
        icons: None,
        meta: None,
    }))
    .expect("resource link content should serialize")
}
```

### 输出格式

```
• Called
  └ search.find_docs({"query":"ratatui
        styling","limit":3})
    Found styling guidance in styles.md and
        additional notes in CONTRIBUTING.md.
    link: file:///docs/styles.md
```

注意：由于宽度限制 (48)，调用参数和输出文本都被换行了。

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/history_cell.rs` | MCP 单元格实现，测试位于 line 3325-3361 |
| `codex-rs/tui/src/wrapping.rs` | 自适应换行实现 (`adaptive_wrap_line`) |
| `rmcp::model` | MCP 内容模型（Content, RawResource, ResourceContents） |
| `codex_protocol::mcp::CallToolResult` | 工具调用结果类型 |

### 渲染流程

```
McpToolCallCell::display_lines(width: 48)
    ↓
format_mcp_invocation() → 格式化调用信息
    ↓
inline_invocation = false (宽度不足)
    ↓
单独渲染调用头 + 换行渲染参数
    ↓
for block in result.content:
    render_content_block(block)
        ↓
        text_block → format_and_truncate_tool_result()
        resource_link_block → "link: file:///..."
    ↓
    split('\n') → 按行分割
    ↓
    adaptive_wrap_line() with width-4
        ↓
    prefix_lines() 添加 "  └ " 和 "    " 前缀
```

## 依赖与外部交互

### 外部依赖

- `rmcp::model::{Content, RawResource, ResourceContents}`: MCP 资源模型
- `serde_json`: JSON 序列化
- `textwrap`: 文本换行算法

### 内部模块

```rust
// wrapping.rs
pub struct RtOptions {
    width: usize,
    initial_indent: Line<'static>,
    subsequent_indent: Line<'static>,
    // ...
}

pub fn adaptive_wrap_line(line: &Line, opts: RtOptions) -> Vec<Line>;
```

## 风险、边界与改进建议

### 潜在风险

1. **链接截断**：长 URI 在换行时可能被截断，导致链接失效
2. **资源类型丢失**：当前仅显示 URI，丢失 mime_type 等资源元数据
3. **点击交互缺失**：文本界面无法点击链接跳转

### 边界情况

1. **超长 URI**：超过宽度限制的 URI 展示
2. **无效 URI 格式**：非标准格式的资源链接
3. **大量资源链接**：单个调用返回数十个资源链接
4. **混合编码**：URI 中包含非 ASCII 字符的编码处理

### 改进建议

1. **链接可点击**：在支持超链接的终端中嵌入 OSC 8 超链接序列
2. **资源预览**：根据 mime_type 显示不同的资源图标
3. **URI 缩短**：显示缩短的 URI 但保留完整链接用于复制
4. **资源操作**：提供打开、复制、预览等操作选项
5. **分组展示**：将相同类型的资源链接分组展示
6. **懒加载**：对于大量资源，实现分页或懒加载

### 相关测试

- `completed_mcp_tool_call_multiple_outputs_inline_snapshot`：内联展示
- `completed_mcp_tool_call_success_snapshot`：基本成功场景
- `completed_mcp_tool_call_wrapped_outputs_snapshot`：长文本换行
