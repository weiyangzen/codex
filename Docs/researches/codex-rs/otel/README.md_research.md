# codex-rs/otel/README.md 研究文档

## 场景与职责

`README.md` 是 `codex-otel` crate 的用户文档，面向 Rust 开发者介绍如何集成和使用该库。该文档提供了高层概述、使用示例和最佳实践，是开发者了解 crate 功能的第一入口。

在 Codex 项目中，`codex-otel` 作为可观测性基础设施，其 README 需要服务于：
- **应用开发者**：了解如何配置 OTEL 导出器
- **核心贡献者**：了解 Session 遥测和指标 API
- **运维人员**：了解不同导出模式（OTLP、Statsig、内存）

## 功能点目的

README 涵盖四大核心功能领域：

1. **Tracing 和 Logs**：配置 `tracing_subscriber` 与 OTEL 集成
2. **SessionTelemetry**：业务事件发射（会话级别的结构化日志）
3. **Metrics**：指标收集（Counter、Histogram、Timer）
4. **Trace Context**：分布式追踪上下文传播

## 具体技术实现

### 1. Tracing 和 Logs

#### 核心类型

```rust
// src/config.rs
pub struct OtelSettings {
    pub environment: String,
    pub service_name: String,
    pub service_version: String,
    pub codex_home: PathBuf,
    pub exporter: OtelExporter,         // 日志导出器
    pub trace_exporter: OtelExporter,   // 追踪导出器
    pub metrics_exporter: OtelExporter, // 指标导出器
    pub runtime_metrics: bool,
}

pub enum OtelExporter {
    None,
    Statsig,  // 内部 Statsig 快捷配置
    OtlpGrpc { endpoint, headers, tls },
    OtlpHttp { endpoint, headers, protocol, tls },
}

pub enum OtelHttpProtocol {
    Binary,  // Protobuf 二进制
    Json,    // JSON 格式
}
```

#### Provider 构建流程

```rust
// src/provider.rs
impl OtelProvider {
    pub fn from(settings: &OtelSettings) -> Result<Option<Self>, Box<dyn Error>> {
        // 1. 解析指标导出器配置
        let metric_exporter = crate::config::resolve_exporter(&settings.metrics_exporter);
        let metrics = if matches!(metric_exporter, OtelExporter::None) {
            None
        } else {
            Some(MetricsClient::new(...)?)
        };
        
        // 2. 安装全局指标客户端
        if let Some(metrics) = metrics.as_ref() {
            crate::metrics::install_global(metrics.clone());
        }
        
        // 3. 构建日志和追踪资源
        let log_resource = make_resource(settings, ResourceKind::Logs);
        let trace_resource = make_resource(settings, ResourceKind::Traces);
        
        // 4. 构建 logger 和 tracer
        let logger = build_logger(&log_resource, &settings.exporter)?;
        let tracer_provider = build_tracer_provider(&trace_resource, &settings.trace_exporter)?;
        
        // 5. 设置全局 tracer
        global::set_tracer_provider(tracer_provider.clone());
        global::set_text_map_propagator(TraceContextPropagator::new());
        
        Ok(Some(Self { logger, tracer_provider, tracer, metrics }))
    }
}
```

#### Layer 集成

```rust
// src/provider.rs
pub fn logger_layer<S>(&self) -> Option<impl Layer<S> + Send + Sync> {
    self.logger.as_ref().map(|logger| {
        OpenTelemetryTracingBridge::new(logger)
            .with_filter(tracing_subscriber::filter::filter_fn(OtelProvider::log_export_filter))
    })
}

pub fn tracing_layer<S>(&self) -> Option<impl Layer<S> + Send + Sync> {
    self.tracer.as_ref().map(|tracer| {
        tracing_opentelemetry::layer()
            .with_tracer(tracer.clone())
            .with_filter(tracing_subscriber::filter::filter_fn(OtelProvider::trace_export_filter))
    })
}
```

**目标过滤机制**（`src/targets.rs`）：
- `codex_otel.log_only`：仅日志导出
- `codex_otel.trace_safe`：日志和追踪都导出
- 其他 `codex_otel.*`：仅日志导出

