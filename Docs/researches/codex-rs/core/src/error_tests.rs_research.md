# error_tests.rs 研究文档

## 场景与职责

`error_tests.rs` 是 `error.rs` 的配套测试模块，负责验证错误类型、错误消息格式化和协议错误映射的正确性。测试覆盖了使用限制错误、沙箱错误、HTTP 错误和协议映射等多个方面。

**测试覆盖范围：**
1. 使用限制错误消息格式化（各套餐类型）
2. 服务器过载错误协议映射
3. 沙箱错误消息提取（多种输出场景）
4. 响应流失败错误事件生成
5. HTTP 意外状态错误处理（Cloudflare、JSON、截断）
6. 时间格式化（各种时间跨度）
7. 促销消息集成

---

## 功能点目的

### 测试用例清单

| 测试函数 | 目的 | 关键验证点 |
|---------|------|-----------|
| `usage_limit_reached_error_formats_plus_plan` | Plus 套餐消息 | 升级 Pro 提示 |
| `server_overloaded_maps_to_protocol` | 协议映射 | ServerOverloaded → ServerOverloaded |
| `sandbox_denied_uses_aggregated_output_when_stderr_empty` | 沙箱错误输出 | 优先使用 aggregated_output |
| `sandbox_denied_reports_both_streams_when_available` | 沙箱错误输出 | 合并 stderr 和 stdout |
| `sandbox_denied_reports_stdout_when_no_stderr` | 沙箱错误输出 | 仅 stdout |
| `to_error_event_handles_response_stream_failed` | 错误事件生成 | 消息格式和协议错误码 |
| `sandbox_denied_reports_exit_code_when_no_output_available` | 沙箱错误输出 | 回退到退出码 |
| `usage_limit_reached_error_formats_free_plan` | Free 套餐消息 | 升级 Plus 提示 |
| `usage_limit_reached_error_formats_go_plan` | Go 套餐消息 | 升级 Plus 提示 |
| `usage_limit_reached_error_formats_default_when_none` | 默认消息 | 无套餐时的通用提示 |
| `usage_limit_reached_error_formats_team_plan` | Team 套餐消息 | 联系管理员提示 |
| `usage_limit_reached_error_formats_business_plan_without_reset` | Business 套餐消息 | 联系管理员提示 |
| `usage_limit_reached_error_formats_default_for_other_plans` | Enterprise/Edu 消息 | 简洁提示 |
| `usage_limit_reached_error_formats_pro_plan_with_reset` | Pro 套餐消息 | 购买积分提示 |
| `usage_limit_reached_error_hides_upsell_for_non_codex_limit_name` | 非 Codex 限制 | 隐藏升级提示 |
| `usage_limit_reached_includes_minutes_when_available` | 时间格式化 | 分钟级精度 |
| `unexpected_status_cloudflare_html_is_simplified` | Cloudflare 错误 | 简化消息提取 |
| `unexpected_status_non_html_is_unchanged` | 纯文本错误 | 保留原始消息 |
| `unexpected_status_prefers_error_message_when_present` | JSON 错误 | 提取 error.message |
| `unexpected_status_truncates_long_body_with_ellipsis` | 长消息截断 | 1000 字节限制 |
| `unexpected_status_includes_cf_ray_and_request_id` | 诊断信息 | cf-ray 和 request_id |
| `unexpected_status_includes_identity_auth_details` | 认证错误 | auth error 和 error code |
| `usage_limit_reached_includes_hours_and_minutes` | 时间格式化 | 小时和分钟 |
| `usage_limit_reached_includes_days_hours_minutes` | 时间格式化 | 天、小时、分钟 |
| `usage_limit_reached_less_than_minute` | 时间格式化 | 秒级精度 |
| `usage_limit_reached_with_promo_message` | 促销消息 | 自定义提示 |

---

## 具体技术实现

### 测试基础设施

**时间覆盖机制：**
```rust
fn with_now_override<T>(now: DateTime<Utc>, f: impl FnOnce() -> T) -> T {
    NOW_OVERRIDE.with(|cell| {
        *cell.borrow_mut() = Some(now);
        let result = f();
        *cell.borrow_mut() = None;
        result
    })
}
```
- 使用线程本地存储覆盖当前时间
- 确保时间格式化测试可预测

**RateLimitSnapshot 构造：**
```rust
fn rate_limit_snapshot() -> RateLimitSnapshot {
    RateLimitSnapshot {
        limit_id: None,
        limit_name: None,
        primary: Some(RateLimitWindow { ... }),
        secondary: Some(RateLimitWindow { ... }),
        credits: None,
        plan_type: None,
    }
}
```
- 提供一致的测试数据

**HTTP 响应构造：**
```rust
let response = http::Response::builder()
    .status(StatusCode::TOO_MANY_REQUESTS)
    .url(Url::parse("http://example.com").unwrap())
    .body("")
    .unwrap();
let source = Response::from(response).error_for_status_ref().unwrap_err();
```
- 使用 `http` crate 构建响应
- 转换为 `reqwest::Error`

### 关键测试场景

