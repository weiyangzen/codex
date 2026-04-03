# 研究报告：codex-rs/tui/src/status 模块

## 1. 场景与职责

### 1.1 模块定位

`status` 模块是 Codex TUI（终端用户界面）中负责 **状态输出格式化与显示适配** 的核心组件。其主要职责是将协议层（protocol-level）的快照数据转换为稳定的显示结构，用于：

1. **`/status` 斜杠命令输出** - 用户执行 `/status` 命令时显示的会话状态卡片
2. **底部状态栏（footer/status-line）辅助** - 为状态栏提供格式化后的使用限制、token 用量等数据

### 1.2 使用场景

| 场景 | 说明 |
|------|------|
| 用户执行 `/status` | 显示当前会话的完整配置信息，包括模型、权限、token 用量、速率限制等 |
| 状态栏实时显示 | 在底部状态栏显示简化的上下文窗口使用情况 |
| 速率限制警告 | 当接近使用限制时，提示用户运行 `/status` 查看详情 |

### 1.3 设计原则

根据模块文档注释，该模块遵循以下设计原则：
- **关注点分离**：将渲染逻辑与传输层代码分离
- **数据转换**：将原始协议数据转换为 UI 友好的显示结构
- **时区敏感**：时间相关值基于调用方提供的捕获时间戳解释

---

## 2. 功能点目的

### 2.1 核心功能模块

```
status/
├── mod.rs           # 模块入口，公共导出
├── account.rs       # 账户信息显示（ChatGPT / API Key）
├── card.rs          # /status 卡片主逻辑（StatusHistoryCell）
├── format.rs        # 字段格式化工具（FieldFormatter）
├── helpers.rs       # 辅助函数（token 格式化、路径显示等）
├── rate_limits.rs   # 速率限制显示逻辑
└── tests.rs         # 单元测试与快照测试
```

### 2.2 各文件功能详解

#### 2.2.1 `account.rs` - 账户类型定义

```rust
pub(crate) enum StatusAccountDisplay {
    ChatGpt {
        email: Option<String>,
        plan: Option<String>,
    },
    ApiKey,
}
```

**目的**：区分两种认证方式的显示：
- **ChatGPT 订阅用户**：显示邮箱和套餐类型（如 Plus）
- **API Key 用户**：显示 "API key configured" 提示

#### 2.2.2 `card.rs` - 状态卡片主逻辑

核心结构 `StatusHistoryCell` 负责渲染 `/status` 命令的完整输出卡片：

**显示字段**：
| 字段 | 来源 | 说明 |
|------|------|------|
| Model | `config.model` + `config_entries` | 模型名称及推理配置详情 |
| Directory | `config.cwd` | 当前工作目录（支持 home 目录简写） |
| Permissions | `config.permissions` | 权限摘要（Default/Full Access/Custom） |
| Agents.md | `discover_project_doc_paths` | 发现的 AGENTS.md 文件路径 |
| Account | `AuthManager` + `PlanType` | 账户信息 |
| Thread name | `thread_name` | 会话名称 |
| Session | `session_id` | 会话 ID |
| Forked from | `forked_from` | 分叉来源会话 ID |
| Collaboration mode | `collaboration_mode` | 协作模式 |
| Token usage | `TokenUsage` | Token 使用统计 |
| Context window | `TokenUsageInfo` | 上下文窗口使用情况 |
| Limits | `RateLimitSnapshotDisplay` | 速率限制进度条 |

**权限显示逻辑**：
```rust
// Default: approval=on-request, sandbox=workspace-write
// Full Access: approval=never, sandbox=danger-full-access
// Custom: 其他组合，显示具体配置
```

#### 2.2.3 `format.rs` - 字段格式化

`FieldFormatter` 提供对齐的标签-值格式化：

```rust
pub(crate) struct FieldFormatter {
    indent: &'static str,      // 缩进（" "）
    label_width: usize,        // 最大标签宽度
    value_offset: usize,       // 值起始偏移
    value_indent: String,      // 续行缩进
}
```

**功能**：
- 自动计算标签列宽，实现右对齐
- 支持续行缩进（continuation）
- 行宽计算与截断（支持 Unicode 宽字符）

#### 2.2.4 `helpers.rs` - 辅助函数

