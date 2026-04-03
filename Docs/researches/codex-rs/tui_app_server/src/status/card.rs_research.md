# card.rs 研究文档

## 场景与职责

`card.rs` 是 TUI 状态显示模块的核心文件，负责将 Codex CLI 的运行时状态渲染为可视化的状态卡片。当用户执行 `/status` 命令时，该模块生成一个格式化的状态面板，展示当前会话的关键信息。

### 主要职责
1. **状态卡片构建**: 整合配置、账户、令牌使用、速率限制等多维度信息
2. **视觉格式化**: 使用 ratatui 库生成带边框、颜色、对齐的终端 UI
3. **权限摘要**: 将复杂的沙箱策略和审批策略转换为人类可读的描述
4. **模型信息展示**: 显示当前模型及其推理配置

## 功能点目的

### 1. StatusContextWindowData - 上下文窗口数据

```rust
#[derive(Debug, Clone)]
struct StatusContextWindowData {
    percent_remaining: i64,      // 剩余上下文百分比
    tokens_in_context: i64,      // 当前上下文中的令牌数
    window: i64,                 // 上下文窗口总大小
}
```

用于展示模型上下文窗口的使用情况，帮助用户了解何时需要压缩或重置会话。

### 2. StatusTokenUsageData - 令牌使用统计

```rust
#[derive(Debug, Clone)]
pub(crate) struct StatusTokenUsageData {
    total: i64,                  // 总令牌数
    input: i64,                  // 输入令牌数（不含缓存）
    output: i64,                 // 输出令牌数
    context_window: Option<StatusContextWindowData>, // 上下文窗口详情
}
```

聚合当前会话的令牌消耗数据，为成本估算提供依据。

### 3. StatusHistoryCell - 状态历史单元格

```rust
#[derive(Debug)]
struct StatusHistoryCell {
    model_name: String,
    model_details: Vec<String>,
    directory: PathBuf,
    permissions: String,
    agents_summary: String,
    collaboration_mode: Option<String>,
    model_provider: Option<String>,
    account: Option<StatusAccountDisplay>,
    thread_name: Option<String>,
    session_id: Option<String>,
    forked_from: Option<String>,
    token_usage: StatusTokenUsageData,
    rate_limits: StatusRateLimitData,
}
```

实现 `HistoryCell` trait，是状态显示的核心数据结构。

## 具体技术实现

### 关键流程

#### 1. 状态卡片创建流程

```rust
pub(crate) fn new_status_output_with_rate_limits(
    config: &Config,
    account_display: Option<&StatusAccountDisplay>,
    token_info: Option<&TokenUsageInfo>,
    total_usage: &TokenUsage,
    session_id: &Option<ThreadId>,
    thread_name: Option<String>,
    forked_from: Option<ThreadId>,
    rate_limits: &[RateLimitSnapshotDisplay],
    _plan_type: Option<PlanType>,
    now: DateTime<Local>,
    model_name: &str,
    collaboration_mode: Option<&str>,
    reasoning_effort_override: Option<Option<ReasoningEffort>>,
) -> CompositeHistoryCell
```

流程步骤：
1. 创建 `/status` 命令前缀单元格（`PlainHistoryCell`）
2. 构建 `StatusHistoryCell` 实例
3. 组合为 `CompositeHistoryCell` 返回

#### 2. StatusHistoryCell::new 构建逻辑

**配置条目收集** (行 166-192):
```rust
let mut config_entries = vec![
    ("workdir", config.cwd.display().to_string()),
    ("model", model_name.to_string()),
    ("provider", config.model_provider_id.clone()),
    ("approval", config.permissions.approval_policy.value().to_string()),
    ("sandbox", summarize_sandbox_policy(config.permissions.sandbox_policy.get())),
];
// 如果是 Responses API，添加推理配置
if config.model_provider.wire_api == WireApi::Responses {
    config_entries.push(("reasoning effort", effort_value));
    config_entries.push(("reasoning summaries", summary_value));
}
```

**权限摘要生成** (行 199-226):
```rust
let permissions = if config.permissions.approval_policy.value() == AskForApproval::OnRequest
    && *config.permissions.sandbox_policy.get() == SandboxPolicy::new_workspace_write_policy()
{
    "Default".to_string()
} else if config.permissions.approval_policy.value() == AskForApproval::Never
    && *config.permissions.sandbox_policy.get() == SandboxPolicy::DangerFullAccess
{
    "Full Access".to_string()
} else {
    format!("Custom ({sandbox}, {approval})")
};
```

**令牌使用计算** (行 232-248):
```rust
let (context_usage, context_window) = match token_info {
    Some(info) => (&info.last_token_usage, info.model_context_window),
    None => (&default_usage, config.model_context_window),
};
let context_window = context_window.map(|window| StatusContextWindowData {
    percent_remaining: context_usage.percent_of_context_window_remaining(window),
    tokens_in_context: context_usage.tokens_in_context_window(),
    window,
});
```

#### 3. display_lines 渲染流程

渲染顺序（行 411-547）:
1. **标题行**: "OpenAI Codex (v{VERSION})"
2. **提示信息**: 访问设置页面的链接
3. **模型信息**: 模型名称 + 推理详情
4. **模型提供商**: 非 OpenAI 默认时显示
5. **工作目录**: 相对 home 目录的缩写路径
6. **权限**: Default/Full Access/Custom
7. **Agents.md**: 项目文档摘要
8. **账户**: ChatGPT 邮箱/计划或 API Key 提示
9. **线程名**: 如有设置
10. **协作模式**: 如有设置
11. **会话 ID**: UUID 格式
12. **Fork 来源**: 如有
13. **令牌使用**: total (input + output)
14. **上下文窗口**: 剩余百分比和用量
15. **速率限制**: 进度条形式展示

