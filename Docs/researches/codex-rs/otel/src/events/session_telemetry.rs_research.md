# codex-rs/otel/src/events/session_telemetry.rs 研究文档

## 场景与职责

`SessionTelemetry` 是 Codex OpenTelemetry 集成中的核心组件，负责在会话生命周期内收集和报告各类遥测事件。它作为业务逻辑与底层指标/日志系统之间的桥梁，提供统一的接口来记录：

- **会话生命周期事件**: 会话开始、配置信息
- **API 请求指标**: HTTP/WebSocket 请求的延迟、成功率
- **流式事件**: SSE (Server-Sent Events) 和 WebSocket 事件的处理情况
- **工具调用**: 工具执行的结果和性能指标
- **用户交互**: 用户输入和工具决策

该组件被设计为会话级别的单例，在 Codex 会话开始时创建，并在整个会话期间复用。

## 功能点目的

### 1. 会话元数据管理

```rust
pub struct SessionTelemetryMetadata {
    pub(crate) conversation_id: ThreadId,
    pub(crate) auth_mode: Option<String>,
    pub(crate) auth_env: AuthEnvTelemetryMetadata,
    pub(crate) account_id: Option<String>,
    pub(crate) account_email: Option<String>,
    pub(crate) originator: String,
    pub(crate) service_name: Option<String>,
    pub(crate) session_source: String,
    pub(crate) model: String,
    pub(crate) slug: String,
    pub(crate) log_user_prompts: bool,
    pub(crate) app_version: &'static str,
    pub(crate) terminal_type: String,
}
```

元数据用于：
- 标识会话来源（CLI、TUI、App Server 等）
- 关联用户账户信息
- 记录认证模式和环境
- 追踪模型使用情况

### 2. 指标收集

支持的指标类型：
- **计数器 (Counter)**: API 调用次数、工具调用次数、事件计数
- **直方图 (Histogram)**: 请求延迟、事件处理时间
- **计时器 (Timer)**: 自动记录代码块执行时间

### 3. 事件分类

| 事件类别 | 方法 | 用途 |
|---------|------|------|
| 会话事件 | `conversation_starts` | 记录会话初始化配置 |
| API 请求 | `log_request`, `record_api_request` | HTTP 请求指标和日志 |
| WebSocket | `record_websocket_connect`, `record_websocket_request`, `record_websocket_event` | WebSocket 连接和消息 |
| 认证恢复 | `record_auth_recovery` | 认证失败后的恢复流程 |
| 流式事件 | `log_sse_event`, `sse_event_completed` | SSE 流处理 |
| 用户输入 | `user_prompt` | 用户提示记录（支持脱敏） |
| 工具调用 | `log_tool_result_with_tags`, `tool_decision` | 工具执行和审批决策 |

## 具体技术实现

### 数据结构

#### AuthEnvTelemetryMetadata

```rust
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct AuthEnvTelemetryMetadata {
    pub openai_api_key_env_present: bool,
    pub codex_api_key_env_present: bool,
    pub codex_api_key_env_enabled: bool,
    pub provider_env_key_name: Option<String>,
    pub provider_env_key_present: Option<bool>,
    pub refresh_token_url_override_present: bool,
}
```

用于记录认证环境状态，帮助诊断认证相关问题。

#### SessionTelemetry

```rust
pub struct SessionTelemetry {
    pub(crate) metadata: SessionTelemetryMetadata,
    pub(crate) metrics: Option<MetricsClient>,
    pub(crate) metrics_use_metadata_tags: bool,
}
```

- `metadata`: 会话级别的静态元数据
- `metrics`: 可选的指标客户端（当 OTEL 禁用时为 None）
- `metrics_use_metadata_tags`: 控制是否自动添加元数据标签到指标

### 核心方法实现

#### 构造与配置

```rust
impl SessionTelemetry {
    pub fn new(
        conversation_id: ThreadId,
        model: &str,
        slug: &str,
        account_id: Option<String>,
        account_email: Option<String>,
        auth_mode: Option<TelemetryAuthMode>,
        originator: String,
        log_user_prompts: bool,
        terminal_type: String,
        session_source: SessionSource,
    ) -> SessionTelemetry
    
    // Builder 模式方法
    pub fn with_auth_env(mut self, auth_env: AuthEnvTelemetryMetadata) -> Self
    pub fn with_model(mut self, model: &str, slug: &str) -> Self
    pub fn with_metrics_service_name(mut self, service_name: &str) -> Self
    pub fn with_metrics(mut self, metrics: MetricsClient) -> Self
    pub fn with_metrics_without_metadata_tags(mut self, metrics: MetricsClient) -> Self
}
```

#### 指标记录方法

