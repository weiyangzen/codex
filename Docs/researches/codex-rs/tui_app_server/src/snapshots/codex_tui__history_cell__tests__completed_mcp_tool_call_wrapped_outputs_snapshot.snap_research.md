# 研究文档：completed_mcp_tool_call_wrapped_outputs_snapshot.snap

## 场景与职责

此快照测试验证 MCP 工具调用结果需要换行显示时的 UI 渲染效果。当工具参数或返回值过长时，文本需要正确换行以保持可读性。

## 功能点目的

1. **长文本换行**：确保 MCP 工具的长参数和结果被正确换行
2. **保持可读性**：换行后的文本应该保持结构清晰
3. **缩进一致性**：换行后的后续行应该有适当的缩进

## 具体技术实现

### 换行逻辑

```rust
// 来自 crate::wrapping
pub fn adaptive_wrap_line(line: &str, width: usize) -> Vec<String>;
pub fn adaptive_wrap_lines(lines: Vec<Line>, width: usize) -> Vec<Line>;
```

### 快照输出分析

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

关键观察：
1. 长 JSON 参数被分割到多行
2. 参数值内部有额外的缩进（8 空格）
3. 结果文本也根据宽度进行换行
4. 多行结果保持一致的缩进层级

## 关键代码路径与文件引用

1. **换行实现**：
   - `codex-rs/tui/src/wrapping.rs` - 自适应换行逻辑
   - `codex-rs/tui/src/live_wrap.rs` - 实时换行处理

2. **MCP 单元格渲染**：
   - `codex-rs/tui/src/history_cell.rs` 第 1891 行附近
   - 处理 `McpInvocation` 的显示逻辑

3. **文本格式化**：
   - `crate::text_formatting::truncate_text` - 文本截断
   - `crate::text_formatting::format_and_truncate_tool_result` - 结果格式化

## 依赖与外部交互

### 换行相关依赖
- `textwrap` - 文本换行库
- `unicode_width` - 计算 Unicode 字符串的显示宽度
- `unicode_segmentation` - Unicode 文本分段

### 样式依赖
- `ratatui::style::Style` - 样式定义
- `crate::style::proposed_plan_style` - 计划样式

## 风险、边界与改进建议

### 潜在风险
1. **宽度计算不准确**：某些 Unicode 字符（如 emoji）的宽度计算可能有误
2. **性能问题**：大量长文本的换行可能影响渲染性能

### 边界情况
1. 极长的单行 token（如 base64 字符串）
2. 包含多字节字符的文本
3. 终端宽度极小的情况

### 改进建议
1. 对于极长的 token（如 base64），考虑使用截断而不是强制换行
2. 添加配置选项，允许用户设置最大显示行数
3. 考虑使用语法高亮来区分 JSON 键和值
4. 添加 "复制完整结果" 功能
