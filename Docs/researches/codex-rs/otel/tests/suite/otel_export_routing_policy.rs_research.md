# otel_export_routing_policy.rs 深入研究

## 场景与职责

`otel_export_routing_policy.rs` 是 Codex OpenTelemetry 模块的核心集成测试文件，专注于测试**日志（Logs）与追踪（Traces）的分离导出策略**。这是 Codex 遥测系统的关键安全特性，确保敏感信息仅进入日志系统而不会泄露到分布式追踪中。

**核心测试场景：**
1. 用户提示（User Prompt）的日志/追踪分离导出
2. 工具执行结果（Tool Result）的日志/追踪分离导出
3. 认证恢复（Auth Recovery）事件的日志/追踪导出
4. API 请求认证可观测性数据的导出
5. WebSocket 连接认证可观测性数据的导出
6. WebSocket 请求传输层可观测性数据的导出

## 功能点目的

### 1. 敏感信息保护（Sink Split）

Codex 处理的用户输入可能包含敏感信息（如密码、密钥、个人隐私数据）。OpenTelemetry 追踪数据通常会被发送到分布式追踪系统（如 Jaeger、Zipkin），这些系统可能有不同的访问控制策略。

**安全策略：**
- **日志（Logs）**：包含完整敏感内容，发送到受控的日志存储
- **追踪（Traces）**：仅包含元数据（长度、计数等），用于性能分析

### 2. 认证可观测性

Codex 支持多种认证模式（API Key、ChatGPT Token 等）。认证过程中的错误恢复、重试等行为需要被记录以便排查问题，但又要避免在追踪中泄露认证头信息。

### 3. 传输层监控

WebSocket 和 SSE（Server-Sent Events）是 Codex 与后端通信的主要方式。需要监控连接建立、消息传输的性能和错误，同时保护实际传输的内容。

## 具体技术实现

### 关键数据结构

```rust
// 日志导出目标（来自 targets.rs）
pub(crate) const OTEL_LOG_ONLY_TARGET: &str = "codex_otel.log_only";
pub(crate) const OTEL_TRACE_SAFE_TARGET: &str = "codex_otel.trace_safe";

// 事件记录宏（来自 events/shared.rs）
macro_rules! log_event {
    ($self:expr, $($fields:tt)*) => {{
        tracing::event!(
            target: $crate::targets::OTEL_LOG_ONLY_TARGET,  // 仅日志目标
            tracing::Level::INFO,
            $($fields)*
            // ... 元数据字段
        );
    }};
}

macro_rules! trace_event {
    ($self:expr, $($fields:tt)*) => {{
        tracing::event!(
            target: $crate::targets::OTEL_TRACE_SAFE_TARGET,  // 追踪安全目标
            tracing::Level::INFO,
            $($fields)*
            // ... 元数据字段（不含敏感信息）
        );
    }};
}

macro_rules! log_and_trace_event {
    (
        $self:expr,
        common: { $($common:tt)* },
        log: { $($log:tt)* },
        trace: { $($trace:tt)* },
    ) => {{
        log_event!($self, $($common)* $($log)*);
        trace_event!($self, $($common)* $($trace)*);
    }};
}
```

### 目标过滤机制（OtelProvider）

```rust
impl OtelProvider {
    pub fn log_export_filter(meta: &tracing::Metadata<'_>) -> bool {
        is_log_export_target(meta.target())
    }

    pub fn trace_export_filter(meta: &tracing::Metadata<'_>) -> bool {
        meta.is_span() || is_trace_safe_target(meta.target())
    }
}

// targets.rs
pub(crate) fn is_log_export_target(target: &str) -> bool {
    target.starts_with(OTEL_TARGET_PREFIX) && !is_trace_safe_target(target)
}

pub(crate) fn is_trace_safe_target(target: &str) -> bool {
    target.starts_with(OTEL_TRACE_SAFE_TARGET)
}
```

### 测试架构

每个测试遵循相同的模式：