| 函数 | 功能 |
|------|------|
| `compose_model_display` | 组合模型显示（添加 reasoning effort、summaries 详情） |
| `compose_agents_summary` | 发现 AGENTS.md 文件并格式化相对路径 |
| `compose_account_display` | 根据认证模式构建账户显示 |
| `format_tokens_compact` | 紧凑 token 数量格式化（K/M/B/T） |
| `format_directory_display` | 目录路径格式化（支持 home 简写和截断） |
| `format_reset_timestamp` | 重置时间格式化（同天只显示时间，跨天显示日期） |
| `title_case` | 首字母大写转换 |

**token 格式化示例**：
```rust
format_tokens_compact(1_200)    // "1.2K"
format_tokens_compact(1_500_000) // "1.5M"
```

#### 2.2.5 `rate_limits.rs` - 速率限制显示

**核心数据结构**：

```rust
pub(crate) struct RateLimitSnapshotDisplay {
    pub limit_name: String,                    // 限制标识（如 "codex"）
    pub captured_at: DateTime<Local>,          // 捕获时间戳
    pub primary: Option<RateLimitWindowDisplay>,    // 主窗口（通常 5 小时）
    pub secondary: Option<RateLimitWindowDisplay>,  // 次窗口（通常每周）
    pub credits: Option<CreditsSnapshotDisplay>,    // 额度信息
}

pub(crate) struct RateLimitWindowDisplay {
    pub used_percent: f64,          // 已使用百分比
    pub resets_at: Option<String>,  // 重置时间（本地化）
    pub window_minutes: Option<i64>, // 窗口时长（分钟）
}

pub(crate) enum StatusRateLimitData {
    Available(Vec<StatusRateLimitRow>),  // 数据可用
    Stale(Vec<StatusRateLimitRow>),      // 数据陈旧（>15 分钟）
    Missing,                              // 数据缺失
}
```

**陈旧数据检测**：
```rust
const RATE_LIMIT_STALE_THRESHOLD_MINUTES: i64 = 15;
```

**进度条渲染**：
```rust
const STATUS_LIMIT_BAR_SEGMENTS: usize = 20;
const STATUS_LIMIT_BAR_FILLED: &str = "█";
const STATUS_LIMIT_BAR_EMPTY: &str = "░";

// 示例输出：[███████████░░░░░░░░░] 55% left
```

**多限制桶支持**：
- 支持 `codex` 主限制桶和其他限制桶（如 `codex-other`）
- 单限制桶时合并显示标签（如 "codex-other 5h limit"）
- 多限制桶时分组显示

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 `/status` 命令执行流程

```
用户输入 /status
    ↓
SlashCommand::Status 匹配（slash_command.rs:39）
    ↓
ChatWidget::add_status_output()（chatwidget.rs:5700）
    ↓
status::new_status_output_with_rate_limits()
    ↓
StatusHistoryCell::new() 构建数据
    ↓
StatusHistoryCell::display_lines() 渲染为 Line
    ↓
添加到历史记录显示
```

#### 3.1.2 速率限制数据流

```
Backend Client 获取 RateLimitSnapshot（protocol 类型）
    ↓
rate_limit_snapshot_display_for_limit() 转换为显示类型
    ↓
compose_rate_limit_data_many() 构建行数据
    ↓
检测陈旧数据（与当前时间比较 >15 分钟）
    ↓
rate_limit_row_lines() 渲染进度条和重置时间
```

### 3.2 数据结构关系

```rust
// 协议层数据（来自后端）
protocol::RateLimitSnapshot {
    limit_id: Option<String>,
    limit_name: Option<String>,
    primary: Option<RateLimitWindow>,      // used_percent, window_minutes, resets_at
    secondary: Option<RateLimitWindow>,
    credits: Option<CreditsSnapshot>,      // has_credits, unlimited, balance
    plan_type: Option<PlanType>,
}

// 显示层数据（status 模块转换后）
RateLimitSnapshotDisplay {
    limit_name: String,
    captured_at: DateTime<Local>,          // 本地时间戳
    primary: Option<RateLimitWindowDisplay>,
    secondary: Option<RateLimitWindowDisplay>,
    credits: Option<CreditsSnapshotDisplay>,
}

// 最终渲染数据
StatusRateLimitRow {
    label: String,                         // "5h limit", "Weekly limit", "Credits"
    value: StatusRateLimitValue::Window {  // 或 Text
        percent_used: f64,
        resets_at: Option<String>,
    },
}
```

### 3.3 关键算法

#### 3.3.1 Token 数量紧凑格式化

