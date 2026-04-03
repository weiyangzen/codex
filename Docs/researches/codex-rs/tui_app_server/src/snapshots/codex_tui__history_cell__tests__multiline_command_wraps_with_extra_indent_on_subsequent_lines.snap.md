# 多行命令续行额外缩进测试快照研究文档

## 场景与职责

本快照测试验证 **ExecCell** 对多行命令的渲染，特别关注当**第一行命令需要换行**时的缩进处理。测试验证第一行命令的续行（continuation lines）与原始多行命令的后续行之间的视觉区分。

测试场景：
- 命令包含两行（`set -o pipefail` 和 `cargo test --all-features --quiet`）
- 终端宽度限制（28字符）强制第一行换行
- 验证续行使用正确的前缀和缩进

## 功能点目的

### 核心功能
1. **首行换行处理**：当第一行命令超过可用宽度时的换行
2. **续行缩进**：首行换行后的续行使用统一缩进
3. **多行结构保持**：即使首行换行，也保持命令的多行结构

### 展示目标
- 标题行显示 "• Ran " + 第一行命令的开头部分
- 第一行命令的续行使用 "  │ " 前缀
- 原始第二行命令使用 "  │ " 前缀
- 输出块使用 "  └ " 前缀

## 具体技术实现

### 首行宽度计算

位于 `exec_cell/render.rs`（行 399-401）：

```rust
// 计算第一行可用宽度（扣除标题前缀宽度）
let available_first_width = (width as usize)
    .saturating_sub(header_prefix_width)  // "• Ran " 的宽度
    .max(1);

let first_opts = RtOptions::new(available_first_width)
    .word_splitter(WordSplitter::NoHyphenation);
```

### 首行分割逻辑

位于 `exec_cell/render.rs`（行 403-416）：

```rust
let mut first_wrapped: Vec<Line<'static>> = Vec::new();
push_owned_lines(&adaptive_wrap_line(first, first_opts), &mut first_wrapped);
let mut first_wrapped_iter = first_wrapped.into_iter();

// 第一段附加到标题行
if let Some(first_segment) = first_wrapped_iter.next() {
    header_line.extend(first_segment);
}
// 剩余段作为续行
continuation_lines.extend(first_wrapped_iter);

// 处理原始多行命令的剩余行
for line in rest {
    push_owned_lines(
        &adaptive_wrap_line(line, continuation_opts.clone()),
        &mut continuation_lines,
    );
}
```

### 前缀应用

位于 `exec_cell/render.rs`（行 421-431）：

```rust
let continuation_lines = Self::limit_lines_from_start(
    &continuation_lines,
    layout.command_continuation_max_lines,
);
if !continuation_lines.is_empty() {
    lines.extend(prefix_lines(
        continuation_lines,
        Span::from(layout.command_continuation.initial_prefix).dim(),  // "  │ "
        Span::from(layout.command_continuation.subsequent_prefix).dim(), // "  │ "
    ));
}
```

### 测试用例构造

位于 `history_cell.rs` 测试模块（行 3626-3651）：

```rust
#[test]
fn multiline_command_wraps_with_extra_indent_on_subsequent_lines() {
    // 多行命令，第一行会换行
    let cmd = "set -o pipefail\ncargo test --all-features --quiet".to_string();
    let call_id = "c1".to_string();
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

    // 窄宽度 28 强制第一行换行
    let width: u16 = 28;
    let lines = cell.display_lines(width);
    let rendered = render_lines(&lines).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 快照输出分析

```
• Ran set -o pipefail
  │ cargo test
  │ --all-features --quiet
  └ (no output)
