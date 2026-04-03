# 研究文档：status_snapshot_shows_stale_limits_message.snap

## 场景与职责

此快照文件验证 Codex TUI 状态显示模块在速率限制数据变为"陈旧"（stale）时的警告显示行为。当快照的捕获时间超过 15 分钟阈值时，系统需要向用户发出警告，提示数据可能已不准确。

该测试对应 `codex-rs/tui/src/status/tests.rs` 中的 `status_snapshot_shows_stale_limits_message` 测试函数，验证陈旧数据检测和警告渲染逻辑。

## 功能点目的

### 核心功能
1. **陈旧数据检测**：检测快照捕获时间与当前时间的差值是否超过阈值
2. **警告信息显示**：在状态卡片中添加警告行，提示用户刷新数据
3. **数据仍然显示**：即使数据陈旧，仍然显示现有数据而非隐藏

### 业务逻辑
- 陈旧阈值定义为 15 分钟（`RATE_LIMIT_STALE_THRESHOLD_MINUTES`）
- 陈旧状态通过 `StatusRateLimitData::Stale` 枚举变体表示
- 警告消息："limits may be stale - start new turn to refresh."

## 具体技术实现

### 关键数据结构

```rust
// rate_limits.rs:47-55
pub(crate) enum StatusRateLimitData {
    Available(Vec<StatusRateLimitRow>),  // 数据新鲜
    Stale(Vec<StatusRateLimitRow>),      // 数据陈旧（超过15分钟）
    Missing,                              // 数据缺失
}

// rate_limits.rs:57-58
pub(crate) const RATE_LIMIT_STALE_THRESHOLD_MINUTES: i64 = 15;
```

### 陈旧检测算法

```rust
// rate_limits.rs:168-181
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
        // 关键：检测每个快照的陈旧状态
        stale |= now.signed_duration_since(snapshot.captured_at)
            > ChronoDuration::minutes(RATE_LIMIT_STALE_THRESHOLD_MINUTES);
        
        // ... 构建 rows
    }

    if rows.is_empty() {
        StatusRateLimitData::Available(vec![])
    } else if stale {
        StatusRateLimitData::Stale(rows)  // 任一快照陈旧即整体陈旧
    } else {
        StatusRateLimitData::Available(rows)
    }
}
```

### 警告渲染逻辑

```rust
// card.rs:322-330
StatusRateLimitData::Stale(rows_data) => {
    let mut lines = self.rate_limit_row_lines(rows_data, available_inner_width, formatter);
    // 在现有数据行后添加警告行
    lines.push(formatter.line(
        "Warning",
        vec![Span::from("limits may be stale - start new turn to refresh.").dim()],
    ));
    lines
}
```

### 测试用例构造

```rust
// tests.rs:832-896
let captured_at = chrono::Local
    .with_ymd_and_hms(2024, 1, 2, 3, 4, 5)
    .single()
    .expect("timestamp");

let snapshot = RateLimitSnapshot {
    limit_id: None,
    limit_name: None,
    primary: Some(RateLimitWindow {
        used_percent: 72.5,
        window_minutes: Some(300),
        resets_at: Some(reset_at_from(&captured_at, 600)),
    }),
    secondary: Some(RateLimitWindow {
        used_percent: 40.0,
        window_minutes: Some(10_080),
        resets_at: Some(reset_at_from(&captured_at, 1_800)),
    }),
    credits: None,
    plan_type: None,
};

let rate_display = rate_limit_snapshot_display(&snapshot, captured_at);
let now = captured_at + ChronoDuration::minutes(20);  // 20分钟后，超过15分钟阈值
```

### 渲染输出分析

```
╭───────────────────────────────────────────────────────────────────────╮
│  >_ OpenAI Codex (v0.0.0)                                             │
│                                                                       │
│ Visit https://chatgpt.com/codex/settings/usage for up-to-date         │
│ information on rate limits and credits                                │
│                                                                       │
│  Model:            gpt-5.1-codex-max (reasoning none, summaries auto) │
│  Directory: [[workspace]]                                             │
│  Permissions:      Custom (read-only, on-request)                     │
│  Agents.md:        <none>                                             │
│                                                                       │
│  Token usage:      1.9K total  (1K input + 900 output)                │
│  Context window:   100% left (2.25K used / 272K)                      │
│  5h limit:         [██████░░░░░░░░░░░░░░] 28% left (resets 03:14)     │
│  Weekly limit:     [████████████░░░░░░░░] 60% left (resets 03:34)     │
│  Warning:          limits may be stale - start new turn to refresh.   │
╰───────────────────────────────────────────────────────────────────────╯
```

