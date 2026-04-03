# Research: codex-rs/tui_app_server/src/status/snapshots

## 1. 场景与职责

### 1.1 目录定位

`snapshots/` 目录位于 `codex-rs/tui_app_server/src/status/` 下，是 Rust TUI 应用服务器中负责 **状态展示（Status Display）** 的测试快照存储目录。该目录包含 18 个 `.snap` 文件，用于存储 `insta` 快照测试的预期输出。

### 1.2 核心职责

该目录服务于 `status` 模块，主要职责包括：

1. **UI 快照测试**：验证 `/status` 命令输出的视觉呈现是否符合预期
2. **速率限制展示**：测试不同速率限制场景下的进度条、百分比、重置时间显示
3. **积分/额度展示**：验证 Credits 余额、无限额度等状态的渲染
4. **边界条件处理**：测试空数据、过期数据、窄终端等边界场景的 UI 表现
5. **跨 crate 兼容性**：同时支持 `codex-tui` 和 `codex-tui-app-server` 两个 crate 的测试

### 1.3 业务场景

当用户在 Codex TUI 中执行 `/status` 斜杠命令时，系统会展示当前会话的完整状态信息，包括：
- 模型配置（Model、Provider、Reasoning Effort 等）
- 工作目录（Directory）
- 权限配置（Permissions）
- Agents.md 文件状态
- 账户信息（Account）
- 会话标识（Session ID、Forked from）
- Token 使用情况（Token usage）
- 上下文窗口使用率（Context window）
- 速率限制（Rate Limits）：5h limit、Weekly limit、Monthly limit 等
- 积分余额（Credits）

---

## 2. 功能点目的

### 2.1 快照测试覆盖的功能点

| 快照文件 | 测试目的 |
|---------|---------|
| `status_snapshot_includes_reasoning_details.snap` | 验证 reasoning effort 和 reasoning summaries 的显示 |
| `status_snapshot_includes_credits_and_limits.snap` | 验证积分余额和速率限制同时显示的场景 |
| `status_snapshot_includes_forked_from.snap` | 验证 fork 会话的父会话 ID 显示 |
| `status_snapshot_includes_monthly_limit.snap` | 验证月度限制（30天窗口）的显示 |
| `status_snapshot_shows_empty_limits_message.snap` | 验证空限制数据的友好提示 |
| `status_snapshot_shows_missing_limits_message.snap` | 验证缺失限制数据的处理 |
| `status_snapshot_shows_stale_limits_message.snap` | 验证过期限制数据的警告提示 |
| `status_snapshot_truncates_in_narrow_terminal.snap` | 验证窄终端下的内容截断处理 |
| `status_snapshot_cached_limits_hide_credits_without_flag.snap` | 验证 has_credits=false 时隐藏积分显示 |

### 2.2 双 crate 支持

快照文件分为两组前缀：
- `codex_tui__status__tests__*`：为 `codex-tui` crate 生成的快照
- `codex_tui_app_server__status__tests__*`：为 `codex-tui-app-server` crate 生成的快照

这表明 `status` 模块的代码被两个 crate 共享，测试用例相同但生成的快照分别存储。

---

## 3. 具体技术实现

### 3.1 核心数据结构

#### 3.1.1 协议层数据结构（codex-protocol）

```rust
// codex-rs/protocol/src/protocol.rs
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize, JsonSchema, TS)]
pub struct RateLimitSnapshot {
    pub limit_id: Option<String>,
    pub limit_name: Option<String>,
    pub primary: Option<RateLimitWindow>,      // 主窗口（如 5h）
    pub secondary: Option<RateLimitWindow>,    // 次窗口（如 weekly）
    pub credits: Option<CreditsSnapshot>,
    pub plan_type: Option<crate::account::PlanType>,
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize, JsonSchema, TS)]
pub struct RateLimitWindow {
    pub used_percent: f64,           // 已使用百分比 (0-100)
    pub window_minutes: Option<i64>, // 窗口时长（分钟）
    pub resets_at: Option<i64>,      // 重置时间（Unix 时间戳）
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize, JsonSchema, TS)]
pub struct CreditsSnapshot {
    pub has_credits: bool,   // 是否启用积分追踪
    pub unlimited: bool,     // 是否无限额度
    pub balance: Option<String>, // 余额字符串
}
```

#### 3.1.2 展示层数据结构（status 模块）