### 关键数据结构

| 结构体 | 用途 | 关键方法 |
|--------|------|----------|
| `StatusContextWindowData` | 上下文窗口统计 | 字段访问 |
| `StatusTokenUsageData` | 令牌使用聚合 | `token_usage_spans()`, `context_window_spans()` |
| `StatusHistoryCell` | 状态卡片核心 | `new()`, `display_lines()` |

### 辅助函数

#### format_model_provider (行 550-568)
格式化模型提供商信息，隐藏默认 OpenAI 配置：
```rust
fn format_model_provider(config: &Config) -> Option<String> {
    // 如果是默认 OpenAI，返回 None（不显示）
    // 否则返回 "provider_name - base_url" 格式
}
```

#### sanitize_base_url (行 570-584)
清理 URL 中的敏感信息（用户名、密码、查询参数、片段）：
```rust
fn sanitize_base_url(raw: &str) -> Option<String> {
    // 解析 URL，清除 credentials 和 query/fragment
}
```

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/status/card.rs` - 584 行

### 直接依赖
| 文件 | 用途 |
|------|------|
| `account.rs` | `StatusAccountDisplay` 枚举 |
| `format.rs` | `FieldFormatter`, `line_display_width`, `truncate_line_to_width`, `push_label` |
| `helpers.rs` | `compose_account_display`, `compose_agents_summary`, `compose_model_display`, `format_directory_display`, `format_tokens_compact` |
| `rate_limits.rs` | `RateLimitSnapshotDisplay`, `StatusRateLimitData`, `StatusRateLimitRow`, `StatusRateLimitValue`, `compose_rate_limit_data`, `compose_rate_limit_data_many`, `format_status_limit_summary`, `render_status_limit_progress_bar` |
| `../history_cell.rs` | `CompositeHistoryCell`, `HistoryCell`, `PlainHistoryCell`, `with_border_with_inner_width` |
| `../version.rs` | `CODEX_CLI_VERSION` |
| `../wrapping.rs` | `RtOptions`, `adaptive_wrap_lines` |

### 外部 crate 依赖
| Crate | 用途 |
|-------|------|
| `chrono` | 日期时间处理 (`DateTime`, `Local`) |
| `codex_core` | `WireApi`, `Config` |
| `codex_protocol` | `ThreadId`, `PlanType`, `ReasoningEffort`, `AskForApproval`, `NetworkAccess`, `SandboxPolicy`, `TokenUsage`, `TokenUsageInfo` |
| `codex_utils_sandbox_summary` | `summarize_sandbox_policy` |
| `ratatui` | 终端 UI 渲染 (`Line`, `Span`, `Stylize`) |
| `url` | URL 解析和清理 |

### 调用方
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/chatwidget.rs` (行 6804) - 处理 `/status` 命令时调用
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/status/tests.rs` - 测试用例

## 依赖与外部交互

### 配置依赖
依赖 `codex_core::config::Config` 的以下字段：
- `cwd` - 当前工作目录
- `model` - 模型名称
- `model_provider_id` - 提供商 ID
- `model_provider.wire_api` - API 类型 (Responses/ChatCompletions)
- `model_reasoning_summary` - 推理摘要配置
- `permissions.approval_policy` - 审批策略
- `permissions.sandbox_policy` - 沙箱策略

### 协议依赖
依赖 `codex_protocol::protocol` 的以下类型：
- `TokenUsage` - 令牌使用统计
- `TokenUsageInfo` - 扩展的令牌信息（含上下文窗口）
- `RateLimitSnapshot` - 速率限制快照
- `SandboxPolicy` - 沙箱策略枚举
- `AskForApproval` - 审批策略枚举

## 风险、边界与改进建议

### 当前限制

1. **ChatGPT 用户令牌隐藏** (行 528-531):
```rust
// Hide token usage only for ChatGPT subscribers
if !matches!(self.account, Some(StatusAccountDisplay::ChatGpt { .. })) {
    lines.push(formatter.line("Token usage", self.token_usage_spans()));
}
```
ChatGPT 订阅用户看不到令牌使用统计，这可能导致成本不透明。

2. **_plan_type 未使用**: 参数被标记为 `_plan_type` 但未在代码中使用，可能是遗留参数。

3. **硬编码阈值**: 速率限制数据的新鲜度阈值（15 分钟）定义在 `rate_limits.rs` 中，但此处消费。

### 潜在改进

1. **可选显示令牌使用**: 为 ChatGPT 用户添加配置选项，允许查看令牌使用（用于调试）。

2. **移除未使用参数**: 清理 `_plan_type` 参数或实现相关功能。

3. **响应式布局**: 当前布局在极窄终端（< 40 列）下可能显示不佳，可添加最小宽度检测。

4. **国际化支持**: 当前所有标签都是硬编码英文，可考虑 i18n 支持。

### 测试覆盖
- 通过 `tests.rs` 进行快照测试，覆盖多种配置组合
- 建议添加边界测试：极长路径、极宽令牌数、缺失可选字段

### 性能考虑
- `display_lines()` 在每次渲染时重新计算所有行，对于静态数据可考虑缓存
- 但在 TUI 场景下，渲染频率可控，当前实现已足够高效
