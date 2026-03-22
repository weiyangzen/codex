# error.rs 研究文档

## 场景与职责

`error.rs` 是 Codex CLI 的**核心错误类型定义模块**，定义了整个应用程序使用的错误类型层次结构。该模块提供了统一的错误处理机制，包括错误分类、用户友好的错误消息、协议错误映射和重试策略决策。

**核心职责：**
1. **错误类型定义** - 定义所有核心业务错误变体
2. **错误分类** - 区分可重试错误和不可重试错误
3. **用户消息生成** - 将技术错误转换为用户友好的消息
4. **协议错误映射** - 将内部错误映射到协议错误码
5. **使用限制处理** - 根据用户套餐类型生成不同的提示消息

**使用场景：**
- 所有业务逻辑的错误返回
- 网络请求失败处理
- 沙箱执行错误处理
- 使用限制和配额超限提示
- 流式响应错误处理

---

## 功能点目的

### 1. 错误类型层次结构

**主错误类型：CodexErr**
```rust
pub enum CodexErr {
    TurnAborted,                    // Turn 被中止
    Stream(String, Option<Duration>), // 流断开，可选重试延迟
    ContextWindowExceeded,          // 上下文窗口超限
    ThreadNotFound(ThreadId),       // 线程不存在
    AgentLimitReached { max_threads: usize }, // 代理线程数超限
    Timeout,                        // 命令执行超时
    Spawn,                          // 子进程创建失败
    Interrupted,                    // 用户中断（Ctrl-C）
    UnexpectedStatus(UnexpectedResponseError), // 意外 HTTP 状态
    InvalidRequest(String),         // 无效请求
    InvalidImageRequest(),          // 无效图像请求
    UsageLimitReached(UsageLimitReachedError), // 使用限制超限
    ServerOverloaded,               // 服务器过载
    QuotaExceeded,                  // 配额超限
    UsageNotIncluded,               // 使用不包含在套餐中
    InternalServerError,            // 服务器内部错误
    RetryLimit(RetryLimitReachedError), // 重试次数超限
    InternalAgentDied,              // 代理循环异常终止
    Sandbox(SandboxErr),            // 沙箱错误
    LandlockSandboxExecutableNotProvided, // Landlock 可执行文件缺失
    UnsupportedOperation(String),   // 不支持的操作
    RefreshTokenFailed(RefreshTokenFailedError), // 刷新令牌失败
    Fatal(String),                  // 致命错误
    // 外部错误转换
    Io(io::Error),
    Json(serde_json::Error),
    LandlockRuleset(landlock::RulesetError),      // Linux only
    LandlockPathFd(landlock::PathFdError),        // Linux only
    TokioJoin(JoinError),
    EnvVar(EnvVarError),
}
```

**沙箱错误子类型：SandboxErr**
```rust
pub enum SandboxErr {
    Denied { output: Box<ExecToolCallOutput>, network_policy_decision: Option<NetworkPolicyDecisionPayload> },
    SeccompInstall(seccompiler::Error),    // Linux only
    SeccompBackend(seccompiler::BackendError), // Linux only
    Timeout { output: Box<ExecToolCallOutput> },
    Signal(i32),                           // 被信号终止
    LandlockRestrict,                      // Landlock 限制失败
}
```

### 2. 错误重试策略

```rust
impl CodexErr {
    pub fn is_retryable(&self) -> bool
}
```

**可重试错误：**
- `Stream` - 流断开，可重试
- `Timeout` - 超时，可重试
- `UnexpectedStatus` - 意外状态码，可重试
- `ResponseStreamFailed` - 响应流失败，可重试
- `ConnectionFailed` - 连接失败，可重试
- `InternalServerError` - 服务器内部错误，可重试
- `InternalAgentDied` - 代理异常终止，可重试
- `Io`, `Json`, `TokioJoin` - IO/序列化/任务错误，可重试

