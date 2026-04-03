# PS 输出空状态测试快照研究文档

## 场景与职责

本快照测试验证 **UnifiedExecProcessesCell** 在没有后台进程运行时的**空状态展示**。这是 `/ps` 命令的边界情况处理，确保当没有后台终端运行时向用户提供清晰的反馈信息。

测试场景：
- 执行 `/ps` 命令查看后台终端
- 当前没有运行的后台终端进程（空向量）
- 验证空状态的友好提示

## 功能点目的

### 核心功能
1. **空状态检测**：检测后台进程列表为空
2. **友好提示**：向用户展示清晰的空状态信息
3. **一致性展示**：保持与其他 `/ps` 输出一致的视觉风格

### 展示目标
- 命令行显示 `/ps`
- 标题显示 "Background terminals"
- 显示 "No background terminals running." 提示
- 使用斜体样式表示空状态

## 具体技术实现

### 空状态检测逻辑

位于 `history_cell.rs` 的 `UnifiedExecProcessesCell::display_lines` 方法（行 674-677）：

```rust
impl HistoryCell for UnifiedExecProcessesCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        // ...
        if self.processes.is_empty() {
            out.push("  • No background terminals running.".italic().into());
            return out;
        }
        // ... 正常渲染逻辑
    }
}
```

### 空状态渲染流程

```rust
fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
    let mut out: Vec<Line<'static>> = Vec::new();
    out.push(vec!["Background terminals".bold()].into());  // 标题
    out.push("".into());  // 空行

    if self.processes.is_empty() {
        // 空状态：显示提示信息
        out.push("  • No background terminals running.".italic().into());
        return out;
    }
    
    // 正常状态：渲染进程列表
    for process in &self.processes {
        // ...
    }
    // ...
}
```

### 测试用例构造

位于 `history_cell.rs` 测试模块（行 2728-2732）：

```rust
#[test]
fn ps_output_empty_snapshot() {
    let cell = new_unified_exec_processes_output(Vec::new());  // 空向量
    let rendered = render_lines(&cell.display_lines(60)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 快照输出分析

```
/ps

Background terminals

  • No background terminals running.
```

输出结构解析：
1. `/ps` - 命令行（品红色）
   - 由 `PlainHistoryCell` 渲染
   - 样式：`.magenta()`

2. `Background terminals` - 标题（粗体）
   - 样式：`"Background terminals".bold()`

3. `  • No background terminals running.` - 空状态提示
   - `  • ` - 项目符号前缀（2空格 + 点 + 1空格）
   - `No background terminals running.` - 提示文本
   - 样式：`.italic()`（斜体）

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/history_cell.rs` | UnifiedExecProcessesCell 实现 |

### 关键代码段

```rust
// history_cell.rs:772-778
pub(crate) fn new_unified_exec_processes_output(
    processes: Vec<UnifiedExecProcessDetails>,
) -> CompositeHistoryCell {
    let command = PlainHistoryCell::new(vec!["/ps".magenta().into()]);
    let summary = UnifiedExecProcessesCell::new(processes);
    CompositeHistoryCell::new(vec![Box::new(command), Box::new(summary)])
}

// history_cell.rs:650-654
impl UnifiedExecProcessesCell {
    fn new(processes: Vec<UnifiedExecProcessDetails>) -> Self {
        Self { processes }
    }
}
```

### 样式定义

```rust
// 命令样式
"/ps".magenta()

// 标题样式
"Background terminals".bold()

// 空状态样式
"  • No background terminals running.".italic()
```

## 依赖与外部交互

### 内部依赖
- `CompositeHistoryCell` - 组合多个 HistoryCell
- `PlainHistoryCell` - 简单文本渲染

### 组合结构
```
CompositeHistoryCell
├── PlainHistoryCell ("/ps" 命令行)
└── UnifiedExecProcessesCell (进程列表或空状态)
    └── 空状态: "No background terminals running."
```

### 相关命令
| 命令 | 功能 |
|-----|------|
| `/ps` | 列出后台终端 |
| `/exec` | 在后台执行命令 |
| `/wait` | 等待后台命令完成 |

## 风险、边界与改进建议

### 潜在风险
1. **用户困惑**：用户可能不清楚如何创建后台终端
2. **信息不足**：空状态没有提供下一步操作指引
3. **国际化**：硬编码英文提示，不支持多语言

### 边界情况
1. **进程刚结束**：进程在查询瞬间结束，显示空状态
2. **权限问题**：因权限无法查看进程时的处理
3. **系统错误**：系统调用失败时的降级展示

### 改进建议

#### 高优先级
1. **操作指引**：空状态时提供创建后台终端的提示
   ```
   Background terminals
   
   • No background terminals running.
     Use /exec <command> to start one.
   ```

2. **帮助链接**：提供相关命令的帮助链接
   ```
   • No background terminals running.
     See /help exec for more information.
   ```

#### 中优先级
3. **国际化支持**：将提示文本提取到资源文件
   ```rust
   t!("ps.no_background_terminals")  // 使用本地化宏
   ```

4. **历史记录**：显示最近结束的后台终端（可选）
   ```
   Background terminals
   
   • No background terminals running.
   
   Recently completed:
     ✓ just build (2 minutes ago)
   ```

#### 低优先级
5. **快捷操作**：提供快捷创建常用后台任务的选项
   ```
   • No background terminals running.
     Quick start: [dev server] [tests] [build]
   ```

6. **视觉优化**：空状态使用更明显的视觉提示
   ```
   Background terminals
   
   ○ No background terminals running.
     ─────────────────────────────
   ```

### 测试建议
1. 增加空状态后立即创建进程的过渡测试
2. 增加多语言环境下的渲染测试
3. 增加高对比度主题下的可读性测试
4. 增加屏幕阅读器兼容性测试

### 相关功能扩展
1. **进程历史**：记录和展示最近的后台进程历史
2. **快速重启**：一键重启最近的后台进程
3. **进程模板**：保存常用的后台进程配置
