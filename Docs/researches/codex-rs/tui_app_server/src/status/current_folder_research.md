# 研究文档：codex-rs/tui_app_server/src/status 目录

## 1. 场景与职责

`status` 目录是 Codex TUI（Terminal User Interface）应用中负责**状态输出格式化与显示适配**的核心模块。其主要职责包括：

1. **协议层快照到显示结构的转换**：将来自协议层（`codex_protocol`）的原始数据（如 `RateLimitSnapshot`、`TokenUsageInfo`）转换为适合 TUI 渲染的显示结构。
2. **`/status` 命令输出**：当用户在 TUI 中输入 `/status` 斜杠命令时，生成格式化的状态卡片输出。
3. **状态栏（Status Line）数据支持**：为底部状态栏提供格式化后的数据，包括速率限制、Token 使用量、上下文窗口等。
4. **账户信息显示**：处理 ChatGPT 账户和 API Key 认证方式的显示差异。

该模块的设计原则是**将渲染关注点与传输层代码分离**，确保协议层代码保持纯净，而 TUI 层获得稳定的显示结构。

## 2. 功能点目的

### 2.1 核心功能模块

| 模块 | 文件 | 功能目的 |
|------|------|----------|
| 账户显示 | `account.rs` | 定义账户显示类型（ChatGPT 邮箱/套餐 或 API Key） |
| 状态卡片 | `card.rs` | 构建 `/status` 命令输出的完整状态卡片 |
| 格式化工具 | `format.rs` | 提供字段格式化、行宽计算、文本截断等工具 |
| 辅助函数 | `helpers.rs` | 提供 Agents.md 路径汇总、Token 格式化、目录显示等辅助功能 |
| 速率限制 | `rate_limits.rs` | 处理速率限制快照的显示转换和进度条渲染 |
| 测试 | `tests.rs` | 包含全面的快照测试（insta snapshot tests） |

### 2.2 关键功能点详细说明

#### 2.2.1 `/status` 命令输出（Status Card）

当用户执行 `/status` 命令时，系统会生成一个包含以下信息的格式化卡片：

- **OpenAI Codex 版本信息**：显示 CLI 版本号
- **模型信息**：模型名称、推理努力级别（reasoning effort）、推理摘要设置
- **工作目录**：当前工作目录（支持 home 目录简化为 `~`）
- **权限配置**：沙盒策略和审批策略的汇总显示
- **Agents.md**：检测并显示项目中 Agents.md 文件的位置
- **账户信息**：ChatGPT 用户显示邮箱和套餐，API Key 用户显示相应提示
- **线程信息**：线程名称、Session ID、Fork 来源
- **Token 使用**：总使用量、输入/输出分解、上下文窗口使用情况
- **速率限制**：5小时限制、周限制、积分余额（带进度条可视化）

#### 2.2.2 速率限制显示（Rate Limits）

速率限制模块支持以下特性：

- **多限制桶支持**：支持 `codex` 主限制桶和其他限制桶（如 `codex-other`）
- **双窗口显示**：主窗口（通常 5 小时）和次窗口（通常周限制）
- **积分显示**：支持无限积分、具体积分余额、零积分隐藏
- **陈旧数据检测**：15 分钟阈值，超过则显示警告
- **进度条可视化**：20 段 Unicode 块字符进度条（`█` 和 `░`）

#### 2.2.3 Token 使用格式化

- **紧凑格式**：大数字使用 K/M/B/T 后缀（如 1.2K、3.5M）
- **上下文窗口计算**：显示已使用百分比和剩余百分比
- **缓存 Token 处理**：输入 Token 排除缓存部分，避免重复计算

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 账户显示类型 (`account.rs`)

```rust
#[derive(Debug, Clone)]
pub(crate) enum StatusAccountDisplay {
    ChatGpt {
        email: Option<String>,
        plan: Option<String>,
    },
    ApiKey,
}
```

