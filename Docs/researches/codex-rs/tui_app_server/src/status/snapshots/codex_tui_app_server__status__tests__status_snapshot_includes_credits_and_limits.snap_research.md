# 研究文档: codex_tui_app_server__status__tests__status_snapshot_includes_credits_and_limits.snap

## 场景与职责

此快照文件是 `codex-tui-app-server` crate 中状态显示功能的 insta 快照测试结果，测试用例为 `status_snapshot_includes_credits_and_limits`。该测试验证当用户账户同时具有速率限制和 credits 余额时，状态显示能正确展示所有相关信息。

## 功能点目的

### 测试目标
验证以下信息的完整显示：
1. **双窗口速率限制**: 5 小时限制（55% 剩余）和每周限制（70% 剩余）
2. **Credits 余额**: 显示格式化后的 credits 数量（37.5 → 38 credits）
3. **Token 使用统计**: 显示输入/输出 token 数量和总量

### 与 tui crate 的区别
- 使用 `StatusAccountDisplay` 替代 `AuthManager` 进行账户信息显示
- 其他显示逻辑与 tui crate 保持一致

## 具体技术实现

### 关键数据结构

```rust
pub struct RateLimitSnapshot {
    pub primary: Option<RateLimitWindow>,
    pub secondary: Option<RateLimitWindow>,
    pub credits: Option<CreditsSnapshot>,
}

pub struct RateLimitWindow {
    pub used_percent: f64,          // 45.0% 已使用 = 55% 剩余
    pub window_minutes: Option<i64>,
    pub resets_at: Option<i64>,
}
```

### 关键流程

1. **Credits 格式化** (`rate_limits.rs:323-343`):
```rust
fn format_credit_balance(raw: &str) -> Option<String> {
    if let Ok(value) = trimmed.parse::<f64>()
        && value > 0.0
    {
        let rounded = value.round() as i64;  // 37.5 -> 38
        return Some(rounded.to_string());
    }
    None
}
```

2. **进度条渲染** (`rate_limits.rs:284-294`):
```rust
pub(crate) fn render_status_limit_progress_bar(percent_remaining: f64) -> String {
    let ratio = (percent_remaining / 100.0).clamp(0.0, 1.0);
    let filled = (ratio * 20.0).round() as usize;  // 20 段进度条
    format!("[{}{}]", "█".repeat(filled), "░".repeat(20 - filled))
}
```

3. **测试数据** (`tests.rs:702-769`):
```rust
let snapshot = RateLimitSnapshot {
    primary: Some(RateLimitWindow {
        used_percent: 45.0,        // 55% 剩余
        window_minutes: Some(300), // 5小时
        resets_at: Some(reset_at_from(&captured_at, 900)),
    }),
    secondary: Some(RateLimitWindow {
        used_percent: 30.0,        // 70% 剩余
        window_minutes: Some(10_080), // 每周
        resets_at: Some(reset_at_from(&captured_at, 2_700)),
    }),
    credits: Some(CreditsSnapshot {
        has_credits: true,
        unlimited: false,
        balance: Some("37.5".to_string()), // 显示为 "38 credits"
    }),
    ...
};
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `tui_app_server/src/status/tests.rs:702-769` | 测试用例定义 |
| `tui_app_server/src/status/rate_limits.rs` | 速率限制和 credits 显示逻辑 |
| `tui_app_server/src/status/card.rs` | 状态卡片渲染 |

## 依赖与外部交互

### 显示格式
- **Token 数量**: 使用 `format_tokens_compact` 格式化为 K/M 单位
- **Credits**: 小数四舍五入为整数
- **进度条**: 20 段 Unicode 块字符

## 风险、边界与改进建议

### 当前风险
1. **Credits 精度丢失**: 余额四舍五入可能导致用户困惑
2. **代码重复**: 与 tui crate 有大量重复逻辑

### 改进建议
1. **代码共享**: 将共同逻辑提取到共享模块
2. **精度保留**: 考虑显示原始余额或保留 1 位小数

### 测试覆盖
- ✅ 双窗口速率限制显示
- ✅ Credits 余额显示（含小数四舍五入）
- ✅ Token 使用统计
