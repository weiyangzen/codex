# 研究文档：MCP 工具调用换行输出快照测试

## 场景与职责

该快照测试验证了 `McpToolCallCell` 在 MCP 工具调用返回内容需要换行展示时的行为。当工具返回的内容较长，在有限宽度下无法单行展示时，UI 需要智能地进行换行处理，同时保持内容的可读性和结构清晰。

### 业务场景
用户调用 MCP 工具获取较长的文本结果：
- 调用 `metrics.get_nearby_metric` 工具
- 传入较长的查询参数
- 返回多行、长文本的结果内容
- 终端宽度有限（40 列）

### 测试重点
本测试与 `completed_mcp_tool_call_multiple_outputs_snapshot` 的区别在于：
- 本测试关注**单个 content block 内部的多行文本**换行
- 前者关注**多个 content block** 的展示

## 功能点目的

### 核心功能
- **长参数换行**：工具调用参数过长时的换行处理
- **内容自动换行**：返回内容根据宽度自动换行
- **多行内容保持**：保留原始内容中的换行结构

### 预期输出
```
• Called
  └ metrics.get_nearby_metric({"query":"
        very_long_query_that_needs_wrapp
        ing_to_display_properly_in_the_h
        istory","limit":1})
    Line one of the response, which is
        quite long and needs wrapping.
    Line two continues the response with
        more detail.
```

### 设计特点
1. **参数换行**：长 JSON 参数在边界处换行，使用 8 空格缩进
2. **内容换行**：每行内容独立换行，续行缩进对齐
3. **结构保持**：原始的两行内容结构被保留

## 具体技术实现

### 测试数据结构

```rust
#[test]
fn completed_mcp_tool_call_wrapped_outputs_snapshot() {
    let invocation = McpInvocation {
        server: "metrics".into(),
        tool: "get_nearby_metric".into(),
        arguments: Some(json!({
            // 故意构造的长查询参数
            "query": "very_long_query_that_needs_wrapping_to_display_properly_in_the_history",
            "limit": 1,
        })),
    };

    // 包含多行长文本的单个 content block
    let result = CallToolResult {
        content: vec![text_block(
            "Line one of the response, which is quite long and needs wrapping.\n\
             Line two continues the response with more detail."
        )],
        is_error: None,
        structured_content: None,
        meta: None,
    };

    let mut cell = new_active_mcp_tool_call("call-5".into(), invocation, true);
    cell.complete(Duration::from_millis(1280), Ok(result));

    // 使用较窄宽度（40）强制换行
    let rendered = render_lines(&cell.display_lines(40)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 换行处理流程

```rust
impl HistoryCell for McpToolCallCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        // 1. 渲染调用头部（换行模式）
        // ...
        
        // 2. 处理 content block
        for block in content {
            let text = Self::render_content_block(block, detail_wrap_width);
            
            // 3. 按原始换行分割
            for segment in text.split('\n') {
                let line = Line::from(segment.to_string().dim());
                
                // 4. 自适应换行
                let wrapped = adaptive_wrap_line(
                    &line,
                    RtOptions::new(detail_wrap_width)
                        .initial_indent("".into())
                        .subsequent_indent("    ".into()),
                );
                detail_lines.extend(wrapped.iter().map(line_to_static));
            }
        }
        
        // 5. 添加前缀
        lines.extend(prefix_lines(detail_lines, initial_prefix, "    ".into()));
    }
}
```

### 宽度计算

```rust
// 可用宽度计算
let detail_wrap_width = (width as usize).saturating_sub(4).max(1);
// 40 - 4 = 36 字符可用

// 缩进规则
let opts = RtOptions::new(detail_wrap_width)
    .initial_indent("".into())      // 首行无额外缩进
    .subsequent_indent("    ".into());  // 续行 4 空格缩进