```rust
// codex-rs/tui_app_server/src/status/rate_limits.rs
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
    pub resets_at: Option<String>,   // 本地时间格式化字符串
    pub window_minutes: Option<i64>,
}

#[derive(Debug, Clone)]
pub(crate) enum StatusRateLimitData {
    Available(Vec<StatusRateLimitRow>),  // 数据可用
    Stale(Vec<StatusRateLimitRow>),      // 数据过期（>15分钟）
    Missing,                              // 数据缺失
}
```

### 3.2 关键流程

#### 3.2.1 状态展示生成流程

```
用户执行 /status 命令
    ↓
ChatWidget::add_status_output()
    ↓
收集数据：
  - token_info (TokenUsageInfo)
  - total_usage (TokenUsage)
  - rate_limit_snapshots (Vec<RateLimitSnapshotDisplay>)
  - config (Config)
  - thread_id, thread_name, forked_from
    ↓
status::new_status_output_with_rate_limits()
    ↓
StatusHistoryCell::new()  // 构建状态卡片
    ↓
compose_rate_limit_data_many()  // 处理速率限制数据
    ↓
HistoryCell::display_lines()  // 渲染为 UI 行
    ↓
输出到聊天记录
```

#### 3.2.2 速率限制数据处理流程

```rust
// rate_limits.rs: compose_rate_limit_data_many
pub(crate) fn compose_rate_limit_data_many(
    snapshots: &[RateLimitSnapshotDisplay],
    now: DateTime<Local>,
) -> StatusRateLimitData {
    // 1. 检查数据新鲜度（15分钟阈值）
    let stale = now.signed_duration_since(snapshot.captured_at) 
                > ChronoDuration::minutes(15);
    
    // 2. 构建展示行
    for snapshot in snapshots {
        // 处理主窗口（5h limit）
        if let Some(primary) = snapshot.primary {
            rows.push(StatusRateLimitRow {
                label: "5h limit".to_string(),
                value: StatusRateLimitValue::Window {
                    percent_used: primary.used_percent,
                    resets_at: primary.resets_at.clone(),
                },
            });
        }
        
        // 处理次窗口（Weekly limit）
        if let Some(secondary) = snapshot.secondary {
            rows.push(StatusRateLimitRow {
                label: "Weekly limit".to_string(),
                value: StatusRateLimitValue::Window {
                    percent_used: secondary.used_percent,
                    resets_at: secondary.resets_at.clone(),
                },
            });
        }
        
        // 处理积分显示
        if let Some(credits) = snapshot.credits {
            if let Some(row) = credit_status_row(credits) {
                rows.push(row);
            }
        }
    }
    
    // 3. 返回带状态的数据
    if stale { StatusRateLimitData::Stale(rows) } 
    else { StatusRateLimitData::Available(rows) }
}
```

#### 3.2.3 进度条渲染

```rust
// rate_limits.rs
const STATUS_LIMIT_BAR_SEGMENTS: usize = 20;
const STATUS_LIMIT_BAR_FILLED: &str = "█";
const STATUS_LIMIT_BAR_EMPTY: &str = "░";

pub(crate) fn render_status_limit_progress_bar(percent_remaining: f64) -> String {
    let ratio = (percent_remaining / 100.0).clamp(0.0, 1.0);
    let filled = (ratio * STATUS_LIMIT_BAR_SEGMENTS as f64).round() as usize;
    let empty = STATUS_LIMIT_BAR_SEGMENTS.saturating_sub(filled);
    format!("[{}{}]", 
        STATUS_LIMIT_BAR_FILLED.repeat(filled),
        STATUS_LIMIT_BAR_EMPTY.repeat(empty)
    )
}
```

### 3.3 时间窗口分类逻辑

