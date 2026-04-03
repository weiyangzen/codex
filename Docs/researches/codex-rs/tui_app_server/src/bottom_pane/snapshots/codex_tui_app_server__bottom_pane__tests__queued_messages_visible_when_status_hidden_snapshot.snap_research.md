# queued_messages_visible_when_status_hidden_snapshot 研究文档

## 场景与职责

本快照测试展示了 `BottomPane` 在**状态指示器隐藏但排队消息可见**时的渲染行为。验证当 `hide_status_indicator()` 被调用后，排队消息仍然能够正确显示，而不受状态指示器隐藏的影响。

**典型使用场景**：
- 任务完成后状态指示器自动隐藏
- 用户手动隐藏状态指示器但保留排队消息
- 验证状态隐藏后底部面板的正确布局

## 功能点目的

该测试验证以下核心功能：

1. **状态隐藏独立性**：隐藏状态指示器不影响排队消息的显示
2. **布局调整**：状态隐藏后，排队消息和 Composer 正确填充空间
3. **视觉连续性**：用户仍然可以看到和操作排队消息
4. **底部面板完整性**：确保所有可见元素正确渲染

**渲染输出特征**：
```
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

    pane.set_task_running(true);
    pane.set_pending_input_preview(vec!["Queued follow-up question".to_string()], Vec::new());
    pane.hide_status_indicator();  // 关键：隐藏状态指示器

    let width = 48;
    let height = pane.desired_height(width);
    let area = Rect::new(0, 0, width, height);
    assert_snapshot!("queued_messages_visible_when_status_hidden_snapshot", 
                     render_snapshot(&pane, area));
}
```

### 布局逻辑
```rust
fn as_renderable(&'_ self) -> RenderableItem<'_> {
    let mut flex = FlexRenderable::new();
    
    // 状态指示器（已隐藏，不添加）
    if let Some(status) = &self.status {
        flex.push(/*flex*/ 0, RenderableItem::Borrowed(status));
    }
    
    // 排队消息预览（仍然显示）
    flex.push(
        /*flex*/ 1,
        RenderableItem::Borrowed(&self.pending_input_preview),
    );
    
    // Composer
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
| `queued_messages_visible_when_status_hidden_snapshot` (test) | 1556-1581 | 本测试用例 |
| `hide_status_indicator()` | 743-747 | 隐藏状态指示器 |
| `set_pending_input_preview()` | 815-823 | 设置排队消息预览 |
| `as_renderable()` | 1123-1167 | 主渲染逻辑 |

### 状态管理
```rust
pub(crate) fn hide_status_indicator(&mut self) {
    if self.status.take().is_some() {
        self.request_redraw();
    }
}
```

## 依赖与外部交互

### 依赖模块
- `crate::bottom_pane::pending_input_preview::PendingInputPreview` - 排队消息预览
- `crate::status_indicator_widget::StatusIndicatorWidget` - 状态指示器
- `crate::render::renderable::FlexRenderable` - 弹性布局

### 布局组件
| 组件 | 可见性 | 说明 |
|------|--------|------|
| StatusIndicatorWidget | 隐藏 | 被 `hide_status_indicator()` 移除 |
| PendingInputPreview | 可见 | 显示排队消息 |
| ChatComposer | 可见 | 输入框 |

## 风险、边界与改进建议

### 当前边界情况
1. **单一消息**：测试只使用一条排队消息
2. **无 Pending Steers**：`pending_steers` 参数为空
3. **固定尺寸**：48x? 的固定测试尺寸

### 潜在风险
1. **高度计算**：状态隐藏后高度计算需要重新评估
2. **布局跳跃**：状态显示/隐藏可能导致布局突然变化
3. **消息截断**：如果空间不足，排队消息可能被截断

### 改进建议
1. **动画过渡**：状态指示器隐藏/显示时添加淡入淡出动画
2. **高度保持**：可选保持高度避免布局跳跃
3. **消息优先级**：当空间不足时，优先显示排队消息而非其他元素
4. **视觉提示**：状态隐藏后，添加提示说明为什么状态不可见
5. **自动恢复**：状态隐藏后，在特定条件下自动恢复显示
