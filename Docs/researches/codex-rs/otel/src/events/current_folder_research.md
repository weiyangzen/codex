# DIR codex-rs/otel/src/events 研究文档

## 场景与职责

`codex-rs/otel/src/events` 目录是 Codex OpenTelemetry (OTEL) 集成 crate 中的**会话事件遥测核心模块**，负责：

1. **会话级业务事件发射**：通过 `SessionTelemetry` 提供统一的会话事件记录接口
2. **结构化日志与追踪**：区分仅日志 (`log_only`) 和追踪安全 (`trace_safe`) 的事件目标
3. **指标收集与上报**：将业务事件转换为 OTEL 指标（counter/histogram/duration）
4. **运行时指标汇总**：支持会话级别的性能指标聚合（工具调用、API 调用、流事件等）

该模块在整个 Codex 架构中处于**数据收集层**，向上为 `codex-core` 提供遥测 API，向下通过 `opentelemetry_sdk` 将数据导出到 OTLP 端点。

### 典型使用场景

- **会话启动**：记录 `codex.conversation_starts` 事件，包含认证环境、模型配置、沙箱策略等
- **用户输入**：记录 `codex.user_prompt` 事件，支持敏感内容脱敏（`[REDACTED]`）
- **工具调用**：记录 `codex.tool_result` 事件，包含执行时长、成功状态、MCP 服务器来源
- **API 请求**：记录 `codex.api_request` 和 WebSocket 相关事件，用于性能监控
- **SSE 流事件**：记录 `codex.sse_event` 事件，追踪响应流的生命周期

---

## 功能点目的

### 1. SessionTelemetry - 会话遥测管理器

**文件**: `session_telemetry.rs`

核心结构体，每个 Codex 会话拥有一个实例，封装：
- `SessionTelemetryMetadata`: 会话元数据（conversation_id、model、auth_mode 等）
- `MetricsClient`: 可选的指标客户端，用于上报 OTEL 指标
- 元数据标签控制（`metrics_use_metadata_tags`）

**关键方法分类**:

| 类别 | 方法 | 目的 |
|------|------|------|
| 构造 | `new()` | 创建会话遥测实例，绑定会话元数据 |
| 配置 | `with_metrics()`, `with_auth_env()`, `with_model()` | 链式配置指标客户端和元数据 |
| 指标 | `counter()`, `histogram()`, `record_duration()`, `start_timer()` | 直接记录指标数据 |
| 会话事件 | `conversation_starts()`, `user_prompt()` | 记录会话生命周期事件 |
| API 事件 | `record_api_request()`, `log_request()` | 记录 HTTP/API 调用事件 |
| WebSocket | `record_websocket_connect()`, `record_websocket_request()`, `record_websocket_event()` | 记录 WebSocket 连接和消息事件 |
| SSE 事件 | `log_sse_event()`, `sse_event_completed()` | 记录 Server-Sent Events 事件 |
| 工具调用 | `log_tool_result_with_tags()`, `tool_result_with_tags()`, `tool_decision()` | 记录工具执行结果和审批决策 |
| 认证恢复 | `record_auth_recovery()` | 记录认证失败恢复流程 |
| 运行时 | `snapshot_metrics()`, `runtime_metrics_summary()`, `reset_runtime_metrics()` | 获取会话性能快照 |

### 2. 事件宏系统 - 统一事件发射

**文件**: `shared.rs`

提供三个宏实现统一的事件发射模式：

```rust
// 仅记录日志（可能包含敏感信息）
log_event!(self, event.name = "...", ...);

// 仅记录追踪（脱敏，安全用于分布式追踪）
trace_event!(self, event.name = "...", ...);

// 同时记录日志和追踪
log_and_trace_event!(self, 
    common: { /* 共享字段 */ },
    log: { /* 仅日志字段 */ },
    trace: { /* 仅追踪字段 */ }
);
```

**设计目的**：
- **隐私合规**：`log_event` 可包含用户敏感数据（如 prompt 内容），`trace_event` 必须脱敏
- **目标分离**：通过不同的 `tracing::target` 将事件路由到不同的 OTEL 导出器
- **自动注入元数据**：所有事件自动附加 `conversation.id`, `app.version`, `auth_mode`, `model` 等字段

### 3. 目标常量定义

**文件**: `../targets.rs`

```rust
pub(crate) const OTEL_TARGET_PREFIX: &str = "codex_otel";
pub(crate) const OTEL_LOG_ONLY_TARGET: &str = "codex_otel.log_only";
pub(crate) const OTEL_TRACE_SAFE_TARGET: &str = "codex_otel.trace_safe";
```

