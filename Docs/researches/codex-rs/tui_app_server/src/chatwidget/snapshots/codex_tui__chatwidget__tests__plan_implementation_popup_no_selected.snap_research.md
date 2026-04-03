# Snapshot Research: plan_implementation_popup_no_selected

## 场景与职责

此快照测试验证计划实现弹出框在"No"选项被选中时的渲染输出。当用户在 Plan 模式下完成计划制定后，系统会显示此弹出框询问是否切换到 Default 模式开始执行代码。

测试场景：
- 用户在 Plan 模式下完成计划
- 系统显示计划实现确认弹出框
- 用户按下方向键"Down"选择"No"选项（默认选中"Yes"）
- 弹出框显示两个选项："Yes, implement this plan" 和 "No, stay in Plan mode"
- 使用 `render_bottom_popup` 捕获底部弹出框渲染输出进行验证

## 功能点目的

1. **模式切换确认**：在从 Plan 模式切换到 Default 模式前获得用户确认
2. **防止误操作**：避免用户意外退出 Plan 模式而丢失计划上下文
3. **明确选项**：清晰展示两个选项的含义和后果
4. **键盘导航**：支持方向键选择和 Enter 键确认

## 具体技术实现

### 关键流程

1. **计划实现确认流程**：
   ```
   完成计划项 → maybe_prompt_plan_implementation() → open_plan_implementation_prompt() → 渲染弹出框 → 用户选择 → 切换模式或保持
   ```

2. **弹出框渲染**：
   - 使用 `render_bottom_popup(&chat, 80)` 捕获宽度为 80 的弹出框渲染内容
   - 通过 `insta::assert_snapshot` 进行快照比对
   - 测试中使用 `KeyCode::Down` 模拟用户选择第二个选项

### 数据结构

```rust
pub struct SelectionItem {
    pub name: String,
    pub description: Option<String>,
    pub actions: Vec<SelectionAction>,
    pub disabled_reason: Option<String>,
}

const PLAN_IMPLEMENTATION_CODING_MESSAGE: &str = "Implement the plan";
const PLAN_IMPLEMENTATION_TITLE: &str = "Implement this plan?";
```

### 选项定义

- **选项 1 (Yes)**：切换到 Default 模式并开始编码
  - 动作：发送 `SubmitUserMessageWithMode` 事件，使用 `default_mode_mask`
  - 文本：`PLAN_IMPLEMENTATION_CODING_MESSAGE`
  
- **选项 2 (No)**：继续保持在 Plan 模式
  - 动作：关闭弹出框，不执行模式切换
  - 描述："Continue planning with the model"

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 测试定义和快照断言（tui） |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试定义和快照断言（tui_app_server） |
| `codex-rs/tui/src/chatwidget.rs` | `open_plan_implementation_prompt()` 实现 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | `open_plan_implementation_prompt()` 实现 |

### 关键函数

- `ChatWidget::open_plan_implementation_prompt()` - 打开计划实现确认弹出框
- `ChatWidget::maybe_prompt_plan_implementation()` - 检查并触发计划实现提示
- `collaboration_modes::default_mode_mask()` - 获取 Default 模式的协作掩码
- `render_bottom_popup()` - 测试辅助函数，渲染底部弹出框

### 相关常量

```rust
// codex-rs/tui/src/chatwidget.rs (line ~1818)
fn open_plan_implementation_prompt(&mut self) {
    let default_mask = collaboration_modes::default_mode_mask(self.models_manager.as_ref());
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
    // ... 构建 SelectionItem 列表
}
```

## 依赖与外部交互

### 内部依赖

- `collaboration_modes` 模块 - 协作模式定义和掩码生成
- `SelectionItem`, `SelectionAction` - 弹出框选项数据结构
- `AppEvent::SubmitUserMessageWithMode` - 用户提交消息事件

### 外部交互

- **模式管理**：与 `models_manager`/`model_catalog` 交互获取可用的协作模式
- **事件系统**：通过 `AppEvent` 发送模式切换请求
- **UI 渲染**：通过 `bottom_pane` 渲染弹出框界面

## 风险、边界与改进建议

### 潜在风险

1. **模式不可用**：当 Default 模式不可用时（`default_mode_mask` 返回 None），需要正确处理禁用状态
2. **重复提示**：如果用户在 Plan 模式下频繁完成计划，可能会被重复提示
3. **状态同步**：弹出框状态需要与实际的协作模式状态保持同步

### 边界情况

- Default 模式不可用时的禁用状态显示
- 用户在弹出框显示期间切换模式
- 弹出框与其他模态框（如费率限制提示）的优先级冲突
- 队列中有待处理消息时的提示抑制

### 改进建议

1. **增强用户体验**：
   - 添加"记住我的选择"选项，允许用户设置默认行为
   - 在选项描述中添加更详细的后果说明
   - 考虑添加计划预览摘要

2. **测试覆盖**：
   - 添加 Default 模式不可用时的测试用例
   - 测试与其他弹出框的优先级交互
   - 测试键盘导航的边界情况

3. **国际化**：
   - 支持多语言显示
   - 考虑不同语言的文本长度对布局的影响

---

**快照内容**：
```
  Implement this plan?

  1. Yes, implement this plan  Switch to Default and start coding.
› 2. No, stay in Plan mode     Continue planning with the model.

  Press enter to confirm or esc to go back
```

**说明**：显示计划实现确认弹出框，其中选项 2 "No, stay in Plan mode" 被选中（由 `›` 指示器标识）。弹出框包含标题、两个选项及其描述，以及操作提示。
