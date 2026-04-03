# Plan Implementation Popup Snapshot Research

## 场景与职责

该 snapshot 测试验证计划实现确认弹出框的渲染效果。当 Codex 在 Plan 模式下完成计划制定后，系统询问用户是否要切换到 Default 模式并开始执行计划。

**测试场景**：
- 用户处于 Plan 模式（协作模式之一）
- AI 完成计划制定并输出计划内容
- 系统显示确认对话框询问是否开始执行

## 功能点目的

1. **模式切换确认**：确保用户明确同意从计划模式切换到执行模式
2. **计划审查机会**：给用户机会审查计划后再开始执行
3. **工作流引导**：引导用户完成 "计划 → 审查 → 执行" 的完整工作流
4. **自动消息发送**：确认后自动发送执行指令消息

## 具体技术实现

### 测试代码路径
**文件**：`codex-rs/tui_app_server/src/chatwidget/tests.rs` (约第 2470-2476 行)

```rust
#[tokio::test]
async fn plan_implementation_popup_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(Some("gpt-5")).await;
    chat.open_plan_implementation_prompt();  // 打开计划实现提示

    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("plan_implementation_popup", popup);
}
```

### 核心实现代码
**文件**：`codex-rs/tui_app_server/src/chatwidget.rs` (约第 2198-2245 行)

```rust
fn open_plan_implementation_prompt(&mut self) {
    let default_mask = collaboration_modes::default_mode_mask(self.model_catalog.as_ref());
    let (implement_actions, implement_disabled_reason) = match default_mask {
        Some(mask) => {
            let user_text = PLAN_IMPLEMENTATION_CODING_MESSAGE.to_string();
            let actions: Vec<SelectionAction> = vec![Box::new(move |tx| {
                tx.send(AppEvent::SubmitUserMessageWithMode {
                    text: user_text.clone(),
                    collaboration_mode: mask.clone(),
                });
            })];
            (actions, None)
        }
        None => (Vec::new(), Some("Default mode unavailable".to_string())),
    };

    let items = vec![
        SelectionItem {
            name: PLAN_IMPLEMENTATION_YES.to_string(),  // "Yes, implement this plan"
            description: Some("Switch to Default and start coding.".to_string()),
            selected_description: None,
            is_current: false,
            actions: implement_actions,
            disabled_reason: implement_disabled_reason,
            dismiss_on_select: true,
            ..Default::default()
        },
        SelectionItem {
            name: PLAN_IMPLEMENTATION_NO.to_string(),  // "No, stay in Plan mode"
            description: Some("Continue planning with the model.".to_string()),
            selected_description: None,
            is_current: false,
            actions: vec![],
            disabled_reason: None,
            dismiss_on_select: true,
            ..Default::default()
        },
    ];

    self.bottom_pane.show_selection_view(SelectionViewParams {
        title: Some(PLAN_IMPLEMENTATION_TITLE.to_string()),  // "Implement this plan?"
        subtitle: None,
        footer_hint: Some(standard_popup_hint_line()),
        items,
        ..Default::default()
    });
}
```

### 常量定义
```rust
const PLAN_IMPLEMENTATION_TITLE: &str = "Implement this plan?";
const PLAN_IMPLEMENTATION_YES: &str = "Yes, implement this plan";
const PLAN_IMPLEMENTATION_NO: &str = "No, stay in Plan mode";
const PLAN_IMPLEMENTATION_CODING_MESSAGE: &str = "Go ahead and implement the plan.";
```

### Snapshot 内容
```
  Implement this plan?

› 1. Yes, implement this plan  Switch to Default and start coding.
  2. No, stay in Plan mode     Continue planning with the model.

  Press enter to confirm or esc to go back
```

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs:2198-2245` | `open_plan_implementation_prompt()` - 主逻辑 |
| `codex-rs/tui_app_server/src/chatwidget.rs:2185-2196` | 计划完成检测和提示触发 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs:2470-2505` | 测试用例实现 |
| `codex-rs/core/src/collaboration_modes.rs` | 协作模式定义和掩码 |