```rust
// chatwidget.rs: get_limits_duration
pub(crate) fn get_limits_duration(windows_minutes: i64) -> String {
    const MINUTES_PER_HOUR: i64 = 60;
    const MINUTES_PER_DAY: i64 = 24 * MINUTES_PER_HOUR;
    const MINUTES_PER_WEEK: i64 = 7 * MINUTES_PER_DAY;
    const MINUTES_PER_MONTH: i64 = 30 * MINUTES_PER_DAY;
    const ROUNDING_BIAS_MINUTES: i64 = 3;

    if windows_minutes <= MINUTES_PER_DAY.saturating_add(ROUNDING_BIAS_MINUTES) {
        // ≤ 1天：显示为 "Xh"
        let hours = std::cmp::max(1, adjusted / MINUTES_PER_HOUR);
        format!("{hours}h")
    } else if windows_minutes <= MINUTES_PER_WEEK.saturating_add(ROUNDING_BIAS_MINUTES) {
        // ≤ 1周：显示为 "weekly"
        "weekly".to_string()
    } else if windows_minutes <= MINUTES_PER_MONTH.saturating_add(ROUNDING_BIAS_MINUTES) {
        // ≤ 30天：显示为 "monthly"
        "monthly".to_string()
    } else {
        // > 30天：显示为 "annual"
        "annual".to_string()
    }
}
```

### 3.4 快照测试实现

```rust
// status/tests.rs
#[tokio::test]
async fn status_snapshot_includes_credits_and_limits() {
    // 1. 准备测试配置
    let temp_home = TempDir::new().expect("temp home");
    let mut config = test_config(&temp_home).await;
    config.model = Some("gpt-5.1-codex".to_string());
    
    // 2. 构建速率限制快照
    let snapshot = RateLimitSnapshot {
        limit_id: None,
        limit_name: None,
        primary: Some(RateLimitWindow {
            used_percent: 45.0,
            window_minutes: Some(300),  // 5h
            resets_at: Some(reset_at_from(&captured_at, 900)),
        }),
        secondary: Some(RateLimitWindow {
            used_percent: 30.0,
            window_minutes: Some(10_080),  // weekly
            resets_at: Some(reset_at_from(&captured_at, 2_700)),
        }),
        credits: Some(CreditsSnapshot {
            has_credits: true,
            unlimited: false,
            balance: Some("37.5".to_string()),
        }),
        plan_type: None,
    };
    let rate_display = rate_limit_snapshot_display(&snapshot, captured_at);
    
    // 3. 生成状态输出
    let composite = new_status_output(
        &config,
        account_display.as_ref(),
        Some(&token_info),
        &usage,
        &None,  // session_id
        None,   // thread_name
        None,   // forked_from
        Some(&rate_display),
        None,   // plan_type
        captured_at,
        &model_slug,
        None,   // collaboration_mode
        None,   // reasoning_effort_override
    );
    
    // 4. 渲染并断言快照
    let mut rendered_lines = render_lines(&composite.display_lines(80));
    let sanitized = sanitize_directory(rendered_lines).join("\n");
    assert_snapshot!(sanitized);  // 与 .snap 文件比对
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件结构

```
codex-rs/tui_app_server/src/status/
├── mod.rs              # 模块入口，导出公共接口
├── account.rs          # 账户信息展示结构
├── card.rs             # StatusHistoryCell 实现，主渲染逻辑
├── format.rs           # 字段格式化工具（FieldFormatter）
├── helpers.rs          # 辅助函数（token 格式化、路径显示等）
├── rate_limits.rs      # 速率限制数据处理与展示
├── tests.rs            # 测试用例
└── snapshots/          # 测试快照文件
    ├── codex_tui__status__tests__*.snap
    └── codex_tui_app_server__status__tests__*.snap
