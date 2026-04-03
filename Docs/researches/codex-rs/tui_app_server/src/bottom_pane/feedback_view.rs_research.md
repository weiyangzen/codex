# feedback_view.rs 研究文档

## 场景与职责

`feedback_view.rs` 是 Codex TUI 应用中负责用户反馈收集和上传的核心模块。它实现了一套完整的反馈流程 UI，包括：

1. **反馈类别选择**：提供多种反馈类型（Bug、Bad Result、Good Result、Safety Check、Other）
2. **日志上传确认**：询问用户是否同意上传会话日志用于诊断
3. **反馈备注输入**：允许用户输入可选的详细描述
4. **反馈上传**：将反馈数据（分类、备注、日志等）上传到服务器
5. **后续引导**：根据反馈类别提供 GitHub Issue 链接或内部反馈渠道

该模块主要服务于 OpenAI 收集 Codex CLI 的使用反馈，区分内部员工和外部用户的不同处理流程。

## 功能点目的

### 1. 反馈备注视图（FeedbackNoteView）
- **目的**：收集用户反馈的详细描述并执行上传
- **关键字段**：
  - `category`: 反馈类别
  - `snapshot`: 反馈快照（包含会话信息、诊断数据等）
  - `rollout_path`: 日志文件路径
  - `include_logs`: 是否包含日志
  - `feedback_audience`: 目标受众（内部员工/外部用户）
  - `textarea`: 备注输入框

### 2. 反馈类别枚举（FeedbackCategory）
- **定义位置**：`app_event.rs`
- **类别**：
  - `Bug`: 崩溃、错误、挂起或 UI/行为异常
  - `BadResult`: 输出不准确、不完整或无帮助
  - `GoodResult`: 有帮助、正确、高质量的结果
  - `SafetyCheck`: 安全检查误报
  - `Other`: 其他反馈（性能、建议等）

### 3. 受众区分（FeedbackAudience）
- **目的**：根据用户类型提供不同的后续引导
- **变体**：
  - `OpenAiEmployee`: 内部员工，使用内部 Slack 链接
  - `External`: 外部用户，使用 GitHub Issue 链接

### 4. 反馈选择参数构建
- **`feedback_selection_params`**: 构建类别选择弹窗
- **`feedback_upload_consent_params`**: 构建日志上传确认弹窗
- **`feedback_disabled_params`**: 反馈禁用时的提示弹窗

### 5. 诊断信息显示
- **目的**：在反馈时收集连接诊断信息，帮助排查问题
- **触发条件**：非 GoodResult 类别且存在诊断信息时显示

## 具体技术实现

### 关键数据结构

```rust
/// 反馈受众类型
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum FeedbackAudience {
    OpenAiEmployee,
    External,
}

/// 反馈备注输入视图
pub(crate) struct FeedbackNoteView {
    category: FeedbackCategory,
    snapshot: codex_feedback::FeedbackSnapshot,
    rollout_path: Option<PathBuf>,
    app_event_tx: AppEventSender,
    include_logs: bool,
    feedback_audience: FeedbackAudience,
    
    // UI 状态
    textarea: TextArea,
    textarea_state: RefCell<TextAreaState>,
    complete: bool,
}
```

### 提交流程

```rust
fn submit(&mut self) {
    let note = self.textarea.text().trim().to_string();
    let reason_opt = if note.is_empty() { None } else { Some(note.as_str()) };
    
    // 确定附件路径
    let attachment_paths = if self.include_logs {
        self.rollout_path.iter().cloned().collect::<Vec<_>>()
    } else {
        Vec::new()
    };
    
    let classification = feedback_classification(self.category);
    let mut thread_id = self.snapshot.thread_id.clone();
    
    // 执行上传
    let result = self.snapshot.upload_feedback(
        classification,
        reason_opt,
        self.include_logs,
        &attachment_paths,
        Some(SessionSource::Cli),
        /*logs_override*/ None,
    );
    
    match result {
        Ok(()) => {
            // 显示成功消息和后续链接
            let prefix = if self.include_logs { 
                "• Feedback uploaded." 
            } else { 
                "• Feedback recorded (no logs)." 
            };
            let issue_url = issue_url_for_category(self.category, &thread_id, self.feedback_audience);
            
            // 根据受众类型构建不同的提示信息
            let mut lines = vec![Line::from(match issue_url.as_ref() { ... })];
            
            // 内部员工：显示 Slack 链接和 go 链接
            // 外部用户：显示 GitHub Issue 链接和 Thread ID
            match issue_url { ... }
            
            self.app_event_tx.send(AppEvent::InsertHistoryCell(Box::new(
                history_cell::PlainHistoryCell::new(lines),
            )));
        }
        Err(e) => {
            // 显示错误消息
            self.app_event_tx.send(AppEvent::InsertHistoryCell(Box::new(
                history_cell::new_error_event(format!("Failed to upload feedback: {e}")),
            )));
        }
    }
    self.complete = true;
}
```

