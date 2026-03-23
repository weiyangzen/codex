# 研究报告: unified_exec_begin_restores_working_status.snap

## 场景与职责

该快照文件验证 **Unified Exec** 功能开始时，状态指示器正确恢复为 "Working" 状态。Unified Exec 允许 Codex 在后台终端中执行长时间运行的命令（如开发服务器）。

测试场景：
- 任务已开始，状态指示器激活
- 收到 Agent 消息增量并提交
- Unified Exec 启动（`sleep 2` 命令）
- 验证状态指示器显示 "Working" 并包含后台终端信息

## 功能点目的

**Unified Exec 状态管理**：

1. **后台执行** - 支持长时间运行的后台进程
2. **状态可见** - 用户知道有后台任务正在运行
3. **终端交互** - 支持与后台终端的交互
4. **中断控制** - 可按 Esc 中断后台任务

## 具体技术实现

### 测试实现

```rust
// tests.rs:3998-4021
#[tokio::test]
async fn unified_exec_begin_restores_working_status_snapshot() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;

    // 启动任务并提交消息
    chat.on_task_started();
    chat.on_agent_message_delta("Preamble line\n".to_string());
    chat.on_commit_tick();
    drain_insert_history(&mut rx);

    // 启动 Unified Exec
    begin_unified_exec_startup(&mut chat, "call-1", "proc-1", "sleep 2");

    // 渲染并快照
    let width: u16 = 80;
    let height = chat.desired_height(width);
    let mut terminal = ratatui::Terminal::new(ratatui::backend::TestBackend::new(width, height))
        .expect("create terminal");
    terminal.set_viewport_area(Rect::new(0, 0, width, height));
    terminal
        .draw(|f| chat.render(f.area(), f.buffer_mut()))
        .expect("draw chatwidget");
    assert_snapshot!("unified_exec_begin_restores_working_status", terminal.backend());
}
```

### Unified Exec 启动辅助函数

```rust
// tests.rs:3506-3529
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
        source: ExecCommandSource::UnifiedExecStartup, // 关键：Unified Exec 源
        interaction_input: None,
    };
    chat.handle_codex_event(Event {
        id: call_id.to_string(),
        msg: EventMsg::ExecCommandBegin(event.clone()),
    });
    event
}
```

### 状态恢复逻辑

```rust
fn on_unified_exec_begin(&mut self, event: ExecCommandBeginEvent) {
    // 添加到 Unified Exec 进程列表
    self.unified_exec_processes.push(UnifiedExecProcessSummary {
        key: event.process_id.unwrap_or_default(),
        call_id: event.call_id,
        command_display: extract_command_display(&event.command),
        recent_chunks: Vec::new(),
    });
    
    // 恢复状态指示器
    self.bottom_pane.show_status_indicator();
    self.current_status.header = "Working".to_string();
    self.current_status.details = Some(format!(
        "{} background terminal running",
        self.unified_exec_processes.len()
    ));
}
```

### 渲染输出

```
"                                                                                "
"• Working (0s • esc to interrupt) · 1 background terminal running · /ps to view…"
"                                                                                "
"                                                                                "
"› Ask Codex to do anything                                                      "
"                                                                                "
"  ? for shortcuts                                            100% context left  "
```

**解析**：
- `• Working (0s • esc to interrupt)` - 工作状态指示
- `· 1 background terminal running` - 后台终端数量
- `· /ps to view…` - 查看所有后台进程的提示

## 关键代码路径与文件引用

| 文件 | 行号范围 | 描述 |
|------|----------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 3998-4021 | Unified Exec 状态恢复测试 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 3506-3529 | `begin_unified_exec_startup` 辅助函数 |
| `codex-rs/tui/src/chatwidget/mod.rs` | - | Unified Exec 事件处理 |
| `codex-rs/tui/src/chatwidget/realtime.rs` | - | 后台进程管理 |

## 依赖与外部交互

### ExecCommandSource

```rust
codex_protocol::protocol::ExecCommandSource {
    Normal,             // 普通命令执行
    UnifiedExecStartup, // Unified Exec 启动
    // ...
}
```

### UnifiedExecProcessSummary

```rust
struct UnifiedExecProcessSummary {
    key: String,              // 进程标识
    call_id: String,          // 关联调用 ID
    command_display: String,  // 显示用命令
    recent_chunks: Vec<String>, // 最近输出块
}
```

## 风险、边界与改进建议

### 特定风险

1. **进程泄漏** - 后台进程在异常退出时可能未被清理
2. **资源占用** - 大量后台进程消耗系统资源
3. **状态混淆** - 多个后台任务时状态显示可能混乱

### 边界情况

1. **进程崩溃** - 后台进程异常退出时的处理
2. **输出溢出** - 大量输出时的内存管理
3. **权限问题** - 后台进程权限与主进程不同

### 改进建议

1. **进程监控** - 实时显示后台进程 CPU/内存使用
2. **输出限制** - 限制每个进程保留的输出历史大小
3. **自动清理** - 长时间无交互的后台进程自动终止
4. **命名终端** - 允许为后台终端设置自定义名称
5. **输出搜索** - 在后台终端输出中搜索特定内容

### 相关测试

- `unified_exec_wait_status_renders_command_in_single_details_row` - 等待状态显示
- `unified_exec_empty_then_non_empty_after` - 空/非空交互测试
- `interrupt_keeps_unified_exec_processes` - 中断保持后台进程
