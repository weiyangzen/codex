# 研究文档: codex_tui_app_server__status__tests__status_snapshot_shows_empty_limits_message.snap

## 场景与职责

此快照文件是 `codex-tui-app-server` crate 中状态显示功能的 insta 快照测试结果，测试用例为 `status_snapshot_shows_empty_limits_message`。该测试验证当速率限制快照存在但所有窗口数据都为空时，状态显示能正确处理。

## 功能点目的

### 测试目标
验证以下场景的状态显示行为：
1. **空限制快照**: `RateLimitSnapshot` 存在但 `primary` 和 `secondary` 都为 `None`
2. **默认提示**: 显示 "Limits: data not available yet"

### Empty vs Missing
- `Available([])`: 后端返回了空快照
- `Missing`: 后端未返回任何快照
- 两者显示相同但语义不同

## 具体技术实现

### 关键流程

1. **空快照处理** (`rate_limits.rs:271-277`):
```rust
if rows.is_empty() {
    StatusRateLimitData::Available(vec![])  // 空但 Available
} else if stale {
    StatusRateLimitData::Stale(rows)
} else {
    StatusRateLimitData::Available(rows)
}
```

2. **空 Available 渲染** (`card.rs:312-320`):
```rust
StatusRateLimitData::Available(rows_data) => {
    if rows_data.is_empty() {
        return vec![
            formatter.line("Limits", vec![Span::from("data not available yet").dim()]),
        ];
    }
    // ...
}
```

3. **测试数据** (`tests.rs:771-826`):
```rust
let snapshot = RateLimitSnapshot {
    limit_id: None,
    limit_name: None,
    primary: None,
    secondary: None,
    credits: None,
    plan_type: None,
};
let rate_display = rate_limit_snapshot_display(&snapshot, captured_at);

let composite = new_status_output(
    &config,
    account_display.as_ref(),
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
| `tui_app_server/src/status/tests.rs:771-826` | 测试用例定义 |
| `tui_app_server/src/status/rate_limits.rs:271-277` | 空 rows 处理 |
| `tui_app_server/src/status/card.rs:312-320` | Available 空状态渲染 |

## 风险、边界与改进建议

### 当前风险
1. **状态混淆**: `Available([])` 和 `Missing` 显示相同

### 改进建议
1. **区分显示**: 使用不同的提示信息
2. **调试信息**: 在详细模式下显示原始快照数据

### 测试覆盖
- ✅ 空限制快照
- ✅ 默认提示显示
