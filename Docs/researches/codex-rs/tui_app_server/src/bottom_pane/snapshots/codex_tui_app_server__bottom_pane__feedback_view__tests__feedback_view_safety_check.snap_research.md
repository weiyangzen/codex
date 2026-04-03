# Feedback View - Safety Check 快照研究

## 场景与职责

该快照展示了 **FeedbackNoteView** 组件在 **SafetyCheck（安全检查）** 反馈类别下的 UI 渲染效果。这是 Codex TUI 应用服务器中用户反馈收集流程的重要组成部分，专门用于收集关于 AI 安全审查误报（false positives）的反馈——即良性使用被安全审查阻止的情况。

**使用场景：**
- 用户的正常、无害请求被 AI 的安全检查机制拒绝
- 用户认为这是一个误报（false positive），应该被允许
- 用户通过快捷键或菜单触发反馈功能
- 系统显示反馈类别选择弹窗后，用户选择 "safety check" 类别
- 进入此视图收集用户对安全审查误报的详细描述

**核心职责：**
- 提供简洁的文本输入界面，收集用户对安全审查误报的补充说明
- 显示类别特定的标题和专门的占位提示文本（与其他类别不同）
- 支持可选（optional）描述输入，用户可以直接按 Enter 跳过
- 作为 BottomPaneView 栈的一部分，支持 Esc 取消操作
- 提交后提供 GitHub Issue 链接，方便用户报告安全审查问题

## 功能点目的

**1. 安全审查误报收集（Safety False Positive Collection）**
- 允许用户报告 AI 安全审查的误判情况
- 收集的反馈将上传至服务器，帮助安全团队改进审查机制
- 帮助减少误报，提高用户体验

**2. 专门的引导文本**
- 与其他类别不同，SafetyCheck 使用专门的占位文本：
  - "(optional) Share what was refused and why it should have been allowed"
- 明确引导用户描述被拒绝的内容以及为什么应该被允许
- 帮助安全团队更好地理解上下文

**3. 后续跟进支持**
- 提交后，外部用户会看到 GitHub Issue 链接（`BASE_CLI_BUG_ISSUE_URL`）
- OpenAI 内部员工会看到内部反馈链接（`CODEX_FEEDBACK_INTERNAL_URL`）
- 链接自动包含 thread ID，便于安全团队追踪问题上下文

## 具体技术实现

**渲染结构（从快照反推）：**
```
▌ Tell us more (safety check)   <- 标题行（青色分隔符 + 加粗标题）
▌                               <- 空行/输入区域顶部
▌ (optional) Share what was refused and why it should b  <- 占位提示（被截断）

Press enter to confirm or esc to go back  <- 底部操作提示
```

**关键渲染逻辑：**
- 标题通过 `feedback_title_and_placeholder()` 函数根据类别动态生成
- `SafetyCheck` 类别对应标题："Tell us more (safety check)"
- 占位文本："(optional) Share what was refused and why it should have been allowed"
- 使用青色（cyan）的 "▌ " 作为行首分隔符（`gutter()` 函数）
- 标题使用粗体样式（`.bold()`）
- 注意：快照中占位文本被截断为 "...should b"，因为宽度限制（60字符）

**输入处理：**
- `handle_key_event()` 处理键盘输入
- `Enter` 键：提交反馈（`submit()` 方法）
- `Esc` 键：取消并关闭视图（`on_ctrl_c()`）
- 其他键：转发到 `TextArea` 组件处理文本输入

**反馈提交流程：**
1. 调用 `submit()` 方法
2. 获取用户输入文本（trim 后为空则设为 None）
3. 调用 `snapshot.upload_feedback()` 上传反馈
   - classification: "safety_check"
   - reason: 用户输入（可选）
   - include_logs: 根据用户之前的选择
   - attachment_paths: rollout 日志文件路径（如果 include_logs 为 true）
