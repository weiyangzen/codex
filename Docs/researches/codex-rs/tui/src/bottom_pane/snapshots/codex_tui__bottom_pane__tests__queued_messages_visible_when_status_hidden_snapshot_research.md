# BottomPane - Queued Messages Visible When Status Hidden Research Document

## 场景与职责

此快照测试验证当状态指示器被隐藏时，队列中的消息预览仍然可见。这是 `BottomPane` 组件的一个重要布局行为，确保用户在任务运行期间添加的后续消息（队列）始终可见，即使状态指示器被隐藏。

### 核心场景
- **任务运行中**：`set_task_running(true)` 激活状态指示器
- **队列消息存在**：`set_pending_input_preview()` 设置待处理的消息队列
- **状态指示器隐藏**：`hide_status_indicator()` 手动隐藏状态指示器
- **预期行为**：队列消息预览仍然显示，不受状态指示器隐藏的影响

## 功能点目的

### 1. 队列消息预览
- **目的**：显示用户已排队但尚未发送的后续消息
- **使用场景**：当 AI 正在处理当前任务时，用户可以预先输入下一个问题并排队
- **视觉标识**：使用 `• Queued follow-up messages` 标题和 `↳` 前缀显示具体消息

### 2. 状态指示器控制
- **目的**：允许在特定情况下隐藏状态指示器（如模态框显示时）
- **实现**：`hide_status_indicator()` 方法清除 `self.status`
- **独立性**：状态指示器的显示状态不应影响其他 UI 组件

### 3. 布局隔离
- **目的**：确保不同功能区域（状态、队列、编辑器）独立渲染
- **实现**：使用 `FlexRenderable` 组合多个子组件

## 具体技术实现

### 测试代码分析
```rust
#[test]
fn queued_messages_visible_when_status_hidden_snapshot() {
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
        vec!["Queued follow-up question".to_string()],  // 队列消息
        Vec::new()
    );
    pane.hide_status_indicator();  // 隐藏状态指示器

    let width = 48;
    let height = pane.desired_height(width);
    let area = Rect::new(0, 0, width, height);
    assert_snapshot!("queued_messages_visible_when_status_hidden_snapshot", 
        render_snapshot(&pane, area));
}
```

### 渲染输出分析
```
• Queued follow-up messages                      <- 队列消息标题
  ↳ Queued follow-up question                    <- 具体队列消息
    ⌥ + ↑ edit last queued message               <- 编辑提示
                                                <- 空行（间距）
› Ask Codex to do anything                       <- 编辑器输入框
                                                <- 空行（间距）
  ? for shortcuts            100% context left   <- 底部提示栏
```

### 关键观察
1. **无状态指示器行**：输出中没有 `• Working` 或类似的状态行
2. **队列消息完整显示**：包括标题、消息内容和编辑提示
3. **编辑器正常显示**：输入框和底部提示栏正常工作
4. **布局紧凑**：没有为状态指示器保留的空白行

## 关键代码路径与文件引用

### 主要文件
- `codex-rs/tui/src/bottom_pane/mod.rs` - BottomPane 实现

### 相关方法

#### `hide_status_indicator()`（line 744-748）
```rust
pub(crate) fn hide_status_indicator(&mut self) {
    if self.status.take().is_some() {
        self.request_redraw();
    }
}
```
- 使用 `Option::take()` 移除状态指示器
- 仅在确实移除时请求重绘

#### `as_renderable()`（lines 1130-1174）
```rust
fn as_renderable(&'_ self) -> RenderableItem<'_> {
    if let Some(view) = self.active_view() {
        RenderableItem::Borrowed(view)
    } else {
        let mut flex = FlexRenderable::new();
        if let Some(status) = &self.status {
            flex.push(/*flex*/ 0, RenderableItem::Borrowed(status));
        }
        // 避免在状态行可见时重复显示 unified_exec 摘要
        if self.status.is_none() && !self.unified_exec_footer.is_empty() {
            flex.push(/*flex*/ 0, RenderableItem::Borrowed(&self.unified_exec_footer));
        }
        // ... 队列消息和编辑器渲染
    }
}
```

#### `set_pending_input_preview()`（lines 815-824）
```rust
pub(crate) fn set_pending_input_preview(
    &mut self,
    queued: Vec<String>,
    pending_steers: Vec<String>,
) {
    self.pending_input_preview.pending_steers = pending_steers;
    self.pending_input_preview.queued_messages = queued;
    self.request_redraw();
}
```

### 依赖模块
- `crate::bottom_pane::pending_input_preview::PendingInputPreview` - 队列消息预览组件
- `crate::render::renderable::FlexRenderable` - 弹性布局容器

## 依赖与外部交互

### 内部组件依赖
| 组件 | 用途 |
|------|------|
| `PendingInputPreview` | 渲染队列消息预览 |
| `ChatComposer` | 编辑器输入框 |
| `StatusIndicatorWidget` | 状态指示器（可选） |
| `FlexRenderable` | 布局管理 |

### 状态交互
| 状态 | 影响 |
|------|------|
| `status: None` | 不渲染状态指示器 |
| `queued_messages: non-empty` | 渲染队列消息预览 |
| `is_task_running: true` | 内部状态，但不影响此测试的布局 |

## 风险边界与改进建议

### 潜在风险

1. **布局耦合**
   - **风险**：如果 `as_renderable()` 逻辑变更，可能意外影响队列消息的显示
   - **边界**：当前测试捕获了正确的行为快照
   - **建议**：确保任何布局重构都运行此测试验证

2. **高度计算**
   - **风险**：`desired_height()` 可能在状态隐藏时计算不正确的高度
   - **边界**：测试验证了渲染输出，但未直接验证高度计算
   - **建议**：添加显式的高度断言测试

3. **空状态处理**
   - **风险**：当队列为空时，`PendingInputPreview` 可能仍占用空间
   - **边界**：需要验证空队列时的布局行为
   - **建议**：添加空队列快照测试

### 改进建议

1. **测试增强**
   - 添加高度计算的显式断言
   - 测试多种宽度下的布局行为
   - 测试长队列消息的截断行为

2. **文档完善**
   - 在代码中添加注释说明状态指示器和队列消息的独立性
   - 解释为什么 `hide_status_indicator` 不应影响队列显示

3. **功能扩展**
   - 考虑添加队列消息的折叠/展开功能
   - 支持队列消息的重新排序
