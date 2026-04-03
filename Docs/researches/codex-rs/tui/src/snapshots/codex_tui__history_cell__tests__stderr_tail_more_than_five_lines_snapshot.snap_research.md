# Research Document: Stderr Tail More Than Five Lines Snapshot

## 场景与职责

此快照测试验证 **ExecCell** 组件在处理大量 stderr 输出时的截断和展示策略。当命令产生超过 `line_limit`（默认为 5 行）的输出时，组件应采用"头尾展示"策略，中间用省略号表示被隐藏的内容。

该组件负责：
- 限制输出行数，避免历史记录被长输出淹没
- 智能展示输出的开头和结尾部分
- 清晰标示被省略的行数
- 正确处理 stderr 和 stdout 的混合输出

## 功能点目的

**主要功能**：验证 ExecCell 对大量 stderr 输出的截断渲染效果：

1. **输出生成**：命令 `seq 1 10 1>&2 && false` 产生 10 行 stderr 输出（数字 1-10）
2. **头尾展示**：显示前 5 行（1-2）和后 5 行（9-10），中间省略
3. **省略提示**：显示 `… +6 lines` 表示有 6 行被隐藏
4. **视觉层次**：使用 `"  └ "` 和 `"    "` 前缀保持缩进

**预期输出结构**：
```
• Ran seq 1 10 1>&2 && false
  └ 1
    2
    … +6 lines
    9
    10
```

## 具体技术实现

### 输出截断算法

**output_lines 函数**（位于 `exec_cell/render.rs` 第 99-180 行）：
```rust
pub(crate) fn output_lines(
    output: Option<&CommandOutput>,
    params: OutputLinesParams,
) -> OutputLines {
    let src = aggregated_output;
    let lines: Vec<&str> = src.lines().collect();
    let total = lines.len();
    
    // 显示头部
    let head_end = total.min(line_limit);  // 前 5 行
    for (i, raw) in lines[..head_end].iter().enumerate() {
        let mut line = ansi_escape_line(raw);
        let prefix = if i == 0 && include_angle_pipe {
            "  └ "
        } else {
            "    "
        };
        line.spans.insert(0, prefix.into());
        out.push(line);
    }
    
    // 判断是否显示省略号
    let show_ellipsis = total > 2 * line_limit;  // 10 > 10? 否
    // 实际上测试用例使用 line_limit=5，总输出 10 行
    // 10 > 10 为 false，所以这里有个细节...
    
    // 显示尾部
    let tail_start = if show_ellipsis {
        total - line_limit
    } else {
        head_end
    };
    for raw in lines[tail_start..].iter() {
        // ...
    }
}
```

**注意**：测试中 `line_limit=5`，总输出 10 行，`2 * line_limit = 10`，`show_ellipsis = false`。
但实际快照显示了省略号。这表明实际使用的 `line_limit` 可能不同，或者存在其他截断逻辑。

### 行数限制配置

```rust
pub(crate) const TOOL_CALL_MAX_LINES: usize = 5;
const USER_SHELL_TOOL_CALL_MAX_LINES: usize = 50;

// 在 command_display_lines 中
let line_limit = if call.is_user_shell_command() {
    USER_SHELL_TOOL_CALL_MAX_LINES
} else {
    TOOL_CALL_MAX_LINES
};
```

### 截断流程

1. **原始输出**：`seq 1 10` 产生 10 行（1-10）
2. **头部提取**：前 `line_limit` 行（1-5）
3. **省略判断**：总输出 > 2 * line_limit（10 > 10 为 false）
4. **实际行为**：由于 `show_ellipsis` 为 false，应该显示全部 10 行
5. **但快照显示**：`… +6 lines`，说明实际逻辑可能更复杂