```

### 4.2 关键代码路径

#### 4.2.1 状态展示入口

- **文件**: `codex-rs/tui_app_server/src/chatwidget.rs:6791`
- **函数**: `ChatWidget::add_status_output()`
- **职责**: 收集当前会话状态数据，调用 status 模块生成展示卡片

#### 4.2.2 速率限制数据处理

- **文件**: `codex-rs/tui_app_server/src/status/rate_limits.rs:168`
- **函数**: `compose_rate_limit_data_many()`
- **职责**: 将协议层的 `RateLimitSnapshot` 转换为展示层的 `StatusRateLimitData`

#### 4.2.3 状态卡片渲染

- **文件**: `codex-rs/tui_app_server/src/status/card.rs:411`
- **实现**: `impl HistoryCell for StatusHistoryCell`
- **职责**: 实现 `display_lines()` 方法，将状态数据渲染为 ratatui 的 `Line` 列表

#### 4.2.4 进度条渲染

- **文件**: `codex-rs/tui_app_server/src/status/rate_limits.rs:284`
- **函数**: `render_status_limit_progress_bar()`
- **职责**: 将剩余百分比转换为可视化进度条（█/░）

#### 4.2.5 时间窗口标签生成

- **文件**: `codex-rs/tui_app_server/src/chatwidget.rs:490`
- **函数**: `get_limits_duration()`
- **职责**: 将分钟数转换为人类可读的标签（5h/weekly/monthly/annual）

### 4.3 协议层定义

- **文件**: `codex-rs/protocol/src/protocol.rs:1868`
- **结构**: `RateLimitSnapshot`, `RateLimitWindow`, `CreditsSnapshot`
- **职责**: 定义客户端与服务器间速率限制数据的序列化格式

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `chatwidget` | 提供 `get_limits_duration` 函数，管理速率限制快照状态 |
| `history_cell` | 提供 `HistoryCell` trait 和 `CompositeHistoryCell` 结构 |
| `text_formatting` | 提供 `capitalize_first` 等文本处理函数 |
| `wrapping` | 提供文本换行处理（`adaptive_wrap_lines`） |
| `version` | 提供版本号常量 `CODEX_CLI_VERSION` |

### 5.2 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_protocol` | 协议数据结构（`RateLimitSnapshot`, `TokenUsage` 等） |
| `codex_core` | 配置管理（`Config`）和测试支持 |
| `chrono` | 时间处理（`DateTime`, `Local`, `Utc`） |
| `ratatui` | TUI 渲染（`Line`, `Span`, `Stylize` 等） |
| `unicode_width` | Unicode 字符宽度计算 |
| `insta` | 快照测试框架 |
| `pretty_assertions` | 测试断言美化 |

### 5.3 数据流

