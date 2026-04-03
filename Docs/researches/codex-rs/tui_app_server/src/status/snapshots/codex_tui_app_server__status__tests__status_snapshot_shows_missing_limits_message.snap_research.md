# 研究文档: codex_tui_app_server__status__tests__status_snapshot_shows_missing_limits_message.snap

## 场景与职责

此快照文件是 `codex-tui-app-server` crate 中状态显示功能的 insta 快照测试结果，测试用例为 `status_snapshot_shows_missing_limits_message`。该测试验证当速率限制快照完全缺失时，状态显示能正确处理。

## 功能点目的

### 测试目标
验证以下场景的状态显示行为：
1. **完全缺失限制数据**: 不传递任何 `RateLimitSnapshotDisplay`
2. **Missing 状态**: `StatusRateLimitData::Missing`
3. **默认提示**: "Limits: data not available yet"

### Missing vs Empty
| 状态 | 含义 | 触发条件 |
|------|------|----------|
| Missing | 从未获取过数据 | `rate_limits: None` |
| Available([]) | 获取了空数据 | `RateLimitSnapshot` 所有字段为 None |

## 具体技术实现

### 关键流程

1. **缺失数据处理** (`rate_limits.rs:158-166`):
```rust
pub(crate) fn compose_rate_limit_data(
    snapshot: Option<&RateLimitSnapshotDisplay>,
    now: DateTime<Local>,
) -> StatusRateLimitData {
    match snapshot {
        Some(snapshot) => compose_rate_limit_data_many(...),
        None => StatusRateLimitData::Missing,  // None -> Missing
    }
}
```

2. **Missing 状态渲染** (`card.rs:330-333`):
```rust
StatusRateLimitData::Missing => {
    vec![formatter.line("Limits", vec![Span::from("data not available yet").dim()])]
}
```

3. **测试数据** (`tests.rs:654-700`):
```rust
// 不创建 RateLimitSnapshot，直接传递 None
let composite = new_status_output(
    &config,
    account_display.as_ref(),
    Some(&token_info),
    &usage,
    &None,
    None,
    None,
    None,  // rate_limits 为 None
    None,
    now,
    &model_slug,
    None,
    None,
);
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `tui_app_server/src/status/tests.rs:654-700` | 测试用例定义 |
| `tui_app_server/src/status/rate_limits.rs:158-166` | `compose_rate_limit_data` |
| `tui_app_server/src/status/card.rs:330-333` | Missing 状态渲染 |

## 风险、边界与改进建议

### 当前风险
1. **无法区分**: Missing 和 Available([]) 显示相同

### 改进建议
1. **区分显示**: Missing 显示 "waiting for first response..."
2. **自动刷新**: 检测到 Missing 时自动触发刷新

### 测试覆盖
- ✅ 完全缺失限制数据
- ✅ Missing 状态
