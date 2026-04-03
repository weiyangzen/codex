# rate_limits.rs 研究文档

## 场景与职责

`rate_limits.rs` 是状态显示模块中处理速率限制和额度显示的核心文件。它将协议层的 `RateLimitSnapshot` 转换为 TUI 友好的显示结构，支持多种速率限制窗口、额度信息和数据新鲜度检测。

### 核心职责
1. **快照转换**: 将 `RateLimitSnapshot` 转换为 `RateLimitSnapshotDisplay`
2. **数据分类**: 将速率限制数据标记为 Available/Stale/Missing
3. **窗口渲染**: 生成进度条和百分比显示
4. **额度处理**: 处理 credits 余额的格式化和显示
5. **多限制支持**: 支持 codex 和 codex-other 等多种限制类型

## 功能点目的

### 1. StatusRateLimitRow - 速率限制行

```rust
#[derive(Debug, Clone)]
pub(crate) struct StatusRateLimitRow {
    pub label: String,           // 标签，如 "5h limit" 或 "Credits"
    pub value: StatusRateLimitValue,
}
```

### 2. StatusRateLimitValue - 行值类型

```rust
#[derive(Debug, Clone)]
pub(crate) enum StatusRateLimitValue {
    Window {
        percent_used: f64,       // 已使用百分比
        resets_at: Option<String>, // 重置时间文本
    },
    Text(String),               // 纯文本值
}
```

### 3. StatusRateLimitData - 数据可用性状态

```rust
#[derive(Debug, Clone)]
pub(crate) enum StatusRateLimitData {
    Available(Vec<StatusRateLimitRow>),  // 数据新鲜
    Stale(Vec<StatusRateLimitRow>),      // 数据过期（>15分钟）
    Missing,                             // 无数据
}
```

### 4. RateLimitWindowDisplay - 窗口显示

```rust
#[derive(Debug, Clone)]
pub(crate) struct RateLimitWindowDisplay {
    pub used_percent: f64,       // 已使用百分比
    pub resets_at: Option<String>, // 本地时间重置文本
    pub window_minutes: Option<i64>, // 窗口时长（分钟）
}
```

### 5. RateLimitSnapshotDisplay - 快照显示

```rust
#[derive(Debug, Clone)]
pub(crate) struct RateLimitSnapshotDisplay {
    pub limit_name: String,      // 限制标识（codex/codex_other）
    pub captured_at: DateTime<Local>, // 本地捕获时间
    pub primary: Option<RateLimitWindowDisplay>,   // 主窗口（通常5小时）
    pub secondary: Option<RateLimitWindowDisplay>, // 次窗口（通常每周）
    pub credits: Option<CreditsSnapshotDisplay>,   // 额度信息
}
```

### 6. CreditsSnapshotDisplay - 额度显示

```rust
#[derive(Debug, Clone)]
pub(crate) struct CreditsSnapshotDisplay {
    pub has_credits: bool,       // 是否启用额度追踪
    pub unlimited: bool,         // 是否无限额度
    pub balance: Option<String>, // 余额文本
}
```

## 具体技术实现

### 关键常量

```rust
const STATUS_LIMIT_BAR_SEGMENTS: usize = 20;     // 进度条段数
const STATUS_LIMIT_BAR_FILLED: &str = "█";       // 已使用字符
const STATUS_LIMIT_BAR_EMPTY: &str = "░";        // 未使用字符
pub(crate) const RATE_LIMIT_STALE_THRESHOLD_MINUTES: i64 = 15; // 过期阈值
```

### 快照转换流程

#### rate_limit_snapshot_display_for_limit

```rust
pub(crate) fn rate_limit_snapshot_display_for_limit(
    snapshot: &RateLimitSnapshot,
    limit_name: String,
    captured_at: DateTime<Local>,
) -> RateLimitSnapshotDisplay {
    RateLimitSnapshotDisplay {
        limit_name,
        captured_at,
        primary: snapshot.primary.as_ref()
            .map(|window| RateLimitWindowDisplay::from_window(window, captured_at)),
        secondary: snapshot.secondary.as_ref()
            .map(|window| RateLimitWindowDisplay::from_window(window, captured_at)),
        credits: snapshot.credits.as_ref().map(CreditsSnapshotDisplay::from),
    }
}
```

