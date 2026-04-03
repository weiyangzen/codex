# Active MCP Tool Call Snapshot 研究文档

## 场景与职责

此快照测试验证了**MCP（Model Context Protocol）工具调用正在进行中**的状态渲染。当 Codex 调用外部 MCP 工具时，需要向用户展示调用的进度和状态。

测试场景：
- 调用 `search` 服务器的 `find_docs` 工具
- 参数：`{"query":"ratatui styling","limit":3}`
- 状态：进行中（显示 spinner）

## 功能点目的

### MCP 工具调用展示

```
• Calling search.find_docs({"query":"ratatui styling","limit":3})
```

关键信息：
- **状态指示**：`Calling` 表示进行中（vs `Called` 表示已完成）
- **服务器名**：`search`
- **工具名**：`find_docs`
- **参数**：JSON 格式的参数

### 进行中 vs 已完成

| 状态 | Header | 图标 |
|------|--------|------|
| 进行中 | `Calling` | Spinner（旋转动画）|
| 成功完成 | `Called` | `•`（绿色）|
| 失败 | `Called` | `•`（红色）|

## 具体技术实现

### 数据结构

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

#[derive(Debug, Clone)]
pub(crate) struct McpInvocation {
    pub server: String,
    pub tool: String,
    pub arguments: Option<serde_json::Value>,
}
```

### 渲染逻辑

```rust
impl HistoryCell for McpToolCallCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        let mut lines: Vec<Line<'static>> = Vec::new();
        let status = self.success();
        
        // 根据状态选择图标
        let bullet = match status {
            Some(true) => "•".green().bold(),
            Some(false) => "•".red().bold(),
            None => spinner(Some(self.start_time), self.animations_enabled),
        };
        
        // 根据状态选择 header 文本
        let header_text = if status.is_some() { "Called" } else { "Calling" };
        
        // 格式化调用信息
        let invocation_line = line_to_static(&format_mcp_invocation(self.invocation.clone()));
        
        // 决定是内联显示还是换行显示
        let mut compact_spans = vec![bullet.clone(), " ".into(), header_text.bold(), " ".into()];
        let mut compact_header = Line::from(compact_spans.clone());
        let reserved = compact_header.width();
        
        let inline_invocation = invocation_line.width() <= (width as usize).saturating_sub(reserved);
        
        if inline_invocation {
            // 内联显示：header + 调用信息在一行
            compact_header.extend(invocation_line.spans.clone());
            lines.push(compact_header);
        } else {
            // 换行显示：header 单独一行，调用信息在下一行缩进
            compact_spans.pop();
            lines.push(Line::from(compact_spans));
            
            let opts = RtOptions::new((width as usize).saturating_sub(4))
                .initial_indent("".into())
                .subsequent_indent("    ".into());
            let wrapped = adaptive_wrap_line(&invocation_line, opts);
            let body_lines: Vec<Line<'static>> = wrapped.iter().map(line_to_static).collect();
            lines.extend(prefix_lines(body_lines, "  └ ".dim(), "    ".into()));
        }
        
        // 渲染结果详情...
        lines
    }
}
```

### 调用信息格式化

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

输出格式：`server.tool(args)`

示例：`search.find_docs({"query":"ratatui styling","limit":3})`

### Spinner 动画

```rust
fn spinner(start_time: Option<Instant>, animations_enabled: bool) -> Span<'static> {
    if !animations_enabled || start_time.is_none() {
        return "•".dim().into();
    }
    
    // 基于时间的旋转动画
    let elapsed = start_time.unwrap().elapsed().as_millis() as usize;
    let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
    let frame = frames[elapsed / 80 % frames.len()];
    frame.cyan().into()
}
```

### 动画 Tick

```rust
fn transcript_animation_tick(&self) -> Option<u64> {
    if !self.animations_enabled || self.result.is_some() {
        return None;  // 已完成，无需动画
    }
    Some((self.start_time.elapsed().as_millis() / 50) as u64)
}
```

返回变化的 tick 值触发 transcript 缓存刷新，实现动画效果。

## 关键代码路径与文件引用

### 核心代码

| 结构体/函数 | 文件 | 行号 | 职责 |
|------------|------|------|------|
| `McpToolCallCell` | `history_cell.rs` | 1399-1406 | MCP 工具调用单元格 |
| `display_lines` | `history_cell.rs` | 1484-1573 | 渲染逻辑 |
| `format_mcp_invocation` | `history_cell.rs` | 2515-2534 | 格式化调用信息 |
| `spinner` | `exec_cell.rs` | （相关） | 旋转动画 |
| `new_active_mcp_tool_call` | `history_cell.rs` | 1583-1589 | 构造函数 |

### 测试代码

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

### 相关测试

| 测试名 | 说明 |
|--------|------|
| `active_mcp_tool_call_snapshot` | 进行中状态快照 |
| `completed_mcp_tool_call_success_snapshot` | 成功完成快照 |
| `completed_mcp_tool_call_error_snapshot` | 失败状态快照 |
| `completed_mcp_tool_call_image_after_text_returns_extra_cell` | 图片输出处理 |

## 依赖与外部交互

### MCP 协议集成

- `codex_protocol::mcp::CallToolResult`：工具调用结果
- `codex_protocol::protocol::McpInvocation`：调用请求
- `rmcp::model::Content`：内容块（文本、图片、资源等）

### 内容渲染

```rust
fn render_content_block(block: &serde_json::Value, width: usize) -> String {
    let content = serde_json::from_value::<rmcp::model::Content>(block.clone())?;
    
    match content.raw {
        RawContent::Text(text) => format_and_truncate_tool_result(&text.text, ...),
        RawContent::Image(_) => "<image content>".to_string(),
        RawContent::Audio(_) => "<audio content>".to_string(),
        RawContent::Resource(resource) => format!("embedded resource: {uri}"),
        RawContent::ResourceLink(link) => format!("link: {}", link.uri),
    }
}
```

## 风险、边界与改进建议

### 边界情况

1. **超长参数**：
   - JSON 参数可能非常长
   - 当前实现会换行并缩进显示
   - 可能需要截断或折叠

2. **特殊字符**：
   - 参数中可能包含换行符
   - 需要正确处理转义

3. **无参数调用**：
   - `arguments` 为 `None` 或 `{}`
   - 显示为 `server.tool()`

4. **快速完成**：
   - 如果调用瞬间完成
   - 用户可能看不到 `Calling` 状态

### 潜在问题

1. **Spinner 性能**：
   - 每 50ms 触发一次 transcript 刷新
   - 大量并发调用时可能影响性能

2. **结果渲染**：
   - 工具结果可能包含大量文本
   - 当前有 `TOOL_CALL_MAX_LINES` 限制
   - 超出限制时截断显示

3. **图片输出**：
   - 图片需要特殊处理
   - 当前返回额外的 `CompletedMcpToolCallWithImageOutput` cell

### 改进建议

1. **参数展示优化**：
   - 对长参数进行折叠，显示 `...` 可展开
   - 对嵌套 JSON 进行格式化显示
   - 添加参数类型提示

2. **进度指示**：
   - 对于长时间运行的工具，显示进度百分比
   - 添加已运行时间

3. **结果展示**：
   - 支持 Markdown 渲染
   - 代码块语法高亮
   - 表格格式化

4. **交互增强**：
   - 点击展开/折叠结果
   - 复制结果到剪贴板
   - 重新运行工具按钮

5. **错误处理**：
   - 更详细的错误信息展示
   - 错误堆栈折叠/展开
   - 重试机制

6. **可访问性**：
   - 动画可配置（考虑减少动画偏好）
   - 屏幕阅读器支持
