# Research: unified_exec_unknown_end_with_active_exploring_cell Snapshot Test

## 场景与职责

该 snapshot 测试验证 `tui_app_server` 中 `ChatWidget` 组件在**存在未知结束事件（orphan end event）且有活动探索单元格**时的复杂状态处理。具体场景包括：

1. 启动一个探索命令（`begin_exec` with exploring source）
2. 启动一个统一执行命令（`begin_unified_exec_startup`）
3. 统一执行命令结束（`end_exec`），但探索命令仍在运行
4. 验证历史记录正确显示已结束的命令，同时活动单元格保留正在运行的探索命令

此测试确保在复杂的并发命令执行场景下，历史记录和活动状态的管理正确无误。

## 功能点目的

### 核心功能
- **并发命令管理**：同时管理多个不同类型的命令（探索和统一执行）
- **孤儿事件处理**：处理没有对应开始事件的结束事件
- **状态隔离**：确保一个命令的结束不影响其他正在运行的命令

### 业务价值
- 提供准确的并发命令执行状态
- 防止一个命令的结束错误地影响其他命令
- 确保用户始终了解哪些命令仍在运行

## 具体技术实现

### 测试设置
```rust
let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
chat.on_task_started();

// 1. 启动探索命令（标准执行）
begin_exec(&mut chat, "call-exploring", "cat /dev/null");

// 2. 启动统一执行命令
let orphan = begin_unified_exec_startup(&mut chat, "call-orphan", "proc-1", "echo repro-marker");

// 3. 结束统一执行命令（探索命令仍在运行）
end_exec(&mut chat, orphan, "repro-marker\n", "", 0);
```

### 辅助函数
```rust
fn begin_exec(chat: &mut ChatWidget, call_id: &str, raw_cmd: &str) -> ExecCommandBeginEvent {
    // 创建标准执行命令（非统一执行源）
    let event = ExecCommandBeginEvent {
        call_id: call_id.to_string(),
        process_id: Some("proc-exploring".to_string()),
        turn_id: "turn-1".to_string(),
        command: vec!["bash".to_string(), "-lc".to_string(), raw_cmd.to_string()],
        cwd: std::env::current_dir().unwrap(),
        parsed_cmd: Vec::new(),
        source: ExecCommandSource::ToolCall,  // 标准工具调用源
        interaction_input: None,
    };
    chat.handle_codex_event(Event {
        id: call_id.to_string(),
        msg: EventMsg::ExecCommandBegin(event.clone()),
    });
    event
}

fn end_exec(
    chat: &mut ChatWidget,
    begin: ExecCommandBeginEvent,
    stdout: &str,
    stderr: &str,
    exit_code: i32,
) {
    chat.handle_codex_event(Event {
        id: begin.call_id.clone(),
        msg: EventMsg::ExecCommandEnd(ExecCommandEndEvent {
            call_id: begin.call_id,
            process_id: begin.process_id,
            turn_id: begin.turn_id,
            stdout: stdout.as_bytes().to_vec(),
            stderr: stderr.as_bytes().to_vec(),
            exit_code,
            source: begin.source,
        }),
    });
}
```

### 渲染验证
```rust
let cells = drain_insert_history(&mut rx);
let history = cells
    .iter()
    .map(|lines| lines_to_single_string(lines))
    .collect::<String>();
let active = active_blob(&chat);  // 获取活动单元格内容
let snapshot = format!("History:\n{history}\nActive:\n{active}");
assert_snapshot!("unified_exec_unknown_end_with_active_exploring_cell", snapshot);
```

### Snapshot 输出分析
生成的 snapshot 显示：
```
History:
• Ran echo repro-marker
  └ repro-marker

Active:
• Exploring
  └ Read null
```

关键元素：
- **History**：显示已结束的统一执行命令 `echo repro-marker` 及其输出
- **Active**：显示仍在运行的探索命令 `Read null`（`cat /dev/null` 的显示形式）

这验证了：
1. 统一执行命令结束后正确记录到历史
2. 探索命令不受影响，仍在活动单元格中显示
3. 两种不同类型的命令正确隔离

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs` | `ChatWidget` 主实现，包含命令生命周期管理 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试实现，包含 `unified_exec_unknown_end_with_active_exploring_cell_snapshot` |
| `codex-rs/tui_app_server/src/exec_cell.rs` | 执行单元格实现 |

### 关键代码路径
```rust
// chatwidget.rs: handle_exec_command_end
fn handle_exec_command_end(&mut self, ev: ExecCommandEndEvent) {
    // 根据命令源类型分别处理
    match ev.source {
        ExecCommandSource::UnifiedExecStartup | ExecCommandSource::UnifiedExecInteraction => {
            // 统一执行：更新统一执行进程列表
            self.track_unified_exec_process_end(&ev);
        }
        _ => {
            // 标准执行：更新活动单元格或历史记录
            if let Some(active_cell) = &mut self.active_cell {
                if active_cell.matches_call_id(&ev.call_id) {
                    active_cell.complete(ev);
                    self.flush_active_cell_to_history();
                    return;
                }
            }
            // 孤儿事件：创建独立的历史记录
            self.create_orphan_history_entry(ev);
        }
    }
}
```

### 数据结构
```rust
// ExecCommandSource 枚举
pub enum ExecCommandSource {
    ToolCall,           // 标准工具调用
    UnifiedExecStartup, // 统一执行启动
    UnifiedExecInteraction, // 统一执行交互
    // ...
}

// 活动单元格管理
pub struct ExecCell {
    call_id: String,
    command: Vec<String>,
    status: ExecStatus,
    // ...
}
```

## 依赖与外部交互

### 内部依赖
- `codex_protocol::protocol::ExecCommandBeginEvent` 和 `ExecCommandEndEvent`：执行命令事件
- `codex_protocol::protocol::ExecCommandSource`：命令源类型

### 外部交互
- `active_cell`：当前活动单元格
- `unified_exec_processes`：统一执行进程列表
- `AppEvent::InsertHistoryCell`：历史记录插入事件

### 并发管理
```
ExecCommandBegin (ToolCall) → 创建探索活动单元格
    ↓
ExecCommandBegin (UnifiedExecStartup) → 添加到 unified_exec_processes
    ↓
ExecCommandEnd (UnifiedExecStartup) → 
    ├── 从 unified_exec_processes 移除
    ├── 创建历史记录
    └── 不影响探索活动单元格
    ↓
探索活动单元格继续运行
```

## 风险、边界与改进建议

### 潜在风险
1. **命令 ID 冲突**：如果两个命令使用相同的 call_id，可能导致状态混乱
2. **内存泄漏**：如果探索命令永远不结束，活动单元格可能一直占用内存
3. **状态不一致**：统一执行和探索命令的状态更新可能存在竞态条件

### 边界条件
- 多个统一执行命令同时结束
- 探索命令在统一执行命令结束前完成
- 快速连续的命令开始和结束
- 网络延迟导致的乱序事件

### 改进建议
1. **增加命令 ID 唯一性验证**：确保所有命令 ID 全局唯一
2. **增加活动单元格超时**：防止长时间运行的命令无限占用资源
3. **增加并发压力测试**：模拟大量并发命令的执行
4. **增加事件顺序测试**：验证乱序事件的处理正确性

### 相关测试
- `codex_tui_app_server__chatwidget__tests__unified_exec_orphan_end_renders_standalone.snap`：孤儿结束事件测试
- `codex_tui_app_server__chatwidget__tests__interrupt_exec_marks_failed.snap`：中断命令测试
- `codex_tui_app_server__chatwidget__tests__exploring_step*.snap`：探索命令系列测试
