# 研究文档：status_snapshot_includes_monthly_limit.snap

## 场景与职责

此快照文件验证 Codex TUI 状态显示模块对月度速率限制（monthly limit）的正确渲染。与常规的 5 小时和每周限制不同，月度限制代表更长周期的使用配额，通常用于企业级或高级订阅计划。

该测试对应 `codex-rs/tui/src/status/tests.rs` 中的 `status_snapshot_includes_monthly_limit` 测试函数，验证当 `RateLimitWindow.window_minutes` 设置为月度时长（43,200 分钟 = 30 天）时的显示行为。

## 功能点目的

### 核心功能
1. **月度限制检测**：通过 `window_minutes` 值识别月度限制（43,200 分钟 = 30 天）
2. **智能标签生成**：根据窗口时长生成人类可读的标签（如 "Monthly limit"）
3. **跨天重置时间**：当重置时间跨天时，显示完整日期（如 "07:08 on 7 May"）

### 业务逻辑
- 限制标签通过 `get_limits_duration` 函数从分钟数转换
- 43,200 分钟对应 "30d"，首字母大写后显示为 "Monthly limit"
- 重置时间格式化考虑当前日期，跨天时附加日期信息

## 具体技术实现

### 窗口时长到标签的映射

```rust
// chatwidget.rs (通过 get_limits_duration)
pub fn get_limits_duration(window_minutes: i64) -> String {
    if window_minutes >= 7 * 24 * 60 {  // >= 10080 分钟（1周）
        let weeks = window_minutes / (7 * 24 * 60);
        format!("{}w", weeks)
    } else if window_minutes >= 24 * 60 {  // >= 1440 分钟（1天）
        let days = window_minutes / (24 * 60);
        format!("{}d", days)
    } else if window_minutes >= 60 {  // >= 60 分钟
        let hours = window_minutes / 60;
        format!("{}h", hours)
    } else {
        format!("{}m", window_minutes)
    }
}
```

### 标签首字母大写

```rust
// rate_limits.rs:194
let primary_label = snapshot
    .primary
    .as_ref()
    .map(|window| {
        window
            .window_minutes
            .map(get_limits_duration)
            .unwrap_or_else(|| "5h".to_string())
    })
    .map(|label| capitalize_first(&label));  // "30d" -> "30d" -> "Monthly" (通过特殊处理)
```

注意：实际代码中 `capitalize_first` 只是首字母大写，但快照显示 "Monthly" 而非 "30d"，说明有额外的映射逻辑或测试使用了特定的 `limit_name`。

### 重置时间格式化

```rust
// helpers.rs:169-176
pub(crate) fn format_reset_timestamp(dt: DateTime<Local>, captured_at: DateTime<Local>) -> String {
    let time = dt.format("%H:%M").to_string();
    if dt.date_naive() == captured_at.date_naive() {
        time  // 同一天只显示时间，如 "07:08"
    } else {
        format!("{time} on {}", dt.format("%-d %b"))  // 跨天显示日期，如 "07:08 on 7 May"
    }
}
```

### 测试用例构造

```rust
// tests.rs:293-353
let captured_at = chrono::Local
    .with_ymd_and_hms(2024, 5, 6, 7, 8, 9)  // 5月6日
    .single()
    .expect("timestamp");

let snapshot = RateLimitSnapshot {
    limit_id: None,
    limit_name: None,
    primary: Some(RateLimitWindow {
        used_percent: 12.0,  // 12% 已使用 = 88% 剩余
        window_minutes: Some(43_200),  // 30 天 = 月度
        resets_at: Some(reset_at_from(&captured_at, 86_400)),  // 1天后重置（5月7日）
    }),
    secondary: None,  // 无次要窗口
    credits: None,
    plan_type: None,
};
```

### 渲染输出分析

```
╭────────────────────────────────────────────────────────────────────────────╮
│  >_ OpenAI Codex (v0.0.0)                                                  │
│                                                                            │
│ Visit https://chatgpt.com/codex/settings/usage for up-to-date              │
│ information on rate limits and credits                                     │
│                                                                            │
│  Model:            gpt-5.1-codex-max (reasoning none, summaries auto)      │
│  Directory: [[workspace]]                                                  │
│  Permissions:      Custom (read-only, on-request)                          │
│  Agents.md:        <none>                                                  │
│                                                                            │
│  Token usage:      1.2K total  (800 input + 400 output)                    │
│  Context window:   100% left (1.2K used / 272K)                            │
│  Monthly limit:    [██████████████████░░] 88% left (resets 07:08 on 7 May) │
╰────────────────────────────────────────────────────────────────────────────╯
```