### 2. SessionTelemetry

#### 数据结构

```rust
// src/events/session_telemetry.rs
pub struct SessionTelemetry {
    pub(crate) metadata: SessionTelemetryMetadata,
    pub(crate) metrics: Option<MetricsClient>,
    pub(crate) metrics_use_metadata_tags: bool,
}

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

#### 事件记录宏

```rust
// src/events/shared.rs
macro_rules! log_event {
    ($self:expr, $($fields:tt)*) => {{
        tracing::event!(
            target: $crate::targets::OTEL_LOG_ONLY_TARGET,
            tracing::Level::INFO,
            $($fields)*
            event.timestamp = %timestamp(),
            conversation.id = %$self.metadata.conversation_id,
            app.version = %$self.metadata.app_version,
            // ... 其他元数据字段
        );
    }};
}

macro_rules! trace_event {
    // 类似，但目标为 OTEL_TRACE_SAFE_TARGET
}

macro_rules! log_and_trace_event {
    // 同时记录到日志和追踪
}
```

#### 典型事件方法

```rust
// src/events/session_telemetry.rs
impl SessionTelemetry {
    pub fn user_prompt(&self, items: &[UserInput]) { ... }
    pub fn tool_decision(&self, tool_name, call_id, decision, source) { ... }
    pub fn conversation_starts(&self, provider_name, reasoning_effort, ...) { ... }
    pub fn record_api_request(&self, attempt, status, error, duration, ...) { ... }
    pub fn record_websocket_event(&self, result, duration) { ... }
    pub fn log_sse_event<E>(&self, response, duration) { ... }
}
```

### 3. Metrics

#### 客户端结构

```rust
// src/metrics/client.rs
pub struct MetricsClient(std::sync::Arc<MetricsClientInner>);

struct MetricsClientInner {
    meter_provider: SdkMeterProvider,
    meter: Meter,
    counters: Mutex<HashMap<String, Counter<u64>>>,
    histograms: Mutex<HashMap<String, Histogram<f64>>>,
    duration_histograms: Mutex<HashMap<String, Histogram<f64>>>,
    runtime_reader: Option<Arc<ManualReader>>,  // 用于运行时快照
    default_tags: BTreeMap<String, String>,
}
```

#### 指标类型

```rust
// src/metrics/client.rs
impl MetricsClient {
    pub fn counter(&self, name: &str, inc: i64, tags: &[(&str, &str)]) -> Result<()> {
        // 验证名称和标签
        validate_metric_name(name)?;
        // 检查 inc >= 0
        // 获取或创建 Counter，添加属性，记录
    }
    
    pub fn histogram(&self, name: &str, value: i64, tags: &[(&str, &str)]) -> Result<()> {
        // 类似 counter，但使用 Histogram
    }
    
    pub fn record_duration(&self, name: &str, duration: Duration, tags: &[(&str, &str)]) -> Result<()> {
        // 自动转换为毫秒，使用 duration_histograms
    }
    
    pub fn start_timer(&self, name: &str, tags: &[(&str, &str)]) -> Result<Timer> {
        // 返回 Timer，Drop 时自动记录
    }
}
```

#### Timer 实现

```rust
// src/metrics/timer.rs
pub struct Timer {
    name: String,
    tags: Vec<(String, String)>,
    client: MetricsClient,
    start_time: Instant,
}

impl Drop for Timer {
    fn drop(&mut self) {
        if let Err(e) = self.record(&[]) {
            tracing::error!("metrics client error: {}", e);
        }
    }
}
```

#### 预定义指标名称

```rust
// src/metrics/names.rs
pub const TOOL_CALL_COUNT_METRIC: &str = "codex.tool.call";
pub const TOOL_CALL_DURATION_METRIC: &str = "codex.tool.call.duration_ms";
pub const API_CALL_COUNT_METRIC: &str = "codex.api_request";
pub const API_CALL_DURATION_METRIC: &str = "codex.api_request.duration_ms";
// ... 更多指标名称
```

#### 运行时指标快照

```rust
// src/metrics/runtime_metrics.rs
pub struct RuntimeMetricsSummary {
    pub tool_calls: RuntimeMetricTotals,
    pub api_calls: RuntimeMetricTotals,
    pub streaming_events: RuntimeMetricTotals,
    pub websocket_calls: RuntimeMetricTotals,
    pub websocket_events: RuntimeMetricTotals,
    pub responses_api_overhead_ms: u64,
    pub responses_api_inference_time_ms: u64,
    // ... TTFT, TBT 等延迟指标
}

