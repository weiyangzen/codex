# ChatWidget 任务运行时禁用斜杠命令测试

## 场景与职责

该 snapshot 测试验证当任务正在运行时，某些斜杠命令（如 `/model`）被正确禁用，并向用户显示适当的错误消息。

### 测试目的
- 验证任务运行时的命令可用性控制
- 确保用户收到清晰的禁用提示
- 测试命令分发和错误处理流程

### 业务场景
- 用户正在等待 Codex 完成任务
- 用户尝试切换模型（`/model`）
- 系统应阻止该操作并解释原因

## 功能点目的

### 1. 命令可用性管理
某些命令在任务运行时应被禁用：
- `/model` - 切换模型
- `/reasoning` - 更改推理设置
- `/personality` - 更改个性设置
- 其他可能影响运行任务的操作

### 2. 用户反馈
当禁用命令被调用时：
- 显示清晰的错误消息
- 解释命令被禁用的原因
- 建议用户等待任务完成

## 具体技术实现

### 测试代码位置
```rust
// codex-rs/tui_app_server/src/chatwidget/tests.rs
#[tokio::test]
async fn disabled_slash_command_while_task_running_snapshot() {
    // 1. 构建 ChatWidget 并模拟活动任务
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.bottom_pane.set_task_running(true);

    // 2. 分派一个在任务运行时被禁用的命令（如 /model）
    chat.dispatch_command(SlashCommand::Model);

    // 3. 排空历史记录并捕获渲染的错误行
    let cells = drain_insert_history(&mut rx);
    assert!(
        !cells.is_empty(),
        "expected an error message history cell to be emitted",
    );
    let blob = lines_to_single_string(cells.last().unwrap());
    assert_snapshot!(blob);
}
```

### Snapshot 内容
```
■ '/model' is disabled while a task is in progress.
```

**分析**：
- 使用 `■` 符号作为错误/警告标记
- 明确指出被禁用的命令 `/model`
- 清晰说明原因：任务正在进行中

### 命令分发逻辑
```rust
// codex-rs/tui_app_server/src/chatwidget.rs

impl ChatWidget {
    /// 分派斜杠命令
    pub(crate) fn dispatch_command(&mut self, command: SlashCommand) {
        // 检查命令是否可用
        if self.is_command_disabled(&command) {
            self.show_disabled_command_message(&command);
            return;
        }
        
        // 执行命令
        match command {
            SlashCommand::Model => self.open_model_picker(),
            SlashCommand::Reasoning => self.open_reasoning_picker(),
            // ... 其他命令
        }
    }
    
    /// 检查命令是否被禁用
    fn is_command_disabled(&self, command: &SlashCommand) -> bool {
        if !self.bottom_pane.is_task_running() {
            return false;
        }
        
        matches!(command,
            SlashCommand::Model |
            SlashCommand::Reasoning |
            SlashCommand::Personality |
            // ... 其他禁用命令
        )
    }
    
    /// 显示禁用命令消息
    fn show_disabled_command_message(&mut self, command: &SlashCommand) {
        let cmd_name = command.name(); // "/model"
        let message = format!(
            "■ '{}' is disabled while a task is in progress.",
            cmd_name
        );
        
        self.emit_history_message(message);
    }
}
```

### 斜杠命令定义
```rust
// codex-rs/tui_app_server/src/slash_command.rs

pub enum SlashCommand {
    Model,           // /model - 切换模型
    Reasoning,       // /reasoning - 切换推理设置
    Personality,     // /personality - 切换个性
    FullAccess,      // /full-access - 全访问模式
    Approve,         // /approve - 批准策略
    // ... 其他命令
}

impl SlashCommand {
    pub fn name(&self) -> &'static str {
        match self {
            SlashCommand::Model => "/model",
            SlashCommand::Reasoning => "/reasoning",
            SlashCommand::Personality => "/personality",
            // ...
        }
    }
    
    /// 返回命令的可用性规则
    pub fn availability(&self) -> CommandAvailability {
        match self {
            // 任务运行时禁用
            SlashCommand::Model |
            SlashCommand::Reasoning |
            SlashCommand::Personality => CommandAvailability::RequiresIdle,
            
            // 始终可用
            SlashCommand::Help |
            SlashCommand::Status |
            SlashCommand::Quit => CommandAvailability::Always,
            
            // 任务运行时才可用
            SlashCommand::Interrupt => CommandAvailability::RequiresRunning,
        }
    }
}

pub enum CommandAvailability {
    Always,           // 始终可用
    RequiresIdle,     // 需要空闲状态
    RequiresRunning,  // 需要运行状态
}
```

## 关键代码路径与文件引用

### 底部面板任务状态
```rust
// codex-rs/tui_app_server/src/bottom_pane/mod.rs

pub struct BottomPane {
    task_running: bool,
    // ...
}

impl BottomPane {
    pub(crate) fn set_task_running(&mut self, running: bool) {
        self.task_running = running;
        // 更新相关 UI 状态
    }
    
    pub(crate) fn is_task_running(&self) -> bool {
        self.task_running
    }
}
```