**不可重试错误：**
- `TurnAborted`, `Interrupted` - 用户主动操作
- `ContextWindowExceeded` - 上下文超限，需新开线程
- `UsageLimitReached`, `QuotaExceeded`, `UsageNotIncluded` - 配额问题
- `InvalidRequest`, `InvalidImageRequest` - 请求无效
- `Sandbox` - 沙箱错误（安全策略）
- `ThreadNotFound`, `AgentLimitReached` - 资源限制

### 3. 使用限制错误处理

**UsageLimitReachedError**
```rust
pub struct UsageLimitReachedError {
    pub(crate) plan_type: Option<PlanType>,
    pub(crate) resets_at: Option<DateTime<Utc>>,
    pub(crate) rate_limits: Option<Box<RateLimitSnapshot>>,
    pub(crate) promo_message: Option<String>,
}
```

**套餐特定消息：**
- `Plus` - 提示升级到 Pro 或购买积分
- `Team`/`Business` - 提示联系管理员
- `Free`/`Go` - 提示升级到 Plus
- `Pro` - 提示购买积分
- `Enterprise`/`Edu` - 简洁提示

**时间格式化：**
- 同一天：显示时间（如 "1:30 PM"）
- 不同天：显示完整日期（如 "Jan 1st, 2024 1:30 PM"）

### 4. 意外响应错误处理

**UnexpectedResponseError**
```rust
pub struct UnexpectedResponseError {
    pub status: StatusCode,
    pub body: String,
    pub url: Option<String>,
    pub cf_ray: Option<String>,
    pub request_id: Option<String>,
    pub identity_authorization_error: Option<String>,
    pub identity_error_code: Option<String>,
}
```

**特殊处理：**
- Cloudflare 拦截检测（403 + 包含 "Cloudflare" 和 "blocked"）
- JSON 错误消息提取（`error.message` 字段）
- 长响应体截断（最多 1000 字节）

### 5. 协议错误映射

```rust
impl CodexErr {
    pub fn to_codex_protocol_error(&self) -> CodexErrorInfo
    pub fn to_error_event(&self, message_prefix: Option<String>) -> ErrorEvent
    pub fn http_status_code_value(&self) -> Option<u16>
}
```

**错误映射表：**
| 内部错误 | 协议错误 |
|---------|---------|
| ContextWindowExceeded | ContextWindowExceeded |
| UsageLimitReached, QuotaExceeded, UsageNotIncluded | UsageLimitExceeded |
| ServerOverloaded | ServerOverloaded |
| RetryLimit | ResponseTooManyFailedAttempts |
| ConnectionFailed | HttpConnectionFailed |
| ResponseStreamFailed | ResponseStreamConnectionFailed |
| RefreshTokenFailed | Unauthorized |
| InternalServerError, InternalAgentDied | InternalServerError |
| Sandbox | SandboxError |
| 其他 | Other |

---

## 具体技术实现

### 错误消息截断

```rust
const ERROR_MESSAGE_UI_MAX_BYTES: usize = 2 * 1024; // 2 KiB

pub fn get_error_message_ui(e: &CodexErr) -> String {
    // 根据错误类型生成用户消息
    // 沙箱错误特殊处理（优先使用 aggregated_output）
    // 超时错误特殊格式
    // 其他错误使用 Display 实现
    // 最后截断到 2KB
}
```

### 时间格式化

```rust
fn format_retry_timestamp(resets_at: &DateTime<Utc>) -> String {
    let local_reset = resets_at.with_timezone(&Local);
    let local_now = now_for_retry().with_timezone(&Local);
    if local_reset.date_naive() == local_now.date_naive() {
        local_reset.format("%-I:%M %p").to_string()  // 仅时间
    } else {
        let suffix = day_suffix(local_reset.day());
        local_reset.format("%b %-d{suffix}, %Y %-I:%M %p").to_string()  // 完整日期
    }
}

fn day_suffix(day: u32) -> &'static str {
    match day {
        11..=13 => "th",
        _ => match day % 10 {
            1 => "st",
            2 => "nd",
            3 => "rd",
            _ => "th",
        },
    }
}
```

### 测试时间覆盖

```rust
#[cfg(test)]
thread_local! {
    static NOW_OVERRIDE: std::cell::RefCell<Option<DateTime<Utc>>> = ...
}
```
- 允许测试覆盖当前时间
- 用于验证时间格式化逻辑

