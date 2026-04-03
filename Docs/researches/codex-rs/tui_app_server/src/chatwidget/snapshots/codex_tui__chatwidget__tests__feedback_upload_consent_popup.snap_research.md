# 研究文档：反馈上传同意弹出框（含连接诊断信息）

## 场景与职责

本快照测试验证 Codex TUI 的用户反馈系统中，当用户选择 "bug" 反馈类型后的日志上传确认界面。与 "good result" 反馈不同，bug 反馈会在弹窗中**显示详细的连接诊断信息**，帮助开发团队诊断问题。

这是用户反馈工作流中的第三步：
1. 用户触发 `/feedback` 斜杠命令
2. 选择 "bug" 反馈类型
3. **显示日志上传同意弹窗**（本快照）
4. 用户选择是否上传日志
5. 显示反馈备注输入界面

## 功能点目的

1. **诊断信息展示**：对于问题类反馈，展示连接诊断信息帮助问题定位
2. **透明数据收集**：明确告知用户将上传的文件和诊断信息内容
3. **用户同意机制**：在收集可能敏感的诊断数据前获得用户明确同意
4. **差异化信息展示**：根据反馈类型决定是否展示技术诊断信息

## 具体技术实现

### 核心数据结构

```rust
// codex_feedback::feedback_diagnostics
pub struct FeedbackDiagnostic {
    pub headline: String,      // 诊断标题
    pub details: Vec<String>,  // 详细信息列表
}

pub struct FeedbackDiagnostics {
    diagnostics: Vec<FeedbackDiagnostic>,
}

pub const FEEDBACK_DIAGNOSTICS_ATTACHMENT_FILENAME: &str = 
    "codex-connectivity-diagnostics.txt";
```

### 诊断信息显示判定

```rust
// bottom_pane/feedback_view.rs
pub(crate) fn should_show_feedback_connectivity_details(
    category: FeedbackCategory,
    diagnostics: &FeedbackDiagnostics,
) -> bool {
    category != FeedbackCategory::GoodResult && !diagnostics.is_empty()
}
```

### 日志上传同意弹窗参数构建

```rust
// bottom_pane/feedback_view.rs
pub(crate) fn feedback_upload_consent_params(
    app_event_tx: AppEventSender,
    category: FeedbackCategory,
    rollout_path: Option<std::path::PathBuf>,
    feedback_diagnostics: &FeedbackDiagnostics,
) -> super::SelectionViewParams {
    // ...
    
    // Build header listing files that would be sent
    let mut header_lines: Vec<Box<dyn Renderable>> = vec![
        Line::from("Upload logs?".bold()).into(),
        Line::from("").into(),
        Line::from("The following files will be sent:".dim()).into(),
        Line::from(vec!["  • ".into(), "codex-logs.log".into()]).into(),
    ];
    
    // 添加诊断文件
    if !feedback_diagnostics.is_empty() {
        header_lines.push(
            Line::from(vec![
                "  • ".into(),
                FEEDBACK_DIAGNOSTICS_ATTACHMENT_FILENAME.into(),
            ])
            .into(),
        );
    }
    
    // 关键：Bug 类型会显示详细的连接诊断信息
    if should_show_feedback_connectivity_details(category, feedback_diagnostics) {
        header_lines.push(Line::from("").into());
        header_lines.push(Line::from("Connectivity diagnostics".bold()).into());
        for diagnostic in feedback_diagnostics.diagnostics() {
            header_lines
                .push(Line::from(vec!["  - ".into(), diagnostic.headline.clone().into()]).into());
            for detail in &diagnostic.details {
                header_lines.push(Line::from(vec!["    - ".dim(), detail.clone().into()]).into());
            }
        }
    }
    // ...
}
```

### 测试代码（来自 tests.rs）

```rust
// tui/src/chatwidget/tests.rs
#[tokio::test]
async fn feedback_upload_consent_popup_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;

    chat.show_selection_view(crate::bottom_pane::feedback_upload_consent_params(
        chat.app_event_tx.clone(),
        crate::app_event::FeedbackCategory::Bug,  // 关键：Bug 类型
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

### 快照输出解析

```
  Upload logs?

  The following files will be sent:
    • codex-logs.log
    • codex-connectivity-diagnostics.txt

  Connectivity diagnostics
    - OPENAI_BASE_URL is set and may affect connectivity.
      - OPENAI_BASE_URL = hello

