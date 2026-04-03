# card.rs 研究文档

## 场景与职责

`card.rs` 是 Codex TUI 状态显示模块的核心组件，负责构建和渲染 `/status` 命令的输出卡片。该模块将配置、认证、使用量、速率限制等分散的信息整合为一个统一的视觉卡片，展示在聊天历史记录中。

## 功能点目的

### 主要功能

1. **状态卡片构建**: 将各种运行时信息整合为 `StatusHistoryCell` 结构
2. **视觉渲染**: 使用 ratatui 库渲染带边框的卡片界面
3. **信息格式化**: 处理模型名称、权限、目录路径、Token 使用量等显示格式
4. **速率限制展示**: 支持单/多限制组的展示，包括进度条和重置时间

### 核心数据结构

```rust
#[derive(Debug, Clone)]
pub(crate) struct StatusTokenUsageData {
    total: i64,
    input: i64,
    output: i64,
    context_window: Option<StatusContextWindowData>,
}

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

## 具体技术实现

### 1. 状态卡片创建流程

#### new_status_output (单限制组)
```rust
pub(crate) fn new_status_output(
    config: &Config,
    auth_manager: &AuthManager,
    token_info: Option<&TokenUsageInfo>,
    total_usage: &TokenUsage,
    session_id: &Option<ThreadId>,
    thread_name: Option<String>,
    forked_from: Option<ThreadId>,
    rate_limits: Option<&RateLimitSnapshotDisplay>,
    plan_type: Option<PlanType>,
    now: DateTime<Local>,
    model_name: &str,
    collaboration_mode: Option<&str>,
    reasoning_effort_override: Option<Option<ReasoningEffort>>,
) -> CompositeHistoryCell
```

#### new_status_output_with_rate_limits (多限制组)
```rust
pub(crate) fn new_status_output_with_rate_limits(
    // ... 同上，但 rate_limits 参数为数组
    rate_limits: &[RateLimitSnapshotDisplay],
    // ...
) -> CompositeHistoryCell
```

### 2. StatusHistoryCell::new 构建逻辑

构建过程分为多个阶段：

#### 阶段 1: 配置项收集
```rust
let mut config_entries = vec![
    ("workdir", config.cwd.display().to_string()),
    ("model", model_name.to_string()),
    ("provider", config.model_provider_id.clone()),
    ("approval", config.permissions.approval_policy.value().to_string()),
    ("sandbox", summarize_sandbox_policy(config.permissions.sandbox_policy.get())),
];
```

#### 阶段 2: Responses API 特有配置
当使用 Responses API 时，添加推理相关配置：
```rust
if config.model_provider.wire_api == WireApi::Responses {
    let effort_value = reasoning_effort_override
        .unwrap_or(None)
        .map(|effort| effort.to_string())
        .unwrap_or_else(|| "none".to_string());
    config_entries.push(("reasoning effort", effort_value));
    config_entries.push(("reasoning summaries", ...));
}
```

#### 阶段 3: 权限显示简化
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

#### 阶段 4: Token 使用量计算
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

### 3. 渲染实现 (HistoryCell trait)

#### 标签收集与排序
```rust
let mut labels: Vec<String> = vec!["Model", "Directory", "Permissions", "Agents.md"]
    .into_iter()
    .map(str::to_string)
    .collect();
let mut seen: BTreeSet<String> = labels.iter().cloned().collect();

