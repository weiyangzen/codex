# 研究文档：status_snapshot_includes_credits_and_limits.snap

## 场景与职责

此快照文件验证 Codex TUI 状态显示模块在同时存在速率限制和积分信息时的正确渲染行为。这是 `/status` 命令输出格式的核心测试用例，展示了完整的账户状态信息展示。

该测试对应 `codex-rs/tui/src/status/tests.rs` 中的 `status_snapshot_includes_credits_and_limits` 测试函数，确保当用户有积分余额且存在速率限制窗口时，所有信息都能正确格式化显示。

## 功能点目的

### 核心功能
1. **综合信息显示**：同时展示速率限制（5小时和每周）和积分余额
2. **积分格式化**：将字符串余额（如 "37.5"）格式化为整数积分显示（"38 credits"）
3. **多窗口进度条**：为不同的速率限制窗口渲染独立的进度条

### 业务逻辑
- 积分余额通过 `CreditsSnapshot` 传递，支持字符串格式以处理小数
- 速率限制通过 `RateLimitSnapshot` 的主/次窗口结构传递
- 显示格式遵循 "字段名: 值" 的左对齐布局，使用 `FieldFormatter` 处理

## 具体技术实现

### 关键数据结构

```rust
// 协议层积分快照
pub struct CreditsSnapshot {
    pub has_credits: bool,      // true 表示启用积分追踪
    pub unlimited: bool,        // false 表示有限积分
    pub balance: Option<String>, // "37.5" - 支持小数字符串
}

// 显示层积分快照
pub(crate) struct CreditsSnapshotDisplay {
    pub has_credits: bool,
    pub unlimited: bool,
    pub balance: Option<String>,
}
```

### 积分余额格式化

```rust
// rate_limits.rs:323-343
fn format_credit_balance(raw: &str) -> Option<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }

    // 尝试解析为整数
    if let Ok(int_value) = trimmed.parse::<i64>()
        && int_value > 0
    {
        return Some(int_value.to_string());
    }

    // 尝试解析为浮点数并四舍五入
    if let Ok(value) = trimmed.parse::<f64>()
        && value > 0.0
    {
        let rounded = value.round() as i64;
        return Some(rounded.to_string());
    }

    None
}
```

### 积分行生成

```rust
// rate_limits.rs:305-321
fn credit_status_row(credits: &CreditsSnapshotDisplay) -> Option<StatusRateLimitRow> {
    if !credits.has_credits {
        return None;
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
```

### 测试用例构造

```rust
// tests.rs:707-773
let snapshot = RateLimitSnapshot {
    limit_id: None,
    limit_name: None,
    primary: Some(RateLimitWindow {
        used_percent: 45.0,  // 45% 已使用 = 55% 剩余
        window_minutes: Some(300),
        resets_at: Some(reset_at_from(&captured_at, 900)),
    }),
    secondary: Some(RateLimitWindow {
        used_percent: 30.0,  // 30% 已使用 = 70% 剩余
        window_minutes: Some(10_080),
        resets_at: Some(reset_at_from(&captured_at, 2_700)),
    }),
    credits: Some(CreditsSnapshot {
        has_credits: true,
        unlimited: false,
        balance: Some("37.5".to_string()), // 将显示为 "38 credits"
    }),
    plan_type: None,
};
```

### 渲染输出分析

```
╭───────────────────────────────────────────────────────────────────╮
│  >_ OpenAI Codex (v0.0.0)                                         │
│                                                                   │
│ Visit https://chatgpt.com/codex/settings/usage for up-to-date     │
│ information on rate limits and credits                            │
│                                                                   │
│  Model:            gpt-5.1-codex (reasoning none, summaries auto) │
│  Directory: [[workspace]]                                         │
│  Permissions:      Custom (read-only, on-request)                 │
│  Agents.md:        <none>                                         │
│                                                                   │
│  Token usage:      2K total  (1.4K input + 600 output)            │
│  Context window:   100% left (2.2K used / 272K)                   │
│  5h limit:         [███████████░░░░░░░░░] 55% left (resets 09:25) │
│  Weekly limit:     [██████████████░░░░░░] 70% left (resets 09:55) │
│  Credits:          38 credits                                     │
╰───────────────────────────────────────────────────────────────────╯
```

