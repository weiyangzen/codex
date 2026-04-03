# 研究文档：反馈选择弹出菜单

## 场景与职责

本快照测试验证 Codex TUI 的用户反馈系统中，反馈类型选择界面的渲染效果。当用户通过 `/feedback` 斜杠命令触发反馈流程时，系统显示此弹出菜单让用户选择反馈的类别。

这是用户反馈工作流的第一步：
1. **显示反馈类型选择弹窗**（本快照）
2. 用户选择反馈类型
3. 显示日志上传同意弹窗
4. 显示反馈备注输入界面

## 功能点目的

1. **反馈分类收集**：将用户反馈分类为预定义的类别，便于后续分析和处理
2. **用户体验优化**：提供清晰的选项描述，帮助用户准确表达反馈意图
3. **差异化处理路径**：不同反馈类型触发不同的后续流程（如 GoodResult 不显示连接诊断）
4. **快捷操作支持**：每个选项支持键盘快捷键选择

## 具体技术实现

### 核心数据结构

```rust
// app_event.rs
pub enum FeedbackCategory {
    Bug,
    BadResult,
    GoodResult,
    SafetyCheck,
    Other,
}
```

### 反馈选择弹窗参数构建

```rust
// bottom_pane/feedback_view.rs
pub(crate) fn feedback_selection_params(
    app_event_tx: AppEventSender,
) -> super::SelectionViewParams {
    super::SelectionViewParams {
        title: Some("How was this?".to_string()),
        items: vec![
            make_feedback_item(
                app_event_tx.clone(),
                "bug",
                "Crash, error message, hang, or broken UI/behavior.",
                FeedbackCategory::Bug,
            ),
            make_feedback_item(
                app_event_tx.clone(),
                "bad result",
                "Output was off-target, incorrect, incomplete, or unhelpful.",
                FeedbackCategory::BadResult,
            ),
            make_feedback_item(
                app_event_tx.clone(),
                "good result",
                "Helpful, correct, high‑quality, or delightful result worth celebrating.",
                FeedbackCategory::GoodResult,
            ),
            make_feedback_item(
                app_event_tx.clone(),
                "safety check",
                "Benign usage blocked due to safety checks or refusals.",
                FeedbackCategory::SafetyCheck,
            ),
            make_feedback_item(
                app_event_tx,
                "other",
                "Slowness, feature suggestion, UX feedback, or anything else.",
                FeedbackCategory::Other,
            ),
        ],
        ..Default::default()
    }
}

fn make_feedback_item(
    app_event_tx: AppEventSender,
    name: &str,
    description: &str,
    category: FeedbackCategory,
) -> super::SelectionItem {
    let action: super::SelectionAction = Box::new(move |_sender: &AppEventSender| {
        app_event_tx.send(AppEvent::OpenFeedbackConsent { category });
    });
    super::SelectionItem {
        name: name.to_string(),
        description: Some(description.to_string()),
        actions: vec![action],
        dismiss_on_select: true,
        ..Default::default()
    }
}
```

### 测试代码（来自 tests.rs）

```rust
// tui/src/chatwidget/tests.rs
#[tokio::test]
async fn feedback_selection_popup_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;

    // Open the feedback category selection popup via slash command.
    chat.dispatch_command(SlashCommand::Feedback);

    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("feedback_selection_popup", popup);
}
```

### 快照输出解析

```
  How was this?

› 1. bug           Crash, error message, hang, or broken UI/behavior.
  2. bad result    Output was off-target, incorrect, incomplete, or unhelpful.
  3. good result   Helpful, correct, high‑quality, or delightful result worth
                   celebrating.
  4. safety check  Benign usage blocked due to safety checks or refusals.
  5. other         Slowness, feature suggestion, UX feedback, or anything
                   else.
```

UI 元素分析：
- **标题**：`How was this?` - 简洁友好的询问
- **选项格式**：`序号. 名称` + 描述文本
- **当前选中**：使用 `›` 符号指示当前选中项（第1项 bug）
- **描述对齐**：描述文本与名称保持视觉对齐
- **长文本处理**：`good result` 和 `other` 的描述跨多行显示，保持缩进对齐

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/feedback_view.rs` | 反馈视图实现，包含反馈选择弹窗逻辑（约第 426-498 行） |
| `codex-rs/tui/src/bottom_pane/list_selection_view.rs` | 列表选择视图的通用实现 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 快照测试定义（约第 8122-8130 行） |
| `codex-rs/tui/src/app_event.rs` | FeedbackCategory 枚举和 AppEvent::OpenFeedbackConsent 定义 |
| `codex-rs/tui/src/slash_commands.rs` | SlashCommand::Feedback 定义 |
| `codex-rs/tui/src/chatwidget/snapshots/codex_tui__chatwidget__tests__feedback_selection_popup.snap` | 本快照文件 |

### 相关测试函数

- `feedback_selection_popup_snapshot()` - 本测试
- `feedback_upload_consent_popup_snapshot()` - 下一步流程测试
- `feedback_good_result_consent_popup_includes_connectivity_diagnostics_filename()` - GoodResult 特殊处理测试

## 依赖与外部交互

### 依赖模块

1. **list_selection_view 模块**
   - `SelectionViewParams` - 选择视图参数
   - `SelectionItem` - 选择项定义
   - `SelectionAction` - 选择动作回调
   - `ListSelectionView` - 列表选择视图渲染

2. **FeedbackCategory 枚举**
   ```rust
   pub enum FeedbackCategory {
       Bug,           // 程序错误
       BadResult,     // 结果不符合预期
       GoodResult,    // 正面反馈
       SafetyCheck,   // 安全检查相关问题
       Other,         // 其他
   }
   ```

3. **AppEvent 系统**
   ```rust
   pub enum AppEvent {
       OpenFeedbackConsent { category: FeedbackCategory },
       // ...
   }
   ```

4. **ratatui**
   - 用于终端 UI 渲染

### 触发方式

- 用户输入 `/feedback` 斜杠命令
- 通过 `chat.dispatch_command(SlashCommand::Feedback)` 触发

## 风险、边界与改进建议

### 潜在风险

1. **选项理解差异**
   - 用户可能对 "bad result" 和 "bug" 的区别理解不清
   - "safety check" 类别可能不够直观

2. **本地化缺失**
   - 当前所有文本都是硬编码的英文
   - 不支持国际化

3. **选项顺序偏见**
   - 第一个选项（bug）可能获得更多选择
   - 负面选项（bug, bad result）在正面选项（good result）之前

### 边界情况

| 场景 | 预期行为 |
|------|---------|
| 反馈功能被禁用 | 显示 "Sending feedback is disabled" 提示 |
| 用户按 Esc | 关闭弹窗，取消反馈流程 |
| 用户输入数字键 | 快速选择对应选项 |
| 用户输入方向键 | 在选项间移动选择 |
| 用户按 Enter | 确认当前选中选项 |

### 改进建议

1. **用户体验优化**
   - 考虑将 "good result" 放在更显眼的位置（如第一位或添加特殊标记）
   - 添加图标或颜色区分不同类别的反馈
   - 添加更详细的选项说明或示例

2. **本地化支持**
   - 将文本提取到资源文件中
   - 支持多语言显示

3. **快捷操作增强**
   - 显示每个选项的快捷键提示
   - 支持首字母快速跳转

4. **数据收集优化**
   - 考虑添加可选的详细分类（如 bug 可细分为 crash, hang, UI 等）
   - 记录用户选择反馈类型的耗时

5. **测试覆盖**
   - 添加键盘导航测试
   - 测试反馈禁用状态的弹窗显示
   - 测试长描述的换行和缩进
