# 研究报告: slash_copy_no_output_info_message.snap

## 场景与职责

该快照文件验证当用户执行 `/copy` 命令但**没有可复制内容**时，系统显示的提示信息。`/copy` 命令用于将 Codex 的最后输出复制到剪贴板，但在某些情况下该操作不可用。

测试场景：
- 用户尝试执行 `/copy` 命令
- 但当前没有可用的 Codex 输出（如会话刚开始或刚执行回滚）
- 系统显示友好的提示信息解释原因

## 功能点目的

**`/copy` 命令的边界处理**：

1. **防止误操作** - 明确告知用户为何无法复制
2. **状态教育** - 帮助用户理解何时可以使用 `/copy`
3. **替代引导** - 暗示用户需要先与 Codex 交互获取输出

## 具体技术实现

### 测试实现

```rust
// tests.rs:5954-5971
#[tokio::test]
async fn slash_copy_reports_when_no_copyable_output_exists() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;

    // 执行 /copy 命令（没有前置输出）
    chat.dispatch_command(SlashCommand::Copy);

    let cells = drain_insert_history(&mut rx);
    assert_eq!(cells.len(), 1, "expected one info message");
    let rendered = lines_to_single_string(&cells[0]);
    assert_snapshot!("slash_copy_no_output_info_message", rendered);
    assert!(
        rendered.contains(
            "`/copy` is unavailable before the first Codex output or right after a rollback."
        ),
        "expected no-output message"
    );
}
```

### 复制可用性检查

```rust
// chatwidget.rs (示意)
fn dispatch_command(&mut self, command: SlashCommand) {
    match command {
        SlashCommand::Copy => {
            if let Some(output) = &self.last_copyable_output {
                // 复制到剪贴板
                self.copy_to_clipboard(output);
            } else {
                // 显示不可用提示
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

### 关键状态管理

```rust
struct ChatWidget {
    last_copyable_output: Option<String>, // 最后可复制的输出
    // ...
}

// 更新可复制输出
fn on_turn_complete(&mut self, last_agent_message: Option<String>) {
    if let Some(msg) = last_agent_message {
        self.last_copyable_output = Some(msg);
    }
}

// 回滚时清除
fn on_thread_rollback(&mut self) {
    self.last_copyable_output = None;
}
```

### 渲染输出

```
• `/copy` is unavailable before the first Codex output or right after a rollback.
```

**特点**：
- 使用项目符号 `•` 标记为信息消息
- 使用反引号 `` ` `` 标记命令名
- 清晰说明两种不可用情况：
  1. 第一次 Codex 输出之前
  2. 刚执行回滚后

## 关键代码路径与文件引用

| 文件 | 行号范围 | 描述 |
|------|----------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 5954-5971 | `/copy` 无输出测试 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 5973-5991 | `/copy` 状态保持测试 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 5993-6010 | `/copy` 回滚清除测试 |
| `codex-rs/tui/src/chatwidget/mod.rs` | - | `SlashCommand::Copy` 处理 |

## 依赖与外部交互

### 剪贴板交互

```rust
// 使用 arboard 或其他剪贴板库
fn copy_to_clipboard(&self, text: &str) -> Result<(), Box<dyn Error>> {
    // 平台特定的剪贴板操作
    #[cfg(not(target_os = "linux"))]
    { /* 标准剪贴板操作 */ }
    
    #[cfg(target_os = "linux")]
    { /* 可能需要特殊处理 Wayland/X11 */ }
}
```

### 相关 Slash 命令

- `/copy` - 复制最后输出
- `/rollout` - 相关功能，导出会话记录

## 风险、边界与改进建议

### 特定风险

1. **剪贴板权限** - 某些环境（如远程 SSH）可能没有剪贴板访问权限
2. **大内容** - 非常大的输出复制可能导致延迟
3. **隐私泄露** - 敏感信息被复制到系统剪贴板

### 边界情况

1. **多行输出** - 正确处理包含换行符的输出
2. **ANSI 转义** - 是否保留或去除颜色代码
3. **图片输出** - 非文本输出的处理

### 改进建议

1. **复制确认** - 成功复制后显示短暂确认提示
2. **历史复制** - 支持复制更早的输出（如 `/copy 3` 复制倒数第 3 条）
3. **选择性复制** - 支持复制特定代码块或文件
4. **格式选项** - 支持 Markdown/纯文本/富文本格式
5. **隐私模式** - 敏感信息复制前添加确认提示

### 相关测试

- `slash_copy_state_is_preserved_during_running_task` - 任务运行时状态保持
- `slash_copy_state_clears_on_thread_rollback` - 回滚时状态清除