4. 上传成功后，在聊天记录中插入确认消息和后续链接

**SafetyCheck 类别的特殊处理：**
- SafetyCheck 使用专门的占位文本，引导用户描述被拒绝的内容
- 会生成 GitHub Issue 链接（通过 `issue_url_for_category()`）
- 链接格式：`https://github.com/openai/codex/issues/new?template=3-cli.yml&steps=Uploaded%20thread:%20{thread_id}`

## 关键代码路径与文件引用

**主要实现文件：**
- `codex-rs/tui_app_server/src/bottom_pane/feedback_view.rs` - FeedbackNoteView 完整实现

**关键函数和类型：**

```rust
// 视图结构定义（行 49-61）
pub(crate) struct FeedbackNoteView {
    category: FeedbackCategory,
    snapshot: codex_feedback::FeedbackSnapshot,
    rollout_path: Option<PathBuf>,
    app_event_tx: AppEventSender,
    include_logs: bool,
    feedback_audience: FeedbackAudience,
    textarea: TextArea,
    textarea_state: RefCell<TextAreaState>,
    complete: bool,
}

// 标题和占位文本生成 - SafetyCheck 特殊处理（行 360-383）
fn feedback_title_and_placeholder(category: FeedbackCategory) -> (String, String) {
    match category {
        FeedbackCategory::SafetyCheck => (
            "Tell us more (safety check)".to_string(),
            "(optional) Share what was refused and why it should have been allowed".to_string(),
        ),
        // ... 其他类别使用通用占位文本
    }
}

// 反馈分类映射（行 385-393）
fn feedback_classification(category: FeedbackCategory) -> &'static str {
    match category {
        FeedbackCategory::SafetyCheck => "safety_check",
        // ...
    }
}

// Issue URL 生成（行 395-415）
fn issue_url_for_category(
    category: FeedbackCategory,
    thread_id: &str,
    feedback_audience: FeedbackAudience,
) -> Option<String> {
    match category {
        FeedbackCategory::Bug
        | FeedbackCategory::BadResult
        | FeedbackCategory::SafetyCheck
        | FeedbackCategory::Other => Some(match feedback_audience {
            FeedbackAudience::OpenAiEmployee => slack_feedback_url(thread_id),
            FeedbackAudience::External => {
                format!("{BASE_CLI_BUG_ISSUE_URL}&steps=Uploaded%20thread:%20{thread_id}")
            }
        }),
        FeedbackCategory::GoodResult => None,
    }
}
```

**相关常量：**
- `BASE_CLI_BUG_ISSUE_URL` (行 32-33): `https://github.com/openai/codex/issues/new?template=3-cli.yml`
- `CODEX_FEEDBACK_INTERNAL_URL` (行 35): `http://go/codex-feedback-internal`

**测试代码位置：**
- 测试函数：`feedback_view_safety_check()` (行 670-675)
- 使用 `make_view(FeedbackCategory::SafetyCheck)` 创建测试视图
- 渲染宽度：60 字符

**事件类型定义：**
- `FeedbackCategory` 枚举 (app_event.rs 行 488-495):
  ```rust
  pub(crate) enum FeedbackCategory {
      BadResult,
      GoodResult,
      Bug,
      SafetyCheck,
      Other,
  }
  ```

**反馈选择参数构建（行 426-465）：**
```rust
pub(crate) fn feedback_selection_params(
    app_event_tx: AppEventSender,
) -> super::SelectionViewParams {
    super::SelectionViewParams {
        title: Some("How was this?".to_string()),
        items: vec![
            // ...
            make_feedback_item(
                app_event_tx.clone(),
                "safety check",
                "Benign usage blocked due to safety checks or refusals.",
                FeedbackCategory::SafetyCheck,
            ),
            // ...
        ],
        ..Default::default()
    }
}
```

## 依赖与外部交互

