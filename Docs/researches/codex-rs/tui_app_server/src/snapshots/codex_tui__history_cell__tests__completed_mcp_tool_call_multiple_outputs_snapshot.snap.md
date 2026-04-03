# 研究文档：MCP 工具调用多输出换行展示快照测试

## 场景与职责

该快照测试验证了 `McpToolCallCell` 在 MCP 工具调用返回多个输出内容块时的**换行展示**行为。当终端宽度不足以在一行内完整展示工具调用信息时，UI 会自动切换到换行模式，将调用参数和输出内容分行展示，确保可读性。

### 业务场景
在较窄的终端窗口中使用 Codex：
- 终端宽度有限（如 48 列）
- 工具调用参数较长（如 JSON 参数）
- 需要清晰展示多个输出内容块

### 与行内展示的区别
本测试使用宽度 48，强制触发换行模式，与 `completed_mcp_tool_call_multiple_outputs_inline_snapshot`（宽度 120）形成对比。

## 功能点目的

### 核心功能
- **响应式布局**：根据可用宽度自动选择展示模式
- **参数换行**：长参数自动换行并正确缩进
- **多内容块展示**：每个 content block 独立成行

### 预期输出
```
• Called
  └ search.find_docs({"query":"ratatui
        styling","limit":3})
    Found styling guidance in styles.md and
        additional notes in CONTRIBUTING.md.
    link: file:///docs/styles.md
```

### 布局特点
1. **头部换行**："Called" 单独成行，参数换行缩进
2. **参数换行**：JSON 参数在逗号后换行，保持可读性
3. **内容缩进**：每个输出块有清晰的前缀标识

## 具体技术实现

### 测试数据结构

```rust
#[test]
fn completed_mcp_tool_call_multiple_outputs_snapshot() {
    let invocation = McpInvocation {
        server: "search".into(),
        tool: "find_docs".into(),
        arguments: Some(json!({
            "query": "ratatui styling",  // 较长的查询参数
            "limit": 3,
        })),
    };

    // 包含文本和资源链接的混合结果
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
        is_error: None,
        structured_content: None,
        meta: None,
    };

    let mut cell = new_active_mcp_tool_call("call-4".into(), invocation, true);
    cell.complete(Duration::from_millis(640), Ok(result));

    // 使用较窄宽度（48）触发换行模式
    let rendered = render_lines(&cell.display_lines(48)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 换行决策逻辑

```rust
let invocation_line = line_to_static(&format_mcp_invocation(self.invocation.clone()));
let mut compact_spans = vec![bullet.clone(), " ".into(), header_text.bold(), " ".into()];
let mut compact_header = Line::from(compact_spans.clone());
let reserved = compact_header.width();

// 判断是否适合行内展示
let inline_invocation =
    invocation_line.width() <= (width as usize).saturating_sub(reserved);

