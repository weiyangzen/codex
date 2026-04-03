# rate_limits.rs 研究文档

## 场景与职责

`rate_limits.rs` 是 Codex TUI 状态显示模块中负责速率限制和额度显示的核心组件。该模块将协议层的 `RateLimitSnapshot` 转换为 TUI 可渲染的显示结构，支持多限制组（如 `codex` 和 `codex_other`）、进度条渲染、过期检测和额度显示。

## 功能点目的

### 核心功能

1. **速率限制数据转换**: 将协议快照转换为显示友好的结构
2. **多限制组支持**: 处理主限制组和其他限制组（如不同模型的限制）
3. **过期检测**: 检测快照数据是否超过 15 分钟阈值
4. **进度条渲染**: 生成 Unicode 块字符进度条
5. **额度显示**: 处理 credits 余额显示（包括无限额度）

### 核心数据结构

```rust
/// 单条速率限制行
#[derive(Debug, Clone)]
pub(crate) struct StatusRateLimitRow {
    pub label: String,           // 如 "5h limit", "Credits"
    pub value: StatusRateLimitValue,
}

/// 速率限制值变体
#[derive(Debug, Clone)]
pub(crate) enum StatusRateLimitValue {
    Window {
        percent_used: f64,       // 已使用百分比
        resets_at: Option<String>, // 重置时间文本
    },
    Text(String),               // 纯文本值（如额度）
}

/// 速率限制数据可用性状态
#[derive(Debug, Clone)]
pub(crate) enum StatusRateLimitData {
    Available(Vec<StatusRateLimitRow>),  // 数据可用
    Stale(Vec<StatusRateLimitRow>),      // 数据过期
    Missing,                             // 数据缺失
}

/// 显示友好的窗口数据
#[derive(Debug, Clone)]
pub(crate) struct RateLimitWindowDisplay {
    pub used_percent: f64,
    pub resets_at: Option<String>,
    pub window_minutes: Option<i64>,
}

/// 显示友好的快照数据
#[derive(Debug, Clone)]
pub(crate) struct RateLimitSnapshotDisplay {
    pub limit_name: String,              // 如 "codex", "codex_other"
    pub captured_at: DateTime<Local>,    // 本地捕获时间
    pub primary: Option<RateLimitWindowDisplay>,    // 主窗口（通常 5 小时）
    pub secondary: Option<RateLimitWindowDisplay>,  // 次窗口（通常每周）
    pub credits: Option<CreditsSnapshotDisplay>,    // 额度信息
}

/// 额度显示数据
#[derive(Debug, Clone)]
pub(crate) struct CreditsSnapshotDisplay {
    pub has_credits: bool,      // 是否启用额度跟踪
    pub unlimited: bool,        // 是否无限额度
    pub balance: Option<String>, // 余额文本
}
```

## 具体技术实现

### 1. 常量定义

```rust
const STATUS_LIMIT_BAR_SEGMENTS: usize = 20;        // 进度条分段数
const STATUS_LIMIT_BAR_FILLED: &str = "█";          // 已填充字符 (U+2588)
const STATUS_LIMIT_BAR_EMPTY: &str = "░";           // 未填充字符 (U+2591)
pub(crate) const RATE_LIMIT_STALE_THRESHOLD_MINUTES: i64 = 15;  // 过期阈值
```

### 2. 窗口显示转换

```rust
impl RateLimitWindowDisplay {
    fn from_window(window: &RateLimitWindow, captured_at: DateTime<Local>) -> Self {
        // UTC 时间戳转本地时间
        let resets_at_utc = window
            .resets_at
            .and_then(|seconds| DateTime::<Utc>::from_timestamp(seconds, 0))
            .map(|dt| dt.with_timezone(&Local));
        
        // 格式化重置时间（相对于捕获时间）
        let resets_at = resets_at_utc.map(|dt| format_reset_timestamp(dt, captured_at));

        Self {
            used_percent: window.used_percent,
            resets_at,
            window_minutes: window.window_minutes,
        }
    }
}
```

### 3. 快照显示转换

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