```rust
pub(crate) fn format_tokens_compact(value: i64) -> String {
    let value = value.max(0);
    if value < 1_000 { return value.to_string(); }
    
    let (scaled, suffix) = match value {
        v if v >= 1_000_000_000_000 => (v as f64 / 1e12, "T"),
        v if v >= 1_000_000_000 => (v as f64 / 1e9, "B"),
        v if v >= 1_000_000 => (v as f64 / 1e6, "M"),
        _ => (v as f64 / 1e3, "K"),
    };
    
    // 动态小数位：<10 保留 2 位，<100 保留 1 位，否则整数
    let decimals = if scaled < 10.0 { 2 } else if scaled < 100.0 { 1 } else { 0 };
    format!("{scaled:.decimals$}{suffix}").trim_end_matches(".0").to_string()
}
```

#### 3.3.2 进度条渲染

```rust
pub(crate) fn render_status_limit_progress_bar(percent_remaining: f64) -> String {
    let ratio = (percent_remaining / 100.0).clamp(0.0, 1.0);
    let filled = (ratio * 20.0).round() as usize;
    let empty = 20 - filled;
    format!("[{}{}]", "█".repeat(filled), "░".repeat(empty))
}
```

#### 3.3.3 陈旧数据检测

```rust
pub(crate) const RATE_LIMIT_STALE_THRESHOLD_MINUTES: i64 = 15;

fn is_stale(snapshot: &RateLimitSnapshotDisplay, now: DateTime<Local>) -> bool {
    now.signed_duration_since(snapshot.captured_at) > Duration::minutes(15)
}
```

### 3.4 协议与接口

#### 3.4.1 公共导出接口（mod.rs）

```rust
// 主入口函数
pub(crate) use card::new_status_output;
pub(crate) use card::new_status_output_with_rate_limits;

// 速率限制相关
pub(crate) use rate_limits::RateLimitSnapshotDisplay;
pub(crate) use rate_limits::RateLimitWindowDisplay;
pub(crate) use rate_limits::rate_limit_snapshot_display_for_limit;

// 辅助函数（供其他模块使用）
pub(crate) use helpers::format_directory_display;
pub(crate) use helpers::format_tokens_compact;
```

#### 3.4.2 与 protocol 模块的关系

```
codex_protocol::protocol::RateLimitSnapshot  ← 后端 API 响应
              ↓ 转换
status::RateLimitSnapshotDisplay             ← 显示层使用
```

---

## 4. 关键代码路径与文件引用

### 4.1 调用方（入口点）

| 调用方 | 文件 | 函数 | 用途 |
|--------|------|------|------|
| Slash 命令处理 | `chatwidget.rs:4553` | `add_status_output()` | `/status` 命令 |
| 状态栏 | `bottom_pane/footer.rs:47` | `format_tokens_compact()` | Token 格式化 |
| 状态栏 | `chatwidget.rs:47-50` | 多个辅助函数 | 状态栏数据显示 |
| 主题选择器 | `theme_picker.rs:38` | `format_directory_display()` | 目录格式化 |

### 4.2 被调用方（依赖）

| 被调用方 | 文件 | 用途 |
|----------|------|------|
| `HistoryCell` trait | `history_cell.rs:98` | 实现显示接口 |
| `CompositeHistoryCell` | `history_cell.rs:1369` | 组合命令和卡片 |
| `PlainHistoryCell` | `history_cell.rs:474` | `/status` 命令标签 |
| `with_border_with_inner_width` | `history_cell.rs:1014` | 边框渲染 |
| `discover_project_doc_paths` | `codex_core::project_doc` | AGENTS.md 发现 |
| `AuthManager` | `codex_core::AuthManager` | 账户信息获取 |
| `summarize_sandbox_policy` | `codex_utils_sandbox_summary` | 沙盒策略摘要 |

### 4.3 核心代码路径

```
# 主渲染路径
status/card.rs:412  impl HistoryCell for StatusHistoryCell
    → display_lines(width: u16) -> Vec<Line<'static>>
        → 构建标签列表（labels）
        → 创建 FieldFormatter
        → 渲染各行数据
        → with_border_with_inner_width() 添加边框

# 速率限制渲染路径
status/card.rs:307  fn rate_limit_lines()
    → 根据 StatusRateLimitData 状态分支
    → rate_limit_row_lines() 渲染每行
        → render_status_limit_progress_bar() 进度条
        → format_status_limit_summary() 百分比文本

# 数据构建路径
status/card.rs:150  fn new()
    → 从 Config 提取配置项
    → compose_model_display() 构建模型显示
    → compose_agents_summary() 发现 AGENTS.md
    → compose_account_display() 获取账户信息
    → compose_rate_limit_data_many() 构建限制数据
```

