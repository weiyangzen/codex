# 研究文档: status_snapshot_shows_missing_limits_message.snap

## 场景与职责

此快照文件是 `codex-tui` crate 中状态显示功能的 insta 快照测试结果，测试用例为 `status_snapshot_shows_missing_limits_message`。该测试验证当速率限制快照完全缺失时（即 `None`），状态显示能正确处理并显示适当的提示信息。

## 功能点目的

### 测试目标
验证以下场景的状态显示行为：
1. **完全缺失限制数据**: 不传递任何 `RateLimitSnapshotDisplay` 给状态显示函数
2. **Missing 状态**: `StatusRateLimitData::Missing` 被正确设置
3. **默认提示**: 显示 "Limits: data not available yet"

### 业务逻辑
- 在会话初期或网络问题时，限制数据可能尚未获取
- 用户需要知道限制数据正在等待获取
- 这与空限制快照（`Available([])`）在显示上相同，但语义不同

## 具体技术实现

### 关键数据结构

```rust
pub(crate) enum StatusRateLimitData {
    Available(Vec<StatusRateLimitRow>),  // 有数据
    Stale(Vec<StatusRateLimitRow>),      // 数据过时
    Missing,                              // 完全无数据
}
```

### 关键流程

1. **缺失数据处理** (`rate_limits.rs:158-166`):
```rust
pub(crate) fn compose_rate_limit_data(
    snapshot: Option<&RateLimitSnapshotDisplay>,
    now: DateTime<Local>,
) -> StatusRateLimitData {
    match snapshot {
        Some(snapshot) => compose_rate_limit_data_many(std::slice::from_ref(snapshot), now),
        None => StatusRateLimitData::Missing,  // None -> Missing
    }
}
```

2. **Missing 状态渲染** (`card.rs:330-333`):
```rust
fn rate_limit_lines(&self, ...) -> Vec<Line<'static>> {
    match &self.rate_limits {
        // ...
        StatusRateLimitData::Missing => {
            vec![formatter.line("Limits", vec![Span::from("data not available yet").dim()])]
        }
    }
}
```

3. **测试数据设置** (`tests.rs:654-704`):
```rust
// 注意：不创建 RateLimitSnapshot，直接传递 None
let composite = new_status_output(
    &config,
    &auth_manager,
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

4. **状态卡片构建** (`card.rs:249-254`):
```rust
let rate_limits = if rate_limits.len() <= 1 {
    compose_rate_limit_data(rate_limits.first(), now)  // first() 返回 None
} else {
    compose_rate_limit_data_many(rate_limits, now)
};
// 当 rate_limits 为空切片时，first() 返回 None，导致 Missing 状态
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `tui/src/status/tests.rs:654-704` | 测试用例定义 |
| `tui/src/status/rate_limits.rs:158-166` | `compose_rate_limit_data` - None 处理 |
| `tui/src/status/card.rs:249-254` | 状态卡片构建时的限制数据处理 |
| `tui/src/status/card.rs:330-333` | Missing 状态渲染 |

## 依赖与外部交互

### 依赖模块
- `codex_protocol::protocol::RateLimitSnapshot` - 限制快照结构

### 与 Empty 状态对比
| 状态 | 含义 | 触发条件 |
|------|------|----------|
| `Missing` | 从未获取过限制数据 | `rate_limits: None` 或空切片 |
| `Available([])` | 获取了数据但内容为空 | `RateLimitSnapshot` 所有字段为 None |

## 风险、边界与改进建议

### 当前风险
1. **无法区分**: `Missing` 和 `Available([])` 显示相同，不利于调试
2. **用户体验**: 用户不知道是需要等待还是账户本身无限制

### 边界情况
1. **网络恢复**: 从 Missing 到 Available 的过渡应有平滑处理
2. **首次加载**: 应用启动时通常处于 Missing 状态
3. **错误处理**: 如果获取限制数据失败，仍保持 Missing 状态

### 改进建议
1. **区分显示**:
   ```
   Missing: "Limits: waiting for first response..."
   Available([]): "Limits: no limits configured"
   ```
2. **刷新按钮**: 提供手动刷新限制数据的交互
3. **错误提示**: 如果获取失败，显示错误信息而非默认提示
4. **加载状态**: 添加加载指示器表示正在获取数据

### 测试覆盖
此快照测试覆盖了以下场景：
- ✅ 完全缺失限制数据
- ✅ Missing 状态正确设置
- ✅ 默认提示显示

### 相关测试
- `status_snapshot_shows_empty_limits_message` - 测试空快照场景
- `status_snapshot_shows_stale_limits_message` - 测试过时数据场景
- `status_snapshot_includes_credits_and_limits` - 测试正常数据场景

### 代码对比
```rust
// Missing 状态（本测试）
new_status_output(..., None, ...)  // rate_limits = None

// Empty 状态（shows_empty_limits_message）
let snapshot = RateLimitSnapshot { primary: None, secondary: None, ... };
let rate_display = rate_limit_snapshot_display(&snapshot, captured_at);
new_status_output(..., Some(&rate_display), ...)  // rate_limits = Some(空)
```