### 历史消息插入
```rust
// codex-rs/tui_app_server/src/chatwidget.rs

impl ChatWidget {
    /// 向历史记录插入系统消息
    fn emit_history_message(&mut self, message: String) {
        let cell = PlainHistoryCell::new(message);
        self.app_event_tx.send(AppEvent::InsertHistoryCell(Box::new(cell)));
    }
}

// codex-rs/tui_app_server/src/history_cell.rs

pub struct PlainHistoryCell {
    content: String,
}

impl HistoryCell for PlainHistoryCell {
    fn display_lines(&self, _width: usize) -> Vec<Line> {
        vec![Line::from(self.content.clone())]
    }
}
```

### 命令解析
```rust
// codex-rs/tui_app_server/src/chatwidget.rs

/// 处理用户输入中的斜杠命令
fn handle_slash_command(&mut self, input: &str) -> bool {
    let command = match SlashCommand::parse(input) {
        Some(cmd) => cmd,
        None => return false,
    };
    
    self.dispatch_command(command);
    true
}
```

## 依赖与外部交互

### 命令可用性矩阵

| 命令 | 空闲时 | 运行时 | 说明 |
|------|--------|--------|------|
| `/model` | ✅ | ❌ | 切换模型 |
| `/reasoning` | ✅ | ❌ | 更改推理设置 |
| `/personality` | ✅ | ❌ | 更改个性 |
| `/interrupt` | ❌ | ✅ | 中断任务 |
| `/help` | ✅ | ✅ | 显示帮助 |
| `/status` | ✅ | ✅ | 显示状态 |
| `/quit` | ✅ | ✅ | 退出程序 |

### 状态转换
```
空闲状态 ──[/model]──→ 打开模型选择器
    │
    ├── 任务开始 ──→ 运行状态
    │
运行状态 ──[/model]──→ 显示禁用消息
    │
    ├── 任务完成 ──→ 空闲状态
    │
```

### 错误消息样式
```rust
// 错误消息使用特定样式
fn error_style() -> Style {
    Style::default()
        .fg(Color::Red)
        .add_modifier(Modifier::BOLD)
}

// 前缀符号
const ERROR_PREFIX: &str = "■";
const WARNING_PREFIX: &str = "▲";
const INFO_PREFIX: &str = "●";
```

## 风险、边界与改进建议

### 当前限制

1. **命令列表硬编码**
   - 禁用命令列表分散在代码中
   - 容易遗漏新添加的命令

2. **无重试机制**
   - 用户必须手动重新输入命令
   - 无法自动在任务完成后执行

3. **消息单一**
   - 所有禁用命令使用相同的消息格式
   - 无法提供命令特定的帮助

### 改进建议

1. **集中化命令配置**
   ```rust
   // commands.toml
   [commands.model]
   name = "/model"
   description = "Switch to a different model"
   availability = "idle_only"
   disabled_message = "Cannot switch models while a task is running."
   
   [commands.interrupt]
   name = "/interrupt"
   availability = "running_only"
   ```

2. **队列延迟执行**
   ```rust
   pub struct CommandQueue {
       pending: Vec<QueuedCommand>,
   }
   
   pub struct QueuedCommand {
       command: SlashCommand,
       execute_when: ExecutionCondition,
   }
   
   pub enum ExecutionCondition {
       TaskComplete,
       Immediate,
   }
   ```

3. **增强错误消息**
   ```rust
   fn show_disabled_command_message(&mut self, command: &SlashCommand) {
       let (cmd_name, reason, suggestion) = match command {
           SlashCommand::Model => (
               "/model",
               "switching models affects the running task",
               "Wait for the current task to complete, then try again.",
           ),
           // ... 其他命令
       };
       
       let message = format!(
           "■ '{}' is disabled while a task is in progress.\n  Reason: {}\n  Tip: {}",
           cmd_name, reason, suggestion
       );
       
       self.emit_history_message(message);
   }
   ```

4. **测试扩展**
   ```rust
   #[tokio::test]
   async fn all_disabled_commands_while_running() {
       let disabled_while_running = vec![
           SlashCommand::Model,
           SlashCommand::Reasoning,
           SlashCommand::Personality,
           // ...
       ];
       
       for command in disabled_while_running {
           let (mut chat, mut rx, _) = make_chatwidget_manual(None).await;
           chat.bottom_pane.set_task_running(true);
           chat.dispatch_command(command);
           
           let cells = drain_insert_history(&mut rx);
           assert!(!cells.is_empty(), "{:?} should emit message", command);
       }
   }
   ```

### 相关测试
- `chatwidget_exec_and_status_layout_vt100_snapshot` - 执行布局
- `interrupt_exec_marks_failed` - 中断功能
- `unified_exec_*` 系列 - 统一执行状态

---

*文档生成时间：2026-03-23*
*对应 snapshot：codex_tui_app_server__chatwidget__tests__disabled_slash_command_while_task_running_snapshot.snap*
