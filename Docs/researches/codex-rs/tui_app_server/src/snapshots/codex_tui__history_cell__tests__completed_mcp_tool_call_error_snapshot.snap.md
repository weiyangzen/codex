# 研究文档：MCP 工具调用错误状态快照测试

## 场景与职责

该快照测试验证了 `McpToolCallCell` 在 MCP（Model Context Protocol）工具调用失败时的渲染行为。当 MCP 服务器返回错误或网络超时时，UI 需要清晰地展示错误信息，帮助用户理解发生了什么。

### 业务场景
用户通过 Codex 调用外部 MCP 工具（如文档搜索服务）时可能遇到：
- 网络超时（network timeout）
- 服务器内部错误
- 认证失败
- 参数验证错误

## 功能点目的

### 核心功能
- **错误状态可视化**：使用红色标记（•）和 "Error:" 前缀明确标识错误
- **错误信息展示**：清晰展示错误描述
- **调用信息保留**：即使失败也保留调用的工具名称和参数

### 预期输出
```
• Called search.find_docs({"query":"ratatui styling","limit":3})
  └ Error: network timeout
```

### 设计要点
1. **视觉区分**：错误状态使用红色（red）标记，与成功状态的绿色形成对比
2. **信息完整**：保留完整的调用签名，便于调试
3. **简洁明了**：错误信息单行展示，避免过多视觉噪音

## 具体技术实现

### 数据结构

```rust
// McpToolCallCell - MCP 工具调用单元格
#[derive(Debug)]
pub(crate) struct McpToolCallCell {
    call_id: String,
    invocation: McpInvocation,           // 调用信息
    start_time: Instant,
    duration: Option<Duration>,          // 执行耗时
    result: Option<Result<CallToolResult, String>>,  // 执行结果
    animations_enabled: bool,
}

// McpInvocation - MCP 调用详情
pub struct McpInvocation {
    pub server: String,      // 服务器名称
    pub tool: String,        // 工具名称
    pub arguments: Option<serde_json::Value>,  // 参数
}
```

### 测试构建

```rust
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
    // 模拟调用失败，返回错误字符串
    assert!(
        cell.complete(Duration::from_secs(2), Err("network timeout".into()))
            .is_none()
    );

    let rendered = render_lines(&cell.display_lines(80)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 渲染逻辑

```rust
impl HistoryCell for McpToolCallCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        let status = self.success();  // Some(false) 表示错误
        
        // 1. 根据状态选择标记颜色
        let bullet = match status {
            Some(true) => "•".green().bold(),
            Some(false) => "•".red().bold(),   // 错误状态
            None => spinner(...),
        };
        
        // 2. 渲染调用头
        let header_text = "Called";  // 已完成调用
        
        // 3. 渲染错误详情
        if let Some(result) = &self.result {
            match result {
                Err(err) => {
                    let err_text = format_and_truncate_tool_result(
                        &format!("Error: {err}"),
                        TOOL_CALL_MAX_LINES,
                        width as usize,
                    );
                    // 使用 dim 样式显示错误
                    let err_line = Line::from(err_text.dim());
                    // ...
                }
                Ok(...) => { /* 成功处理 */ }
            }
        }
    }
}
```

### 样式规范

| 元素 | 样式 | 说明 |
|------|------|------|
| 标记（•）| `.red().bold()` | 错误状态的视觉提示 |
| "Called" | `.bold()` | 操作类型强调 |
| 工具名 | `.cyan()` | 服务器和工具名使用青色 |
| 参数 | `.dim()` | 参数使用暗淡色 |
| 错误信息 | `.dim()` | 错误详情使用暗淡色 |

## 关键代码路径与文件引用

### 主要文件
1. **`tui/src/history_cell.rs`**（第 3303-3322 行）
   - 测试用例 `completed_mcp_tool_call_error_snapshot`
   - 构建失败的 MCP 工具调用场景

2. **`tui/src/history_cell.rs`**（第 1404-1587 行）
   - `McpToolCallCell` 结构体定义
   - `HistoryCell` trait 实现
   - 错误状态渲染逻辑

### 辅助函数
```rust
fn format_mcp_invocation(invocation: McpInvocation) -> Line<'a>
fn format_and_truncate_tool_result(text: &str, max_lines: usize, width: usize) -> String
```

### 相关快照
- `tui/src/snapshots/codex_tui__history_cell__tests__completed_mcp_tool_call_error_snapshot.snap`

## 依赖与外部交互

### 协议依赖
- `codex_protocol::protocol::McpInvocation` - MCP 调用协议类型
- `codex_protocol::mcp::CallToolResult` - 工具调用结果

### 渲染依赖
- `ratatui::style::Color` - 颜色定义
- `ratatui::style::Stylize` - 样式扩展方法

### 工具函数
- `crate::text_formatting::format_and_truncate_tool_result` - 结果格式化与截断
- `crate::exec_cell::TOOL_CALL_MAX_LINES` - 最大输出行数限制

## 风险、边界与改进建议

### 当前风险

1. **错误信息泄露敏感信息**
   - 风险：MCP 服务器可能返回包含敏感信息的错误
   - 现状：直接展示原始错误字符串
   - 建议：增加错误信息脱敏处理

2. **长错误信息处理**
   - 风险：错误信息可能很长，超出显示区域
   - 缓解：`format_and_truncate_tool_result` 提供截断功能

3. **多行错误信息**
   - 风险：某些错误可能包含换行符
   - 现状：使用 `split('\n')` 处理多行

### 边界情况

| 场景 | 当前行为 | 评估 |
|------|----------|------|
| 空错误字符串 | 显示 "Error:" | ⚠️ 不够友好 |
| 超长错误（>1000 字符）| 截断显示 | ✅ 合理 |
| 包含换行符的错误 | 分行显示 | ✅ 清晰 |
| Unicode 错误信息 | 正常显示 | ✅ 支持 |
| 网络超时 vs 业务错误 | 统一显示 | ⚠️ 可区分 |

### 改进建议

1. **错误分类与图标**
   ```rust
   pub enum McpErrorType {
       NetworkTimeout,    // ⏱️
       Authentication,    // 🔒
       Validation,        // ⚠️
       ServerError,       // 🔥
       Unknown,           // ❌
   }
   ```

2. **可展开的错误详情**
   - 默认显示错误摘要
   - 支持按键展开完整错误堆栈

3. **重试机制提示**
   ```
   • Called search.find_docs(...)
     └ Error: network timeout (Press 'r' to retry)
   ```

4. **错误日志链接**
   - 提供查看详细日志的快捷方式
   - 帮助用户和开发者诊断问题

5. **国际化支持**
   - 常见错误类型提供本地化描述
   - 原始错误作为技术详情

### 相关测试建议

- [ ] 不同类型的错误（超时、认证、验证等）
- [ ] 空错误消息的处理
- [ ] 包含特殊字符的错误消息
- [ ] 多语言错误消息
- [ ] 超长错误消息的截断行为
