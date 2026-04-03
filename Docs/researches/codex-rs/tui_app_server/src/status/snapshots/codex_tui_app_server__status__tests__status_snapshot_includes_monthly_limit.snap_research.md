# 研究文档: codex_tui_app_server__status__tests__status_snapshot_includes_monthly_limit.snap

## 场景与职责

此快照文件是 `codex-tui-app-server` crate 中状态显示功能的 insta 快照测试结果，测试用例为 `status_snapshot_includes_monthly_limit`。该测试验证当速率限制配置为月度窗口（43,200 分钟 = 30 天）时，状态显示能正确识别并展示月度限制信息。

## 功能点目的

### 测试目标
验证以下场景的状态显示行为：
1. **月度限制识别**: 将 43,200 分钟正确识别为 "Monthly limit"
2. **单窗口显示**: 仅显示主限制窗口
3. **跨天重置时间**: 显示包含日期的重置时间

## 具体技术实现

### 关键流程

1. **窗口时长到标签的转换** (`chatwidget.rs`):
```rust
// window_minutes: Some(43_200) -> "monthly"
```

2. **标签首字母大写** (`rate_limits.rs`):
```rust
let primary_label = snapshot
    .primary
    .as_ref()
    .map(|window| {
        window
            .window_minutes
            .map(get_limits_duration)
            .unwrap_or_else(|| "5h".to_string())
    })
    .map(|label| capitalize_first(&label));  // "monthly" -> "Monthly"
```

3. **重置时间格式化** (`helpers.rs`):
```rust
// 跨天显示："07:08 on 7 May"
```

4. **测试数据** (`tests.rs:289-349`):
```rust
let captured_at = chrono::Local
    .with_ymd_and_hms(2024, 5, 6, 7, 8, 9)  // 5月6日
    .single()
    .expect("timestamp");

let snapshot = RateLimitSnapshot {
    primary: Some(RateLimitWindow {
        used_percent: 12.0,              // 88% 剩余
        window_minutes: Some(43_200),    // 30天
        resets_at: Some(reset_at_from(&captured_at, 86_400)), // 5月7日
    }),
    secondary: None,
    credits: None,
    ...
};
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `tui_app_server/src/status/tests.rs:289-349` | 测试用例定义 |
| `tui_app_server/src/status/rate_limits.rs` | 限制标签生成 |
| `tui_app_server/src/chatwidget.rs` | `get_limits_duration` 时长映射 |
| `tui_app_server/src/status/helpers.rs` | 重置时间格式化 |

## 依赖与外部交互

### 时长标签映射
- 300 分钟 → "5h"
- 43,200 分钟 → "monthly"

## 风险、边界与改进建议

### 当前风险
1. **硬编码时长**: 月度定义为 30 天，与实际月份天数不同
2. **时区问题**: 重置时间使用本地时区

### 改进建议
1. **动态标签**: 根据实际天数显示
2. **时区提示**: 添加时区标识

### 测试覆盖
- ✅ 月度限制窗口识别
- ✅ 单窗口显示
- ✅ 跨天重置时间显示
