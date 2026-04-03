# 多行命令无换行分支与八空格缩进测试快照研究文档

## 场景与职责

本快照测试验证 **ExecCell** 对多行命令的渲染，当命令**不需要换行**（即每行都能在终端宽度内完整显示）时的前缀处理。重点验证多行命令的结构化展示，使用分支符号（│）和适当的缩进来清晰区分命令的不同行。

测试场景：
- 命令包含两行（`echo one` 和 `echo two`）
- 终端宽度（80字符）足够容纳完整命令
- 验证无换行时的前缀一致性

## 功能点目的

### 核心功能
1. **多行命令展示**：将多行 bash 命令按原始结构展示
2. **视觉层次**：使用树形分支符号创建清晰的视觉层次
3. **前缀一致性**：即使不换行也保持统一的前缀风格

### 展示目标
- 标题行显示 "• Ran " + 第一行命令
- 后续每行命令前使用 "  │ " 前缀
- 输出块使用 "  └ " 前缀
- 清晰展示命令的原始多行结构

## 具体技术实现

### 渲染布局配置

位于 `exec_cell/render.rs`（行 637-656）：

```rust
#[derive(Clone, Copy)]
struct PrefixedBlock {
    initial_prefix: &'static str,      // "  │ "
    subsequent_prefix: &'static str,   // "  │ "
}

impl PrefixedBlock {
    const fn new(initial_prefix: &'static str, subsequent_prefix: &'static str) -> Self {
        Self { initial_prefix, subsequent_prefix }
    }
    
    fn wrap_width(self, total_width: u16) -> usize {
        let prefix_width = UnicodeWidthStr::width(self.initial_prefix)
            .max(UnicodeWidthStr::width(self.subsequent_prefix));
        usize::from(total_width).saturating_sub(prefix_width).max(1)
    }
}
```

### 关键渲染逻辑

位于 `exec_cell/render.rs` 的 `command_display_lines` 方法（行 398-431）：

```rust
fn command_display_lines(&self, width: u16) -> Vec<Line<'static>> {
    // ...
    let cmd_display = strip_bash_lc_and_escape(&call.command);
    let highlighted_lines = highlight_bash_to_lines(&cmd_display);
    
    let continuation_wrap_width = layout.command_continuation.wrap_width(width);
    let continuation_opts = RtOptions::new(continuation_wrap_width)
        .word_splitter(WordSplitter::NoHyphenation);
    
    let mut continuation_lines: Vec<Line<'static>> = Vec::new();
    
    if let Some((first, rest)) = highlighted_lines.split_first() {
        // 第一行处理
        let available_first_width = (width as usize).saturating_sub(header_prefix_width).max(1);
        let first_opts = RtOptions::new(available_first_width)
            .word_splitter(WordSplitter::NoHyphenation);
        
        let mut first_wrapped: Vec<Line<'static>> = Vec::new();
        push_owned_lines(&adaptive_wrap_line(first, first_opts), &mut first_wrapped);
        
        if let Some(first_segment) = first_wrapped_iter.next() {
            header_line.extend(first_segment);
        }
        continuation_lines.extend(first_wrapped_iter);
        
        // 处理后续行（原始多行命令的剩余行）
        for line in rest {
            push_owned_lines(
                &adaptive_wrap_line(line, continuation_opts.clone()),
                &mut continuation_lines,
            );
        }
    }
    
    // 应用前缀到续行
    if !continuation_lines.is_empty() {
        lines.extend(prefix_lines(
            continuation_lines,
            Span::from(layout.command_continuation.initial_prefix).dim(),
            Span::from(layout.command_continuation.subsequent_prefix).dim(),
        ));
    }
    // ...
}
```

### 前缀应用工具函数

位于 `codex-rs/tui/src/render/line_utils.rs`：

```rust
/// 为每行添加前缀，第一行使用 initial_prefix，后续行使用 subsequent_prefix
pub fn prefix_lines(
    lines: Vec<Line<'static>>,
    initial_prefix: impl Into<Span<'static>>,
    subsequent_prefix: impl Into<Span<'static>>,
) -> Vec<Line<'static>> {
    let initial_prefix = initial_prefix.into();
    let subsequent_prefix = subsequent_prefix.into();
    
    lines.into_iter().enumerate().map(|(idx, mut line)| {
        let prefix = if idx == 0 { &initial_prefix } else { &subsequent_prefix };
        line.spans.insert(0, prefix.clone());
        line
    }).collect()
}
```

