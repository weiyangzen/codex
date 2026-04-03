# ChatWidget 小尺寸终端运行状态测试 (高度3)

## 场景与职责

该 snapshot 测试验证 `ChatWidget` 在受限但可用的终端高度（3行）且任务运行状态下的渲染表现。高度3是系列测试中空间最充裕的，能够展示更多 UI 元素的同时仍然保持紧凑。

### 测试目的
- 验证三高度终端下的完整底部面板渲染
- 确保状态指示器、输入框和帮助提示能够共存
- 捕获高度为3时运行状态的视觉快照

### 业务场景
- 标准终端分割（如 tmux 三等分窗口）
- 笔记本屏幕上的多任务处理
- 嵌入式开发环境中的串口终端

## 功能点目的

### 1. 三行空间的优化利用
在3行高度下，`ChatWidget` 可以展示：
- 第1行：状态指示器（带 spinner 的 "Working" + 计时器）
- 第2行：消息队列预览（如有排队消息）
- 第3行：输入框 + 快捷键提示

### 2. 完整用户交互能力
相比高度1和2，高度3提供了：
- 清晰的状态反馈
- 输入能力保留
- 队列管理可视化

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
"                                        "
```

**分析**：
- 三行均显示为空格
- 与高度1和2的 snapshot 类似
- 可能原因：
  1. `TestBackend` 的渲染机制与 VT100Backend 不同
  2. 测试中的 `ChatWidget` 配置可能未启用某些视觉元素
  3. 状态指示器的渲染可能需要实际动画帧才能显示

### 状态流分析
```
TurnStartedEvent
    ↓
agent_turn_running = true
    ↓
BottomPane.set_task_running(true)
    ↓
AgentReasoningDeltaEvent("**Thinking**")
    ↓
reasoning_buffer = "Thinking"
    ↓
current_status.header = "Thinking"
    ↓
render() 被调用
    ↓
TestBackend 捕获输出
```

## 关键代码路径与文件引用

### 状态更新链
```rust
// codex-rs/tui_app_server/src/chatwidget.rs

// 1. 处理任务开始事件
fn handle_turn_started(&mut self, event: TurnStartedEvent) {
    self.agent_turn_running = true;
    self.bottom_pane.set_task_running(true);
    self.session_header.on_turn_started(&event);
    // ...
}

// 2. 处理推理增量
fn on_agent_reasoning_delta(&mut self, delta: String) {
    self.reasoning_buffer.push_str(&delta);
    self.update_status_from_reasoning();
}

// 3. 更新状态指示器
fn update_status_from_reasoning(&mut self) {
    // 从 reasoning_buffer 提取状态文本
    let header = extract_header(&self.reasoning_buffer);
    self.current_status = StatusIndicatorState {
        header,
        details: None,
        details_max_lines: STATUS_DETAILS_DEFAULT_MAX_LINES,
    };
}
```

### 底部面板渲染
```rust
// codex-rs/tui_app_server/src/bottom_pane/mod.rs

pub(crate) fn render(&self, area: Rect, buf: &mut Buffer) {
    let layout = self.calculate_layout(area);
    
    // 状态指示器区域
    if self.task_running && layout.status_height > 0 {
        self.render_status_indicator(layout.status_area, buf);
    }
    
    // 消息队列预览区域
    if !self.queued_user_messages.is_empty() && layout.queue_height > 0 {
        self.render_queue_preview(layout.queue_area, buf);
    }
    
    // 输入框区域
    self.render_composer(layout.composer_area, buf);
    
    // 帮助提示区域
    if layout.help_height > 0 {
        self.render_help_line(layout.help_area, buf);
    }
}
```

### 布局计算
```rust
fn calculate_layout(&self, area: Rect) -> BottomPaneLayout {
    let mut remaining = area.height;
    
    // 状态指示器：1行（如果任务运行中）
    let status_height = if self.task_running { 1 } else { 0 };
    remaining = remaining.saturating_sub(status_height);
    
    // 队列预览：最多2行或实际队列大小
    let queue_height = self.queued_user_messages.len().min(2).min(remaining);
    remaining = remaining.saturating_sub(queue_height);
    
    // 输入框：至少1行
    let composer_height = 1.min(remaining);
    remaining = remaining.saturating_sub(composer_height);
    
    // 帮助行：剩余空间
    let help_height = remaining;
    
    BottomPaneLayout {
        status_height,
        queue_height,
        composer_height,
        help_height,
        // ... 区域计算
    }
}
```

## 依赖与外部交互

### 协议层依赖
```rust
// codex-protocol 事件类型
pub struct TurnStartedEvent {
    pub turn_id: String,
    pub model_context_window: Option<i64>,
    pub collaboration_mode_kind: ModeKind,
}

