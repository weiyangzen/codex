# 研究报告: review_queues_user_messages_snapshot.snap

## 场景与职责

该快照文件验证在 **Review 模式** 下，用户消息队列的渲染效果。当用户进入 `/review` 模式查看未提交更改时，发送的新消息会被排队，此快照捕获了这一状态的 UI 表现。

测试场景：
- 用户进入 Review 模式（针对未提交更改）
- 用户尝试发送新消息 "Queued while /review is running."
- 消息被排队等待 Review 模式结束后处理

## 功能点目的

**Review 模式消息队列** 功能确保：

1. **非中断体验** - 用户可以在 Review 模式下继续输入，无需等待
2. **状态可见性** - 用户清楚看到消息已被排队
3. **顺序保证** - 排队的消息按顺序在 Review 结束后处理
4. **编辑能力** - 支持编辑最后一条排队消息 (⌥ + ↑)

## 具体技术实现

### 测试实现

```rust
// tests.rs:11201-11229
#[tokio::test]
async fn review_queues_user_messages_snapshot() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.thread_id = Some(ThreadId::new());

    // 进入 Review 模式
    chat.handle_codex_event(Event {
        id: "review-1".into(),
        msg: EventMsg::EnteredReviewMode(ReviewRequest {
            target: ReviewTarget::UncommittedChanges,
            user_facing_hint: Some("current changes".to_string()),
        }),
    });
    let _ = drain_insert_history(&mut rx);

    // 尝试发送消息（会被排队）
    chat.queue_user_message(UserMessage::from(
        "Queued while /review is running.".to_string(),
    ));

    // 渲染并快照
    let width: u16 = 80;
    let height: u16 = 18;
    let backend = VT100Backend::new(width, height);
    let mut term = crate::custom_terminal::Terminal::with_options(backend).expect("terminal");
    let desired_height = chat.desired_height(width).min(height);
    term.set_viewport_area(Rect::new(0, height - desired_height, width, desired_height));
    term.draw(|f| {
        chat.render(f.area(), f.buffer_mut());
    })
    .unwrap();
    assert_snapshot!(term.backend().vt100().screen().contents());
}
```

### 关键数据结构

```rust
// 排队消息存储
codex_protocol::protocol::ReviewRequest {
    target: ReviewTarget,           // UncommittedChanges / ConflictedFiles
    user_facing_hint: Option<String>, // "current changes"
}

// ChatWidget 内部状态
struct ChatWidget {
    queued_user_messages: VecDeque<UserMessage>, // 排队消息队列
    // ...
}
```

### 渲染输出解析

```









• Working (0s • esc to interrupt)

• Queued follow-up messages
  ↳ Queued while /review is running.
    ⌥ + ↑ edit last queued message

› Ask Codex to do anything

  ? for shortcuts                                            100% context left
```

**关键元素**：
- `• Working` - 状态指示器显示 Review 正在进行
- `• Queued follow-up messages` - 排队消息区域标题
- `↳ Queued while /review is running.` - 具体的排队消息内容
- `⌥ + ↑ edit last queued message` - 编辑提示
- `? for shortcuts` - 快捷键提示
- `100% context left` - 上下文余量显示

## 关键代码路径与文件引用

| 文件 | 行号范围 | 描述 |
|------|----------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 11201-11229 | Review 队列消息测试 |
| `codex-rs/tui/src/chatwidget/mod.rs` | - | `queue_user_message` 方法 |
| `codex-rs/tui/src/bottom_pane/` | - | 消息队列渲染组件 |
| `codex-protocol/src/protocol.rs` | - | `ReviewRequest`, `ReviewTarget` 定义 |

## 依赖与外部交互

### Review 模式事件流

1. **进入 Review** - `EventMsg::EnteredReviewMode`
2. **排队消息** - 本地存储到 `queued_user_messages`
3. **退出 Review** - `EventMsg::ExitedReviewMode`
4. **发送排队消息** - Review 结束后自动发送

### 编辑功能

```rust
// 支持 ⌥ + ↑ 编辑最后一条排队消息
fn edit_last_queued_message(&mut self) {
    if let Some(msg) = self.queued_user_messages.back() {
        // 将消息加载到输入框
        self.bottom_pane.set_composer_text(msg.text.clone(), ...);
        // 从队列移除
        self.queued_user_messages.pop_back();
    }
}
```

## 风险、边界与改进建议

### 特定风险

1. **队列溢出** - 大量消息排队可能导致内存问题
2. **状态不一致** - Review 模式异常退出时队列处理
3. **并发编辑** - 用户同时编辑排队消息和输入新消息

### 边界情况

1. **空队列** - 所有排队消息被编辑/删除后
2. **Review 中断** - 用户中断 Review 模式时的队列处理
3. **会话恢复** - 恢复会话时排队消息的状态

### 改进建议

1. **队列限制** - 添加最大排队消息数限制（如 10 条）
2. **队列管理** - 支持查看和删除特定排队消息
3. **优先级** - 支持高优先级消息跳过队列
4. **持久化** - 会话恢复时保留排队消息
5. **批量编辑** - 支持批量编辑多条排队消息

### 相关测试

- `review_popup_custom_prompt_action_sends_event` - Review 弹窗自定义提示测试
- `review_ended_keeps_unified_exec_processes` - Review 结束保持后台进程测试
