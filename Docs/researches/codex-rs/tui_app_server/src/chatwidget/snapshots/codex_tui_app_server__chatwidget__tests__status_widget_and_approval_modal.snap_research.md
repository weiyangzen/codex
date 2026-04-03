# Research: status_widget_and_approval_modal Snapshot Test

## 场景与职责

该 snapshot 测试验证 `tui_app_server` 中 `ChatWidget` 组件在**状态小部件（status widget）和批准模态框（approval modal）同时激活**时的渲染行为。具体场景包括：

1. 一个正在运行的任务（通过 `TurnStarted` 事件触发）使状态指示器处于活动状态
2. 同时显示一个执行批准模态框（exec approval modal），要求用户确认是否运行某个命令
3. 验证模态框在视觉优先级上覆盖状态指示器，同时保持底层状态信息的完整性

此测试确保在复杂的 UI 叠加场景下，用户界面能够正确渲染，不会出现视觉冲突或信息丢失。

## 功能点目的

### 核心功能
- **状态指示器管理**：在代理任务运行时显示工作状态（如 "Working"）和计时器
- **批准模态框渲染**：当需要用户批准执行命令时，显示包含命令详情、执行原因和决策选项的模态框
- **UI 层级管理**：确保模态框在视觉层级上优先于状态指示器，但状态指示器在模态框关闭后能够恢复

### 业务价值
- 提供清晰的命令执行审批流程，增强安全性
- 在长时间运行的任务中保持用户对系统状态的感知
- 确保 UI 在复杂交互场景下的稳定性和一致性

## 具体技术实现

### 测试设置
```rust
// 创建 ChatWidget 实例
let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;

// 1. 启动任务以激活状态指示器
chat.handle_codex_event(Event {
    id: "task-1".into(),
    msg: EventMsg::TurnStarted(TurnStartedEvent {
        turn_id: "turn-1".to_string(),
        model_context_window: None,
        collaboration_mode_kind: ModeKind::Default,
    }),
});

// 设置确定性状态头
chat.handle_codex_event(Event {
    id: "task-1".into(),
    msg: EventMsg::AgentReasoningDelta(AgentReasoningDeltaEvent {
        delta: "**Analyzing**".into(),
    }),
});

// 2. 显示执行批准模态框
let ev = ExecApprovalRequestEvent {
    call_id: "call-approve-exec".into(),
    approval_id: Some("call-approve-exec".into()),
    turn_id: "turn-approve-exec".into(),
    command: vec!["echo".into(), "hello world".into()],
    cwd: PathBuf::from("/tmp"),
    reason: Some("this is a test reason such as one that would be produced by the model".into()),
    network_approval_context: None,
    proposed_execpolicy_amendment: Some(ExecPolicyAmendment::new(vec!["echo".into(), "hello world".into()])),
    proposed_network_policy_amendments: None,
    additional_permissions: None,
    skill_metadata: None,
    available_decisions: None,
    parsed_cmd: vec![],
};
chat.handle_codex_event(Event {
    id: "sub-approve-exec".into(),
    msg: EventMsg::ExecApprovalRequest(ev),
});
```

### 渲染验证
```rust
// 使用 100xN 的终端尺寸进行渲染
let width: u16 = 100;
let height = chat.desired_height(width);
let mut terminal = ratatui::Terminal::new(ratatui::backend::TestBackend::new(width, height))
    .expect("create terminal");
terminal.set_viewport_area(Rect::new(0, 0, width, height));
terminal
    .draw(|f| chat.render(f.area(), f.buffer_mut()))
    .expect("draw status + approval modal");
assert_snapshot!("status_widget_and_approval_modal", terminal.backend());
```

### Snapshot 输出分析
生成的 snapshot 显示：
- 模态框标题："Would you like to run the following command?"
- 执行原因：显示模型提供的理由
- 命令预览：`$ echo 'hello world'`
- 决策选项：
  - "Yes, proceed (y)"
  - "Yes, and don't ask again for commands that start with `echo 'hello world'` (p)"
  - "No, and tell Codex what to do differently (esc)"
- 操作提示："Press enter to confirm or esc to cancel"

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs` | `ChatWidget` 主实现，包含状态管理和事件处理 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试实现，包含 `status_widget_and_approval_modal_snapshot` 测试函数 |
| `codex-rs/tui_app_server/src/bottom_pane/mod.rs` | 底部面板实现，包含状态指示器和模态框渲染 |
| `codex-rs/tui_app_server/src/bottom_pane/approval_modal.rs` | 批准模态框的具体渲染逻辑 |

### 关键结构体
```rust
// ChatWidget 结构体（简化）
pub(crate) struct ChatWidget {
    bottom_pane: BottomPane,
    current_status: StatusIndicatorState,
    // ... 其他字段
}

// 批准请求事件
pub struct ExecApprovalRequestEvent {
    pub call_id: String,
    pub approval_id: Option<String>,
    pub turn_id: String,
    pub command: Vec<String>,
    pub cwd: PathBuf,
    pub reason: Option<String>,
    pub proposed_execpolicy_amendment: Option<ExecPolicyAmendment>,
    // ...
}
```

### 事件处理流程
1. `handle_codex_event` 接收 `EventMsg::TurnStarted` → 设置 `agent_turn_running = true`
2. `handle_codex_event` 接收 `EventMsg::AgentReasoningDelta` → 更新 `current_status.header`
3. `handle_codex_event` 接收 `EventMsg::ExecApprovalRequest` → 创建 `ApprovalRequest` 并显示模态框
4. `render` 方法 → 模态框优先渲染，状态指示器在模态框后渲染

## 依赖与外部交互

### 内部依赖
- `codex_protocol::protocol::*`：协议事件定义（`Event`, `EventMsg`, `TurnStartedEvent`, `ExecApprovalRequestEvent` 等）
- `ratatui`：TUI 渲染框架，提供 `Terminal`, `TestBackend`, `Rect` 等
- `insta`：Snapshot 测试框架

### 外部交互
- 通过 `make_chatwidget_manual` 创建测试实例，模拟完整的 ChatWidget 生命周期
- 使用 `TestBackend` 捕获渲染输出，避免依赖实际终端

### 配置依赖
- `AskForApproval` 策略：控制批准请求的行为
- `SandboxPolicy`：沙箱策略配置

## 风险、边界与改进建议

### 潜在风险
1. **模态框层级问题**：如果模态框渲染逻辑改变，可能导致状态指示器覆盖模态框
2. **响应式布局**：在极窄终端（< 80 列）下，模态框内容可能被截断
3. **状态恢复**：模态框关闭后，状态指示器需要正确恢复之前的状态

### 边界条件
- 空命令或空理由的批准请求
- 超长命令或理由的文本截断处理
- 多个批准请求同时到达的队列处理

### 改进建议
1. **增加尺寸变体测试**：添加不同终端宽度（如 60, 80, 120 列）的 snapshot 测试
2. **增加颜色主题测试**：验证模态框在不同颜色主题下的可读性
3. **增加交互测试**：验证用户选择后的状态转换
4. **性能优化**：模态框渲染涉及多个字符串拼接，可考虑使用缓存

### 相关测试
- `codex_tui_app_server__chatwidget__tests__approval_modal_exec.snap`：纯批准模态框测试
- `codex_tui_app_server__chatwidget__tests__status_widget_active.snap`：纯状态指示器测试
- `codex_tui_app_server__chatwidget__tests__guardian_approved_exec_renders_approved_request.snap`：Guardian 批准流程测试
