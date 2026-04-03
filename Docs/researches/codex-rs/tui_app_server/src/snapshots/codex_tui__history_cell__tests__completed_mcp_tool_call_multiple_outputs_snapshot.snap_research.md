# completed_mcp_tool_call_multiple_outputs_snapshot 研究文档

## 场景与职责

该测试验证 MCP 工具调用成功且返回多个输出块时的**换行渲染**行为。当工具调用的参数较长或终端宽度较窄时，TUI 采用换行布局，将工具调用和结果分行显示，确保内容完整可读。

## 功能点目的

1. **自适应布局**: 根据内容长度和终端宽度自动选择内联或换行布局
2. **内容完整性**: 确保长参数和输出不会被截断或挤压
3. **树状结构**: 使用 "└" 和 "  " 等字符构建视觉树状层次，清晰展示调用-结果关系

**Snapshot 内容示例**:
```
• Called
  └ search.find_docs({"query":"ratatui
        styling","limit":3})
    Found styling guidance in styles.md and
        additional notes in CONTRIBUTING.md.
    link: file:///docs/styles.md
```

## 具体技术实现

### 换行布局逻辑

```rust
// history_cell.rs 第 1500-1520 行
let inline_invocation = invocation_line.width() <= (width as usize).saturating_sub(reserved);

if inline_invocation {
    compact_header.extend(invocation_line.spans.clone());
    lines.push(compact_header);
} else {
    // 换行显示模式
    compact_spans.pop(); // 移除尾部空格
    lines.push(Line::from(compact_spans));

    let opts = RtOptions::new((width as usize).saturating_sub(4))
        .initial_indent("".into())
        .subsequent_indent("    ".into());
    let wrapped = adaptive_wrap_line(&invocation_line, opts);
    let body_lines: Vec<Line<'static>> = wrapped.iter().map(line_to_static).collect();
    lines.extend(prefix_lines(body_lines, "  └ ".dim(), "    ".into()));
}
```

### 多输出块与资源链接处理

```rust
// 处理文本内容和资源链接混合的输出
let result = CallToolResult {
    content: vec![
        text_block("Found styling guidance in styles.md and additional notes in CONTRIBUTING.md."),
        resource_link_block(
            "file:///docs/styles.md",
            "styles.md",
            Some("Styles"),
            Some("Link to styles documentation"),
        ),
    ],
    // ...
};
```

### 资源链接渲染

```rust
// history_cell.rs 第 1472-1479 行
rmcp::model::RawContent::Resource(resource) => {
    let uri = match resource.resource {
        rmcp::model::ResourceContents::TextResourceContents { uri, .. } => uri,
        rmcp::model::ResourceContents::BlobResourceContents { uri, .. } => uri,
    };
    format!("embedded resource: {uri}")
}
rmcp::model::RawContent::ResourceLink(link) => format!("link: {}", link.uri),
```

### 测试代码

```rust
// history_cell.rs 第 3325-3361 行
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
            text_block(
                "Found styling guidance in styles.md and additional notes in CONTRIBUTING.md.",
            ),
            resource_link_block(
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
    assert!(
        cell.complete(Duration::from_millis(640), Ok(result))
            .is_none()
    );

    let rendered = render_lines(&cell.display_lines(48)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

## 关键代码路径与文件引用

| 文件路径 | 行号范围 | 说明 |
|---------|---------|------|
| `codex-rs/tui/src/history_cell.rs` | 1500-1520 | 内联/换行布局判断 |
| `codex-rs/tui/src/history_cell.rs` | 1513-1519 | 换行布局的具体实现 |
| `codex-rs/tui/src/history_cell.rs` | 1472-1479 | 资源内容渲染 |
| `codex-rs/tui/src/history_cell.rs` | 2608-2625 | `resource_link_block` 测试辅助函数 |
| `codex-rs/tui/src/history_cell.rs` | 3325-3361 | 测试用例定义 |
| `codex-rs/tui/src/render/line_utils.rs` | - | `prefix_lines` 函数实现 |

## 依赖与外部交互

### 外部依赖

1. **rmcp crate**: 提供 `Resource`, `ResourceContents`, `ResourceLink` 等类型
2. **serde_json**: JSON 处理
3. **ratatui**: UI 组件

### 关键辅助函数

```rust
// line_utils.rs
pub fn prefix_lines(
    lines: Vec<Line<'static>>,
    initial_prefix: Span<'static>,
    subsequent_prefix: Span<'static>,
) -> Vec<Line<'static>>
```

### 测试辅助函数

```rust
// 第 2608-2625 行
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

## 风险、边界与改进建议

### 当前风险与边界

1. **缩进层级复杂**: 当调用参数和输出都换行时，缩进层级较深（4空格起步），可能影响可读性
2. **资源链接显示**: 当前仅显示 URI 字符串，无点击跳转或复制功能
3. **宽度计算精度**: `saturating_sub(4)` 的魔法数字可能与实际前缀宽度不完全匹配

### 边界情况

| 场景 | 当前行为 | 潜在问题 |
|------|---------|---------|
| 极窄终端（<20列） | 强制换行 | 内容可能无法显示 |
| 混合文本和资源 | 顺序显示 | 关联性不够直观 |
| 资源 URI 极长 | 换行显示 | URI 可读性差 |

### 改进建议

1. **URI 缩短显示**: 对于长 URI，显示为可点击的短链接
   ```rust
   let display_uri = if uri.len() > 40 {
       format!("{}...{}", &uri[..15], &uri[uri.len()-20..])
   } else { uri.to_string() };
   ```

2. **资源预览**: 对于文本资源，显示前N行预览而非仅 URI

3. **交互式资源**: 支持快捷键复制 URI 或在浏览器中打开

4. **缩进优化**: 考虑使用可变缩进或视觉引导线替代固定空格

5. **内容分组**: 当输出包含多个资源时，添加分组标题
   ```
   Resources:
   • file:///docs/styles.md
   • file:///CONTRIBUTING.md
   ```
