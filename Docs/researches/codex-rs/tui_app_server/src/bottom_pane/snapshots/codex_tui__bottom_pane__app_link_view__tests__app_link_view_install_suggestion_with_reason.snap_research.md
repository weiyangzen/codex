# App Link View Install Suggestion Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `app_link_view.rs` 模块的测试快照，用于验证**应用链接视图的安装建议界面**的渲染输出。该界面在用户需要安装某个应用（如 Google Calendar）以在当前请求中使用时被触发。

### 业务场景
- 当 AI 检测到某个未安装的应用可以帮助完成当前任务时
- 用户通过 `$` 触发应用选择后选择了一个未安装的应用
- 需要引导用户完成安装流程，包括跳转到 ChatGPT 安装和后续确认

### 与 Enable Suggestion 的区别
| 特性 | Install Suggestion | Enable Suggestion |
|------|-------------------|-------------------|
| `is_installed` | `false` | `true` |
| `is_enabled` | `false` | `false` |
| 操作选项 | Install on ChatGPT, Back | Manage on ChatGPT, Enable app, Back |
| 说明文本 | 引导安装 | 引导启用 |
| 两阶段流程 | 是（Link → InstallConfirmation） | 否 |

## 功能点目的

### 核心功能
1. **应用信息展示**：显示应用名称、描述和使用场景
2. **安装引导**：清晰说明需要在浏览器中完成安装
3. **两阶段流程**：
   - 第一阶段：引导用户到 ChatGPT 安装
   - 第二阶段：确认安装完成（InstallConfirmation 屏幕）
4. **后续使用提示**：安装后如何使用 `$` 插入应用

### UI 设计目标
- 明确告知用户安装是外部流程（在浏览器中完成）
- 提供 "I already Installed it" 确认按钮
- 提示安装后可能需要几分钟同步

## 具体技术实现

### 关键数据结构
```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum AppLinkScreen {
    Link,                 // 初始屏幕
    InstallConfirmation,  // 安装确认屏幕
}

pub(crate) struct AppLinkView {
    // ... 其他字段
    screen: AppLinkScreen,  // 当前屏幕状态
    // ...
}
```

### 屏幕状态转换
```
Link 屏幕
    ↓ 用户选择 "Install on ChatGPT" 并按 Enter
OpenUrlInBrowser 事件发送
    ↓ 用户返回并选择 "I already Installed it"
InstallConfirmation 屏幕
    ↓ 用户确认
RefreshConnectors + ResolveElicitation 事件发送
```

### 内容生成逻辑

**Link 屏幕** (`link_content_lines`):
```rust
if !self.is_installed {
    for line in wrap("Install this app in your browser, then return here.", usable_width) {
        lines.push(Line::from(line.into_owned()));
    }
    // ... 提示安装后使用 $
}
```

**InstallConfirmation 屏幕** (`install_confirmation_lines`):
```rust
lines.push(Line::from("Finish App Setup".bold()));
// 说明完成设置的步骤
// 显示 Setup URL（可点击）
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/app_link_view.rs`
- **测试函数**: `install_suggestion_with_reason_snapshot` (行 892-916)
- **测试函数**: `install_tool_suggestion_resolves_elicitation_after_confirmation` (行 742-798) - 验证完整流程

### 测试参数
```rust
AppLinkViewParams {
    app_id: "connector_google_calendar".to_string(),
    title: "Google Calendar".to_string(),
    description: Some("Plan events and schedules.".to_string()),
    instructions: "Install this app in your browser, then return here.".to_string(),
    url: "https://example.test/google-calendar".to_string(),
    is_installed: false,     // 未安装
    is_enabled: false,       // 未启用
    suggest_reason: Some("Plan and reference events from your calendar".to_string()),
    suggestion_type: Some(AppLinkSuggestionType::Install),
    elicitation_target: Some(suggestion_target()),
}
```

## 依赖与外部交互

### 内部依赖
与 Enable Suggestion 相同，额外关注：
- `adaptive_wrap_lines` - 用于 URL 的自适应换行，确保 URL 尾部可见

### 外部交互
- **AppEventSender**:
  - `OpenUrlInBrowser` - 打开浏览器
  - `RefreshConnectors { force_refetch: true }` - 强制刷新连接器列表
  - `ResolveElicitation` - 通知核心用户决策

### URL 处理
```rust
fn install_confirmation_lines(&self, width: u16) -> Vec<Line<'static>> {
    // ...
    let url_line = Line::from(vec![self.url.clone().cyan().underlined()]);
    lines.extend(adaptive_wrap_lines(
        vec![url_line],
        RtOptions::new(usable_width),
    ));
    // ...
}
```

## 风险、边界与改进建议

### 潜在风险
1. **URL 截断问题**: 长 URL 在窄终端可能被截断，已通过 `install_confirmation_render_keeps_url_tail_visible_when_narrow` 测试缓解
2. **同步延迟**: 用户点击 "I already Installed it" 后，应用可能不会立即出现，需要轮询
3. **外部依赖**: 依赖 ChatGPT 网站的可用性和 URL 结构稳定性

### 边界情况
1. **URL-like token 分割**: 测试 `install_confirmation_does_not_split_long_url_like_token_without_scheme` 确保无 scheme 的 URL 不被错误分割
2. **网络中断**: 如果用户在安装过程中失去网络连接，没有明确的错误处理
3. **取消流程**: 用户可以通过 Esc 或选择 "Back" 取消，会发送 `Decline` 决策

### 改进建议
1. **安装状态轮询**: 添加自动轮询机制，检测应用是否已安装
2. **错误重试**: 如果 `RefreshConnectors` 未找到新应用，提供重试选项
3. **QR 码支持**: 对于终端设备，考虑显示 QR 码便于手机扫描
4. **进度指示**: 在 InstallConfirmation 屏幕添加安装状态指示器

### 测试覆盖
- 正常安装流程: `install_tool_suggestion_resolves_elicitation_after_confirmation`
- 取消流程: `declined_tool_suggestion_resolves_elicitation_decline`
- URL 渲染: `install_confirmation_render_keeps_url_tail_visible_when_narrow`
- URL 分割: `install_confirmation_does_not_split_long_url_like_token_without_scheme`

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/app_link_view.rs`
- 换行处理: `codex-rs/tui_app_server/src/wrapping.rs`
