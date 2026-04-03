# 研究文档：single_line_command_compact_when_fits

## 场景与职责

该快照测试验证 `ExecCell` 在命令较短且能在单行内完整显示时的紧凑渲染行为。当执行的命令足够短，可以与 "Ran" 标题内联显示时，系统应该采用紧凑布局以节省屏幕空间。

**核心职责**：
- 检测命令长度是否适合内联显示
- 在紧凑模式下将命令与标题放在同一行
- 对于无输出的命令显示 "(no output)" 提示
- 保持视觉层次清晰

## 功能点目的

**从快照内容分析**：
```
• Ran echo ok
  └ (no output)
```

**功能特性**：
1. **紧凑头部**：`• Ran echo ok` - 命令与标题内联显示
2. **无输出提示**：`(no output)` 以暗淡样式显示
3. **视觉前缀**：使用 `└` 符号标记输出块的开始
4. **状态指示**：绿色/红色粗体点表示执行状态

## 具体技术实现

### 紧凑模式检测

**代码位置**：`codex-rs/tui/src/exec_cell/render.rs` 第 378-419 行

```rust
let mut header_line = if is_interaction {
    Line::from(vec![bullet.clone(), " ".into()])
} else {
    Line::from(vec![bullet.clone(), " ".into(), title.bold(), " ".into()])
};
let header_prefix_width = header_line.width();

// 计算命令显示
let cmd_display = if call.is_unified_exec_interaction() {
    format_unified_exec_interaction(&call.command, call.interaction_input.as_deref())
} else {
    strip_bash_lc_and_escape(&call.command)
};
let highlighted_lines = highlight_bash_to_lines(&cmd_display);

// 尝试内联显示
let available_first_width = (width as usize).saturating_sub(header_prefix_width).max(1);
let first_opts = RtOptions::new(available_first_width)
    .word_splitter(WordSplitter::NoHyphenation);

let mut first_wrapped: Vec<Line<'static>> = Vec::new();
push_owned_lines(&adaptive_wrap_line(first, first_opts), &mut first_wrapped);

let mut first_wrapped_iter = first_wrapped.into_iter();
if let Some(first_segment) = first_wrapped_iter.next() {
    header_line.extend(first_segment);  // 内联到头部
}
```

### 紧凑模式条件

命令能够内联显示的条件：
1. 命令的第一行（去除 bash `-lc` 包装后）能够放入 `available_first_width`
2. `available_first_width = width - header_prefix_width`
3. 对于 "Ran echo ok"：`header_prefix_width` ≈ 10 字符（`• Ran `）

### 无输出处理

**代码位置**：第 454-461 行

```rust
if raw_output.lines.is_empty() {
    if !call.is_unified_exec_interaction() {
        lines.extend(prefix_lines(
            vec![Line::from("(no output)".dim())],
            Span::from(layout.output_block.initial_prefix).dim(),  // "  └ "
            Span::from(layout.output_block.subsequent_prefix),      // "    "
        ));
    }
}
```

### 布局常量

```rust
const EXEC_DISPLAY_LAYOUT: ExecDisplayLayout = ExecDisplayLayout::new(
    PrefixedBlock::new("  │ ", "  │ "),  // 命令延续前缀（本测试未使用）
    /*command_continuation_max_lines*/ 2,
    PrefixedBlock::new("  └ ", "    "),   // 输出块前缀
    /*output_max_lines*/ 5,
);
```

## 关键代码路径与文件引用

### 主要文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/exec_cell/render.rs` | `ExecCell::command_display_lines` 实现 |
| `codex-rs/tui/src/exec_cell/model.rs` | `ExecCell` 和 `ExecCall` 数据模型 |

### 测试代码

**位置**：`codex-rs/tui/src/history_cell.rs` 第 3653-3674 行

