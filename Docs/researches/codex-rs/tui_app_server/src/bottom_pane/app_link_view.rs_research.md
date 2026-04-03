# app_link_view.rs 研究文档

## 场景与职责

`AppLinkView` 是 TUI bottom pane 中的一个模态视图组件，用于展示和管理 ChatGPT 应用的链接、安装和启用流程。它处理两种主要场景：

1. **普通应用链接展示**: 显示应用信息并提供管理选项（在浏览器中打开、启用/禁用应用）
2. **工具建议流程**: 当 MCP 服务器建议安装或启用某个工具时，引导用户完成安装/启用流程并解析elicitation

该组件实现了 `BottomPaneView` trait，可以嵌入到 bottom pane 的视图栈中。

## 功能点目的

### 1. 双屏幕状态机
- **Link 屏幕**: 主屏幕，显示应用信息和主要操作
  - 未安装应用: 显示 "Install on ChatGPT" 和 "Back"
  - 已安装应用: 显示 "Manage on ChatGPT"、"Enable/Disable app" 和 "Back"
- **InstallConfirmation 屏幕**: 安装确认屏幕，用户点击安装链接后显示
  - 提示用户在浏览器中完成安装
  - 提供 "I already Installed it" 确认按钮

### 2. 工具建议集成
- 支持 `Install` 和 `Enable` 两种建议类型
- 与 MCP elicitation 系统集成，通过 `AppLinkElicitationTarget` 解析elicitation决策
- 用户完成安装/启用后自动发送 `ElicitationAction::Accept`
- 用户取消时发送 `ElicitationAction::Decline`

### 3. 键盘导航
- 方向键/Tab: 在选项间移动
- 数字键 1-9: 直接选择并激活对应选项
- Enter: 激活选中选项
- Esc: 关闭视图（会解析elicitation为 Decline 如果是工具建议）

## 具体技术实现

### 核心数据结构

```rust
// 屏幕状态枚举
enum AppLinkScreen {
    Link,
    InstallConfirmation,
}

// 建议类型
pub(crate) enum AppLinkSuggestionType {
    Install,
    Enable,
}

// Elicitation 目标信息
pub(crate) struct AppLinkElicitationTarget {
    pub(crate) thread_id: ThreadId,
    pub(crate) server_name: String,
    pub(crate) request_id: McpRequestId,
}

// 视图参数
pub(crate) struct AppLinkViewParams {
    pub(crate) app_id: String,
    pub(crate) title: String,
    pub(crate) description: Option<String>,
    pub(crate) instructions: String,
    pub(crate) url: String,
    pub(crate) is_installed: bool,
    pub(crate) is_enabled: bool,
    pub(crate) suggest_reason: Option<String>,
    pub(crate) suggestion_type: Option<AppLinkSuggestionType>,
    pub(crate) elicitation_target: Option<AppLinkElicitationTarget>,
}

// 视图状态
pub(crate) struct AppLinkView {
    app_id: String,
    title: String,
    // ... 其他字段
    screen: AppLinkScreen,
    selected_action: usize,
    complete: bool,
}
```

### 关键流程

#### 1. 操作激活流程 (`activate_selected_action`)
```
如果是工具建议:
  - Install 类型:
    - Link 屏幕: Enter/1 → 打开 ChatGPT 链接
    - Link 屏幕: 2/其他 → 拒绝elicitation
    - InstallConfirmation: Enter/1 → 刷新连接器并解析elicitation为Accept
    - InstallConfirmation: 其他 → 拒绝elicitation
  - Enable 类型:
    - Link 屏幕: Enter/1 → 打开 ChatGPT 链接
    - Link 屏幕: 2 → 切换启用状态并解析elicitation
    - Link 屏幕: 其他 → 拒绝elicitation

如果是普通链接:
  - Link 屏幕: Enter/1 → 打开 ChatGPT 链接
  - Link 屏幕: 2 (已安装) → 切换启用状态
  - Link 屏幕: 其他/3 → 完成关闭
  - InstallConfirmation: Enter/1 → 刷新连接器并关闭
  - InstallConfirmation: 其他 → 返回 Link 屏幕
```

#### 2. Elicitation 解析流程
```rust
fn resolve_elicitation(&self, decision: ElicitationAction) {
    if let Some(target) = &self.elicitation_target {
        self.app_event_tx.resolve_elicitation(
            target.thread_id,
            target.server_name.clone(),
            target.request_id.clone(),
            decision,
            None,  // content
            None,  // meta
        );
    }
}
```

#### 3. 内容渲染流程
- `content_lines()`: 根据当前屏幕返回内容行
  - `link_content_lines()`: 显示标题、描述、建议原因、使用说明
  - `install_confirmation_lines()`: 显示安装确认信息和 URL
- `action_rows()`: 生成可选择的操作行
- `hint_line()`: 显示键盘导航提示

### URL 自适应换行

使用 `adaptive_wrap_lines` 函数处理 URL 显示，确保：
- URL 类 token 不会在中间被截断
- 长 URL 的尾部在窄窗口中仍然可见
- 使用 `RtOptions` 配置换行选项

