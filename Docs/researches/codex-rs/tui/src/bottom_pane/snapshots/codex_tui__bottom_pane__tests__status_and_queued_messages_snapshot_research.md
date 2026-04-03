# BottomPane - Status and Queued Messages Snapshot Research Document

## 场景与职责

此快照测试验证当任务正在运行且存在队列消息时，状态指示器和队列消息预览能够正确共存并渲染。这是 `BottomPane` 最常见的使用场景之一，确保用户可以同时看到当前任务状态和已排队的后续消息。

### 核心场景
- **任务运行中**：`set_task_running(true)` 激活状态指示器
- **队列消息存在**：`set_pending_input_preview()` 设置待处理的消息队列
- **预期行为**：状态指示器和队列消息预览同时可见，布局合理

## 功能点目的

### 1. 并发信息展示
- **目的**：在 AI 处理当前任务时，让用户了解已排队的后续消息
- **价值**：提高透明度，让用户知道他们的输入已被接收并等待处理
- **实现**：状态指示器和队列预览垂直堆叠显示

### 2. 视觉层次
- **目的**：通过布局和样式区分不同类型的信息
- **状态指示器**：使用 `•` 前缀和动画表示活动状态
- **队列消息**：使用 `↳` 前缀表示从属/排队关系
- **编辑提示**：使用 `⌥ + ↑` 显示键盘快捷键

### 3. 空间管理
- **目的**：在有限的空间内有效组织多个信息组件
- **实现**：使用间距行分隔不同功能区域
- **自适应**：根据内容动态调整布局

## 具体技术实现

### 测试代码分析
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

    pane.set_task_running(true);  // 激活任务状态
    pane.set_pending_input_preview(
        vec!["Queued follow-up question".to_string()],  // 设置队列消息
        Vec::new()  // 无待处理 steer
    );

    let width = 48;
    let height = pane.desired_height(width);
    let area = Rect::new(0, 0, width, height);
    assert_snapshot!("status_and_queued_messages_snapshot", 
        render_snapshot(&pane, area));
}
```

### 渲染输出分析
```
• Working (0s • esc to interrupt)               <- 状态指示器（第1行）
                                                <- 间距行（第2行）
• Queued follow-up messages                      <- 队列标题（第3行）
  ↳ Queued follow-up question                    <- 队列消息（第4行）
    ⌥ + ↑ edit last queued message               <- 编辑提示（第5行）
                                                <- 间距行（第6行）
› Ask Codex to do anything                       <- 编辑器（第7行）
                                                <- 间距行（第8行）
  ? for shortcuts            100% context left   <- 底部提示（第9行）
```

### 布局结构
```
BottomPane (FlexRenderable)
├── 状态指示器区域 (StatusIndicatorWidget)
│   └── "• Working (0s • esc to interrupt)"
├── 间距行（条件插入）
├── 待处理输入预览 (PendingInputPreview)
│   ├── "• Queued follow-up messages"
│   ├── "  ↳ Queued follow-up question"
│   └── "    ⌥ + ↑ edit last queued message"
├── 间距行（条件插入）
└── 编辑器区域 (ChatComposer)
    ├── 编辑器输入框
    └── 底部提示栏
```

## 关键代码路径与文件引用

### 主要文件
- `codex-rs/tui/src/bottom_pane/mod.rs` - BottomPane 实现

### 间距插入逻辑（lines 1146-1168）
```rust
let has_pending_thread_approvals = !self.pending_thread_approvals.is_empty();
let has_pending_input = !self.pending_input_preview.queued_messages.is_empty()
    || !self.pending_input_preview.pending_steers.is_empty();
let has_status_or_footer = self.status.is_some() || !self.unified_exec_footer.is_empty();
let has_inline_previews = has_pending_thread_approvals || has_pending_input;

// 条件1：有内联预览且有状态/页脚时插入间距
if has_inline_previews && has_status_or_footer {
    flex.push(/*flex*/ 0, RenderableItem::Owned("".into()));
}

flex.push(/*flex*/ 1, RenderableItem::Borrowed(&self.pending_thread_approvals));

if has_pending_thread_approvals && has_pending_input {
    flex.push(/*flex*/ 0, RenderableItem::Owned("".into()));
}

flex.push(/*flex*/ 1, RenderableItem::Borrowed(&self.pending_input_preview));

// 条件3：无内联预览但有状态/页脚时插入间距
if !has_inline_previews && has_status_or_footer {
    flex.push(/*flex*/ 0, RenderableItem::Owned("".into()));
}
```

### 依赖模块
- `crate::bottom_pane::pending_input_preview::PendingInputPreview` - 队列消息预览
- `crate::status_indicator_widget::StatusIndicatorWidget` - 状态指示器
- `crate::render::renderable::FlexRenderable` - 弹性布局

## 依赖与外部交互

### 数据流
```
App (后端)
  │
  ├── set_task_running(true) ──► BottomPane
  │                               └── 创建/显示 StatusIndicatorWidget
  │
  └── set_pending_input_preview() ──► BottomPane
                                      └── 更新 PendingInputPreview
                                            └── request_redraw()
```

### 组件关系
| 组件 | 依赖 | 被依赖 |
|------|------|--------|
| StatusIndicatorWidget | FrameRequester (动画) | BottomPane |
| PendingInputPreview | KeyBinding (编辑提示) | BottomPane |
| ChatComposer | AppEventSender | BottomPane |

## 风险边界与改进建议

### 潜在风险

1. **垂直空间不足**
   - **风险**：在小高度终端中，多个组件堆叠可能导致编辑器空间不足
   - **边界**：当前测试使用 48 宽度，高度自动计算
   - **建议**：添加最小高度测试，验证极端情况下的布局

2. **间距重复**
   - **风险**：多个条件可能同时触发，导致过多间距行
   - **边界**：当前逻辑中条件互斥或有优先级
   - **建议**：审查条件组合，确保间距不会累积

3. **队列消息截断**
   - **风险**：长队列消息可能在有限宽度内被截断
   - **边界**：当前测试使用短消息
   - **建议**：添加长消息换行/截断测试

### 改进建议

1. **动态优先级**
   - 当空间极度受限时，考虑隐藏次要信息（如编辑提示）
   - 实现折叠/展开机制

2. **视觉优化**
   - 考虑使用不同颜色区分状态指示器和队列消息
   - 添加分隔线替代空行间距

3. **测试覆盖**
   ```rust
   // 建议添加的测试
   #[test]
   fn status_and_many_queued_messages() {
       // 测试多条队列消息的渲染
   }
   
   #[test]
   fn status_and_queued_messages_narrow() {
       // 测试窄宽度下的布局
   }
   
   #[test]
   fn status_and_queued_messages_with_steers() {
       // 测试同时有 steer 和队列消息
   }
   ```

4. **可访问性**
   - 确保屏幕阅读器能够正确朗读状态变化和队列消息
   - 添加 ARIA 标签等辅助功能属性
