# status_and_queued_messages_snapshot 研究文档

## 场景与职责

本快照测试展示了 `BottomPane` 在**状态指示器和排队消息同时显示**时的渲染行为。验证当任务正在运行且有排队消息时，两者能够正确共存并合理布局。

**典型使用场景**：
- 后台任务执行期间用户排队了后续问题
- 需要同时显示任务状态和待发送消息
- 验证多元素共存时的布局正确性

## 功能点目的

该测试验证以下核心功能：

1. **元素共存**：状态指示器和排队消息同时正确显示
2. **视觉分层**：状态在上，排队消息在下，层次清晰
3. **空行分隔**：状态与排队消息之间有空行分隔
4. **布局完整性**：Composer 和底部状态栏正确渲染

**渲染输出特征**：
```
• Working (0s • esc to interrupt)                <- 状态指示器
                                                 <- 空行分隔
• Queued follow-up messages                      <- 排队消息标题
  ↳ Queued follow-up question                    <- 排队消息内容
    ⌥ + ↑ edit last queued message               <- 编辑提示
                                                 <- 空行
› Ask Codex to do anything                       <- Composer 占位符
                                                 <- 空行
  ? for shortcuts            100% context left   <- 底部状态栏
```

## 具体技术实现

### 测试设置
```rust
#[test]
fn status_and_queued_messages_snapshot() {
    let (tx_raw, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx_raw);
    let mut pane = BottomPane::new(BottomPaneParams {
        app_event_tx: tx,
        frame_requester: FrameRequester::test_dummy(),
        has_input_focus: true,
        enhanced_keys_supported: false,
        placeholder_text: "Ask Codex to do anything".to_string(),
        disable_paste_burst: false,
        animations_enabled: true,
        skills: Some(Vec::new()),
    });

    pane.set_task_running(true);
    pane.set_pending_input_preview(vec!["Queued follow-up question".to_string()], Vec::new());

    let width = 48;
    let height = pane.desired_height(width);
    let area = Rect::new(0, 0, width, height);
    assert_snapshot!("status_and_queued_messages_snapshot", render_snapshot(&pane, area));
}
```

### 布局逻辑
```rust
fn as_renderable(&'_ self) -> RenderableItem<'_> {
    let mut flex = FlexRenderable::new();
    
    // 1. 状态指示器
    if let Some(status) = &self.status {
        flex.push(/*flex*/ 0, RenderableItem::Borrowed(status));
    }
    
    // 2. 空行分隔（当同时有状态和排队消息时）
    let has_status_or_footer = self.status.is_some() || !self.unified_exec_footer.is_empty();
    let has_pending_input = !self.pending_input_preview.queued_messages.is_empty()
        || !self.pending_input_preview.pending_steers.is_empty();
    if has_pending_input && has_status_or_footer {
        flex.push(/*flex*/ 0, RenderableItem::Owned("".into()));
    }
    
    // 3. 排队消息预览
    flex.push(
        /*flex*/ 1,
        RenderableItem::Borrowed(&self.pending_input_preview),
    );
    
    // 4. Composer
    let mut flex2 = FlexRenderable::new();
    flex2.push(/*flex*/ 1, RenderableItem::Owned(flex.into()));
    flex2.push(/*flex*/ 0, RenderableItem::Borrowed(&self.composer));
}
```

## 关键代码路径与文件引用

### 主要文件
- `codex-rs/tui_app_server/src/bottom_pane/mod.rs` - BottomPane 组件实现
- `codex-rs/tui_app_server/src/bottom_pane/pending_input_preview.rs` - 排队消息预览

### 关键函数
| 函数 | 行号 | 职责 |
|------|------|------|
| `status_and_queued_messages_snapshot` (test) | 1584-1608 | 本测试用例 |
| `set_task_running()` | 716-740 | 启动任务，显示状态指示器 |
| `set_pending_input_preview()` | 815-823 | 设置排队消息 |
| `as_renderable()` | 1123-1167 | 主渲染逻辑 |

### 布局层次
```
FlexRenderable (flex2)
├── FlexRenderable (flex, flex: 1)
│   ├── StatusIndicatorWidget (flex: 0)
│   ├── "" (flex: 0, 空行分隔)
│   └── PendingInputPreview (flex: 1)
└── ChatComposer (flex: 0)
```

## 依赖与外部交互

### 依赖模块
- `crate::status_indicator_widget::StatusIndicatorWidget` - 状态指示器
- `crate::bottom_pane::pending_input_preview::PendingInputPreview` - 排队消息预览
- `crate::bottom_pane::chat_composer::ChatComposer` - 聊天输入框
- `crate::render::renderable::FlexRenderable` - 弹性布局

### 状态与消息关系
| 状态 | 排队消息 | 布局结果 |
|------|----------|----------|
| 有 | 有 | 状态 + 空行 + 消息 + Composer |
| 有 | 无 | 状态 + Composer |
| 无 | 有 | 消息 + Composer |
| 无 | 无 | Composer |

## 风险、边界与改进建议

### 当前边界情况
1. **单条消息**：测试只使用一条排队消息
2. **无详情**：状态指示器没有设置详细文本
3. **固定尺寸**：48 字符宽度

### 潜在风险
1. **高度膨胀**：同时显示多个元素时，总高度可能过高
2. **视觉拥挤**：元素之间缺乏足够的视觉分隔
3. **响应延迟**：状态更新和消息更新可能不同步

### 改进建议
1. **可折叠区域**：允许用户折叠状态或消息区域
2. **优先级显示**：当空间不足时，优先显示更重要的信息
3. **动画效果**：状态变化和消息添加时添加平滑动画
4. **计数徽章**：在状态行显示排队消息数量
5. **一键清除**：提供快捷键清除所有排队消息
6. **自适应布局**：根据终端高度动态调整显示内容
