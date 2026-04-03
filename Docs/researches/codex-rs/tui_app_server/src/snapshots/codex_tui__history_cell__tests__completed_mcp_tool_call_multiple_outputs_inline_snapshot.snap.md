# 研究文档：MCP 工具调用多输出行内展示快照测试

## 场景与职责

该快照测试验证了 `McpToolCallCell` 在 MCP 工具调用返回多个输出内容块（content blocks）时的行内展示行为。当工具调用返回的内容较短且可以在一行内完整展示时，UI 采用紧凑的行内格式，减少垂直空间的占用。

### 业务场景
用户调用 MCP 工具（如 metrics 服务）获取监控数据：
- 工具返回多个简短的数据点
- 每个数据点都是一个独立的 content block
- 内容总长度适合在一行内展示

示例场景：
```json
{
  "content": [
    {"type": "text", "text": "Latency summary: p50=120ms, p95=480ms."},
    {"type": "text", "text": "No anomalies detected."}
  ]
}
```

## 功能点目的

### 核心功能
- **多内容块支持**：处理包含多个 content block 的工具调用结果
- **行内紧凑展示**：当内容适合时，在同一行展示多个输出
- **智能布局决策**：根据内容长度自动选择行内或换行展示

### 预期输出
```
• Called metrics.summary({"metric":"trace.latency","window":"15m"})
  └ Latency summary: p50=120ms, p95=480ms.
    No anomalies detected.
```

### 设计特点
1. **紧凑布局**：工具调用和参数在同一行展示
2. **内容缩进**：输出内容使用 "  └ " 和 "    " 前缀形成层级
3. **多行支持**：每个 content block 单独一行，保持清晰

## 具体技术实现

### 测试数据结构

```rust
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

    // 包含两个文本内容块的结果
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
    cell.complete(Duration::from_millis(320), Ok(result));

    // 使用较宽宽度（120）确保行内展示
    let rendered = render_lines(&cell.display_lines(120)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 行内展示判定逻辑

```rust
impl HistoryCell for McpToolCallCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        // 1. 构建调用描述行
        let invocation_line = line_to_static(&format_mcp_invocation(self.invocation.clone()));
        
        // 2. 计算预留宽度（标记 + "Called" + 空格）
        let mut compact_spans = vec![bullet.clone(), " ".into(), header_text.bold(), " ".into()];
        let mut compact_header = Line::from(compact_spans.clone());
        let reserved = compact_header.width();
        
        // 3. 判断是否适合行内展示
        let inline_invocation =
            invocation_line.width() <= (width as usize).saturating_sub(reserved);
        
        if inline_invocation {
            // 行内展示：将调用信息附加到头部
            compact_header.extend(invocation_line.spans.clone());
            lines.push(compact_header);
        } else {
            // 换行展示：调用信息单独成行
            // ...
        }
    }
}
```

### 内容块渲染流程

```rust
// 遍历所有 content block
for block in content {
    let text = Self::render_content_block(block, detail_wrap_width);
    
    // 处理多行文本
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
```

### 宽度参数分析

| 参数 | 值 | 说明 |
|------|-----|------|
| 测试宽度 | 120 | 足够宽以容纳行内展示 |
| 预留宽度 | ~12 | "• Called " 的宽度 |
| 详情换行宽度 | 116 | 120 - 4（前缀预留）|

## 关键代码路径与文件引用

### 主要文件
1. **`tui/src/history_cell.rs`**（第 3395-3424 行）
   - 测试用例 `completed_mcp_tool_call_multiple_outputs_inline_snapshot`
   - 构建包含两个文本块的 metrics 工具调用

2. **`tui/src/history_cell.rs`**（第 1484-1587 行）
   - `McpToolCallCell::display_lines()` 实现
   - 行内/换行展示决策逻辑

### 辅助函数
```rust
fn format_mcp_invocation(invocation: McpInvocation) -> Line<'a>
fn render_content_block(block: &serde_json::Value, width: usize) -> String
fn text_block(text: &str) -> serde_json::Value  // 测试辅助函数
```

### 相关快照对比
| 快照 | 宽度 | 展示模式 |
|------|------|----------|
| `completed_mcp_tool_call_success_snapshot` | 80 | 行内 |
| `completed_mcp_tool_call_multiple_outputs_inline_snapshot` | 120 | 行内（本测试）|
| `completed_mcp_tool_call_multiple_outputs_snapshot` | 48 | 换行 |

## 依赖与外部交互

### 协议类型
- `codex_protocol::mcp::CallToolResult` - 工具调用结果
- `rmcp::model::Content` - MCP 内容块类型

### 渲染工具
- `crate::wrapping::RtOptions` - 换行选项
- `crate::wrapping::adaptive_wrap_line` - 自适应换行
- `crate::render::line_utils::line_to_static` - 行类型转换

### 格式化工具
- `crate::text_formatting::format_and_truncate_tool_result` - 结果格式化

## 风险、边界与改进建议

### 当前风险

1. **宽度阈值敏感**
   - 风险：行内/换行切换的阈值可能导致布局抖动
   - 场景：终端宽度调整时，展示模式可能频繁切换

2. **内容块数量无限制**
   - 风险：大量 content block 可能导致输出过长
   - 现状：依赖 `TOOL_CALL_MAX_LINES` 限制

3. **混合内容类型**
   - 风险：文本、图片、资源链接混合时的展示顺序
   - 现状：按原顺序渲染

### 边界情况

| 场景 | 当前行为 | 评估 |
|------|----------|------|
| 单个 content block | 正常展示 | ✅ |
| 多个短 content block | 每块一行 | ✅ |
| 包含换行的 content | 分行展示 | ✅ |
| 宽度不足以行内展示 | 自动切换换行模式 | ✅ |
| 空 content 列表 | 不展示详情行 | ⚠️ 需确认 |
| 超长单行 content | 换行截断 | ✅ |

### 改进建议

1. **内容块分组**
   ```rust
   // 将相关的短内容块合并到一行
   if total_content_length < threshold {
       render_inline(content_blocks);
   } else {
       render_separate_lines(content_blocks);
   }
   ```

2. **内容类型图标**
   ```
   • Called metrics.summary(...)
     └ 📝 Latency summary: p50=120ms, p95=480ms.
       📝 No anomalies detected.
   ```

3. **可折叠输出**
   - 当 content block 数量超过阈值时，提供折叠功能
   - 显示摘要："3 outputs (click to expand)"

4. **智能排序**
   - 优先展示文本内容
   - 资源链接和图片可以折叠或后置

5. **性能优化**
   - 对于大量 content block，使用虚拟列表
   - 避免一次性渲染所有内容

### 测试覆盖建议

- [ ] 边界宽度（刚好切换行内/换行的临界值）
- [ ] 大量 content block（>50）的性能
- [ ] 混合内容类型（文本+图片+资源）
- [ ] 包含 ANSI 转义序列的内容
- [ ] 从右到左（RTL）语言的文本