if inline_invocation {
    // 行内模式：头部 + 调用信息在同一行
    compact_header.extend(invocation_line.spans.clone());
    lines.push(compact_header);
} else {
    // 换行模式：头部单独成行
    compact_spans.pop(); // 移除尾部空格
    lines.push(Line::from(compact_spans));
    
    // 调用信息换行展示，使用缩进
    let opts = RtOptions::new((width as usize).saturating_sub(4))
        .initial_indent("".into())
        .subsequent_indent("    ".into());
    let wrapped = adaptive_wrap_line(&invocation_line, opts);
    let body_lines: Vec<Line<'static>> = wrapped.iter().map(line_to_static).collect();
    lines.extend(prefix_lines(body_lines, "  └ ".dim(), "    ".into()));
}
```

### 资源链接渲染

```rust
fn render_content_block(block: &serde_json::Value, width: usize) -> String {
    let content = serde_json::from_value::<rmcp::model::Content>(block.clone())?;
    
    match content.raw {
        rmcp::model::RawContent::Text(text) => {
            format_and_truncate_tool_result(&text.text, TOOL_CALL_MAX_LINES, width)
        }
        rmcp::model::RawContent::ResourceLink(link) => {
            format!("link: {}", link.uri)
        }
        // ... 其他类型
    }
}
```

### 缩进层级

| 层级 | 前缀 | 用途 |
|------|------|------|
| 1 | "• Called" | 操作头部 |
| 2 | "  └ " | 调用信息（首行）|
| 2+ | "    " | 调用信息（续行）|
| 3 | "    " | 输出内容 |

## 关键代码路径与文件引用

### 主要文件
1. **`tui/src/history_cell.rs`**（第 3325-3361 行）
   - 测试用例 `completed_mcp_tool_call_multiple_outputs_snapshot`
   - 构建包含文本和资源链接的混合输出

2. **`tui/src/history_cell.rs`**（第 1490-1587 行）
   - `McpToolCallCell::display_lines()` 完整实现
   - 换行模式的具体处理逻辑

### 辅助函数
```rust
fn format_mcp_invocation(invocation: McpInvocation) -> Line<'a>
fn resource_link_block(uri, name, title, description) -> serde_json::Value
fn prefix_lines(lines, initial_prefix, subsequent_prefix) -> Vec<Line<'static>>
```

### 相关测试对比
| 测试 | 宽度 | 调用展示 | 内容类型 |
|------|------|----------|----------|
| `completed_mcp_tool_call_success_snapshot` | 80 | 行内 | 单文本 |
| `completed_mcp_tool_call_multiple_outputs_inline_snapshot` | 120 | 行内 | 多文本 |
| 本测试 | 48 | 换行 | 文本+资源 |

## 依赖与外部交互

### MCP 协议
- `rmcp::model::Content` - MCP 内容模型
- `rmcp::model::RawContent::ResourceLink` - 资源链接类型
- `rmcp::model::RawResource` - 资源元数据

### 渲染工具
- `crate::wrapping::adaptive_wrap_line` - 自适应换行
- `crate::render::line_utils::prefix_lines` - 行前缀添加

### 格式化
- `crate::text_formatting::format_and_truncate_tool_result` - 工具结果格式化

## 风险、边界与改进建议

### 当前风险

1. **换行位置不可控**
   - 风险：JSON 参数可能在任意位置被截断
   - 示例：`{"query":"ratatui` 后换行，破坏 JSON 结构
   - 建议：对 JSON 参数使用智能换行（在逗号、冒号后）

2. **缩进层级过深**
   - 风险：窄宽度下缩进占用过多空间
   - 现状：4 空格缩进，在 48 宽度下可用空间仅 44

3. **资源链接截断**
   - 风险：长 URI 可能被截断，影响可点击性
   - 现状：依赖 `format_and_truncate_tool_result`

### 边界情况

| 场景 | 当前行为 | 评估 |
|------|----------|------|
| 极窄宽度（<20）| 可能无法正确渲染 | ⚠️ 需测试 |
| 超长 JSON 参数 | 多行换行 | ✅ |
| 多行文本内容 | 保持换行结构 | ✅ |
| 混合内容类型 | 按顺序渲染 | ✅ |
| 空参数 | 显示空括号 | ✅ |

### 改进建议

1. **JSON 智能换行**
   ```rust
   fn wrap_json_params(json: &str, width: usize) -> Vec<String> {
       // 优先在逗号后换行
       // 其次在冒号后换行
       // 避免在字符串中间换行
   }
   ```

2. **动态缩进**
   ```rust
   // 根据宽度调整缩进大小
   let indent_size = if width < 40 { 2 } else { 4 };
   ```

3. **资源链接优化**
   ```
   // 当前
   link: file:///docs/styles.md
   
   // 优化：显示为可点击链接，缩短显示文本
   [styles.md](file:///docs/styles.md)
   ```

4. **折叠长参数**
   - 当参数超过一定长度时，默认折叠
   - 提供展开按钮或快捷键

5. **语法高亮**
   - 对 JSON 参数进行语法高亮
   - 提高可读性

### 测试覆盖建议

- [ ] 极窄宽度（20-30 列）的渲染行为
- [ ] 超长 JSON 参数（>500 字符）
- [ ] 嵌套 JSON 参数的换行
- [ ] 包含特殊字符的 URI
- [ ] 大量资源链接（>10 个）
