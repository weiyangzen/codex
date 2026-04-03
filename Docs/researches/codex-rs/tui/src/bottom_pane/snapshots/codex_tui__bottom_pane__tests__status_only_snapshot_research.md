# BottomPane - Status Only Snapshot Research Document

## 场景与职责

此快照测试验证当任务正在运行且没有其他辅助信息（如队列消息、unified_exec 摘要等）时，BottomPane 仅显示状态指示器和编辑器的基本布局。这是 `BottomPane` 最简化的有效状态，用于验证核心组件的独立渲染能力。

### 核心场景
- **任务运行中**：`set_task_running(true)` 激活状态指示器
- **无队列消息**：`set_pending_input_preview()` 未被调用或传入空列表
- **无其他预览**：没有待处理线程审批或 unified_exec 进程
- **预期行为**：简洁的布局，仅包含状态指示器和编辑器

## 功能点目的

### 1. 最小化界面验证
- **目的**：验证核心组件在没有辅助信息时的正确渲染
- **价值**：确保基础功能不受可选组件影响
- **隔离性**：测试单一职责，便于问题定位

### 2. 状态指示器独立渲染
- **目的**：确认状态指示器可以独立存在并正确显示
- **内容**：包括工作状态、运行时间和中断提示
- **交互**：显示 `esc to interrupt` 提示用户可中断任务

### 3. 编辑器基础状态
- **目的**：验证编辑器在任务运行时的默认状态
- **占位文本**：显示提示用户输入的占位符
- **上下文信息**：显示剩余上下文百分比

## 具体技术实现

### 测试代码分析
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

    pane.set_task_running(true);  // 仅激活任务状态，不添加其他预览

    let width = 48;
    let height = pane.desired_height(width);
    let area = Rect::new(0, 0, width, height);
    assert_snapshot!("status_only_snapshot", render_snapshot(&pane, area));
}
```

### 渲染输出分析
```
• Working (0s • esc to interrupt)               <- 状态指示器（第1行）
                                                <- 空行（第2行）
                                                <- 空行（第3行）
› Ask Codex to do anything                       <- 编辑器输入框（第4行）
                                                <- 空行（第5行）
  ? for shortcuts            100% context left   <- 底部提示栏（第6行）
```

### 布局结构分析
```
BottomPane (总高度: 6行)
├── 状态指示器 (StatusIndicatorWidget)
│   ├── 标题: "• Working"
│   ├── 计时器: "(0s"
│   └── 中断提示: "• esc to interrupt)"
├── 间距行 (条件插入)
├── 编辑器区域 (ChatComposer)
│   ├── 顶部内边距
│   ├── 输入框: "› Ask Codex to do anything"
│   ├── 底部内边距
│   └── 底部提示栏: "? for shortcuts ... 100% context left"
```

### 与 "status_and_composer_fill_height" 测试的对比
| 测试 | 宽度 | 特殊条件 | 主要验证点 |
|------|------|----------|-----------|
| status_only_snapshot | 48 | 无 | 标准布局外观 |
| status_and_composer_fill_height | 30 | height == desired_height | 无底部填充 |

## 关键代码路径与文件引用

### 主要文件
- `codex-rs/tui/src/bottom_pane/mod.rs` - BottomPane 实现

### 状态指示器创建（lines 722-736）
```rust
pub fn set_task_running(&mut self, running: bool) {
    let was_running = self.is_task_running;
    self.is_task_running = running;
    self.composer.set_task_running(running);

    if running {
        if !was_running {
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
    } else {
        self.hide_status_indicator();
    }
}
```

### 布局条件判断（lines 1146-1168）
```rust
let has_pending_thread_approvals = !self.pending_thread_approvals.is_empty();  // false
let has_pending_input = !self.pending_input_preview.queued_messages.is_empty()  // false
    || !self.pending_input_preview.pending_steers.is_empty();                   // false
let has_status_or_footer = self.status.is_some() || !self.unified_exec_footer.is_empty();  // true
let has_inline_previews = has_pending_thread_approvals || has_pending_input;  // false

// 条件1: has_inline_previews && has_status_or_footer = false && true = false (不插入)
if has_inline_previews && has_status_or_footer {
    flex.push(/*flex*/ 0, RenderableItem::Owned("".into()));
}

// 条件2: has_pending_thread_approvals && has_pending_input = false (不插入)
if has_pending_thread_approvals && has_pending_input {
    flex.push(/*flex*/ 0, RenderableItem::Owned("".into()));
}

// 条件3: !has_inline_previews && has_status_or_footer = true && true = true (插入间距)
if !has_inline_previews && has_status_or_footer {
    flex.push(/*flex*/ 0, RenderableItem::Owned("".into()));
}
```

### 依赖模块
- `crate::status_indicator_widget::StatusIndicatorWidget` - 状态指示器
- `crate::bottom_pane::chat_composer::ChatComposer` - 编辑器
- `crate::render::renderable::FlexRenderable` - 弹性布局

## 依赖与外部交互

### 状态流
```
set_task_running(true)
  │
  ├──► is_task_running = true
  │
  ├──► composer.set_task_running(true)
  │
  ├──► status = Some(StatusIndicatorWidget::new(...))
  │    └── 启动动画计时器
  │
  ├──► status.set_interrupt_hint_visible(true)
  │    └── 显示 "esc to interrupt"
  │
  ├──► sync_status_inline_message()
  │    └── 同步 unified_exec 摘要（如有）
  │
  └──► request_redraw()
       └── 触发重新渲染
```

### 渲染触发
| 事件 | 来源 | 处理 |
|------|------|------|
| 动画帧 | StatusIndicatorWidget | 更新计时器显示 |
| 重绘请求 | set_task_running | 完整重新布局 |
| 尺寸变化 | 终端调整 | 重新计算布局 |

## 风险边界与改进建议

### 潜在风险

1. **计时器精度**
   - **风险**：状态指示器显示 `(0s` 是动画初始值
   - **边界**：实际显示时间取决于渲染时机
   - **影响**：快照测试可能捕获非确定性时间值
   - **缓解**：测试中使用了动画模拟或固定时间

2. **间距逻辑复杂性**
   - **风险**：`!has_inline_previews && has_status_or_footer` 条件导致插入间距
   - **边界**：即使无内联预览，状态指示器和编辑器之间仍有间距
   - **建议**：审查此间距是否必要，或应可配置

3. **上下文百分比硬编码**
   - **风险**：`100% context left` 是默认值，未连接实际上下文数据
   - **边界**：测试中未调用 `set_context_window()`
   - **建议**：确保测试覆盖不同上下文状态

### 改进建议

1. **测试多样化**
   ```rust
   // 建议添加的测试
   #[test]
   fn status_only_with_context_usage() {
       // 测试有上下文使用数据时的显示
       pane.set_context_window(Some(50), Some(1000));
   }
   
   #[test]
   fn status_only_running_for_a_while() {
       // 测试运行一段时间后的计时器显示
       // 需要模拟时间流逝
   }
   ```

2. **间距优化**
   - 评估状态指示器和编辑器之间的间距是否必要
   - 考虑提供紧凑模式选项

3. **状态指示器增强**
   - 添加更多状态信息（如当前操作类型）
   - 支持自定义状态文本

4. **文档完善**
   - 在代码中注释间距插入逻辑的原因
   - 说明各条件的业务含义
