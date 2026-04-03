# 计划实现弹出框测试研究文档

## 场景与职责

该 snapshot 测试验证 tui_app_server 的 ChatWidget 能够正确显示计划实现确认弹出框，当 AI 完成计划制定后询问用户是否要切换到实现模式开始编码。

**测试场景**：
1. 用户当前处于 Plan（计划）协作模式
2. 使用 gpt-5 模型
3. AI 完成了计划制定
4. 系统显示确认弹出框，询问是否要实现该计划

**职责**：确保用户在计划完成后可以方便地切换到实现模式，提供流畅的计划到实现的过渡体验。

## 功能点目的

- **模式切换提示**：在计划完成后提示用户切换到实现模式
- **用户控制**：让用户决定是否立即开始实现或继续完善计划
- **上下文保持**：切换模式时保持当前对话上下文
- **工作流引导**：引导用户完成计划→实现的完整工作流

## 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/chatwidget/tests.rs` 第 2470-2476 行

```rust
#[tokio::test]
async fn plan_implementation_popup_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(Some("gpt-5")).await;
    chat.open_plan_implementation_prompt();

    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("plan_implementation_popup", popup);
}
```

### 关键实现细节

1. **初始化 ChatWidget**：
   - 使用 `make_chatwidget_manual` 创建测试实例
   - 指定当前模型为 gpt-5

2. **打开计划实现提示**：
   - 调用 `open_plan_implementation_prompt()` 触发确认对话框
   - 通常在 Plan 模式下任务完成后自动触发

3. **渲染捕获**：
   - 使用 `render_bottom_popup` 在 80 列宽度下渲染弹出框内容
   - 捕获并验证 UI 输出

### 相关功能测试

第 2489-2505 行测试了确认后的行为：

```rust
#[tokio::test]
async fn plan_implementation_popup_yes_emits_submit_message_event() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(Some("gpt-5")).await;
    chat.open_plan_implementation_prompt();

    chat.handle_key_event(KeyEvent::from(KeyCode::Enter));

    let event = rx.try_recv().expect("expected AppEvent");
    let AppEvent::SubmitUserMessageWithMode { text, collaboration_mode } = event
    else {
        panic!("expected SubmitUserMessageWithMode, got {event:?}");
    };
    assert_eq!(text, PLAN_IMPLEMENTATION_CODING_MESSAGE);
    assert_eq!(collaboration_mode.mode, Some(ModeKind::Default));
}
```

### Snapshot 输出内容

```
Implement this plan?

› 1. Yes, implement this plan  Switch to Default and start coding.
  2. No, stay in Plan mode     Continue planning with the model.

Press enter to confirm or esc to go back
```

## 关键代码路径与文件引用

### 主要代码文件

1. **测试文件**：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
   - 测试函数：`plan_implementation_popup_snapshot` (第 2470 行)
   - 功能测试：`plan_implementation_popup_yes_emits_submit_message_event` (第 2489 行)
   - 其他相关测试：多个 `plan_implementation_popup_*` 测试函数

2. **ChatWidget 实现**：`codex-rs/tui_app_server/src/chatwidget/mod.rs`
   - 方法：`open_plan_implementation_prompt`
   - 常量：`PLAN_IMPLEMENTATION_TITLE`, `PLAN_IMPLEMENTATION_CODING_MESSAGE`

3. **底部面板**：`codex-rs/tui_app_server/src/bottom_pane/mod.rs`
   - 负责渲染确认对话框 UI

4. **协作模式**：`codex-protocol/src/config_types.rs`
   - `ModeKind`：协作模式枚举（Default, Plan, etc.）
   - `CollaborationMode`：协作模式配置

### 相关协议类型

- `ModeKind::Plan`：计划模式
- `ModeKind::Default`：默认（实现）模式
- `AppEvent::SubmitUserMessageWithMode`：带模式的用户消息提交事件

## 依赖与外部交互

### 内部依赖

| 组件 | 用途 |
|------|------|
| `ChatWidget` | 主聊天组件，管理计划实现流程 |
| `BottomPane` | 渲染确认对话框 UI |
| `CollaborationMode` | 协作模式配置 |
| `AppEventSender` | 发送模式切换事件 |

### 外部依赖

- `ratatui`：终端 UI 渲染库
- `insta`：snapshot 测试框架
- `tokio`：异步运行时

### 触发条件

计划实现弹出框在以下条件下触发：
1. 当前处于 Plan 协作模式
2. 任务完成且产生了计划输出
3. 没有排队的用户消息
4. 没有待处理的速率限制提示

## 风险、边界与改进建议

### 潜在风险

1. **时机问题**：弹出框可能在用户正在输入时弹出，打断工作流
2. **重复提示**：如果用户选择"否"，后续可能反复收到相同提示
3. **上下文丢失**：切换模式时可能丢失某些上下文信息

### 边界情况

1. **重放消息**：重放的 TurnComplete 消息不应触发弹出框（见 `plan_implementation_popup_skips_replayed_turn_complete` 测试）
2. **队列消息**：如果有排队的消息，不应显示弹出框（见 `plan_implementation_popup_skips_when_messages_queued` 测试）
3. **无计划输出**：如果没有产生计划输出，不应显示弹出框（见 `plan_implementation_popup_skips_without_proposed_plan` 测试）
4. **用户干预**：如果用户在计划后发送了消息，不应显示弹出框（见 `plan_implementation_popup_skips_when_steer_follows_proposed_plan` 测试）
5. **速率限制**：如果有待处理的速率限制提示，优先显示速率限制提示（见 `plan_implementation_popup_skips_when_rate_limit_prompt_pending` 测试）

### 改进建议

1. **智能时机**：检测用户活动，避免在用户活跃输入时弹出
2. **记忆选择**：记住用户的选择，避免重复询问
3. **延迟提示**：提供"稍后提醒我"选项
4. **计划预览**：在弹出框中显示计划的简要预览
5. **批量操作**：允许用户标记多个计划任务，一次性实现

### 相关测试

- `plan_implementation_popup_no_selected_snapshot`：未选中状态测试
- `plan_implementation_popup_skips_replayed_turn_complete`：跳过重放消息测试
- `plan_implementation_popup_shows_once_when_replay_precedes_live_turn_complete`：重放后只显示一次测试
- `plan_implementation_popup_skips_when_messages_queued`：有排队消息时跳过测试
- `plan_implementation_popup_skips_without_proposed_plan`：无计划输出时跳过测试
- `plan_implementation_popup_shows_after_proposed_plan_output`：有计划输出时显示测试
- `plan_implementation_popup_skips_when_steer_follows_proposed_plan`：用户干预后跳过测试
- `plan_implementation_popup_skips_when_rate_limit_prompt_pending`：速率限制优先测试
