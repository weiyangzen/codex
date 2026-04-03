# 研究文档: status_snapshot_cached_limits_hide_credits_without_flag.snap

## 场景与职责

此快照文件是 `codex-tui` crate 中状态显示功能的 insta 快照测试结果，具体测试用例为 `status_snapshot_cached_limits_hide_credits_without_flag`。该测试验证当速率限制数据被缓存（即过时）且 `has_credits` 标志为 false 时，状态显示是否正确隐藏 credits 信息并显示过时警告。

## 功能点目的

### 测试目标
验证以下场景的状态显示行为：
1. **缓存/过时限制数据**: 当速率限制快照的捕获时间与当前时间相差超过 15 分钟时，数据显示为 "stale"（过时）
2. **隐藏 Credits**: 当 `CreditsSnapshot.has_credits = false` 时，即使有余额信息也不显示 credits
3. **警告提示**: 在过时数据情况下显示警告行 "limits may be stale - start new turn to refresh"

### 业务逻辑
- 用户需要知道速率限制数据是否新鲜，以避免基于过时信息做决策
- Credits 显示受 `has_credits` 标志控制，而非仅依赖余额值

## 具体技术实现

### 关键数据结构

```rust
// 来自 codex_protocol::protocol
pub struct RateLimitSnapshot {
    pub limit_id: Option<String>,
    pub limit_name: Option<String>,
    pub primary: Option<RateLimitWindow>,      // 5小时限制窗口
    pub secondary: Option<RateLimitWindow>,    // 每周限制窗口
    pub credits: Option<CreditsSnapshot>,
    pub plan_type: Option<PlanType>,
}

pub struct CreditsSnapshot {
    pub has_credits: bool,      // 控制是否显示 credits
    pub unlimited: bool,
    pub balance: Option<String>,
}
```

### 关键流程

1. **过时检测** (`rate_limits.rs:180-181`):
```rust
stale |= now.signed_duration_since(snapshot.captured_at)
    > ChronoDuration::minutes(RATE_LIMIT_STALE_THRESHOLD_MINUTES); // 15分钟
```

2. **Credits 行构建** (`rate_limits.rs:305-321`):
```rust
fn credit_status_row(credits: &CreditsSnapshotDisplay) -> Option<StatusRateLimitRow> {
    if !credits.has_credits {
        return None;  // 关键：has_credits=false 时直接返回 None
    }
    // ...
}
```

3. **状态显示渲染** (`card.rs:306-334`):
```rust
fn rate_limit_lines(&self, ...) -> Vec<Line<'static>> {
    match &self.rate_limits {
        StatusRateLimitData::Stale(rows_data) => {
            let mut lines = self.rate_limit_row_lines(rows_data, ...);
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

### 测试用例设置

```rust
// tests.rs:898-940
let snapshot = RateLimitSnapshot {
    primary: Some(RateLimitWindow { used_percent: 60.0, ... }),
    secondary: Some(RateLimitWindow { used_percent: 35.0, ... }),
    credits: Some(CreditsSnapshot {
        has_credits: false,  // 关键：设置为 false
        unlimited: false,
        balance: Some("80".to_string()),  // 有余额但不显示
    }),
    ...
};
let now = captured_at + ChronoDuration::minutes(20);  // 20分钟后，超过15分钟阈值
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `tui/src/status/tests.rs:898-965` | 测试用例定义 |
| `tui/src/status/rate_limits.rs:158-278` | `compose_rate_limit_data_many` - 构建速率限制显示数据 |
| `tui/src/status/rate_limits.rs:305-321` | `credit_status_row` - credits 行构建逻辑 |
| `tui/src/status/card.rs:306-334` | `rate_limit_lines` - 渲染速率限制行（含过时警告） |
| `tui/src/status/card.rs:337-388` | `rate_limit_row_lines` - 渲染进度条和重置时间 |

## 依赖与外部交互

### 依赖模块
- `codex_protocol::protocol::{RateLimitSnapshot, RateLimitWindow, CreditsSnapshot}` - 协议数据结构
- `chrono::Duration` - 时间计算
- `ratatui` - TUI 渲染
- `insta` - 快照测试框架

### 相关配置
- `RATE_LIMIT_STALE_THRESHOLD_MINUTES = 15` - 过时阈值常量

## 风险、边界与改进建议

### 当前风险
1. **硬编码阈值**: 15 分钟的过时阈值是硬编码的，无法根据用户需求调整
2. **时区处理**: 重置时间显示依赖本地时区转换，可能存在夏令时问题

### 边界情况
1. **刚好 15 分钟**: 在刚好 15 分钟边界时，过时状态可能不稳定
2. **余额为 0**: 当 `has_credits=true` 但余额为 0 时，credits 行被隐藏（见 `format_credit_balance`）

### 改进建议
1. **可配置阈值**: 允许通过配置或环境变量调整过时阈值
2. **更精确的时间显示**: 考虑显示相对时间（如 "5 minutes ago"）而非绝对时间
3. **Credits 显示优化**: 当前 `has_credits=false` 时完全隐藏，可考虑显示 "Credits: N/A" 以明确状态

### 测试覆盖
此快照测试覆盖了以下场景：
- ✅ 过时数据检测和警告显示
- ✅ `has_credits=false` 时隐藏 credits
- ✅ 多窗口限制显示（5h + Weekly）
- ✅ 进度条渲染（40% 和 65% 剩余）