**内部依赖：**
- `codex_feedback::FeedbackSnapshot` - 反馈数据快照和上传功能
- `codex_feedback::FeedbackDiagnostics` - 连接诊断信息
- `crate::app_event::AppEvent` - 应用事件系统
- `crate::bottom_pane::textarea::TextArea` - 文本输入组件
- `crate::render::renderable::Renderable` - 渲染接口

**外部 crate：**
- `ratatui` - TUI 渲染框架（Buffer, Rect, Paragraph, Line, Span 等）
- `crossterm` - 终端输入处理（KeyCode, KeyEvent, KeyModifiers）

**与反馈系统的交互：**
- 通过 `snapshot.upload_feedback()` 上传反馈数据
- 上传内容包括：分类、用户描述、日志文件、会话来源等
- 上传成功后，通过 `AppEvent::InsertHistoryCell` 在聊天记录中显示确认信息

**与安全团队的集成：**
- SafetyCheck 类别的反馈会路由到安全团队
- 反馈分类 "safety_check" 帮助团队快速识别安全相关反馈
- 用户描述帮助团队理解误报的上下文

**与底部面板的集成：**
- `FeedbackNoteView` 实现 `BottomPaneView` trait
- 通过 `BottomPane::push_view()` 压入视图栈
- 支持 `CancellationEvent` 处理 Esc 取消操作

## 风险、边界与改进建议

**潜在风险：**

1. **隐私风险**
   - 日志文件可能包含敏感信息（文件路径、代码内容、环境变量等）
   - 缓解措施：用户必须显式同意（"Upload logs?" 弹窗）才能包含日志

2. **反馈丢失风险**
   - 用户输入在提交前如果程序崩溃会丢失
   - 缓解措施：视图相对简单，输入通常很短

3. **内部 URL 泄露风险**
   - `CODEX_FEEDBACK_INTERNAL_URL` 是内部链接，不应暴露给外部用户
   - 缓解措施：`FeedbackAudience` 枚举严格控制受众，代码注释明确警告

4. **误报报告不足**
   - 用户可能不知道如何描述误报情况
   - 专门的占位文本有助于引导用户

**边界情况：**

1. **空输入处理**
   - 用户可以直接按 Enter 提交空描述
   - 代码正确处理：`reason_opt` 为 None 时仍会上传反馈
   - 但安全团队可能难以处理没有描述的误报报告

2. **长文本输入**
   - `input_height()` 方法限制最大高度为 8 行
   - 文本区域支持多行输入和自动换行

3. **上传失败处理**
   - `submit()` 方法匹配 `upload_feedback()` 的 Result
   - 失败时通过 `AppEvent::InsertHistoryCell` 显示错误消息

4. **不同受众的不同行为**
   - OpenAI 员工和外部用户看到不同的后续链接
   - 通过 `feedback_audience` 字段控制

5. **连接诊断信息**
   - 如果存在连接诊断信息，会在上传同意弹窗中显示
   - SafetyCheck 类别会显示连接诊断（与 GoodResult 不同）

**改进建议：**

1. **更详细的引导**
   - 可考虑添加更多引导，帮助用户描述误报
   - 例如："请描述您的请求内容、预期的安全审查结果、以及为什么这是误报"

2. **上下文自动捕获**
   - 可考虑自动捕获被拒绝的请求内容
   - 减少用户手动描述的负担

3. **误报类型分类**
   - 可考虑添加误报类型选择（如：过度敏感、上下文误解等）
   - 帮助安全团队更快定位问题

4. **快照测试扩展**
   - 当前快照仅测试初始渲染状态
   - 可添加测试：用户输入文本后的渲染、提交后的历史记录渲染等

5. **安全反馈分析**
   - 定期分析 SafetyCheck 类别的反馈
   - 识别常见的误报模式，改进安全审查机制

6. **占位文本截断问题**
   - 当前快照显示占位文本在 60 字符宽度下被截断
   - 可考虑缩短占位文本或优化换行逻辑
