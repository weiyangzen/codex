# Research: 后台进程输出前导空白测试快照

## 场景与职责

该快照测试验证 `UnifiedExecProcessesCell` 在渲染后台进程输出时，正确处理输出块（chunks）中包含的前导空白字符（缩进）。

这是 Codex TUI 后台终端管理功能的一部分，用于显示 `/ps` 命令的输出，展示正在运行的后台进程及其最近输出。

## 功能点目的

1. **保留原始缩进**: 保持进程输出中的前导空白字符
2. **层次化显示**: 使用缩进表示输出的层次结构
3. **命令显示**: 显示后台进程的命令
4. **输出预览**: 显示每个进程的最近输出块

## 具体技术实现

### 渲染格式

```
/ps

Background terminals

  • just fix
    ↳   indented first
          more indented
```

格式说明：
- `/ps`: 命令标识
- `Background terminals`: 标题
- `• just fix`: 进程命令（青色显示）
- `↳ `: 输出块前缀
- `  indented first`: 包含前导空格的输出内容
- `    more indented`: 更多缩进的输出

### 关键数据结构

```rust
// UnifiedExecProcessDetails（history_cell.rs:656-660）
#[derive(Debug, Clone)]
pub(crate) struct UnifiedExecProcessDetails {
    pub(crate) command_display: String,
    pub(crate) recent_chunks: Vec<String>,
}

// UnifiedExecProcessesCell（history_cell.rs:645-654）
#[derive(Debug)]
struct UnifiedExecProcessesCell {
    processes: Vec<UnifiedExecProcessDetails>,
}
```

### 渲染逻辑

```rust
// history_cell.rs:662-770
impl HistoryCell for UnifiedExecProcessesCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        // ...
        for process in &self.processes {
            // 显示命令
            let command = &process.command_display;
            // ... 截断处理 ...
            out.push(vec![prefix.dim(), truncated.cyan()].into());

            // 显示输出块
            let chunk_prefix_first = "    ↳ ";
            let chunk_prefix_next = "      ";
            for (idx, chunk) in process.recent_chunks.iter().enumerate() {
                let chunk_prefix = if idx == 0 {
                    chunk_prefix_first
                } else {
                    chunk_prefix_next
                };
                // 保留 chunk 中的前导空白
                let (truncated, remainder, _) = take_prefix_by_width(chunk, budget);
                // ...
            }
        }
        out
    }
}
```

### 测试数据构造

```rust
// history_cell.rs:2848-2858
let cell = new_unified_exec_processes_output(vec![UnifiedExecProcessDetails {
    command_display: "just fix".to_string(),
    recent_chunks: vec![
        "  indented first".to_string(),  // 2 空格前导
        "    more indented".to_string(), // 4 空格前导
    ],
}]);
let rendered = render_lines(&cell.display_lines(60)).join("\n");
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/history_cell.rs` | UnifiedExecProcessesCell 实现，测试位于行 2848-2858 |
| `codex-rs/tui/src/live_wrap.rs` | `take_prefix_by_width` 函数 |

### 测试代码位置

```rust
// history_cell.rs:2848-2858
#[test]
fn ps_output_chunk_leading_whitespace_snapshot() {
    let cell = new_unified_exec_processes_output(vec![UnifiedExecProcessDetails {
        command_display: "just fix".to_string(),
        recent_chunks: vec![
            "  indented first".to_string(),
            "    more indented".to_string(),
        ],
    }]);
    let rendered = render_lines(&cell.display_lines(60)).join("\n");
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

1. **宽度计算**: 前导空白字符的宽度计算必须准确
2. **截断位置**: 在空白字符处截断可能导致视觉上的不对齐
3. **终端兼容性**: 某些终端可能对前导空格的渲染有差异

### 边界情况

1. **全空白块**: 输出块只包含空白字符
2. **制表符**: 输出块包含制表符时的宽度计算
3. **Unicode 空白**: 非 ASCII 空白字符（如全角空格）

### 改进建议

1. **制表符展开**: 将制表符展开为空格，确保一致的缩进显示
2. **空白可视化**: 可选显示空白字符（如使用特殊符号）
3. **语法高亮**: 对代码输出进行语法高亮
4. **折叠长输出**: 对于超长的输出块提供折叠功能

### 相关快照文件

- `ps_output_empty_snapshot.snap` - 空进程列表测试
- `ps_output_long_command_snapshot.snap` - 长命令截断测试
- `ps_output_many_sessions_snapshot.snap` - 多进程测试
- `ps_output_multiline_snapshot.snap` - 多行输出测试
