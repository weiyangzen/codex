# codex-rs/otel/src/events/shared.rs 研究文档

## 场景与职责

`shared.rs` 是 `codex-otel` crate 中事件记录的基础设施模块，提供声明式宏来简化结构化日志和追踪事件的记录。该模块的核心职责是：

1. **标准化事件格式**: 确保所有遥测事件包含一致的元数据字段
2. **分离日志和追踪**: 支持同时向日志后端和追踪系统发送事件，但内容可以差异化
3. **时间戳生成**: 提供统一的 UTC 时间戳格式

该模块被 `session_telemetry.rs` 大量使用，是 Codex 遥测系统的底层构建块。

## 功能点目的

### 1. 声明式宏 `log_event!`

用于记录仅发送到日志后端的事件：

```rust
log_event!(
    self,
    event.name = "codex.user_prompt",
    prompt_length = %prompt.chars().count(),
    prompt = %prompt_to_log,
);
```

特点：
- 目标：`OTEL_LOG_ONLY_TARGET` (`codex_otel.log_only`)
- 级别：`INFO`
- 自动注入标准字段：时间戳、会话ID、应用版本等

### 2. 声明式宏 `trace_event!`

用于记录发送到追踪系统的事件（可能包含更详细的结构化数据）：

```rust
trace_event!(
    self,
    event.name = "codex.user_prompt",
    prompt_length = %prompt.chars().count(),
    text_input_count = text_input_count as i64,
    image_input_count = image_input_count as i64,
);
```

特点：
- 目标：`OTEL_TRACE_SAFE_TARGET` (`codex_otel.trace_safe`)
- 级别：`INFO`
- 自动注入标准字段（不含用户敏感信息如 account_id/email）

### 3. 组合宏 `log_and_trace_event!`

同时记录日志和追踪事件，支持差异化字段：

```rust
log_and_trace_event!(
    self,
    common: {
        event.name = "codex.conversation_starts",
        provider_name = %provider_name,
    },
    log: {
        mcp_servers = mcp_servers.join(", "),
        active_profile = active_profile,
    },
    trace: {
        mcp_server_count = mcp_servers.len() as i64,
        active_profile_present = active_profile.is_some(),
    },
);
```

设计意图：
- `common`: 两个目标都包含的字段
- `log`: 仅日志目标包含的字段（可包含详细文本）
- `trace`: 仅追踪目标包含的字段（倾向于结构化数值）

### 4. 时间戳生成

```rust
pub(crate) fn timestamp() -> String {
    Utc::now().to_rfc3339_opts(SecondsFormat::Millis, true)
}
```

- 格式：RFC 3339 带毫秒
- 使用 UTC 时区（`true` 参数表示使用 `Z` 后缀而非 `+00:00`）

## 具体技术实现

### 宏实现详解

#### `log_event!` 宏

```rust
macro_rules! log_event {
    ($self:expr, $($fields:tt)*) => {{
        tracing::event!(
            target: $crate::targets::OTEL_LOG_ONLY_TARGET,
            tracing::Level::INFO,
            $($fields)*
            event.timestamp = %$crate::events::shared::timestamp(),
            conversation.id = %$self.metadata.conversation_id,
            app.version = %$self.metadata.app_version,
            auth_mode = $self.metadata.auth_mode,
            originator = %$self.metadata.originator,
            user.account_id = $self.metadata.account_id,
            user.email = $self.metadata.account_email,
            terminal.type = %$self.metadata.terminal_type,
            model = %$self.metadata.model,
            slug = %$self.metadata.slug,
        );
    }};
}
```

关键点：
- 使用 `$crate::` 前缀确保宏在 crate 外部使用时路径正确
- `%` 表示使用 `Display` trait 格式化
- 包含用户敏感信息（account_id, email）仅发送到日志

#### `trace_event!` 宏

```rust
macro_rules! trace_event {
    ($self:expr, $($fields:tt)*) => {{
        tracing::event!(
            target: $crate::targets::OTEL_TRACE_SAFE_TARGET,
            tracing::Level::INFO,
            $($fields)*
            event.timestamp = %$crate::events::shared::timestamp(),
            conversation.id = %$self.metadata.conversation_id,
            app.version = %$self.metadata.app_version,
            auth_mode = $self.metadata.auth_mode,
            originator = %$self.metadata.originator,
            terminal.type = %$self.metadata.terminal_type,
            model = %$self.metadata.model,
            slug = %$self.metadata.slug,
        );
    }};
}
```

与 `log_event!` 的区别：
- 目标不同：`OTEL_TRACE_SAFE_TARGET`
- **不包含** `user.account_id` 和 `user.email`
- 设计用于可能导出到第三方追踪系统的场景

#### `log_and_trace_event!` 宏

```rust
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

实现策略：
- 使用重复模式匹配 (`$($common:tt)*`) 捕获任意 token
- 宏展开后分别调用两个子宏
- 共享 `common` 部分，差异化 `log` 和 `trace` 部分

### 模块导出

```rust
pub(crate) use log_and_trace_event;
pub(crate) use log_event;
pub(crate) use trace_event;
```

- `pub(crate)` 限制仅在 `codex-otel` crate 内部使用
- 通过 `session_telemetry.rs` 间接暴露功能给外部

## 关键代码路径与文件引用

### 文件关系图

```
codex-rs/otel/src/
├── events/
│   ├── mod.rs
│   ├── session_telemetry.rs      # 主要使用方
│   └── shared.rs                 # 本文件
├── targets.rs                    # 目标常量定义
└── lib.rs
```

### 依赖关系

```
shared.rs
  ├── 依赖: chrono (时间戳)
  ├── 依赖: targets.rs (OTEL_LOG_ONLY_TARGET, OTEL_TRACE_SAFE_TARGET)
  └── 被依赖: session_telemetry.rs (通过 mod.rs)