```
┌─────────────────────────────────────────────────────────────────┐
│                        Backend (OpenAI API)                      │
│  - Rate limit headers (x-ratelimit-*）                           │
│  - Credits information                                           │
└──────────────────────┬──────────────────────────────────────────┘
                       │ HTTP Response
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                    backend-client crate                          │
│  - Parse rate limit headers                                      │
│  - Build RateLimitSnapshot                                       │
└──────────────────────┬──────────────────────────────────────────┘
                       │ RateLimitSnapshot
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                    app-server crate                              │
│  - Handle TokenCountEvent                                        │
│  - Forward to clients                                            │
└──────────────────────┬──────────────────────────────────────────┘
                       │ TokenCountEvent (WebSocket/SSE)
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                 tui_app_server crate                             │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  ChatWidget::on_rate_limit_snapshot()                   │    │
│  │  - Store in rate_limit_snapshots_by_limit_id            │    │
│  └─────────────────────────────────────────────────────────┘    │
│                              │                                   │
│                              ▼ /status command                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  status module                                          │    │
│  │  - rate_limits.rs: compose_rate_limit_data_many()       │    │
│  │  - card.rs: StatusHistoryCell::display_lines()          │    │
│  └─────────────────────────────────────────────────────────┘    │
└──────────────────────┬──────────────────────────────────────────┘
                       │ Vec<Line<'static>>
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                      ratatui                                     │
│  - Render to terminal                                            │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 数据新鲜度风险

- **问题**: 速率限制数据通过 `TokenCountEvent` 事件异步更新，如果用户长时间不发送新消息，数据可能过期（>15分钟）
- **缓解**: 系统会显示 "limits may be stale - start new turn to refresh" 警告
- **代码**: `rate_limits.rs:58` 定义了 `RATE_LIMIT_STALE_THRESHOLD_MINUTES = 15`

#### 6.1.2 时区处理风险

- **问题**: `resets_at` 时间戳从 UTC 转换为本地时间显示，依赖系统时区设置
- **代码**: `rate_limits.rs:73-76` 使用 `with_timezone(&Local)` 转换

#### 6.1.3 积分精度丢失

- **问题**: 积分余额从字符串解析为浮点数后四舍五入，可能丢失小数精度
- **代码**: `rate_limits.rs:335-339` 将 `"12.5"` 显示为 `"13 credits"`

#### 6.1.4 窄终端截断

- **问题**: 终端宽度小于内容宽度时，长行会被截断，可能影响可读性
- **缓解**: `format.rs:101-147` 实现了 `truncate_line_to_width` 函数进行智能截断

### 6.2 边界条件

| 边界条件 | 处理方式 |
|---------|---------|
| 空速率限制数据 | 显示 "data not available yet" |
| 零积分余额 | 完全隐藏 Credits 行 |
| has_credits=false | 隐藏 Credits 显示，即使有余额数据 |
| unlimited=true | 显示 "Credits: Unlimited" |
| 过期数据（>15min） | 显示数据 + "Warning: limits may be stale" |
| 非 codex 限制桶 | 显示前缀如 "codex-other 5h limit" |
| 单窗口非 codex 桶 | 合并显示为 "codex-other 5h limit" |
| 多窗口非 codex 桶 | 分组显示 "codex-other limit" + "1h limit" + "Weekly limit" |

### 6.3 改进建议

#### 6.3.1 数据刷新机制

- **建议**: 添加手动刷新速率限制数据的机制（如 `/status --refresh`）
- **理由**: 用户可能希望在不下发新指令的情况下获取最新限制状态

#### 6.3.2 积分精度显示

- **建议**: 根据余额大小动态决定小数位数，小额保留 1-2 位小数
- **当前**: `"12.5"` → `"13 credits"`
- **建议**: `"12.5"` → `"12.5 credits"`（当余额 < 100 时）

#### 6.3.3 多语言支持

- **建议**: 将硬编码的英文文本提取到本地化资源文件
- **当前硬编码文本**: "data not available yet", "limits may be stale", "Unlimited" 等

#### 6.3.4 快照测试优化

- **建议**: 合并 `codex_tui` 和 `codex_tui_app_server` 的重复快照
- **现状**: 18 个快照文件中，有 9 对内容几乎相同，仅前缀不同
- **方案**: 使用符号链接或共享测试数据目录

#### 6.3.5 速率限制可视化增强

- **建议**: 添加颜色编码（绿色/黄色/红色）表示使用率严重程度
- **当前**: 仅使用黑白进度条
- **实现位置**: `card.rs:351` 的 `rate_limit_row_lines` 方法

#### 6.3.6 测试覆盖扩展

- **建议**: 添加以下边界条件的快照测试：
  - 多限制桶同时显示（codex + codex-other）
  - 年度限制（>30天窗口）
  - 跨日期重置时间显示（resets_at 在次日）
  - 零窗口使用率（0% used）
  - 满窗口使用率（100% used）

#### 6.3.7 代码结构优化

- **建议**: 将 `get_limits_duration` 函数从 `chatwidget.rs` 移至 `status` 模块
- **理由**: 该函数仅用于状态展示，放在 status 模块更符合内聚性原则

---

## 7. 附录

### 7.1 快照文件完整列表

```
codex-rs/tui_app_server/src/status/snapshots/
├── codex_tui__status__tests__status_snapshot_cached_limits_hide_credits_without_flag.snap
├── codex_tui__status__tests__status_snapshot_includes_credits_and_limits.snap
├── codex_tui__status__tests__status_snapshot_includes_forked_from.snap
├── codex_tui__status__tests__status_snapshot_includes_monthly_limit.snap
├── codex_tui__status__tests__status_snapshot_includes_reasoning_details.snap
├── codex_tui__status__tests__status_snapshot_shows_empty_limits_message.snap
├── codex_tui__status__tests__status_snapshot_shows_missing_limits_message.snap
├── codex_tui__status__tests__status_snapshot_shows_stale_limits_message.snap
├── codex_tui__status__tests__status_snapshot_truncates_in_narrow_terminal.snap
├── codex_tui_app_server__status__tests__status_snapshot_cached_limits_hide_credits_without_flag.snap
├── codex_tui_app_server__status__tests__status_snapshot_includes_credits_and_limits.snap
├── codex_tui_app_server__status__tests__status_snapshot_includes_forked_from.snap
├── codex_tui_app_server__status__tests__status_snapshot_includes_monthly_limit.snap
├── codex_tui_app_server__status__tests__status_snapshot_includes_reasoning_details.snap
├── codex_tui_app_server__status__tests__status_snapshot_shows_empty_limits_message.snap
├── codex_tui_app_server__status__tests__status_snapshot_shows_missing_limits_message.snap
├── codex_tui_app_server__status__tests__status_snapshot_shows_stale_limits_message.snap
└── codex_tui_app_server__status__tests__status_snapshot_truncates_in_narrow_terminal.snap
```

### 7.2 相关文档

- `AGENTS.md`: 项目级编码规范
- `codex-rs/tui/styles.md`: TUI 样式规范
- `codex-rs/tui_app_server/src/status/mod.rs`: 模块文档注释
- `codex-rs/protocol/src/protocol.rs`: 协议数据结构定义
