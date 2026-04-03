# Research: unified_exec_begin_restores_working_status Snapshot Test

## 场景与职责

该 snapshot 测试验证 `tui_app_server` 中 `ChatWidget` 组件在**统一执行（Unified Exec）开始事件触发时正确恢复工作状态**的行为。具体场景包括：

1. 任务开始运行（`on_task_started`），状态指示器显示 "Working"
2. 代理消息序言（preamble）被接收并提交，此时状态指示器可能被隐藏
3. 统一执行启动事件（`ExecCommandBeginEvent` with `UnifiedExecStartup` source）触发
4. 验证状态指示器正确恢复为 "Working" 状态，显示后台终端运行信息

此测试确保在流式消息输出和后台命令执行之间的状态切换正确无误。

## 功能点目的

### 核心功能
- **状态指示器生命周期管理**：在任务不同阶段（启动、流式输出、后台执行）正确显示相应状态
- **统一执行集成**：处理来自统一执行框架的后台命令启动事件
- **状态恢复机制**：在序言输出完成后，恢复工作状态指示

### 业务价值
- 确保用户始终清楚当前系统正在执行的操作
- 区分前台流式输出和后台命令执行的不同状态
- 提供后台终端数量的可视化反馈

## 具体技术实现

### 测试设置
```rust
let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;

// 1. 任务开始
chat.on_task_started();

// 2. 模拟序言消息接收和提交
chat.on_agent_message_delta("Preamble line\n".to_string());
chat.on_commit_tick();
drain_insert_history(&mut rx);

// 3. 启动统一执行
begin_unified_exec_startup(&mut chat, "call-1", "proc-1", "sleep 2");
```

### `begin_unified_exec_startup` 辅助函数
```rust
fn begin_unified_exec_startup(
    chat: &mut ChatWidget,
    call_id: &str,
    process_id: &str,
    raw_cmd: &str,
) -> ExecCommandBeginEvent {
    let command = vec!["bash".to_string(), "-lc".to_string(), raw_cmd.to_string()];
    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    let event = ExecCommandBeginEvent {
        call_id: call_id.to_string(),
        process_id: Some(process_id.to_string()),
        turn_id: "turn-1".to_string(),
        command,
        cwd,
        parsed_cmd: Vec::new(),
        source: ExecCommandSource::UnifiedExecStartup,  // 关键：统一执行源
        interaction_input: None,
    };
    chat.handle_codex_event(Event {
        id: call_id.to_string(),
        msg: EventMsg::ExecCommandBegin(event.clone()),
    });
    event
}
```

### 渲染验证
```rust
let width: u16 = 80;
let height = chat.desired_height(width);
let mut terminal = ratatui::Terminal::new(ratatui::backend::TestBackend::new(width, height))
    .expect("create terminal");
terminal.set_viewport_area(Rect::new(0, 0, width, height));
terminal
    .draw(|f| chat.render(f.area(), f.buffer_mut()))
    .expect("draw chatwidget");
assert_snapshot!("unified_exec_begin_restores_working_status", terminal.backend());
```

### Snapshot 输出分析
生成的 snapshot 显示底部状态栏：
```
"• Working (0s • esc to interrupt) · 1 background terminal running · /ps to view…"
```

关键元素：
- `• Working`：工作状态指示器（带旋转动画标记）
- `(0s • esc to interrupt)`：运行时间和中断提示
- `1 background terminal running`：后台终端数量
- `/ps to view…`：查看所有后台进程的命令提示

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs` | `ChatWidget` 主实现，包含 `track_unified_exec_process_begin` 和 `sync_unified_exec_footer` |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试实现，包含 `unified_exec_begin_restores_working_status_snapshot` 测试函数 |
| `codex-rs/tui_app_server/src/bottom_pane/mod.rs` | 底部面板实现，包含状态指示器更新 |

### 关键代码路径
```rust
// chatwidget.rs: track_unified_exec_process_begin
fn track_unified_exec_process_begin(&mut self, ev: &ExecCommandBeginEvent) {
    let key = ev.process_id.clone().unwrap_or(ev.call_id.to_string());
    let command_display = strip_bash_lc_and_escape(&ev.command);
    
    if let Some(existing) = self.unified_exec_processes.iter_mut().find(|p| p.key == key) {
        existing.call_id = ev.call_id.clone();
        existing.command_display = command_display.clone();
        existing.recent_chunks.clear();
    } else {
        self.unified_exec_processes.push(UnifiedExecProcessSummary {
            key,
            call_id: ev.call_id.clone(),
            command_display,
            recent_chunks: Vec::new(),
        });
    }
    self.sync_unified_exec_footer();
}

// chatwidget.rs: sync_unified_exec_footer
fn sync_unified_exec_footer(&mut self) {
    let processes = self
        .unified_exec_processes
        .iter()
        .map(|process| process.command_display.clone())
        .collect();
    self.bottom_pane.set_unified_exec_processes(processes);
}
```

### 数据结构
```rust
struct UnifiedExecProcessSummary {
    key: String,           // process_id 或 call_id
    call_id: String,       // 调用 ID
    command_display: String, // 显示用的命令字符串
    recent_chunks: Vec<String>, // 最近的输出块
}
```

## 依赖与外部交互

### 内部依赖
- `codex_protocol::protocol::ExecCommandBeginEvent`：执行命令开始事件
- `codex_protocol::protocol::ExecCommandSource`：命令源类型（区分统一执行和普通执行）
- `codex_core::terminal::strip_bash_lc_and_escape`：命令字符串处理

### 外部交互
- `BottomPane::set_unified_exec_processes`：更新底部面板的后台进程列表
- `StatusIndicatorState::working()`：创建工作状态指示器状态

### 事件流
```
TurnStarted → on_task_started() → agent_turn_running = true
    ↓
AgentMessageDelta → on_agent_message_delta() → 隐藏状态指示器
    ↓
CommitTick → on_commit_tick() → 提交历史记录
    ↓
ExecCommandBegin (UnifiedExecStartup) → track_unified_exec_process_begin()
    ↓
sync_unified_exec_footer() → bottom_pane.set_unified_exec_processes()
    ↓
状态指示器恢复显示
```

## 风险、边界与改进建议

### 潜在风险
1. **状态竞争**：如果在 `on_commit_tick` 和 `ExecCommandBegin` 之间有其他事件，可能导致状态不一致
2. **内存泄漏**：`unified_exec_processes` 列表如果没有正确清理，可能累积大量已结束的进程
3. **命令注入**：`strip_bash_lc_and_escape` 函数需要正确处理特殊字符

### 边界条件
- 多个统一执行进程同时启动
- 进程 ID 冲突处理
- 命令字符串超长时的截断处理

### 改进建议
1. **增加并发测试**：验证多个统一执行进程同时启动时的状态管理
2. **增加清理测试**：验证进程结束后 `unified_exec_processes` 的正确清理
3. **增加错误处理测试**：验证 `ExecCommandBegin` 事件中的无效数据处理
4. **性能优化**：考虑使用 `HashMap` 替代 `Vec` 存储进程摘要，优化查找性能

### 相关测试
- `codex_tui_app_server__chatwidget__tests__status_widget_active.snap`：基础状态指示器测试
- `codex_tui_app_server__chatwidget__tests__preamble_keeps_working_status.snap`：序言保持工作状态测试
- `codex_tui_app_server__chatwidget__tests__unified_exec_waiting_multiple_empty_after.snap`：多等待状态测试