```

### 目标常量定义

在 `targets.rs` 中：

```rust
pub(crate) const OTEL_TARGET_PREFIX: &str = "codex_otel";
pub(crate) const OTEL_LOG_ONLY_TARGET: &str = "codex_otel.log_only";
pub(crate) const OTEL_TRACE_SAFE_TARGET: &str = "codex_otel.trace_safe";

pub(crate) fn is_log_export_target(target: &str) -> bool {
    target.starts_with(OTEL_TARGET_PREFIX) && !is_trace_safe_target(target)
}

pub(crate) fn is_trace_safe_target(target: &str) -> bool {
    target.starts_with(OTEL_TRACE_SAFE_TARGET)
}
```

### 使用示例

在 `session_telemetry.rs` 中的典型使用模式：

```rust
// 简单事件
pub fn tool_decision(&self, tool_name: &str, call_id: &str, decision: &ReviewDecision, source: ToolDecisionSource) {
    log_event!(
        self,
        event.name = "codex.tool_decision",
        tool_name = %tool_name,
        call_id = %call_id,
        decision = %decision.clone().to_string().to_lowercase(),
        source = %source.to_string(),
    );
}

// 复杂事件（差异化日志和追踪）
pub fn conversation_starts(&self, ...) {
    log_and_trace_event!(
        self,
        common: {
            event.name = "codex.conversation_starts",
            provider_name = %provider_name,
            // ...
        },
        log: {
            mcp_servers = mcp_servers.join(", "),  // 详细列表
        },
        trace: {
            mcp_server_count = mcp_servers.len() as i64,  // 结构化计数
        },
    );
}
```

## 依赖与外部交互

### 外部依赖

| Crate | 用途 |
|-------|------|
| `chrono` | UTC 时间戳生成 |
| `tracing` | 通过宏展开后的 `tracing::event!` 调用 |

### 内部依赖

- `targets.rs`: 提供目标字符串常量
- `session_telemetry.rs` 的 `SessionTelemetryMetadata`: 宏展开后访问其字段

### 与 tracing_subscriber 的集成

在 `provider.rs` 中配置过滤：

```rust
pub fn logger_layer<S>(&self) -> Option<impl Layer<S> + Send + Sync> {
    self.logger.as_ref().map(|logger| {
        OpenTelemetryTracingBridge::new(logger).with_filter(
            tracing_subscriber::filter::filter_fn(OtelProvider::log_export_filter),
        )
    })
}

pub fn log_export_filter(meta: &tracing::Metadata<'_>) -> bool {
    is_log_export_target(meta.target())
}
```

## 风险、边界与改进建议

### 当前限制

1. **宏的复杂性**: 使用 `tt` (token tree) 重复模式，编译时开销较大
2. **字段注入硬编码**: 标准字段列表在宏定义中硬编码，修改需要更新所有宏
3. **错误处理缺失**: 宏内部不处理 `tracing::event!` 可能的失败

### 潜在风险

1. **字段名冲突**: 如果调用方提供的字段名与自动注入的字段冲突，会导致编译错误
   ```rust
   // 这将导致编译错误：重复字段
   log_event!(self, conversation.id = "custom");
   ```

2. **格式化开销**: 每个事件都调用 `timestamp()` 生成时间戳，频繁事件可能影响性能

3. **敏感信息泄露风险**: 
   - `log_event!` 包含 `user.account_id` 和 `user.email`
   - 调用方需要确保日志后端的安全性

### 边界情况

1. **空字段处理**: `tracing` 会自动处理 `None` 值的字段
2. **长字段值**: 没有长度限制，可能导致日志过大
3. **特殊字符**: 依赖 `tracing` 的默认转义行为

### 改进建议

1. **字段名空间隔离**:
   ```rust
   // 使用前缀避免冲突
   auto.conversation.id = %$self.metadata.conversation_id,
   ```

2. **时间戳缓存**:
   ```rust
   // 在毫秒级批量事件中复用时间戳
   thread_local! {
       static LAST_TIMESTAMP: RefCell<Option<(Instant, String)>> = RefCell::new(None);
   }
   ```

3. **字段验证**:
   ```rust
   // 添加编译期字段名检查（需要过程宏）
   #[derive(EventFields)]
   struct ConversationStarts {
       provider_name: String,
       // ...
   }
   ```

4. **文档和示例**:
   - 添加更多使用示例
   - 说明 `log` 和 `trace` 字段选择的指导原则

5. **性能优化**:
   - 考虑使用 `tracing::field::debug` 替代 `%` 格式化以减少分配
   - 对静态字符串使用 `tracing::field::display`

### 替代方案考虑

对于更复杂的场景，可以考虑：

1. **过程宏**: 提供 `#[derive(TelemetryEvent)]` 自动实现事件记录
2. **Builder 模式**: 替代宏，提供更好的 IDE 支持和类型安全
3. **结构化日志类型**: 使用 `serde::Serialize` 类型替代自由字段

```rust
// 可能的未来 API
#[derive(TelemetryEvent)]
#[event(name = "codex.conversation_starts")]
struct ConversationStarts {
    provider_name: String,
    #[telemetry(log_only)]
    mcp_servers: String,
    #[telemetry(trace_only)]
    mcp_server_count: i64,
}
```
