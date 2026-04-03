# ChatWidget 小尺寸终端运行状态测试 (高度1)

## 场景与职责

该 snapshot 测试验证 `ChatWidget` 在极紧凑终端高度（仅1行）且任务运行状态下的渲染表现。这是测试系列中最极端的情况，验证 UI 在几乎无可用空间时的降级策略。

### 测试目的
- 验证单高度终端下的最小可用 UI
- 确保任务运行状态在极限空间下仍可被感知
- 捕获高度为1时运行状态的视觉快照

### 业务场景
- 用户在分割终端（tmux/screen）中运行 Codex
- 嵌入式设备或远程 SSH 会话中的受限终端
- 用户主动压缩终端以查看其他内容

## 功能点目的

### 1. 极限空间下的状态优先级
当高度仅为1行时，`ChatWidget` 必须决定：
- 显示状态指示器（如 "Working"）还是输入提示
- 如何传达任务正在进行的信息
- 是否完全隐藏输入功能

### 2. 任务运行状态可视化
即使在单高度模式下，也需要：
- 指示有任务正在运行
- 提供中断提示（如 `esc to interrupt`）
- 保留最基本的用户交互能力

## 具体技术实现

### 测试代码位置
```rust
// codex-rs/tui_app_server/src/chatwidget/tests.rs
#[tokio::test]
async fn ui_snapshots_small_heights_task_running() {
    use ratatui::Terminal;
    use ratatui::backend::TestBackend;
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;
    // 激活状态行 - 模拟任务开始
    chat.handle_codex_event(Event {
        id: "task-1".into(),
        msg: EventMsg::TurnStarted(TurnStartedEvent {
            turn_id: "turn-1".to_string(),
            model_context_window: None,
            collaboration_mode_kind: ModeKind::Default,
        }),
    });
    chat.handle_codex_event(Event {
        id: "task-1".into(),
        msg: EventMsg::AgentReasoningDelta(AgentReasoningDeltaEvent {
            delta: "**Thinking**".into(),
        }),
    });
    for h in [1u16, 2, 3] {
        let name = format!("chat_small_running_h{h}");
        let mut terminal = Terminal::new(TestBackend::new(40, h)).expect("create terminal");
        terminal
            .draw(|f| chat.render(f.area(), f.buffer_mut()))
            .expect("draw chat running");
        assert_snapshot!(name, terminal.backend());
    }
}
```

### 测试设置详解
1. **创建 ChatWidget** - 使用 `make_chatwidget_manual(None)` 初始化
2. **模拟任务开始** - 发送 `TurnStartedEvent`
3. **添加推理内容** - 通过 `AgentReasoningDeltaEvent` 设置 "Thinking" 状态
4. **渲染并捕获** - 对高度 1, 2, 3 分别创建快照

### Snapshot 内容
```
"                                        "
```

**分析**：
- 单高度下显示为空行（40个空格）
- 可能原因：
  1. 渲染逻辑在高度不足时静默跳过
  2. 状态行被隐藏，输入框被隐藏
  3. 实际内容被渲染但 snapshot 未捕获（如颜色代码）

## 关键代码路径与文件引用

### 状态管理
```rust
// codex-rs/tui_app_server/src/chatwidget.rs
struct ChatWidget {
    agent_turn_running: bool,  // 标记任务是否运行中
    current_status: StatusIndicatorState,  // 当前状态指示
    // ...
}
```

### 状态指示器渲染
- `codex-rs/tui_app_server/src/status_indicator_widget.rs`
  - 处理 "Working" 状态的显示
  - 管理 spinner 动画（在测试后端中可能不可见）

### 底部面板任务状态
```rust
// codex-rs/tui_app_server/src/bottom_pane/mod.rs
impl BottomPane {
    pub(crate) fn set_task_running(&mut self, running: bool) {
        self.task_running = running;
        // 更新 UI 状态...
    }
    
    pub(crate) fn is_task_running(&self) -> bool {
        self.task_running
    }
}
```

### 事件处理流程
```
TurnStartedEvent → handle_codex_event() → agent_turn_running = true
                                               ↓
AgentReasoningDeltaEvent → 更新 reasoning_buffer → 设置状态文本
                                               ↓
render() → 根据高度决定显示内容
```

## 依赖与外部交互

### 协议事件依赖
| 事件类型 | 来源 | 用途 |
|----------|------|------|
| `TurnStartedEvent` | codex-protocol | 标记任务开始 |
| `AgentReasoningDeltaEvent` | codex-protocol | 流式推理内容 |

### 内部状态依赖
- `SessionHeader` - 会话头部信息
- `StatusIndicatorState` - 状态指示器状态
- `BottomPane.task_running` - 底部面板的任务状态

### 测试基础设施
```rust
// 测试辅助函数
async fn make_chatwidget_manual(
    model_override: Option<&str>,
) -> (ChatWidget, UnboundedReceiver<AppEvent>, UnboundedReceiver<Op>)
```

## 风险、边界与改进建议

### 关键风险

1. **用户体验降级**
   - 高度为1时用户无法看到任何有意义的信息
   - 无法区分"空闲"和"运行中"状态
   - 用户可能误以为程序卡死

2. **交互能力丧失**
   - 无法显示输入框意味着无法接收新输入
   - 中断快捷键（Ctrl+C/Esc）的提示不可见

3. **测试有效性**
   - 当前 snapshot 为空行，难以检测回归
   - 无法区分"预期行为"和"渲染失败"

### 改进建议

1. **单高度专用渲染**
   ```rust
   fn render_single_line(&self, buf: &mut Buffer) {
       // 优先级：状态 > 输入提示 > 空行
       let content = if self.agent_turn_running {
           "⚡ Working... (Ctrl+C to cancel)"
       } else {
           "› Ready for input"
       };
       // 截断或滚动显示
   }
   ```

2. **增强测试断言**
   ```rust
   // 除了 snapshot，添加功能性断言
   assert!(chat.bottom_pane.is_task_running());
   assert!(!chat.queued_user_messages.is_empty() || /* 其他条件 */);
   ```

3. **最小高度检查**
   ```rust
   const MIN_RECOMMENDED_HEIGHT: u16 = 10;
   
   fn render(&self, area: Rect, buf: &mut Buffer) {
       if area.height < MIN_RECOMMENDED_HEIGHT {
           self.render_warning(area, buf);
       }
       // ...
   }
   ```

4. **添加文档说明**
   - 在 README 中声明最小支持终端尺寸
   - 建议用户保持至少 10 行高度以获得最佳体验

### 相关测试矩阵

| 测试名称 | 高度 | 状态 | 预期行为 |
|----------|------|------|----------|
| chat_small_idle_h1 | 1 | 空闲 | 显示输入提示或空行 |
| chat_small_idle_h2 | 2 | 空闲 | 显示输入框 + 帮助 |
| chat_small_idle_h3 | 3 | 空闲 | 完整底部面板 |
| chat_small_running_h1 | 1 | 运行 | **本测试** - 显示状态 |
| chat_small_running_h2 | 2 | 运行 | 状态 + 压缩输入 |
| chat_small_running_h3 | 3 | 运行 | 状态 + 输入框 |

---

*文档生成时间：2026-03-23*
*对应 snapshot：codex_tui_app_server__chatwidget__tests__chat_small_running_h1.snap*
