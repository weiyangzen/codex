# 研究文档：status_snapshot_shows_empty_limits_message.snap

## 场景与职责

此快照文件验证 Codex TUI 状态显示模块在速率限制数据完全为空（empty）时的降级显示行为。当服务器返回的 `RateLimitSnapshot` 包含空的主/次窗口且没有积分信息时，系统需要优雅地显示 "data not available yet" 消息。

该测试对应 `codex-rs/tui/src/status/tests.rs` 中的 `status_snapshot_shows_empty_limits_message` 测试函数，验证空限制数据的处理逻辑。

## 功能点目的

### 核心功能
1. **空数据检测**：识别所有限制窗口都为 `None` 且没有积分信息的快照
2. **降级消息显示**：显示用户友好的 "data not available yet" 消息
3. **视觉一致性**：保持与其他状态行相同的缩进和对齐格式

### 业务逻辑
- 空数据通过 `StatusRateLimitData::Available(vec![])` 表示
- 渲染时检查行向量是否为空，如果是则显示降级消息
- 消息使用暗淡（dim）样式，表示信息不可用

## 具体技术实现

### 关键数据结构

```rust
// rate_limits.rs:47-55
pub(crate) enum StatusRateLimitData {
    Available(Vec<StatusRateLimitRow>),  // 数据可用（可能为空向量）
    Stale(Vec<StatusRateLimitRow>),      // 数据陈旧
    Missing,                              // 数据缺失（无快照）
}
```

### 空数据生成逻辑

```rust
// rate_limits.rs:271-278
if rows.is_empty() {
    StatusRateLimitData::Available(vec![])  // 空但可用
} else if stale {
    StatusRateLimitData::Stale(rows)
} else {
    StatusRateLimitData::Available(rows)
}
```

### 渲染降级逻辑

```rust
// card.rs:307-335
fn rate_limit_lines(
    &self,
    available_inner_width: usize,
    formatter: &FieldFormatter,
) -> Vec<Line<'static>> {
    match &self.rate_limits {
        StatusRateLimitData::Available(rows_data) => {
            if rows_data.is_empty() {
                // 空数据：显示降级消息
                return vec![
                    formatter.line("Limits", vec![Span::from("data not available yet").dim()]),
                ];
            }
            self.rate_limit_row_lines(rows_data, available_inner_width, formatter)
        }
        StatusRateLimitData::Stale(rows_data) => { /* ... */ }
        StatusRateLimitData::Missing => {
            // 缺失数据：同样显示降级消息
            vec![formatter.line("Limits", vec![Span::from("data not available yet").dim()])]
        }
    }
}
```

### 测试用例构造

```rust
// tests.rs:775-830
let snapshot = RateLimitSnapshot {
    limit_id: None,
    limit_name: None,
    primary: None,      // 无主窗口
    secondary: None,    // 无次窗口
    credits: None,      // 无积分
    plan_type: None,
};
let captured_at = chrono::Local
    .with_ymd_and_hms(2024, 6, 7, 8, 9, 10)
    .single()
    .expect("timestamp");
let rate_display = rate_limit_snapshot_display(&snapshot, captured_at);

let composite = new_status_output(
    &config,
    &auth_manager,
    Some(&token_info),
    &usage,
    &None,
    None,
    None,
    Some(&rate_display),  // 传入空快照
    None,
    captured_at,
    &model_slug,
    None,
    None,
);
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
│  Token usage:      750 total  (500 input + 250 output)                │
│  Context window:   100% left (750 used / 272K)                        │
│  Limits:           data not available yet                             │
╰───────────────────────────────────────────────────────────────────────╯
```

关键验证点：
1. **Limits 行存在**：即使没有数据，也显示 Limits 标签
2. **降级消息**：显示 "data not available yet" 而非空白
3. **视觉样式**：消息使用暗淡样式（`.dim()`）
4. **无进度条**：不显示空的进度条或 0% 指示

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|-----|------|
| `codex-rs/tui/src/status/tests.rs` | 测试定义，第 775-830 行 |
| `codex-rs/tui/src/status/card.rs` | 空数据处理，第 314-317 行 |
| `codex-rs/tui/src/status/rate_limits.rs` | 数据状态生成，第 271-272 行 |

### 渲染调用链

```
new_status_output
  └── StatusHistoryCell::new
      └── compose_rate_limit_data (rate_limits.rs:158)
          └── 传入 Some(snapshot) -> compose_rate_limit_data_many
              ├── 遍历 snapshots（此处只有一个）
              ├── 无 primary、secondary、credits 窗口，rows 保持为空
              └── 返回 StatusRateLimitData::Available(vec![])
  └── StatusHistoryCell::display_lines (card.rs:413)
      └── rate_limit_lines (card.rs:538)
          └── 匹配 StatusRateLimitData::Available(rows)
              └── rows.is_empty() -> true
                  └── 返回降级消息行
```

### 与 Missing 状态的区别

| 状态 | 触发条件 | 显示结果 |
|-----|---------|---------|
| `Available(vec![])` | 有快照但所有窗口为 None | "data not available yet" |
| `Missing` | 无快照（`rate_limits: None`） | "data not available yet" |

虽然显示结果相同，但内部状态不同：
- `Available(vec![])`：服务器响应了，但数据为空
- `Missing`：尚未收到服务器响应

## 依赖与外部交互

### 外部 crate

| crate | 用途 |
|-------|------|
| `ratatui` | 终端渲染，`.dim()` 样式 |
| `insta` | 快照测试 |

### 内部模块

```rust
use crate::status::rate_limits::{rate_limit_snapshot_display, compose_rate_limit_data};
use codex_protocol::protocol::{RateLimitSnapshot, RateLimitWindow};
```

## 风险、边界与改进建议

### 当前风险

1. **状态混淆**：`Available(vec![])` 和 `Missing` 显示相同消息，用户无法区分"服务器返回空"和"尚未获取"
2. **硬编码消息**："data not available yet" 是硬编码字符串，不支持本地化
3. **无加载状态**：没有区分"正在加载"和"加载完成但为空"

### 边界情况

1. **部分空数据**：如果只有 `primary` 为 None 但 `secondary` 有数据，会显示次要窗口而不会触发空消息
2. **零值窗口**：`used_percent: 0.0` 不等于 `None`，会显示 100% 剩余
3. **积分但无窗口**：`credits: Some(...)` 但窗口为 None 时，会显示积分行

### 改进建议

1. **区分空状态和缺失状态**：
   ```rust
   StatusRateLimitData::Empty => {
       vec![formatter.line("Limits", vec![
           Span::from("waiting for server...").dim()
       ])]
   }
   StatusRateLimitData::Missing => {
       vec![formatter.line("Limits", vec![
           Span::from("start a conversation to see limits").dim()
       ])]
   }
   ```

2. **添加加载状态**：
   ```rust
   pub(crate) enum StatusRateLimitData {
       Loading,  // 新状态
       Available(Vec<StatusRateLimitRow>),
       Stale(Vec<StatusRateLimitRow>),
       Missing,
   }
   ```

3. **重试提示**：
   - 在空数据状态下添加提示："Try running /status again in a few seconds"
   - 添加自动刷新机制

4. **诊断信息**：
   - 在调试模式下显示原始快照数据
   - 添加错误代码或状态码

5. **测试扩展**：
   - 测试部分空数据（仅 primary 为 None）
   - 测试空数据后接收到有效数据的过渡
   - 测试网络错误后的降级显示
