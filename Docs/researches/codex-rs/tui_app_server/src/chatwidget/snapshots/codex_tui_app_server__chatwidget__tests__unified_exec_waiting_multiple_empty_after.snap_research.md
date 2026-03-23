# 研究文档：Unified Exec Waiting Multiple Empty After 快照测试

## 场景与职责

此快照文件验证当 Unified Exec（统一执行）后台终端任务完成等待状态后，TUI 如何在历史记录中渲染该操作的总结。测试展示了当用户与后台终端交互（发送空输入）多次后，最终任务完成时的历史记录格式。

## 功能点目的

1. **后台终端等待记录**：记录对后台终端的等待操作
2. **命令显示**：显示触发等待的命令（`just fix`）
3. **交互历史**：记录多次空交互（terminal interaction）
4. **状态转换**：从 "Waiting" 状态到完成的记录转换

## 具体技术实现

### 关键流程

测试函数 `unified_exec_waiting_multiple_empty_snapshots`（行 5927）：

```rust
async fn unified_exec_waiting_multiple_empty_snapshots() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    
    // 1. 标记任务开始
    chat.on_task_started();
    
    // 2. 启动统一执行会话
    begin_unified_exec_startup(&mut chat, "call-wait-1", "proc-1", "just fix");
    
    // 3. 模拟两次空终端交互
    terminal_interaction(&mut chat, "call-wait-1a", "proc-1", "");
    terminal_interaction(&mut chat, "call-wait-1b", "proc-1", "");
    
    // 4. 验证状态
    assert_eq!(chat.current_status.header, "Waiting for background terminal");
    let status = chat.bottom_pane.status_widget().expect("status indicator");
    assert_eq!(status.header(), "Waiting for background terminal");
    assert_eq!(status.details(), Some("just fix"));
    
    // 5. 模拟回合完成
    chat.handle_codex_event(Event {
        id: "turn-wait-1".into(),
        msg: EventMsg::TurnComplete(TurnCompleteEvent {
            turn_id: "turn-1".to_string(),
            last_agent_message: None,
        }),
    });
    
    // 6. 捕获历史记录
    let cells = drain_insert_history(&mut rx);
    let combined = cells
        .iter()
        .map(|lines| lines_to_single_string(lines))
        .collect::<String>();
    assert_snapshot!("unified_exec_waiting_multiple_empty_after", combined);
}
```

### 辅助函数

**begin_unified_exec_startup**（行 3524）：
```rust
fn begin_unified_exec_startup(
    chat: &mut ChatWidget,
    call_id: &str,
    process_id: &str,
    raw_cmd: &str,
) -> ExecCommandBeginEvent {
    let command = vec!["bash".to_string(), "-lc".to_string(), raw_cmd.to_string()];
    let event = ExecCommandBeginEvent {
        call_id: call_id.to_string(),
        process_id: Some(process_id.to_string()),
        turn_id: "turn-1".to_string(),
        command,
        cwd: std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")),
        parsed_cmd: Vec::new(),  // Unified exec 不解析命令
        source: ExecCommandSource::UnifiedExecStartup,
        interaction_input: None,
    };
    chat.handle_codex_event(Event {
        id: call_id.to_string(),
        msg: EventMsg::ExecCommandBegin(event.clone()),
    });
    event
}
```

**terminal_interaction**（行 3549）：
```rust
fn terminal_interaction(chat: &mut ChatWidget, call_id: &str, process_id: &str, stdin: &str) {
    chat.handle_codex_event(Event {
        id: call_id.to_string(),
        msg: EventMsg::TerminalInteraction(TerminalInteractionEvent {
            call_id: call_id.to_string(),
            process_id: process_id.to_string(),
            data: stdin.to_string(),  // 空字符串表示仅等待
        }),
    });
}
```

### 渲染输出格式

快照显示历史记录内容：
```
• Waited for background terminal · just fix
```

格式解析：
- `•` - 列表标记（可能表示活跃或完成状态）
- `Waited for background terminal` - 操作类型描述
- `·` - 中点分隔符（U+00B7）
- `just fix` - 执行的命令

### 数据结构

**ExecCommandSource** 枚举（`codex-rs/protocol/src/protocol.rs`）：
```rust
pub enum ExecCommandSource {
    Agent,                  // Agent 发起的命令
    UserShell,             // 用户 shell 命令
    UnifiedExecStartup,    // 统一执行启动
    UnifiedExecInteraction, // 统一执行交互
}
```

**TerminalInteractionEvent**：
```rust
pub struct TerminalInteractionEvent {
    pub call_id: String,
    pub process_id: String,
    pub data: String,  // 发送到终端的输入数据
}
```