impl RuntimeMetricsSummary {
    pub(crate) fn from_snapshot(snapshot: &ResourceMetrics) -> Self {
        // 从 OpenTelemetry ResourceMetrics 聚合数据
    }
}
```

### 4. Trace Context

#### W3C Trace Context

```rust
// src/trace_context.rs
pub fn current_span_w3c_trace_context() -> Option<W3cTraceContext> {
    span_w3c_trace_context(&Span::current())
}

pub fn span_w3c_trace_context(span: &Span) -> Option<W3cTraceContext> {
    let context = span.context();
    if !context.span().span_context().is_valid() {
        return None;
    }
    
    let mut headers = HashMap::new();
    TraceContextPropagator::new().inject_context(&context, &mut headers);
    
    Some(W3cTraceContext {
        traceparent: headers.remove("traceparent"),
        tracestate: headers.remove("tracestate"),
    })
}

pub fn context_from_w3c_trace_context(trace: &W3cTraceContext) -> Option<Context> {
    context_from_trace_headers(trace.traceparent.as_deref(), trace.tracestate.as_deref())
}

pub fn set_parent_from_w3c_trace_context(span: &Span, trace: &W3cTraceContext) -> bool {
    // 从 W3C context 设置 span 的 parent
}

pub fn traceparent_context_from_env() -> Option<Context> {
    // 从 TRACEPARENT/TRACESTATE 环境变量加载
}
```

## 关键代码路径与文件引用

### 模块结构

```
src/
├── lib.rs                 # 公共导出
├── config.rs              # OtelSettings, OtelExporter
├── provider.rs            # OtelProvider
├── otlp.rs                # OTLP 导出器构建
├── trace_context.rs       # W3C Trace Context
├── targets.rs             # 日志目标常量
├── metrics/
│   ├── mod.rs             # 全局指标客户端
│   ├── client.rs          # MetricsClient
│   ├── config.rs          # MetricsConfig
│   ├── names.rs           # 指标名称常量
│   ├── tags.rs            # 会话标签
│   ├── timer.rs           # Timer
│   ├── runtime_metrics.rs # 运行时指标聚合
│   ├── validation.rs      # 名称/标签验证
│   └── error.rs           # MetricsError
└── events/
    ├── mod.rs
    ├── session_telemetry.rs # SessionTelemetry
    └── shared.rs            # 事件宏
```

### 关键导出

```rust
// src/lib.rs
pub use crate::events::session_telemetry::SessionTelemetry;
pub use crate::metrics::timer::Timer;
pub use crate::provider::OtelProvider;
pub use crate::trace_context::current_span_w3c_trace_context;
pub use crate::trace_context::set_parent_from_w3c_trace_context;
pub use codex_utils_string::sanitize_metric_tag_value;