pub struct AgentReasoningDeltaEvent {
    pub delta: String,
}
```

### 内部模块依赖
| 模块 | 关键类型/函数 | 职责 |
|------|--------------|------|
| `session_header.rs` | `SessionHeader::on_turn_started()` | 更新会话头部状态 |
| `status_indicator_widget.rs` | `StatusIndicatorWidget` | 渲染状态指示器 UI |
| `bottom_pane/mod.rs` | `BottomPane::set_task_running()` | 管理任务运行状态 |
| `streaming/` | `StreamController` | 控制流式输出 |

### 测试辅助
```rust
// 测试配置
async fn test_config() -> Config {
    let codex_home = std::env::temp_dir();
    ConfigBuilder::default()
        .codex_home(codex_home.clone())
        .build()
        .await
        .expect("config")
}

// 模型目录
fn test_model_catalog(config: &Config) -> Arc<ModelCatalog> {
    let collaboration_modes_config = CollaborationModesConfig {
        default_mode_request_user_input: config
            .features
            .enabled(Feature::DefaultModeRequestUserInput),
    };
    Arc::new(ModelCatalog::new(
        codex_core::test_support::all_model_presets().clone(),
        collaboration_modes_config,
    ))
}
```

## 风险、边界与改进建议

### 当前问题

1. **Snapshot 内容为空**
   - 三行均为空格，无法验证渲染正确性
   - 可能遗漏了重要的回归问题
   - 与其他小高度测试无法区分

2. **测试验证不足**
   - 仅依赖视觉 snapshot，缺少状态断言
   - 未验证 `agent_turn_running` 标志是否正确设置
   - 未验证 `current_status` 内容

3. **渲染逻辑不透明**
   - 不清楚为什么3行高度下仍无可见输出
   - `TestBackend` 的行为与生产环境可能有差异

### 改进建议

1. **增强 Snapshot 内容**
   ```rust
   // 考虑使用 VT100Backend 替代 TestBackend
   let backend = VT100Backend::new(width, height);
   let mut term = crate::custom_terminal::Terminal::with_options(backend).expect("terminal");
   ```

2. **添加状态断言**
   ```rust
   #[tokio::test]
   async fn ui_snapshots_small_heights_task_running() {
       // ... 设置代码 ...
       
       // 验证内部状态
       assert!(chat.agent_turn_running);
       assert_eq!(chat.reasoning_buffer, "Thinking");
       assert_eq!(chat.current_status.header, "Thinking");
       assert!(chat.bottom_pane.is_task_running());
       
       // ... 渲染和 snapshot ...
   }
   ```

3. **改进 TestBackend 渲染**
   - 调查为什么 `TestBackend` 不捕获状态指示器
   - 可能需要手动触发 spinner 动画帧
   - 或者使用 `Buffer::content` 直接检查

4. **添加交互测试**
   ```rust
   #[tokio::test]
   async fn small_height_interrupt_still_works() {
       let (mut chat, _rx, mut op_rx) = make_chatwidget_manual(None).await;
       
       // 设置运行状态
       chat.bottom_pane.set_task_running(true);
       
       // 模拟 Ctrl+C
       chat.handle_key_event(KeyEvent::new(KeyCode::Char('c'), KeyModifiers::CONTROL));
       
       // 验证中断操作被发送
       assert_matches!(op_rx.try_recv(), Ok(Op::Interrupt));
   }
   ```

5. **文档化最小支持尺寸**
   ```markdown
   ## 终端尺寸要求
   
   - **推荐高度**: 24+ 行（完整功能）
   - **最小可用高度**: 10 行（基本功能）
   - **紧急模式**: 3 行（仅状态 + 输入）
   - **低于 3 行**: 不推荐，功能受限
   ```

### 测试系列总结

| 测试 | 高度 | 状态 | 关键验证点 |
|------|------|------|-----------|
| chat_small_idle_h1 | 1 | 空闲 | 不 panic |
| chat_small_idle_h2 | 2 | 空闲 | 输入框可见性 |
| chat_small_idle_h3 | 3 | 空闲 | 完整底部面板 |
| chat_small_running_h1 | 1 | 运行 | 不 panic |
| chat_small_running_h2 | 2 | 运行 | 状态指示器 |
| chat_small_running_h3 | 3 | 运行 | **本测试** - 完整状态 + 输入 |

---

*文档生成时间：2026-03-23*
*对应 snapshot：codex_tui_app_server__chatwidget__tests__chat_small_running_h3.snap*
