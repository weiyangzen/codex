# feedback_selection_popup 快照研究文档

## 场景与职责

此快照测试验证 **tui_app_server** 中反馈功能的**反馈类别选择弹出框**渲染。当用户通过斜杠命令（`/feedback` 或 `:feedback`）触发反馈功能时，系统显示一个选择弹出框，让用户选择反馈的类别。

这是用户反馈流程的第一步，提供了五种预定义的反馈类别供用户选择。

## 功能点目的

1. **反馈分类收集**：将用户反馈按类别分类，便于团队优先处理和统计分析
2. **用户体验优化**：提供清晰的选项描述，帮助用户准确表达反馈意图
3. **快捷入口**：通过斜杠命令快速访问反馈功能
4. **引导式反馈**：每个类别都有详细的描述，引导用户提供更有价值的反馈

### 反馈类别说明

| 类别 | 描述 | 用途 |
|------|------|------|
| bug | Crash, error message, hang, or broken UI/behavior | 报告程序错误 |
| bad result | Output was off-target, incorrect, incomplete, or unhelpful | 报告结果质量问题 |
| good result | Helpful, correct, high‑quality, or delightful result worth celebrating | 正面反馈 |
| safety check | Benign usage blocked due to safety checks or refusals | 安全误判报告 |
| other | Slowness, feature suggestion, UX feedback, or anything else | 其他反馈 |

## 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/chatwidget/tests.rs` 第 8720-8728 行

```rust
#[tokio::test]
async fn feedback_selection_popup_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;

    // Open the feedback category selection popup via slash command.
    chat.dispatch_command(SlashCommand::Feedback);

    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("feedback_selection_popup", popup);
}
```

### 核心实现逻辑

1. **命令分发** (`dispatch_command`):
   - 处理 `SlashCommand::Feedback` 命令
   - 触发反馈选择弹出框的显示

2. **选择项构建** (`feedback_selection_params`):
   - 位于 `codex-rs/tui_app_server/src/bottom_pane/feedback_view.rs` 第 426-465 行
   
   ```rust
   pub(crate) fn feedback_selection_params(
       app_event_tx: AppEventSender,
   ) -> super::SelectionViewParams {
       super::SelectionViewParams {
           title: Some("How was this?".to_string()),
           items: vec![
               make_feedback_item(app_event_tx.clone(), "bug", "...", FeedbackCategory::Bug),
               make_feedback_item(app_event_tx.clone(), "bad result", "...", FeedbackCategory::BadResult),
               make_feedback_item(app_event_tx.clone(), "good result", "...", FeedbackCategory::GoodResult),
               make_feedback_item(app_event_tx.clone(), "safety check", "...", FeedbackCategory::SafetyCheck),
               make_feedback_item(app_event_tx, "other", "...", FeedbackCategory::Other),
           ],
           ..Default::default()
       }
   }
   ```

3. **选择项创建** (`make_feedback_item`):
   - 第 482-498 行
   - 为每个反馈类别创建 `SelectionItem`
   - 绑定选择后的动作：发送 `AppEvent::OpenFeedbackConsent` 事件

4. **渲染机制**:
   - 使用 `render_bottom_popup` 函数渲染弹出框
   - 宽度限制为 80 字符，测试布局适配

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试用例定义 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | ChatWidget 实现，包含 `dispatch_command` 方法 |
| `codex-rs/tui_app_server/src/bottom_pane/feedback_view.rs` | 反馈选择参数构建 |
| `codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs` | 选择弹出框通用渲染 |
| `codex-rs/tui_app_server/src/bottom_pane/mod.rs` | BottomPane 渲染协调 |
| `codex-rs/tui_app_server/src/slash_command.rs` | 斜杠命令定义 |

### 关键数据结构

```rust
// SelectionViewParams 结构
pub struct SelectionViewParams {
    pub title: Option<String>,
    pub subtitle: Option<String>,
    pub header: Box<dyn Renderable>,
    pub items: Vec<SelectionItem>,
    pub footer_hint: Option<Line<'static>>,
}

// SelectionItem 结构
pub struct SelectionItem {
    pub name: String,
    pub description: Option<String>,
    pub actions: Vec<SelectionAction>,
    pub dismiss_on_select: bool,
    pub is_disabled: bool,
    pub disabled_reason: Option<String>,
}
```

## 依赖与外部交互

### 内部模块交互流程
```
用户输入 :feedback
    └── SlashCommand::Feedback
            └── dispatch_command()
                    └── show_selection_view()
                            └── feedback_selection_params()
                                    └── render_bottom_popup()
```

### 事件流
1. 用户选择某个类别
2. 触发 `SelectionAction` 回调
3. 发送 `AppEvent::OpenFeedbackConsent` 事件
4. 关闭选择弹出框（`dismiss_on_select: true`）
5. 显示反馈同意弹出框

## 风险、边界与改进建议

### 潜在风险

1. **类别歧义**：
   - 用户可能不清楚应该选择哪个类别
   - 缓解措施：详细的描述文本帮助用户理解

2. **选择疲劳**：
   - 5 个选项可能对某些用户来说过多
   - 考虑根据上下文智能排序或隐藏某些选项

### 边界情况

1. **窄屏幕适配**：
   - 测试使用 80 字符宽度
   - 描述文本较长，需要验证换行处理

2. **键盘导航**：
   - 需要支持上下箭头选择和 Enter 确认
   - 需要支持 Esc 取消

3. **禁用状态**：
   - 某些类别在特定上下文中可能被禁用
   - 当前实现中所有类别默认可用

### 改进建议

1. **智能默认选择**：
   - 根据当前会话上下文（如是否发生错误）预选择最可能的类别
   - 减少用户操作步骤

2. **最近使用排序**：
   - 记录用户常用的反馈类别
   - 将常用类别排在前面

3. **搜索/过滤功能**：
   - 当类别数量增加时，添加实时搜索过滤
   - 支持键盘快速跳转（如输入 "b" 跳转到 "bug"）

4. **视觉层次优化**：
   - 正面反馈（good result）可以使用不同的颜色突出
   - 错误相关类别（bug, bad result）可以分组显示

5. **快捷方式**：
   - 为常用类别添加数字快捷键（1-5）
   - 在选项前显示快捷键提示

### 相关测试

- `feedback_upload_consent_popup_snapshot`：测试选择后的同意弹出框
- `feedback_good_result_consent_popup_snapshot`：测试良好结果的特定同意弹出框
- `feedback_view_*` 系列测试：测试各类别的反馈视图渲染