### 触发条件
**文件**：`codex-rs/tui_app_server/src/chatwidget.rs` (约第 2185-2196 行)

```rust
fn maybe_show_plan_implementation_prompt(&mut self) {
    // 检查是否在 Plan 模式
    if !self.collaboration_modes_enabled() || 
       self.active_mode_kind() != ModeKind::Plan {
        return;
    }
    
    // 检查是否有计划输出
    if !self.has_proposed_plan_output() {
        return;
    }
    
    // 检查是否已显示过提示
    if self.plan_implementation_prompt_shown {
        return;
    }
    
    self.open_plan_implementation_prompt();
}
```

## 依赖与外部交互

### 依赖模块
1. **CollaborationModes**：定义 Plan 和 Default 模式
2. **ModeKind**：协作模式类型枚举
3. **SubmitUserMessageWithMode**：带模式的用户消息提交
4. **Plan Tracking**：跟踪计划输出状态

### 事件流
```
AI 完成计划输出
    ↓
检测到 Plan 模式且有计划内容
    ↓
显示 "Implement this plan?" 提示
    ↓
用户选择 "Yes, implement this plan"
    ↓
发送 AppEvent::SubmitUserMessageWithMode
    ↓
自动发送消息 "Go ahead and implement the plan."
    ↓
切换到 Default 模式
    ↓
开始执行计划
```

### 与协作模式的集成
- Plan 模式：`ModeKind::Plan`，专注于计划制定
- Default 模式：`ModeKind::Default`，执行计划
- 模式切换通过 `collaboration_mode` 参数实现

### 防止重复显示
```rust
plan_implementation_prompt_shown: bool  // 标记是否已显示过提示
```

## 风险、边界与改进建议

### 潜在风险
1. **意外执行**：用户可能误操作导致计划立即执行
2. **计划审查不足**：用户可能没有充分审查计划就确认
3. **模式切换困惑**：用户可能不理解 Plan 和 Default 模式的区别

### 边界情况
1. **无 Default 模式**：某些配置下 Default 模式可能不可用
2. **已排队消息**：如果有待发送消息，提示可能被跳过
3. **重放消息**：历史消息重放时不应触发提示
4. **速率限制**：速率限制警告优先于计划实现提示

### 改进建议
1. **计划预览**：在提示中显示计划的部分内容供快速审查
2. **分步执行**：提供 "执行第一步" 选项，而非全部执行
3. **计划修改**：提供 "修改计划" 选项，返回计划模式进行细化
4. **确认强化**：重要计划的执行需要额外确认
5. **执行摘要**：显示计划执行预计影响的文件和操作
6. **撤销准备**：执行前创建检查点，便于撤销

### 相关测试
- `plan_implementation_popup_no_selected`：测试 "No" 选项被选中状态
- `plan_implementation_popup_yes_emits_submit_message_event`：测试确认后的事件
- `plan_implementation_popup_skips_replayed_turn_complete`：测试重放场景
- `plan_implementation_popup_skips_when_messages_queued`：测试排队消息场景

### 协作模式工作流
```
用户输入任务描述
    ↓
[Plan Mode] AI 制定执行计划
    ↓
显示计划内容
    ↓
显示 "Implement this plan?" 提示
    ↓
用户确认
    ↓
[Default Mode] AI 执行计划
    ↓
输出执行结果
```

### UI 设计特点
1. **行动导向标题**："Implement this plan?" 直接询问行动意向
2. **明确后果描述**：
   - "Yes"：明确说明会 "Switch to Default and start coding"
   - "No"：明确说明会 "Continue planning"
3. **默认选中 "Yes"**：符合常见工作流（计划后立即执行）
4. **简洁界面**：无副标题，保持焦点在决策上
