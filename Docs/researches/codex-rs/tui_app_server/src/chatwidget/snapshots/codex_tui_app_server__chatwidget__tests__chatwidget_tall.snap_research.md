# ChatWidget 高尺寸终端测试

## 场景与职责

该 snapshot 测试验证 `ChatWidget` 在高尺寸终端（80x24）且包含大量排队消息时的渲染表现。测试重点验证消息队列预览功能在充足垂直空间下的行为。

### 测试目的
- 验证大量排队消息的显示和布局
- 确保消息队列预览在充足空间下正确渲染
- 测试状态指示器和输入框的共存

### 业务场景
- 用户快速连续发送多条消息
- 任务运行期间用户继续输入后续问题
- 查看所有待处理的消息队列

## 功能点目的

### 1. 消息队列管理
当任务运行时，新消息被排队而非立即发送：
- 显示队列中的消息数量
- 预览每条消息的内容（截断显示）
- 提供视觉反馈表明消息已接收

### 2. 高尺寸终端利用
在24行高度下：
- 可以显示更多排队消息（本测试显示16条）
- 状态指示器有充足空间
- 输入框和帮助行清晰可见

## 具体技术实现

### 测试代码位置
```rust
// codex-rs/tui_app_server/src/chatwidget/tests.rs
#[tokio::test]
async fn chatwidget_tall() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.thread_id = Some(ThreadId::new());
    
    // 1. 模拟任务开始
    chat.handle_codex_event(Event {
        id: "t1".into(),
        msg: EventMsg::TurnStarted(TurnStartedEvent {
            turn_id: "turn-1".to_string(),
            model_context_window: None,
            collaboration_mode_kind: ModeKind::Default,
        }),
    });
    
    // 2. 添加30条排队消息
    for i in 0..30 {
        chat.queue_user_message(format!("Hello, world! {i}").into());
    }
    
    // 3. 设置 VT100 终端
    let width: u16 = 80;
    let height: u16 = 24;
    let backend = VT100Backend::new(width, height);
    let mut term = crate::custom_terminal::Terminal::with_options(backend).expect("terminal");
    
    // 4. 计算并设置视口
    let desired_height = chat.desired_height(width).min(height);
    term.set_viewport_area(Rect::new(0, height - desired_height, width, desired_height));
    
    // 5. 渲染并捕获
    term.draw(|f| {
        chat.render(f.area(), f.buffer_mut());
    }).unwrap();
    
    assert_snapshot!(term.backend().vt100().screen().contents());
}
```

### Snapshot 内容分析
```
（空行 x 5）
• Working (0s • esc to interrupt)

• Queued follow-up messages
  ↳ Hello, world! 0
  ↳ Hello, world! 1
  ↳ Hello, world! 2
  ↳ Hello, world! 3
  ↳ Hello, world! 4
  ↳ Hello, world! 5
  ↳ Hello, world! 6
  ↳ Hello, world! 7
  ↳ Hello, world! 8
  ↳ Hello, world! 9
  ↳ Hello, world! 10
  ↳ Hello, world! 11
  ↳ Hello, world! 12
  ↳ Hello, world! 13
  ↳ Hello, world! 14
  ↳ Hello, world! 15

› Ask Codex to do anything

  ? for shortcuts                                            100% context left
```

**布局解析**：
- 第1-5行：空行（历史记录区域）
- 第6行：状态指示器（"Working" + 计时器 + 中断提示）
- 第7行：空行（分隔）
- 第8行：队列标题（"Queued follow-up messages"）
- 第9-24行：排队消息列表（16条，编号0-15）
- 第25行：空行（分隔）
- 第26行：输入框提示符
- 第27行：帮助行

**注意**：虽然添加了30条消息，但只显示16条，说明有截断逻辑。

## 关键代码路径与文件引用

### 消息队列实现
```rust
// codex-rs/tui_app_server/src/chatwidget.rs

pub(crate) struct ChatWidget {
    // 排队等待发送的用户消息
    queued_user_messages: VecDeque<UserMessage>,
    // ...
}

impl ChatWidget {
    /// 将消息加入队列
    pub(crate) fn queue_user_message(&mut self, message: UserMessage) {
        self.queued_user_messages.push_back(message);
        self.refresh_pending_input_preview();
    }
    
    /// 刷新待处理输入预览
    fn refresh_pending_input_preview(&mut self) {
        // 更新底部面板的队列预览
        let preview: Vec<String> = self.queued_user_messages
            .iter()
            .map(|msg| truncate(&msg.text, 50)) // 截断显示
            .collect();
        self.bottom_pane.set_queue_preview(preview);
    }
}
```

