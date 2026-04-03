# 研究文档: status_snapshot_shows_stale_limits_message.snap

## 场景与职责

此快照文件是 `codex-tui` crate 中状态显示功能的 insta 快照测试结果，测试用例为 `status_snapshot_shows_stale_limits_message`。该测试验证当速率限制数据过时（超过 15 分钟）时，状态显示能正确显示数据并附加过时警告。

## 功能点目的

### 测试目标
验证以下场景的状态显示行为：
1. **过时数据检测**: 当捕获时间与当前时间相差超过 15 分钟时标记为 stale
2. **数据仍显示**: 即使数据过时，仍显示限制信息（5h 和 Weekly）
3. **警告提示**: 添加 "Warning: limits may be stale - start new turn to refresh."

### 业务逻辑
- 速率限制数据可能因网络问题或用户长时间不活动而过时
- 用户需要知道数据可能不准确，但仍有参考价值
- 提示用户通过开始新对话来刷新数据

## 具体技术实现

### 关键数据结构

```rust
pub(crate) enum StatusRateLimitData {
    Available(Vec<StatusRateLimitRow>),  // 新鲜数据
    Stale(Vec<StatusRateLimitRow>),      // 过时数据
    Missing,                              // 无数据
}

pub(crate) const RATE_LIMIT_STALE_THRESHOLD_MINUTES: i64 = 15;
```

### 关键流程

1. **过时检测** (`rate_limits.rs:179-181`):
```rust
pub(crate) fn compose_rate_limit_data_many(
    snapshots: &[RateLimitSnapshotDisplay],
    now: DateTime<Local>,
) -> StatusRateLimitData {
    let mut stale = false;
    
    for snapshot in snapshots {
        // 检测每个快照是否过时
        stale |= now.signed_duration_since(snapshot.captured_at)
            > ChronoDuration::minutes(RATE_LIMIT_STALE_THRESHOLD_MINUTES);
        // ...
    }
    
    if rows.is_empty() {
        StatusRateLimitData::Available(vec![])
    } else if stale {
        StatusRateLimitData::Stale(rows)  // 任一快照过时即整体标记为 Stale
    } else {
        StatusRateLimitData::Available(rows)
    }
}
```

2. **Stale 状态渲染** (`card.rs:321-329`):
```rust
fn rate_limit_lines(&self, ...) -> Vec<Line<'static>> {
    match &self.rate_limits {
        // ...
        StatusRateLimitData::Stale(rows_data) => {
            let mut lines = self.rate_limit_row_lines(rows_data, available_inner_width, formatter);
            // 添加警告行
            lines.push(formatter.line(
                "Warning",
                vec![Span::from("limits may be stale - start new turn to refresh.").dim()],
            ));
            lines
        }
        // ...
    }
}
```

3. **测试数据设置** (`tests.rs:832-896`):
```rust
let captured_at = chrono::Local
    .with_ymd_and_hms(2024, 1, 2, 3, 4, 5)
    .single()
    .expect("timestamp");
let snapshot = RateLimitSnapshot {
    primary: Some(RateLimitWindow { used_percent: 72.5, ... }),
    secondary: Some(RateLimitWindow { used_percent: 40.0, ... }),
    ...
};
let rate_display = rate_limit_snapshot_display(&snapshot, captured_at);

// 当前时间比捕获时间晚 20 分钟，超过 15 分钟阈值
let now = captured_at + ChronoDuration::minutes(20);

let composite = new_status_output(
    &config,
    &auth_manager,
    Some(&token_info),
    &usage,
    &None,
    None,
    None,
    Some(&rate_display),
    None,
    now,  // 使用晚于 captured_at 的时间
    &model_slug,
    None,
    None,
);
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `tui/src/status/tests.rs:832-896` | 测试用例定义 |
| `tui/src/status/rate_limits.rs:57-58` | 过时阈值常量定义 |
| `tui/src/status/rate_limits.rs:179-181` | 过时检测逻辑 |
| `tui/src/status/rate_limits.rs:273-277` | Stale 状态返回 |
| `tui/src/status/card.rs:321-329` | Stale 状态渲染（含警告） |

## 依赖与外部交互

### 依赖模块
- `chrono::Duration` - 时间差计算
- `chrono::DateTime` - 时间戳比较

### 过时阈值
```rust
const RATE_LIMIT_STALE_THRESHOLD_MINUTES: i64 = 15;
```
此值是硬编码的，不可配置。

## 风险、边界与改进建议

### 当前风险
1. **硬编码阈值**: 15 分钟阈值无法根据用户需求调整
2. **整体标记**: 任一快照过时即整体标记为 Stale，可能误伤新鲜数据
3. **时区问题**: 如果系统时钟被修改，可能误判过时状态

### 边界情况
1. **刚好 15 分钟**: 边界值处理（当前使用 `>`，所以 15 分钟整不算过时）
2. **多快照混合**: 如果一个快照新鲜、一个过时，整体标记为 Stale
3. **负时间差**: 如果 `now < captured_at`，不会标记为过时
4. **夏令时切换**: 可能导致意外的过时检测

### 改进建议
1. **可配置阈值**: 允许通过环境变量或配置调整阈值
2. **逐快照标记**: 为每个快照单独标记过时状态
3. **相对时间显示**: 显示 "captured 20 minutes ago" 而非仅警告
4. **自动刷新**: 检测到过时数据时自动触发刷新
5. **时间同步提示**: 如果检测到系统时间可能不准确，提示用户

### 测试覆盖
此快照测试覆盖了以下场景：
- ✅ 过时数据检测（20 分钟 > 15 分钟阈值）
- ✅ Stale 状态设置
- ✅ 过时数据仍显示（5h 和 Weekly 限制）
- ✅ 警告提示显示

### 相关测试
- `status_snapshot_cached_limits_hide_credits_without_flag` - 也测试了过时场景
- `status_snapshot_includes_credits_and_limits` - 测试新鲜数据场景

### 显示对比
| 状态 | 显示 |
|------|------|
| Available | 限制数据行 |
| Stale | 限制数据行 + Warning 行 |
| Missing | "Limits: data not available yet" |