**实际逻辑**（`truncate_lines_middle` 方法）：
```rust
fn truncate_lines_middle(
    lines: &[Line<'static>],
    max_rows: usize,      // 5
    width: u16,
    omitted_hint: Option<usize>,
    ellipsis_prefix: Option<&Line<'static>>,
) -> Vec<Line<'static>> {
    // 计算每行的视口行数
    let line_rows: Vec<usize> = lines.iter().map(|line| {
        Paragraph::new(Text::from(vec![line.clone()]))
            .wrap(Wrap { trim: false })
            .line_count(width)
    }).collect();
    
    // 如果超过 max_rows，进行头尾截断
    let head_budget = (max_rows - 1) / 2;  // 2
    let tail_budget = max_rows - head_budget - 1;  // 2
    // ...
}
```

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/exec_cell/render.rs` | `output_lines` 函数（第 99-180 行） |
| `codex-rs/tui/src/exec_cell/render.rs` | `truncate_lines_middle` 方法（第 530-622 行） |
| `codex-rs/tui/src/exec_cell/render.rs` | `EXEC_DISPLAY_LAYOUT` 常量（第 682-687 行） |
| `codex-rs/tui/src/history_cell.rs` | 测试用例（第 3747-3790 行） |

### 测试代码位置

```rust
// history_cell.rs 第 3747-3790 行
#[test]
fn stderr_tail_more_than_five_lines_snapshot() {
    let call_id = "c_err".to_string();
    let mut cell = ExecCell::new(
        ExecCall {
            call_id: call_id.clone(),
            command: vec!["bash".into(), "-lc".into(), "seq 1 10 1>&2 && false".into()],
            parsed: Vec::new(),
            output: None,
            source: ExecCommandSource::Agent,
            start_time: Some(Instant::now()),
            duration: None,
            interaction_input: None,
        },
        true,
    );
    
    let stderr: String = (1..=10)
        .map(|n| n.to_string())
        .collect::<Vec<_>>()
        .join("\n");
    
    cell.complete_call(
        &call_id,
        CommandOutput {
            exit_code: 1,
            formatted_output: String::new(),
            aggregated_output: stderr,  // "1\n2\n...\n10"
        },
        Duration::from_millis(1),
    );
    
    let rendered = cell.display_lines(80)
        .iter()
        .map(|l| l.spans.iter().map(|s| s.content.as_ref()).collect::<String>())
        .collect::<Vec<_>>()
        .join("\n");
    insta::assert_snapshot!(rendered);
}
```

## 依赖与外部交互

### 内部依赖

- **codex-ansi-escape**: ANSI 转义序列处理 `ansi_escape_line`
- **ratatui**: `Paragraph::line_count` 计算视口行数

### 输出处理流程

```
aggregated_output (String)
    ├── lines() 分割成行
    ├── ansi_escape_line 处理每行
    ├── 应用前缀（"  └ " / "    "）
    ├── 应用样式（Modifier::DIM）
    └── 组装为 OutputLines
```

## 风险、边界与改进建议

### 已知风险

1. **行数计算歧义**："逻辑行" vs "视口行" 的混淆
2. **ANSI 序列影响**：ANSI 颜色序列可能影响行数计算
3. **省略提示累积**：多次截断时 `omitted_hint` 的累加可能不准确

### 边界情况

| 场景 | 当前行为 |
|------|---------|
| 输出为空 | 显示 `"(no output)"` |
| 输出 1 行 | 完整显示 |
| 输出 5 行 | 完整显示 |
| 输出 6 行 | 头 2 + 省略 + 尾 2 = 5 行 |
| 输出 100 行 | 头 2 + 省略 + 尾 2 = 5 行 |

### 改进建议

1. **可配置性**：
   - 允许用户自定义 `TOOL_CALL_MAX_LINES`
   - 支持按命令类型设置不同限制

2. **交互性**：
   - 点击省略号展开完整输出
   - 快捷键查看完整日志

3. **智能截断**：
   - 优先保留包含错误关键字的行
   - 使用摘要算法提取关键信息

4. **性能优化**：
   - 对于超长输出，延迟加载或流式处理
   - 避免在内存中保留完整输出