pub fn start_global_timer(name: &str, tags: &[(&str, &str)]) -> MetricsResult<Timer> {
    // 使用全局指标客户端启动计时器
}
```

## 依赖与外部交互

### 内部调用方

| Crate | 使用方式 | 主要功能 |
|-------|----------|----------|
| `codex-core` | `SessionTelemetry` | 会话事件记录 |
| `codex-tui` | `OtelProvider`, `SessionTelemetry` | TUI 遥测 |
| `codex-exec` | `OtelProvider`, `SessionTelemetry` | Exec 模式遥测 |
| `codex-app-server` | `OtelProvider` | 服务器遥测 |
| `codex-tui_app_server` | `OtelProvider` | TUI 应用服务器遥测 |

### 外部系统交互

| 协议 | 用途 | 配置方式 |
|------|------|----------|
| OTLP/gRPC | 日志、追踪、指标导出 | `OtelExporter::OtlpGrpc` |
| OTLP/HTTP (Binary) | 指标导出 | `OtelExporter::OtlpHttp { protocol: Binary }` |
| OTLP/HTTP (JSON) | 指标导出到 Statsig | `OtelExporter::OtlpHttp { protocol: Json }` 或 `OtelExporter::Statsig` |
| W3C Trace Context | 分布式追踪传播 | HTTP 头 `traceparent`, `tracestate` |

### Statsig 集成

```rust
// src/config.rs
const STATSIG_OTLP_HTTP_ENDPOINT: &str = "https://ab.chatgpt.com/otlp/v1/metrics";
const STATSIG_API_KEY_HEADER: &str = "statsig-api-key";
const STATSIG_API_KEY: &str = "client-MkRuleRQBd6qakfnDYqJVR9JuXcY57Ljly3vi5JVUIO";

pub(crate) fn resolve_exporter(exporter: &OtelExporter) -> OtelExporter {
    match exporter {
        OtelExporter::Statsig => {
            if cfg!(test) || cfg!(feature = "disable-default-metrics-exporter") {
                return OtelExporter::None;
            }
            OtelExporter::OtlpHttp {
                endpoint: STATSIG_OTLP_HTTP_ENDPOINT.to_string(),
                headers: HashMap::from([(STATSIG_API_KEY_HEADER.to_string(), STATSIG_API_KEY.to_string())]),
                protocol: OtelHttpProtocol::Json,
                tls: None,
            }
        }
        _ => exporter.clone(),
    }
}
```

## 风险、边界与改进建议

### 风险点

1. **硬编码 API Key**：Statsig API key 硬编码在源码中，存在泄露风险
2. **全局状态**：`GLOBAL_METRICS` 使用 `OnceLock`，一旦初始化不可更改，不利于动态配置
3. **TLS 配置复杂**：支持多种 TLS 场景（gRPC/HTTP、mTLS/单向 TLS），容易配置错误
4. **测试隔离**：`disable-default-metrics-exporter` 仅覆盖 Statsig，其他 OTLP 导出器仍需手动禁用

### 边界条件

1. **Tokio 运行时**：`otlp.rs` 中的运行时检测决定使用同步还是异步客户端，在特殊运行时（如 `current_thread`）下可能行为不一致
2. **指标名称/标签验证**：严格的字符限制（ASCII 字母数字 + `._-/`）可能拒绝合法的非 ASCII 标识符
3. **内存限制**：`InMemoryMetricExporter` 在长时间运行的测试中可能积累大量数据
4. **并发限制**：`Mutex` 保护的 `counters`/`histograms` 在高并发下可能成为瓶颈

### 改进建议

1. **配置外部化**：将 Statsig API key 移至构建时环境变量或配置文件
   ```rust
   const STATSIG_API_KEY: &str = env!("STATSIG_API_KEY", "fallback-key");
   ```

2. **动态重配置**：支持 `MetricsClient` 的动态替换，避免全局状态限制

3. **批处理优化**：为高频指标添加本地批处理和采样，减少网络开销
   ```rust
    pub struct BatchingMetricsClient {
        inner: MetricsClient,
        buffer: Vec<MetricRecord>,
        flush_interval: Duration,
    }
   ```

4. **异步指标**：考虑使用 `tokio::sync::RwLock` 或无锁结构（如 `dashmap`）优化并发性能

5. **健康检查**：添加导出器健康检查和自动故障转移机制
   ```rust
    pub struct HealthCheckingExporter {
        primary: Box<dyn MetricExporter>,
        fallback: Box<dyn MetricExporter>,
        health_checker: HealthChecker,
    }
   ```

6. **文档完善**：README 中添加更多关于 TLS 配置、错误处理、性能调优的示例

7. **指标注册表**：提供指标预注册机制，在启动时验证所有指标名称，避免运行时错误