#### RateLimitWindowDisplay::from_window

```rust
fn from_window(window: &RateLimitWindow, captured_at: DateTime<Local>) -> Self {
    let resets_at_utc = window.resets_at
        .and_then(|seconds| DateTime::<Utc>::from_timestamp(seconds, 0))
        .map(|dt| dt.with_timezone(&Local));
    let resets_at = resets_at_utc.map(|dt| format_reset_timestamp(dt, captured_at));

    Self {
        used_percent: window.used_percent,
        resets_at,
        window_minutes: window.window_minutes,
    }
}
```

### 数据组合流程

#### compose_rate_limit_data_many

```rust
pub(crate) fn compose_rate_limit_data_many(
    snapshots: &[RateLimitSnapshotDisplay],
    now: DateTime<Local>,
) -> StatusRateLimitData {
    if snapshots.is_empty() {
        return StatusRateLimitData::Missing;
    }

    let mut rows = Vec::with_capacity(snapshots.len().saturating_mul(3));
    let mut stale = false;

    for snapshot in snapshots {
        // 检查数据新鲜度
        stale |= now.signed_duration_since(snapshot.captured_at)
            > ChronoDuration::minutes(RATE_LIMIT_STALE_THRESHOLD_MINUTES);

        let limit_bucket_label = snapshot.limit_name.clone();
        let show_limit_prefix = !limit_bucket_label.eq_ignore_ascii_case("codex");
        
        // 确定标签
        let primary_label = snapshot.primary.as_ref()
            .map(|window| window.window_minutes.map(get_limits_duration)
                .unwrap_or_else(|| "5h".to_string()))
            .map(|label| capitalize_first(&label));
        let secondary_label = snapshot.secondary.as_ref()
            .map(|window| window.window_minutes.map(get_limits_duration)
                .unwrap_or_else(|| "weekly".to_string()))
            .map(|label| capitalize_first(&label));
        
        let window_count = usize::from(snapshot.primary.is_some()) 
            + usize::from(snapshot.secondary.is_some());
        let combine_non_codex_single_limit = show_limit_prefix && window_count == 1;

        // 添加分组标签（多窗口非 codex 限制）
        if show_limit_prefix && !combine_non_codex_single_limit {
            rows.push(StatusRateLimitRow {
                label: format!("{limit_bucket_label} limit"),
                value: StatusRateLimitValue::Text(String::new()),
            });
        }

        // 添加主窗口行
        if let Some(primary) = snapshot.primary.as_ref() {
            let label = if combine_non_codex_single_limit {
                format!("{} {} limit", limit_bucket_label, 
                    primary_label.clone().unwrap_or_else(|| "5h".to_string()))
            } else {
                format!("{} limit", primary_label.clone().unwrap_or_else(|| "5h".to_string()))
            };
            rows.push(StatusRateLimitRow {
                label,
                value: StatusRateLimitValue::Window {
                    percent_used: primary.used_percent,
                    resets_at: primary.resets_at.clone(),
                },
            });
        }

        // 添加次窗口行
        if let Some(secondary) = snapshot.secondary.as_ref() {
            // ... 类似逻辑
        }

        // 添加额度行
        if let Some(credits) = snapshot.credits.as_ref()
            && let Some(row) = credit_status_row(credits) {
            rows.push(row);
        }
    }

    if rows.is_empty() {
        StatusRateLimitData::Available(vec![])
    } else if stale {
        StatusRateLimitData::Stale(rows)
    } else {
        StatusRateLimitData::Available(rows)
    }
}
```

### 进度条渲染

```rust
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

### 额度处理

```rust
fn credit_status_row(credits: &CreditsSnapshotDisplay) -> Option<StatusRateLimitRow> {
    if !credits.has_credits {
        return None;  // 未启用额度追踪
    }
    if credits.unlimited {
        return Some(StatusRateLimitRow {
            label: "Credits".to_string(),
            value: StatusRateLimitValue::Text("Unlimited".to_string()),
        });
    }
    let balance = credits.balance.as_ref()?;
    let display_balance = format_credit_balance(balance)?;
    Some(StatusRateLimitRow {
        label: "Credits".to_string(),
        value: StatusRateLimitValue::Text(format!("{display_balance} credits")),
    })
}

