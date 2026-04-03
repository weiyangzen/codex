# Research: unified_exec_empty_then_non_empty_after Snapshot Test

## 场景与职责

该 snapshot 测试验证 `tui_app_server` 中 `ChatWidget` 组件在**统一执行（Unified Exec）终端交互中从空输入到非空输入**的历史记录渲染行为。具体场景包括：

1. 启动统一执行进程（`begin_unified_exec_startup`）
2. 发送空输入的终端交互事件（模拟用户只按回车）
3. 发送非空输入的终端交互事件（模拟用户输入实际命令如 `ls`）
4. 验证历史记录正确显示等待状态和交互内容

此测试确保终端交互的历史记录能够正确累积和显示，区分空输入和有内容的输入。

## 功能点目的

### 核心功能
- **终端交互跟踪**：记录用户与后台终端的交互历史
- **输入状态管理**：区分空输入（仅回车）和有内容的输入
- **历史记录渲染**：将交互记录以可读的格式显示在历史区域

### 业务价值
- 提供完整的终端交互审计日志
- 帮助用户回顾与后台终端的交互过程
- 区分有意义的命令输入和空操作

## 具体技术实现

### 测试设置
```rust
let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
chat.on_task_started();

// 1. 启动统一执行
begin_unified_exec_startup(&mut chat, "call-wait-2", "proc-2", "just fix");

// 2. 发送空输入交互
terminal_interaction(&mut chat, "call-wait-2a", "proc-2", "");

// 3. 发送非空输入交互（用户输入 ls）
terminal_interaction(&mut chat, "call-wait-2b", "proc-2", "ls\n");
```

### `terminal_interaction` 辅助函数
```rust
fn terminal_interaction(chat: &mut ChatWidget, call_id: &str, process_id: &str, stdin: &str) {
    chat.handle_codex_event(Event {
        id: call_id.to_string(),
        msg: EventMsg::TerminalInteraction(TerminalInteractionEvent {
            call_id: call_id.to_string(),
            process_id: process_id.to_string(),
            stdin: stdin.to_string(),
        }),
    });
}
```

### 渲染验证
```rust
let cells = drain_insert_history(&mut rx);
let combined = cells
    .iter()
    .map(|lines| lines_to_single_string(lines))
    .collect::<String>();
assert_snapshot!("unified_exec_empty_then_non_empty_after", combined);
```

### Snapshot 输出分析
生成的 snapshot 显示历史记录：
```
• Waited for background terminal · just fix

↳ Interacted with background terminal · just fix
  └ ls
```

关键元素：
- `• Waited for background terminal · just fix`：等待状态记录，显示命令
- `↳ Interacted with background terminal · just fix`：交互状态记录
- `└ ls`：实际输入的命令内容

注意：空输入（第一次 `terminal_interaction`）没有产生独立的记录，只有非空输入被记录。

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs` | `ChatWidget` 主实现，包含 `on_terminal_interaction` 处理 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试实现，包含 `unified_exec_empty_then_non_empty_snapshot` 测试函数 |
| `codex-rs/tui_app_server/src/history_cell/` | 历史记录单元格实现 |

### 关键代码路径
```rust
// chatwidget.rs: on_terminal_interaction
fn on_terminal_interaction(&mut self, ev: TerminalInteractionEvent) {
    // 检查是否为统一执行源
    if !is_unified_exec_source(ev.source) {
        return;
    }
    
    // 查找对应的进程
    if let Some(process) = self.unified_exec_processes.iter_mut().find(|p| p.key == ev.process_id) {
        // 记录交互
        if !ev.stdin.is_empty() {
            // 非空输入：创建或更新交互记录
            self.add_terminal_interaction_history(&ev, &process.command_display);
        }
        // 更新等待状态
        self.update_unified_exec_wait_state(&ev, process);
    }
}
```

### 数据结构
```rust
// TerminalInteractionEvent 结构
pub struct TerminalInteractionEvent {
    pub call_id: String,
    pub process_id: String,
    pub stdin: String,  // 用户输入内容
}

// 统一执行等待状态
struct UnifiedExecWaitState {
    command_display: String,
}
```

## 依赖与外部交互

### 内部依赖
- `codex_protocol::protocol::TerminalInteractionEvent`：终端交互事件
- `codex_protocol::protocol::ExecCommandSource`：用于判断是否为统一执行源

### 外部交互
- `AppEvent::InsertHistoryCell`：插入历史记录单元格事件
- `HistoryCell` 渲染系统：将交互记录渲染为可读的文本格式

### 事件流
```
ExecCommandBegin (UnifiedExecStartup)
    ↓
unified_exec_processes.push(...)
    ↓
TerminalInteraction (stdin="") → 更新内部状态，不产生历史记录
    ↓
TerminalInteraction (stdin="ls\n") → add_terminal_interaction_history()
    ↓
AppEvent::InsertHistoryCell → 渲染交互记录
```

## 风险、边界与改进建议

### 潜在风险
1. **空输入处理**：空输入是否应该被记录？当前实现不记录，但某些场景可能需要
2. **输入编码**：特殊字符或二进制输入可能导致显示问题
3. **历史记录累积**：长时间运行的终端可能产生大量历史记录

### 边界条件
- 超长输入行的截断处理
- 多行输入（包含 `\n`）的显示处理
- 特殊控制字符（如 `\r`, `\t`）的渲染
- 并发交互（快速连续输入）的处理

### 改进建议
1. **增加空输入记录选项**：考虑添加配置项控制是否记录空输入
2. **增加输入长度限制**：防止超长输入导致 UI 性能问题
3. **增加特殊字符处理**：确保控制字符不会破坏终端显示
4. **增加时间戳记录**：为交互记录添加时间戳，便于审计

### 相关测试
- `codex_tui_app_server__chatwidget__tests__unified_exec_non_empty_then_empty_after.snap`：反向流程测试
- `codex_tui_app_server__chatwidget__tests__unified_exec_non_empty_then_empty_active.snap`：活动状态测试
- `codex_tui_app_server__chatwidget__tests__unified_exec_waiting_multiple_empty_after.snap`：多等待状态测试
