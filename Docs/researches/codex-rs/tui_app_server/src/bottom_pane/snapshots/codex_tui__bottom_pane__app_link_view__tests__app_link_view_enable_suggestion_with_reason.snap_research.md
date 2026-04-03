# App Link View Enable Suggestion Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `app_link_view.rs` 模块的测试快照，用于验证**应用链接视图的启用建议界面**的渲染输出。该界面在用户需要启用某个应用（如 Google Calendar）以在当前请求中使用时被触发。

### 业务场景
- 当 AI 检测到某个已安装但未启用的应用可以帮助完成当前任务时
- 用户通过 `$` 触发应用选择后选择了一个未启用的应用
- 需要引导用户完成启用流程，同时提供跳转到 ChatGPT 管理应用的选项

## 功能点目的

### 核心功能
1. **应用信息展示**：显示应用名称、描述和使用说明
2. **建议理由展示**：说明为什么建议启用此应用（如 "Plan and reference events from your calendar"）
3. **操作引导**：提供清晰的操作选项（管理/启用/返回）
4. **键盘导航支持**：支持 Tab/↑↓ 移动、Enter 选择、Esc 关闭

### UI 设计目标
- 保持界面简洁，突出关键信息
- 使用 `›` 符号指示当前选中的选项
- 通过斜体和灰色文本区分不同类型的信息

## 具体技术实现

### 关键数据结构
```rust
// AppLinkView 结构体（简化）
pub(crate) struct AppLinkView {
    app_id: String,
    title: String,
    description: Option<String>,
    instructions: String,
    url: String,
    is_installed: bool,
    is_enabled: bool,
    suggest_reason: Option<String>,
    suggestion_type: Option<AppLinkSuggestionType>,  // Enable 或 Install
    elicitation_target: Option<AppLinkElicitationTarget>,
    // ... 其他字段
}

pub(crate) enum AppLinkSuggestionType {
    Install,
    Enable,
}
```

### 渲染流程
1. **内容行生成** (`link_content_lines` 方法)：
   - 应用标题（加粗）
   - 描述（灰色、斜体）
   - 建议理由（斜体）
   - 使用说明（普通文本）
   - 提示信息（关于 `$` 使用和应用安装延迟）

2. **操作行生成** (`action_rows` 方法)：
   - 根据 `is_installed` 和 `is_enabled` 状态动态生成选项
   - 已安装时显示：["Manage on ChatGPT", "Enable app"/"Disable app", "Back"]
   - 未安装时显示：["Install on ChatGPT", "Back"]

3. **渲染** (`render` 方法)：
   - 使用 `Block` 设置用户消息样式
   - 使用 `Layout` 垂直分割内容区、操作区和提示区
   - 使用 `Paragraph` 和 `Wrap` 处理文本换行

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/app_link_view.rs`
- **测试函数**: `enable_suggestion_with_reason_snapshot` (行 918-942)
- **渲染辅助函数**: `render_snapshot` (行 563-583)

### 测试参数
```rust
AppLinkViewParams {
    app_id: "connector_google_calendar".to_string(),
    title: "Google Calendar".to_string(),
    description: Some("Plan events and schedules.".to_string()),
    instructions: "Enable this app to use it for the current request.".to_string(),
    url: "https://example.test/google-calendar".to_string(),
    is_installed: true,      // 已安装
    is_enabled: false,       // 未启用
    suggest_reason: Some("Plan and reference events from your calendar".to_string()),
    suggestion_type: Some(AppLinkSuggestionType::Enable),
    elicitation_target: Some(suggestion_target()),
}
```

## 依赖与外部交互

### 内部依赖
- `codex_protocol::ThreadId` - 线程标识
- `codex_protocol::approvals::ElicitationAction` - 用户决策类型
- `codex_protocol::mcp::RequestId` - MCP 请求标识
- `ratatui` - TUI 渲染框架
- `textwrap` - 文本换行处理

### 外部交互
- **AppEventSender**: 发送应用事件
  - `OpenUrlInBrowser` - 打开浏览器访问 ChatGPT
  - `SetAppEnabled` - 设置应用启用状态
  - `ResolveElicitation` - 解析用户决策

### 与 tui crate 的关系
- 该快照的 `source` 字段指向 `tui/src/bottom_pane/app_link_view.rs`
- 说明 `tui_app_server` 与 `tui` 共享相同的应用链接视图逻辑
- 两者通过相同的测试用例确保渲染一致性

## 风险、边界与改进建议

### 潜在风险
1. **路径规范化差异**: 测试中使用 `normalize_snapshot_paths` 处理绝对路径，跨平台可能存在差异
2. **文本换行差异**: 不同终端宽度下的文本换行可能影响快照稳定性
3. **状态同步延迟**: "Newly installed apps can take a few minutes to appear" 提示说明存在后台同步延迟

### 边界情况
1. **超长 URL**: 测试 `install_confirmation_render_keeps_url_tail_visible_when_narrow` 验证窄终端下的 URL 显示
2. **无描述**: 当 `description` 为 None 或空字符串时，不渲染描述行
3. **无建议理由**: 当 `suggest_reason` 为 None 时，不渲染理由部分

### 改进建议
1. **国际化支持**: 当前所有文本硬编码为英文，建议添加 i18n 支持
2. **可访问性**: 考虑添加屏幕阅读器支持，如为 `›` 符号添加语义描述
3. **性能优化**: 对于大量应用的场景，考虑添加搜索/过滤功能
4. **测试覆盖**: 当前测试主要覆盖正常路径，建议增加错误处理路径的测试

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/app_link_view.rs`
- 对应 tui 文件: `codex-rs/tui/src/bottom_pane/app_link_view.rs`（如果存在）
- 协议定义: `codex-rs/protocol/src/` 下的 approvals 和 mcp 模块