// 条件性添加可选标签
if self.model_provider.is_some() { push_label(&mut labels, &mut seen, "Model provider"); }
if account_value.is_some() { push_label(&mut labels, &mut seen, "Account"); }
// ... 更多条件标签
```

#### 字段格式化器创建
```rust
let formatter = FieldFormatter::from_labels(labels.iter().map(String::as_str));
let value_width = formatter.value_width(available_inner_width);
```

#### 模型信息行渲染
```rust
let mut model_spans = vec![Span::from(self.model_name.clone())];
if !self.model_details.is_empty() {
    model_spans.push(Span::from(" (").dim());
    model_spans.push(Span::from(self.model_details.join(", ")).dim());
    model_spans.push(Span::from(")").dim());
}
```

### 4. 速率限制行渲染

```rust
fn rate_limit_lines(&self, available_inner_width: usize, formatter: &FieldFormatter) -> Vec<Line<'static>> {
    match &self.rate_limits {
        StatusRateLimitData::Available(rows_data) => {
            if rows_data.is_empty() {
                return vec![formatter.line("Limits", vec![Span::from("data not available yet").dim()])];
            }
            self.rate_limit_row_lines(rows_data, available_inner_width, formatter)
        }
        StatusRateLimitData::Stale(rows_data) => {
            // 添加过期警告
        }
        StatusRateLimitData::Missing => {
            vec![formatter.line("Limits", vec![Span::from("data not available yet").dim()])]
        }
    }
}
```

### 5. 模型提供商格式化

```rust
fn format_model_provider(config: &Config) -> Option<String> {
    let provider = &config.model_provider;
    let name = provider.name.trim();
    let provider_name = if name.is_empty() {
        config.model_provider_id.as_str()
    } else {
        name
    };
    let base_url = provider.base_url.as_deref().and_then(sanitize_base_url);
    let is_default_openai = provider.is_openai() && base_url.is_none();
    if is_default_openai {
        return None;  // 默认 OpenAI 不显示
    }
    // ...
}
```

### 6. URL 安全清理

```rust
fn sanitize_base_url(raw: &str) -> Option<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() { return None; }
    
    let Ok(mut url) = Url::parse(trimmed) else { return None; };
    let _ = url.set_username("");      // 移除用户名
    let _ = url.set_password(None);     // 移除密码
    url.set_query(None);                // 移除查询参数
    url.set_fragment(None);             // 移除片段
    Some(url.to_string().trim_end_matches('/').to_string()).filter(|v| !v.is_empty())
}
```

## 关键代码路径与文件引用

### 上游依赖（输入）

| 模块 | 路径 | 用途 |
|------|------|------|
| `Config` | `codex_core::config::Config` | 配置信息源 |
| `AuthManager` | `codex_core::AuthManager` | 认证信息管理 |
| `TokenUsageInfo` | `codex_protocol::protocol::TokenUsageInfo` | Token 使用详情 |
| `RateLimitSnapshotDisplay` | `rate_limits.rs` | 速率限制显示数据 |
| `PlanType` | `codex_protocol::account::PlanType` | 账户计划类型 |
| `StatusAccountDisplay` | `account.rs` | 账户显示信息 |

### 下游依赖（输出）

| 模块 | 路径 | 用途 |
|------|------|------|
| `chatwidget.rs` | `../chatwidget.rs` | 调用创建状态卡片 |
| `tests.rs` | `./tests.rs` | 单元测试和快照测试 |

### 内部模块依赖

```rust
use super::account::StatusAccountDisplay;
use super::format::FieldFormatter;
use super::format::line_display_width;
use super::format::push_label;
use super::format::truncate_line_to_width;
use super::helpers::compose_account_display;
use super::helpers::compose_agents_summary;
use super::helpers::compose_model_display;
use super::helpers::format_directory_display;
use super::helpers::format_tokens_compact;
use super::rate_limits::RateLimitSnapshotDisplay;
use super::rate_limits::StatusRateLimitData;
use super::rate_limits::StatusRateLimitRow;
use super::rate_limits::StatusRateLimitValue;
use super::rate_limits::compose_rate_limit_data;
use super::rate_limits::compose_rate_limit_data_many;
use super::rate_limits::format_status_limit_summary;
use super::rate_limits::render_status_limit_progress_bar;
```

## 依赖与外部交互

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染框架 |
| `chrono` | 日期时间处理 |
| `url` | URL 解析和清理 |
| `codex_core` | 核心配置和认证 |
| `codex_protocol` | 协议类型定义 |
| `codex_utils_sandbox_summary` | 沙箱策略摘要 |

### 历史记录单元集成

```rust
impl HistoryCell for StatusHistoryCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        // 实现状态卡片的行渲染
    }
}
```

`CompositeHistoryCell` 组合结构：
```rust
let command = PlainHistoryCell::new(vec!["/status".magenta().into()]);
let card = StatusHistoryCell::new(...);
CompositeHistoryCell::new(vec![Box::new(command), Box::new(card)])
```

## 风险、边界与改进建议

### 边界情况

1. **窄终端处理**: 当 `available_inner_width == 0` 时返回空向量
2. **缺失数据**: 速率限制、账户信息、Token 使用量等都可能缺失，需要优雅降级
3. **Windows 路径**: 测试中使用条件编译处理 Windows 路径分隔符
4. **ChatGPT 用户**: Token 使用量对 ChatGPT 订阅者隐藏

### 潜在风险

1. **敏感信息泄露**: 
   - `sanitize_base_url` 虽然清理了凭证，但仍需确保所有 URL 都经过处理
   - 邮箱地址在状态卡片中明文显示

2. **时区处理**: 
   - 使用 `DateTime<Local>` 进行本地时间转换，依赖系统时区设置正确

3. **性能问题**: 
   - `display_lines` 在每次渲染时重新计算，如果调用频繁可能影响性能
   - 字符串拼接较多，可考虑使用 `String::with_capacity` 预分配

4. **硬编码值**:
   - 版本号 `CODEX_CLI_VERSION` 来自编译时
   - URL `https://chatgpt.com/codex/settings/usage` 硬编码

### 改进建议

1. **缓存优化**: 
   - 考虑缓存 `display_lines` 结果，仅在数据变化时重新计算
   - 使用 `Arc<str>` 减少字符串克隆

2. **可配置性**:
   - 添加配置选项控制哪些字段显示/隐藏
   - 支持自定义状态卡片模板

3. **可访问性**:
   - 考虑色盲用户，不要仅依赖颜色区分信息
   - 添加高对比度模式支持

4. **国际化**:
   - 当前所有字符串硬编码为英文
   - 考虑使用 `i18n` 框架支持多语言

5. **测试覆盖**:
   - 当前依赖快照测试，可添加更多单元测试覆盖边界情况
   - 测试不同终端宽度下的渲染效果

### 代码度量

- 代码行数: 585 行
- 主要结构体: 3 个 (`StatusContextWindowData`, `StatusTokenUsageData`, `StatusHistoryCell`)
- 公共函数: 3 个 (`new_status_output`, `new_status_output_with_rate_limits`, `format_model_provider`)
- 复杂度: 中等（主要是条件渲染逻辑）