#### 3.1.2 状态历史单元格 (`card.rs`)

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

#### 3.1.3 Token 使用数据 (`card.rs`)

```rust
#[derive(Debug, Clone)]
pub(crate) struct StatusTokenUsageData {
    total: i64,
    input: i64,
    output: i64,
    context_window: Option<StatusContextWindowData>,
}

#[derive(Debug, Clone)]
struct StatusContextWindowData {
    percent_remaining: i64,
    tokens_in_context: i64,
    window: i64,
}
```

#### 3.1.4 速率限制显示结构 (`rate_limits.rs`)

```rust
#[derive(Debug, Clone)]
pub(crate) struct RateLimitSnapshotDisplay {
    pub limit_name: String,
    pub captured_at: DateTime<Local>,
    pub primary: Option<RateLimitWindowDisplay>,
    pub secondary: Option<RateLimitWindowDisplay>,
    pub credits: Option<CreditsSnapshotDisplay>,
}

#[derive(Debug, Clone)]
pub(crate) struct RateLimitWindowDisplay {
    pub used_percent: f64,
    pub resets_at: Option<String>,
    pub window_minutes: Option<i64>,
}

#[derive(Debug, Clone)]
pub(crate) enum StatusRateLimitData {
    Available(Vec<StatusRateLimitRow>),
    Stale(Vec<StatusRateLimitRow>),
    Missing,
}
```

### 3.2 关键流程

#### 3.2.1 `/status` 命令执行流程

```
用户输入 /status
    ↓
ChatWidget::add_status_output() 被调用
    ↓
收集当前状态数据：
    - config: &Config
    - status_account_display: Option<&StatusAccountDisplay>
    - token_info: Option<&TokenUsageInfo>
    - total_usage: TokenUsage
    - rate_limit_snapshots: Vec<RateLimitSnapshotDisplay>
    ↓
new_status_output_with_rate_limits() 创建 CompositeHistoryCell
    ↓
StatusHistoryCell::new() 构建状态数据
    ↓
HistoryCell::display_lines() 渲染为 ratatui Line 列表
    ↓
添加到历史记录显示
```

#### 3.2.2 速率限制数据处理流程

```
RateLimitSnapshot (protocol)
    ↓
rate_limit_snapshot_display_for_limit() 转换为显示结构
    ↓
compose_rate_limit_data_many() 构建行数据
    ↓
检测陈旧数据（>15分钟）
    ↓
生成 StatusRateLimitRow 列表
    ↓
渲染进度条和重置时间
```

### 3.3 协议与接口

#### 3.3.1 输入协议类型（来自 codex_protocol）

```rust
// protocol/src/protocol.rs
pub struct RateLimitSnapshot {
    pub limit_id: Option<String>,
    pub limit_name: Option<String>,
    pub primary: Option<RateLimitWindow>,
    pub secondary: Option<RateLimitWindow>,
    pub credits: Option<CreditsSnapshot>,
    pub plan_type: Option<crate::account::PlanType>,
}

pub struct RateLimitWindow {
    pub used_percent: f64,
    pub window_minutes: Option<i64>,
    pub resets_at: Option<i64>,  // Unix timestamp
}

pub struct CreditsSnapshot {
    pub has_credits: bool,
    pub unlimited: bool,
    pub balance: Option<String>,
}

pub struct TokenUsageInfo {
    pub total_token_usage: TokenUsage,
    pub last_token_usage: TokenUsage,
    pub model_context_window: Option<i64>,
}

pub struct TokenUsage {
    pub input_tokens: i64,
    pub cached_input_tokens: i64,
    pub output_tokens: i64,
    pub reasoning_output_tokens: i64,
    pub total_tokens: i64,
}
```

#### 3.3.2 模块公共接口 (`mod.rs`)

