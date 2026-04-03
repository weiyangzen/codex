# Research: User Shell LS Output

## 场景与职责

该 snapshot 测试验证当用户通过 shell 执行命令（如 `ls`）时，命令输出在历史记录中的正确显示。

**测试场景：**
- 用户在 shell 模式下执行 `ls` 命令
- 命令输出包含多行内容（file1, file2）
- 验证输出正确显示在历史记录中

**核心职责：**
1. 确保用户 shell 命令与代理命令的显示区分
2. 验证命令输出的正确渲染
3. 确保历史记录单元格的正确创建和插入

---

## 功能点目的

### 1. 用户 Shell 命令执行（User Shell Execution）
Codex 支持用户直接执行 shell 命令（通过 `/shell` 或类似命令）。这些命令：
- 由用户主动发起，而非代理
- 输出直接显示给用户
- 不触发代理的代码分析流程

### 2. 命令来源区分（Command Source Distinction）
通过 `ExecCommandSource` 区分命令来源：
- `UserShell`: 用户直接执行的 shell 命令
- `Agent`: 代理执行的命令
- `UnifiedExecStartup/Interaction`: 统一执行框架命令

### 3. 输出渲染（Output Rendering）
用户 shell 命令的输出以简洁格式显示：
- 显示执行的命令
- 显示命令的标准输出
- 不显示额外的分析或元数据

---

## 具体技术实现

### 测试代码路径
**文件**: `codex-rs/tui/src/chatwidget/tests.rs`  
**函数**: `user_shell_command_renders_output_not_exploring`

```rust
#[tokio::test]
async fn user_shell_command_renders_output_not_exploring() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;

    let begin_ls = begin_exec_with_source(
        &mut chat,
        "user-shell-ls",
        "ls",
        ExecCommandSource::UserShell,
    );
    end_exec(&mut chat, begin_ls, "file1\nfile2\n", "", 0);

    let cells = drain_insert_history(&mut rx);
    assert_eq!(
        cells.len(),
        1,
        "expected a single history cell for the user command"
    );
    let blob = lines_to_single_string(cells.first().unwrap());
    assert_snapshot!("user_shell_ls_output", blob);
}
```

### 关键实现组件

#### 1. 命令来源定义
```rust
enum ExecCommandSource {
    Agent,
    UserShell,
    UnifiedExecStartup,
    UnifiedExecInteraction,
}
```

#### 2. 执行开始处理
```rust
fn begin_exec_with_source(
    chat: &mut ChatWidget,
    call_id: &str,
    raw_cmd: &str,
    source: ExecCommandSource,
) -> ExecCommandBeginEvent {
    let command = vec!["bash".to_string(), "-lc".to_string(), raw_cmd.to_string()];
    let parsed_cmd = codex_shell_command::parse_command::parse_command(&command);
    let event = ExecCommandBeginEvent {
        call_id: call_id.to_string(),
        process_id: None,
        turn_id: "turn-1".to_string(),
        command,
        cwd,
        parsed_cmd,
        source,
        interaction_input: None,
    };
    chat.handle_codex_event(Event {
        id: call_id.into(),
        msg: EventMsg::ExecCommandBegin(event.clone()),
    });
    event
}
```

#### 3. 执行结束处理
```rust
fn end_exec(
    chat: &mut ChatWidget,
    begin_event: ExecCommandBeginEvent,
    stdout: &str,
    stderr: &str,
    exit_code: i32,
) {
    let aggregated = if stderr.is_empty() {
        stdout.to_string()
    } else {
        format!("{stdout}{stderr}")
    };
    chat.handle_codex_event(Event {
        id: begin_event.call_id.clone().into(),
        msg: EventMsg::ExecCommandEnd(ExecCommandEndEvent {
            call_id: begin_event.call_id,
            turn_id: begin_event.turn_id,
            command: begin_event.command,
            source: begin_event.source,
            process_id: begin_event.process_id,
            stdout: stdout.as_bytes().to_vec(),
            stderr: stderr.as_bytes().to_vec(),
            exit_code,
            formatted_output: aggregated.clone(),
            aggregated_output: aggregated,
        }),
    });
}
```

