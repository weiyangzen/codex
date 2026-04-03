# status_only_snapshot 研究文档

## 场景与职责

本快照测试展示了 `BottomPane` 在**仅显示状态指示器**时的渲染行为。验证当任务正在运行但没有排队消息时，底部面板的正确布局和渲染。

**典型使用场景**：
- 后台任务执行期间用户没有排队任何消息
- 验证最小化状态下的底部面板渲染
- 作为其他复杂布局的基准参考

## 功能点目的

该测试验证以下核心功能：

1. **状态独占显示**：仅状态指示器可见时正确渲染
2. **布局简洁性**：没有多余的空行或占位符
3. **Composer 可见性**：输入框仍然可用
4. **底部状态栏**：上下文信息正确显示

**渲染输出特征**：
```
• Working (0s • esc to interrupt)                <- 状态指示器
                                                 <- 空行
                                                 <- 空行（flex 空间）
› Ask Codex to do anything                       <- Composer 占位符
                                                 <- 空行
  ? for shortcuts            100% context left   <- 底部状态栏
```

## 具体技术实现

### 测试设置
```rust
#[test]
fn status_only_snapshot() {
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

    pane.set_task_running(true);  // 启动任务，显示状态指示器

    let width = 48;
    let height = pane.desired_height(width);
    let area = Rect::new(0, 0, width, height);
    assert_snapshot!("status_only_snapshot", render_snapshot(&pane, area));
}
```

### 布局逻辑（状态独占）
```rust
fn as_renderable(&'_ self) -> RenderableItem<'_> {
    let mut flex = FlexRenderable::new();
    
    // 状态指示器
    if let Some(status) = &self.status {
        flex.push(/*flex*/ 0, RenderableItem::Borrowed(status));
    }
    
    // 检查是否需要空行分隔
    let has_pending_thread_approvals = !self.pending_thread_approvals.is_empty();
    let has_pending_input = !self.pending_input_preview.queued_messages.is_empty()
        || !self.pending_input_preview.pending_steers.is_empty();
    let has_status_or_footer = self.status.is_some() || !self.unified_exec_footer.is_empty();
    let has_inline_previews = has_pending_thread_approvals || has_pending_input;
    
    // 本测试中 has_inline_previews = false，has_status_or_footer = true
    // 所以不会添加空行分隔
    if has_inline_previews && has_status_or_footer {
        flex.push(/*flex*/ 0, RenderableItem::Owned("".into()));
    }
    
    // 排队消息预览（本测试中为空，不添加）
    flex.push(
        /*flex*/ 1,
        RenderableItem::Borrowed(&self.pending_input_preview),
    );
    
    // Composer
    let mut flex2 = FlexRenderable::new();
    flex2.push(/*flex*/ 1, RenderableItem::Owned(flex.into()));
    flex2.push(/*flex*/ 0, RenderableItem::Borrowed(&self.composer));
}
```

## 关键代码路径与文件引用

### 主要文件
- `codex-rs/tui_app_server/src/bottom_pane/mod.rs` - BottomPane 组件实现

### 关键函数
| 函数 | 行号 | 职责 |
|------|------|------|
| `status_only_snapshot` (test) | 1471-1491 | 本测试用例 |
| `set_task_running()` | 716-740 | 启动任务，创建状态指示器 |
| `as_renderable()` | 1123-1167 | 主渲染逻辑 |

### 状态指示器创建
```rust
if running && !was_running {
    if self.status.is_none() {
        self.status = Some(StatusIndicatorWidget::new(
            self.app_event_tx.clone(),
            self.frame_requester.clone(),
            self.animations_enabled,
        ));
    }
    if let Some(status) = self.status.as_mut() {
        status.set_interrupt_hint_visible(/*visible*/ true);
    }
    self.sync_status_inline_message();
    self.request_redraw();
}
```

## 依赖与外部交互

### 依赖模块
- `crate::status_indicator_widget::StatusIndicatorWidget` - 状态指示器
- `crate::bottom_pane::chat_composer::ChatComposer` - 聊天输入框
- `crate::render::renderable::FlexRenderable` - 弹性布局

### 状态指示器功能
- 显示当前任务状态（"Working"）
- 显示运行时间（"0s"）
- 显示中断提示（"esc to interrupt"）
- 支持动画效果（如果启用）

## 风险、边界与改进建议

### 当前边界情况
1. **初始状态**：任务刚开始，运行时间为 0 秒
2. **无排队消息**：`pending_input_preview` 为空
3. **固定宽度**：48 字符宽度

### 潜在风险
1. **状态闪烁**：任务快速启动/停止可能导致状态指示器闪烁
2. **高度变化**：状态显示/隐藏导致底部面板高度变化
3. **中断冲突**：Esc 键可能与其他功能冲突

### 改进建议
1. **最小显示时间**：状态指示器至少显示 N 秒，避免闪烁
2. **平滑过渡**：状态显示/隐藏时添加淡入淡出效果
3. **高度保持**：可选保持高度稳定，避免布局跳跃
4. **状态历史**：显示最近的状态变化历史
5. **进度指示**：对于长时间任务，显示进度条或百分比
6. **取消确认**：中断任务前添加确认提示，防止误操作
