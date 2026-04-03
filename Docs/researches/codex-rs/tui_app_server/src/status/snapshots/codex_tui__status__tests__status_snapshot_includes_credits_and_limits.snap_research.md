# 研究文档: status_snapshot_includes_credits_and_limits.snap

## 场景与职责

此快照文件是 `codex-tui` crate 中状态显示功能的 insta 快照测试结果，测试用例为 `status_snapshot_includes_credits_and_limits`。该测试验证当用户账户同时具有速率限制和 credits 余额时，状态显示能正确展示所有相关信息。

## 功能点目的

### 测试目标
验证以下信息的完整显示：
1. **双窗口速率限制**: 同时显示 5 小时限制和每周限制
2. **Credits 余额**: 显示格式化后的 credits 数量（向上取整）
3. **Token 使用统计**: 显示输入/输出 token 数量和总量
4. **上下文窗口**: 显示上下文窗口使用百分比

### 业务逻辑
- 用户需要全面了解其账户状态，包括速率限制和 credits 余额
- Credits 显示需要格式化（小数向上取整为整数）
- 速率限制以可视化进度条形式展示

## 具体技术实现

### 关键数据结构

```rust
pub struct RateLimitSnapshot {
    pub primary: Option<RateLimitWindow>,      // 5小时窗口
    pub secondary: Option<RateLimitWindow>,    // 每周窗口
    pub credits: Option<CreditsSnapshot>,
}

pub struct RateLimitWindow {
    pub used_percent: f64,          // 已使用百分比
    pub window_minutes: Option<i64>, // 窗口时长（分钟）
    pub resets_at: Option<i64>,     // 重置时间戳
}

pub struct CreditsSnapshot {
    pub has_credits: bool,
    pub unlimited: bool,
    pub balance: Option<String>,    // 原始余额字符串
}
```

### 关键流程

1. **Credits 格式化** (`rate_limits.rs:323-343`):
```rust
fn format_credit_balance(raw: &str) -> Option<String> {
    let trimmed = raw.trim();
    
    if let Ok(int_value) = trimmed.parse::<i64>()
        && int_value > 0
    {
        return Some(int_value.to_string());
    }

    if let Ok(value) = trimmed.parse::<f64>()
        && value > 0.0
    {
        let rounded = value.round() as i64;  // 四舍五入
        return Some(rounded.to_string());
    }
    None
}
```

2. **进度条渲染** (`rate_limits.rs:284-294`):
```rust
pub(crate) fn render_status_limit_progress_bar(percent_remaining: f64) -> String {
    let ratio = (percent_remaining / 100.0).clamp(0.0, 1.0);
    let filled = (ratio * STATUS_LIMIT_BAR_SEGMENTS as f64).round() as usize;
    let filled = filled.min(STATUS_LIMIT_BAR_SEGMENTS);  // 20 段
    let empty = STATUS_LIMIT_BAR_SEGMENTS.saturating_sub(filled);
    format!("[{}{}]", 
        STATUS_LIMIT_BAR_FILLED.repeat(filled),   // "█"
        STATUS_LIMIT_BAR_EMPTY.repeat(empty)      // "░"
    )
}
```

3. **测试数据设置** (`tests.rs:706-773`):
```rust
let usage = TokenUsage {
    input_tokens: 1_500,
    cached_input_tokens: 100,
    output_tokens: 600,
    total_tokens: 2_200,
};

let snapshot = RateLimitSnapshot {
    primary: Some(RateLimitWindow {
        used_percent: 45.0,        // 55% 剩余
        window_minutes: Some(300), // 5小时
        resets_at: Some(...),
    }),
    secondary: Some(RateLimitWindow {
        used_percent: 30.0,        // 70% 剩余
        window_minutes: Some(10_080), // 每周
        resets_at: Some(...),
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
| `tui/src/status/tests.rs:706-773` | 测试用例定义 |
| `tui/src/status/rate_limits.rs:124-142` | `rate_limit_snapshot_display_for_limit` - 快照转显示结构 |
| `tui/src/status/rate_limits.rs:264-268` | credits 行添加到 rows |
| `tui/src/status/rate_limits.rs:305-321` | `credit_status_row` - credits 行构建 |
| `tui/src/status/rate_limits.rs:323-343` | `format_credit_balance` - 余额格式化 |
| `tui/src/status/card.rs:273-289` | `token_usage_spans` - Token 使用显示 |
| `tui/src/status/card.rs:291-305` | `context_window_spans` - 上下文窗口显示 |

## 依赖与外部交互

### 依赖模块
- `codex_core::test_support` - 测试辅助函数（模型信息构建）
- `codex_protocol::protocol::TokenUsage` - Token 使用统计
- `chrono::TimeZone` - 时间处理

### 显示格式
- **Token 数量**: 使用 `format_tokens_compact` 格式化为 K/M 单位（如 "1.4K"）
- **Credits**: 小数四舍五入为整数（37.5 → 38）
- **进度条**: 20 段 Unicode 块字符（█/░）

## 风险、边界与改进建议

### 当前风险
1. **Credits 精度丢失**: 余额四舍五入可能导致用户困惑（37.5 显示为 38）
2. **进度条精度**: 20 段进度条在数值较小时精度有限

### 边界情况
1. **余额为 0**: 当 balance 为 "0" 时，credits 行完全隐藏
2. **无限 Credits**: `unlimited=true` 时显示 "Credits: Unlimited"
3. **单窗口限制**: 如果只有 primary 或 secondary，显示会相应调整

### 改进建议
1. **Credits 精度**: 考虑保留 1 位小数或显示原始值
2. **颜色编码**: 对低剩余百分比使用颜色警告（如 <20% 显示红色）
3. **交互式提示**: 考虑添加刷新按钮或自动刷新机制

### 测试覆盖
此快照测试覆盖了以下场景：
- ✅ 双窗口速率限制显示（5h + Weekly）
- ✅ Credits 余额显示（含小数四舍五入）
- ✅ Token 使用统计（含 cached tokens 排除）
- ✅ 上下文窗口百分比
- ✅ 重置时间显示
