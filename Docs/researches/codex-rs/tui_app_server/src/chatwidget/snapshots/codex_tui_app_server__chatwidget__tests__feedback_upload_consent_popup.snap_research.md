# feedback_upload_consent_popup 快照研究文档

## 场景与职责

此快照测试验证 **tui_app_server** 中反馈功能的**日志上传同意弹出框**渲染。当用户选择了反馈类别（如 bug、bad result 等）后，系统显示此弹出框，询问用户是否同意上传会话日志以协助故障排查。

与 `feedback_good_result_consent_popup` 不同，此测试验证的是通用上传同意弹出框，特别是当存在连接诊断信息时的渲染效果。

## 功能点目的

1. **知情同意**：明确告知用户将要上传的文件清单，确保透明度
2. **隐私保护**：让用户自主选择是否分享日志
3. **诊断辅助**：通过上传的日志帮助开发团队定位和修复问题
4. **连接问题检测**：展示可能影响连接的环境变量诊断信息

## 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/chatwidget/tests.rs` 第 8731-8748 行

```rust
#[tokio::test]
async fn feedback_upload_consent_popup_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;

    chat.show_selection_view(crate::bottom_pane::feedback_upload_consent_params(
        chat.app_event_tx.clone(),
        crate::app_event::FeedbackCategory::Bug,  // 注意：使用 Bug 类别
        chat.current_rollout_path.clone(),
        &codex_feedback::feedback_diagnostics::FeedbackDiagnostics::new(vec![
            codex_feedback::feedback_diagnostics::FeedbackDiagnostic {
                headline: "OPENAI_BASE_URL is set and may affect connectivity.".to_string(),
                details: vec!["OPENAI_BASE_URL = hello".to_string()],
            },
        ]),
    ));

    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("feedback_upload_consent_popup", popup);
}
```

### 与 good_result 测试的关键区别

| 方面 | feedback_upload_consent_popup | feedback_good_result_consent_popup |
|------|------------------------------|-----------------------------------|
| 反馈类别 | `FeedbackCategory::Bug` | `FeedbackCategory::GoodResult` |
| 诊断信息显示 | 显示（Bug 类别会显示诊断） | 测试强制传入诊断 |
| 使用场景 | 问题报告时的标准流程 | 正面反馈时的特殊处理 |

### 核心实现逻辑

1. **弹出框参数构建** (`feedback_upload_consent_params`):
   - 位于 `codex-rs/tui_app_server/src/bottom_pane/feedback_view.rs` 第 501-588 行

2. **诊断信息显示逻辑**:
   ```rust
   if should_show_feedback_connectivity_details(category, feedback_diagnostics) {
       header_lines.push(Line::from("").into());
       header_lines.push(Line::from("Connectivity diagnostics".bold()).into());
       for diagnostic in feedback_diagnostics.diagnostics() {
           header_lines.push(
               Line::from(vec!["  - ".into(), diagnostic.headline.clone().into()]).into()
           );
           for detail in &diagnostic.details {
               header_lines.push(
                   Line::from(vec!["    - ".dim(), detail.clone().into()]).into()
               );
           }
       }
   }
   ```

3. **文件列表构建**:
   ```rust
   let mut header_lines: Vec<Box<dyn Renderable>> = vec![
       Line::from("Upload logs?".bold()).into(),
       Line::from("").into(),
       Line::from("The following files will be sent:".dim()).into(),
       Line::from(vec!["  • ".into(), "codex-logs.log".into()]).into(),
   ];
   // 可选添加 rollout 文件
   // 可选添加诊断文件
   ```

4. **选择项定义**:
   - "Yes"：分享日志用于故障排查
   - "No"：不上传日志，仅记录反馈

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试用例定义 |
| `codex-rs/tui_app_server/src/bottom_pane/feedback_view.rs` | 上传同意参数构建和视图实现 |
| `codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs` | 选择弹出框渲染逻辑 |
| `codex-rs/tui_app_server/src/app_event.rs` | 应用事件定义（FeedbackCategory 等） |

### 关键函数

```rust
// 构建上传同意弹出框参数
pub(crate) fn feedback_upload_consent_params(
    app_event_tx: AppEventSender,
    category: FeedbackCategory,
    rollout_path: Option<std::path::PathBuf>,
    feedback_diagnostics: &FeedbackDiagnostics,
) -> super::SelectionViewParams

// 判断是否显示连接诊断详情
pub(crate) fn should_show_feedback_connectivity_details(
    category: FeedbackCategory,
    diagnostics: &FeedbackDiagnostics,
) -> bool
```

## 依赖与外部交互

### 外部 crate 依赖
- **codex-feedback**: 提供诊断信息收集
  - `FeedbackDiagnostics`：诊断集合
  - `FEEDBACK_DIAGNOSTICS_ATTACHMENT_FILENAME`：诊断文件名常量

### 内部事件流
```
用户选择 "Yes"
    └── SelectionAction 回调
            └── AppEvent::OpenFeedbackNote { category, include_logs: true }
                    └── 显示反馈备注输入视图

用户选择 "No"
    └── SelectionAction 回调
            └── AppEvent::OpenFeedbackNote { category, include_logs: false }
                    └── 显示反馈备注输入视图（不附日志）
```

## 风险、边界与改进建议

### 潜在风险

1. **诊断信息泄露**：
   - 环境变量可能包含敏感信息（如代理认证信息）
   - 缓解措施：诊断收集时应过滤敏感字段

2. **用户困惑**：
   - 连接诊断信息对普通用户可能过于技术化
   - 需要平衡技术细节和可读性

### 边界情况

1. **无 rollout 文件**：
   - `current_rollout_path` 为 `None` 时，仅显示日志文件
   
2. **空诊断信息**：
   - 当 `FeedbackDiagnostics` 为空时，不显示诊断部分

3. **长诊断详情**：
   - 测试验证了多行诊断详情的渲染
   - 使用缩进保持层次结构清晰

4. **不同反馈类别**：
   - Bug/ BadResult/ SafetyCheck/ Other：显示诊断信息
   - GoodResult：不显示诊断信息（按设计）

### 改进建议

1. **诊断信息过滤**：
   - 添加敏感信息检测和脱敏处理
   - 对代理 URL 中的认证信息进行掩码

2. **诊断信息解释**：
   - 为每个诊断项添加简短说明，解释其含义
   - 提供链接到帮助文档

3. **文件大小提示**：
   - 显示将要上传文件的大小
   - 让用户了解数据传输量

4. **预览功能**：
   - 添加"预览日志"选项，让用户查看将要上传的内容
   - 增加透明度和用户信任

5. **批量反馈优化**：
   - 如果用户短时间内多次反馈，考虑缓存同意选择
   - 避免重复询问同一用户

### 相关测试

- `feedback_selection_popup_snapshot`：前置的选择类别测试
- `feedback_good_result_consent_popup_snapshot`：良好结果的同意弹出框
- `feedback_view_with_connectivity_diagnostics`：带诊断的反馈视图
- `feedback_view_bug` / `feedback_view_bad_result` 等：各类别反馈视图