```rust
pub(crate) use account::StatusAccountDisplay;
pub(crate) use card::new_status_output_with_rate_limits;
pub(crate) use helpers::format_directory_display;
pub(crate) use helpers::format_tokens_compact;
pub(crate) use rate_limits::RateLimitSnapshotDisplay;
pub(crate) use rate_limits::RateLimitWindowDisplay;
pub(crate) use rate_limits::rate_limit_snapshot_display_for_limit;
```

### 3.4 格式化技术细节

#### 3.4.1 字段格式化器 (`format.rs`)

`FieldFormatter` 提供对齐的标签-值格式化：

```rust
pub(crate) struct FieldFormatter {
    indent: &'static str,      // " "
    label_width: usize,        // 最大标签宽度
    value_offset: usize,       // 值起始偏移
    value_indent: String,      // 续行缩进
}
```

示例输出：
```
 Model:        gpt-5.1-codex-max (reasoning high, summaries detailed)
 Directory:    ~/workspace/project
 Permissions:  Default
```

#### 3.4.2 进度条渲染 (`rate_limits.rs`)

```rust
const STATUS_LIMIT_BAR_SEGMENTS: usize = 20;
const STATUS_LIMIT_BAR_FILLED: &str = "█";
const STATUS_LIMIT_BAR_EMPTY: &str = "░";

pub(crate) fn render_status_limit_progress_bar(percent_remaining: f64) -> String {
    let ratio = (percent_remaining / 100.0).clamp(0.0, 1.0);
    let filled = (ratio * STATUS_LIMIT_BAR_SEGMENTS as f64).round() as usize;
    let empty = STATUS_LIMIT_BAR_SEGMENTS.saturating_sub(filled);
    format!("[{}{}]", STATUS_LIMIT_BAR_FILLED.repeat(filled), STATUS_LIMIT_BAR_EMPTY.repeat(empty))
}
```

#### 3.4.3 Token 紧凑格式化 (`helpers.rs`)

```rust
pub(crate) fn format_tokens_compact(value: i64) -> String {
    let value = value.max(0);
    if value < 1_000 { return value.to_string(); }
    
    let (scaled, suffix) = match value {
        v if v >= 1_000_000_000_000 => (value_f64 / 1_000_000_000_000.0, "T"),
        v if v >= 1_000_000_000 => (value_f64 / 1_000_000_000.0, "B"),
        v if v >= 1_000_000 => (value_f64 / 1_000_000.0, "M"),
        _ => (value_f64 / 1_000.0, "K"),
    };
    
    // 动态小数位：小于10保留2位，小于100保留1位，否则整数
    format!("{scaled:.decimals$}{suffix}")
}
```

## 4. 关键代码路径与文件引用

### 4.1 核心文件结构

```
codex-rs/tui_app_server/src/status/
├── mod.rs           # 模块入口，公共接口导出
├── account.rs       # 账户显示类型定义
├── card.rs          # 状态卡片构建（~584行）
├── format.rs        # 格式化工具（~147行）
├── helpers.rs       # 辅助函数（~160行）
├── rate_limits.rs   # 速率限制处理（~440行）
└── tests.rs         # 测试用例（~1026行）
```

### 4.2 关键代码路径

#### 4.2.1 状态卡片生成入口