### 反馈分类映射

```rust
fn feedback_classification(category: FeedbackCategory) -> &'static str {
    match category {
        FeedbackCategory::BadResult => "bad_result",
        FeedbackCategory::GoodResult => "good_result",
        FeedbackCategory::Bug => "bug",
        FeedbackCategory::SafetyCheck => "safety_check",
        FeedbackCategory::Other => "other",
    }
}
```

### Issue URL 生成

```rust
fn issue_url_for_category(
    category: FeedbackCategory,
    thread_id: &str,
    feedback_audience: FeedbackAudience,
) -> Option<String> {
    match category {
        // Bug、BadResult、SafetyCheck、Other 提供后续链接
        FeedbackCategory::Bug
        | FeedbackCategory::BadResult
        | FeedbackCategory::SafetyCheck
        | FeedbackCategory::Other => Some(match feedback_audience {
            FeedbackAudience::OpenAiEmployee => slack_feedback_url(thread_id),
            FeedbackAudience::External => {
                format!("{BASE_CLI_BUG_ISSUE_URL}&steps=Uploaded%20thread:%20{thread_id}")
            }
        }),
        // GoodResult 不提供链接
        FeedbackCategory::GoodResult => None,
    }
}

fn slack_feedback_url(_thread_id: &str) -> String {
    CODEX_FEEDBACK_INTERNAL_URL.to_string()  // "http://go/codex-feedback-internal"
}
```

### 反馈选择弹窗参数

