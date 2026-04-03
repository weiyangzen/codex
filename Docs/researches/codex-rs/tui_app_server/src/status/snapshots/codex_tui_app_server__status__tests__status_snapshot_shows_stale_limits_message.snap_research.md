# 研究文档: codex_tui_app_server__status__tests__status_snapshot_shows_stale_limits_message.snap

## 场景与职责

此快照文件是 `codex-tui-app-server` crate 中状态显示功能的 insta 快照测试结果，测试用例为 `status_snapshot_shows_stale_limits_message`。该测试验证当速率限制数据过时（超过 15 分钟）时，状态显示能正确显示数据并附加过时警告。

## 功能点目的

### 测试目标
验证以下场景的状态显示行为：
1. **过时数据检测**: 捕获时间与当前时间相差超过 15 分钟
2. **数据仍显示**: 显示限制信息（5h 和 Weekly）
3. **警告提示**: "Warning: limits may be stale - start new turn to refresh."

## 具体技术实现

### 关键数据结构

```rust
pub(crate) const RATE_LIMIT_STALE_THRESHOLD_MINUTES: i64 = 15;

pub(crate) enum StatusRateLimitData {
    Available(Vec<StatusRateLimitRow>),
    Stale(Vec<StatusRateLimitRow>),
    Missing,
}
```

### 关键流程

1. **过时检测** (`rate_limits.rs:179-181`):
```rust
for snapshot in snapshots {
    stale |= now.signed_duration_since(snapshot.captured_at)
        > ChronoDuration::minutes(RATE_LIMIT_STALE_THRESHOLD_MINUTES);
}
```

2. **Stale 状态渲染** (`card.rs:321-329`):
```rust
StatusRateLimitData::Stale(rows_data) => {
    let mut lines = self.rate_limit_row_lines(rows_data, available_inner_width, formatter);
    lines.push(formatter.line(
        "Warning",
        vec![Span::from("limits may be stale - start new turn to refresh.").dim()],
    ));
    lines
}
```

3. **测试数据** (`tests.rs:828-892`):
```rust
let captured_at = chrono::Local
    .with_ymd_and_hms(2024, 1, 2, 3, 4, 5)
    .single()
    .expect("timestamp");

// 当前时间比捕获时间晚 20 分钟
let now = captured_at + ChronoDuration::minutes(20);

let composite = new_status_output(
    &config,
    account_display.as_ref(),
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
| `tui_app_server/src/status/tests.rs:828-892` | 测试用例定义 |
| `tui_app_server/src/status/rate_limits.rs:57-58` | 过时阈值常量 |
| `tui_app_server/src/status/rate_limits.rs:179-181` | 过时检测 |
| `tui_app_server/src/status/card.rs:321-329` | Stale 状态渲染 |

## 依赖与外部交互

### 过时阈值
```rust
const RATE_LIMIT_STALE_THRESHOLD_MINUTES: i64 = 15;
```

## 风险、边界与改进建议

### 当前风险
1. **硬编码阈值**: 15 分钟无法配置
2. **整体标记**: 任一快照过时即整体标记为 Stale

### 改进建议
1. **可配置阈值**: 允许通过环境变量调整
2. **逐快照标记**: 为每个快照单独标记过时状态

### 测试覆盖
- ✅ 过时数据检测（20 分钟 > 15 分钟）
- ✅ Stale 状态
- ✅ 警告提示
