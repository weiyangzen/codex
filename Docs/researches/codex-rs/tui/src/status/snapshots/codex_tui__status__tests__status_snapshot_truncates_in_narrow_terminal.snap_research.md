# 研究文档：status_snapshot_truncates_in_narrow_terminal.snap

## 场景与职责

此快照文件验证 Codex TUI 状态显示模块在窄终端（narrow terminal）环境下的正确截断行为。当终端宽度不足以显示完整内容时，系统需要优雅地截断文本，确保状态卡片仍然可读且布局不混乱。

该测试对应 `codex-rs/tui/src/status/tests.rs` 中的 `status_snapshot_truncates_in_narrow_terminal` 测试函数，验证宽度受限情况下的文本截断逻辑。

## 功能点目的

### 核心功能
1. **宽度感知渲染**：根据可用宽度动态调整内容显示
2. **智能截断**：优先截断长文本（如模型详情），保留关键信息
3. **布局保护**：确保边框和基本结构在窄终端中保持完整

### 业务逻辑
- 测试使用 70 字符宽度（正常为 80+）
- 截断通过 `truncate_line_to_width` 函数实现
- 模型详情和 URL 等长文本优先被截断

## 具体技术实现

### 关键数据结构

```rust
// format.rs:101-147
pub(crate) fn truncate_line_to_width(line: Line<'static>, max_width: usize) -> Line<'static> {
    if max_width == 0 {
        return Line::from(Vec::<Span<'static>>::new());
    }

    let mut used = 0usize;
    let mut spans_out: Vec<Span<'static>> = Vec::new();

    for span in line.spans {
        let text = span.content.into_owned();
        let style = span.style;
        let span_width = UnicodeWidthStr::width(text.as_str());

        if span_width == 0 {
            spans_out.push(Span::styled(text, style));
            continue;
        }

        if used >= max_width {
            break;
        }

        if used + span_width <= max_width {
            used += span_width;
            spans_out.push(Span::styled(text, style));
            continue;
        }

        // 部分截断：逐个字符检查
        let mut truncated = String::new();
        for ch in text.chars() {
            let ch_width = UnicodeWidthChar::width(ch).unwrap_or(0);
            if used + ch_width > max_width {
                break;
            }
            truncated.push(ch);
            used += ch_width;
        }

        if !truncated.is_empty() {
            spans_out.push(Span::styled(truncated, style));
        }
        break;
    }

    Line::from(spans_out)
}
```

### 终端宽度计算

```rust
// card.rs:413-548
fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
    // ...
    let available_inner_width = usize::from(width.saturating_sub(4));  // 减去边框和边距
    // ...
    
    // 最终截断
    let content_width = lines.iter().map(line_display_width).max().unwrap_or(0);
    let inner_width = content_width.min(available_inner_width);
    let truncated_lines: Vec<Line<'static>> = lines
        .into_iter()
        .map(|line| truncate_line_to_width(line, inner_width))
        .collect();

    with_border_with_inner_width(truncated_lines, inner_width)
}
```

### 模型详情截断

```rust
// card.rs:492-498
let mut model_spans = vec![Span::from(self.model_name.clone())];
if !self.model_details.is_empty() {
    model_spans.push(Span::from(" (").dim());
    model_spans.push(Span::from(self.model_details.join(", ")).dim());
    model_spans.push(Span::from(")").dim());
}
```

### 测试用例构造

```rust
// tests.rs:593-656
let mut config = test_config(&temp_home).await;
config.model = Some("gpt-5.1-codex-max".to_string());
config.model_reasoning_summary = Some(ReasoningSummary::Detailed);
config.cwd = PathBuf::from("/workspace/tests");

let reasoning_effort_override = Some(Some(ReasoningEffort::High));

let composite = new_status_output(
    &config,
    &auth_manager,
    Some(&token_info),
    &usage,
    &None,
    None,
    None,
    Some(&rate_display),
    None,
    captured_at,
    &model_slug,
    None,
    reasoning_effort_override,
);

// 关键：使用 70 字符宽度（比正常的 80 窄）
let mut rendered_lines = render_lines(&composite.display_lines(70));
```

### 渲染输出分析

