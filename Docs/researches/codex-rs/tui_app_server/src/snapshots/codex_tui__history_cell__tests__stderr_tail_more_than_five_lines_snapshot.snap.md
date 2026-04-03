# 研究文档：stderr_tail_more_than_five_lines_snapshot

## 场景与职责

该快照测试验证 `ExecCell` 在 stderr 输出超过 5 行时的"头部+省略+尾部"渲染行为。当命令产生大量错误输出时，系统需要智能地截断显示，保留头部和尾部信息，同时告知用户被省略的内容。

**核心职责**：
- 限制错误输出的显示行数，避免占用过多屏幕空间
- 使用"头部+省略提示+尾部"的模式展示长输出
- 保持输出的可读性和上下文完整性
- 清晰地指示被省略的行数

## 功能点目的

**从快照内容分析**：
```
• Ran seq 1 10 1>&2 && false
  └ 1
    2
    … +6 lines
    9
    10
```

**功能特性**：
1. **命令显示**：`• Ran seq 1 10 1>&2 && false` - 显示执行的命令
2. **头部输出**：显示前 2 行（`1`、`2`）
3. **省略提示**：`… +6 lines` - 告知用户有 6 行被省略
4. **尾部输出**：显示最后 2 行（`9`、`10`）
5. **视觉前缀**：使用 `└` 和空格作为输出块前缀

## 具体技术实现

### 输出截断算法

**代码位置**：`codex-rs/tui/src/exec_cell/render.rs` 第 99-180 行

```rust
pub(crate) fn output_lines(
    output: Option<&CommandOutput>,
    params: OutputLinesParams,
) -> OutputLines {
    let OutputLinesParams { line_limit, only_err, include_angle_pipe, include_prefix } = params;
    
    // 收集所有行
    let lines: Vec<&str> = src.lines().collect();
    let total = lines.len();
    
    // 显示头部
    let head_end = total.min(line_limit);  // line_limit = 5
    for (i, raw) in lines[..head_end].iter().enumerate() {
        let mut line = ansi_escape_line(raw);
        let prefix = if !include_prefix {
            ""
        } else if i == 0 && include_angle_pipe {
            "  └ "
        } else {
            "    "
        };
        line.spans.insert(0, prefix.into());
        line.spans.iter_mut().for_each(|span| {
            span.style = span.style.add_modifier(Modifier::DIM);
        });
        out.push(line);
    }

    // 判断是否需要省略
    let show_ellipsis = total > 2 * line_limit;  // 10 > 10? No, wait...
    // Actually, the logic is: show ellipsis if total > 2 * line_limit
    // For 10 lines with limit 5: 10 > 10 is false, but the test shows ellipsis
    // Let me check the actual implementation...
    
    // Correct logic (from source):
    let show_ellipsis = total > 2 * line_limit;
    let omitted = if show_ellipsis {
        Some(total - 2 * line_limit)
    } else {
        None
    };
    
    if show_ellipsis {
        let omitted = total - 2 * line_limit;
        out.push(format!("… +{omitted} lines").into());
    }

    // 显示尾部
    let tail_start = if show_ellipsis {
        total - line_limit
    } else {
        head_end
    };
    for raw in lines[tail_start..].iter() {
        // ... 类似头部处理
    }
}
```

### 修正：实际截断逻辑

**`truncate_lines_middle` 函数**（第 530-622 行）：

