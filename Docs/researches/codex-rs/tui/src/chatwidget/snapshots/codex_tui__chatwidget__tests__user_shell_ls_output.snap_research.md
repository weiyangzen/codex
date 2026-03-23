# 研究报告: user_shell_ls_output.snap

## 场景与职责

该快照文件验证 **用户执行的 shell 命令输出** 的渲染效果。当用户通过 `@` 语法或类似方式执行 shell 命令时，系统会记录命令及其输出。

测试场景：
- 用户执行 `ls` 命令
- 命令输出 `file1\nfile2\n`
- 验证历史记录正确显示命令和输出

## 功能点目的

**用户命令记录**：

1. **操作追踪** - 记录用户直接执行的命令
2. **输出保留** - 保存命令输出供参考
3. **上下文完整** - 在会话历史中保留完整的操作上下文
4. **审计支持** - 支持会话审计和回放

## 具体技术实现

### 测试实现

```rust
// tests.rs:8205-8242
#[tokio::test]
async fn user_shell_command_includes_output_in_history() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.thread_id = Some(ThreadId::new());

    // 模拟用户执行 ls 命令
    let begin_ls = begin_exec_with_source(
        &mut chat,
        "call-ls-user",
        "ls",
        ExecCommandSource::User, // 用户发起的命令
    );
    // 命令完成，带输出
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

### 命令执行辅助函数

```rust
fn begin_exec_with_source(
    chat: &mut ChatWidget,
    call_id: &str,
    raw_cmd: &str,
    source: ExecCommandSource, // 区分用户命令和 Agent 命令
) -> ExecCommandBeginEvent {
    let command = vec!["bash".to_string(), "-lc".to_string(), raw_cmd.to_string()];
    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    let event = ExecCommandBeginEvent {
        call_id: call_id.to_string(),
        process_id: None,
        turn_id: "turn-1".to_string(),
        command,
        cwd,
        parsed_cmd: Vec::new(),
        source, // User 或 Agent
        interaction_input: None,
    };
    chat.handle_codex_event(Event {
        id: call_id.to_string(),
        msg: EventMsg::ExecCommandBegin(event.clone()),
    });
    event
}
```

### 渲染输出

```
• You ran ls
  └ file1
    file2
```

**解析**：
- `• You ran ls` - 命令记录（用户执行）
- `  └ file1` - 第一行输出
- `    file2` - 第二行输出（缩进对齐）

**注意**：与 Agent 执行的命令不同，用户命令使用 "You ran" 前缀。

## 关键代码路径与文件引用

| 文件 | 行号范围 | 描述 |
|------|----------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 8205-8242 | 用户 shell 命令测试 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 3529-3550 | `begin_exec_with_source` 辅助函数 |
| `codex-rs/tui/src/history_cell.rs` | - | 历史单元格渲染 |

## 依赖与外部交互

### ExecCommandSource

```rust
codex_protocol::protocol::ExecCommandSource {
    User,               // 用户发起
    Agent,              // Agent 发起
    UnifiedExecStartup, // Unified Exec
    // ...
}
```

### 历史单元格区分

```rust
// 根据 source 使用不同的前缀
fn format_exec_header(source: ExecCommandSource, command: &str) -> String {
    match source {
        ExecCommandSource::User => format!("You ran {command}"),
        ExecCommandSource::Agent => format!("Ran {command}"),
        ExecCommandSource::Exploring => format!("Explored {command}"),
        // ...
    }
}
```

## 风险、边界与改进建议

### 特定风险

1. **输出过大** - 大量输出导致历史记录膨胀
2. **敏感信息** - 命令输出可能包含敏感信息
3. **编码问题** - 非 UTF-8 输出的处理

### 边界情况

1. **无输出** - 命令没有输出的情况
2. **错误输出** - stderr 的处理
3. **多行命令** - 复杂命令的显示

### 改进建议

1. **输出限制** - 限制保存的输出行数（如最多 100 行）
2. **折叠显示** - 大量输出默认折叠，可展开查看
3. **搜索功能** - 在历史命令输出中搜索
4. **导出功能** - 导出命令输出到文件
5. **语法高亮** - 对常见命令输出进行语法高亮

### 相关测试

- `user_shell_command_includes_stderr_in_history` - 包含 stderr 的测试
- `exploring_step1_start_ls` - Agent 执行的探索命令