```rust
pub fn counter(&self, name: &str, inc: i64, tags: &[(&str, &str)])
pub fn histogram(&self, name: &str, value: i64, tags: &[(&str, &str)])
pub fn record_duration(&self, name: &str, duration: Duration, tags: &[(&str, &str)])
pub fn start_timer(&self, name: &str, tags: &[(&str, &str)]) -> Result<Timer, MetricsError>
```

所有指标方法都：
1. 检查 `metrics` 是否启用
2. 合并元数据标签（如果启用）
3. 调用底层 `MetricsClient`
4. 错误时记录警告日志（不 panic）

#### 标签合并逻辑

```rust
fn tags_with_metadata<'a>(
    &'a self,
    tags: &'a [(&'a str, &'a str)],
) -> MetricsResult<Vec<(&'a str, &'a str)>> {
    let mut merged = self.metadata_tag_refs()?;
    merged.extend(tags.iter().copied());
    Ok(merged)
}
```

自动注入的标签包括：
- `auth_mode`: 认证模式
- `session_source`: 会话来源（cli/tui/exec）
- `originator`: 发起者标识
- `service_name`: 服务名称
- `model`: 模型名称
- `app.version`: 应用版本

### 事件记录宏的使用

`session_telemetry.rs` 大量使用 `shared.rs` 提供的宏：

```rust
// 同时记录日志和追踪
log_and_trace_event!(
    self,
    common: {
        event.name = "codex.conversation_starts",
        provider_name = %provider_name,
        // ... 更多字段
    },
    log: {
        mcp_servers = mcp_servers.join(", "),
    },
    trace: {
        mcp_server_count = mcp_servers.len() as i64,
    },
);
```

宏展开后会：
1. 调用 `tracing::event!` 记录到 `OTEL_LOG_ONLY_TARGET`（日志专用）
2. 调用 `tracing::event!` 记录到 `OTEL_TRACE_SAFE_TARGET`（追踪安全）
3. 自动注入标准字段：时间戳、会话ID、应用版本等

### WebSocket 时间指标解析

特殊处理 `responsesapi.websocket_timing` 事件：

```rust
fn record_responses_websocket_timing_metrics(&self, value: &serde_json::Value) {
    let timing_metrics = value.get(RESPONSES_WEBSOCKET_TIMING_METRICS_FIELD);
    
    // 解析多个时间指标
    let overhead_value = timing_metrics.and_then(|v| v.get(RESPONSES_API_OVERHEAD_FIELD));
    let inference_value = timing_metrics.and_then(|v| v.get(RESPONSES_API_INFERENCE_FIELD));
    // ... TTFT, TBT 等
}
```

支持的指标字段：
- `responses_duration_excl_engine_and_client_tool_time_ms`: API 开销时间
- `engine_service_total_ms`: 推理总时间
- `engine_iapi_ttft_total_ms` / `engine_service_ttft_total_ms`: 首 token 时间
- `engine_iapi_tbt_across_engine_calls_ms` / `engine_service_tbt_across_engine_calls_ms`:  token 间时间

### 用户提示脱敏

```rust
pub fn user_prompt(&self, items: &[UserInput]) {
    let prompt = /* 提取文本 */;
    
    let prompt_to_log = if self.metadata.log_user_prompts {
        prompt.as_str()
    } else {
        "[REDACTED]"
    };
    
    // 记录到日志（可能脱敏）
    log_event!(..., prompt = %prompt_to_log);
    // 记录到追踪（仅统计信息）
    trace_event!(..., prompt_length = %prompt.chars().count(), ...);
}
```

## 关键代码路径与文件引用

### 文件依赖图

```
session_telemetry.rs
  ├── 依赖: events/shared.rs (宏)
  ├── 依赖: metrics/* (MetricsClient, Timer)
  ├── 依赖: targets.rs (OTEL_LOG_ONLY_TARGET, OTEL_TRACE_SAFE_TARGET)
  ├── 依赖: provider.rs (OtelProvider)
  └── 被依赖: lib.rs (重新导出)
      └── 被依赖: codex-core/* (主要使用方)
```

### 指标名称常量

定义在 `metrics/names.rs`：

```rust
pub const TOOL_CALL_COUNT_METRIC: &str = "codex.tool.call";
pub const TOOL_CALL_DURATION_METRIC: &str = "codex.tool.call.duration_ms";
pub const API_CALL_COUNT_METRIC: &str = "codex.api_request";
pub const API_CALL_DURATION_METRIC: &str = "codex.api_request.duration_ms";
pub const SSE_EVENT_COUNT_METRIC: &str = "codex.sse_event";
pub const SSE_EVENT_DURATION_METRIC: &str = "codex.sse_event.duration_ms";
// ... WebSocket 相关指标
```

