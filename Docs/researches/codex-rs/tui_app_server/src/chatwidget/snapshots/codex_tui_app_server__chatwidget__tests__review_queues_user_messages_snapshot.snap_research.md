# Review Queues User Messages Snapshot 研究文档

## 场景与职责

该 snapshot 测试验证在代码审查（/review）模式下，当用户消息被排队时，TUI 的正确渲染行为。确保在审查模式运行时，用户可以看到队列中的后续消息提示，并了解如何编辑这些排队消息。

**测试文件**: `codex-rs/tui_app_server/src/chatwidget/tests.rs`  
**Snapshot 文件**: `codex_tui_app_server__chatwidget__tests__review_queues_user_messages_snapshot.snap`

## 功能点目的

1. **审查模式指示**: 显示当前正处于代码审查模式的状态
2. **消息队列提示**: 告知用户有消息正在等待审查完成后发送
3. **编辑指引**: 提供快捷键提示（⌥ + ↑）让用户可以编辑最后一条排队消息
4. **上下文保留**: 在审查期间保持上下文窗口信息的显示

## 具体技术实现

### 测试场景构建
```rust
#[tokio::test]
async fn review_queues_user_messages_snapshot() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.thread_id = Some(ThreadId::new());
    
    // 进入审查模式
    chat.handle_codex_event(Event {
        id: "review-1".into(),
        msg: EventMsg::EnteredReviewMode(ReviewRequest {
            target: ReviewTarget::UncommittedChanges,
            user_facing_hint: Some("current changes".to_string()),
        }),
    });
    let _ = drain_insert_history(&mut rx);
    
    // 将用户消息加入队列（在审查模式下，消息会被排队而非立即发送）
    chat.queue_user_message(UserMessage::from(
        "Queued while /review is running.".to_string(),
    ));
    
    // 使用 VT100 后端进行渲染测试
    let width: u16 = 80;
    let height: u16 = 18;
    let backend = VT100Backend::new(width, height);
    let mut term = crate::custom_terminal::Terminal::with_options(backend).expect("terminal");
    let desired_height = chat.desired_height(width).min(height);
    term.set_viewport_area(Rect::new(0, height - desired_height, width, desired_height));
    term.draw(|f| {
        chat.render(f.area(), f.buffer_mut());
    }).unwrap();
    
    assert_snapshot!(term.backend().vt100().screen().contents());
}
```

### 审查模式进入
```rust
fn on_entered_review_mode(&mut self, review: ReviewRequest) {
    let hint = review.user_facing_hint
        .unwrap_or_else(|| codex_core::review_prompts::user_facing_hint(&review.target));
    let banner = format!(">> Code review started: {hint} <<");
    self.add_to_history(history_cell::new_review_status_line(banner));
    
    if !self.bottom_pane.is_task_running() {
        self.bottom_pane.set_task_running(/*running*/ true);
    }
    self.is_review_mode = true;
}
```

### 消息队列处理
```rust
fn queue_user_message(&mut self, message: UserMessage) {
    self.queued_user_messages.push_back(message);
    self.refresh_pending_input_preview();
    
    // 显示队列提示
    if self.queued_user_messages.len() == 1 {
        self.add_info_message(
            "Queued follow-up messages".to_string(),
            Some("Queued while /review is running.".to_string()),
        );
    }
}
```

### 待输入预览刷新
```rust
fn refresh_pending_input_preview(&mut self) {
    if self.queued_user_messages.is_empty() {
        self.bottom_pane.set_pending_input_preview(None);
        return;
    }
    
    let preview = format!(
        "• Queued follow-up messages\n  ↳ Queued while /review is running.\n    ⌥ + ↑ edit last queued message"
    );
    self.bottom_pane.set_pending_input_preview(Some(preview));
}
```

## 关键代码路径与文件引用

| 文件路径 | 相关代码/函数 | 说明 |
|---------|-------------|------|
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | `review_queues_user_messages_snapshot()` (L11934) | 测试函数 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | `on_entered_review_mode()` | 进入审查模式处理 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | `queue_user_message()` | 消息入队处理 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | `refresh_pending_input_preview()` | 预览刷新 |
| `codex-rs/tui_app_server/src/history_cell.rs` | `new_review_status_line()` | 审查状态历史单元 |
| `codex-rs/tui_app_server/src/bottom_pane.rs` | `set_pending_input_preview()` | 底部面板预览设置 |
| `codex-rs/tui_app_server/src/test_backend.rs` | `VT100Backend` | VT100 测试后端 |

## 依赖与外部交互

### 依赖模块
- `codex_protocol::protocol::ReviewRequest`: 审查请求
- `codex_protocol::protocol::ReviewTarget`: 审查目标（未提交更改、分支等）
- `codex_protocol::protocol::EnteredReviewMode`: 进入审查模式事件
- `crate::history_cell`: 历史记录单元创建
- `crate::test_backend::VT100Backend`: VT100 渲染测试后端

### 审查目标类型
```rust
pub enum ReviewTarget {
    UncommittedChanges,           // 当前未提交更改
    BaseBranch { branch: String }, // 指定基础分支
}
```

### 用户消息队列
```rust
struct UserMessage {
    text: String,
    local_images: Vec<LocalImageAttachment>,
    remote_image_urls: Vec<String>,
    text_elements: Vec<TextElement>,
    mention_bindings: Vec<MentionBinding>,
}

queued_user_messages: VecDeque<UserMessage>,
```

### 快捷键绑定
- `⌥ + ↑` (Alt + Up): 编辑最后一条排队消息

## 风险、边界与改进建议

### 潜在风险
1. **队列溢出**: 长时间审查可能导致消息队列过长
2. **状态不一致**: 审查模式状态与消息队列状态可能不同步
3. **内存泄漏**: 排队消息中的图片附件可能占用大量内存

### 边界情况
1. **空队列**: 审查模式下没有排队消息时的显示
2. **多条消息**: 队列中有多个消息时的预览截断
3. **审查中断**: 审查被中断时队列消息的处理
4. **图片消息**: 包含图片的消息在队列中的显示

### 改进建议
1. **队列限制**: 设置最大队列长度，超过时提示用户
2. **队列管理**: 提供 `/queue` 命令查看和管理排队消息
3. **优先级**: 允许用户设置排队消息的优先级
4. **草稿保存**: 将排队消息自动保存为草稿，防止意外丢失
5. **批量编辑**: 支持批量编辑多条排队消息
6. **队列预览**: 在底部面板显示队列中消息的数量和摘要

### 相关测试覆盖
- 审查模式消息队列测试（本测试）
- 审查模式进入/退出测试
- 排队消息编辑测试
- 审查模式与正常模式切换测试

### Snapshot 内容分析
```









• Working (0s • esc to interrupt)

• Queued follow-up messages
  ↳ Queued while /review is running.
    ⌥ + ↑ edit last queued message

› Ask Codex to do anything

  ? for shortcuts                                            100% context left
```

**关键观察点**:
1. **工作状态**: "• Working (0s • esc to interrupt)" 显示审查正在进行
2. **队列提示**: "• Queued follow-up messages" 表明有消息在队列中
3. **编辑指引**: "⌥ + ↑ edit last queued message" 提供编辑快捷键
4. **上下文信息**: "100% context left" 显示上下文窗口使用情况
5. **输入区域**: "› Ask Codex to do anything" 保持可用状态

这表明审查模式下的 UI 能够清晰地传达当前状态和可用操作。
