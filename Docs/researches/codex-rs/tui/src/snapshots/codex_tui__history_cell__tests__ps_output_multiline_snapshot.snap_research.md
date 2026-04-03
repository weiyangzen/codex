# Research: 后台进程多行输出测试快照

## 场景与职责

该快照测试验证 `UnifiedExecProcessesCell` 在渲染后台进程列表时，正确处理多行命令和多行输出的场景。这包括命令本身包含换行符，以及进程的最近输出包含多行内容的情况。

这是 Codex TUI 后台终端管理功能的核心测试，确保复杂输出格式的正确渲染。

## 功能点目的

1. **多行命令显示**: 正确处理包含换行符的命令
2. **多行输出显示**: 显示进程的多个最近输出块
3. **首行提取**: 从多行命令中提取第一行进行显示
4. **层次化输出**: 使用不同前缀区分命令和输出

## 具体技术实现

### 渲染格式

```
/ps

Background terminals

  • echo hello [...]
    ↳ hello
      done
  • rg "foo" src
    ↳ src/main.rs:12:foo
```

格式说明：
- `echo hello [...]`: 多行命令的第一行 + 截断提示
- `↳ hello`: 第一个输出块
- `done`: 第二个输出块（续行前缀）
- `rg "foo" src`: 单行命令
- `↳ src/main.rs:12:foo`: 进程输出

### 关键代码逻辑

```rust
// history_cell.rs:684-722
// 命令首行提取
let (snippet, snippet_truncated) = {
    let (first_line, has_more_lines) = match command.split_once('\n') {
        Some((first, _)) => (first, true),  // 提取第一行
        None => (command.as_str(), false),
    };
    // ... 字符限制处理
};

// 输出块渲染（history_cell.rs:724-748）
let chunk_prefix_first = "    ↳ ";
let chunk_prefix_next = "      ";
for (idx, chunk) in process.recent_chunks.iter().enumerate() {
    let chunk_prefix = if idx == 0 {
        chunk_prefix_first
    } else {
        chunk_prefix_next
    };
    // 渲染输出块，保留原始内容（包括前导空白）
    let (truncated, remainder, _) = take_prefix_by_width(chunk, budget);
    // ...
}
```

### 测试数据构造

```rust
// history_cell.rs:2806-2819
let cell = new_unified_exec_processes_output(vec![
    UnifiedExecProcessDetails {
        command_display: "echo hello\nand then some extra text".to_string(),
        recent_chunks: vec!["hello".to_string(), "done".to_string()],
    },
    UnifiedExecProcessDetails {
        command_display: "rg \"foo\" src".to_string(),
        recent_chunks: vec!["src/main.rs:12:foo".to_string()],
    },
]);
let rendered = render_lines(&cell.display_lines(40)).join("\n");
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/history_cell.rs` | UnifiedExecProcessesCell 实现，测试位于行 2806-2819 |
| `codex-rs/tui/src/live_wrap.rs` | `take_prefix_by_width` 函数 |

### 测试代码位置

```rust
// history_cell.rs:2806-2819
#[test]
fn ps_output_multiline_snapshot() {
    let cell = new_unified_exec_processes_output(vec![
        UnifiedExecProcessDetails {
            command_display: "echo hello\nand then some extra text".to_string(),
            recent_chunks: vec!["hello".to_string(), "done".to_string()],
        },
        UnifiedExecProcessDetails {
            command_display: "rg \"foo\" src".to_string(),
            recent_chunks: vec!["src/main.rs:12:foo".to_string()],
        },
    ]);
    let rendered = render_lines(&cell.display_lines(40)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

## 依赖与外部交互

### 外部依赖

1. **ratatui**: TUI 渲染框架
2. **unicode-width**: 字符串宽度计算
3. **insta**: 快照测试

### 内部模块依赖

```rust
use crate::live_wrap::take_prefix_by_width;
use unicode_width::UnicodeWidthStr;
```

## 风险、边界与改进建议

### 潜在风险

1. **换行符处理**: 不同操作系统（Windows/Linux/Mac）的换行符差异
2. **输出块顺序**: `recent_chunks` 的顺序必须与预期一致
3. **前缀对齐**: 多行输出时的前缀对齐可能产生视觉偏移

### 边界情况

1. **空输出块**: `recent_chunks` 包含空字符串
2. **大量输出块**: 单个进程有大量输出块时的渲染
3. **超长输出行**: 单行输出超过可用宽度时的截断

### 改进建议

1. **时间戳显示**: 为每个输出块添加时间戳
2. **输出高亮**: 对特定模式（如错误信息）进行高亮
3. **交互式查看**: 支持点击查看进程的完整输出历史
4. **实时更新**: 支持实时更新正在运行的进程输出
5. **颜色保留**: 保留进程输出的 ANSI 颜色代码

### 相关快照文件

- `ps_output_empty_snapshot.snap` - 空进程列表测试
- `ps_output_chunk_leading_whitespace_snapshot.snap` - 带缩进输出测试
- `ps_output_long_command_snapshot.snap` - 长命令截断测试
- `ps_output_many_sessions_snapshot.snap` - 多进程测试
