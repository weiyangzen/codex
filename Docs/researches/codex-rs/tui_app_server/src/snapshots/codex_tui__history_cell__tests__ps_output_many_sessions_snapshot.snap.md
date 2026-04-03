# 研究文档：ps_output_many_sessions_snapshot

## 场景与职责

该快照测试验证 `/ps` 命令在存在大量后台终端进程时的显示行为。当用户执行 `/ps` 命令查看后台进程列表时，如果有超过 16 个进程在运行，系统需要限制显示数量并提示用户还有更多进程。

**核心职责**：
- 限制同时显示的进程数量，避免占用过多屏幕空间
- 提供清晰的提示告知用户被隐藏的进程数量
- 保持 UI 的响应性和可读性

## 功能点目的

**从快照内容分析**：
```
/ps

Background terminals

  • command 0
  • command 1
  • command 2
  • command 3
  • command 4
  • command 5
  • command 6
  • command 7
  • command 8
  • command 9
  • command 10
  • command 11
  • command 12
  • command 13
  • command 14
  • command 15
  • ... and 4 more running
```

**功能特性**：
1. 最多显示 16 个进程（`max_processes = 16`）
2. 每个进程显示为列表项（`•` 前缀）
3. 超出限制的进程显示为 "... and N more running"
4. 使用暗淡（dim）样式区分提示文本

## 具体技术实现

### 核心算法

**进程限制逻辑**（`codex-rs/tui/src/history_cell.rs` 第 683-768 行）：

```rust
let max_processes = 16usize;
let mut shown = 0usize;

for process in &self.processes {
    if shown >= max_processes {
        break;
    }
    // 渲染进程信息...
    shown += 1;
}

// 显示剩余进程提示
let remaining = self.processes.len().saturating_sub(shown);
if remaining > 0 {
    let more_text = format!("... and {remaining} more running");
    // 渲染提示行...
}
```

### 数据结构

**UnifiedExecProcessesCell**（第 651-654 行）：
```rust
#[derive(Debug)]
struct UnifiedExecProcessesCell {
    processes: Vec<UnifiedExecProcessDetails>,
}
```

**UnifiedExecProcessDetails**（第 657-666 行）：
```rust
#[derive(Debug, Clone)]
pub(crate) struct UnifiedExecProcessDetails {
    pub(crate) command_display: String,
    pub(crate) recent_chunks: Vec<String>,
}
```

### 渲染流程

1. **初始化**：创建输出向量，添加标题
2. **空列表处理**：如果没有进程，显示 "No background terminals running"
3. **进程遍历**：
   - 使用 `shown` 计数器跟踪已显示进程数
   - 达到 `max_processes` 时中断循环
4. **剩余提示**：计算并显示剩余进程数量

### 样式处理

```rust
// 标题使用粗体
out.push(vec!["Background terminals".bold()].into());

// 进程命令使用青色
out.push(vec![prefix.dim(), truncated.cyan()].into());

// 剩余提示使用暗淡样式
out.push(vec![prefix.dim(), truncated.dim()].into());
```

## 关键代码路径与文件引用

### 主要文件

| 文件路径 | 行号范围 | 说明 |
|---------|---------|------|
| `codex-rs/tui/src/history_cell.rs` | 651-776 | `UnifiedExecProcessesCell` 完整实现 |
| `codex-rs/tui/src/history_cell.rs` | 772-778 | `new_unified_exec_processes_output` 工厂函数 |

### 关键代码段

**测试代码**（第 2833-2845 行）：
```rust
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

**核心渲染逻辑**（第 683-768 行）：
```rust
impl HistoryCell for UnifiedExecProcessesCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        // ... 宽度检查 ...
        let max_processes = 16usize;
        let mut shown = 0usize;
        
        for process in &self.processes {
            if shown >= max_processes {
                break;
            }
            // 渲染逻辑...
            shown += 1;
        }
        
        // 剩余提示...
        let remaining = self.processes.len().saturating_sub(shown);
        if remaining > 0 {
            let more_text = format!("... and {remaining} more running");
            // 渲染提示...
        }
        
        out
    }
}
```

### 相关常量

```rust
const max_processes: usize = 16;  // 最大显示进程数
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `ratatui::style::Stylize` | 文本样式（bold, dim, cyan 等） |
| `unicode_width::UnicodeWidthStr` | 计算字符串显示宽度 |

### 内部依赖

- `crate::live_wrap::take_prefix_by_width`：宽度敏感的文本截断
- `CompositeHistoryCell`：组合多个 history cell

### 调用链

```
new_unified_exec_processes_output(processes)
    └── CompositeHistoryCell::new([
            PlainHistoryCell("/ps"),
            UnifiedExecProcessesCell(processes)
        ])
        └── UnifiedExecProcessesCell::display_lines(width)
            └── 遍历进程，限制 16 个
```

## 风险、边界与改进建议

### 潜在风险

1. **硬编码限制**：
   - `max_processes = 16` 是硬编码的，不适合所有屏幕尺寸
   - 在高分辨率显示器上可能浪费空间，在小屏幕上可能仍然过多

2. **信息丢失**：
   - 用户无法直接看到被隐藏的进程
   - 没有提供查看全部进程的方式（如滚动或分页）

3. **性能问题**：
   - 即使只显示 16 个，也会遍历整个进程列表
   - 对于数百个进程，遍历开销不可忽视

### 边界情况

| 场景 | 当前行为 | 评估 |
|-----|---------|------|
| 0 个进程 | 显示 "No background terminals running" | ✅ 合理 |
| 16 个进程 | 显示全部，无提示 | ✅ 合理 |
| 17 个进程 | 显示 16 个 + "... and 1 more running" | ✅ 合理 |
| 进程命令超长 | 截断显示 | ⚠️ 可能丢失关键信息 |
| 宽度为 0 | 返回空向量 | ✅ 防御性编程 |

### 改进建议

1. **动态限制**：
   ```rust
   // 根据终端高度动态调整
   let max_processes = (available_height / lines_per_process).min(16);
   ```

2. **交互式展开**：
   - 添加 `/ps --all` 选项显示全部进程
   - 支持在 UI 中按某个键展开完整列表

3. **优先级排序**：
   ```rust
   // 按活跃度或最近输出排序，确保重要进程优先显示
   processes.sort_by(|a, b| b.last_activity.cmp(&a.last_activity));
   ```

4. **虚拟列表**：
   - 实现虚拟滚动，支持查看任意数量的进程
   - 只渲染可见区域的进程

5. **配置选项**：
   ```rust
   // 在配置中添加选项
   pub struct Config {
       max_displayed_processes: usize,  // 默认 16
   }
   ```

6. **改进提示信息**：
   ```rust
   // 添加提示如何查看全部
   format!("... and {remaining} more running (use /ps --all to see all)")
   ```