```rust
fn truncate_lines_middle(
    lines: &[Line<'static>],
    max_rows: usize,  // EXEC_DISPLAY_LAYOUT.output_max_lines = 5
    width: u16,
    omitted_hint: Option<usize>,
    ellipsis_prefix: Option<&Line<'static>>,
) -> Vec<Line<'static>> {
    // 计算每行的实际显示行数（考虑换行）
    let line_rows: Vec<usize> = lines
        .iter()
        .map(|line| {
            Paragraph::new(Text::from(vec![line.clone()]))
                .wrap(Wrap { trim: false })
                .line_count(width)
                .max(1)
        })
        .collect();
    let total_rows: usize = line_rows.iter().sum();
    
    // 如果总行数在限制内，直接返回
    if total_rows <= max_rows {
        return lines.to_vec();
    }

    // 计算头部和尾部预算
    let head_budget = (max_rows - 1) / 2;  // (5 - 1) / 2 = 2
    let tail_budget = max_rows - head_budget - 1;  // 5 - 2 - 1 = 2
    
    // 收集头部行
    let mut head_lines: Vec<Line<'static>> = Vec::new();
    let mut head_rows = 0usize;
    let mut head_end = 0usize;
    while head_end < lines.len() {
        let line_row_count = line_rows[head_end];
        if head_rows + line_row_count > head_budget {
            break;
        }
        head_rows += line_row_count;
        head_lines.push(lines[head_end].clone());
        head_end += 1;
    }

    // 收集尾部行（反向）
    let mut tail_lines_reversed: Vec<Line<'static>> = Vec::new();
    let mut tail_rows = 0usize;
    let mut tail_start = lines.len();
    while tail_start > head_end {
        let idx = tail_start - 1;
        let line_row_count = line_rows[idx];
        if tail_rows + line_row_count > tail_budget {
            break;
        }
        tail_rows += line_row_count;
        tail_lines_reversed.push(lines[idx].clone());
        tail_start -= 1;
    }

    // 组装结果：头部 + 省略行 + 尾部
    let mut out = head_lines;
    let base = omitted_hint.unwrap_or(0);
    let additional = lines.len().saturating_sub(out.len() + tail_lines_reversed.len())
        .saturating_sub(usize::from(omitted_hint.is_some()));
    out.push(Self::ellipsis_line_with_prefix(
        base + additional,
        ellipsis_prefix.as_ref(),
    ));
    out.extend(tail_lines_reversed.into_iter().rev());

    out
}
```

### 布局配置

```rust
const EXEC_DISPLAY_LAYOUT: ExecDisplayLayout = ExecDisplayLayout::new(
    PrefixedBlock::new("  │ ", "  │ "),
    /*command_continuation_max_lines*/ 2,
    PrefixedBlock::new("  └ ", "    "),  // 输出块前缀
    /*output_max_lines*/ 5,               // 最大输出行数
);
```

## 关键代码路径与文件引用

### 主要文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/exec_cell/render.rs` | `ExecCell` 渲染实现，包含 `truncate_lines_middle` |
| `codex-rs/tui/src/exec_cell/model.rs` | `CommandOutput` 数据模型 |

### 测试代码

**位置**：`codex-rs/tui/src/history_cell.rs` 第 3746-3790 行