#### 4. 历史记录单元格创建
对于 `UserShell` 来源的命令，创建专门的历史记录单元格：
```rust
// 在 handle_exec_end_now 中
let cell = history_cell::new_user_shell_exec(
    command_display,
    output.formatted_output,
    exit_code,
);
self.add_boxed_history(cell);
```

---

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget.rs` | ChatWidget 主实现 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 测试代码 |
| `codex-rs/tui/src/history_cell.rs` | 历史记录单元格创建 |
| `codex-rs/tui/src/exec_cell.rs` | 执行单元格实现 |

### 关键函数

| 函数 | 位置 | 职责 |
|-----|------|------|
| `begin_exec_with_source` | `tests.rs:3476` | 测试辅助：开始执行 |
| `end_exec` | `tests.rs:3604` | 测试辅助：结束执行 |
| `handle_exec_end_now` | `chatwidget.rs` | 处理执行结束 |
| `new_user_shell_exec` | `history_cell.rs` | 创建用户 shell 执行记录 |
| `drain_insert_history` | `tests.rs` | 测试辅助：获取历史记录 |

### 相关协议类型

| 类型 | 定义位置 | 说明 |
|-----|---------|------|
| `ExecCommandSource` | `codex-protocol/src/protocol.rs` | 命令来源枚举 |
| `ExecCommandBeginEvent` | `codex-protocol/src/protocol.rs` | 命令开始事件 |
| `ExecCommandEndEvent` | `codex-protocol/src/protocol.rs` | 命令结束事件 |

---

## 依赖与外部交互

### 内部依赖

```
tui/src/chatwidget.rs
├── tui/src/history_cell.rs (历史记录单元格)
├── tui/src/exec_cell.rs (执行单元格)
└── codex-protocol/src/protocol.rs (协议定义)
```

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `codex_shell_command::parse_command` | 解析 shell 命令 |

### 命令处理流程

```
User Shell Command
    ↓
ExecCommandBeginEvent (source = UserShell)
    ↓
ChatWidget::on_exec_command_begin
    ↓
ExecCommandEndEvent
    ↓
ChatWidget::handle_exec_end_now
    ↓
HistoryCell::new_user_shell_exec
    ↓
AppEvent::InsertHistoryCell
```

---

## 风险、边界与改进建议

### 潜在风险

1. **命令来源混淆**
   - 用户 shell 命令和代理命令可能显示相似
   - **缓解**: 使用不同的前缀或图标区分

2. **大输出处理**
   - 用户 shell 命令可能产生大量输出
   - **缓解**: 实现输出截断和折叠

3. **错误处理**
   - 命令失败时的错误信息可能不够清晰
   - **缓解**: 改进错误信息显示

### 边界情况

| 场景 | 行为 |
|-----|------|
| 空输出 | 显示命令，无输出内容 |
| 仅 stderr | 显示 stderr 内容 |
| 大输出 | 可能截断显示 |
| 非零退出码 | 显示错误标记 |
| 多行输出 | 正确换行显示 |

### 改进建议

1. **添加命令执行时间**
   - 显示命令执行耗时

2. **支持输出折叠**
   - 对于大输出，提供展开/折叠功能

3. **添加复制功能**
   - 允许用户复制命令输出

4. **改进视觉区分**
   - 使用不同颜色或图标区分用户命令和代理命令

5. **添加命令历史**
   - 支持查看和重新执行之前的用户命令

---

## Snapshot 内容分析

```
• You ran ls
  └ file1
    file2
```

**观察要点：**
1. 使用 "You ran" 明确标识这是用户执行的命令
2. 命令（ls）与状态文本在同一行
3. 输出内容以树形结构显示
4. 多行输出正确缩进对齐
5. 简洁清晰，无多余信息

**与代理命令对比：**
- 用户命令: "You ran ls"
- 代理命令: "• Ran ls" 或 "• Exploring"