用于 `tracing_subscriber` 的过滤器配置，实现：
- `is_log_export_target()`: 判断事件是否应导出到日志系统
- `is_trace_safe_target()`: 判断事件是否安全用于追踪系统

---

## 具体技术实现

### 关键数据结构

#### SessionTelemetryMetadata
```rust
pub struct SessionTelemetryMetadata {
    pub(crate) conversation_id: ThreadId,     // 会话唯一标识
    pub(crate) auth_mode: Option<String>,     // 认证模式 (api_key/chatgpt)
    pub(crate) auth_env: AuthEnvTelemetryMetadata, // 认证环境变量状态
    pub(crate) account_id: Option<String>,    // 用户账号 ID
    pub(crate) account_email: Option<String>, // 用户邮箱
    pub(crate) originator: String,            // 发起方 (codex_cli/codex_tui)
    pub(crate) service_name: Option<String>,  // 服务名称（用于 metrics）
    pub(crate) session_source: String,        // 会话来源 (cli/tui/exec)
    pub(crate) model: String,                 // 模型名称
    pub(crate) slug: String,                  // 模型 slug
    pub(crate) log_user_prompts: bool,        // 是否记录用户 prompt
    pub(crate) app_version: &'static str,     // 应用版本
    pub(crate) terminal_type: String,         // 终端类型
}
```

#### AuthEnvTelemetryMetadata
```rust
pub struct AuthEnvTelemetryMetadata {
    pub openai_api_key_env_present: bool,     // OPENAI_API_KEY 是否存在
    pub codex_api_key_env_present: bool,      // CODEX_API_KEY 是否存在
    pub codex_api_key_env_enabled: bool,      // CODEX_API_KEY 是否启用
    pub provider_env_key_name: Option<String>, // 自定义 provider key 名称
    pub provider_env_key_present: Option<bool>, // 自定义 provider key 是否存在
    pub refresh_token_url_override_present: bool, // 刷新 token URL 是否被覆盖
}
```

### 关键流程

#### 1. 会话启动事件流程 (`conversation_starts`)

```
Core::Codex::start_conversation()
  └── session_telemetry.conversation_starts()
      ├── 记录 auth 环境变量状态
      ├── 记录 reasoning_effort / reasoning_summary
      ├── 记录 context_window / auto_compact_token_limit
      ├── 记录 approval_policy / sandbox_policy
      ├── 记录 mcp_servers / active_profile
      └── 通过 log_and_trace_event! 发射事件
```

#### 2. 工具调用指标流程 (`log_tool_result_with_tags`)

```
ToolRegistry::invoke()
  └── otel.log_tool_result_with_tags(tool_name, call_id, arguments, ...)
      ├── 启动计时器 (Instant::now())
      ├── 执行工具 handler
      ├── 计算执行时长
      ├── 记录指标: codex.tool.call (counter)
      ├── 记录指标: codex.tool.call.duration_ms (histogram)
      ├── 记录日志事件: codex.tool_result (含完整参数和输出)
      └── 记录追踪事件: codex.tool_result (仅元数据)
```

#### 3. API 请求指标流程 (`record_api_request`)

```
ModelClient::send_http_request()
  └── session_telemetry.record_api_request()
      ├── 计算请求耗时
      ├── 判断成功/失败状态
      ├── 记录指标: codex.api_request (counter, 按 status/success 分桶)
      ├── 记录指标: codex.api_request.duration_ms (histogram)
      └── 记录事件: codex.api_request (含详细 auth 信息)
```

#### 4. WebSocket 事件处理流程 (`record_websocket_event`)

```
ModelClient::handle_websocket_response()
  └── session_telemetry.record_websocket_event()
      ├── 解析消息类型 (Text/Binary/Ping/Pong/Close)
      ├── 特殊处理 responsesapi.websocket_timing 消息
      │   └── 提取并记录引擎级性能指标 (TTFT/TBT/overhead)
      ├── 记录指标: codex.websocket.event (counter)
      ├── 记录指标: codex.websocket.event.duration_ms (histogram)
      └── 记录事件: codex.websocket_event
```

#### 5. SSE 事件处理流程 (`log_sse_event`)

```
ModelClient::process_sse_stream()
  └── session_telemetry.log_sse_event()
      ├── 处理 response.created / output_item.done 等事件
      ├── 特殊处理 response.failed 事件
      ├── 记录指标: codex.sse_event (counter)
      ├── 记录指标: codex.sse_event.duration_ms (histogram)
      └── 记录事件: codex.sse_event
```