关键验证点：
1. **积分四舍五入**：输入 "37.5" 显示为 "38 credits"
2. **进度条计算**：
   - 5小时：45% 已使用 → 55% 剩余 → 11 个填充块（20×0.55≈11）
   - 每周：30% 已使用 → 70% 剩余 → 14 个填充块（20×0.70≈14）
3. **无陈旧警告**：数据新鲜，不显示警告

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|-----|------|
| `codex-rs/tui/src/status/tests.rs` | 测试定义，第 707-773 行 |
| `codex-rs/tui/src/status/rate_limits.rs` | 积分和速率限制格式化，第 305-343 行 |
| `codex-rs/tui/src/status/card.rs` | 状态卡片渲染，第 538 行调用 `rate_limit_lines` |
| `codex-rs/tui/src/status/format.rs` | 字段格式化，`FieldFormatter` 处理标签对齐 |

### 渲染调用链

```
StatusHistoryCell::display_lines (card.rs:413)
  ├── 构建基础信息行（Model, Directory, Permissions 等）
  ├── 添加 Token usage 行
  ├── 添加 Context window 行
  └── rate_limit_lines (card.rs:538)
      └── 处理 StatusRateLimitData::Available
          ├── 5h limit 行（主窗口）
          ├── Weekly limit 行（次窗口）
          └── Credits 行（通过 credit_status_row 生成）
```

### 进度条渲染

```rust
// rate_limits.rs:284-294
pub(crate) fn render_status_limit_progress_bar(percent_remaining: f64) -> String {
    let ratio = (percent_remaining / 100.0).clamp(0.0, 1.0);
    let filled = (ratio * 20.0).round() as usize;
    let empty = 20_usize.saturating_sub(filled);
    format!("[{}{}]", "█".repeat(filled), "░".repeat(empty))
}
```

## 依赖与外部交互

### 外部 crate

| crate | 用途 |
|-------|------|
| `chrono` | 时间戳处理和本地时区转换 |
| `ratatui` | 终端渲染，Span/Line 构造 |
| `insta` | 快照测试 |
| `pretty_assertions` | 测试断言美化 |

### 内部模块依赖

```rust
use codex_protocol::protocol::{RateLimitSnapshot, RateLimitWindow, CreditsSnapshot};
use crate::status::rate_limits::{rate_limit_snapshot_display, compose_rate_limit_data};
```

## 风险、边界与改进建议

### 当前风险

1. **浮点数精度**：`37.5` 解析为 f64 后四舍五入，极端情况下可能有精度问题
2. **余额格式化硬编码**："credits" 单词是硬编码的，不支持本地化
3. **零值处理**：`format_credit_balance` 对 0 返回 None，导致积分行隐藏，这可能不符合用户预期

### 边界情况

1. **极大余额**：未测试超过 i64 范围的余额字符串
2. **非数字余额**：非数字字符串会被 `parse::<f64>()` 拒绝，返回 None
3. **负余额**：负数会被过滤，不显示积分行

### 改进建议

1. **余额格式化增强**：
   - 支持千分位分隔符（如 "1,000 credits"）
   - 支持大数缩写（如 "1.5K credits"）
   - 添加货币符号支持

2. **错误处理**：
   - 当 `has_credits: true` 但余额解析失败时，显示 "Credits: Unknown" 而非隐藏
   - 添加日志记录解析失败的余额值

3. **测试扩展**：
   - 添加边界值测试：0.1, 0.5, 0.9, 999.9 等
   - 添加无效余额测试："abc", "", "-5"
   - 添加极大值测试："999999999999"

4. **代码重构**：
   - 将积分格式化逻辑提取到独立模块，便于单元测试
   - 使用 `rust_decimal` 替代 f64 进行精确的十进制计算
