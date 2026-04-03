# Slash Copy No Output Info Message 研究文档

## 场景与职责

该 snapshot 测试验证当用户执行 `/copy` 命令但没有可用的 Codex 输出时，系统显示的信息消息。确保用户清楚地了解为什么复制操作不可用，以及在什么条件下可以使用此功能。

**测试文件**: `codex-rs/tui_app_server/src/chatwidget/tests.rs`  
**Snapshot 文件**: `codex_tui_app_server__chatwidget__tests__slash_copy_no_output_info_message.snap`

## 功能点目的

1. **功能可用性提示**: 告知用户 `/copy` 命令的可用条件
2. **使用指导**: 解释为什么当前无法复制（没有输出或刚回滚）
3. **错误预防**: 防止用户困惑为什么复制操作没有产生预期效果
4. **状态同步**: 确保用户了解当前会话的输出状态

## 具体技术实现

### 复制命令处理逻辑
```rust
fn dispatch_command(&mut self, cmd: SlashCommand) {
    match cmd {
        SlashCommand::Copy => {
            // 检查是否有可复制的输出
            let Some(text) = self.last_copyable_output.as_deref() else {
                // 没有可用输出，显示信息消息
                self.add_info_message(
                    "`/copy` is unavailable before the first Codex output or right after a rollback."
                        .to_string(),
                    /*hint*/ None,
                );
                return;
            };
            
            // 执行复制操作
            let copy_result = clipboard_text::copy_text_to_clipboard(text);
            match copy_result {
                Ok(()) => {
                    let hint = self.agent_turn_running.then_some(
                        "Current turn is still running; copied the latest completed output (not the in-progress response)."
                            .to_string(),
                    );
                    self.add_info_message(
                        "Copied latest Codex output to clipboard.".to_string(),
                        hint,
                    );
                }
                Err(err) => {
                    self.add_error_message(format!("Failed to copy to clipboard: {err}"))
                }
            }
        }
        // ...
    }
}
```

### 可复制输出状态管理
```rust
struct ChatWidget {
    // 最新的可复制 Codex 输出
    last_copyable_output: Option<String>,
    // ...
}

fn on_turn_complete(&mut self, event: TurnCompleteEvent) {
    if let Some(last_message) = event.last_agent_message {
        self.last_copyable_output = Some(last_message);
    }
}

fn on_thread_rollback(&mut self) {
    // 回滚后清除可复制输出
    self.last_copyable_output = None;
}
```

### 测试用例实现
```rust
#[tokio::test]
async fn slash_copy_no_output_info_message_snapshot() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    
    // 确保没有可复制输出（默认状态）
    assert!(chat.last_copyable_output.is_none());
    
    // 执行 /copy 命令
    chat.dispatch_command(SlashCommand::Copy);
    
    // 获取显示的历史单元
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

## 关键代码路径与文件引用

| 文件路径 | 相关代码/函数 | 说明 |
|---------|-------------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs` | `dispatch_command()` (L4535) | 斜杠命令分发 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | `SlashCommand::Copy` 处理 (L4752) | 复制命令处理 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | `last_copyable_output` (L728) | 可复制输出状态 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | `on_turn_complete()` | 回合完成处理 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | `slash_copy_no_output_info_message_snapshot()` (L6568) | 测试函数 |
| `codex-rs/tui_app_server/src/clipboard_text.rs` | `copy_text_to_clipboard()` | 剪贴板复制功能 |

## 依赖与外部交互

### 依赖模块
- `crate::slash_command::SlashCommand`: 斜杠命令枚举
- `crate::clipboard_text`: 剪贴板操作模块
- `crate::history_cell`: 历史记录单元创建

### 可复制输出的条件
| 条件 | 状态 | 说明 |
|------|------|------|
| 首次输出前 | 不可用 | 还没有任何 Codex 回复 |
| 有完整回合后 | 可用 | 可以复制最后一条代理消息 |
| 回滚后 | 不可用 | 回滚清除了输出历史 |
| 回合进行中 | 部分可用 | 复制的是上一回合的输出，而非正在生成的 |

### 信息消息类型
```rust
fn add_info_message(&mut self, message: String, hint: Option<String>) {
    self.add_to_history(history_cell::new_info_event(message, hint));
}

fn add_error_message(&mut self, message: String) {
    self.add_to_history(history_cell::new_error_event(message));
}
```

## 风险、边界与改进建议

### 潜在风险
1. **状态同步延迟**: `last_copyable_output` 可能与实际显示内容不同步
2. **多行输出截断**: 复制的内容可能被截断或格式化
3. **剪贴板权限**: 某些环境可能无法访问剪贴板

### 边界情况
1. **空输出**: Codex 返回空响应时的处理
2. **仅图片输出**: 输出仅包含图片时的复制行为
3. **长输出**: 超长输出的剪贴板处理
4. **特殊字符**: 包含特殊 Unicode 字符的输出复制

### 改进建议
1. **输出预览**: 在复制前显示即将复制内容的预览
2. **复制历史**: 支持访问和复制更早的输出
3. **选择性复制**: 允许用户选择复制特定部分的输出
4. **格式保留**: 保留 Markdown 格式或纯文本选项
5. **快捷键支持**: 添加键盘快捷键（如 Ctrl+Shift+C）快速复制
6. **成功反馈**: 复制成功时显示更明显的视觉反馈

### 相关测试覆盖
- 无输出时复制提示测试（本测试）
- 复制状态保持测试
- 回滚后复制状态清除测试
- 复制成功消息测试

### Snapshot 内容分析
```
• `/copy` is unavailable before the first Codex output or right after a rollback.
```

**关键观察点**:
1. **信息级别**: 使用信息图标（•）而非错误图标，表示这是提示而非错误
2. **明确条件**: 清楚说明两种不可用情况（首次输出前、回滚后）
3. **简洁明了**: 单条消息传达完整信息
4. **Markdown 格式**: 命令使用反引号包裹，提高可读性

这表明系统在处理用户操作失败时提供了友好且有用的反馈。
