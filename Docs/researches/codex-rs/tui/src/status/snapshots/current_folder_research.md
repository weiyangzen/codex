# Codex TUI Status Module Research

## 目录
- [场景与职责](#场景与职责)
- [功能点目的](#功能点目的)
- [具体技术实现](#具体技术实现)
- [关键代码路径与文件引用](#关键代码路径与文件引用)
- [依赖与外部交互](#依赖与外部交互)
- [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 模块定位

`codex-rs/tui/src/status/` 模块是 Codex TUI（终端用户界面）中负责 **状态展示与格式化** 的核心组件。该模块将协议层（protocol-level）的原始数据转换为稳定的显示结构，用于 `/status` 命令输出以及页脚（footer）/状态栏（status-line）辅助显示。

### 核心职责

1. **状态卡片渲染**：将配置、认证、令牌使用、速率限制等数据格式化为美观的终端界面卡片
2. **速率限制可视化**：将 `RateLimitSnapshot` 协议数据转换为进度条、百分比和重置时间等用户友好的显示
3. **数据格式化**：提供统一的字段格式化、文本截断、令牌数量压缩显示等工具函数
4. **账户信息展示**：处理 ChatGPT 账户与 API Key 两种认证模式下的账户信息显示

### 目录结构

```
codex-rs/tui/src/status/
├── mod.rs           # 模块入口，导出公共接口
├── account.rs       # 账户信息显示类型定义
├── card.rs          # 状态卡片核心实现（StatusHistoryCell）
├── format.rs        # 字段格式化工具（FieldFormatter）
├── helpers.rs       # 辅助函数（令牌格式化、路径显示等）
├── rate_limits.rs   # 速率限制数据转换与显示
├── tests.rs         # 单元测试
└── snapshots/       # insta 快照测试文件（9个 .snap 文件）
```

---

## 功能点目的

### 1. `/status` 命令输出

当用户在 TUI 中输入 `/status` 时，系统会生成一个复合历史单元格（`CompositeHistoryCell`），包含：
- 命令提示（`/status` 前缀）
- 状态卡片（`StatusHistoryCell`）

状态卡片展示的信息包括：

| 信息类别 | 说明 |
|---------|------|
| 模型信息 | 当前使用的模型名称、推理 effort、摘要设置 |
| 工作目录 | 当前工作目录（支持 home 目录简写为 `~`）|
| 权限配置 | 沙盒策略与审批策略的组合显示 |
| Agents.md | 项目文档的发现与显示 |
| 账户信息 | ChatGPT 邮箱/套餐或 API Key 模式 |
| 会话信息 | Session ID、线程名称、Fork 来源 |
| 令牌使用 | 总输入/输出令牌数 |
| 上下文窗口 | 剩余百分比与使用详情 |
| 速率限制 | 5h/weekly/monthly 限制进度条与重置时间 |
| 积分余额 | Credits 余额显示（如适用）|

### 2. 速率限制状态管理

速率限制显示支持三种状态：
- **Available**：数据新鲜，正常渲染
- **Stale**：数据超过 15 分钟，显示警告提示
- **Missing**：无可用数据，显示 "data not available yet"

### 3. 多限制桶支持

系统支持多个速率限制桶（如 `codex`、`codex-other`），每个桶可包含：
- Primary 窗口（通常是 5 小时）
- Secondary 窗口（通常是 weekly）
- Credits 信息（余额、是否无限）

---

## 具体技术实现

### 关键数据结构

#### 1. StatusHistoryCell（card.rs）

```rust
#[derive(Debug)]
struct StatusHistoryCell {
    model_name: String,
    model_details: Vec<String>,      // 推理 effort、摘要设置等
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

#### 2. RateLimitSnapshotDisplay（rate_limits.rs）

```rust
#[derive(Debug, Clone)]
pub(crate) struct RateLimitSnapshotDisplay {
    pub limit_name: String,              // 限制桶标识（如 "codex"）
    pub captured_at: DateTime<Local>,    // 本地捕获时间戳
    pub primary: Option<RateLimitWindowDisplay>,
    pub secondary: Option<RateLimitWindowDisplay>,
    pub credits: Option<CreditsSnapshotDisplay>,
}

#[derive(Debug, Clone)]
pub(crate) struct RateLimitWindowDisplay {
    pub used_percent: f64,               // 已使用百分比
    pub resets_at: Option<String>,       // 本地化重置时间文本
    pub window_minutes: Option<i64>,     // 窗口时长（分钟）
}
```

#### 3. StatusRateLimitData（rate_limits.rs）

```rust
#[derive(Debug, Clone)]
pub(crate) enum StatusRateLimitData {
    Available(Vec<StatusRateLimitRow>),
    Stale(Vec<StatusRateLimitRow>),
    Missing,
}

#[derive(Debug, Clone)]
pub(crate) struct StatusRateLimitRow {
    pub label: String,                   // 如 "5h limit"、"Credits"
    pub value: StatusRateLimitValue,
}

#[derive(Debug, Clone)]
pub(crate) enum StatusRateLimitValue {
    Window { percent_used: f64, resets_at: Option<String> },
    Text(String),
}
```

#### 4. FieldFormatter（format.rs）

用于对齐标签和值的格式化器：

```rust
#[derive(Debug, Clone)]
pub(crate) struct FieldFormatter {
    indent: &'static str,        // 缩进（默认 " "）
    label_width: usize,          // 最大标签宽度
    value_offset: usize,         // 值起始偏移
    value_indent: String,        // 续行缩进
}
```

### 核心流程

#### 1. 状态卡片生成流程

```
new_status_output() / new_status_output_with_rate_limits()
    ↓
StatusHistoryCell::new()
    ├── 构建配置条目（workdir、model、approval、sandbox）
    ├── compose_model_display() - 提取推理详情
    ├── compose_agents_summary() - 发现 Agents.md
    ├── compose_account_display() - 获取账户信息
    ├── 计算 token_usage（使用 last_token_usage 而非 total）
    └── compose_rate_limit_data() / compose_rate_limit_data_many()
        ↓
    StatusHistoryCell 实例
        ↓
display_lines() - 渲染为 ratatui Line 列表
    ├── 构建标签列表（动态根据可用数据）
    ├── 使用 FieldFormatter 对齐输出
    ├── rate_limit_lines() - 渲染速率限制行
    └── with_border_with_inner_width() - 添加边框
```

#### 2. 速率限制数据处理流程

```
RateLimitSnapshot (protocol)
    ↓
rate_limit_snapshot_display_for_limit()
    ├── RateLimitWindowDisplay::from_window() - 转换 primary
    ├── RateLimitWindowDisplay::from_window() - 转换 secondary
    └── CreditsSnapshotDisplay::from() - 转换 credits
    ↓
RateLimitSnapshotDisplay
    ↓
compose_rate_limit_data_many()
    ├── 检查数据新鲜度（>15分钟标记为 Stale）
    ├── 构建窗口标签（get_limits_duration 转换分钟数为可读文本）
    ├── 处理非 codex 限制桶的命名
    └── credit_status_row() - 添加 credits 行（如适用）
    ↓
StatusRateLimitData
```

#### 3. 窗口时长格式化（chatwidget.rs）

```rust
pub(crate) fn get_limits_duration(windows_minutes: i64) -> String {
    // 使用 ROUNDING_BIAS_MINUTES = 3 进行四舍五入
    // <= 1天+3分钟 -> 显示小时（如 "5h"）
    // <= 1周+3分钟 -> 显示天（如 "7d"）
    // <= 1月+3分钟 -> 显示周（如 "4w"）
    // > 1月 -> 显示月（如 "1mo"）
}
```

### 进度条渲染

```rust
const STATUS_LIMIT_BAR_SEGMENTS: usize = 20;
const STATUS_LIMIT_BAR_FILLED: &str = "█";
const STATUS_LIMIT_BAR_EMPTY: &str = "░";

pub(crate) fn render_status_limit_progress_bar(percent_remaining: f64) -> String {
    // 将剩余百分比转换为 20 段进度条
    // 如 55% left -> [███████████░░░░░░░░░]
}
```

### 令牌数量压缩显示

```rust
pub(crate) fn format_tokens_compact(value: i64) -> String {
    // < 1,000: 原样显示
    // < 1,000,000: 显示为 K（如 1.5K）
    // < 1,000,000,000: 显示为 M
    // < 1,000,000,000,000: 显示为 B
    // >= 1,000,000,000,000: 显示为 T
    // 小数位根据数值大小自适应（<10: 2位，<100: 1位，>=100: 0位）
}
```

---

## 关键代码路径与文件引用

### 入口函数

| 函数 | 位置 | 用途 |
|-----|------|------|
| `new_status_output()` | `card.rs:81` | 单限制桶状态卡片（向后兼容） |
| `new_status_output_with_rate_limits()` | `card.rs:115` | 多限制桶状态卡片（推荐） |
| `rate_limit_snapshot_display()` | `rate_limits.rs:117` | 单限制桶转换（测试用） |
| `rate_limit_snapshot_display_for_limit()` | `rate_limits.rs:124` | 指定限制桶转换 |
| `compose_rate_limit_data()` | `rate_limits.rs:158` | 单快照数据组合 |
| `compose_rate_limit_data_many()` | `rate_limits.rs:168` | 多快照数据组合 |

### 渲染关键路径

| 组件 | 位置 | 功能 |
|-----|------|------|
| `StatusHistoryCell::display_lines()` | `card.rs:413` | 主渲染逻辑 |
| `rate_limit_lines()` | `card.rs:307` | 速率限制行渲染 |
| `rate_limit_row_lines()` | `card.rs:337` | 单行速率限制渲染 |
| `FieldFormatter::line()` | `format.rs:38` | 标签值对格式化 |
| `with_border_with_inner_width()` | `history_cell.rs:1014` | 边框包装 |

### 测试快照文件（snapshots/）

| 快照文件 | 测试用例 | 覆盖场景 |
|---------|---------|---------|
| `status_snapshot_includes_reasoning_details.snap` | `status_snapshot_includes_reasoning_details` | 推理 effort 与摘要设置显示 |
| `status_snapshot_includes_credits_and_limits.snap` | `status_snapshot_includes_credits_and_limits` | 积分与速率限制同时显示 |
| `status_snapshot_includes_forked_from.snap` | `status_snapshot_includes_forked_from` | Fork 会话来源显示 |
| `status_snapshot_includes_monthly_limit.snap` | `status_snapshot_includes_monthly_limit` | 月度限制（43,200分钟）显示 |
| `status_snapshot_truncates_in_narrow_terminal.snap` | `status_snapshot_truncates_in_narrow_terminal` | 窄终端自动截断 |
| `status_snapshot_shows_missing_limits_message.snap` | `status_snapshot_shows_missing_limits_message` | 无限制数据时的提示 |
| `status_snapshot_shows_empty_limits_message.snap` | `status_snapshot_shows_empty_limits_message` | 空限制数据时的提示 |
| `status_snapshot_shows_stale_limits_message.snap` | `status_snapshot_shows_stale_limits_message` | 过期数据警告提示 |
| `status_snapshot_cached_limits_hide_credits_without_flag.snap` | `status_snapshot_cached_limits_hide_credits_without_flag` | has_credits=false 时隐藏积分 |

### 外部调用方

| 调用方 | 位置 | 调用目的 |
|-------|------|---------|
| `ChatWidget` | `chatwidget.rs:5700` | `/status` 命令触发状态卡片显示 |
| `ChatWidget::on_rate_limit_snapshot()` | `chatwidget.rs:1969` | 接收速率限制快照更新 |
| `ChatWidget::get_limits_duration()` | `chatwidget.rs:449` | 窗口时长格式化（共享函数） |
| `AppEvent` | `app_event.rs:132` | 速率限制快照事件定义 |

---

## 依赖与外部交互

### 内部依赖

| 模块 | 依赖类型 | 说明 |
|-----|---------|------|
| `history_cell` | 核心依赖 | `HistoryCell` trait、`CompositeHistoryCell`、`PlainHistoryCell`、`with_border_with_inner_width` |
| `chatwidget` | 函数共享 | `get_limits_duration` 被 `rate_limits.rs` 和 `chatwidget.rs` 共享 |
| `text_formatting` | 工具函数 | `capitalize_first`、`center_truncate_path` |
| `wrapping` | 文本换行 | `RtOptions`、`adaptive_wrap_lines` |
| `version` | 常量 | `CODEX_CLI_VERSION` |

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `ratatui` | 终端 UI 渲染（`Line`、`Span`、`Style`、`Stylize`） |
| `chrono` | 时间处理（`DateTime`、`Local`、`Utc`、`Duration`） |
| `unicode_width` | Unicode 字符宽度计算（`UnicodeWidthStr`、`UnicodeWidthChar`） |
| `codex_core` | 配置、认证管理器（`Config`、`AuthManager`） |
| `codex_protocol` | 协议类型（`RateLimitSnapshot`、`TokenUsage`、`ThreadId` 等） |
| `codex_utils_sandbox_summary` | 沙盒策略摘要（`summarize_sandbox_policy`） |
| `insta` | 快照测试（仅测试依赖） |
| `pretty_assertions` | 测试断言美化（仅测试依赖） |
| `tempfile` | 临时目录（仅测试依赖） |

### 协议类型映射

```
codex_protocol::protocol::RateLimitSnapshot
    ├── primary: Option<RateLimitWindow>
    │   ├── used_percent: f64
    │   ├── window_minutes: Option<i64>
    │   └── resets_at: Option<i64> (Unix timestamp)
    ├── secondary: Option<RateLimitWindow>
    ├── credits: Option<CreditsSnapshot>
    │   ├── has_credits: bool
    │   ├── unlimited: bool
    │   └── balance: Option<String>
    └── plan_type: Option<PlanType>
        ↓
RateLimitSnapshotDisplay (本地显示类型)
```

---

## 风险、边界与改进建议

### 已知风险

#### 1. 数据新鲜度阈值硬编码

```rust
pub(crate) const RATE_LIMIT_STALE_THRESHOLD_MINUTES: i64 = 15;
```

- **风险**：15 分钟阈值是硬编码的，无法根据用户场景调整
- **影响**：在快速变化的使用场景下可能产生误报或漏报

#### 2. 时间戳依赖本地时钟

```rust
stale |= now.signed_duration_since(snapshot.captured_at)
    > ChronoDuration::minutes(RATE_LIMIT_STALE_THRESHOLD_MINUTES);
```

- **风险**：用户设备时钟漂移可能导致错误的 stale 判定
- **缓解**：使用服务器时间戳与本地捕获时间戳结合

#### 3. Credits 余额解析容错

```rust
fn format_credit_balance(raw: &str) -> Option<String> {
    // 尝试解析为 i64，失败则尝试 f64
    // 零值或负值返回 None 隐藏显示
}
```

- **风险**：非标准格式的余额字符串可能导致显示异常
- **边界**：零积分账户完全不显示 Credits 行，用户可能误解为功能缺失

#### 4. 窄终端截断逻辑

```rust
let available_inner_width = usize::from(width.saturating_sub(4));
```

- **风险**：极端窄终端（< 4 列）返回空行，用户看不到任何状态
- **边界**：未定义最小可用宽度，可能导致完全空白输出

### 边界情况

| 场景 | 当前行为 | 潜在问题 |
|-----|---------|---------|
| 多限制桶（>1） | 显示分组标题和子项 | 标签可能过长导致换行混乱 |
| 非 codex 单限制桶 | 合并标签（如 "codex-other 5h limit"）| 逻辑复杂，容易出错 |
| 重置时间跨天 | 显示 "HH:MM on D Mmm" | 时区处理依赖系统本地时区 |
| ChatGPT 订阅用户 | 隐藏 Token usage 行 | 用户可能想查看实际使用量 |
| 路径截断 | 使用 center_truncate_path | 长路径中间截断可能丢失关键信息 |

### 改进建议

#### 1. 可配置的数据新鲜度阈值

```rust
// 建议：从 Config 读取而非硬编码
pub(crate) fn is_stale(captured_at: DateTime<Local>, now: DateTime<Local>, config: &Config) -> bool {
    let threshold = config.rate_limit_stale_threshold_minutes.unwrap_or(15);
    now.signed_duration_since(captured_at) > ChronoDuration::minutes(threshold)
}
```

#### 2. 增强的余额显示

```rust
// 建议：零积分显示 "0 credits" 而非隐藏
fn credit_status_row(credits: &CreditsSnapshotDisplay) -> Option<StatusRateLimitRow> {
    if !credits.has_credits {
        return None;
    }
    if credits.unlimited {
        return Some(...);
    }
    // 即使 balance 为 "0" 也显示，避免用户困惑
    let balance = credits.balance.as_ref()?;
    let display_balance = format_credit_balance(balance).unwrap_or_else(|| "0".to_string());
    Some(...)
}
```

#### 3. 最小宽度保护

```rust
// 建议：添加最小宽度检查
fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
    const MIN_USABLE_WIDTH: u16 = 40;
    if width < MIN_USABLE_WIDTH {
        return vec![Line::from("Terminal too narrow to display status")];
    }
    // ...
}
```

#### 4. 统一的时间格式化

```rust
// 建议：将时间格式化逻辑集中到 helpers.rs
// 目前 format_reset_timestamp 在 helpers.rs
// 但 get_limits_duration 在 chatwidget.rs
// 存在逻辑分散问题
```

#### 5. 测试覆盖率增强

当前测试主要覆盖：
- ✅ 正常数据渲染
- ✅ 各种限制窗口组合
- ✅ Credits 各种状态
- ✅ 窄终端截断
- ✅ 过期数据警告

建议补充：
- ⬜ 极端窗口时长（如 1 分钟、1 年）
- ⬜ 多字节 Unicode 路径显示
- ⬜ 时区跨越测试
- ⬜ 并发更新场景

### 性能考虑

| 操作 | 复杂度 | 说明 |
|-----|-------|------|
| 标签宽度计算 | O(n) | n = 标签数量，通常 < 20 |
| 进度条渲染 | O(1) | 固定 20 段 |
| 路径格式化 | O(m) | m = 路径长度 |
| 快照数据转换 | O(1) | 固定结构转换 |

总体性能开销较低，主要瓶颈在终端渲染而非数据处理。

---

## 总结

`codex-rs/tui/src/status/` 模块是一个设计良好的状态展示层，通过清晰的分层将协议数据转换为用户友好的终端界面。核心设计亮点包括：

1. **分离关注点**：`rate_limits.rs` 处理数据转换，`card.rs` 处理渲染布局，`format.rs` 处理格式化细节
2. **类型安全**：使用强类型区分 Available/Stale/Missing 三种数据状态
3. **测试完善**：9 个快照测试覆盖主要场景，确保 UI 变更可追踪
4. **国际化友好**：时间格式化使用本地化，Unicode 宽度计算支持多语言

主要改进空间在于配置灵活性（硬编码阈值）和边界情况处理（极端窄终端、零值显示）。
