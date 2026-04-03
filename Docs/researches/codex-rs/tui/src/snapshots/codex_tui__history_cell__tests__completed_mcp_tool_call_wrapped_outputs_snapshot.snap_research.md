# Research: Completed MCP Tool Call Wrapped Outputs Snapshot

## 场景与职责

此快照测试验证 Codex TUI 在 MCP 工具调用返回长文本输出时的换行展示能力。当工具返回的内容超过可用显示宽度时，UI 需要智能地进行换行处理，保持内容的可读性和视觉层次。

## 功能点目的

1. **长参数换行**：当调用参数过长时，在适当位置换行
2. **长输出换行**：对工具返回的多行长文本进行正确的换行和缩进
3. **视觉层次保持**：通过缩进前缀保持输出与调用的层级关系

## 具体技术实现

### 换行处理逻辑

```rust
// history_cell.rs:1522-1541
detail_wrap_width = (width as usize).saturating_sub(4).max(1);

if let Some(result) = &self.result {
    match result {
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
        // ...
    }
}
```

### 前缀处理

```rust
// history_cell.rs:1563-1569
if !detail_lines.is_empty() {
    let initial_prefix: Span<'static> = if inline_invocation {
        "  └ ".dim()
    } else {
        "    ".into()
    };
    lines.extend(prefix_lines(detail_lines, initial_prefix, "    ".into()));
}
```

### 测试场景

```rust
// history_cell.rs:3364-3392
#[test]
fn completed_mcp_tool_call_wrapped_outputs_snapshot() {
    let invocation = McpInvocation {
        server: "metrics".into(),
        tool: "get_nearby_metric".into(),
        arguments: Some(json!({
            // 长参数，需要换行
            "query": "very_long_query_that_needs_wrapping_to_display_properly_in_the_history",
            "limit": 1,
        })),
    };

    let result = CallToolResult {
        content: vec![text_block(
            // 多行长输出
            "Line one of the response, which is quite long and needs wrapping.\n\
             Line two continues the response with more detail.",
        )],
        is_error: None,
        structured_content: None,
        meta: None,
    };

    let mut cell = new_active_mcp_tool_call("call-5".into(), invocation, true);
    cell.complete(Duration::from_millis(1280), Ok(result));

    // 窄宽度 (40) 强制换行
    let rendered = render_lines(&cell.display_lines(40)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 输出格式

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

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/history_cell.rs` | MCP 单元格实现，测试位于 line 3364-3392 |
| `codex-rs/tui/src/wrapping.rs` | 自适应换行核心实现 |
| `codex-rs/tui/src/render/line_utils.rs` | 行前缀工具 (`prefix_lines`) |
| `codex-rs/tui/src/live_wrap.rs` | 实时换行辅助函数 |

### 换行算法流程

```
display_lines(width: 40)
    ↓
format_mcp_invocation() → 长参数字符串
    ↓
inline_invocation = false (宽度不足)
    ↓
渲染调用头单独一行
    ↓
adaptive_wrap_line(invocation_line, opts with width-4)
    ↓
    - 使用 textwrap 进行单词换行
    - 保持 URL-like token 不换行
    - 应用 initial/subsequent 缩进
    ↓
前缀添加 "  └ " 和 "    "
    ↓
处理结果内容:
    split('\n') → 按原始换行分割
    ↓
    对每行应用 adaptive_wrap_line
        ↓
    添加前缀并合并到输出
```

## 依赖与外部交互

### 外部依赖

- `textwrap`: 文本换行算法库
- `unicode_width`: Unicode 字符宽度计算
- `unicode_segmentation`: 字符分割

### 内部模块

```rust
// wrapping.rs
pub struct RtOptions {
    width: usize,
    initial_indent: Line<'static>,
    subsequent_indent: Line<'static>,
    break_words: bool,
    wrap_algorithm: textwrap::WrapAlgorithm,
    word_splitter: textwrap::WordSplitter,
}

pub fn adaptive_wrap_line(line: &Line, opts: RtOptions) -> Vec<Line<'static>> {
    // 自适应换行，保持 URL-like token 完整
}
```

## 风险、边界与改进建议

### 潜在风险

1. **URL 截断**：长 URL 在换行时可能被截断
2. **代码可读性**：代码块换行后可能破坏语法结构
3. **表格对齐**：表格内容换行后对齐失效

### 边界情况

1. **超长单词**：超过行宽的单个单词处理
2. **CJK 字符**：中日韩字符的换行边界
3. **组合字符**：表情符号等组合字符的换行
4. **零宽度字符**：零宽空格、零宽连接符的处理

### 改进建议

1. **智能断行**：对代码、URL、表格使用不同的断行策略
2. **水平滚动**：对代码块提供水平滚动而非强制换行
3. **语法高亮保留**：换行时保持语法高亮状态
4. **折叠长输出**：超过一定行数的输出默认折叠
5. **复制原始文本**：提供复制未换行原始文本的功能
6. **响应式宽度**：根据终端宽度动态调整换行策略

### 相关测试

- `completed_mcp_tool_call_multiple_outputs_snapshot`：多输出换行
- `prefixed_wrapped_history_cell_indents_wrapped_lines`：前缀缩进验证
- `user_history_cell_wraps_and_prefixes_each_line_snapshot`：用户消息换行
