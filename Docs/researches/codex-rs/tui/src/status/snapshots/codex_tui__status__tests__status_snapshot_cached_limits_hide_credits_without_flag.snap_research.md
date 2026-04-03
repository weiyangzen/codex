# 研究文档：status_snapshot_cached_limits_hide_credits_without_flag.snap

## 场景与职责

此快照文件是 Codex TUI（Terminal User Interface）状态显示模块的测试快照，用于验证当速率限制数据变为"陈旧"（stale）且用户没有 `has_credits` 标志时，积分（credits）信息是否正确被隐藏。这是 TUI 状态卡片（Status Card）渲染系统的回归测试的一部分。

该测试属于 `codex-rs/tui/src/status/tests.rs` 中的 `status_snapshot_cached_limits_hide_credits_without_flag` 测试函数，使用 `insta` 快照测试框架捕获 `/status` 命令的输出渲染结果。

## 功能点目的

### 核心功能
1. **陈旧数据检测**：验证当速率限制快照的捕获时间超过 15 分钟阈值时，系统能正确识别并标记数据为陈旧
2. **积分显示控制**：验证当 `has_credits: false` 时，即使存在余额数据，也不显示积分信息
3. **警告信息展示**：验证陈旧数据情况下，系统显示适当的警告提示用户刷新

### 业务逻辑
- 速率限制数据通过 `RateLimitSnapshot` 结构传递，包含主窗口（5小时）和次窗口（周限制）的使用百分比
- 陈旧检测逻辑位于 `rate_limits.rs` 中的 `compose_rate_limit_data_many` 函数
- 积分显示由 `credit_status_row` 函数控制，仅在 `has_credits: true` 时返回行数据

## 具体技术实现

### 关键数据结构

```rust
// 协议层数据结构 (codex-rs/protocol/src/protocol.rs)
pub struct RateLimitSnapshot {
    pub limit_id: Option<String>,
    pub limit_name: Option<String>,
    pub primary: Option<RateLimitWindow>,    // 5小时窗口
    pub secondary: Option<RateLimitWindow>,  // 周窗口
    pub credits: Option<CreditsSnapshot>,
    pub plan_type: Option<PlanType>,
}

pub struct RateLimitWindow {
    pub used_percent: f64,           // 已使用百分比
    pub window_minutes: Option<i64>, // 窗口时长（分钟）
    pub resets_at: Option<i64>,      // 重置时间戳
}

pub struct CreditsSnapshot {
    pub has_credits: bool,   // 是否启用积分追踪
    pub unlimited: bool,     // 是否无限积分
    pub balance: Option<String>, // 余额字符串
}
```

### 显示层数据结构 (rate_limits.rs)

```rust
pub(crate) enum StatusRateLimitData {
    Available(Vec<StatusRateLimitRow>),  // 数据可用
    Stale(Vec<StatusRateLimitRow>),      // 数据陈旧
    Missing,                              // 数据缺失
}

pub(crate) struct StatusRateLimitRow {
    pub label: String,           // 如 "5h limit", "Credits"
    pub value: StatusRateLimitValue,
}

pub(crate) enum StatusRateLimitValue {
    Window { percent_used: f64, resets_at: Option<String> },
    Text(String),
}
```

### 陈旧检测算法

```rust
// rate_limits.rs: compose_rate_limit_data_many
const RATE_LIMIT_STALE_THRESHOLD_MINUTES: i64 = 15;

for snapshot in snapshots {
    stale |= now.signed_duration_since(snapshot.captured_at)
        > ChronoDuration::minutes(RATE_LIMIT_STALE_THRESHOLD_MINUTES);
    // ...
}
```

### 积分行生成逻辑

```rust
// rate_limits.rs: credit_status_row
fn credit_status_row(credits: &CreditsSnapshotDisplay) -> Option<StatusRateLimitRow> {
    if !credits.has_credits {
        return None;  // 关键：has_credits 为 false 时直接返回 None
    }
    if credits.unlimited {
        return Some(StatusRateLimitRow {
            label: "Credits".to_string(),
            value: StatusRateLimitValue::Text("Unlimited".to_string()),
        });
    }
    // ... 处理有余额的情况
}
```

### 测试用例构造

```rust
// tests.rs: status_snapshot_cached_limits_hide_credits_without_flag
let snapshot = RateLimitSnapshot {
    limit_id: None,
    limit_name: None,
    primary: Some(RateLimitWindow {
        used_percent: 60.0,
        window_minutes: Some(300),  // 5小时
        resets_at: Some(reset_at_from(&captured_at, 1_200)),
    }),
    secondary: Some(RateLimitWindow {
        used_percent: 35.0,
        window_minutes: Some(10_080),  // 1周
        resets_at: Some(reset_at_from(&captured_at, 2_400)),
    }),
    credits: Some(CreditsSnapshot {
        has_credits: false,  // 关键：设置为 false
        unlimited: false,
        balance: Some("80".to_string()), // 有余额但不显示
    }),
    plan_type: None,
};

// 模拟 20 分钟后，超过 15 分钟陈旧阈值
let now = captured_at + ChronoDuration::minutes(20);
```

