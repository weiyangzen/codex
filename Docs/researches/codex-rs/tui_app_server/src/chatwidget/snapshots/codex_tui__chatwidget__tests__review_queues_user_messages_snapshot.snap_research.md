# Snapshot Research: review_queues_user_messages_snapshot

## 场景与职责

此快照测试验证在审核（review）模式下用户消息队列的显示。当用户进入审核模式（如执行 `/review` 命令）时，新输入的消息会被排队而不是立即发送。此测试确保排队消息的 UI 反馈正确显示。

测试场景：
- 用户进入审核模式（`EnteredReviewMode` 事件）
- 用户输入消息被排队（`queue_user_message`）
- 排队消息显示在状态行下方
- 显示队列提示信息和编辑快捷方式
- 使用 VT100 后端捕获完整终端渲染输出

## 功能点目的

1. **队列状态反馈**：让用户知道他们的消息已被排队等待发送
2. **审核模式指示**：明确显示当前处于审核模式
3. **快捷操作提示**：提供编辑最后排队消息的快捷方式
4. **防止消息丢失**：确保用户知道消息不会立即发送

## 具体技术实现

### 关键流程

1. **审核模式队列流程**：
   ```
   EnteredReviewMode 事件 → is_review_mode = true
   ↓
   用户输入消息
   ↓
   queue_user_message() → 添加到 queued_user_messages
   ↓
   refresh_pending_input_preview() → 更新 UI
   ↓
   渲染排队消息提示
   ```

2. **队列显示**：
   - 在 Working 状态行下方显示排队消息
   - 显示队列原因（"Queued while /review is running"）
   - 提供编辑快捷方式提示（⌥ + ↑）

### 数据结构

```rust
pub struct ReviewRequest {
    pub target: ReviewTarget,
    pub user_facing_hint: Option<String>,
}

pub enum ReviewTarget {
    UncommittedChanges,
    // ...
}

pub struct UserMessage {
    pub text: String,
    // ...
}

// ChatWidget 中的队列
queued_user_messages: VecDeque<UserMessage>,
is_review_mode: bool,
```

### 队列逻辑

```rust
fn queue_user_message(&mut self, user_message: UserMessage) {
    if !self.is_session_configured()
        || self.bottom_pane.is_task_running()
        || self.is_review_mode
    {
        self.queued_user_messages.push_back(user_message);
        self.refresh_pending_input_preview();
    } else {
        self.submit_user_message(user_message);
    }
}
```

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 测试定义（tui，line ~11202） |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试定义（tui_app_server，line ~11934） |
| `codex-rs/tui/src/chatwidget.rs` | `queue_user_message()` 和审核模式处理 |
| `codex-rs/tui/src/bottom_pane/mod.rs` | 排队消息渲染 |

### 关键函数

- `ChatWidget::queue_user_message()` - 将消息加入队列
- `ChatWidget::refresh_pending_input_preview()` - 刷新待处理输入预览
- `ChatWidget::handle_codex_event()` - 处理 `EnteredReviewMode` 事件
- `VT100Backend` - 测试用的 VT100 终端后端

### 测试实现

```rust
#[tokio::test]
async fn review_queues_user_messages_snapshot() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.thread_id = Some(ThreadId::new());

    chat.handle_codex_event(Event {
        id: "review-1".into(),
        msg: EventMsg::EnteredReviewMode(ReviewRequest {
            target: ReviewTarget::UncommittedChanges,
            user_facing_hint: Some("current changes".to_string()),
        }),
    });
    let _ = drain_insert_history(&mut rx);

    chat.queue_user_message(UserMessage::from(
        "Queued while /review is running.".to_string(),
    ));

    let width: u16 = 80;
    let height: u16 = 18;
    let backend = VT100Backend::new(width, height);
    let mut term = crate::custom_terminal::Terminal::with_options(backend).expect("terminal");
    // ... 渲染和快照
}
```

## 依赖与外部交互

### 内部依赖

- `ReviewRequest`, `ReviewTarget` - 审核请求结构
- `UserMessage` - 用户消息结构
- `EventMsg::EnteredReviewMode` - 进入审核模式事件
- `VT100Backend` - VT100 终端后端

### 外部交互

- **审核系统**：与代码审核功能集成
- **Git 集成**：获取未提交更改信息
- **事件系统**：处理审核模式状态变化

## 风险、边界与改进建议

### 潜在风险

1. **队列堆积**：用户可能忘记发送排队的消息
2. **状态混淆**：用户可能不清楚为什么消息被排队
3. **多消息管理**：多个排队消息的显示和管理

### 边界情况

- 审核模式期间的任务中断
- 多个消息排队
- 审核模式取消后的队列处理
- 会话恢复后的队列状态

### 改进建议

1. **队列管理增强**：
   - 添加队列消息计数显示
   - 提供查看和编辑所有排队消息的界面
   - 添加队列清空功能

2. **UI/UX 改进**：
   - 添加更明显的审核模式指示器
   - 显示预计审核完成时间
   - 提供一键发送所有排队消息的选项

3. **测试覆盖**：
   - 添加多个排队消息的测试
   - 测试审核模式取消后的行为
   - 测试队列消息的持久化

---

**快照内容**：
```










• Working (0s • esc to interrupt)

• Queued follow-up messages
  ↳ Queued while /review is running.
    ⌥ + ↑ edit last queued message

› Ask Codex to do anything

  ? for shortcuts                                            100% context left
```

**说明**：显示审核模式下的 ChatWidget 渲染输出。关键元素包括：
- `• Working (0s • esc to interrupt)` - 工作状态指示
- `• Queued follow-up messages` - 排队消息提示
- `↳ Queued while /review is running.` - 队列原因说明
- `⌥ + ↑ edit last queued message` - 编辑快捷方式提示
- `› Ask Codex to do anything` - 输入提示符

这验证了审核模式下用户消息的队列状态正确显示。