```

### 内容渲染细节

```rust
fn render_content_block(block: &serde_json::Value, width: usize) -> String {
    let content = serde_json::from_value::<rmcp::model::Content>(block.clone())?;
    
    match content.raw {
        rmcp::model::RawContent::Text(text) => {
            // 格式化并截断
            format_and_truncate_tool_result(&text.text, TOOL_CALL_MAX_LINES, width)
        }
        // ...
    }
}
```

## 关键代码路径与文件引用

### 主要文件
1. **`tui/src/history_cell.rs`**（第 3364-3392 行）
   - 测试用例 `completed_mcp_tool_call_wrapped_outputs_snapshot`
   - 长参数和多行内容的换行场景

2. **`tui/src/history_cell.rs`**（第 1528-1567 行）
   - 内容块处理和换行逻辑
   - `adaptive_wrap_line` 调用

### 辅助函数
```rust
fn format_and_truncate_tool_result(text: &str, max_lines: usize, width: usize) -> String
fn adaptive_wrap_line(line: &Line, opts: RtOptions) -> Vec<Line<'_>>
fn prefix_lines(lines, initial_prefix, subsequent_prefix) -> Vec<Line<'static>>
```

### 相关测试
| 测试 | 宽度 | 重点 |
|------|------|------|
| `completed_mcp_tool_call_success_snapshot` | 80 | 基础成功场景 |
| `completed_mcp_tool_call_multiple_outputs_snapshot` | 48 | 多 content block |
| 本测试 | 40 | 单 content block 多行换行 |

## 依赖与外部交互

### 换行算法
- `crate::wrapping::adaptive_wrap_line` - 自适应换行
- `crate::wrapping::RtOptions` - 换行选项

### 文本处理
- `textwrap` crate - 底层换行算法
- `unicode_width` - 字符宽度计算
- `unicode_segmentation` - 文本分段

### 格式化
- `crate::text_formatting::format_and_truncate_tool_result` - 结果格式化

## 风险、边界与改进建议

### 当前风险

1. **单词截断**
   - 风险：长单词（如本测试中的长查询字符串）可能被任意截断
   - 示例：`wrapp` + `ing` 被分开
   - 影响：可读性降低

2. **JSON 结构破坏**
   - 风险：JSON 参数换行后结构不清晰
   - 现状：依赖 `serde_json::to_string` 的紧凑格式

3. **缩进不一致**
   - 参数续行使用 4 空格缩进
   - 内容续行也使用 4 空格缩进
   - 可能导致视觉上的混淆

### 边界情况

| 场景 | 当前行为 | 评估 |
|------|----------|------|
| 超长单词（>宽度）| 强制截断 | ⚠️ 可读性差 |
| 包含制表符 | 视为普通字符 | ⚠️ 可能错位 |
| 包含多个连续换行 | 每行单独处理 | ✅ |
| 空行 | 保留空行 | ✅ |
| 行尾空格 | 保留 | ⚠️ 可能不必要 |

### 改进建议

1. **智能单词换行**
   ```rust
   // 使用 textwrap 的 WordSeparator
   let opts = RtOptions::new(width)
       .word_separator(textwrap::WordSeparator::UnicodeBreakProperties);
   ```

2. **JSON 美化**
   ```rust
   // 对 JSON 参数使用美化格式
   serde_json::to_string_pretty(&args)
   ```

3. **语法感知换行**
   - 对代码内容使用语法感知换行
   - 在语法边界处换行（如逗号后、操作符后）

4. **行号显示**
   ```
   • Called metrics.get_nearby_metric(...)
     └ 1: Line one of the response, which is
          quite long and needs wrapping.
       2: Line two continues the response with
          more detail.
   ```

5. **原始/换行视图切换**
   - 提供快捷键切换换行和原始视图
   - 原始视图使用水平滚动

### 测试覆盖建议

- [ ] 包含 CJK 字符的换行
- [ ] 包含 emoji 的换行
- [ ] 包含 ANSI 转义序列的内容
- [ ] 极长单词（>100 字符）
- [ ] 大量空行的处理
- [ ] 混合方向文本（RTL + LTR）
