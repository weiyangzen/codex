# ChatWidget 小尺寸终端运行状态测试 (高度2)

## 场景与职责

该 snapshot 测试验证 `ChatWidget` 在紧凑终端高度（2行）且任务运行状态下的渲染表现。相比高度1的极端情况，高度2提供了稍多的空间来展示状态信息和用户界面元素。

### 测试目的
- 验证双高度终端下的 UI 布局策略
- 确保状态指示器和输入区域能够共存
- 捕获高度为2时运行状态的视觉快照

### 业务场景
- 使用 tmux 分割窗口时，每个窗格可能只有2-3行
- 在 IDE 集成终端的底部面板中运行 Codex
- 远程服务器上的低分辨率终端会话

## 功能点目的

### 1. 双行空间的分配策略
在2行高度下，`ChatWidget` 需要平衡：
- 第1行：状态指示器（"Working" + 计时器 + 中断提示）
- 第2行：输入框提示符或消息队列预览

### 2. 任务状态的清晰传达
即使在紧凑空间，也要确保：
- 用户知道有任务正在执行
- 了解已运行时间
- 知道如何中断任务

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
    
    // 添加推理内容，设置状态文本为 "Thinking"
    chat.handle_codex_event(Event {
        id: "task-1".into(),
        msg: EventMsg::AgentReasoningDelta(AgentReasoningDeltaEvent {
            delta: "**Thinking**".into(),
        }),
    });
    
    // 测试高度 1, 2, 3
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

### Snapshot 内容
```
"                                        "
"                                        "
```

**分析**：
- 两行均显示为空格
- 可能原因分析：
  1. `TestBackend` 的渲染输出与 VT100 后端不同
  2. 状态行和输入框在高度为2时都被隐藏
  3. 渲染逻辑可能优先保证功能性而非视觉输出

### 状态指示器工作原理
```rust
// codex-rs/tui_app_server/src/chatwidget.rs
#[derive(Clone, Debug, PartialEq, Eq)]
struct StatusIndicatorState {
    header: String,           // 如 "Working"
    details: Option<String>, // 详细信息
    details_max_lines: usize,
}

impl StatusIndicatorState {
    fn working() -> Self {
        Self {
            header: String::from("Working"),
            details: None,
            details_max_lines: STATUS_DETAILS_DEFAULT_MAX_LINES,
        }
    }
}
```

## 关键代码路径与文件引用

### 渲染决策逻辑
```rust
// codex-rs/tui_app_server/src/chatwidget.rs
pub(crate) fn render(&self, area: Rect, buf: &mut Buffer) {
    // 高度分配逻辑
    let status_height = if self.should_show_status() { 1 } else { 0 };
    let composer_height = 1; // 最小输入框高度
    
    if area.height < status_height + composer_height {
        // 空间不足时的降级策略
        self.render_minimal(area, buf);
    } else {
        // 正常渲染
        self.render_full(area, buf);
    }
}
```

### 底部面板高度管理
- `codex-rs/tui_app_server/src/bottom_pane/mod.rs`
  - `desired_height()` - 计算底部面板所需高度
  - `render()` - 根据可用空间调整布局

### 推理内容处理
```rust
// 处理 AgentReasoningDeltaEvent
fn on_agent_reasoning_delta(&mut self, delta: String) {
    self.reasoning_buffer.push_str(&delta);
    // 更新状态指示器文本
    self.current_status = StatusIndicatorState {
        header: self.reasoning_buffer.clone(),
        details: None,
        details_max_lines: 1,
    };
}
```

## 依赖与外部交互

### 核心依赖模块
| 模块 | 路径 | 职责 |
|------|------|------|
| TestBackend | ratatui::backend | 内存中的测试终端 |
| TurnStartedEvent | codex-protocol | 任务生命周期标记 |
| AgentReasoningDeltaEvent | codex-protocol | 流式推理内容 |
| StatusIndicatorState | chatwidget.rs | 状态指示器状态管理 |

### 事件流
```
用户输入 → TurnStartedEvent → agent_turn_running = true
                                    ↓
AgentReasoningDeltaEvent → 更新 reasoning_buffer
                                    ↓
                              更新 current_status
                                    ↓
                               render() 调用
                                    ↓
                         根据 area.height 决定渲染策略
```

### 配置影响
- `config.animations` - 控制 spinner 动画（测试中通常为 false）
- `config.features` - 功能开关可能影响可用 UI 元素

## 风险、边界与改进建议

### 当前限制

1. **视觉反馈不足**
   - 高度为2时 snapshot 显示为空行
   - 用户无法从视觉上确认任务状态
   - 难以区分"程序正常"和"程序挂起"

2. **功能与空间的权衡**
   - 状态行 vs 输入框的优先级不明确
   - 消息队列预览完全不可见
   - 帮助提示（如 `esc to interrupt`）被截断

3. **测试覆盖缺口**
   - 仅验证渲染不 panic，不验证内容正确性
   - 缺少功能性断言
   - 未测试键盘交互在紧凑高度下的行为

### 改进建议

1. **优化双行渲染策略**
   ```rust
   fn render_two_lines(&self, area: Rect, buf: &mut Buffer) {
       // 第1行：紧凑状态指示器
       let status_line = format!(
           "● {} ({}s)",
           self.current_status.header,
           self.elapsed_secs()
       );
       self.render_status_line(area.x, area.y, buf, &status_line);
       
       // 第2行：简化输入提示
       let input_hint = if self.queued_user_messages.is_empty() {
           "› type here..."
       } else {
           &format!("↳ {} queued", self.queued_user_messages.len())
       };
       self.render_input_line(area.x, area.y + 1, buf, input_hint);
   }
   ```

2. **增强测试验证**
   ```rust
   #[tokio::test]
   async fn ui_snapshots_small_heights_task_running() {
       // ... 现有代码 ...
       
       for h in [1u16, 2, 3] {
           // ... 渲染代码 ...
           
           // 添加功能性断言
           assert!(chat.agent_turn_running, "任务应处于运行状态");
           assert!(
               chat.current_status.header.contains("Thinking"),
               "状态应显示 Thinking"
           );
           
           assert_snapshot!(name, terminal.backend());
       }
   }
   ```

3. **添加高度警告**
   ```rust
   const MIN_USABLE_HEIGHT: u16 = 5;
   
   fn render(&self, area: Rect, buf: &mut Buffer) {
       if area.height < MIN_USABLE_HEIGHT {
           // 在首次渲染时记录警告
           warn!(
               "Terminal height ({}) is below recommended minimum ({}). \
                Some UI elements may not be visible.",
               area.height, MIN_USABLE_HEIGHT
           );
       }
       // ...
   }
   ```

4. **文档和用户体验**
   - 在启动时检测终端尺寸并给出建议
   - 在 `--help` 中注明推荐终端尺寸
   - 考虑添加 `codex --compact-mode` 专门用于小终端

### 相关测试对比

| 维度 | chat_small_running_h1 | chat_small_running_h2 | chat_small_running_h3 |
|------|----------------------|----------------------|----------------------|
| 高度 | 1 | 2 | 3 |
| 状态行 | ❌ 不可见 | ⚠️ 可能可见 | ✅ 可见 |
| 输入框 | ❌ 不可见 | ⚠️ 压缩显示 | ✅ 可见 |
| 帮助提示 | ❌ 不可见 | ❌ 不可见 | ⚠️ 可能可见 |
| 队列预览 | ❌ 不可见 | ❌ 不可见 | ⚠️ 可能可见 |

---

*文档生成时间：2026-03-23*
*对应 snapshot：codex_tui_app_server__chatwidget__tests__chat_small_running_h2.snap*
