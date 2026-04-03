# 研究文档: codex_tui_app_server__status__tests__status_snapshot_truncates_in_narrow_terminal.snap

## 场景与职责

此快照文件是 `codex-tui-app-server` crate 中状态显示功能的 insta 快照测试结果，测试用例为 `status_snapshot_truncates_in_narrow_terminal`。该测试验证当终端宽度较窄时，状态显示能正确截断内容。

## 功能点目的

### 测试目标
验证以下场景的状态显示行为：
1. **窄终端适配**: 在 70 字符宽度下渲染
2. **内容截断**: 过长的模型详情被截断
3. **布局保持**: 基本布局结构保持完整

## 具体技术实现

### 关键流程

1. **宽度计算** (`card.rs:422`):
```rust
let available_inner_width = usize::from(width.saturating_sub(4));
// 减去 4 是为了边框和间距
```

2. **行截断** (`card.rs:539-547`):
```rust
let content_width = lines.iter().map(line_display_width).max().unwrap_or(0);
let inner_width = content_width.min(available_inner_width);
let truncated_lines: Vec<Line<'static>> = lines
    .into_iter()
    .map(|line| truncate_line_to_width(line, inner_width))
    .collect();
```

3. **截断函数** (`format.rs`):
```rust
pub(crate) fn truncate_line_to_width(line: Line<'static>, width: usize) -> Line<'static> {
    let current_width = line_display_width(&line);
    if current_width <= width {
        return line;
    }
    let mut spans = line.spans;
    while line_display_width(&Line::from(spans.clone())) > width && !spans.is_empty() {
        spans.pop();  // 从右侧移除 spans
    }
    Line::from(spans)
}
```

4. **测试数据** (`tests.rs:589-652`):
```rust
config.model = Some("gpt-5.1-codex-max".to_string());
config.model_reasoning_summary = Some(ReasoningSummary::Detailed);

let reasoning_effort_override = Some(Some(ReasoningEffort::High));
let composite = new_status_output(
    // ...
    reasoning_effort_override,
);

// 使用 70 字符宽度
let mut rendered_lines = render_lines(&composite.display_lines(70));
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `tui_app_server/src/status/tests.rs:589-652` | 测试用例定义 |
| `tui_app_server/src/status/card.rs:412-425` | `display_lines` 入口 |
| `tui_app_server/src/status/card.rs:539-547` | 内容截断 |
| `tui_app_server/src/status/format.rs` | `truncate_line_to_width` |

## 风险、边界与改进建议

### 当前风险
1. **无省略号**: 截断时不显示 "..."
2. **信息丢失**: 重要信息可能在右侧被截断

### 改进建议
1. **智能截断**: 优先截断次要信息
2. **省略号提示**: 添加 "..." 表示截断
3. **响应式布局**: 根据宽度调整显示内容

### 测试覆盖
- ✅ 70 字符宽度渲染
- ✅ 模型详情截断
- ✅ 基本布局保持

### 显示对比
| 宽度 | 模型行显示 |
|------|-----------|
| 80 | `Model: gpt-5.1-codex-max (reasoning high, summaries detailed)` |
| 70 | `Model: gpt-5.1-codex-max (reasoning high, summaries de` |