```rust
#[test]n otel_export_routing_policy_routes_user_prompt_log_and_trace_events() {
    // 1. 创建内存导出器
    let log_exporter = InMemoryLogExporter::default();
    let logger_provider = SdkLoggerProvider::builder()
        .with_simple_exporter(log_exporter.clone())
        .build();
    let span_exporter = InMemorySpanExporter::default();
    let tracer_provider = SdkTracerProvider::builder()
        .with_simple_exporter(span_exporter.clone())
        .build();
    let tracer = tracer_provider.tracer("sink-split-test");

    // 2. 配置 tracing subscriber，应用过滤器
    let subscriber = tracing_subscriber::registry()
        .with(
            OpenTelemetryTracingBridge::new(&logger_provider)
                .with_filter(filter_fn(OtelProvider::log_export_filter)),
        )
        .with(
            tracing_opentelemetry::layer()
                .with_tracer(tracer)
                .with_filter(filter_fn(OtelProvider::trace_export_filter)),
        );

    // 3. 在 subscriber 上下文中执行被测操作
    tracing::subscriber::with_default(subscriber, || {
        tracing::callsite::rebuild_interest_cache();
        let manager = SessionTelemetry::new(...);
        // ... 执行操作
        manager.user_prompt(&[...]);
    });

    // 4. 强制刷新导出器
    logger_provider.force_flush().expect("flush logs");
    tracer_provider.force_flush().expect("flush traces");

    // 5. 验证日志包含敏感信息
    let logs = log_exporter.get_emitted_logs().expect("log export");
    let prompt_log = find_log_by_event_name(&logs, "codex.user_prompt");
    assert_eq!(prompt_log_attrs.get("prompt"), Some("super secret prompt"));

    // 6. 验证追踪不包含敏感信息
    let spans = span_exporter.get_finished_spans().expect("span export");
    let prompt_trace_attrs = span_event_attributes(prompt_trace_event);
    assert_eq!(prompt_trace_attrs.get("prompt_length"), Some("19"));
    assert!(!prompt_trace_attrs.contains_key("prompt"));
}
```

### 具体测试用例分析

#### 测试 1: User Prompt 路由 (`otel_export_routing_policy_routes_user_prompt_log_and_trace_events`)

**被测方法：** `SessionTelemetry::user_prompt`

**日志字段（含敏感信息）：**
- `prompt` - 完整提示文本
- `user.email` - 用户邮箱

**追踪字段（元数据）：**
- `prompt_length` - 提示长度
- `text_input_count` - 文本输入数量
- `image_input_count` - 图片输入数量
- `local_image_input_count` - 本地图片输入数量

**关键断言：**
```rust
// 日志包含敏感信息
assert_eq!(prompt_log_attrs.get("prompt"), Some("super secret prompt"));
assert_eq!(prompt_log_attrs.get("user.email"), Some("engineer@example.com"));

// 追踪不包含敏感信息
assert!(!prompt_trace_attrs.contains_key("prompt"));
assert!(!prompt_trace_attrs.contains_key("user.email"));
assert!(!prompt_trace_attrs.contains_key("user.account_id"));
```

#### 测试 2: Tool Result 路由 (`otel_export_routing_policy_routes_tool_result_log_and_trace_events`)

**被测方法：** `SessionTelemetry::tool_result_with_tags`

**日志字段（含敏感信息）：**
- `arguments` - 工具参数（可能包含敏感数据）
- `output` - 工具输出（可能包含敏感数据）
- `mcp_server` - MCP 服务器名称

**追踪字段（元数据）：**
- `arguments_length` - 参数长度
- `output_length` - 输出长度
- `output_line_count` - 输出行数
- `tool_origin` - 工具来源（builtin/mcp）
- `mcp_tool` - 是否为 MCP 工具

#### 测试 3: Auth Recovery 路由 (`otel_export_routing_policy_routes_auth_recovery_log_and_trace_events`)

**被测方法：** `SessionTelemetry::record_auth_recovery`

**特点：** 认证恢复事件在日志和追踪中导出**相同**的字段，因为这些都是元数据级别的信息，不包含敏感凭证。

**导出字段：**
- `auth.mode` - 认证模式
- `auth.step` - 恢复步骤
- `auth.outcome` - 恢复结果
- `auth.request_id` - 请求 ID
- `auth.cf_ray` - Cloudflare Ray ID
- `auth.error` - 错误类型
- `auth.error_code` - 错误代码
- `auth.state_changed` - 状态是否改变

#### 测试 4: API Request 认证可观测性 (`otel_export_routing_policy_routes_api_request_auth_observability`)

**被测方法：** `SessionTelemetry::conversation_starts` 和 `record_api_request`

**验证内容：**
- 环境变量存在性标记（`auth.env_*_present`）
- 认证头附加状态（`auth.header_attached`）
- 认证恢复相关信息（`auth.retry_after_unauthorized`, `auth.recovery_mode`）

#### 测试 5: WebSocket Connect 认证可观测性 (`otel_export_routing_policy_routes_websocket_connect_auth_observability`)

**被测方法：** `SessionTelemetry::record_websocket_connect`