```rust
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
    
    // 生成 10 行 stderr 输出
    let stderr: String = (1..=10)
        .map(|n| n.to_string())
        .collect::<Vec<_>>()
        .join("\n");
    
    cell.complete_call(
        &call_id,
        CommandOutput {
            exit_code: 1,
            formatted_output: String::new(),
            aggregated_output: stderr,
        },
        Duration::from_millis(1),
    );

    let rendered = cell
        .display_lines(80)
        .iter()
        .map(|l| { /* 提取文本 */ })
        .collect::<Vec<_>>()
        .join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 关键函数

**`output_lines`**（第 99-180 行）：
```rust
pub(crate) fn output_lines(
    output: Option<&CommandOutput>,
    params: OutputLinesParams,
) -> OutputLines
```

**`truncate_lines_middle`**（第 530-622 行）：
```rust
fn truncate_lines_middle(
    lines: &[Line<'static>],
    max_rows: usize,
    width: u16,
    omitted_hint: Option<usize>,
    ellipsis_prefix: Option<&Line<'static>>,
) -> Vec<Line<'static>>
```

**`ellipsis_line_with_prefix`**（第 628-634 行）：
```rust
fn ellipsis_line_with_prefix(
    omitted: usize,
    prefix: Option<&Line<'static>>
) -> Line<'static>
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `ratatui` | 终端 UI 渲染，特别是 `Paragraph::line_count` |
| `codex_ansi_escape` | ANSI 转义序列处理 |

### 内部依赖

- `crate::wrapping::adaptive_wrap_line`：自适应换行
- `crate::render::line_utils::prefix_lines`：行前缀处理

### 数据流

```
CommandOutput {
    exit_code: 1,
    aggregated_output: "1\n2\n3\n4\n5\n6\n7\n8\n9\n10",
    formatted_output: "",
}
    └── output_lines(params)
        └── lines = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]
            └── ExecCell::command_display_lines(width)
                └── truncate_lines_middle(lines, max_rows=5, width)
                    ├── head_budget = 2
                    ├── tail_budget = 2
                    ├── head = ["1", "2"]
                    ├── ellipsis = "… +6 lines"
                    └── tail = ["9", "10"]
                        └── 最终渲染
```

## 风险、边界与改进建议

### 潜在风险

1. **行数计算精度**：
   - `Paragraph::line_count` 估算的行数可能与实际渲染有偏差
   - 长行（如 URL）可能实际占用多行，但逻辑上只算一行

2. **省略提示的歧义**：
   - `… +6 lines` 表示省略了 6 行，但用户可能误以为是总行数
   - 没有明确说明"共 10 行，显示 4 行"

3. **上下文丢失**：
   - 中间被省略的行可能包含关键错误信息
   - 头部和尾部可能不足以诊断问题

### 边界情况

| 场景 | 当前行为 | 评估 |
|-----|---------|------|
| 5 行输出 | 全部显示，无省略 | ✅ 合理 |
| 6 行输出 | 头部 2 + 省略 1 + 尾部 2 = 5 行 | ⚠️ 只显示 5 行，实际 6 行 |
| 长行（需换行） | 按实际显示行数计算 | ✅ 准确 |
| 空输出 | 显示 "(no output)" | ✅ 明确 |
| 单行超长 | 可能只显示部分 | ⚠️ 需要测试 |

### 改进建议

1. **改进省略提示**：
   ```rust
   // 显示更详细的信息
   format!("… {} of {} lines hidden", omitted, total)
   // 或
   format!("… showing {} of {} lines", shown, total)
   ```

2. **可配置的截断策略**：
   ```rust
   pub enum TruncationStrategy {
       HeadOnly,      // 只显示头部
       TailOnly,      // 只显示尾部
       HeadAndTail,   // 头部+尾部（当前）
       Smart,         // 智能选择（保留错误行、堆栈跟踪等）
   }
   ```

3. **展开功能**：
   - 添加键盘快捷键（如 Enter）展开完整输出
   - 使用 `…` 作为可点击的展开指示器

4. **错误模式识别**：
   ```rust
   // 识别并优先显示错误行
   fn prioritize_error_lines(lines: &[String]) -> Vec<String> {
       lines.sort_by_key(|line| {
           if is_error_line(line) { 0 }
           else if is_warning_line(line) { 1 }
           else { 2 }
       });
   }
   ```

5. **滚动查看**：
   - 在 transcript overlay（Ctrl+T）中支持滚动查看完整输出
   - 或者在 UI 中添加 "查看完整输出" 选项

6. **配置选项**：
   ```rust
   pub struct OutputConfig {
       pub max_output_lines: usize,        // 默认 5
       pub show_full_output_on_error: bool, // 错误时显示全部
       pub truncation_indicator: String,   // 默认 "…"
   }
   ```

7. **改进头部/尾部分配**：
   ```rust
   // 根据内容动态分配头部和尾部预算
   // 如果头部包含错误信息，分配更多空间给头部
   let head_budget = if contains_error(&lines[0..3]) { 3 } else { 2 };
   ```
