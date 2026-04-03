# Snapshot Research: slash_copy_no_output_info_message

## 场景与职责

此快照测试验证当用户执行 `/copy` 命令但没有可复制的输出时显示的信息消息。`/copy` 命令用于复制 Codex 的最后输出到剪贴板，但在某些情况下（如首次使用或回滚后）可能没有可用的输出内容。

测试场景：
- 创建新的 ChatWidget（没有历史输出）
- 用户执行 `/copy` 命令（`dispatch_command(SlashCommand::Copy)`）
- 由于没有可复制的输出，系统显示信息消息
- 捕获并验证信息消息内容

## 功能点目的

1. **用户引导**：告知用户为什么 `/copy` 命令当前不可用
2. **状态说明**：解释 `/copy` 命令的使用前提条件
3. **防止困惑**：避免用户因命令无响应而感到困惑
4. **教育用户**：帮助用户理解 `/copy` 命令的正确使用时机

## 具体技术实现

### 关键流程

1. **复制命令处理流程**：
   ```
   /copy 命令 → dispatch_command(SlashCommand::Copy)
   ↓
   检查 last_copyable_output
   ↓
   如果为 None → 显示信息消息
   ↓
   信息内容："/copy is unavailable before the first Codex output..."
   ```

2. **可复制输出跟踪**：
   - `last_copyable_output: Option<String>` 存储最后可复制的输出
   - 在 `TurnComplete` 事件中更新
   - 在 `ThreadRolledBack` 事件中清除

### 数据结构

```rust
pub enum SlashCommand {
    Copy,
    // ...
}

// ChatWidget 中的状态
last_copyable_output: Option<String>,
```

### 复制命令处理

```rust
fn dispatch_command(&mut self, cmd: SlashCommand) {
    match cmd {
        SlashCommand::Copy => {
            if let Some(output) = &self.last_copyable_output {
                // 复制到剪贴板
                self.submit_op(Op::CopyToClipboard { text: output.clone() });
            } else {
                // 显示信息消息
                self.add_info_message(
                    "`/copy` is unavailable before the first Codex output or right after a rollback.".to_string(),
                    None,
                );
            }
        }
        // ...
    }
}
```

### 可复制输出更新

```rust
// 在 TurnComplete 事件中更新
EventMsg::TurnComplete(TurnCompleteEvent { last_agent_message, .. }) => {
    if let Some(msg) = last_agent_message {
        self.last_copyable_output = Some(msg);
    }
}

// 在 ThreadRolledBack 事件中清除
EventMsg::ThreadRolledBack(_) => {
    self.last_copyable_output = None;
}
```

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 测试定义（tui，line ~5964） |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试定义（tui_app_server，line ~6573） |
| `codex-rs/tui/src/chatwidget.rs` | `/copy` 命令处理和状态管理 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | 同上 |

### 关键函数

- `ChatWidget::dispatch_command()` - 分发斜杠命令
- `ChatWidget::add_info_message()` - 添加信息消息到历史记录
- `drain_insert_history()` - 测试辅助函数，获取历史记录
- `lines_to_single_string()` - 测试辅助函数，将行转换为字符串

### 测试实现

```rust
#[tokio::test]
async fn slash_copy_reports_when_no_copyable_output_exists() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;

    chat.dispatch_command(SlashCommand::Copy);

    let cells = drain_insert_history(&mut rx);
    assert_eq!(cells.len(), 1, "expected one info message");
    let rendered = lines_to_single_string(&cells[0]);
    assert_snapshot!("slash_copy_no_output_info_message", rendered);
    assert!(
        rendered.contains(
            "`/copy` is unavailable before the first Codex output or right after a rollback."
        ),
        "expected no-output message, got {rendered:?}"
    );
}
```

## 依赖与外部交互

### 内部依赖

- `SlashCommand::Copy` - 复制命令枚举
- `last_copyable_output` - 可复制输出状态
- `TurnCompleteEvent` - 回合完成事件
- `ThreadRolledBackEvent` - 线程回滚事件

### 外部交互

- **剪贴板系统**：实际复制操作通过 `Op::CopyToClipboard` 执行
- **历史记录**：信息消息通过 `add_info_message` 添加到历史记录
- **事件系统**：通过事件更新可复制输出状态

## 风险、边界与改进建议

### 潜在风险

1. **状态同步**：`last_copyable_output` 可能与实际显示内容不同步
2. **格式丢失**：复制的输出可能丢失 Markdown 格式
3. **大内容处理**：非常大的输出可能导致性能问题

### 边界情况

- 空输出（空字符串）
- 仅包含空白字符的输出
- 包含控制字符的输出
- 多回合后的回滚

### 改进建议

1. **功能增强**：
   - 添加 `/copy last` 和 `/copy all` 选项
   - 支持复制特定回合的输出
   - 添加复制格式选项（纯文本/Markdown）

2. **UI/UX 改进**：
   - 在状态栏显示可复制状态指示
   - 添加快捷键支持（如 Ctrl+C）
   - 提供复制成功的视觉反馈

3. **测试覆盖**：
   - 添加复制成功后的状态验证
   - 测试回滚后的复制行为
   - 测试大内容复制的性能

---

**快照内容**：
```
• `/copy` is unavailable before the first Codex output or right after a rollback.
```

**说明**：显示当用户执行 `/copy` 命令但没有可复制输出时的信息消息。消息以项目符号（•）开头，清楚地说明 `/copy` 命令不可用的原因：在第一次 Codex 输出之前或回滚之后。这帮助用户理解命令的使用前提条件。
