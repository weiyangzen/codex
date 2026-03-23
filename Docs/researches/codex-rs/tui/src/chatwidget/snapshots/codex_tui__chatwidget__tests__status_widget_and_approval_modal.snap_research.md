# 研究报告: status_widget_and_approval_modal.snap

## 场景与职责

该快照文件验证**状态指示器与审批弹窗共存**时的渲染效果。当 Codex 正在执行任务且需要用户审批某个操作时（如执行命令），两者需要同时正确显示。

测试场景：
- 任务已开始，状态指示器显示 "Analyzing"
- 同时出现一个执行命令审批请求（`echo 'hello world'`）
- 验证弹窗正确覆盖状态指示器，且布局协调

## 功能点目的

**弹窗优先级管理**确保：

1. **用户注意力** - 审批请求优先于状态显示
2. **上下文保留** - 用户知道后台仍有任务运行
3. **决策信息** - 提供足够信息做出审批决策
4. **操作便捷** - 清晰的确认/取消选项

## 具体技术实现

### 测试实现

```rust
// tests.rs:9426-9487
// Snapshot test: status widget + approval modal active together
// The modal takes precedence visually; this captures the layout with a running
// task (status indicator active) while an approval request is shown.
#[tokio::test]
async fn status_widget_and_approval_modal_snapshot() {
    use codex_protocol::protocol::ExecApprovalRequestEvent;

    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;
    
    // 开始运行任务
    chat.handle_codex_event(Event {
        id: "task-1".into(),
        msg: EventMsg::TurnStarted(TurnStartedEvent {
            turn_id: "turn-1".to_string(),
            model_context_window: None,
            collaboration_mode_kind: ModeKind::Default,
        }),
    });
    // 设置状态标题
    chat.handle_codex_event(Event {
        id: "task-1".into(),
        msg: EventMsg::AgentReasoningDelta(AgentReasoningDeltaEvent {
            delta: "**Analyzing**".into(),
        }),
    });

    // 显示审批弹窗
    let ev = ExecApprovalRequestEvent {
        call_id: "call-approve-exec".into(),
        approval_id: Some("call-approve-exec".into()),
        turn_id: "turn-approve-exec".into(),
        command: vec!["echo".into(), "hello world".into()],
        cwd: PathBuf::from("/tmp"),
        reason: Some("this is a test reason such as one that would be produced by the model".into()),
        // ...
    };
    chat.handle_codex_event(Event {
        id: "exec-approval".into(),
        msg: EventMsg::ExecApprovalRequest(ev),
    });

    // 渲染并快照
    let width: u16 = 100;
    let height = chat.desired_height(width);
    let mut terminal = ratatui::Terminal::new(ratatui::backend::TestBackend::new(width, height))
        .expect("create terminal");
    terminal.set_viewport_area(Rect::new(0, 0, width, height));
    terminal
        .draw(|f| chat.render(f.area(), f.buffer_mut()))
        .expect("draw status + approval modal");
    assert_snapshot!("status_widget_and_approval_modal", terminal.backend());
}
```

### 审批弹窗结构

```rust
struct ExecApprovalRequestEvent {
    call_id: String,           // 调用 ID
    approval_id: Option<String>, // 审批 ID
    turn_id: String,           // 所属回合
    command: Vec<String>,      // 命令及参数
    cwd: PathBuf,              // 工作目录
    reason: Option<String>,    // 模型提供的理由
    exec_policy: Option<ExecPolicyAmendment>, // 执行策略
}
```

### 渲染输出解析

```
"                                                                                                    "
"                                                                                                    "
"  Would you like to run the following command?                                                      "
"                                                                                                    "
"  Reason: this is a test reason such as one that would be produced by the model                     "
"                                                                                                    "
"  $ echo 'hello world'                                                                              "
"                                                                                                    "
"› 1. Yes, proceed (y)                                                                               "
"  2. Yes, and don't ask again for commands that start with `echo 'hello world'` (p)                 "
"  3. No, and tell Codex what to do differently (esc)                                                "
"                                                                                                    "
"  Press enter to confirm or esc to cancel                                                           "
```

**关键元素**：
- 标题 `Would you like to run the following command?`
- 理由说明 `Reason: ...`
- 命令预览 `$ echo 'hello world'`
- 三个选项：
  1. `Yes, proceed (y)` - 确认执行
  2. `Yes, and don't ask again... (p)` - 确认并记住此命令模式
  3. `No, and tell Codex what to do differently (esc)` - 拒绝并提供反馈
- 底部提示 `Press enter to confirm or esc to cancel`

**注意**：状态指示器 (`• Analyzing`) 在弹窗后面，不可见

## 关键代码路径与文件引用

| 文件 | 行号范围 | 描述 |
|------|----------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 9426-9487 | 状态+审批弹窗测试 |
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs` | - | 审批弹窗组件 |
| `codex-rs/tui/src/chatwidget/mod.rs` | - | 审批事件处理 |

## 依赖与外部交互

### 审批决策事件

```rust
// 用户选择后发送的事件
enum AppEvent {
    SubmitApprovalResponse {
        call_id: String,
        approved: bool,
        persist: bool, // 是否记住此决定
    },
    OpenFeedbackForm { // 选择 "No" 时
        audience: FeedbackAudience,
    },
}
```

### 弹窗层级

1. **底层** - 状态指示器（被遮挡）
2. **中层** - 聊天历史
3. **顶层** - 审批弹窗（焦点）

## 风险、边界与改进建议

### 特定风险

1. **焦点管理** - 弹窗关闭后焦点应正确恢复
2. **状态同步** - 审批期间后台任务状态可能变化
3. **多审批** - 多个审批请求排队时的处理

### 边界情况

1. **长命令** - 多行命令的显示和换行
2. **长理由** - 模型提供的理由过长时的处理
3. **危险命令** - `rm -rf` 等高风险命令的特殊提示

### 改进建议

1. **风险分级** - 根据命令风险级别使用不同颜色（黄/红）
2. **命令语法高亮** - 对命令进行语法着色
3. **历史参考** - 显示类似命令的历史审批记录
4. **快捷拒绝** - 提供常见拒绝理由的快速选择
5. **预览输出** - 模拟显示命令可能的输出

### 相关测试

- `status_widget_active` - 单独状态指示器
- `approval_modal_exec` - 单独审批弹窗
- `guardian_approved_exec_renders_approved_request` - Guardian 审批流程