```rust
pub(crate) fn feedback_selection_params(
    app_event_tx: AppEventSender,
) -> super::SelectionViewParams {
    super::SelectionViewParams {
        title: Some("How was this?".to_string()),
        items: vec![
            make_feedback_item(app_event_tx.clone(), "bug", "Crash, error message...", FeedbackCategory::Bug),
            make_feedback_item(app_event_tx.clone(), "bad result", "Output was off-target...", FeedbackCategory::BadResult),
            make_feedback_item(app_event_tx.clone(), "good result", "Helpful, correct...", FeedbackCategory::GoodResult),
            make_feedback_item(app_event_tx.clone(), "safety check", "Benign usage blocked...", FeedbackCategory::SafetyCheck),
            make_feedback_item(app_event_tx, "other", "Slowness, feature suggestion...", FeedbackCategory::Other),
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

### 上传确认弹窗参数

```rust
pub(crate) fn feedback_upload_consent_params(
    app_event_tx: AppEventSender,
    category: FeedbackCategory,
    rollout_path: Option<std::path::PathBuf>,
    feedback_diagnostics: &FeedbackDiagnostics,
) -> super::SelectionViewParams {
    // 构建头部：列出将要上传的文件
    let mut header_lines: Vec<Box<dyn crate::render::renderable::Renderable>> = vec![
        Line::from("Upload logs?".bold()).into(),
        Line::from("").into(),
        Line::from("The following files will be sent:".dim()).into(),
        Line::from(vec!["  • ".into(), "codex-logs.log".into()]).into(),
    ];
    
    // 添加 rollout 文件
    if let Some(path) = rollout_path.as_deref() { ... }
    
    // 添加诊断文件（如果存在）
    if !feedback_diagnostics.is_empty() { ... }
    
    // 添加连接诊断详情（仅非 GoodResult）
    if should_show_feedback_connectivity_details(category, feedback_diagnostics) { ... }
    
    // 构建 Yes/No 选项
    super::SelectionViewParams {
        items: vec![
            SelectionItem { name: "Yes".to_string(), ... },
            SelectionItem { name: "No".to_string(), ... },
        ],
        header: Box::new(crate::render::renderable::ColumnRenderable::with(header_lines)),
        ..Default::default()
    }
}
```

### 诊断信息显示判定

```rust
pub(crate) fn should_show_feedback_connectivity_details(
    category: FeedbackCategory,
    diagnostics: &FeedbackDiagnostics,
) -> bool {
    // GoodResult 不显示诊断信息
    // 无诊断信息时不显示
    category != FeedbackCategory::GoodResult && !diagnostics.is_empty()
}
```

## 关键代码路径与文件引用

### 当前文件关键路径
- `FeedbackNoteView::new()` (行 64-83): 创建视图
- `submit()` (行 85-172): 提交反馈
- `BottomPaneView::handle_key_event()` (行 176-199): 键盘事件处理
- `Renderable::render()` (行 244-333): 渲染逻辑
- `feedback_title_and_placeholder()` (行 360-383): 标题和占位符
- `feedback_classification()` (行 385-393): 分类映射
- `issue_url_for_category()` (行 395-415): Issue URL 生成
- `slack_feedback_url()` (行 421-423): 内部反馈链接
- `feedback_selection_params()` (行 426-465): 类别选择弹窗参数
- `feedback_upload_consent_params()` (行 501-588): 上传确认弹窗参数
- `should_show_feedback_connectivity_details()` (行 349-354): 诊断信息显示判定

### 调用方
- `codex-rs/tui_app_server/src/chatwidget.rs`:
  - `open_feedback()` (行 1893-1900): 打开反馈备注视图
  - `show_feedback_note()` (行 1902-1929): 显示反馈备注视图
  - `open_feedback_consent()` (行 1931-1941): 打开上传确认弹窗
  - 调用 `feedback_selection_params()` 创建类别选择弹窗
  - 调用 `feedback_upload_consent_params()` 创建上传确认弹窗

### 被调用方
- `codex_feedback` crate:
  - `FeedbackSnapshot`: 反馈快照数据
  - `FeedbackDiagnostics`: 诊断信息
  - `upload_feedback()`: 上传方法
- `codex-rs/tui_app_server/src/bottom_pane/textarea.rs`:
  - `TextArea`: 备注输入组件
- `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs`:
  - `SelectionViewParams`: 选择弹窗参数
  - `SelectionItem`: 选择项

### 常量定义
- `BASE_CLI_BUG_ISSUE_URL` (行 32-33): GitHub Issue 模板链接
- `CODEX_FEEDBACK_INTERNAL_URL` (行 35): 内部反馈链接

## 依赖与外部交互

### 依赖模块
| 模块 | 用途 |
|------|------|
| `codex_feedback` | 反馈数据结构和上传功能 |
| `textarea` | 备注输入组件 |
| `bottom_pane_view` | 底部面板视图 trait |
| `app_event` | 应用事件（FeedbackCategory） |
| `app_event_sender` | 事件发送器 |
| `history_cell` | 历史单元格创建 |
| `list_selection_view` | 选择弹窗参数 |
| `popup_consts` | 弹窗常量 |

### 反馈流程
1. **触发**：用户通过 `/feedback` 命令或快捷键触发
2. **类别选择**：显示 `feedback_selection_params` 弹窗
3. **选择处理**：用户选择类别后发送 `OpenFeedbackConsent` 事件
4. **上传确认**：显示 `feedback_upload_consent_params` 弹窗
5. **确认处理**：用户选择 Yes/No 后发送 `OpenFeedbackNote` 事件
6. **备注输入**：显示 `FeedbackNoteView` 收集备注
7. **提交上传**：调用 `upload_feedback` 上传数据
8. **结果展示**：在历史记录中显示成功或失败消息

### 诊断信息收集
- 来源：环境变量检查（HTTP_PROXY、OPENAI_BASE_URL 等）
- 存储：`FeedbackDiagnostics` 附加到 `FeedbackSnapshot`
- 显示：在上传确认弹窗中列出诊断项

## 风险、边界与改进建议

### 风险点

1. **内部链接暴露**
   - 风险：`CODEX_FEEDBACK_INTERNAL_URL` 是内部链接，如果代码泄露可能导致信息泄露
   - 现状：常量名已明确标识为 internal，且仅在 `FeedbackAudience::OpenAiEmployee` 时使用
   - 建议：考虑将内部 URL 移至配置文件或环境变量

2. **日志文件路径安全**
   - 风险：`rollout_path` 可能包含敏感路径信息
   - 现状：仅上传文件内容，路径信息在 UI 中仅显示文件名
   - 建议：确保上传前脱敏处理

3. **上传失败处理**
   - 现状：上传失败仅在历史记录中显示错误消息
   - 风险：用户可能未注意到上传失败
   - 建议：添加更明显的错误提示或重试机制

4. **诊断信息隐私**
   - 风险：诊断信息可能包含敏感环境变量
   - 现状：仅收集与连接相关的变量（HTTP_PROXY、OPENAI_BASE_URL 等）
   - 建议：添加白名单机制，明确允许收集的变量

### 边界情况

1. **空备注**：允许提交空备注，仅上传分类和日志
2. **无日志文件**：`rollout_path` 为 None 时正常处理
3. **无诊断信息**：诊断列表为空时跳过显示
4. **上传超时**：依赖底层 `upload_feedback` 的超时处理
5. **网络异常**：错误信息通过 `InsertHistoryCell` 显示

### 改进建议

1. **反馈预览**
   - 在提交前显示将要上传的数据预览，包括日志摘要

2. **截图附件**
   - 支持用户附加截图，帮助说明问题

3. **反馈历史**
   - 显示用户的历史反馈记录和状态

4. **自动分类**
   - 基于日志内容自动建议反馈类别

5. **匿名反馈**
   - 提供完全匿名反馈选项（不包含 thread_id）

6. **反馈状态跟踪**
   - 提供反馈 ID，允许用户查询处理状态

7. **测试覆盖**
   - 当前有快照测试（`feedback_view_*`），建议添加：
     - 上传成功/失败的单元测试
     - 诊断信息显示逻辑测试
     - URL 生成测试（已完成）

8. **国际化**
   - 当前仅支持英文，考虑添加多语言支持

9. **快捷键优化**
   - 添加 Ctrl+Enter 快速提交
   - 添加 Tab 键在 Yes/No 间切换
