# 研究文档：status_snapshot_shows_missing_limits_message.snap

## 场景与职责

此快照文件验证 Codex TUI 状态显示模块在速率限制数据完全缺失（missing）时的降级显示行为。当系统尚未获取任何速率限制快照时（如初始启动或网络故障后），状态卡片需要优雅地处理这种情况。

该测试对应 `codex-rs/tui/src/status/tests.rs` 中的 `status_snapshot_shows_missing_limits_message` 测试函数，验证缺失限制数据的处理逻辑。

## 功能点目的

### 核心功能
1. **缺失数据检测**：识别当 `rate_limits` 参数为 `None` 的情况
2. **一致降级显示**：与空数据情况相同，显示 "data not available yet"
3. **无崩溃渲染**：确保即使缺少可选数据，状态卡片也能完整渲染

### 业务逻辑
- 缺失数据通过 `StatusRateLimitData::Missing` 枚举变体表示
- 与 `Available(vec![])` 不同，这表示从未接收到任何快照数据
- 渲染逻辑将 `Missing` 和空 `Available` 统一处理为相同的用户消息

## 具体技术实现

### 关键数据结构

```rust
// rate_limits.rs:47-55
pub(crate) enum StatusRateLimitData {
    Available(Vec<StatusRateLimitRow>),  // 有快照数据
    Stale(Vec<StatusRateLimitRow>),      // 有快照但已过期
    Missing,                              // 无快照数据
}
```

### 缺失数据生成逻辑

```rust
// rate_limits.rs:158-166
pub(crate) fn compose_rate_limit_data(
    snapshot: Option<&RateLimitSnapshotDisplay>,
    now: DateTime<Local>,
) -> StatusRateLimitData {
    match snapshot {
        Some(snapshot) => compose_rate_limit_data_many(std::slice::from_ref(snapshot), now),
        None => StatusRateLimitData::Missing,  // 关键：None -> Missing
    }
}

// rate_limits.rs:168-174
pub(crate) fn compose_rate_limit_data_many(
    snapshots: &[RateLimitSnapshotDisplay],
    now: DateTime<Local>,
) -> StatusRateLimitData {
    if snapshots.is_empty() {
        return StatusRateLimitData::Missing;  // 空数组也视为 Missing
    }
    // ...
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
                vec![formatter.line("Limits", vec![Span::from("data not available yet").dim()])]
            } else {
                self.rate_limit_row_lines(rows_data, available_inner_width, formatter)
            }
        }
        StatusRateLimitData::Stale(rows_data) => { /* ... */ }
        StatusRateLimitData::Missing => {
            // 缺失数据：显示相同的降级消息
            vec![formatter.line("Limits", vec![Span::from("data not available yet").dim()])]
        }
    }
}
```

### 测试用例构造

```rust
// tests.rs:658-704
let composite = new_status_output(
    &config,
    &auth_manager,
    Some(&token_info),
    &usage,
    &None,
    None,
    None,
    None,  // 关键：rate_limits 为 None
    None,
    now,
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
1. **与空数据相同显示**："data not available yet"
2. **Limits 标签存在**：即使没有数据也显示标签
3. **暗淡样式**：使用 `.dim()` 表示信息不可用
4. **其他信息完整**：Token usage、Context window 等正常显示

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|-----|------|
| `codex-rs/tui/src/status/tests.rs` | 测试定义，第 658-704 行 |
| `codex-rs/tui/src/status/card.rs` | 缺失数据处理，第 331-333 行 |
| `codex-rs/tui/src/status/rate_limits.rs` | 数据状态生成，第 158-166 行 |

### 渲染调用链

```
new_status_output
  └── StatusHistoryCell::new (card.rs:152)
      └── compose_rate_limit_data (rate_limits.rs:158)
          └── 传入 None -> 返回 StatusRateLimitData::Missing
  └── StatusHistoryCell::display_lines (card.rs:413)
      └── rate_limit_lines (card.rs:538)
          └── 匹配 StatusRateLimitData::Missing
              └── 返回降级消息行
```

### 与 Empty 状态的区别

虽然 `Missing` 和 `Available(vec![])` 显示相同的消息，但它们的语义不同：

| 状态 | 触发条件 | 语义 |
|-----|---------|------|
| `Missing` | `rate_limits: None` | 从未获取过数据 |
| `Available(vec![])` | 有快照但所有字段为 None | 获取了数据但内容为空 |

### 标签收集逻辑

```rust
// card.rs:390-409
fn collect_rate_limit_labels(&self, seen: &mut BTreeSet<String>, labels: &mut Vec<String>) {
    match &self.rate_limits {
        StatusRateLimitData::Available(rows) => {
            if rows.is_empty() {
                push_label(labels, seen, "Limits");  // 空数据也添加标签
            } else {
                for row in rows { push_label(labels, seen, row.label.as_str()); }
            }
        }
        StatusRateLimitData::Stale(rows) => { /* ... */ }
        StatusRateLimitData::Missing => push_label(labels, seen, "Limits"),  // 缺失也添加标签
    }
}
```

## 依赖与外部交互

### 外部 crate

| crate | 用途 |
|-------|------|
| `ratatui` | 终端渲染，`.dim()` 样式 |
| `insta` | 快照测试 |

### 内部模块

```rust
use crate::status::card::new_status_output;
use crate::status::rate_limits::compose_rate_limit_data;
```

## 风险、边界与改进建议

### 当前风险

1. **状态不可区分**：用户无法区分"从未获取"和"获取了但为空"
2. **无加载指示**：没有视觉反馈表明系统正在尝试获取数据
3. **无错误详情**：网络错误、权限错误等都显示相同消息

### 边界情况

1. **首次启动**：应用启动后首次显示状态，数据通常缺失
2. **网络断开**：网络故障后，已有数据可能变为陈旧，但新启动时缺失
3. **权限不足**：某些账户类型可能永远无法获取限制数据

### 改进建议

1. **状态细分**：
   ```rust
   pub(crate) enum StatusRateLimitData {
       Initial,      // 从未尝试获取
       Loading,      // 正在获取
       Available(Vec<StatusRateLimitRow>),
       Stale(Vec<StatusRateLimitRow>),
       Error(String), // 带错误信息
   }
   ```

2. **不同消息**：
   - `Initial`: "Limits will appear after first request"
   - `Loading`: "Fetching limits..."
   - `Error`: "Unable to fetch limits: [error details]"

3. **自动刷新**：
   - 在 `Missing` 状态下自动尝试获取数据
   - 添加刷新按钮或 `/refresh` 命令

4. **诊断模式**：
   - 环境变量 `CODEX_DEBUG=1` 时显示详细状态
   - 显示最后尝试时间、错误代码等

5. **测试扩展**：
   - 测试从 `Missing` 到 `Available` 的状态转换
   - 测试网络错误后的恢复
   - 测试权限不足的场景

6. **用户体验**：
   - 在消息旁添加帮助图标或链接
   - 提供手动刷新按钮
   - 显示上次成功获取的时间（如果有）