关键验证点：
1. **数据仍然显示**：5h 和 Weekly 限制正常显示
2. **警告行添加**：在限制行后添加 Warning 行
3. **暗淡样式**：警告消息使用 `.dim()` 样式
4. **进度条计算**：
   - 5h：72.5% 已使用 → 27.5% 剩余 → 约 6 个填充块
   - Weekly：40% 已使用 → 60% 剩余 → 约 12 个填充块

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|-----|------|
| `codex-rs/tui/src/status/tests.rs` | 测试定义，第 832-896 行 |
| `codex-rs/tui/src/status/card.rs` | 陈旧数据渲染，第 322-330 行 |
| `codex-rs/tui/src/status/rate_limits.rs` | 陈旧检测算法，第 168-181 行 |

### 渲染调用链

```
new_status_output
  └── StatusHistoryCell::new
      └── compose_rate_limit_data (rate_limits.rs:158)
          └── compose_rate_limit_data_many
              ├── 计算 stale = now - captured_at > 15 minutes
              │   └── 20分钟 > 15分钟 -> true
              └── 返回 StatusRateLimitData::Stale(rows)
  └── StatusHistoryCell::display_lines (card.rs:413)
      └── rate_limit_lines (card.rs:307)
          └── 匹配 StatusRateLimitData::Stale(rows_data)
              ├── 渲染限制行（5h, Weekly）
              └── 添加 Warning 行
```

### 标签收集逻辑

```rust
// card.rs:401-406
StatusRateLimitData::Stale(rows) => {
    for row in rows {
        push_label(&mut labels, &mut seen, row.label.as_str());
    }
    push_label(&mut labels, &mut seen, "Warning");  // 添加 Warning 标签
}
```

### FieldFormatter 行构建

```rust
// format.rs:38-44
pub(crate) fn line(
    &self,
    label: &'static str,
    value_spans: Vec<Span<'static>>,
) -> Line<'static> {
    Line::from(self.full_spans(label, value_spans))
}
```

## 依赖与外部交互

### 外部 crate

| crate | 用途 |
|-------|------|
| `chrono` | 时间差计算，`signed_duration_since` |
| `ratatui` | 终端渲染，`.dim()` 样式 |
| `insta` | 快照测试 |

### 时间计算

```rust
use chrono::{DateTime, Local, Duration as ChronoDuration};

// 陈旧检测
let duration = now.signed_duration_since(snapshot.captured_at);
let is_stale = duration > ChronoDuration::minutes(15);
```

## 风险、边界与改进建议

### 当前风险

1. **硬编码阈值**：15 分钟阈值无法配置，对某些使用场景可能不合适
2. **单一阈值**：所有限制类型使用相同的陈旧阈值，但不同限制可能有不同的更新频率
3. **警告信息固定**："start new turn to refresh" 假设特定交互模型，可能不适用于所有场景

### 边界情况

1. **刚好在阈值**：15 分钟整时不视为陈旧（使用 `>` 而非 `>=`）
2. **多个快照**：只要任一快照陈旧，整体视为陈旧
3. **负时间差**：如果 `now < captured_at`（时钟回拨），`signed_duration_since` 返回负值，不会触发陈旧

### 改进建议

1. **可配置阈值**：
   ```rust
   // 在 Config 中添加
   pub rate_limit_stale_threshold_minutes: Option<i64>,
   ```

2. **分级陈旧**：
   ```rust
   pub(crate) enum StatusRateLimitData {
       Fresh(Vec<StatusRateLimitRow>),      // < 5分钟
       Recent(Vec<StatusRateLimitRow>),     // 5-15分钟
       Stale(Vec<StatusRateLimitRow>),      // > 15分钟
       Missing,
   }
   ```

3. **每限制陈旧**：
   - 分别跟踪每个限制窗口的陈旧状态
   - 只标记真正陈旧的限制，而非整体

4. **自动刷新**：
   - 检测到陈旧时自动尝试刷新
   - 添加配置选项控制自动刷新行为

5. **改进消息**：
   - 显示数据年龄："limits are 20 minutes old"
   - 添加快捷键提示："Press R to refresh"

6. **测试扩展**：
   - 测试刚好 15 分钟的边界
   - 测试多个快照部分陈旧的情况
   - 测试时钟回拨场景
   - 测试夏令时转换期间的行为

7. **视觉改进**：
   - 使用黄色/橙色表示陈旧警告（当前使用暗淡样式）
   - 在进度条上添加陈旧指示器
   - 添加最后更新时间戳