### 底部面板队列渲染
```rust
// codex-rs/tui_app_server/src/bottom_pane/mod.rs

impl BottomPane {
    fn render_queue_preview(&self, area: Rect, buf: &mut Buffer) {
        let title = "Queued follow-up messages";
        
        // 计算可显示的消息数量
        let max_visible = (area.height as usize).saturating_sub(1); // 减去标题行
        
        // 渲染标题
        buf.set_string(area.x, area.y, title, Style::default().bold());
        
        // 渲染消息列表
        for (i, msg) in self.queue_preview.iter().take(max_visible).enumerate() {
            let line_y = area.y + 1 + i as u16;
            let prefix = "↳ ";
            buf.set_string(area.x + 2, line_y, prefix, Style::default());
            buf.set_string(area.x + 4, line_y, msg, Style::default());
        }
        
        // 如果有更多消息，显示 "+N more"
        if self.queue_preview.len() > max_visible {
            let remaining = self.queue_preview.len() - max_visible;
            let more_text = format!("+{} more", remaining);
            let line_y = area.y + area.height - 1;
            buf.set_string(area.x + 2, line_y, more_text, Style::default().dim());
        }
    }
}
```

### 高度计算
```rust
// codex-rs/tui_app_server/src/chatwidget.rs

pub(crate) fn desired_height(&self, width: u16) -> u16 {
    let mut height = 0u16;
    
    // 状态指示器高度
    if self.should_show_status() {
        height += 1;
        // 状态详情可能占用更多行
        if let Some(details) = &self.current_status.details {
            height += details.lines().count() as u16;
        }
    }
    
    // 队列预览高度
    if !self.queued_user_messages.is_empty() {
        height += 1; // 标题
        height += self.queued_user_messages.len().min(16) as u16; // 最多16条
    }
    
    // 输入框高度
    height += 1;
    
    // 帮助行高度
    height += 1;
    
    height
}
```

## 依赖与外部交互

### 数据结构
```rust
// 用户消息
pub struct UserMessage {
    text: String,
    local_images: Vec<LocalImageAttachment>,
    remote_image_urls: Vec<String>,
    text_elements: Vec<TextElement>,
    mention_bindings: Vec<MentionBinding>,
}

// 本地图片附件
pub struct LocalImageAttachment {
    placeholder: String,  // 如 "[Image #1]"
    path: PathBuf,
}
```

### 事件流
```
用户输入 → queue_user_message()
                ↓
    queued_user_messages.push_back()
                ↓
    refresh_pending_input_preview()
                ↓
    bottom_pane.set_queue_preview()
                ↓
    触发重绘
                ↓
    render() → render_queue_preview()
```

### 配置选项
| 配置项 | 影响 |
|--------|------|
| `animations` | 是否显示 spinner 动画 |
| `features` | 功能开关可能影响队列显示 |

## 风险、边界与改进建议

### 当前限制

1. **队列长度限制**
   - 仅显示最多16条消息
   - 用户无法直接查看完整队列
   - 需要滚动或展开功能

2. **消息截断**
   - 长消息被截断为50字符
   - 可能丢失重要上下文

3. **无交互功能**
   - 无法从队列中删除单条消息
   - 无法重新排序队列
   - 只能编辑最近一条（Alt+Up）

### 改进建议

1. **队列管理增强**
   ```rust
   // 添加队列管理命令
   enum QueueCommand {
       Remove(usize),      // 删除指定位置消息
       Move(usize, usize), // 移动消息顺序
       Clear,              // 清空队列
       Edit(usize),        // 编辑指定消息
   }
   ```

2. **可展开队列预览**
   ```rust
   // 添加展开/折叠功能
   fn render_queue_preview(&self, area: Rect, buf: &mut Buffer, expanded: bool) {
       if expanded {
           // 显示完整队列（带滚动）
       } else {
           // 显示摘要（如当前实现）
       }
   }
   ```

3. **消息优先级**
   ```rust
   pub struct UserMessage {
       // ... 现有字段 ...
       priority: MessagePriority, // 高/中/低
       timestamp: Instant,
   }
   ```

4. **测试增强**
   ```rust
   #[tokio::test]
   async fn queue_overflow_behavior() {
       // 测试超过最大显示数量的行为
       for i in 0..100 {
           chat.queue_user_message(format!("Message {i}").into());
       }
       // 验证 "+84 more" 显示
   }
   
   #[tokio::test]
   async fn queue_message_with_images() {
       // 测试带图片的消息队列显示
   }
   ```

### 相关测试
- `chat_small_running_h3` - 小高度下的队列显示
- `alt_up_edits_most_recent_queued_message` - 队列编辑功能
- `enqueueing_history_prompt_multiple_times_is_stable` - 队列稳定性

---

*文档生成时间：2026-03-23*
*对应 snapshot：codex_tui_app_server__chatwidget__tests__chatwidget_tall.snap*