---

## 5. 依赖与外部交互

### 5.1 模块依赖图

```
status/
├── 依赖 codex_core::
│   ├── AuthManager              # 账户认证信息
│   ├── config::Config           # 配置数据
│   ├── project_doc              # AGENTS.md 发现
│   └── WireApi                  # API 类型判断
│
├── 依赖 codex_protocol::
│   ├── ThreadId                 # 会话 ID
│   ├── account::PlanType        # 套餐类型
│   ├── openai_models::ReasoningEffort
│   └── protocol::*              # RateLimitSnapshot, TokenUsage, etc.
│
├── 依赖 codex_utils_sandbox_summary
│   └── summarize_sandbox_policy # 沙盒策略摘要
│
├── 依赖 ratatui
│   ├── Line, Span, Style        # 渲染基元
│   └── Stylize trait            # 样式辅助
│
└── 依赖外部 crate
    ├── chrono                   # 时间处理
    ├── unicode_width            # Unicode 宽字符计算
    └── url                      # URL 处理（base_url 脱敏）
```

### 5.2 与 TUI 其他模块的交互

```
┌─────────────────────────────────────────────────────────────┐
│                      ChatWidget                             │
│  ┌─────────────────┐         ┌─────────────────────────────┐│
│  │  SlashCommand   │────────▶│  add_status_output()        ││
│  │  ::Status       │         │  (chatwidget.rs:5700)       ││
│  └─────────────────┘         └─────────────────────────────┘│
│                                         │                   │
│                                         ▼                   │
│                          ┌─────────────────────────────┐    │
│                          │  status::new_status_output  │    │
│                          │  _with_rate_limits()        │    │
│                          └─────────────────────────────┘    │
│                                         │                   │
│                                         ▼                   │
│                          ┌─────────────────────────────┐    │
│                          │  StatusHistoryCell          │    │
│                          │  (impl HistoryCell)         │    │
│                          └─────────────────────────────┘    │
│                                         │                   │
│                                         ▼                   │
│                          ┌─────────────────────────────┐    │
│                          │  History (聊天历史)          │    │
│                          └─────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### 5.3 配置依赖

| 配置项 | 用途 |
|--------|------|
| `config.cwd` | 当前工作目录显示 |
| `config.model` | 模型名称 |
| `config.model_provider_id` | 模型提供商标识 |
| `config.model_provider.wire_api` | 判断是否为 Responses API |
| `config.model_reasoning_summary` | 推理摘要配置 |
| `config.permissions.approval_policy` | 审批策略 |
| `config.permissions.sandbox_policy` | 沙盒策略 |
| `config.tui_status_line` | 状态栏项目配置 |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 陈旧数据风险

**问题**：速率限制数据可能超过 15 分钟未更新，显示 "stale" 警告。

**代码位置**：`rate_limits.rs:58`

**缓解**：UI 显示警告文本 "limits may be stale - start new turn to refresh"

#### 6.1.2 Token 用量隐藏逻辑

**问题**：ChatGPT 订阅用户的 Token 用量被隐藏（商业决策），但代码硬编码了此逻辑。

**代码位置**：`card.rs:530`

```rust
// Hide token usage only for ChatGPT subscribers
if !matches!(self.account, Some(StatusAccountDisplay::ChatGpt { .. })) {
    lines.push(formatter.line("Token usage", self.token_usage_spans()));
}
```

**风险**：如果业务逻辑变化，需要修改代码。

#### 6.1.3 时区处理

**问题**：重置时间从 UTC 转换为本地时间，依赖系统时区设置。

**代码位置**：`rate_limits.rs:72-77`

```rust
let resets_at_utc = window.resets_at
    .and_then(|seconds| DateTime::<Utc>::from_timestamp(seconds, 0))
    .map(|dt| dt.with_timezone(&Local));