### 主要调用方

#### codex-core/src/codex.rs

```rust
// 创建 SessionTelemetry
let session_telemetry = SessionTelemetry::new(
    conversation_id,
    &model_info.id,
    &model_info.slug,
    account_id,
    account_email,
    auth_mode.map(|m| m.into()),
    originator,
    log_user_prompts,
    terminal_type,
    session_source,
)
.with_auth_env(auth_env_telemetry)
.with_provider_metrics(&otel_provider);
```

#### codex-core/src/client.rs

```rust
// API 请求包装
pub async fn log_request<F, Fut>(&self, attempt: u64, f: F) -> Result<Response, Error>

// WebSocket 事件记录
session_telemetry.record_websocket_event(&result, duration);
```

#### codex-core/src/turn_timing.rs

```rust
// 回合计时
impl TurnTiming {
    pub fn record_telemetry(&self, telemetry: &SessionTelemetry) {
        if let Some(ttft) = self.first_token_time {
            telemetry.record_duration(TURN_TTFT_DURATION_METRIC, ttft, &[]);
        }
        // ...
    }
}
```

## 依赖与外部交互

### 直接依赖

| Crate/Module | 用途 |
|-------------|------|
| `codex_protocol` | ThreadId, SessionSource, ResponseItem 等协议类型 |
| `codex_api` | ApiError, ResponseEvent |
| `opentelemetry_sdk` | ResourceMetrics（运行时指标快照） |
| `tracing` | 结构化日志记录 |
| `eventsource_stream` | SSE 事件解析 |
| `tokio_tungstenite` | WebSocket 消息类型 |

### 内部模块依赖

```rust
use crate::events::shared::log_and_trace_event;
use crate::events::shared::log_event;
use crate::events::shared::trace_event;
use crate::metrics::MetricsClient;
use crate::metrics::names::*;
use crate::metrics::timer::Timer;
use crate::metrics::tags::SessionMetricTagValues;
```

### 配置集成

通过 `OtelProvider` 获取指标配置：

```rust
pub fn with_provider_metrics(self, provider: &OtelProvider) -> Self {
    match provider.metrics() {
        Some(metrics) => self.with_metrics(metrics.clone()),
        None => self,
    }
}
```

## 风险、边界与改进建议

### 当前限制

1. **错误处理**: 指标记录错误仅通过 `tracing::warn` 记录，调用方无法感知
2. **标签数量限制**: 未对标签数量进行硬性限制，可能导致指标后端拒绝
3. **内存使用**: `MetricsClient` 内部使用 `Mutex<HashMap>` 缓存指标仪器，高并发时可能成为瓶颈

### 潜在风险

1. **敏感信息泄露**: 
   - `user_prompt` 方法依赖 `log_user_prompts` 配置控制脱敏
   - 工具参数和输出可能包含敏感信息

2. **性能影响**:
   - 每个事件都进行 JSON 序列化和标签合并
   - WebSocket 事件解析涉及多次 `serde_json::from_str`

3. **指标基数爆炸**:
   - 错误消息、请求 ID 等动态内容不应作为标签
   - 当前实现通过 `sanitize_metric_tag_value` 进行清理，但基数控制仍依赖调用方

### 边界情况

1. **MetricsClient 未启用**: 所有指标方法优雅地返回 Ok(())
2. **WebSocket 消息解析失败**: 记录为 `parse_error` 类型，不 panic
3. **时间戳解析异常**: `duration_from_ms_value` 函数过滤非有限值和负值

### 改进建议

1. **错误处理增强**:
   ```rust
   // 考虑返回 Result 让调用方决定如何处理
   pub fn counter(&self, name: &str, inc: i64, tags: &[(&str, &str)]) -> MetricsResult<()>
   ```

2. **标签验证**:
   - 在 `tags_with_metadata` 中添加标签数量检查
   - 对标签值长度进行限制

3. **性能优化**:
   - 考虑使用 `parking_lot::Mutex` 替代标准库 Mutex
   - 对频繁使用的标签进行缓存

4. **安全增强**:
   - 对工具参数和输出进行自动脱敏检查
   - 添加敏感信息检测启发式规则

5. **可观测性**:
   - 添加内部指标：事件队列深度、导出延迟
   - 支持采样率配置

### 测试覆盖

相关测试文件：
- `codex-rs/otel/tests/suite/runtime_summary.rs` - 运行时指标汇总测试
- `codex-rs/otel/tests/suite/snapshot.rs` - 指标快照测试
- `codex-rs/otel/tests/suite/manager_metrics.rs` - 指标管理测试
- `codex-rs/otel/tests/suite/otel_export_routing_policy.rs` - 导出路由策略测试