**文件**: `card.rs:114-147`
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
) -> CompositeHistoryCell {
    let command = PlainHistoryCell::new(vec!["/status".magenta().into()]);
    let card = StatusHistoryCell::new(...);
    CompositeHistoryCell::new(vec![Box::new(command), Box::new(card)])
}
```

#### 4.2.2 速率限制数据组合

**文件**: `rate_limits.rs:168-278`
```rust
pub(crate) fn compose_rate_limit_data_many(
    snapshots: &[RateLimitSnapshotDisplay],
    now: DateTime<Local>,
) -> StatusRateLimitData {
    // 1. 检查空数据
    // 2. 遍历每个快照，检测陈旧数据
    // 3. 构建行标签（处理 codex vs 其他限制桶）
    // 4. 为主/次窗口创建 StatusRateLimitRow
    // 5. 添加积分行（如适用）
    // 6. 返回 Available/Stale/Missing 状态
}
```

#### 4.2.3 显示行渲染

**文件**: `card.rs:411-548`
```rust
impl HistoryCell for StatusHistoryCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        // 1. 构建标签列表（动态根据可用数据）
        // 2. 创建 FieldFormatter 进行对齐
        // 3. 逐行渲染各字段
        // 4. 处理速率限制行的特殊布局（进度条+重置时间）
        // 5. 应用边框和截断
    }
}
```

### 4.3 调用方引用

#### 4.3.1 ChatWidget 调用

**文件**: `chatwidget.rs:6791-6826`
```rust
pub(crate) fn add_status_output(&mut self) {
    let default_usage = TokenUsage::default();
    let token_info = self.token_info.as_ref();
    let total_usage = token_info
        .map(|info| &info.total_token_usage)
        .unwrap_or(&default_usage);
    let rate_limit_snapshots: Vec<RateLimitSnapshotDisplay> = self
        .rate_limit_snapshots_by_limit_id
        .values()
        .cloned()
        .collect();
    self.add_to_history(crate::status::new_status_output_with_rate_limits(
        &self.config,
        self.status_account_display.as_ref(),
        token_info,
        total_usage,
        &self.thread_id,
        self.session_header.thread_name(),
        self.session_header.forked_from(),
        &rate_limit_snapshots,
        self.initial_plan_type,
        Local::now(),
        &self.model_display_name(),
        self.collaboration_mode.as_deref(),
        self.reasoning_effort_override,
    ));
}
```

#### 4.3.2 斜杠命令处理

**文件**: `chatwidget.rs:4785-4788`
```rust
SlashCommand::Status => {
    self.add_status_output();
}
```

## 5. 依赖与外部交互

### 5.1 内部依赖（tui_app_server 内）

| 依赖模块 | 用途 |
|----------|------|
| `history_cell` | `HistoryCell` trait、`CompositeHistoryCell`、`PlainHistoryCell` |
| `version` | `CODEX_CLI_VERSION` 常量 |
| `wrapping` | 文本自适应换行 (`adaptive_wrap_lines`) |
| `text_formatting` | `capitalize_first`、`center_truncate_path` |
| `exec_command` | `relativize_to_home` |
| `chatwidget` | 状态栏速率限制显示辅助函数 |

### 5.2 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染（`Line`, `Span`, `Stylize` 等） |
| `chrono` | 时间处理（`DateTime`, `Local`, `Duration`） |
| `unicode_width` | Unicode 字符宽度计算 |
| `url` | URL 解析和清理（`sanitize_base_url`） |
| `codex_core` | `Config`、`WireApi`、项目文档发现 |
| `codex_protocol` | `RateLimitSnapshot`、`TokenUsageInfo`、`TokenUsage`、`ThreadId`、`SandboxPolicy`、`AskForApproval` 等 |
| `codex_utils_sandbox_summary` | `summarize_sandbox_policy` |

### 5.3 协议层交互

```
┌─────────────────────────────────────────────────────────────┐
│                    Protocol Layer                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ RateLimit    │  │ TokenUsage   │  │   Config     │      │
│  │ Snapshot     │  │    Info      │  │              │      │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘      │
└─────────┼─────────────────┼─────────────────┼──────────────┘
          │                 │                 │
          ▼                 ▼                 ▼