**TurnCompleteEvent**：
```rust
pub struct TurnCompleteEvent {
    pub turn_id: String,
    pub last_agent_message: Option<String>,
}
```

### 统一执行（Unified Exec）架构

Unified Exec 是 Codex 的后台终端执行系统：

1. **启动阶段**：`UnifiedExecStartup` - 启动长时间运行的进程（如 `just fix`）
2. **交互阶段**：`UnifiedExecInteraction` - 向运行中的进程发送输入
3. **等待状态**：进程运行期间显示 "Waiting for background terminal"
4. **完成记录**：回合完成后记录操作历史

## 关键代码路径与文件引用

### 测试代码
- **文件**：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
- **测试函数**：`unified_exec_waiting_multiple_empty_snapshots`（行 5927）
- **辅助函数**：
  - `begin_unified_exec_startup`（行 3524）
  - `terminal_interaction`（行 3549）
  - `drain_insert_history`（清空历史记录通道）

### 统一执行实现
- **文件**：`codex-rs/core/src/unified_exec/process_manager.rs`
  - 后台进程管理
- **文件**：`codex-rs/core/src/unified_exec/async_watcher.rs`
  - 异步监视

### 历史记录渲染
- **文件**：`codex-rs/tui_app_server/src/exec_cell/render.rs`
  - `format_unified_exec_interaction` 函数（行 63-76）：
    ```rust
    fn format_unified_exec_interaction(command: &[String], input: Option<&str>) -> String {
        let command_display = if let Some((_, script)) = extract_bash_command(command) {
            script.to_string()
        } else {
            command.join(" ")
        };
        match input {
            Some(data) if !data.is_empty() => {
                let preview = summarize_interaction_input(data);
                format!("Interacted with `{command_display}`, sent `{preview}`")
            }
            _ => format!("Waited for `{command_display}`"),
        }
    }
    ```

### 协议定义
- **文件**：`codex-rs/protocol/src/protocol.rs`
  - `ExecCommandSource` 枚举
  - `TerminalInteractionEvent`
  - `TurnCompleteEvent`

## 依赖与外部交互

### 上游依赖
1. **codex-core/unified_exec**：统一执行系统的核心实现
2. **codex-protocol**：定义 UnifiedExec 相关事件
3. **codex-shell-command**：命令解析（`extract_bash_command`）

### 下游消费
1. **历史记录系统**：统一执行操作作为历史记录单元格
2. **状态栏**：显示 "Waiting for background terminal" 状态
3. **UI 渲染**：在活跃单元格或历史记录中显示

### 相关测试
- `unified_exec_wait_status_renders_command_in_single_details_row`：验证状态栏显示
- `unified_exec_ps_lists_running_processes`：验证 `/ps` 命令列出运行中的进程

## 风险、边界与改进建议

### 当前风险

1. **空交互语义不清**：两次空交互（`""`）在历史记录中没有单独体现，用户可能不知道发生了多次交互
2. **无输出记录**：测试未验证命令的输出是否被记录
3. **进程状态丢失**：`proc-1` 进程 ID 在历史记录中未显示

### 边界情况

1. **非空交互**：
   ```rust
   terminal_interaction(&mut chat, "call-wait-1c", "proc-1", "y\n");
   ```
   预期显示：`Interacted with 'just fix', sent 'y'`

2. **长命令**：
   ```rust
   begin_unified_exec_startup(&mut chat, "call-long", "proc-long", 
       "cargo test -p codex-core -- --exact some::very::long::test::name");
   ```
   命令截断行为？

3. **多进程并发**：
   多个 Unified Exec 进程同时运行时的显示

4. **进程失败**：
   非零退出码时的显示差异

### 改进建议

1. **交互计数显示**：
   ```
   • Waited for background terminal (2 interactions) · just fix
   ```

2. **展开详情**：
   ```
   • Waited for background terminal · just fix
     ├ Interaction 1: (empty)
     └ Interaction 2: (empty)
   ```

3. **进程 ID 显示**：
   ```
   • Waited for background terminal [proc-1] · just fix
   ```

4. **输出预览**：
   ```
   • Waited for background terminal · just fix
     └ Output: 42 lines, 1.2KB
   ```

5. **增加测试覆盖**：
   - 测试非空交互（发送实际输入）
   - 测试长命令截断
   - 测试多进程并发
   - 测试进程失败场景
   - 测试输出捕获

6. **时间记录**：
   ```
   • Waited for background terminal (5.2s) · just fix
   ```

7. **国际化**：
   - "Waited for" / "Interacted with" 需要本地化
   - 时间格式本地化