### 测试用例构造

位于 `history_cell.rs` 测试模块（行 3700-3720）：

```rust
#[test]
fn multiline_command_without_wrap_uses_branch_then_eight_spaces() {
    let call_id = "c1".to_string();
    // 两行短命令，不需要换行
    let cmd = "echo one\necho two".to_string();
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
    
    // 足够宽的终端（80字符）
    let lines = cell.display_lines(80);
    let rendered = render_lines(&lines).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 快照输出分析

```
• Ran echo one
  │ echo two
  └ (no output)
```

输出结构解析：
1. `• Ran echo one` - 标题行，包含第一行命令
   - `•` - 状态指示器（绿色粗体表示成功）
   - `Ran` - 动作标签（粗体）
   - `echo one` - 第一行命令内容

2. `  │ echo two` - 第二行命令
   - `  │ ` - 分支前缀（4空格 + 分支符号 + 1空格）
   - `echo two` - 第二行命令内容

3. `  └ (no output)` - 输出块
   - `  └ ` - 结束前缀（4空格 + 角符号 + 1空格）
   - `(no output)` - 无输出提示（暗淡斜体）

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/exec_cell/render.rs` | ExecCell 渲染逻辑 |
| `codex-rs/tui/src/render/line_utils.rs` | 行工具函数，包含 `prefix_lines` |
| `codex-rs/tui/src/history_cell.rs` | 测试用例定义 |

### 关键常量
```rust
// exec_cell/render.rs
const EXEC_DISPLAY_LAYOUT: ExecDisplayLayout = ExecDisplayLayout::new(
    PrefixedBlock::new("  │ ", "  │ "),  // 命令续行：4字符前缀
    /*command_continuation_max_lines*/ 2,
    PrefixedBlock::new("  └ ", "    "),    // 输出块：4字符前缀
    /*output_max_lines*/ 5,
);
```

### 前缀宽度分析
| 前缀 | 字符 | 显示宽度 | Unicode 名称 |
|-----|------|---------|-------------|
| `  │ ` | 空格+空格+│+空格 | 4 | U+2502 Box Drawings Light Vertical |
| `  └ ` | 空格+空格+└+空格 | 4 | U+2514 Box Drawings Light Up And Right |
| `    ` | 四个空格 | 4 | - |

## 依赖与外部交互

### 内部依赖
- `unicode_width::UnicodeWidthStr` - Unicode 字符串宽度计算
- `ratatui::style::Stylize` - 样式应用（dim, bold 等）
- `textwrap::WordSplitter` - 单词分割策略

### 样式应用
```rust
// 前缀样式：暗淡（dim）
Span::from(layout.command_continuation.initial_prefix).dim()

// 标题样式
vec![
    bullet.clone(),           // 状态指示器
    " ".into(),
    title.bold(),             // "Ran" 粗体
    " ".into(),
]

// 无输出提示样式
Line::from("(no output)").dim().italic()
```

## 风险、边界与改进建议

### 潜在风险
1. **字符对齐**：不同终端对 Unicode 框线字符的宽度渲染可能不一致
2. **字体支持**：某些字体可能不支持框线字符，显示为方框或问号
3. **复制粘贴**：带前缀的文本被复制时可能包含不需要的前缀字符

### 边界情况
1. **空命令行**：多行命令中包含空行的展示
   ```bash
   echo one
   
   echo two
   ```

2. **仅空白字符的行**：只包含空格或制表符的行

3. **前缀冲突**：命令内容本身以空格开头时的对齐问题

### 改进建议

#### 高优先级
1. **终端能力检测**：检测终端对 Unicode 框线字符的支持
   ```rust
   fn supports_box_drawing() -> bool {
       // 检测 $TERM 和 terminfo
   }
   ```

2. **ASCII 降级**：在不支持 Unicode 的终端使用 ASCII 替代
   ```
   | 替代 │
   `- 替代 └
   ```

#### 中优先级
3. **复制模式**：提供无前缀的纯文本复制模式
4. **可配置前缀**：允许用户自定义前缀字符

#### 低优先级
5. **行号显示**：可选显示命令行号
   ```
   • Ran echo one
   2│ echo two
   3│ echo three
   ```

6. **语法高亮**：对命令内容进行 bash 语法高亮

### 测试建议
1. 增加不同终端模拟器的渲染测试
2. 增加复制粘贴功能测试
3. 增加可访问性测试（屏幕阅读器对框线字符的朗读）