## 关键代码路径与文件引用

### 本文件核心方法

| 方法 | 行号 | 功能 |
|------|------|------|
| `new` | 86-115 | 构造函数，初始化视图状态 |
| `action_labels` | 117-136 | 根据屏幕状态返回可用操作标签 |
| `activate_selected_action` | 206-245 | 核心状态机，处理用户选择 |
| `open_chatgpt_link` | 169-177 | 打开浏览器链接，切换到确认屏幕 |
| `refresh_connectors_and_close` | 179-187 | 刷新连接器状态并完成 |
| `toggle_enabled` | 194-204 | 切换应用启用状态 |
| `resolve_elicitation` | 150-162 | 发送elicitation解析事件 |
| `content_lines` | 247-343 | 内容文本生成 |
| `render` | 491-544 | ratatui 渲染实现 |

### 依赖文件

```
codex-rs/tui_app_server/src/bottom_pane/
├── app_link_view.rs          (本文件)
├── bottom_pane_view.rs       (BottomPaneView trait 定义)
├── scroll_state.rs           (ScrollState 滚动状态)
├── selection_popup_common.rs (GenericDisplayRow, render_rows)
└── mod.rs                    (模块导出)

codex-rs/tui_app_server/src/
├── app_event.rs              (AppEvent 定义)
├── app_event_sender.rs       (AppEventSender, resolve_elicitation)
├── render/renderable.rs      (Renderable trait)
└── wrapping.rs               (adaptive_wrap_lines)

codex-rs/protocol/src/
├── approvals.rs              (ElicitationAction 定义)
└── mcp.rs                    (RequestId 定义)
```

### 外部 crate 依赖
- `ratatui`: TUI 渲染框架
- `crossterm`: 键盘事件处理
- `textwrap`: 文本换行
- `codex_protocol`: 协议类型（ThreadId, ElicitationAction, McpRequestId）

## 依赖与外部交互

### 与 AppEventSender 的交互
通过 `app_event_tx` 发送以下事件：
- `OpenUrlInBrowser { url }`: 打开浏览器
- `RefreshConnectors { force_refetch }`: 刷新连接器状态
- `SetAppEnabled { id, enabled }`: 设置应用启用状态
- `resolve_elicitation()`: 解析 MCP elicitation

### 与 BottomPaneView trait 的交互
实现以下方法：
- `handle_key_event`: 处理键盘输入
- `on_ctrl_c`: 处理 Ctrl+C（解析elicitation为 Decline 如果是工具建议）
- `is_complete`: 返回视图是否完成

### 与父组件的交互
- 由 `BottomPane::push_mcp_server_elicitation_request()` 创建（在 `mod.rs` 中）
- 当检测到工具建议且有 install_url 时，创建 AppLinkView 替代默认的表单视图

## 风险、边界与改进建议

### 风险点

1. **状态机复杂性**: `activate_selected_action` 方法包含复杂的嵌套匹配逻辑，涉及屏幕状态、建议类型、选择索引的三维组合
   - 建议：考虑使用状态模式或查找表简化逻辑

2. **工具建议与普通链接的代码复用**: 两种场景共享大部分代码路径，但行为有微妙差异
   - 风险：修改一种场景可能意外影响另一种
   - 建议：添加更明确的测试覆盖两种场景的所有组合

3. **URL 换行边界情况**: 测试用例显示处理了 URL-like token 不换行和窄窗口尾部可见性
   - 但仍可能有极端长 URL 或特殊字符的边界情况

### 边界情况

1. **数字键越界**: 用户按下的数字键超过可用选项数时，应被忽略（当前实现已处理）
2. **空 elicitation_target**: 非工具建议场景下 `elicitation_target` 为 None，`resolve_elicitation` 应提前返回
3. **窗口极窄**: 宽度小于内容最小需求时的渲染行为

### 测试覆盖

测试文件包含以下测试用例：
- `installed_app_has_toggle_action`: 验证已安装应用的操作标签
- `toggle_action_sends_set_app_enabled_and_updates_label`: 验证启用切换
- `install_confirmation_does_not_split_long_url_like_token_without_scheme`: URL 不换行
- `install_confirmation_render_keeps_url_tail_visible_when_narrow`: 窄窗口 URL 尾部可见
- `install_tool_suggestion_resolves_elicitation_after_confirmation`: 工具建议安装流程
- `declined_tool_suggestion_resolves_elicitation_decline`: 工具建议拒绝流程
- `enable_tool_suggestion_resolves_elicitation_after_enable`: 工具建议启用流程
- Snapshot 测试: UI 渲染快照验证

### 改进建议

1. **状态机重构**: 将 `activate_selected_action` 中的复杂匹配逻辑提取为状态转换表或独立的状态处理函数
2. **错误处理**: 当前 `resolve_elicitation` 在 `elicitation_target` 为 None 时静默返回，考虑添加日志或调试断言
3. **国际化**: 当前所有文本硬编码为英文，考虑支持本地化
4. **可访问性**: 考虑添加更多键盘快捷键（如 Alt+数字直接选择）