---

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/error.rs` (673 行)
- `/home/sansha/Github/codex/codex-rs/core/src/error_tests.rs` (517 行，测试模块)

### 依赖文件
- `/home/sansha/Github/codex/codex-rs/core/src/exec.rs` - `ExecToolCallOutput`, `StreamOutput`
- `/home/sansha/Github/codex/codex-rs/core/src/network_policy_decision.rs` - `NetworkPolicyDecisionPayload`
- `/home/sansha/Github/codex/codex-rs/core/src/token_data.rs` - `PlanType`, `KnownPlan`
- `/home/sansha/Github/codex/codex-rs/core/src/truncate.rs` - `TruncationPolicy`, `truncate_text`
- `/home/sansha/Github/codex/codex-rs/protocol/src/protocol.rs` - `CodexErrorInfo`, `ErrorEvent`, `RateLimitSnapshot`

### 调用方
- 几乎所有核心模块都使用 `CodexErr`
- `/home/sansha/Github/codex/codex-rs/core/src/codex.rs` - 核心逻辑
- `/home/sansha/Github/codex/codex-rs/core/src/client.rs` - HTTP 客户端
- `/home/sansha/Github/codex/codex-rs/core/src/exec.rs` - 命令执行
- `/home/sansha/Github/codex/codex-rs/core/src/sandboxing.rs` - 沙箱

---

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `thiserror::Error` | 错误派生宏 |
| `chrono` | 日期时间处理 |
| `reqwest::StatusCode` | HTTP 状态码 |
| `serde_json` | JSON 错误消息提取 |
| `tokio::task::JoinError` | 异步任务错误 |
| `seccompiler` | seccomp 错误（Linux）|
| `landlock` | Landlock 错误（Linux）|

### 协议集成
```rust
// 转换为协议错误
CodexErr::to_codex_protocol_error() -> CodexErrorInfo
CodexErr::to_error_event() -> ErrorEvent
```

---

## 风险、边界与改进建议

### 已知风险

1. **错误类型膨胀**
   - `CodexErr` 已包含 30+ 变体
   - 可能导致 `match` 语句冗长
   - 建议：按领域拆分为子错误类型

2. **重试策略硬编码**
   - `is_retryable()` 逻辑集中且硬编码
   - 某些场景可能需要动态调整
   - 建议：支持配置化重试策略

3. **时间格式化本地化**
   - 当前使用英文格式（Jan 1st, 2024）
   - 无国际化支持
   - 建议：支持多语言时间格式

4. **错误消息长度限制**
   - 统一截断到 2KB
   - 可能丢失关键调试信息
   - 建议：区分用户消息和日志消息

### 边界情况

1. **时间格式化边界**
   - 日期后缀逻辑（11th, 12th, 13th 特殊处理）
   - 跨天时区变化
   - 夏令时转换

2. **HTTP 错误解析**
   - JSON 解析失败时回退到原始 body
   - 空 body 显示 "Unknown error"
   - 超长 body 截断（1000 字节）

3. **沙箱错误输出**
   - 优先使用 `aggregated_output`
   - 其次合并 stdout/stderr
   - 最后回退到退出码

### 改进建议

1. **错误分类优化**
   ```rust
   pub enum CodexErr {
       Network(NetworkError),      // 网络相关
       Sandbox(SandboxErr),        // 沙箱相关
       Usage(UsageError),          // 使用限制
       Input(InputError),          // 输入验证
       // ...
   }
   ```

2. **重试策略配置**
   ```rust
   pub struct RetryPolicy {
       max_attempts: u32,
       backoff_strategy: BackoffStrategy,
       retryable_errors: Vec<ErrorKind>,
   }
   ```

3. **国际化支持**
   ```rust
   pub fn to_localized_string(&self, locale: &str) -> String
   ```

4. **错误链改进**
   - 使用 `anyhow` 或 `eyre` 提供更好的错误链
   - 保留完整的错误上下文

5. **遥测集成**
   - 自动上报错误类型和频率
   - 帮助识别常见问题和改进点
