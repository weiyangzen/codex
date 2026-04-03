# Research: 后台进程输出空列表测试快照

## 场景与职责

该快照测试验证 `UnifiedExecProcessesCell` 在渲染后台进程列表时的空状态处理，即当没有后台进程运行时的显示行为。

这是 Codex TUI 后台终端管理功能的基础测试，确保用户能够清楚地了解当前没有后台进程在运行。

## 功能点目的

1. **空状态提示**: 当没有后台进程时显示友好的提示信息
2. **命令标识**: 显示触发该输出的命令（`/ps`）
3. **标题显示**: 始终显示 "Background terminals" 标题
4. **视觉一致性**: 保持与非空状态一致的视觉风格

## 具体技术实现

### 渲染格式

```
/ps

Background terminals

  • No background terminals running.
```

格式说明：
- `/ps`: 命令标识（洋红色）
- `Background terminals`: 标题（粗体）
- `• No background terminals running.`: 空状态提示（斜体）

### 关键代码逻辑

```rust
// history_cell.rs:662-770
impl HistoryCell for UnifiedExecProcessesCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        // ...
        
        if self.processes.is_empty() {
            out.push("  • No background terminals running.".italic().into());
            return out;
        }
        
        // 非空状态处理...
    }
}

// 工厂函数（history_cell.rs:772-778）
pub(crate) fn new_unified_exec_processes_output(
    processes: Vec<UnifiedExecProcessDetails>,
) -> CompositeHistoryCell {
    let command = PlainHistoryCell::new(vec!["/ps".magenta().into()]);
    let summary = UnifiedExecProcessesCell::new(processes);
    CompositeHistoryCell::new(vec![Box::new(command), Box::new(summary)])
}
```

### 测试数据构造

```rust
// history_cell.rs:2728-2732
let cell = new_unified_exec_processes_output(Vec::new());  // 空列表
let rendered = render_lines(&cell.display_lines(60)).join("\n");
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/history_cell.rs` | UnifiedExecProcessesCell 实现，测试位于行 2728-2732 |

### 测试代码位置

```rust
// history_cell.rs:2728-2732
#[test]
fn ps_output_empty_snapshot() {
    let cell = new_unified_exec_processes_output(Vec::new());
    let rendered = render_lines(&cell.display_lines(60)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

## 依赖与外部交互

### 外部依赖

1. **ratatui**: TUI 渲染框架
2. **insta**: 快照测试

### 内部模块依赖

```rust
use ratatui::style::Stylize;  // 提供 .magenta()、.italic() 等方法
```

## 风险、边界与改进建议

### 潜在风险

1. **空列表检测**: 必须使用 `is_empty()` 而非 `len() == 0` 进行空列表检测

### 边界情况

1. **进程列表变空**: 从非空变为空时的过渡动画
2. **并发访问**: 进程列表在渲染过程中被修改

### 改进建议

1. **帮助提示**: 在空状态提示后添加如何启动后台进程的提示
2. **快捷操作**: 提供快捷键直接启动常用后台任务
3. **历史记录**: 显示最近结束的后台进程

### 相关快照文件

- `ps_output_chunk_leading_whitespace_snapshot.snap` - 带缩进输出测试
- `ps_output_long_command_snapshot.snap` - 长命令测试
- `ps_output_many_sessions_snapshot.snap` - 多进程测试
- `ps_output_multiline_snapshot.snap` - 多行输出测试
