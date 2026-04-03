# 研究文档: status_snapshot_truncates_in_narrow_terminal.snap

## 场景与职责

此快照文件是 `codex-tui` crate 中状态显示功能的 insta 快照测试结果，测试用例为 `status_snapshot_truncates_in_narrow_terminal`。该测试验证当终端宽度较窄时，状态显示能正确截断内容以适应可用空间。

## 功能点目的

### 测试目标
验证以下场景的状态显示行为：
1. **窄终端适配**: 在 70 字符宽度下正确渲染
2. **内容截断**: 过长的模型详情被截断
3. **布局保持**: 即使在窄空间内，基本布局结构保持完整

### 业务逻辑
- 用户可能使用分屏终端或小窗口运行 Codex
- 状态显示需要优雅地处理空间限制
- 关键信息应优先显示，次要信息可被截断

## 具体技术实现

### 关键流程

1. **宽度计算** (`card.rs:423`):
```rust
fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
    let available_inner_width = usize::from(width.saturating_sub(4));
    // 减去 4 是为了边框和间距：│ 内容 │
    //                              ^ ^^^^
    if available_inner_width == 0 {
        return Vec::new();
    }
    // ...
}
```

2. **行截断** (`card.rs:540-547`):
```rust
let content_width = lines.iter().map(line_display_width).max().unwrap_or(0);
let inner_width = content_width.min(available_inner_width);
let truncated_lines: Vec<Line<'static>> = lines
    .into_iter()
    .map(|line| truncate_line_to_width(line, inner_width))
    .collect();

with_border_with_inner_width(truncated_lines, inner_width)
```

3. **截断函数** (`format.rs`):
```rust
pub(crate) fn truncate_line_to_width(line: Line<'static>, width: usize) -> Line<'static> {
    let current_width = line_display_width(&line);
    if current_width <= width {
        return line;
    }
    
    // 从右向左截断 spans，直到符合宽度
    let mut spans = line.spans;
    while line_display_width(&Line::from(spans.clone())) > width && !spans.is_empty() {
        spans.pop();
    }
    Line::from(spans)
}
```

4. **模型详情截断** (`card.rs:492-498`):
```rust
let mut model_spans = vec![Span::from(self.model_name.clone())];
if !self.model_details.is_empty() {
    model_spans.push(Span::from(" (").dim());
    model_spans.push(Span::from(self.model_details.join(", ")).dim());
    model_spans.push(Span::from(")").dim());
}
// 在窄终端，details 部分可能被截断
```

5. **测试数据设置** (`tests.rs:593-656`):
```rust
config.model = Some("gpt-5.1-codex-max".to_string());
config.model_reasoning_summary = Some(ReasoningSummary::Detailed);
// 模型详情：reasoning high, summaries detailed

let composite = new_status_output(
    // ...
    reasoning_effort_override,  // Some(ReasoningEffort::High)
);

// 使用 70 字符宽度（比正常 80 字符窄）
let mut rendered_lines = render_lines(&composite.display_lines(70));
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `tui/src/status/tests.rs:593-656` | 测试用例定义 |
| `tui/src/status/card.rs:412-425` | `display_lines` 入口和宽度计算 |
| `tui/src/status/card.rs:539-547` | 内容截断和边框添加 |
| `tui/src/status/format.rs` | `truncate_line_to_width` - 行截断实现 |
| `tui/src/history_cell.rs` | `with_border_with_inner_width` - 边框渲染 |

## 依赖与外部交互

### 依赖模块
- `ratatui::prelude::Line` - 行类型
- `ratatui::prelude::Span` - 文本片段类型

### 截断策略
当前实现采用**从右截断**策略：
1. 计算当前行宽度
2. 如果超过目标宽度，从右侧移除 spans
3. 不添加省略号，直接截断

## 风险、边界与改进建议

### 当前风险
1. **无省略号**: 截断时不显示 "..."，用户可能不知道内容被截断
2. **信息丢失**: 重要信息可能在右侧被截断
3. **布局错乱**: 极端窄宽度下（< 20 字符）布局可能异常

### 边界情况
1. **Unicode 宽度**: 中文字符或 emoji 的宽度计算可能不准确
2. **ANSI 转义序列**: 颜色代码计入宽度，可能导致截断位置偏移
3. **零宽度字符**: 组合字符可能被错误处理
4. **极小宽度**: `width < 4` 时返回空 Vec

### 改进建议
1. **智能截断**: 
   - 优先截断次要信息（如 details）
   - 保留关键信息（如模型名称）
   - 添加省略号提示
2. **响应式布局**: 根据宽度调整显示内容：
   ```
   宽: Model: gpt-5.1-codex-max (reasoning high, summaries detailed)
   中: Model: gpt-5.1-codex-max (reasoning high...)
   窄: Model: gpt-5.1-codex-max
   ```
3. **最小宽度保证**: 设置合理的最低宽度（如 40 字符），低于此宽度提示用户
4. **换行支持**: 对于长内容，考虑在窄终端换行而非截断

### 测试覆盖
此快照测试覆盖了以下场景：
- ✅ 70 字符宽度渲染
- ✅ 模型详情截断（"summaries de" 而非 "summaries detailed"）
- ✅ 基本布局保持

### 显示对比
| 宽度 | 模型行显示 |
|------|-----------|
| 80 | `Model: gpt-5.1-codex-max (reasoning high, summaries detailed)` |
| 70 | `Model: gpt-5.1-codex-max (reasoning high, summaries de` |

### 相关测试
- `status_snapshot_includes_reasoning_details` - 相同数据在 80 字符宽度下的显示