```
╭────────────────────────────────────────────────────────────────────╮
│  >_ OpenAI Codex (v0.0.0)                                          │
│                                                                    │
│ Visit https://chatgpt.com/codex/settings/usage for up-to-date      │
│ information on rate limits and credits                             │
│                                                                    │
│  Model:            gpt-5.1-codex-max (reasoning high, summaries de │
│  Directory: [[workspace]]                                          │
│  Permissions:      Custom (read-only, on-request)                  │
│  Agents.md:        <none>                                          │
│                                                                    │
│  Token usage:      1.9K total  (1K input + 900 output)             │
│  Context window:   100% left (2.25K used / 272K)                   │
│  5h limit:         [██████░░░░░░░░░░░░░░] 28% left (resets 03:14)  │
╰────────────────────────────────────────────────────────────────────╯
```

关键验证点：
1. **模型详情截断**：`summaries detailed)` 被截断为 `summaries de`
2. **其他信息完整**：Token usage、Context window、5h limit 等关键信息完整显示
3. **边框保持**：边框宽度适应内容，保持视觉完整性
4. **无重置时间截断**：Weekly limit 行因宽度不足未显示（或被截断到不可见）

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|-----|------|
| `codex-rs/tui/src/status/tests.rs` | 测试定义，第 593-656 行 |
| `codex-rs/tui/src/status/card.rs` | 宽度计算和截断调用，第 540-547 行 |
| `codex-rs/tui/src/status/format.rs` | 截断实现，第 101-147 行 |
| `codex-rs/tui/src/history_cell.rs` | 边框渲染，`with_border_with_inner_width` |

### 渲染调用链

```
StatusHistoryCell::display_lines (card.rs:413, width=70)
  ├── available_inner_width = 70 - 4 = 66
  ├── 构建所有内容行
  ├── content_width = 所有行中的最大宽度
  ├── inner_width = content_width.min(66)
  ├── 截断每行到 inner_width (第 542-545 行)
  │   └── truncate_line_to_width (format.rs:101)
  └── with_border_with_inner_width (history_cell.rs)
```

### Unicode 宽度处理

```rust
// format.rs:95-99
pub(crate) fn line_display_width(line: &Line<'static>) -> usize {
    line.iter()
        .map(|span| UnicodeWidthStr::width(span.content.as_ref()))
        .sum()
}
```

使用 `unicode-width` crate 正确处理全角字符和组合字符。

## 依赖与外部交互

### 外部 crate

| crate | 用途 |
|-------|------|
| `ratatui` | 终端渲染，Line/Span 构造 |
| `unicode-width` | 正确的 Unicode 字符宽度计算 |
| `insta` | 快照测试 |

### 内部模块

```rust
use crate::status::format::{truncate_line_to_width, line_display_width};
use crate::history_cell::with_border_with_inner_width;
```

## 风险、边界与改进建议

### 当前风险

1. **硬编码边距**：`width.saturating_sub(4)` 假设固定边框宽度，如果边框样式改变可能不准确
2. **截断位置不可控**：截断发生在字符边界，可能截断在单词中间
3. **信息丢失**：窄终端中重要信息（如重置时间）可能完全丢失

### 边界情况

1. **极窄终端**：如果宽度小于标签长度，值部分可能完全不可见
2. **全角字符**：中日韩字符宽度为 2，截断逻辑需要正确处理
3. **组合字符**：emoji 和组合标记可能计算宽度不正确

### 改进建议

1. **智能截断**：
   ```rust
   // 优先截断低优先级内容
   fn smart_truncate(line: Line, max_width: usize) -> Line {
       // 1. 尝试截断 URL
       // 2. 尝试截断模型详情
       // 3. 尝试截断路径
       // 4. 最后截断其他内容
   }
   ```

2. **单词边界截断**：
   ```rust
   // 使用 textwrap 的 word wrapping
   use textwrap::wrap;
   
   fn truncate_at_word_boundary(text: &str, max_width: usize) -> String {
       let wrapped = wrap(text, max_width);
       wrapped.into_iter().next().unwrap_or_default().to_string()
   }
   ```

3. **优先级显示**：
   - 在极窄终端中隐藏低优先级信息（如 Agents.md）
   - 保留关键信息（如 Limits、Token usage）

4. **水平滚动**：
   - 对于重要表格数据，支持水平滚动而非截断
   - 添加视觉指示器表示有更多内容

5. **响应式布局**：
   ```rust
   enum LayoutMode {
       Full,      // 完整显示
       Compact,   // 隐藏次要信息
       Minimal,   // 仅显示关键信息
   }
   ```

6. **测试扩展**：
   - 测试极窄终端（< 40 字符）
   - 测试包含全角字符的内容
   - 测试包含 emoji 的内容
   - 测试不同边框样式下的宽度计算

7. **配置选项**：
   - 允许用户配置最小显示宽度
   - 允许禁用某些字段以节省空间