**1. 沙箱错误输出优先级测试**
```rust
#[test]
fn sandbox_denied_uses_aggregated_output_when_stderr_empty() {
    let output = ExecToolCallOutput {
        exit_code: 77,
        stdout: StreamOutput::new(String::new()),
        stderr: StreamOutput::new(String::new()),
        aggregated_output: StreamOutput::new("aggregate detail".to_string()),
        ...
    };
    // 验证优先使用 aggregated_output
}
```
- 验证输出优先级：aggregated > stderr > stdout > exit_code

**2. Cloudflare 拦截检测测试**
```rust
#[test]
fn unexpected_status_cloudflare_html_is_simplified() {
    let err = UnexpectedResponseError {
        status: StatusCode::FORBIDDEN,
        body: "<html><body>Cloudflare error: Sorry, you have been blocked</body></html>".to_string(),
        ...
    };
    // 验证简化为：Access blocked by Cloudflare...
}
```
- 验证 HTML 被识别并简化

**3. JSON 错误提取测试**
```rust
#[test]
fn unexpected_status_prefers_error_message_when_present() {
    let body = r#"{"error":{"message":"Workspace is not authorized in this region."},"status":401}"#;
    // 验证提取 "Workspace is not authorized in this region."
}
```
- 验证 JSON 解析和字段提取

**4. 时间格式化测试**
```rust
#[test]
fn usage_limit_reached_includes_days_hours_minutes() {
    let base = Utc.with_ymd_and_hms(2024, 1, 1, 0, 0, 0).unwrap();
    let resets_at = base + ChronoDuration::days(2) + ChronoDuration::hours(3) + ChronoDuration::minutes(5);
    with_now_override(base, || {
        // 验证格式包含天、小时、分钟
    });
}
```
- 验证各种时间跨度的格式化

---

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/error_tests.rs` (517 行)

### 被测试文件
- `/home/sansha/Github/codex/codex-rs/core/src/error.rs` - 主实现

### 测试依赖
- `pretty_assertions::assert_eq` - 清晰的断言输出
- `chrono` - 时间处理
- `reqwest` - HTTP 类型
- `http` - HTTP 响应构造

---

## 依赖与外部交互

### 测试框架
| 依赖 | 用途 |
|------|------|
| `pretty_assertions` | 清晰的字符串比较 |
| `chrono::TimeZone` | 时间构造 |
| `reqwest::{Response, ResponseBuilderExt, StatusCode, Url}` | HTTP 类型 |

### 被测模块导入
```rust
use super::*;
use crate::exec::StreamOutput;
use codex_protocol::protocol::RateLimitWindow;
```

---

## 风险、边界与改进建议

### 测试覆盖缺口

1. **重试策略测试**
   - 无 `is_retryable()` 测试
   - 无重试边界条件测试

2. **错误转换测试**
   - 无 `From<CancelErr>` 测试
   - 无 `From<io::Error>` 等转换测试

3. **消息截断测试**
   - 无 `get_error_message_ui` 截断测试
   - 无 2KB 边界测试

4. **沙箱超时测试**
   - 无 `SandboxErr::Timeout` 消息格式测试

5. **信号终止测试**
   - 无 `SandboxErr::Signal` 消息格式测试

6. **协议错误映射完整性**
   - 未覆盖所有 `CodexErr` 变体
   - 无 `http_status_code_value` 测试

7. **时间格式化边界**
   - 无夏令时转换测试
   - 无时区边界测试
   - 无闰年测试

### 改进建议

1. **添加重试策略测试**
   ```rust
   #[test]
   fn retryable_errors_are_correctly_identified() {
       assert!(CodexErr::Timeout.is_retryable());
       assert!(!CodexErr::UsageLimitReached(...).is_retryable());
   }
   ```

2. **添加错误转换测试**
   ```rust
   #[test]
   fn cancel_err_converts_to_turn_aborted() {
       let cancel_err = CancelErr;
       let codex_err: CodexErr = cancel_err.into();
       assert!(matches!(codex_err, CodexErr::TurnAborted));
   }
   ```

3. **添加消息截断测试**
   ```rust
   #[test]
   fn error_message_is_truncated_at_2kb() {
       let long_message = "x".repeat(3000);
       // 验证截断到 2048 字节
   }
   ```

4. **添加协议映射完整测试**
   ```rust
   #[test]
   fn all_error_variants_map_to_protocol() {
       // 遍历所有 CodexErr 变体，验证都有对应的协议错误
   }
   ```

5. **添加时间边界测试**
   ```rust
   #[test]
   fn day_suffix_handles_leap_year() { ... }
   
   #[test]
   fn timezone_transition_handled_correctly() { ... }
   ```

6. **使用参数化测试**
   - 使用 `test_case` crate 减少重复代码
   - 套餐类型、时间跨度等可用参数化测试

### 测试代码质量

**优点：**
- 使用 `pretty_assertions` 改善输出
- 时间测试使用覆盖机制确保可预测性
- 清晰的测试命名和结构
- 覆盖多种错误场景

**可改进点：**
- 大量重复的 `UsageLimitReachedError` 构造可提取辅助函数
- 可添加属性测试（proptest）验证错误消息格式
- 可添加快照测试（insta）验证复杂消息格式