┌─────────────────────────────────────────────────────────────┐
│                   status Module                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  rate_limit_snapshot_display_for_limit()            │   │
│  │  compose_rate_limit_data_many()                     │   │
│  │  StatusHistoryCell::new()                           │   │
│  └─────────────────────────────────────────────────────┘   │
│                          │                                  │
│                          ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  HistoryCell::display_lines()                       │   │
│  │  FieldFormatter, render_status_limit_progress_bar() │   │
│  └─────────────────────────────────────────────────────┘   │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                     TUI Rendering                           │
│              (ratatui Line/Span widgets)                    │
└─────────────────────────────────────────────────────────────┘
```

## 6. 风险、边界与改进建议

### 6.1 已知风险与边界情况

#### 6.1.1 陈旧数据检测

- **阈值固定**：`RATE_LIMIT_STALE_THRESHOLD_MINUTES = 15` 是硬编码常量
- **风险**：在网络不稳定或长时间离线使用时，用户可能看到过时的速率限制信息
- **缓解**：UI 会显示 "limits may be stale - start new turn to refresh" 警告

#### 6.1.2 Token 使用计算

- **缓存 Token 排除**：`non_cached_input()` 方法从输入中减去缓存 Token
- **风险**：用户可能对 "input" 的定义产生困惑（是否包含缓存）
- **当前行为**：状态显示明确标注为 "input"（非缓存）+ "output"

#### 6.1.3 多限制桶显示

- **复杂性**：当存在多个限制桶（如 `codex` 和 `codex-other`）时，标签生成逻辑复杂
- **边界**：`combine_non_codex_single_limit` 逻辑处理单窗口非 codex 限制的特殊情况

#### 6.1.4 窗口宽度处理

- **最小宽度**：`available_inner_width == 0` 时返回空行
- **截断**：长路径和长模型名称会被截断，可能丢失信息

### 6.2 测试覆盖

测试文件 `tests.rs` 包含 18+ 个测试用例，覆盖：

- 推理详情显示（`status_snapshot_includes_reasoning_details`）
- 权限显示（`status_permissions_non_default_workspace_write_is_custom`）
- Fork 来源显示（`status_snapshot_includes_forked_from`）
- 月度限制（`status_snapshot_includes_monthly_limit`）
- 积分显示（无限、正数、零、无积分标志）
- Token 使用（排除缓存 Token）
- 窄终端截断（`status_snapshot_truncates_in_narrow_terminal`）
- 缺失/空限制消息
- 陈旧限制消息
- 上下文窗口使用计算

### 6.3 改进建议

#### 6.3.1 可配置的陈旧阈值

```rust
// 建议：从配置读取而非硬编码
const RATE_LIMIT_STALE_THRESHOLD_MINUTES: i64 = 15;
```

#### 6.3.2 增强的积分格式化

当前积分格式化仅支持整数和简单浮点数：

```rust
// helpers.rs:323-343
fn format_credit_balance(raw: &str) -> Option<String> {
    // 可扩展支持货币符号、千位分隔符等
}
```

#### 6.3.3 状态卡片缓存

当前每次 `/status` 调用都重新构建整个卡片。对于静态数据（如版本、模型配置），可考虑缓存优化。

#### 6.3.4 国际化支持

当前所有标签和消息都是硬编码英文：

```rust
// card.rs:439
let mut labels: Vec<String> = vec!["Model", "Directory", "Permissions", "Agents.md"]
```

建议未来支持 i18n。

#### 6.3.5 与 tui 模块的代码共享

根据 AGENTS.md 的约定：

> When a change lands in `codex-rs/tui` and `codex-rs/tui_app_server` has a parallel implementation of the same behavior, reflect the change in `codex-rs/tui_app_server` too unless there is a documented reason not to.

当前 `tui/src/status/` 和 `tui_app_server/src/status/` 存在代码重复，建议：
1. 提取公共代码到共享 crate
2. 或者建立代码同步机制

### 6.4 性能考虑

- **渲染频率**：`/status` 是用户触发的低频操作，渲染开销可接受
- **内存分配**：每次渲染创建新的 `Vec<Line>` 和 `String`，对于状态卡片的大小（通常 <100 行）性能影响可忽略
- **快照测试**：使用 insta 进行快照测试，确保 UI 变更可审查

---

**文档生成时间**: 2026-03-22
**研究范围**: codex-rs/tui_app_server/src/status 目录及其上下游依赖
**相关协议版本**: codex_protocol v2
