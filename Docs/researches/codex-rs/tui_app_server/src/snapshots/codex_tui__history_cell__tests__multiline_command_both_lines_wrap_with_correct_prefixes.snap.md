# 多行命令双行换行前缀测试快照研究文档

## 场景与职责

本快照测试验证 **ExecCell** 对多行命令的渲染能力，特别是当命令的**每一行都超过终端宽度需要换行**时的前缀处理。这是 TUI 历史记录系统中命令展示的核心功能，确保用户能够清晰地识别命令的结构，即使命令很长需要换行显示。

测试场景：
- 命令包含两行，每行都很长
- 终端宽度限制（28字符）强制每行换行
- 验证换行后的前缀一致性

## 功能点目的

### 核心功能
1. **多行命令识别**：识别通过 `\n` 分隔的多行 bash 命令
2. **自适应换行**：根据可用宽度自动换行长命令
3. **前缀一致性**：确保换行后的续行使用正确的前缀缩进

### 展示目标
- 第一行命令前显示 "• Ran " 前缀
- 续行使用 "  │ "（分支线）前缀
- 输出块使用 "  └ "（结束线）前缀
- 清晰区分命令的不同行

## 具体技术实现

### 数据结构

```rust
// ExecCell 结构（exec_cell/model.rs）
pub(crate) struct ExecCell {
    pub(crate) calls: Vec<ExecCall>,
    animations_enabled: bool,
}

pub(crate) struct ExecCall {
    pub(crate) call_id: String,
    pub(crate) command: Vec<String>,  // ["bash", "-lc", "script_with_newlines"]
    pub(crate) parsed: Vec<ParsedCommand>,
    pub(crate) output: Option<CommandOutput>,
    pub(crate) source: ExecCommandSource,
    ...
}
```

### 渲染布局配置

位于 `exec_cell/render.rs`（行 682-687）：

```rust
const EXEC_DISPLAY_LAYOUT: ExecDisplayLayout = ExecDisplayLayout::new(
    PrefixedBlock::new("  │ ", "  │ "),  // 命令续行前缀
    /*command_continuation_max_lines*/ 2,   // 最大续行数
    PrefixedBlock::new("  └ ", "    "),    // 输出块前缀
    /*output_max_lines*/ 5,
);
```

### 关键渲染逻辑

位于 `exec_cell/render.rs` 的 `command_display_lines` 方法（行 356-499）：

```rust
fn command_display_lines(&self, width: u16) -> Vec<Line<'static>> {
    // ...
    let cmd_display = strip_bash_lc_and_escape(&call.command);
    let highlighted_lines = highlight_bash_to_lines(&cmd_display);
    
    // 第一行处理：尝试与标题放在同一行
    if let Some((first, rest)) = highlighted_lines.split_first() {
        let available_first_width = (width as usize).saturating_sub(header_prefix_width).max(1);
        let first_opts = RtOptions::new(available_first_width)
            .word_splitter(WordSplitter::NoHyphenation);
        
        let mut first_wrapped: Vec<Line<'static>> = Vec::new();
        push_owned_lines(&adaptive_wrap_line(first, first_opts), &mut first_wrapped);
        
        // 第一行片段附加到标题
        if let Some(first_segment) = first_wrapped_iter.next() {
            header_line.extend(first_segment);
        }
        // 第一行剩余片段作为续行
        continuation_lines.extend(first_wrapped_iter);
        
        // 处理后续行（原始多行命令的剩余行）
        for line in rest {
            push_owned_lines(
                &adaptive_wrap_line(line, continuation_opts.clone()),
                &mut continuation_lines,
            );
        }
    }
    // ...
}
```

### 测试用例构造

位于 `history_cell.rs` 测试模块（行 3723-3744）：

```rust
#[test]
fn multiline_command_both_lines_wrap_with_correct_prefixes() {
    let call_id = "c1".to_string();
    // 两行命令，每行都足够长以至于需要换行
    let cmd = "first_token_is_long_enough_to_wrap\nsecond_token_is_also_long_enough_to_wrap"
        .to_string();
    let mut cell = ExecCell::new(
        ExecCall {
            call_id: call_id.clone(),
            command: vec!["bash".into(), "-lc".into(), cmd],
            parsed: Vec::new(),
            output: None,
            source: ExecCommandSource::Agent,
            start_time: Some(Instant::now()),
            duration: None,
            interaction_input: None,
        },
        true,
    );
    cell.complete_call(&call_id, CommandOutput::default(), Duration::from_millis(1));
    
    // 窄宽度 28 强制换行
    let width: u16 = 28;
    let lines = cell.display_lines(width);
    let rendered = render_lines(&lines).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 快照输出分析

```
• Ran first_token_is_long_en
  │ ough_to_wrap
  │ second_token_is_also_lon
  │ … +1 lines
  └ (no output)
