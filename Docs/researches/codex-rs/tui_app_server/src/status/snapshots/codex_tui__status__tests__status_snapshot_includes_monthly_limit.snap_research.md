# 研究文档: status_snapshot_includes_monthly_limit.snap

## 场景与职责

此快照文件是 `codex-tui` crate 中状态显示功能的 insta 快照测试结果，测试用例为 `status_snapshot_includes_monthly_limit`。该测试验证当速率限制配置为月度窗口时，状态显示能正确识别并展示月度限制信息。

## 功能点目的

### 测试目标
验证以下场景的状态显示行为：
1. **月度限制识别**: 将 43,200 分钟（30 天）的窗口正确识别为 "Monthly limit"
2. **单窗口显示**: 仅显示主限制窗口（无次要窗口）
3. **重置时间显示**: 显示具体的重置日期和时间

### 业务逻辑
- 不同账户类型可能有不同的限制周期（5小时、每周、每月）
- 系统需要根据窗口时长自动推断限制类型标签
- 月度限制通常与特定的计费周期对齐

## 具体技术实现

### 关键数据结构

```rust
pub struct RateLimitWindow {
    pub used_percent: f64,
    pub window_minutes: Option<i64>,  // 43,200 = 30天
    pub resets_at: Option<i64>,       // Unix 时间戳
}
```

### 关键流程

1. **窗口时长到标签的转换** (`chatwidget.rs` - 通过 `get_limits_duration`):
```rust
// window_minutes: Some(43_200) -> "monthly"
// 转换逻辑基于预定义的时长阈值
```

2. **标签首字母大写** (`rate_limits.rs:189-204`):
```rust
let primary_label = snapshot
    .primary
    .as_ref()
    .map(|window| {
        window
            .window_minutes
            .map(get_limits_duration)           // 获取时长标签
            .unwrap_or_else(|| "5h".to_string())
    })
    .map(|label| capitalize_first(&label));     // 首字母大写
```

3. **重置时间格式化** (`helpers.rs`):
```rust
pub(crate) fn format_reset_timestamp(
    resets_at: DateTime<Local>,
    captured_at: DateTime<Local>,
) -> String {
    // 根据与当前时间的差距选择格式：
    // - 同一天：显示时间 "07:08"
    // - 不同天：显示 "07:08 on 7 May"
}
```

4. **测试数据设置** (`tests.rs:293-353`):
```rust
let snapshot = RateLimitSnapshot {
    primary: Some(RateLimitWindow {
        used_percent: 12.0,              // 88% 剩余
        window_minutes: Some(43_200),    // 30天 = 月度
        resets_at: Some(reset_at_from(&captured_at, 86_400)), // 1天后重置
    }),
    secondary: None,                     // 无次要窗口
    credits: None,
    ...
};
// captured_at: 2024-05-06 07:08:09
// resets_at: 2024-05-07 07:08:09 (显示为 "07:08 on 7 May")
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `tui/src/status/tests.rs:293-353` | 测试用例定义 |
| `tui/src/status/rate_limits.rs:185-228` | 限制标签生成逻辑 |
| `tui/src/chatwidget.rs` | `get_limits_duration` - 时长到标签的映射 |
| `tui/src/status/helpers.rs` | `format_reset_timestamp` - 重置时间格式化 |
| `tui/src/text_formatting.rs` | `capitalize_first` - 首字母大写 |

## 依赖与外部交互

### 依赖模块
- `chrono` - 日期时间处理
- `chatwidget::get_limits_duration` - 时长标签映射

### 时长标签映射规则
根据 `get_limits_duration` 函数的实现：
- 300 分钟 → "5h"
- 1,440 分钟 → "1d" / "daily"
- 10,080 分钟 → "weekly"
- 43,200 分钟 → "monthly"
- 其他 → 根据具体时长计算

## 风险、边界与改进建议

### 当前风险
1. **硬编码时长映射**: 月度定义为 30 天（43,200 分钟），但实际月份天数不同
2. **时区问题**: 重置时间显示使用本地时区，跨时区用户可能困惑

### 边界情况
1. **闰月**: 2 月的月度限制显示仍为 "Monthly"，但实际天数不同
2. **跨月重置**: 重置时间可能在次月，显示格式需要包含日期
3. **非标准周期**: 非 30 天的"月度"限制可能显示为其他标签

### 改进建议
1. **动态标签**: 根据实际天数显示 "30-day limit" 而非固定的 "Monthly"
2. **时区提示**: 在重置时间后添加时区标识（如 "UTC" 或 "Local"）
3. **日历对齐**: 考虑与真实日历月份对齐，而非固定 30 天
4. **相对时间**: 考虑添加相对时间显示（如 "resets in 2 days"）

### 测试覆盖
此快照测试覆盖了以下场景：
- ✅ 月度限制窗口识别（43,200 分钟）
- ✅ 单窗口显示（无次要窗口）
- ✅ 跨天重置时间显示（包含日期）
- ✅ 进度条渲染（88% 剩余）

### 相关测试
- `status_snapshot_includes_credits_and_limits` - 双窗口测试
- `status_snapshot_shows_empty_limits_message` - 空限制测试
