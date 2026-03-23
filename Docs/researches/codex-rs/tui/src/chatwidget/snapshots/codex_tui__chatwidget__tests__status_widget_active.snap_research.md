# 研究报告: status_widget_active.snap

## 场景与职责

该快照文件验证**活动状态指示器**的渲染效果。当 Codex 正在处理任务时，状态指示器显示当前活动（如 "Analyzing"）和持续时间。

测试场景：
- 任务已开始 (`TurnStarted`)
- 收到推理增量 `**Analyzing**`（加粗标记表示状态标题）
- 验证状态指示器正确显示 "Analyzing"

## 功能点目的

**状态指示器**提供实时任务状态反馈：

1. **活动可见性** - 用户清楚知道 Codex 正在工作
2. **进度感知** - 显示已运行时间
3. **中断提示** - 提示可按 Esc 中断
4. **状态细分** - 区分不同活动阶段（Analyzing/Working/Exploring 等）

## 具体技术实现

### 测试实现

```rust
// tests.rs:9600-9629
// Snapshot test: status widget active (StatusIndicatorView)
// Ensures the VT100 rendering of the status indicator is stable when active.
#[tokio::test]
async fn status_widget_active_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;
    // 激活状态指示器
    chat.handle_codex_event(Event {
        id: "task-1".into(),
        msg: EventMsg::TurnStarted(TurnStartedEvent {
            turn_id: "turn-1".to_string(),
            model_context_window: None,
            collaboration_mode_kind: ModeKind::Default,
        }),
    });
    // 通过加粗推理块设置状态标题
    chat.handle_codex_event(Event {
        id: "task-1".into(),
        msg: EventMsg::AgentReasoningDelta(AgentReasoningDeltaEvent {
            delta: "**Analyzing**".into(),
        }),
    });
    
    // 渲染并快照
    let height = chat.desired_height(80);
    let mut terminal = ratatui::Terminal::new(ratatui::backend::TestBackend::new(80, height))
        .expect("create terminal");
    terminal
        .draw(|f| chat.render(f.area(), f.buffer_mut()))
        .expect("draw status widget");
    assert_snapshot!("status_widget_active", terminal.backend());
}
```

### 状态标题提取

```rust
// 从推理增量中提取状态标题
fn on_agent_reasoning_delta(&mut self, delta: String) {
    // 检查加粗标记 **Title**
    if let Some(title) = extract_bold_title(&delta) {
        self.current_status.header = title;
    }
    // ...
}

fn extract_bold_title(text: &str) -> Option<String> {
    // 匹配 **Text** 格式
    let re = regex::Regex::new(r"\*\*(.+?)\*\*").ok()?;
    re.captures(text).and_then(|cap| {
        cap.get(1).map(|m| m.as_str().to_string())
    })
}
```

### 渲染输出

```
"                                                                                "
"• Analyzing (0s • esc to interrupt)                                             "
"                                                                                "
"                                                                                "
"› Ask Codex to do anything                                                      "
"                                                                                "
"  ? for shortcuts                                            100% context left  "
```

**解析**：
- 第 2 行：`• Analyzing (0s • esc to interrupt)` - 状态指示器
  - `•` - 活动指示点
  - `Analyzing` - 状态标题
  - `(0s` - 已运行时间
  - `• esc to interrupt)` - 中断提示
- 第 5 行：`› Ask Codex to do anything` - 输入提示
- 第 7 行：`? for shortcuts` 和 `100% context left` - 底部提示

## 关键代码路径与文件引用

| 文件 | 行号范围 | 描述 |
|------|----------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 9600-9629 | 活动状态指示器测试 |
| `codex-rs/tui/src/chatwidget/mod.rs` | - | 状态事件处理 |
| `codex-rs/tui/src/bottom_pane/` | - | 状态指示器组件 |
| `codex-rs/tui/src/status_indicator_widget.rs` | - | 状态指示器渲染 |

## 依赖与外部交互

### 状态事件类型

```rust
codex_protocol::protocol::TurnStartedEvent {
    turn_id: String,
    model_context_window: Option<u32>,
    collaboration_mode_kind: ModeKind,
}

codex_protocol::protocol::AgentReasoningDeltaEvent {
    delta: String, // 可能包含 **Title** 标记
}
```

### 状态生命周期

1. **TurnStarted** → 激活状态指示器
2. **AgentReasoningDelta** → 更新状态标题
3. **TurnComplete/TurnAborted** → 关闭状态指示器

## 风险、边界与改进建议

### 特定风险

1. **标题闪烁** - 频繁的状态更新导致 UI 闪烁
2. **时间精度** - 长时间运行的任务时间显示精度
3. **状态丢失** - 连接中断后状态恢复

### 边界情况

1. **无标题** - 没有收到加粗标题时的默认显示
2. **超长标题** - 状态标题过长时的截断
3. **多行标题** - 标题包含换行符的处理

### 改进建议

1. **动画指示** - 添加旋转动画表示活动状态
2. **时间格式化** - 长时间任务显示 "2m 30s" 而非 "150s"
3. **状态历史** - 显示最近几个状态变更
4. **进度估算** - 基于历史数据估算剩余时间
5. **子任务显示** - 显示当前子任务/步骤

### 相关测试

- `status_widget_and_approval_modal` - 状态指示器与审批弹窗共存
- `mcp_startup_header_booting` - MCP 启动状态显示
- `background_event_updates_status_header` - 后台事件状态更新