### 渲染输出分析

快照显示的内容：
```
╭─────────────────────────────────────────────────────────────────────╮
│  >_ OpenAI Codex (v0.0.0)                                           │
│                                                                     │
│ Visit https://chatgpt.com/codex/settings/usage for up-to-date       │
│ information on rate limits and credits                              │
│                                                                     │
│  Model:            gpt-5.1-codex (reasoning none, summaries auto)   │
│  Directory: [[workspace]]                                           │
│  Permissions:      Custom (read-only, on-request)                   │
│  Agents.md:        <none>                                           │
│                                                                     │
│  Token usage:      1.05K total  (700 input + 350 output)            │
│  Context window:   100% left (1.45K used / 272K)                    │
│  5h limit:         [████████░░░░░░░░░░░░] 40% left (resets 11:32)   │
│  Weekly limit:     [█████████████░░░░░░░] 65% left (resets 11:52)   │
│  Warning:          limits may be stale - start new turn to refresh. │
╰─────────────────────────────────────────────────────────────────────╯
```

关键验证点：
1. **无 Credits 行**：尽管测试数据设置了 `balance: Some("80")`，但由于 `has_credits: false`，积分行未显示
2. **陈旧警告**：显示 "limits may be stale" 警告
3. **进度条渲染**：5小时限制显示 40% 剩余（60% 已使用），周限制显示 65% 剩余（35% 已使用）

## 关键代码路径与文件引用

### 核心实现文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/status/tests.rs` | 测试用例定义，第 898-966 行 |
| `codex-rs/tui/src/status/card.rs` | 状态卡片渲染，第 307-335 行的 `rate_limit_lines` 方法 |
| `codex-rs/tui/src/status/rate_limits.rs` | 速率限制显示逻辑，第 158-278 行的 `compose_rate_limit_data` 和 `compose_rate_limit_data_many` |
| `codex-rs/protocol/src/protocol.rs` | 协议数据结构，第 1868-1894 行 |

### 关键函数调用链

```
new_status_output (card.rs:81)
  └── StatusHistoryCell::new (card.rs:152)
      └── compose_rate_limit_data_many (rate_limits.rs:168)
          ├── 陈旧检测: now.signed_duration_since(snapshot.captured_at) > 15分钟
          └── credit_status_row (rate_limits.rs:305)
              └── 返回 None (因为 has_credits: false)
  └── StatusHistoryCell::rate_limit_lines (card.rs:307)
      └── 处理 StatusRateLimitData::Stale，添加警告行
```

### 进度条渲染

```rust
// rate_limits.rs:284-294
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

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `chrono` | 时间戳处理和时区转换 |
| `ratatui` | 终端 UI 渲染框架 |
| `insta` | 快照测试框架 |
| `codex_protocol` | 协议数据结构定义 |
| `codex_core` | 配置和认证管理 |

### 配置交互

测试使用 `ConfigBuilder` 构建测试配置：
```rust
let mut config = test_config(&temp_home).await;
config.model = Some("gpt-5.1-codex".to_string());
config.cwd = PathBuf::from("/workspace/tests");
```

### 认证交互

通过 `AuthManager` 获取账户信息：
```rust
let auth_manager = test_auth_manager(&config);
let account = compose_account_display(auth_manager, plan_type);
```

## 风险、边界与改进建议

### 当前风险

1. **硬编码阈值**：15 分钟的陈旧阈值是硬编码的（`RATE_LIMIT_STALE_THRESHOLD_MINUTES`），无法通过配置调整
2. **时区依赖**：测试使用 `chrono::Local`，在不同时区运行可能产生不同的重置时间显示
3. **Windows 路径处理**：测试包含 Windows 路径分隔符替换逻辑，增加复杂性

### 边界情况

1. **刚好在阈值边界**：如果数据年龄正好是 15 分钟，行为取决于 `>` 比较，这是一个开区间
2. **负数余额**：`format_credit_balance` 函数会过滤掉非正数余额，但 `has_credits: true` 且 `balance: Some("0")` 的情况需要验证
3. **空快照数组**：`compose_rate_limit_data_many` 对空数组返回 `Missing`，但测试通常提供至少一个快照

### 改进建议

1. **配置化阈值**：将陈旧阈值提取到配置中，允许用户自定义
2. **更细粒度的陈旧检测**：可以分别检测每个限制窗口的陈旧程度，而不是整体判断
3. **积分显示优化**：当前 `has_credits: false` 时完全隐藏积分行，可以考虑显示 "Credits: N/A" 以明确状态
4. **测试覆盖**：建议添加以下边界测试：
   - 正好 15 分钟的数据年龄
   - `has_credits: true` 但 `balance: None` 的情况
   - 多个限制快照混合（部分陈旧，部分新鲜）

### 代码质量

1. **函数参数过多**：`new_status_output` 有 13 个参数，考虑使用 builder 模式重构
2. **测试辅助函数**：`sanitize_directory` 和 `render_lines` 是测试专用，应放在测试模块中
3. **魔法字符串**：如 "data not available yet" 等字符串应提取为常量