### 4. 多限制组数据处理

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
        // 检测过期
        stale |= now.signed_duration_since(snapshot.captured_at)
            > ChronoDuration::minutes(RATE_LIMIT_STALE_THRESHOLD_MINUTES);

        let limit_bucket_label = snapshot.limit_name.clone();
        let show_limit_prefix = !limit_bucket_label.eq_ignore_ascii_case("codex");
        
        // 获取窗口标签（如 "5h", "weekly"）
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

        // 非 codex 多窗口时显示分组标题
        if show_limit_prefix && !combine_non_codex_single_limit {
            rows.push(StatusRateLimitRow {
                label: format!("{limit_bucket_label} limit"),
                value: StatusRateLimitValue::Text(String::new()),
            });
        }

        // 主窗口行
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

        // 次窗口行
        if let Some(secondary) = snapshot.secondary.as_ref() {
            // ... 类似主窗口
        }

        // 额度行
        if let Some(credits) = snapshot.credits.as_ref()
            && let Some(row) = credit_status_row(credits)
        {
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

### 5. 进度条渲染

```rust
pub(crate) fn render_status_limit_progress_bar(percent_remaining: f64) -> String {
    let ratio = (percent_remaining / 100.0).clamp(0.0, 1.0);
    let filled = (ratio * STATUS_LIMIT_BAR_SEGMENTS as f64).round() as usize;
    let filled = filled.min(STATUS_LIMIT_BAR_SEGMENTS);
    let empty = STATUS_LIMIT_BAR_SEGMENTS.saturating_sub(filled);
    
    format!("[{}{}]",
        STATUS_LIMIT_BAR_FILLED.repeat(filled),
        STATUS_LIMIT_BAR_EMPTY.repeat(empty))
}
```

**渲染示例**:
- 75% 剩余: `[███████████████░░░░░]`
- 30% 剩余: `[██████░░░░░░░░░░░░░░]`

### 6. 额度行构建

```rust
fn credit_status_row(credits: &CreditsSnapshotDisplay) -> Option<StatusRateLimitRow> {
    if !credits.has_credits {
        return None;  // 未启用额度跟踪
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
    if trimmed.is_empty() { return None; }

    // 尝试整数解析
    if let Ok(int_value) = trimmed.parse::<i64>()
        && int_value > 0
    {
        return Some(int_value.to_string());
    }

    // 尝试浮点数解析并四舍五入
    if let Ok(value) = trimmed.parse::<f64>()
        && value > 0.0
    {
        let rounded = value.round() as i64;
        return Some(rounded.to_string());
    }

    None  // 零或负数不显示
}
```

## 关键代码路径与文件引用

### 上游依赖（输入）

| 模块/类型 | 来源 | 用途 |
|-----------|------|------|
| `RateLimitSnapshot` | `codex_protocol::protocol` | 协议层速率限制快照 |
| `RateLimitWindow` | `codex_protocol::protocol` | 协议层窗口数据 |
| `CreditsSnapshot` | `codex_protocol::protocol` | 协议层额度快照 |
| `format_reset_timestamp` | `helpers.rs` | 时间戳格式化 |
| `get_limits_duration` | `chatwidget.rs` | 分钟转可读时长 |
| `capitalize_first` | `text_formatting.rs` | 首字母大写 |

### 下游调用方

| 模块 | 路径 | 用途 |
|------|------|------|
| `card.rs` | `./card.rs` | 调用 `compose_rate_limit_data` 等函数 |
| `chatwidget.rs` | `../chatwidget.rs` | 调用 `rate_limit_snapshot_display_for_limit` |

### 依赖关系

```
rate_limits.rs
├── helpers.rs (format_reset_timestamp)
├── chatwidget.rs (get_limits_duration)
└── text_formatting.rs (capitalize_first)
```

## 依赖与外部交互

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `chrono` | `DateTime`, `Local`, `Utc`, `Duration` 时间处理 |
| `codex_protocol` | 协议类型定义 |

### 协议类型映射

```rust
// 协议层 → 显示层
RateLimitSnapshot → RateLimitSnapshotDisplay
RateLimitWindow → RateLimitWindowDisplay
CreditsSnapshot → CreditsSnapshotDisplay
```

## 风险、边界与改进建议

### 边界情况

1. **过期检测**:
   - 阈值: 15 分钟（`RATE_LIMIT_STALE_THRESHOLD_MINUTES`）
   - 使用本地时间比较，依赖系统时钟

2. **空数据处理**:
   - 空快照数组 → `StatusRateLimitData::Missing`
   - 空行数组 → `StatusRateLimitData::Available(vec![])`

3. **额度显示**:
   - 零或负余额 → 不显示额度行
   - 无限额度 → 显示 "Unlimited"
   - 浮点余额 → 四舍五入到整数

4. **进度条边界**:
   - 百分比钳位到 0-100
   - 填充段数钳位到 0-20

### 潜在风险

1. **时区问题**:
   - 使用 `DateTime<Local>`，依赖系统时区设置正确
   - 跨时区使用可能导致过期检测不准确

2. **浮点精度**:
   - `percent_remaining` 计算使用浮点运算
   - 极端值可能导致进度条显示偏差

3. **性能问题**:
   - 每次渲染都重新计算所有显示值
   - 多限制组时遍历开销随组数线性增长

4. **硬编码值**:
   - "5h" 和 "weekly" 作为默认标签
   - 15 分钟过期阈值

### 改进建议

1. **缓存优化**:
   - 缓存 `RateLimitSnapshotDisplay` 避免重复转换
   - 仅在快照数据变化时重新计算

2. **配置化**:
   - 将过期阈值设为可配置
   - 允许自定义进度条样式

3. **精度改进**:
   - 使用定点数或整数百分比避免浮点误差
   - 添加进度条动画（可选）

4. **测试覆盖**:
   - 添加边界值测试（0%, 100%, 空数据）
   - 测试跨天时的时间戳格式化

### 代码度量

- 代码行数: 440 行
- 公共结构体: 5 个
- 公共函数: 6 个
- 私有函数: 2 个 (`credit_status_row`, `format_credit_balance`)
- 复杂度: 中等（主要是 `compose_rate_limit_data_many` 的条件逻辑）

### 测试

模块包含内联测试，覆盖：
1. 非 codex 单限制组渲染
2. 非 codex 多限制组渲染

测试使用 `pretty_assertions` 进行清晰的差异比较。