```rust
#[test]
fn single_line_command_compact_when_fits() {
    let call_id = "c1".to_string();
    let mut cell = ExecCell::new(
        ExecCall {
            call_id: call_id.clone(),
            command: vec!["echo".into(), "ok".into()],  // 短命令
            parsed: Vec::new(),
            output: None,  // 无输出
            source: ExecCommandSource::Agent,
            start_time: Some(Instant::now()),
            duration: None,
            interaction_input: None,
        },
        true,
    );
    cell.complete_call(&call_id, CommandOutput::default(), Duration::from_millis(1));
    
    // 宽度 80 足够内联显示
    let lines = cell.display_lines(80);
    let rendered = render_lines(&lines).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 关键函数

**`strip_bash_lc_and_escape`**（`codex-rs/tui/src/exec_command.rs`）：
```rust
pub fn strip_bash_lc_and_escape(command: &[String]) -> String {
    // 去除 bash -lc 包装，提取实际命令
    if let Some((_, script)) = extract_bash_command(command) {
        script.to_string()
    } else {
        command.join(" ")
    }
}
```

**`highlight_bash_to_lines`**（`codex-rs/tui/src/render/highlight.rs`）：
```rust
pub fn highlight_bash_to_lines(script: &str) -> Vec<Line<'static>> {
    // 对 bash 命令进行语法高亮
}
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `ratatui` | 终端 UI 渲染 |
| `textwrap` | 文本换行处理 |

### 内部依赖

- `crate::exec_command::strip_bash_lc_and_escape`：清理命令显示
- `crate::render::highlight::highlight_bash_to_lines`：语法高亮
- `crate::wrapping::adaptive_wrap_line`：自适应换行
- `crate::render::line_utils::prefix_lines`：行前缀处理

### 渲染流程

```
ExecCell::display_lines(80)
└── command_display_lines(80)
    ├── 1. 构建头部："• Ran "（宽度 ≈ 10）
    ├── 2. 计算可用宽度：80 - 10 = 70
    ├── 3. 命令 "echo ok" 宽度 = 7 < 70
    │   └── 内联显示："• Ran echo ok"
    ├── 4. 无延续行（命令已完全显示）
    └── 5. 无输出，显示：
        └── "  └ (no output)"
```

## 风险、边界与改进建议

### 潜在风险

1. **宽度计算精度**：
   - `header_line.width()` 计算的是逻辑宽度，可能与实际渲染宽度有偏差
   - 如果计算错误，可能导致命令被意外截断或换行

2. **命令提取失败**：
   - `strip_bash_lc_and_escape` 依赖 `extract_bash_command`
   - 如果命令格式不符合预期，可能显示原始命令数组

3. **无输出提示的歧义**：
   - `(no output)` 可能误导用户认为命令没有执行
   - 应该区分 "命令无输出" 和 "输出被过滤"

### 边界情况

| 场景 | 当前行为 | 评估 |
|-----|---------|------|
| 命令刚好填满宽度 | 内联显示 | ✅ 节省空间 |
| 命令超出一个字符 | 换行显示 | ⚠️ 可能显得突兀 |
| 多命令（exploring） | 使用不同布局 | ✅ 区分处理 |
| 用户 shell 命令 | 显示 "You ran" | ✅ 区分来源 |

### 改进建议

1. **智能阈值**：
   ```rust
   // 不仅考虑宽度，还考虑可读性
   fn should_use_compact_layout(command_width: usize, available_width: usize) -> bool {
       let ratio = command_width as f32 / available_width as f32;
       ratio < 0.8  // 留出一些边距
   }
   ```

2. **改进无输出提示**：
   ```rust
   // 显示更多信息
   if exit_code == 0 {
       "  └ ✓ (completed with no output)"
   } else {
       "  └ ✗ (failed with no output)"
   }
   ```

3. **命令长度提示**：
   ```rust
   // 如果命令被截断，显示提示
   if command_width > available_width {
       header_line.push_span(" ...".dim());
   }
   ```

4. **配置选项**：
   ```rust
   pub struct DisplayConfig {
       pub prefer_compact_layout: bool,  // 默认 true
       pub min_compact_width: usize,     // 默认 20
   }
   ```

5. **动画过渡**：
   - 当命令从 "Running" 变为 "Ran" 时，如果布局变化（紧凑↔展开），添加平滑过渡

6. **悬停提示**：
   - 在紧凑模式下，悬停显示完整命令（包括被隐藏的参数）