```

### 6.2 边界情况

#### 6.2.1 终端宽度极窄

**处理**：当 `available_inner_width == 0` 时返回空向量。

**代码位置**：`card.rs:424`

#### 6.2.2 速率限制数据缺失

**处理**：显示 "data not available yet"

**代码位置**：`card.rs:316, 332`

#### 6.2.3 零额度账户

**处理**：当 `balance` 为 "0" 或 `has_credits` 为 false 时，隐藏 Credits 行。

**代码位置**：`rate_limits.rs:306-308, 323-342`

#### 6.2.4 多限制桶显示

**边界**：非 "codex" 限制桶且只有一个窗口时，合并显示标签（如 "codex-other 5h limit"）。

**代码位置**：`rate_limits.rs:207-227`

### 6.3 改进建议

#### 6.3.1 可配置的陈旧阈值

当前 15 分钟阈值是硬编码的常量，建议改为可配置：

```rust
// 当前
const RATE_LIMIT_STALE_THRESHOLD_MINUTES: i64 = 15;

// 建议：从 config 读取
config.rate_limit_stale_threshold_minutes.unwrap_or(15)
```

#### 6.3.2 国际化支持

当前所有文本都是硬编码的英文，建议：
- 添加 i18n 框架支持
- 将用户可见文本提取到资源文件

#### 6.3.3 测试覆盖

当前测试主要依赖快照测试（insta），建议：
- 增加单元测试覆盖边界情况（如极窄终端、空数据）
- 增加属性测试（proptest）验证格式化函数

#### 6.3.4 性能优化

`display_lines()` 每次调用都重新计算所有行，对于频繁刷新的场景（如状态栏）可以考虑：
- 缓存计算结果（当输入数据未变化时）
- 使用 Cow<'static, str> 减少克隆

#### 6.3.5 代码结构

`card.rs` 文件接近 600 行，建议：
- 将 `StatusHistoryCell` 的渲染逻辑拆分为子模块
- 按功能分组（token 渲染、限制渲染、账户渲染等）

### 6.4 相关测试

| 测试文件 | 测试类型 | 覆盖场景 |
|----------|----------|----------|
| `tests.rs` | 快照测试 | 完整 `/status` 输出 |
| `tests.rs` | 单元测试 | 权限显示、token 格式化、陈旧数据 |
| `rate_limits.rs` (mod tests) | 单元测试 | 多限制桶标签生成 |

**快照测试列表**：
- `status_snapshot_includes_reasoning_details`
- `status_snapshot_includes_forked_from`
- `status_snapshot_includes_monthly_limit`
- `status_snapshot_includes_credits_and_limits`
- `status_snapshot_truncates_in_narrow_terminal`
- `status_snapshot_shows_missing_limits_message`
- `status_snapshot_shows_empty_limits_message`
- `status_snapshot_shows_stale_limits_message`
- `status_snapshot_cached_limits_hide_credits_without_flag`

---

## 7. 附录：关键代码片段

### 7.1 权限显示逻辑

```rust
// card.rs:216-227
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

### 7.2 速率限制行渲染

```rust
// rate_limits.rs:284-294
pub(crate) fn render_status_limit_progress_bar(percent_remaining: f64) -> String {
    let ratio = (percent_remaining / 100.0).clamp(0.0, 1.0);
    let filled = (ratio * STATUS_LIMIT_BAR_SEGMENTS as f64).round() as usize;
    let filled = filled.min(STATUS_LIMIT_BAR_SEGMENTS);
    let empty = STATUS_LIMIT_BAR_SEGMENTS.saturating_sub(filled);
    format!(
        "[{}{}]",
        STATUS_LIMIT_BAR_FILLED.repeat(filled),
        STATUS_LIMIT_BAR_EMPTY.repeat(empty)
    )
}
```

### 7.3 账户显示构建

```rust
// helpers.rs:87-103
pub(crate) fn compose_account_display(
    auth_manager: &AuthManager,
    plan: Option<PlanType>,
) -> Option<StatusAccountDisplay> {
    let auth = auth_manager.auth_cached()?;
    match auth.auth_mode() {
        CoreAuthMode::ApiKey => Some(StatusAccountDisplay::ApiKey),
        CoreAuthMode::Chatgpt => {
            let email = auth.get_account_email();
            let plan = plan
                .map(|plan_type| title_case(format!("{plan_type:?}").as_str()))
                .or_else(|| Some("Unknown".to_string()));
            Some(StatusAccountDisplay::ChatGpt { email, plan })
        }
    }
}
```

---

*文档生成时间：2026-03-22*
*研究范围：codex-rs/tui/src/status 目录及其直接依赖*
