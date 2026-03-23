# 研究报告: unified_exec_empty_then_non_empty_after.snap

## 场景与职责

该快照文件验证 **Unified Exec** 在空交互后接收到非空输入时的历史记录渲染。当用户与后台终端交互时，先发送空输入（可能只是查看），然后发送实际命令（如 `ls`），系统需要正确记录这些交互。

测试场景：
- 启动 Unified Exec（`just fix` 命令）
- 发送空交互（仅按回车）
- 发送非空交互（`ls\n`）
- 验证历史记录正确显示两次交互

## 功能点目的

**后台终端交互记录**：

1. **交互追踪** - 记录用户与后台终端的所有交互
2. **上下文保留** - 保留完整的操作历史供参考
3. **空交互处理** - 正确处理查看性质的交互（空输入）
4. **命令关联** - 将交互与对应的 Unified Exec 进程关联

## 具体技术实现

### 测试实现

```rust
// tests.rs:5357-5372
#[tokio::test]
async fn unified_exec_empty_then_non_empty_snapshot() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.on_task_started();
    begin_unified_exec_startup(&mut chat, "call-wait-2", "proc-2", "just fix");

    // 空交互（查看）
    terminal_interaction(&mut chat, "call-wait-2a", "proc-2", "");
    // 非空交互（执行命令）
    terminal_interaction(&mut chat, "call-wait-2b", "proc-2", "ls\n");

    let cells = drain_insert_history(&mut rx);
    let combined = cells
        .iter()
        .map(|lines| lines_to_single_string(lines))
        .collect::<String>();
    assert_snapshot!("unified_exec_empty_then_non_empty_after", combined);
}
```

### 终端交互辅助函数

```rust
fn terminal_interaction(
    chat: &mut ChatWidget,
    call_id: &str,
    process_id: &str,
    stdin: &str,
) {
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

### 交互处理逻辑

```rust
fn on_terminal_interaction(&mut self, event: TerminalInteractionEvent) {
    // 查找对应的 Unified Exec 进程
    if let Some(process) = self.unified_exec_processes
        .iter_mut()
        .find(|p| p.key == event.process_id) 
    {
        // 记录交互
        if !event.stdin.is_empty() {
            process.recent_chunks.push(event.stdin.clone());
        }
        
        // 更新状态
        self.current_status.header = if event.stdin.is_empty() {
            "Interacted with background terminal".to_string()
        } else {
            format!("Interacted with background terminal · {}", 
                truncate(&process.command_display, 20))
        };
    }
}
```

### 渲染输出

```
• Waited for background terminal · just fix

↳ Interacted with background terminal · just fix
  └ ls
```

**解析**：
- 第一行：`Waited for background terminal` - 等待状态记录
- 空行：分隔不同交互
- `↳ Interacted with background terminal` - 交互记录标题
- `  └ ls` - 具体输入的命令（树形缩进显示）

## 关键代码路径与文件引用

| 文件 | 行号范围 | 描述 |
|------|----------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 5357-5372 | 空/非空交互测试 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 3480-3504 | `terminal_interaction` 辅助函数 |
| `codex-rs/tui/src/chatwidget/mod.rs` | - | 终端交互事件处理 |
| `codex-rs/tui/src/history_cell.rs` | - | 历史单元格渲染 |

## 依赖与外部交互

### TerminalInteractionEvent

```rust
codex_protocol::protocol::TerminalInteractionEvent {
    call_id: String,      // 调用 ID
    process_id: String,   // 进程 ID
    stdin: String,        // 用户输入（可能为空）
}
```

### 历史单元格类型

```rust
enum HistoryCell {
    UnifiedExecWait {      // 等待状态
        command: String,
        duration: Duration,
    },
    UnifiedExecInteract {  // 交互记录
        command: String,
        input: String,
        output: Vec<String>,
    },
}
```

## 风险、边界与改进建议

### 特定风险

1. **输入混淆** - 空输入和非空输入的区分不清
2. **历史膨胀** - 大量交互导致历史记录过长
3. **输出同步** - 交互后的输出可能延迟到达

### 边界情况

1. **多行输入** - 粘贴多行命令的处理
2. **特殊字符** - 控制字符、转义序列的显示
3. **并发交互** - 多个后台终端同时交互

### 改进建议

1. **交互分组** - 将同一进程的连续交互合并显示
2. **输出预览** - 显示交互后的部分输出
3. **时间戳** - 添加交互时间戳
4. **编辑功能** - 支持从历史交互中重新编辑发送
5. **快捷命令** - 常用命令的快速选择

### 相关测试

- `unified_exec_non_empty_then_empty_active` - 非空后空交互
- `unified_exec_non_empty_then_empty_after` - 回合完成后的状态
- `unified_exec_waiting_multiple_empty_after` - 多次空交互
