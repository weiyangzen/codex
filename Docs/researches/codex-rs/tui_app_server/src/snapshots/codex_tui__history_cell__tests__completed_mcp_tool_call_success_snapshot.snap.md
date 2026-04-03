# 研究文档：MCP 工具调用成功状态快照测试

## 场景与职责

该快照测试验证了 `McpToolCallCell` 在 MCP（Model Context Protocol）工具调用成功完成时的渲染行为。这是 MCP 工具调用展示的基础场景，确保成功的工具调用能够清晰、美观地展示给用户。

### 业务场景
用户通过 Codex 调用外部 MCP 工具（如文档搜索服务）并成功获得结果：
- 调用 `search.find_docs` 工具
- 传入查询参数 `{"query": "ratatui styling", "limit": 3}`
- 成功返回文档搜索结果

## 功能点目的

### 核心功能
- **成功状态可视化**：使用绿色标记（•）标识成功状态
- **调用信息展示**：清晰展示调用的服务器、工具名称和参数
- **结果内容展示**：格式化展示工具返回的内容

### 预期输出
```
• Called search.find_docs({"query":"ratatui styling","limit":3})
  └ Found styling guidance in styles.md
```

### 设计要点
1. **视觉反馈**：绿色标记给用户明确的成功反馈
2. **信息完整**：保留完整的调用签名，便于追溯
3. **层级清晰**：使用缩进区分调用信息和返回内容
4. **简洁美观**：单行展示调用信息，内容适当缩进

## 具体技术实现

### 数据结构

```rust
#[derive(Debug)]
pub(crate) struct McpToolCallCell {
    call_id: String,
    invocation: McpInvocation,
    start_time: Instant,
    duration: Option<Duration>,
    result: Option<Result<CallToolResult, String>>,
    animations_enabled: bool,
}

pub struct McpInvocation {
    pub server: String,
    pub tool: String,
    pub arguments: Option<serde_json::Value>,
}

pub struct CallToolResult {
    pub content: Vec<serde_json::Value>,  // 内容块列表
    pub is_error: Option<bool>,
    pub structured_content: Option<serde_json::Value>,
    pub meta: Option<serde_json::Value>,
}
```

### 测试构建

```rust
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
    // 完成调用，返回成功结果
    assert!(
        cell.complete(Duration::from_millis(1420), Ok(result))
            .is_none()  // 无图片输出，返回 None
    );

    let rendered = render_lines(&cell.display_lines(80)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 渲染逻辑

```rust
impl HistoryCell for McpToolCallCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        let status = self.success();
        
        // 1. 状态标记
        let bullet = match status {
            Some(true) => "•".green().bold(),   // 成功
            Some(false) => "•".red().bold(),    // 失败
            None => spinner(...),                // 进行中
        };
        
        // 2. 头部文本
        let header_text = if status.is_some() { "Called" } else { "Calling" };
        
        // 3. 格式化调用信息
        let invocation_line = line_to_static(&format_mcp_invocation(self.invocation.clone()));
        
        // 4. 判断行内/换行展示
        let inline_invocation = invocation_line.width() <= available_width;
        
        // 5. 渲染结果内容
        if let Some(Ok(result)) = &self.result {
            for block in &result.content {
                let text = Self::render_content_block(block, detail_wrap_width);
                // ...
            }
        }
    }
}

fn success(&self) -> Option<bool> {
    match self.result.as_ref() {
        Some(Ok(result)) => Some(!result.is_error.unwrap_or(false)),
        Some(Err(_)) => Some(false),
        None => None,
    }
}
```

### 调用信息格式化

```rust
fn format_mcp_invocation<'a>(invocation: McpInvocation) -> Line<'a> {
    let args_str = invocation
        .arguments
        .as_ref()
        .map(|v| serde_json::to_string(v).unwrap_or_else(|_| v.to_string()))
        .unwrap_or_default();

    vec![
        invocation.server.clone().cyan(),
        ".".into(),
        invocation.tool.cyan(),
        "(".into(),
        args_str.dim(),
        ")".into(),
    ]
    .into()
}
```

### 样式规范

| 元素 | 样式 | 说明 |
|------|------|------|
| 标记（•）| `.green().bold()` | 成功状态标识 |
| "Called" | `.bold()` | 操作完成状态 |
| 服务器名 | `.cyan()` | 服务器标识色 |
| 工具名 | `.cyan()` | 工具标识色 |
| 参数 | `.dim()` | 次要信息 |
| 结果内容 | `.dim()` | 内容使用暗淡色 |

## 关键代码路径与文件引用

### 主要文件
1. **`tui/src/history_cell.rs`**（第 3192-3218 行）
   - 测试用例 `completed_mcp_tool_call_success_snapshot`
   - 基础成功场景验证

2. **`tui/src/history_cell.rs`**（第 1404-1587 行）
   - `McpToolCallCell` 完整实现
   - 成功状态渲染逻辑

### 辅助函数
```rust
fn new_active_mcp_tool_call(call_id, invocation, animations_enabled) -> McpToolCallCell
fn format_mcp_invocation(invocation) -> Line
fn text_block(text) -> serde_json::Value
```

### 相关测试
- `completed_mcp_tool_call_error_snapshot` - 错误状态对比
- `completed_mcp_tool_call_multiple_outputs_*` - 多输出场景
- `active_mcp_tool_call_snapshot` - 进行中状态

## 依赖与外部交互

### 协议依赖
- `codex_protocol::protocol::McpInvocation` - MCP 调用协议
- `codex_protocol::mcp::CallToolResult` - 工具调用结果
- `rmcp::model::Content` - MCP 内容模型

### 渲染依赖
- `ratatui::style::Color` - 颜色系统
- `ratatui::style::Stylize` - 样式扩展

### 工具函数
- `crate::text_formatting::format_and_truncate_tool_result` - 结果格式化
- `crate::exec_cell::spinner` - 加载动画

## 风险、边界与改进建议

### 当前风险

1. **耗时信息未展示**
   - 测试中使用 `Duration::from_millis(1420)` 但未在输出中展示
   - 用户无法直观了解调用耗时

2. **内容截断风险**
   - `format_and_truncate_tool_result` 可能截断重要信息
   - 当前限制为 `TOOL_CALL_MAX_LINES`

3. **is_error 歧义**
   - `is_error: None` 和 `is_error: Some(false)` 都视为成功
   - 可能导致意外的成功标识

### 边界情况

| 场景 | 当前行为 | 评估 |
|------|----------|------|
| 空内容列表 | 仅显示调用信息 | ⚠️ 可能遗漏 |
| 超长参数 | 依赖换行机制 | ✅ |
| 特殊字符参数 | JSON 转义 | ✅ |
| 空参数 | 显示空括号 | ✅ |
| 结构化内容 | 未展示 | ⚠️ 需关注 |

### 改进建议

1. **耗时展示**
   ```
   • Called search.find_docs(...) (1.4s)
     └ Found styling guidance in styles.md
   ```

2. **内容展开/折叠**
   - 长内容默认折叠，显示前 N 行
   - 提供展开快捷键

3. **复制功能**
   - 支持复制调用参数
   - 支持复制返回结果

4. **结构化内容展示**
   - 如果存在 `structured_content`，提供结构化视图
   - 与文本内容视图切换

5. **元信息展示**
   - 展示 `meta` 字段中的有用信息
   - 如缓存状态、数据源等

### 相关测试建议

- [ ] 空内容列表的处理
- [ ] 超长内容（>1000 行）的性能
- [ ] 包含 ANSI 转义序列的内容
- [ ] 结构化内容的展示
- [ ] 元信息的展示