**验证内容：**
- 连接持续时间、状态码、错误信息
- 认证头信息
- 连接复用标记（`auth.connection_reused`）

#### 测试 6: WebSocket Request 传输层可观测性 (`otel_export_routing_policy_routes_websocket_request_transport_observability`)

**被测方法：** `SessionTelemetry::record_websocket_request`

**验证内容：**
- 请求持续时间
- 错误消息
- 连接复用状态

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/otel/tests/suite/otel_export_routing_policy.rs` - 本测试文件

### 被测代码
- `codex-rs/otel/src/events/session_telemetry.rs` - `SessionTelemetry` 实现
- `codex-rs/otel/src/events/shared.rs` - 事件记录宏
- `codex-rs/otel/src/targets.rs` - 导出目标定义
- `codex-rs/otel/src/provider.rs` - `OtelProvider` 过滤器实现

### 依赖库
- `opentelemetry_sdk::logs::*` - OpenTelemetry 日志 SDK
- `opentelemetry_sdk::trace::*` - OpenTelemetry 追踪 SDK
- `tracing_subscriber` - Tracing 订阅者框架
- `opentelemetry_appender_tracing` - Tracing 到 OTel 日志的桥接
- `tracing_opentelemetry` - Tracing 到 OTel 追踪的桥接

## 依赖与外部交互

### 测试辅助函数

```rust
// 从 SdkLogRecord 提取属性为 BTreeMap
fn log_attributes(record: &SdkLogRecord) -> BTreeMap<String, String>;

// 从 Span Event 提取属性为 BTreeMap
fn span_event_attributes(event: &opentelemetry::trace::Event) -> BTreeMap<String, String>;

// 将 AnyValue 转换为字符串
fn any_value_to_string(value: &AnyValue) -> String;

// 按 event.name 查找日志
fn find_log_by_event_name<'a>(logs: &'a [...], event_name: &str) -> &'a LogDataWithResource;

// 按 event.name 查找 Span Event
fn find_span_event_by_name_attr<'a>(events: &'a [...], event_name: &str) -> &'a Event;

// 构造 AuthEnvTelemetryMetadata
fn auth_env_metadata() -> AuthEnvTelemetryMetadata;
```

### 外部协议类型

```rust
use codex_protocol::protocol::AskForApproval;
use codex_protocol::protocol::SandboxPolicy;
use codex_protocol::protocol::SessionSource;
use codex_protocol::user_input::UserInput;
use codex_protocol::config_types::ReasoningSummary;
```

## 风险、边界与改进建议

### 潜在风险

1. **过滤器配置错误**
   - 如果 `log_export_filter` 或 `trace_export_filter` 配置错误，可能导致敏感信息泄露到追踪系统
   - 建议：添加集成测试验证过滤器行为

2. **目标字符串硬编码**
   - `codex_otel.log_only` 和 `codex_otel.trace_safe` 是硬编码字符串
   - 如果重构时忘记同步更新，会导致路由失效
   - 建议：使用常量定义并在测试中引用

3. **宏展开复杂性**
   - `log_and_trace_event!` 宏的复杂性可能导致编译错误难以调试
   - 建议：添加更多文档注释和示例

### 边界情况

1. **空输入处理**
   - `user_prompt(&[])` - 空输入列表
   - 测试中未覆盖，但实现中已处理

2. **超大负载**
   - 工具输出可能非常大（如日志文件）
   - 当前实现会完整记录到日志，可能导致内存问题

3. **特殊字符**
   - 提示文本中的特殊字符（换行、Unicode）在属性中的处理

### 改进建议

1. **增强测试覆盖**
   ```rust
   // 建议添加：空输入测试
   #[test]
   fn otel_export_routing_policy_handles_empty_input() { ... }
   
   // 建议添加：超大负载测试
   #[test]
   fn otel_export_routing_policy_handles_large_output() { ... }
   ```

2. **性能优化**
   - 考虑对超大输出进行截断，只记录前 N 行或前 N 个字符

3. **安全增强**
   - 添加敏感数据检测机制，自动识别可能的密码、密钥模式
   - 即使通过日志导出，也进行脱敏处理

4. **可观测性增强**
   - 记录日志/追踪分离的统计信息（如分离事件数量）
   - 便于监控分离策略的有效性

5. **代码组织**
   - 测试文件较长（852 行），可以考虑按功能拆分为多个文件：
     - `otel_export_routing_policy/user_prompt.rs`
     - `otel_export_routing_policy/tool_result.rs`
     - `otel_export_routing_policy/auth.rs`
