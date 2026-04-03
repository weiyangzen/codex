# 研究文档: status_snapshot_shows_empty_limits_message.snap

## 场景与职责

此快照文件是 `codex-tui` crate 中状态显示功能的 insta 快照测试结果，测试用例为 `status_snapshot_shows_empty_limits_message`。该测试验证当速率限制快照存在但所有窗口数据都为空时，状态显示能正确处理并显示适当的提示信息。

## 功能点目的

### 测试目标
验证以下场景的状态显示行为：
1. **空限制快照**: `RateLimitSnapshot` 存在但 `primary` 和 `secondary` 都为 `None`
2. **无 Credits 数据**: `credits` 字段为 `None`
3. **默认提示**: 显示 "Limits: data not available yet"

### 业务逻辑
- 即使后端返回了限制快照，也可能不包含实际的窗口数据
- 用户需要明确知道限制数据不可用，而非完全缺失
- 这与完全没有限制快照的情况（Missing）在显示上相同

## 具体技术实现

### 关键数据结构

```rust
pub struct RateLimitSnapshot {
    pub limit_id: None,
    pub limit_name: None,
    pub primary: None,      // 无主要窗口
    pub secondary: None,    // 无次要窗口
    pub credits: None,      // 无 credits
    pub plan_type: None,
}
```

### 关键流程

1. **空快照处理** (`rate_limits.rs:271-277`):
```rust
pub(crate) fn compose_rate_limit_data_many(
    snapshots: &[RateLimitSnapshotDisplay],
    now: DateTime<Local>,
) -> StatusRateLimitData {
    // ... 处理每个 snapshot ...
    
    if rows.is_empty() {
        StatusRateLimitData::Available(vec![])  // 空但 Available
    } else if stale {
        StatusRateLimitData::Stale(rows)
    } else {
        StatusRateLimitData::Available(rows)
    }
}
```

2. **空 Available 渲染** (`card.rs:312-320`):
```rust
fn rate_limit_lines(&self, ...) -> Vec<Line<'static>> {
    match &self.rate_limits {
        StatusRateLimitData::Available(rows_data) => {
            if rows_data.is_empty() {
                // 空 Available 状态显示默认提示
                return vec![
                    formatter.line("Limits", vec![Span::from("data not available yet").dim()]),
                ];
            }
            self.rate_limit_row_lines(rows_data, available_inner_width, formatter)
        }
        // ...
    }
}
```

3. **与 Missing 状态对比** (`card.rs:330-333`):
```rust
StatusRateLimitData::Missing => {
    // Missing 状态也显示相同的提示
    vec![formatter.line("Limits", vec![Span::from("data not available yet").dim()])]
}
```

4. **测试数据设置** (`tests.rs:775-830`):
```rust
let snapshot = RateLimitSnapshot {
    limit_id: None,
    limit_name: None,
    primary: None,      // 空
    secondary: None,    // 空
    credits: None,      // 空
    plan_type: None,
};
let rate_display = rate_limit_snapshot_display(&snapshot, captured_at);

let composite = new_status_output(
    &config,
    &auth_manager,
    Some(&token_info),
    &usage,
    &None,
    None,
    None,
    Some(&rate_display),  // 提供了 rate_display，但内容为空
    None,
    captured_at,
    &model_slug,
    None,
    None,
);
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `tui/src/status/tests.rs:775-830` | 测试用例定义 |
| `tui/src/status/rate_limits.rs:271-277` | 空 rows 处理 |
| `tui/src/status/card.rs:312-320` | Available 空状态渲染 |
| `tui/src/status/card.rs:330-333` | Missing 状态渲染 |

## 依赖与外部交互

### 依赖模块
- `codex_protocol::protocol::RateLimitSnapshot` - 限制快照结构

### 状态枚举
```rust
pub(crate) enum StatusRateLimitData {
    Available(Vec<StatusRateLimitRow>),  // 空 Vec 表示快照存在但无数据
    Stale(Vec<StatusRateLimitRow>),
    Missing,                              // 完全无快照
}
```

## 风险、边界与改进建议

### 当前风险
1. **状态混淆**: `Available([])` 和 `Missing` 显示相同，用户无法区分
2. **诊断困难**: 如果后端返回空数据，用户无法知道是网络问题还是账户问题

### 边界情况
1. **部分空**: 如果只有 `primary` 或只有 `secondary`，显示会不同
2. **Credits 但无窗口**: 如果只有 `credits` 有数据，会显示 credits 但不显示窗口
3. **空与非空混合**: 多限制组时，部分空、部分有数据的情况

### 改进建议
1. **区分显示**: 
   - `Available([])`: "Limits: data not available yet"
   - `Missing`: "Limits: waiting for server response..."
2. **重试提示**: 对于 Missing 状态，提示用户如何刷新
3. **调试信息**: 在详细模式下显示原始快照数据
4. **加载状态**: 添加加载动画或进度指示器

### 测试覆盖
此快照测试覆盖了以下场景：
- ✅ 空限制快照（primary=None, secondary=None）
- ✅ 无 credits 数据
- ✅ 默认提示显示

### 与 Missing 状态的区别
| 场景 | 状态 | 显示 |
|------|------|------|
| 后端返回空快照 | `Available([])` | "Limits: data not available yet" |
| 后端未返回快照 | `Missing` | "Limits: data not available yet" |
| 有数据但过时 | `Stale(rows)` | 数据 + 警告 |
| 有数据且新鲜 | `Available(rows)` | 数据 |

### 相关测试
- `status_snapshot_shows_missing_limits_message` - 测试 Missing 状态
- `status_snapshot_shows_stale_limits_message` - 测试 Stale 状态