› 1. Yes  Share the current Codex session logs with the team for
          troubleshooting.
  2. No

  Press enter to confirm or esc to go back
```

关键观察：
- 文件列表包含日志文件和诊断文件
- **显示 "Connectivity diagnostics" 部分**，包含：
  - 诊断标题（headline）
  - 详细信息（details），带缩进层级
- 与 `feedback_good_result_consent_popup` 形成对比

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/feedback_view.rs` | 反馈视图实现，包含日志上传同意弹窗逻辑（约第 500-588 行） |
| `codex-rs/tui/src/bottom_pane/list_selection_view.rs` | 列表选择视图的通用实现 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 快照测试定义（约第 8133-8150 行） |
| `codex-rs/tui/src/app_event.rs` | FeedbackCategory 枚举定义 |
| `codex-feedback/src/feedback_diagnostics.rs` | 反馈诊断数据结构 |
| `codex-rs/tui/src/chatwidget/snapshots/codex_tui__chatwidget__tests__feedback_upload_consent_popup.snap` | 本快照文件 |

### 相关测试函数

- `feedback_upload_consent_popup_snapshot()` - 本测试
- `feedback_good_result_consent_popup_includes_connectivity_diagnostics_filename()` - 对比测试（GoodResult 类型）
- `feedback_selection_popup_snapshot()` - 上一步流程测试

## 依赖与外部交互

### 依赖模块

1. **codex_feedback::feedback_diagnostics**
   - `FeedbackDiagnostics` - 诊断信息集合
   - `FeedbackDiagnostic` - 单个诊断项
   - `FEEDBACK_DIAGNOSTICS_ATTACHMENT_FILENAME` - 诊断文件名常量

2. **FeedbackCategory 枚举**
   ```rust
   pub enum FeedbackCategory {
       Bug,           // 本测试使用的类型
       BadResult,
       GoodResult,    // 不显示诊断详情
       SafetyCheck,
       Other,
   }
   ```

3. **ratatui**
   - 用于终端 UI 渲染

### 诊断信息来源

典型的连接诊断信息包括：
- 代理环境变量设置（HTTP_PROXY, HTTPS_PROXY）
- OpenAI API 基础 URL 覆盖（OPENAI_BASE_URL）
- 其他可能影响连接的环境配置

### 外部服务交互

- 如果选择 "Yes"，日志和诊断信息通过 `codex_feedback` crate 上传
- 上传成功后可能显示 GitHub issue 链接

## 风险、边界与改进建议

### 潜在风险

1. **敏感信息泄露**
   - 诊断信息可能包含敏感的环境变量值
   - 需要确保用户能够审查将要上传的内容

2. **信息过载**
   - 大量诊断信息可能让用户感到困惑
   - 需要良好的格式化和组织

3. **隐私合规**
   - 收集环境信息可能涉及隐私法规合规问题
   - 需要明确的数据收集同意机制

### 边界情况

| 场景 | 预期行为 |
|------|---------|
| 诊断信息为空 | 不显示诊断文件和诊断部分 |
| 大量诊断项 | 可能需要滚动或截断显示 |
| 诊断详情很长 | 需要正确处理换行和缩进 |
| rollout_path 为 None | 只显示日志和诊断文件 |
| 用户选择 No | 跳转到反馈备注界面，不包含日志和诊断 |

### 改进建议

1. **隐私保护增强**
   - 添加敏感信息自动脱敏功能（如隐藏 API key）
   - 允许用户编辑或删除特定的诊断项
   - 添加隐私政策链接

2. **用户体验优化**
   - 添加诊断信息的折叠/展开功能
   - 为诊断项添加帮助说明，解释其含义
   - 添加诊断信息重要程度标识

3. **诊断信息丰富**
   - 添加更多有用的诊断信息（如 Codex 版本、操作系统信息）
   - 添加网络连通性测试结果

4. **测试覆盖**
   - 添加多诊断项的测试
   - 测试长诊断详情的换行处理
   - 测试敏感信息脱敏

5. **文档完善**
   - 文档化收集的诊断信息类型和用途
   - 添加用户指南说明如何解读诊断信息