### 指标名称常量

**文件**: `../metrics/names.rs`

| 常量 | 值 | 用途 |
|------|-----|------|
| `TOOL_CALL_COUNT_METRIC` | `codex.tool.call` | 工具调用次数 |
| `TOOL_CALL_DURATION_METRIC` | `codex.tool.call.duration_ms` | 工具调用耗时 |
| `API_CALL_COUNT_METRIC` | `codex.api_request` | API 请求次数 |
| `API_CALL_DURATION_METRIC` | `codex.api_request.duration_ms` | API 请求耗时 |
| `SSE_EVENT_COUNT_METRIC` | `codex.sse_event` | SSE 事件次数 |
| `SSE_EVENT_DURATION_METRIC` | `codex.sse_event.duration_ms` | SSE 事件处理耗时 |
| `WEBSOCKET_REQUEST_*` | `codex.websocket.request*` | WebSocket 请求指标 |
| `WEBSOCKET_EVENT_*` | `codex.websocket.event*` | WebSocket 事件指标 |
| `RESPONSES_API_*` | `codex.responses_api_*` | Responses API 性能指标 |

### 元数据标签

**文件**: `../metrics/tags.rs`

会话指标自动附加的标签：
- `app.version`: 应用版本
- `auth_mode`: 认证模式
- `session_source`: 会话来源 (cli/tui/exec)
- `originator`: 发起方标识
- `service_name`: 服务名称（可选）
- `model`: 模型名称

---

## 关键代码路径与文件引用

### 本目录文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `mod.rs` | 2 | 模块导出 |
| `session_telemetry.rs` | 1093 | 核心会话遥测实现 |
| `shared.rs` | 60 | 事件宏定义和时间戳工具 |

### 调用方（上游）

| 文件 | 使用方式 |
|------|----------|
| `codex-rs/core/src/codex.rs` | 创建 SessionTelemetry，调用 `conversation_starts()`, `user_prompt()` |
| `codex-rs/core/src/client.rs` | 调用 `record_api_request()`, `log_sse_event()`, `record_websocket_*()` |
| `codex-rs/core/src/tools/registry.rs` | 调用 `log_tool_result_with_tags()`, `tool_result_with_tags()` |
| `codex-rs/core/src/tasks/mod.rs` | 调用 `counter()`, `histogram()` 记录任务指标 |
| `codex-rs/core/src/memories/phase1.rs` | 调用 `counter()`, `histogram()` 记录记忆系统指标 |
| `codex-rs/tui/src/app.rs` | 创建 SessionTelemetry 并传递给 Core |
| `codex-rs/tui_app_server/src/app.rs` | 类似 TUI 的遥测初始化 |

### 被调用方（下游）

| 文件 | 职责 |
|------|------|
| `../metrics/client.rs` | `MetricsClient` 实现 OTEL 指标上报 |
| `../metrics/names.rs` | 指标名称常量定义 |
| `../metrics/tags.rs` | 会话标签生成 |
| `../metrics/runtime_metrics.rs` | 运行时指标汇总 (`RuntimeMetricsSummary`) |
| `../targets.rs` | 事件目标常量 |
| `../provider.rs` | `OtelProvider` 管理 OTEL 导出器生命周期 |

---

## 依赖与外部交互

### 外部 crate 依赖

| crate | 用途 |
|-------|------|
| `opentelemetry` | OTEL API 基础类型（KeyValue, metrics 等） |
| `opentelemetry_sdk` | SDK 实现（MeterProvider, ResourceMetrics 等） |
| `opentelemetry_otlp` | OTLP 导出器（HTTP/gRPC） |
| `tracing` | 结构化日志和 span 追踪 |
| `codex_protocol` | ThreadId, SessionSource, ResponseEvent 等协议类型 |
| `codex_api` | ApiError, ResponseEvent |
| `eventsource_stream` | SSE 事件流解析 |
| `tokio_tungstenite` | WebSocket 消息类型 |
| `serde_json` | JSON 解析（WebSocket 消息体） |

### 与 OpenTelemetry 的集成