fn format_credit_balance(raw: &str) -> Option<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }

    // 尝试整数解析
    if let Ok(int_value) = trimmed.parse::<i64>()
        && int_value > 0 {
        return Some(int_value.to_string());
    }

    // 尝试浮点数解析并四舍五入
    if let Ok(value) = trimmed.parse::<f64>()
        && value > 0.0 {
        let rounded = value.round() as i64;
        return Some(rounded.to_string());
    }

    None
}
```

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/status/rate_limits.rs` - 440 行

### 直接依赖
| 文件 | 用途 |
|------|------|
| `../chatwidget.rs` | `get_limits_duration` - 将分钟数转换为人类可读时长 |
| `../text_formatting.rs` | `capitalize_first` - 首字母大写 |
| `helpers.rs` | `format_reset_timestamp` - 格式化重置时间 |

### 外部 crate 依赖
| Crate | 用途 |
|-------|------|
| `chrono` | `DateTime`, `Duration`, `Local`, `Utc` - 时间处理 |
| `codex_protocol` | `CreditsSnapshot`, `RateLimitSnapshot`, `RateLimitWindow` - 协议类型 |

### 调用方
| 文件 | 使用项 |
|------|--------|
| `card.rs` | `RateLimitSnapshotDisplay`, `StatusRateLimitData`, `StatusRateLimitRow`, `StatusRateLimitValue`, `compose_rate_limit_data`, `compose_rate_limit_data_many`, `format_status_limit_summary`, `render_status_limit_progress_bar` |
| `mod.rs` | 多项导出供 `chatwidget.rs` 使用 |

## 依赖与外部交互

### 与 chatwidget.rs 的交互

```rust
use crate::chatwidget::get_limits_duration;
```

`get_limits_duration` 函数将分钟数转换为人类可读的时长字符串：
- 60 → "1h"
- 300 → "5h"
- 10080 → "weekly"

### 与协议层的交互

依赖 `codex_protocol::protocol` 的以下类型：
- `RateLimitSnapshot` - 速率限制快照（来自服务器）
- `RateLimitWindow` - 单个限制窗口
- `CreditsSnapshot` - 额度快照

### 时间处理

使用 `chrono` 处理时区转换：
```rust
let resets_at_utc = window.resets_at
    .and_then(|seconds| DateTime::<Utc>::from_timestamp(seconds, 0))
    .map(|dt| dt.with_timezone(&Local));
```

将 UTC 时间戳转换为本地时间显示。

## 风险、边界与改进建议

### 当前限制

1. **硬编码阈值**: 15 分钟过期阈值是硬编码的，无法配置
2. **固定进度条宽度**: 20 段进度条在极窄终端可能被截断
3. **额度舍入**: 浮点额度四舍五入到整数，可能丢失精度

### 边界情况

1. **空快照列表**: `compose_rate_limit_data_many` 返回 `Missing`
2. **零额度**: `format_credit_balance` 对 0 返回 `None`，隐藏额度行
3. **未来时间**: `render_status_limit_progress_bar` 使用 `clamp(0.0, 1.0)` 处理异常百分比

### 潜在改进

1. **可配置阈值**: 允许用户配置数据过期阈值
2. **动态进度条**: 根据可用宽度调整进度条段数
3. **精确额度**: 保留 1-2 位小数显示额度
4. **时区显示**: 在重置时间旁添加时区提示

### 测试覆盖

文件包含 94 行内联测试（行 345-440），覆盖：
- 非 codex 单限制渲染
- 非 codex 多限制分组

建议添加：
- 数据过期检测测试
- 额度格式化边界测试
- 时区转换测试

### 性能考虑

- 快照转换是 O(1) 操作
- `compose_rate_limit_data_many` 是 O(n) 复杂度，n 为快照数量
- 字符串分配较多，但在 TUI 渲染频率下可接受

### 代码质量

- 使用 `#[derive(Debug, Clone)]` 方便调试和复制
- 文档注释完整，说明关键函数的契约
- 建议为 `StatusRateLimitData` 添加 `is_stale()` 和 `is_available()` 辅助方法
