# Research: unified_exec_non_empty_then_empty_active Snapshot Test

## 场景与职责

该 snapshot 测试验证 `tui_app_server` 中 `ChatWidget` 组件在**统一执行（Unified Exec）终端交互中从非空输入到空输入**的活动状态渲染行为。具体场景包括：

1. 启动统一执行进程（`begin_unified_exec_startup`）
2. 发送非空输入的终端交互事件（模拟用户输入 `pwd`）
3. 发送空输入的终端交互事件（模拟用户只按回车）
4. 验证活动状态（active cell）正确显示交互内容

此测试与 `unified_exec_empty_then_non_empty_after` 测试形成对比，验证输入顺序对活动状态的影响。

## 功能点目的

### 核心功能
- **活动单元格管理**：维护当前正在进行的交互活动单元格
- **输入状态转换**：处理从有内容输入到空输入的状态转换
- **实时状态显示**：在活动区域显示当前的终端交互状态

### 业务价值
- 提供实时的终端交互反馈
- 帮助用户了解当前与后台终端的交互状态
- 确保状态转换的平滑性和一致性

## 具体技术实现

### 测试设置
```rust
let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
chat.on_task_started();

// 1. 启动统一执行
begin_unified_exec_startup(&mut chat, "call-wait-3", "proc-3", "just fix");

// 2. 发送非空输入交互（用户输入 pwd）
terminal_interaction(&mut chat, "call-wait-3a", "proc-3", "pwd\n");

// 3. 发送空输入交互
terminal_interaction(&mut chat, "call-wait-3b", "proc-3", "");

// 验证状态
assert_eq!(chat.current_status.header, "Waiting for background terminal");
let status = chat.bottom_pane.status_widget().expect("status indicator should be visible");
assert_eq!(status.header(), "Waiting for background terminal");
assert_eq!(status.details(), Some("just fix"));
```

### 渲染验证
```rust
let pre_cells = drain_insert_history(&mut rx);
let active_combined = pre_cells
    .iter()
    .map(|lines| lines_to_single_string(lines))
    .collect::<String>();
assert_snapshot!("unified_exec_non_empty_then_empty_active", active_combined);
```

### Snapshot 输出分析
生成的 snapshot 显示活动状态：
```
↳ Interacted with background terminal · just fix
  └ pwd
```

关键元素：
- `↳ Interacted with background terminal · just fix`：交互状态标题，显示命令
- `└ pwd`：最近输入的命令内容

注意：与 `empty_then_non_empty` 不同，此测试关注活动状态（active）而非历史记录（history）。空输入后，活动单元格仍然保留之前的非空输入内容。

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs` | `ChatWidget` 主实现，包含活动单元格管理 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试实现，包含 `unified_exec_non_empty_then_empty_snapshots` 测试函数 |
| `codex-rs/tui_app_server/src/exec_cell.rs` | 执行单元格实现，可能包含活动状态渲染 |

### 关键代码路径
```rust
// chatwidget.rs: 处理终端交互
fn on_terminal_interaction(&mut self, ev: TerminalInteractionEvent) {
    if !is_unified_exec_source(ev.source) {
        return;
    }
    
    // 查找或创建活动单元格
    if let Some(process) = self.unified_exec_processes.iter().find(|p| p.key == ev.process_id) {
        // 更新活动单元格
        if let Some(active_cell) = &mut self.active_cell {
            // 更新现有活动单元格
            active_cell.update_terminal_interaction(&ev);
        } else {
            // 创建新的活动单元格
            self.active_cell = Some(Box::new(ExecCell::new_interaction(...)));
        }
        
        // 更新状态指示器
        self.current_status = StatusIndicatorState::waiting_for_background_terminal(
            process.command_display.clone()
        );
    }
}
```

### 数据结构
```rust
// 活动单元格 trait
pub trait HistoryCell {
    fn update_terminal_interaction(&mut self, ev: &TerminalInteractionEvent);
    fn display_lines(&self, width: usize) -> Vec<Line>;
    // ...
}

// ExecCell 实现
pub struct ExecCell {
    command_display: String,
    interactions: Vec<TerminalInteraction>,
    // ...
}
```

## 依赖与外部交互

### 内部依赖
- `codex_protocol::protocol::TerminalInteractionEvent`：终端交互事件
- `codex_protocol::protocol::ExecCommandSource`：执行命令源类型判断

### 外部交互
- `active_cell`：当前活动的单元格，用于实时显示
- `bottom_pane.status_widget()`：底部状态指示器

### 状态转换
```
ExecCommandBegin
    ↓
创建活动单元格，状态 = Working
    ↓
TerminalInteraction (stdin="pwd\n") → 更新活动单元格，添加交互记录
    ↓
TerminalInteraction (stdin="") → 保持活动单元格状态，更新等待状态
    ↓
状态指示器显示 "Waiting for background terminal"
```

## 风险、边界与改进建议

### 潜在风险
1. **活动单元格生命周期**：如果活动单元格没有正确关闭，可能导致内存泄漏
2. **状态同步问题**：活动单元格和状态指示器的状态可能不同步
3. **并发交互**：多个进程同时交互时的状态管理复杂性

### 边界条件
- 活动单元格在长时间运行后的性能影响
- 大量交互记录的内存占用
- 进程结束后活动单元格的清理时机

### 改进建议
1. **增加活动单元格超时机制**：防止长时间无响应的活动单元格占用资源
2. **增加交互记录限制**：限制单个活动单元格的交互记录数量
3. **增加状态同步验证**：添加断言确保活动单元格和状态指示器状态一致
4. **增加并发测试**：验证多个统一执行进程同时交互时的正确性

### 相关测试
- `codex_tui_app_server__chatwidget__tests__unified_exec_empty_then_non_empty_after.snap`：相反顺序的测试
- `codex_tui_app_server__chatwidget__tests__unified_exec_non_empty_then_empty_after.snap`：同一测试的后续历史记录
- `codex_tui_app_server__chatwidget__tests__unified_exec_waiting_multiple_empty_after.snap`：多等待状态测试
