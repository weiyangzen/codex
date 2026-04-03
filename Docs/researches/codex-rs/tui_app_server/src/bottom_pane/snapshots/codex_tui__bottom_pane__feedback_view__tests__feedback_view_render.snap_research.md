# Feedback View Render Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `feedback_view.rs` 模块的测试快照，用于验证**反馈视图的渲染**。当用户提交反馈（如报告问题）时，显示此界面询问是否上传日志。

### 业务场景
- 用户遇到问题，想要报告给开发团队
- 系统询问是否上传会话日志以便诊断
- 用户需要决定是否分享日志

### 反馈视图特性
- 解释日志内容和用途
- 说明日志保留期限
- 提供上传/不上传/取消选项
- 显示日志文件路径（可查看）

## 功能点目的

### 核心功能
1. **信息说明**：解释日志包含的内容和用途
2. **隐私透明**：说明日志保留期限和使用方式
3. **用户决策**：提供明确的选项
4. **查看选项**：允许用户先查看日志内容

### 用户体验目标
- **知情同意**：用户清楚知道分享什么内容
- **隐私保护**：明确说明数据使用方式
- **便捷操作**：提供查看和分享的选项

## 具体技术实现

### 关键数据结构
```rust
pub(crate) struct FeedbackView {
    feedback_type: FeedbackType,
    log_path: PathBuf,
    selected_option: usize,
}

pub(crate) enum FeedbackType {
    BugReport,
    BadResult,
    GoodResult,
    SafetyCheck,
    Other,
}

pub(crate) enum FeedbackOption {
    YesShare,    // 分享日志
    No,          // 不分享
    Cancel,      // 取消
}
```

### 渲染逻辑
```rust
impl Renderable for FeedbackView {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        // 标题
        "  Do you want to upload logs before reporting issue?".bold()
            .render(title_area, buf);
        
        // 说明文本
        "  Logs may include the full conversation history of this Codex process"
            .dim().render(line1_area, buf);
        "  These logs are retained for 90 days and are used solely for troubles"
            .dim().render(line2_area, buf);
        
        // 查看提示
        "  You can review the exact content of the logs before they're uploaded"
            .render(review_area, buf);
        "  <LOG_PATH>".cyan().render(path_area, buf);
        
        // 选项
        let options = vec![
            ("1. Yes", "Share the current Codex session logs with the team for troubleshooting."),
            ("2. No", ""),
            ("3. Cancel", ""),
        ];
        
        for (idx, (label, desc)) in options.iter().enumerate() {
            let prefix = if idx == self.selected_option { "› " } else { "  " };
            format!("{}{}     {}", prefix, label, desc).render(option_area, buf);
        }
    }
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/feedback_view.rs`
- **测试函数**: `feedback_view_render` (在 tests 模块中)

### 渲染输出分析
```
  Do you want to upload logs before reporting issue?

  Logs may include the full conversation history of this Codex process
  These logs are retained for 90 days and are used solely for troubles

  You can review the exact content of the logs before they're uploaded
  <LOG_PATH>


› 1. Yes     Share the current Codex session logs with the team for
             troubleshooting.
  2. No
  3. Cancel
```

- 标题询问是否上传日志
- 说明日志内容和保留期限（90天）
- 提示可以查看日志内容
- 三个选项：分享、不分享、取消

## 依赖与外部交互

### 内部依赖
- `FeedbackView` - 反馈视图
- `FeedbackType` - 反馈类型

### 外部交互
- **日志系统**：获取日志文件路径
- **上传服务**：上传日志到服务器
- **反馈系统**：提交反馈报告

## 风险、边界与改进建议

### 潜在风险
1. **隐私泄露**：日志可能包含敏感信息
2. **日志过大**：大日志文件上传可能失败
3. **网络问题**：上传失败的处理

### 边界情况
1. **无日志文件**：日志文件不存在时的处理
2. **日志读取失败**：无法读取日志时的处理
3. **用户取消**：用户取消反馈流程

### 改进建议
1. **日志预览**：在界面上直接显示日志内容预览
2. **敏感信息过滤**：自动过滤密码、密钥等敏感信息
3. **分段上传**：大日志文件分段上传
4. **离线反馈**：支持离线保存，联网后自动上传
5. **反馈模板**：提供反馈模板，引导用户提供有用信息

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/feedback_view.rs`