```
┌─────────────────────────────────────────────────────────────┐
│                     SessionTelemetry                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ log_event!  │  │trace_event! │  │ 指标方法 (counter)   │  │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘  │
│         │                │                    │             │
│         ▼                ▼                    ▼             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              tracing::event! / Span                  │  │
│  └──────────────────────────────────────────────────────┘  │
│                         │                                   │
└─────────────────────────┼───────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────┐
│              OtelProvider (provider.rs)                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ SdkLogger    │  │SdkTracer     │  │MetricsClient │      │
│  │ Provider     │  │Provider      │  │              │      │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘      │
│         │                 │                  │              │
│         ▼                 ▼                  ▼              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │           OTLP Exporter (HTTP/gRPC)                  │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 风险、边界与改进建议

### 已知风险

1. **敏感数据泄露风险**
   - `log_user_prompts` 配置错误可能导致用户 prompt 被记录到日志系统
   - `user_prompt()` 方法根据 `log_user_prompts` 决定是否脱敏，但依赖调用方正确配置

2. **指标标签爆炸**
   - `tool_result_with_tags` 接受动态 `extra_tags`，如果标签值未规范化（如包含用户输入），可能导致高基数问题
   - `sanitize_metric_tag_value` 函数用于清理标签值，但依赖调用方正确使用

3. **WebSocket 消息解析失败**
   - `record_websocket_event` 中的 JSON 解析失败会记录为 `parse_error` 事件，但不会阻止业务流程
   - 如果 `responsesapi.websocket_timing` 消息格式变更，相关指标将停止更新

4. **MetricsClient 未初始化**
   - 当 `metrics` 为 `None` 时，指标方法静默返回（仅记录 warning），可能导致监控盲区

### 边界条件

1. **计时器溢出**
   - `duration_from_ms_value` 函数对非有限值和负值有防护，但毫秒值超过 `u64::MAX` 会被截断

2. **并发安全**
   - `MetricsClientInner` 使用 `Mutex<HashMap>` 缓存 counter/histogram，高并发场景可能成为瓶颈
   - `SessionTelemetry` 本身是无状态包装器（`Clone`），可安全跨任务共享

3. **生命周期管理**
   - `shutdown_metrics()` 必须在会话结束时调用以确保指标刷新
   - `Drop` 实现提供了兜底，但不保证在进程异常退出时完成刷新

### 改进建议

1. **增强可观测性**
   - 为 `record_websocket_event` 添加更详细的错误分类（如区分 JSON 解析错误和 WebSocket 协议错误）
   - 添加指标记录失败的计数器，用于监控遥测系统自身的健康状态

2. **性能优化**
   - 考虑使用 `dashmap` 替换 `Mutex<HashMap>` 减少锁竞争
   - 对高频事件（如 SSE 流中的每个 delta）考虑批量上报或采样

3. **配置增强**
   - 支持按事件类型配置采样率（如只记录 1% 的 SSE 事件）
   - 支持动态调整 `log_user_prompts` 而不需要重启会话

4. **测试覆盖**
   - 当前测试主要集中在 `metrics` 模块，`session_telemetry.rs` 本身缺乏单元测试
   - 建议为 `record_websocket_event` 的复杂匹配逻辑添加测试

5. **文档完善**
   - 各事件字段的语义文档分散在代码中，建议集中维护事件 schema 文档
   - `AuthEnvTelemetryMetadata` 的字段含义（如 `refresh_token_url_override_present`）缺乏注释

---

## 附录：事件类型速查

| 事件名称 | 目标 | 关键字段 | 触发场景 |
|----------|------|----------|----------|
| `codex.conversation_starts` | log+trace | provider_name, auth.*, reasoning_effort, approval_policy | 会话启动 |
| `codex.user_prompt` | log+trace | prompt_length, prompt (可能脱敏), text/image_input_count | 用户提交输入 |
| `codex.tool_result` | log+trace | tool_name, call_id, duration_ms, success, output | 工具执行完成 |
| `codex.tool_decision` | log | tool_name, call_id, decision, source | 工具审批决策 |
| `codex.api_request` | log+trace | duration_ms, http.response.status_code, auth.* | API 请求完成 |
| `codex.websocket_connect` | log+trace | duration_ms, success, auth.* | WebSocket 连接建立 |
| `codex.websocket_request` | log+trace | duration_ms, success | WebSocket 请求发送 |
| `codex.websocket_event` | log+trace | event.kind, duration_ms, success | WebSocket 消息接收 |
| `codex.sse_event` | log+trace | event.kind, duration_ms, error.message | SSE 事件接收 |
| `codex.auth_recovery` | log+trace | auth.mode, auth.step, auth.outcome | 认证恢复流程 |

---

*文档生成时间: 2026-03-21*
*基于 commit: 当前工作目录状态*