```

输出结构解析：
1. `• Ran first_token_is_long_en` - 标题行，第一行命令片段
2. `  │ ough_to_wrap` - 第一行命令的续行
3. `  │ second_token_is_also_lon` - 第二行命令的开始
4. `  │ … +1 lines` - 省略指示（超过最大续行数）
5. `  └ (no output)` - 输出块

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/exec_cell/render.rs` | ExecCell 渲染逻辑，包含 `command_display_lines` |
| `codex-rs/tui/src/exec_cell/model.rs` | ExecCell 和 ExecCall 数据结构 |
| `codex-rs/tui/src/history_cell.rs` | 测试用例定义 |
| `codex-rs/tui/src/wrapping.rs` | 自适应换行工具 |

### 关键函数
| 函数 | 位置 | 职责 |
|-----|------|------|
| `command_display_lines` | `render.rs:356` | 主渲染方法 |
| `adaptive_wrap_line` | `wrapping.rs` | 自适应单行换行 |
| `adaptive_wrap_lines` | `wrapping.rs` | 自适应多行换行 |
| `strip_bash_lc_and_escape` | `exec_command.rs` | 提取 bash 命令 |
| `highlight_bash_to_lines` | `render/highlight.rs` | Bash 语法高亮 |

### 前缀常量
```rust
// 命令续行前缀
const COMMAND_CONTINUATION_PREFIX: &str = "  │ ";

// 输出块前缀
const OUTPUT_BLOCK_INITIAL_PREFIX: &str = "  └ ";
const OUTPUT_BLOCK_SUBSEQUENT_PREFIX: &str = "    ";
```

## 依赖与外部交互

### 内部依赖
- `textwrap` - 文本换行库
- `ratatui` - TUI 渲染框架
- `codex_shell_command::bash::extract_bash_command` - Bash 命令提取
- `codex_ansi_escape::ansi_escape_line` - ANSI 转义处理

### 渲染流程
```
ExecCall (command: ["bash", "-lc", "script"])
    ↓
strip_bash_lc_and_escape() → "script_content"
    ↓
highlight_bash_to_lines() → Vec<Line> (语法高亮)
    ↓
split_first() → (first_line, rest_lines)
    ↓
adaptive_wrap_line() → 第一行可能分割为多段
    ↓
标题行: "• Ran " + first_segment
续行: "  │ " + continuation_segments
    ↓
rest_lines 每行: "  │ " + wrapped_content
    ↓
输出块: "  └ " + output
```

## 风险、边界与改进建议

### 潜在风险
1. **前缀错位**：换行计算错误导致前缀不对齐
2. **宽度计算**：Unicode 字符宽度计算不准确导致溢出
3. **省略过早**：`command_continuation_max_lines` 限制可能截断重要命令

### 边界情况
1. **零宽度字符**：零宽字符（如 ZWJ）可能影响宽度计算
2. **RTL 文本**：从右到左文本的布局问题
3. **极窄终端**：宽度小于前缀长度时的处理
4. **空行处理**：多行命令中的空行展示

### 改进建议

#### 高优先级
1. **动态最大行数**：根据终端高度动态调整 `command_continuation_max_lines`
   ```rust
   fn dynamic_max_lines(terminal_height: u16) -> usize {
       (terminal_height as usize / 4).max(2).min(10)
   }
   ```

2. **智能截断指示**：显示被截断的内容概览而非简单省略
   ```
   … +1 lines (contains: grep, sort, uniq)
   ```

#### 中优先级
3. **可折叠命令**：支持用户展开/折叠长命令
4. **语法高亮优化**：对截断的命令保持语法高亮一致性

#### 低优先级
5. **命令折叠提示**：显示命令行数的视觉指示器
6. **复制完整命令**：提供复制原始命令的快捷方式

### 测试建议
1. 增加极端宽度测试（1字符、1000字符）
2. 增加 Unicode 字符测试（emoji、CJK、组合字符）
3. 增加性能测试（1000行命令的渲染时间）
4. 增加可访问性测试（屏幕阅读器兼容性）
