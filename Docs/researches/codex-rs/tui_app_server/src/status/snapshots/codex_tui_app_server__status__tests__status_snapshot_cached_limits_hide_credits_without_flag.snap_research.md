# 研究文档: codex_tui_app_server__status__tests__status_snapshot_cached_limits_hide_credits_without_flag.snap

## 场景与职责

此快照文件是 `codex-tui-app-server` crate 中状态显示功能的 insta 快照测试结果，测试用例为 `status_snapshot_cached_limits_hide_credits_without_flag`。该测试验证当速率限制数据被缓存（过时）且 `has_credits` 标志为 false 时，状态显示是否正确隐藏 credits 信息并显示过时警告。

## 功能点目的

### 测试目标
验证以下场景的状态显示行为：
1. **缓存/过时限制数据**: 当速率限制快照的捕获时间与当前时间相差超过 15 分钟时，数据显示为 "stale"
2. **隐藏 Credits**: 当 `CreditsSnapshot.has_credits = false` 时，即使有余额信息也不显示 credits
3. **警告提示**: 在过时数据情况下显示警告行

### 与 tui crate 的区别
`tui_app_server` 版本的 `new_status_output` 函数签名不同：
- 使用 `StatusAccountDisplay` 替代 `AuthManager`
- 参数顺序和类型略有调整
- 核心显示逻辑保持一致

## 具体技术实现

### 关键数据结构

```rust
// 与 tui crate 相同
pub struct RateLimitSnapshot {
    pub primary: Option<RateLimitWindow>,
    pub secondary: Option<RateLimitWindow>,
    pub credits: Option<CreditsSnapshot>,
}

pub struct CreditsSnapshot {
    pub has_credits: bool,  // 控制 credits 显示的关键标志
    pub unlimited: bool,
    pub balance: Option<String>,
}

// tui_app_server 特有
pub(crate) enum StatusAccountDisplay {
    ChatGpt { email: Option<String>, plan: Option<String> },
    ApiKey,
}
```

### 关键流程

1. **函数签名差异** (`card.rs:79-95`):
```rust
// tui_app_server 版本
pub(crate) fn new_status_output(
    config: &Config,
    account_display: Option<&StatusAccountDisplay>,  // 差异：使用 StatusAccountDisplay
    token_info: Option<&TokenUsageInfo>,
    total_usage: &TokenUsage,
    session_id: &Option<ThreadId>,
    thread_name: Option<String>,
    forked_from: Option<ThreadId>,
    rate_limits: Option<&RateLimitSnapshotDisplay>,
    _plan_type: Option<PlanType>,
    now: DateTime<Local>,
    model_name: &str,
    collaboration_mode: Option<&str>,
    reasoning_effort_override: Option<Option<ReasoningEffort>>,
) -> CompositeHistoryCell
```

2. **过时检测** (`rate_limits.rs:179-181`):
```rust
stale |= now.signed_duration_since(snapshot.captured_at)
    > ChronoDuration::minutes(RATE_LIMIT_STALE_THRESHOLD_MINUTES); // 15分钟
```

3. **Credits 行构建** (`rate_limits.rs:305-321`):
```rust
fn credit_status_row(credits: &CreditsSnapshotDisplay) -> Option<StatusRateLimitRow> {
    if !credits.has_credits {
        return None;  // has_credits=false 时隐藏 credits
    }
    // ...
}
```

4. **测试数据** (`tests.rs:894-965`):
```rust
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
let now = captured_at + ChronoDuration::minutes(20);  // 20分钟后，超过阈值
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `tui_app_server/src/status/tests.rs:894-965` | 测试用例定义 |
| `tui_app_server/src/status/card.rs:79-95` | `new_status_output` 函数（tui_app_server 版本） |
| `tui_app_server/src/status/rate_limits.rs` | 速率限制显示逻辑（与 tui 共享） |
| `tui_app_server/src/status/account.rs` | `StatusAccountDisplay` 定义 |

## 依赖与外部交互

### 与 tui crate 的关系
- `tui_app_server` 是 `tui` 的并行实现，用于应用服务器模式
- `rate_limits.rs` 和 `helpers.rs` 等模块代码基本相同
- `card.rs` 的账户处理逻辑有差异（`StatusAccountDisplay` vs `AuthManager`）

### 代码同步约定
根据 `AGENTS.md`：
> When a change lands in `codex-rs/tui` and `codex-rs/tui_app_server` has a parallel implementation of the same behavior, reflect the change in `codex-rs/tui_app_server` too unless there is a documented reason not to.

## 风险、边界与改进建议

### 当前风险
1. **代码重复**: 两个 crate 有大量重复的显示逻辑，维护成本高
2. **同步遗漏**: 修改 tui 时可能忘记同步到 tui_app_server

### 改进建议
1. **代码共享**: 考虑将共同逻辑提取到共享 crate（如 `codex-tui-common`）
2. **自动化同步**: 添加 CI 检查确保两个 crate 的关键文件保持一致
3. **差异文档**: 明确记录两个 crate 的差异点和原因

### 测试覆盖
此快照测试覆盖了以下场景：
- ✅ 过时数据检测和警告显示
- ✅ `has_credits=false` 时隐藏 credits
- ✅ 双窗口限制显示（5h + Weekly）

### 相关测试
- `codex_tui__status__tests__status_snapshot_cached_limits_hide_credits_without_flag.snap` - tui crate 的对应测试