```

输出结构解析：
1. `• Ran set -o pipefail` - 标题行
   - `•` - 状态指示器
   - `Ran` - 动作标签
   - `set -o pipefail` - 第一行命令（完整显示，未超过宽度）

2. `  │ cargo test` - 第二行命令的开始
   - `  │ ` - 分支前缀
   - `cargo test` - 第二行命令的开头

3. `  │ --all-features --quiet` - 第二行命令的续行
   - `  │ ` - 分支前缀（与上一行相同）
   - `--all-features --quiet` - 第二行命令的剩余部分

4. `  └ (no output)` - 输出块

**注意**：在此测试中，第一行 `set -o pipefail` 实际上在 28 字符宽度内可以完整显示（`• Ran ` = 6字符 + `set -o pipefail` = 16字符 = 22字符 < 28字符），所以不需要换行。第二行 `cargo test --all-features --quiet` 较长，需要换行。

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/exec_cell/render.rs` | ExecCell 渲染逻辑 |
| `codex-rs/tui/src/wrapping.rs` | 自适应换行实现 |
| `codex-rs/tui/src/history_cell.rs` | 测试用例定义 |

### 关键函数
| 函数 | 位置 | 职责 |
|-----|------|------|
| `adaptive_wrap_line` | `wrapping.rs` | 自适应单行换行，保持 URL 等token完整 |
| `push_owned_lines` | `render/line_utils.rs` | 将换行结果推入行集合 |
| `limit_lines_from_start` | `render.rs:501` | 限制续行数量，防止过长 |

### 自适应换行特性

```rust
// wrapping.rs
pub fn adaptive_wrap_line(line: &Line, opts: RtOptions) -> Vec<Line<'static>> {
    // 使用 textwrap 但保持 URL-like token 不被分割
    // 检测包含 / 或 . 的长token，避免在中间断开
}
```

## 依赖与外部交互

### 内部依赖
- `textwrap::WrapAlgorithm::FirstFit` - 首选适配换行算法
- `textwrap::WordSplitter::NoHyphenation` - 禁用连字符分割

### 换行算法
```rust
RtOptions::new(width)
    .wrap_algorithm(textwrap::WrapAlgorithm::FirstFit)
    .word_splitter(WordSplitter::NoHyphenation)
```

### 行数限制
```rust
const EXEC_DISPLAY_LAYOUT: ExecDisplayLayout = ExecDisplayLayout::new(
    PrefixedBlock::new("  │ ", "  │ "),
    /*command_continuation_max_lines*/ 2,  // 最多显示 2 行续行
    PrefixedBlock::new("  └ ", "    "),
    /*output_max_lines*/ 5,
);
```

## 风险、边界与改进建议

### 潜在风险
1. **行数限制导致信息丢失**：`command_continuation_max_lines = 2` 可能截断重要命令
2. **换行位置不自然**：在参数中间换行可能影响可读性
3. **宽字符处理**：CJK 字符的宽度计算可能导致换行位置偏差

### 边界情况
1. **超长单token**：如极长的文件路径或 URL
   ```bash
   cat /very/long/path/to/some/deeply/nested/file/in/the/project
   ```

2. **混合宽度字符**：ASCII 和 CJK 字符混合时的对齐

3. **连续多行换行**：三行以上命令，每行都换行

### 改进建议

#### 高优先级
1. **智能换行**：在参数边界处换行而非字符边界
   ```rust
   // 当前：cargo test --all-fea
   //        tures --quiet
   // 
   // 改进：cargo test
   //        --all-features --quiet
   ```

2. **增加续行限制**：根据终端高度动态调整
   ```rust
   fn calculate_max_lines(terminal_height: u16, content_lines: usize) -> usize {
       let available = terminal_height.saturating_sub(10) as usize;
       content_lines.min(available).max(3)
   }
   ```

#### 中优先级
3. **参数感知分割**：理解命令参数结构，在 `--` 或 `-` 前换行
4. **折叠指示器**：显示被折叠的命令概览

#### 低优先级
5. **水平滚动**：对于极长命令，支持水平滚动而非换行
6. **工具提示**：悬停显示完整命令

### 测试建议
1. 增加极端长 token 测试（1000+ 字符路径）
2. 增加混合语言测试（中英文混合命令）
3. 增加嵌套命令测试（`$(...)` 和 `` `...` ``）
4. 增加管道命令测试（`cmd1 | cmd2 | cmd3`）
