# Research: 后台进程多会话测试快照

## 场景与职责

该快照测试验证 `UnifiedExecProcessesCell` 在渲染后台进程列表时，对大量进程的处理能力。当运行的后台进程数量超过显示限制（16个）时，需要正确截断列表并显示剩余数量提示。

这是 Codex TUI 后台终端管理功能的重要测试，确保在大量后台进程场景下的性能和用户体验。

## 功能点目的

1. **数量限制**: 最多显示 16 个后台进程
2. **剩余提示**: 显示 "... and X more running" 提示剩余进程数
3. **性能保护**: 避免在进程过多时渲染性能下降
4. **信息完整**: 即使截断也让用户了解完整情况

## 具体技术实现

### 渲染格式

```
/ps

Background terminals

  • command 0
  • command 1
  • command 2
  ...
  • command 15
  • ... and 4 more running
```

格式说明：
- 显示前 16 个进程（command 0 到 command 15）
- `... and 4 more running`: 剩余 4 个进程的提示

### 关键代码逻辑

```rust
// history_cell.rs:662-770
impl HistoryCell for UnifiedExecProcessesCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        // ...
        let max_processes = 16usize;  // 最大显示数量
        let mut shown = 0usize;
        
        for process in &self.processes {
            if shown >= max_processes {
                break;
            }
            // 渲染进程...
            shown += 1;
        }

        // 显示剩余数量
        let remaining = self.processes.len().saturating_sub(shown);
        if remaining > 0 {
            let more_text = format!("... and {remaining} more running");
            // ...
        }
        
        out
    }
}
```

### 测试数据构造

```rust
// history_cell.rs:2833-2845
let cell = new_unified_exec_processes_output(
    (0..20)  // 创建 20 个进程
        .map(|idx| UnifiedExecProcessDetails {
            command_display: format!("command {idx}"),
            recent_chunks: Vec::new(),
        })
        .collect(),
);
let rendered = render_lines(&cell.display_lines(32)).join("\n");
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/history_cell.rs` | UnifiedExecProcessesCell 实现，测试位于行 2833-2845 |

### 测试代码位置

```rust
// history_cell.rs:2833-2845
#[test]
fn ps_output_many_sessions_snapshot() {
    let cell = new_unified_exec_processes_output(
        (0..20)
            .map(|idx| UnifiedExecProcessDetails {
                command_display: format!("command {idx}"),
                recent_chunks: Vec::new(),
            })
            .collect(),
    );
    let rendered = render_lines(&cell.display_lines(32)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

## 依赖与外部交互

### 外部依赖

1. **ratatui**: TUI 渲染框架
2. **insta**: 快照测试

### 内部模块依赖

```rust
use crate::live_wrap::take_prefix_by_width;
```

## 风险、边界与改进建议

### 潜在风险

1. **硬编码限制**: `max_processes = 16` 是硬编码的，可能不适合所有场景
2. **动态调整**: 没有根据终端高度动态调整显示数量

### 边界情况

1. **恰好 16 个**: 进程数恰好为 16 时不应显示剩余提示
2. **17 个进程**: 第 17 个进程应触发剩余提示
3. **大量进程**: 数百个进程时的列表渲染性能

### 改进建议

1. **动态限制**: 根据终端高度动态计算最大显示数量
2. **分页显示**: 提供翻页功能查看所有进程
3. **滚动支持**: 在进程列表区域支持滚动
4. **排序选项**: 支持按时间、名称等排序
5. **过滤搜索**: 支持按关键字过滤进程

### 相关快照文件

- `ps_output_empty_snapshot.snap` - 空进程列表测试
- `ps_output_chunk_leading_whitespace_snapshot.snap` - 带缩进输出测试
- `ps_output_long_command_snapshot.snap` - 长命令截断测试
- `ps_output_multiline_snapshot.snap` - 多行输出测试