关键验证点：
1. **标签识别**：正确显示 "Monthly limit" 而非 "30d limit"
2. **进度条计算**：88% 剩余 → 约 18 个填充块（20×0.88≈17.6，四舍五入为 18）
3. **跨天重置时间**：显示 "07:08 on 7 May"，因为重置时间是 5月7日
4. **单一限制**：只有月度限制，无 5h/Weekly 限制

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|-----|------|
| `codex-rs/tui/src/status/tests.rs` | 测试定义，第 293-353 行 |
| `codex-rs/tui/src/status/rate_limits.rs` | 限制标签生成，第 185-228 行 |
| `codex-rs/tui/src/status/helpers.rs` | 重置时间格式化，第 169-176 行 |
| `codex-rs/tui/src/chatwidget.rs` | `get_limits_duration` 函数 |

### 标签生成调用链

```rust
// rate_limits.rs:185-228 (compose_rate_limit_data_many 中的标签生成)
let primary_label = snapshot
    .primary
    .as_ref()
    .map(|window| {
        window
            .window_minutes
            .map(get_limits_duration)  // 43_200 -> "30d"
            .unwrap_or_else(|| "5h".to_string())
    })
    .map(|label| capitalize_first(&label));  // "30d" -> "30d" (首字母大写)

// 实际标签构建
let label = format!(
    "{} limit",
    primary_label.clone().unwrap_or_else(|| "5h".to_string())
);
// 结果: "30d limit" 或经过特殊处理的 "Monthly limit"
```

**注意**：快照显示 "Monthly limit"，但代码逻辑会生成 "30d limit"。这可能表明：
1. 测试使用了特定的 `limit_name` 字段覆盖
2. 存在额外的标签映射逻辑未在当前代码中显示
3. 快照是在代码修改前生成的

### 重置时间计算

```rust
// rate_limits.rs:72-85 (RateLimitWindowDisplay::from_window)
fn from_window(window: &RateLimitWindow, captured_at: DateTime<Local>) -> Self {
    let resets_at_utc = window
        .resets_at
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

## 依赖与外部交互

### 外部 crate

| crate | 用途 |
|-------|------|
| `chrono` | 日期时间处理和格式化 |
| `ratatui` | 终端渲染 |
| `insta` | 快照测试 |

### 时间计算

```rust
use chrono::{DateTime, Local, Utc, Duration as ChronoDuration};

// reset_at_from 辅助函数
captured_at + ChronoDuration::seconds(seconds)
```

## 风险、边界与改进建议

### 当前风险

1. **标签硬编码假设**：代码假设 43,200 分钟是月度，但实际月份天数不同（28-31 天）
2. **时区问题**：跨天判断基于本地时区，用户在不同时区可能看到不同的日期显示
3. **单复数处理**："1 day" vs "2 days" 的显示未在代码中体现

### 边界情况

1. **闰秒和 DST**：夏令时转换期间，时间计算可能有 1 小时偏差
2. **极长窗口**：超过 30 天的窗口（如季度、年度）没有专门处理
3. **零窗口时长**：`window_minutes: Some(0)` 会导致除以零或空标签

### 改进建议

1. **智能月份检测**：
   ```rust
   fn get_limit_label(window_minutes: i64) -> String {
       match window_minutes {
           43_200 => "Monthly".to_string(),  // 30 天
           // 或者更智能的检测
           n if n >= 28 * 24 * 60 && n <= 31 * 24 * 60 => "Monthly".to_string(),
           _ => capitalize_first(&get_limits_duration(window_minutes)),
       }
   }
   ```

2. **相对时间显示**：
   - 添加 "resets in 2 days" 格式的相对时间
   - 在接近重置时显示倒计时（如 "resets in 5 hours"）

3. **本地化支持**：
   - 日期格式本地化（"7 May" vs "May 7"）
   - 多语言标签支持

4. **测试扩展**：
   - 测试 DST 转换期间的时间显示
   - 测试不同月份天数（28/29/30/31）
   - 测试跨年重置（12月31日 -> 1月1日）

5. **代码文档**：
   - 在 `get_limits_duration` 中添加月度特殊处理的注释
   - 解释为什么 43,200 分钟被视为月度
