# codex-rs/otel 深度研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

`codex-otel` 是 Codex 项目的 OpenTelemetry 集成 crate，负责提供统一的**可观测性（Observability）**基础设施。它作为 Codex 核心模块与 OpenTelemetry 生态之间的桥梁，承担以下核心职责：

### 核心职责

| 职责领域 | 说明 |
|---------|------|
| **Trace（链路追踪）** | 通过 OpenTelemetry SDK 实现分布式链路追踪，支持 W3C Trace Context 标准传播 |
| **Metrics（指标收集）** | 提供 Counter、Histogram、Timer 等度量指标收集能力，支持 OTLP/HTTP/gRPC 导出 |
| **Logs（日志导出）** | 将 tracing 事件导出到 OpenTelemetry Collector，支持分层过滤策略 |
| **Session Telemetry（会话遥测）** | 封装 Codex 特定的业务事件（user_prompt、tool_result、api_request 等）|
| **Runtime Metrics（运行时指标）** | 提供运行时指标快照能力，用于性能分析和调试 |

### 架构定位

```
┌─────────────────────────────────────────────────────────────┐
│                      Codex Application                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │   codex-cli  │  │  codex-tui   │  │  codex-app-server│   │
│  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘   │
└─────────┼─────────────────┼───────────────────┼─────────────┘
          │                 │                   │
          └─────────────────┼───────────────────┘
                            ▼
              ┌─────────────────────────┐
              │      codex-core         │
              │  (business logic layer) │
              └───────────┬─────────────┘
                          │
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
   ┌────────────┐  ┌────────────┐  ┌────────────┐
   │   Logs     │  │   Traces   │  │   Metrics  │
   │  (events)  │  │   (spans)  │  │  (counters)│
   └─────┬──────┘  └─────┬──────┘  └─────┬──────┘
         │               │               │
         └───────────────┼───────────────┘
                         ▼
              ┌─────────────────────┐
              │    codex-otel       │
              │  (this crate)       │
              └──────────┬──────────┘
                         │
         ┌───────────────┼───────────────┐
         ▼               ▼               ▼
   ┌────────────┐  ┌────────────┐  ┌────────────┐
   │ OTLP/HTTP  │  │ OTLP/gRPC  │  │  Statsig   │
   │  (JSON/    │  │            │  │  (internal)│
   │  Binary)   │  │            │  │            │
   └────────────┘  └────────────┘  └────────────┘
```

### 使用场景

1. **开发调试**：通过 InMemoryMetricExporter 收集指标，验证业务逻辑正确性
2. **生产监控**：通过 OTLP 导出到 OpenTelemetry Collector，接入 Prometheus/Grafana
3. **性能分析**：通过 RuntimeMetricsSummary 获取 API 调用、工具执行等耗时统计
4. **安全审计**：通过 SessionTelemetry 记录用户提示、工具调用等敏感操作（支持脱敏）

---

## 功能点目的

### 1. OtelProvider - 统一出口提供者

**目的**：整合 Logs、Traces、Metrics 三种可观测性信号，提供统一的初始化和关闭接口。

**关键特性**：
- 支持独立配置三种信号的导出器（可分别启用/禁用）
- 自动设置全局 TracerProvider 和 TextMapPropagator
- 提供 `logger_layer()` 和 `tracing_layer()` 供 tracing_subscriber 注册
- 实现 `Drop` trait 确保优雅关闭

### 2. SessionTelemetry - 会话级业务遥测

**目的**：封装 Codex 特定的业务语义，统一记录会话生命周期中的关键事件。

**核心事件类型**：

| 事件方法 | 触发场景 | 敏感数据处理 |
|---------|---------|-------------|
| `conversation_starts` | 新会话开始 | 记录配置信息（沙盒策略、MCP 服务器等）|
| `user_prompt` | 用户提交输入 | 支持 `log_user_prompts` 开关控制是否记录原始内容 |
| `tool_result_with_tags` | 工具执行完成 | Log 输出完整内容，Trace 仅输出长度统计 |
| `record_api_request` | API 请求完成 | 记录认证相关元数据（脱敏）|
| `record_websocket_*` | WebSocket 连接/请求/事件 | 记录连接复用、时序指标 |
| `record_auth_recovery` | 认证恢复流程 | 记录恢复步骤和结果 |
| `log_sse_event` | SSE 流事件 | 解析响应类型并记录时序 |

**双轨导出策略**：
- **Log 轨道**（`codex_otel.log_only`）：包含完整敏感信息，用于审计
- **Trace 轨道**（`codex_otel.trace_safe`）：脱敏后仅包含统计信息，用于分布式追踪

### 3. MetricsClient - 指标收集客户端

**目的**：提供类型安全的指标收集 API，支持 Counter、Histogram、Timer 三种类型。

**设计特点**：
- 惰性创建指标仪器（首次使用时初始化）
- 支持默认标签（所有指标自动附加）
- 支持运行时快照（通过 ManualReader）
- 严格的命名和标签校验（防止非法字符）

### 4. Trace Context - 链路上下文传播

**目的**：实现 W3C Trace Context 标准，支持跨服务/跨进程的链路追踪。

**核心功能**：
- `current_span_w3c_trace_context()`：获取当前 Span 的 W3C 上下文
- `set_parent_from_w3c_trace_context()`：从上游上下文恢复 Span 父子关系
- `traceparent_context_from_env()`：从环境变量 `TRACEPARENT`/`TRACESTATE` 恢复上下文

### 5. Runtime Metrics Summary - 运行时指标汇总

**目的**：提供会话级别的性能统计，用于诊断和优化。

**统计维度**：
- Tool Calls（次数、耗时）
- API Calls（次数、耗时）
- Streaming Events（SSE 事件次数、耗时）
- WebSocket Calls/Events（次数、耗时）
- Responses API 细分指标（Overhead、Inference、TTFT、TBT）
- Turn-level 指标（TTFT、TTFM）

---

## 具体技术实现

### 3.1 配置与初始化流程

#### OtelSettings 配置结构

```rust
// src/config.rs
pub struct OtelSettings {
    pub environment: String,           // 环境标识（dev/staging/prod）
    pub service_name: String,          // 服务名称
    pub service_version: String,       // 服务版本
    pub codex_home: PathBuf,           // Codex 主目录
    pub exporter: OtelExporter,        // Logs 导出器
    pub trace_exporter: OtelExporter,  // Traces 导出器
    pub metrics_exporter: OtelExporter,// Metrics 导出器
    pub runtime_metrics: bool,         // 是否启用运行时指标
}

pub enum OtelExporter {
    None,
    Statsig,  // 内部 Statsig 快捷配置
    OtlpGrpc { endpoint, headers, tls },
    OtlpHttp { endpoint, headers, protocol, tls },
}
```

#### Provider 初始化流程

```rust
// src/provider.rs:67-120
pub fn from(settings: &OtelSettings) -> Result<Option<Self>, Box<dyn Error>> {
    // 1. 解析并配置 Metrics 导出器
    let metric_exporter = crate::config::resolve_exporter(&settings.metrics_exporter);
    let metrics = if matches!(metric_exporter, OtelExporter::None) {
        None
    } else {
        Some(MetricsClient::new(config)?)
    };
    
    // 2. 安装全局 Metrics 客户端
    if let Some(metrics) = metrics.as_ref() {
        crate::metrics::install_global(metrics.clone());
    }
    
    // 3. 构建 Logger（如果启用）
    let logger = log_enabled
        .then(|| build_logger(&log_resource, &settings.exporter))
        .transpose()?;
    
    // 4. 构建 TracerProvider（如果启用）
    let tracer_provider = trace_enabled
        .then(|| build_tracer_provider(&trace_resource, &settings.trace_exporter))
        .transpose()?;
    
    // 5. 设置全局 TracerProvider 和 Propagator
    if let Some(provider) = tracer_provider.clone() {
        global::set_tracer_provider(provider);
        global::set_text_map_propagator(TraceContextPropagator::new());
    }
    
    Ok(Some(Self { logger, tracer_provider, tracer, metrics }))
}
```

### 3.2 SessionTelemetry 事件记录机制

#### 双轨导出宏实现

```rust
// src/events/shared.rs
macro_rules! log_event {
    ($self:expr, $($fields:tt)*) => {{
        tracing::event!(
            target: $crate::targets::OTEL_LOG_ONLY_TARGET,  // 关键：指定 log_only 目标
            tracing::Level::INFO,
            $($fields)*
            // 自动附加会话元数据
            conversation.id = %$self.metadata.conversation_id,
            app.version = %$self.metadata.app_version,
            auth_mode = $self.metadata.auth_mode,
            // ... 其他元数据
        );
    }};
}

macro_rules! trace_event {
    ($self:expr, $($fields:tt)*) => {{
        tracing::event!(
            target: $crate::targets::OTEL_TRACE_SAFE_TARGET,  // 关键：指定 trace_safe 目标
            tracing::Level::INFO,
            $($fields)*
            // 自动附加会话元数据（不含敏感字段如 user.email）
            conversation.id = %$self.metadata.conversation_id,
            // ...
        );
    }};
}
```

#### 目标过滤策略

```rust
// src/targets.rs
pub(crate) const OTEL_LOG_ONLY_TARGET: &str = "codex_otel.log_only";
pub(crate) const OTEL_TRACE_SAFE_TARGET: &str = "codex_otel.trace_safe";

pub(crate) fn is_log_export_target(target: &str) -> bool {
    target.starts_with(OTEL_TARGET_PREFIX) && !is_trace_safe_target(target)
}

pub(crate) fn is_trace_safe_target(target: &str) -> bool {
    target.starts_with(OTEL_TRACE_SAFE_TARGET)
}
```

#### Provider 层过滤配置

```rust
// src/provider.rs:122-144
pub fn logger_layer<S>(&self) -> Option<impl Layer<S> + Send + Sync> {
    self.logger.as_ref().map(|logger| {
        OpenTelemetryTracingBridge::new(logger).with_filter(
            tracing_subscriber::filter::filter_fn(OtelProvider::log_export_filter),
        )
    })
}

pub fn tracing_layer<S>(&self) -> Option<impl Layer<S> + Send + Sync> {
    self.tracer.as_ref().map(|tracer| {
        tracing_opentelemetry::layer()
            .with_tracer(tracer.clone())
            .with_filter(tracing_subscriber::filter::filter_fn(
                OtelProvider::trace_export_filter,
            ))
    })
}
```

### 3.3 MetricsClient 实现细节

#### 内部数据结构

```rust
// src/metrics/client.rs:81-90
struct MetricsClientInner {
    meter_provider: SdkMeterProvider,
    meter: Meter,
    counters: Mutex<HashMap<String, Counter<u64>>>,      // 惰性创建的计数器
    histograms: Mutex<HashMap<String, Histogram<f64>>>,  // 惰性创建的直方图
    duration_histograms: Mutex<HashMap<String, Histogram<f64>>>,
    runtime_reader: Option<Arc<ManualReader>>,           // 运行时快照读取器
    default_tags: BTreeMap<String, String>,              // 默认标签
}
```

#### Counter 实现

```rust
// src/metrics/client.rs:93-112
fn counter(&self, name: &str, inc: i64, tags: &[(&str, &str)]) -> Result<()> {
    validate_metric_name(name)?;
    if inc < 0 {
        return Err(MetricsError::NegativeCounterIncrement { name: name.to_string(), inc });
    }
    let attributes = self.attributes(tags)?;
    
    let mut counters = self.counters.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
    let counter = counters
        .entry(name.to_string())
        .or_insert_with(|| self.meter.u64_counter(name.to_string()).build());
    counter.add(inc as u64, &attributes);
    Ok(())
}
```

#### Timer 实现（RAII 模式）

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

pub fn record(&self, additional_tags: &[(&str, &str)]) -> Result<()> {
    let mut tags = Vec::with_capacity(self.tags.len() + additional_tags.len());
    tags.extend(additional_tags);
    tags.extend(self.tags.iter().map(|(k, v)| (k.as_str(), v.as_str())));
    self.client.record_duration(&self.name, self.start_time.elapsed(), &tags)
}
```

### 3.4 OTLP 导出器 TLS 配置

```rust
// src/otlp.rs:34-68
pub(crate) fn build_grpc_tls_config(
    endpoint: &str,
    tls_config: ClientTlsConfig,
    tls: &OtelTlsConfig,
) -> Result<ClientTlsConfig, Box<dyn Error>> {
    let uri: Uri = endpoint.parse()?;
    let host = uri.host().ok_or_else(|| { /* ... */ })?;
    
    let mut config = tls_config.domain_name(host.to_owned());
    
    // CA 证书配置
    if let Some(path) = tls.ca_certificate.as_ref() {
        let (pem, _) = read_bytes(path)?;
        config = config.ca_certificate(TonicCertificate::from_pem(pem));
    }
    
    // mTLS 客户端证书配置
    match (&tls.client_certificate, &tls.client_private_key) {
        (Some(cert_path), Some(key_path)) => {
            let (cert_pem, _) = read_bytes(cert_path)?;
            let (key_pem, _) = read_bytes(key_path)?;
            config = config.identity(TonicIdentity::from_pem(cert_pem, key_pem));
        }
        // 校验：必须同时提供证书和私钥
        (Some(_), None) | (None, Some(_)) => {
            return Err(config_error(
                "client_certificate and client_private_key must both be provided for mTLS"
            ));
        }
        (None, None) => {}
    }
    
    Ok(config)
}
```

### 3.5 Runtime Metrics 快照机制

```rust
// src/metrics/runtime_metrics.rs:119-169
pub(crate) fn from_snapshot(snapshot: &ResourceMetrics) -> Self {
    Self {
        tool_calls: RuntimeMetricTotals {
            count: sum_counter(snapshot, TOOL_CALL_COUNT_METRIC),
            duration_ms: sum_histogram_ms(snapshot, TOOL_CALL_DURATION_METRIC),
        },
        api_calls: RuntimeMetricTotals {
            count: sum_counter(snapshot, API_CALL_COUNT_METRIC),
            duration_ms: sum_histogram_ms(snapshot, API_CALL_DURATION_METRIC),
        },
        // ... 其他指标聚合
    }
}

fn sum_counter(snapshot: &ResourceMetrics, name: &str) -> u64 {
    snapshot
        .scope_metrics()
        .flat_map(opentelemetry_sdk::metrics::data::ScopeMetrics::metrics)
        .filter(|metric| metric.name() == name)
        .map(sum_counter_metric)
        .sum()
}
```

---

## 关键代码路径与文件引用

### 核心模块文件

| 文件路径 | 职责 | 关键类型/函数 |
|---------|------|--------------|
| `src/lib.rs` | 模块导出和公共 API | `SessionTelemetry`, `OtelProvider`, `ToolDecisionSource`, `TelemetryAuthMode` |
| `src/config.rs` | OTEL 配置定义 | `OtelSettings`, `OtelExporter`, `OtelHttpProtocol`, `OtelTlsConfig` |
| `src/provider.rs` | Provider 初始化和层构建 | `OtelProvider::from()`, `logger_layer()`, `tracing_layer()` |
| `src/otlp.rs` | OTLP 导出器 TLS/HTTP 配置 | `build_grpc_tls_config()`, `build_http_client()`, `build_async_http_client()` |
| `src/targets.rs` | Tracing 目标过滤 | `OTEL_LOG_ONLY_TARGET`, `OTEL_TRACE_SAFE_TARGET`, `is_log_export_target()` |
| `src/trace_context.rs` | W3C Trace Context 实现 | `current_span_w3c_trace_context()`, `set_parent_from_w3c_trace_context()` |

### Events 模块

| 文件路径 | 职责 | 关键类型/函数 |
|---------|------|--------------|
| `src/events/mod.rs` | Events 模块组织 | 子模块导出 |
| `src/events/session_telemetry.rs` | 会话遥测实现 | `SessionTelemetry`, `SessionTelemetryMetadata`, `AuthEnvTelemetryMetadata` |
| `src/events/shared.rs` | 共享宏和工具 | `log_event!`, `trace_event!`, `log_and_trace_event!`, `timestamp()` |

### Metrics 模块

| 文件路径 | 职责 | 关键类型/函数 |
|---------|------|--------------|
| `src/metrics/mod.rs` | Metrics 模块组织和全局客户端 | `MetricsClient`, `GLOBAL_METRICS`, `install_global()`, `global()` |
| `src/metrics/client.rs` | MetricsClient 实现 | `MetricsClient::new()`, `counter()`, `histogram()`, `record_duration()`, `snapshot()` |
| `src/metrics/config.rs` | Metrics 配置 | `MetricsConfig`, `MetricsExporter` |
| `src/metrics/error.rs` | 错误类型定义 | `MetricsError` |
| `src/metrics/names.rs` | 指标名称常量 | `TOOL_CALL_COUNT_METRIC`, `API_CALL_DURATION_METRIC`, `TURN_TTFT_DURATION_METRIC` 等 |
| `src/metrics/tags.rs` | 会话标签管理 | `SessionMetricTagValues`, `AUTH_MODE_TAG`, `MODEL_TAG` 等 |
| `src/metrics/timer.rs` | Timer 实现 | `Timer` (RAII 模式) |
| `src/metrics/validation.rs` | 命名校验 | `validate_metric_name()`, `validate_tag_key()`, `validate_tag_value()` |
| `src/metrics/runtime_metrics.rs` | 运行时指标汇总 | `RuntimeMetricsSummary`, `RuntimeMetricTotals` |

### 测试文件

| 文件路径 | 测试范围 |
|---------|---------|
| `tests/suite/send.rs` | Metrics 发送和标签合并 |
| `tests/suite/timing.rs` | Timer 和 Duration 记录 |
| `tests/suite/validation.rs` | 命名和标签校验 |
| `tests/suite/snapshot.rs` | 运行时快照功能 |
| `tests/suite/manager_metrics.rs` | SessionTelemetry 标签附加 |
| `tests/suite/runtime_summary.rs` | RuntimeMetricsSummary 聚合 |
| `tests/suite/otel_export_routing_policy.rs` | Log/Trace 双轨导出策略 |
| `tests/suite/otlp_http_loopback.rs` | OTLP HTTP 导出器端到端测试 |

### 调用方（Callers）

| 调用方 | 文件路径 | 使用方式 |
|-------|---------|---------|
| codex-core | `core/src/otel_init.rs` | 从 Config 构建 OtelProvider |
| codex-core | `core/src/auth_env_telemetry.rs` | 构建 AuthEnvTelemetryMetadata |
| codex-core | `core/src/client.rs` | 使用 SessionTelemetry 记录 API 请求 |
| codex-core | `core/src/turn_timing.rs` | 记录 Turn 级时序指标 |
| codex-tui | `tui/src/app.rs` | 初始化 OTEL 和 SessionTelemetry |
| codex-exec | `exec/src/lib.rs` | 使用 SessionTelemetry |

---

## 依赖与外部交互

### 外部 Crate 依赖

| Crate | 用途 | 版本特性 |
|-------|------|---------|
| `opentelemetry` | OpenTelemetry API | `logs`, `metrics`, `trace` |
| `opentelemetry_sdk` | OpenTelemetry SDK | `rt-tokio`, `testing`, `experimental_*` |
| `opentelemetry_otlp` | OTLP 导出器 | `grpc-tonic`, `http-proto`, `http-json`, `logs`, `metrics`, `trace` |
| `opentelemetry-appender-tracing` | Tracing 到 OTEL Logs 桥接 | - |
| `opentelemetry-semantic-conventions` | 语义约定常量 | - |
| `tracing` | 结构化日志/span | - |
| `tracing-opentelemetry` | Tracing 到 OTEL Traces 桥接 | - |
| `tracing-subscriber` | 订阅者注册和过滤 | - |
| `reqwest` | HTTP 客户端（TLS 配置）| `blocking`, `rustls-tls` |
| `tokio` | 异步运行时检测 | - |
| `serde`/`serde_json` | JSON 序列化 | - |
| `chrono` | 时间戳格式化 | - |
| `os_info` | 操作系统信息采集 | - |
| `gethostname` | 主机名获取 | - |

### Workspace 内部依赖

| Crate | 用途 |
|-------|------|
| `codex-utils-absolute-path` | 绝对路径处理（TLS 证书路径）|
| `codex-utils-string` | 字符串清理（`sanitize_metric_tag_value`）|
| `codex-api` | API 错误类型 (`ApiError`) |
| `codex-protocol` | 协议类型 (`ThreadId`, `ResponseEvent`, `UserInput`, `SessionSource` 等) |

### 外部系统交互

```
┌─────────────────┐     OTLP/HTTP (JSON/Binary)     ┌─────────────────┐
│   codex-otel    │ ───────────────────────────────> │  OTEL Collector │
│                 │                                  │  (optional)     │
│                 │     OTLP/gRPC                   │                 │
│                 │ ───────────────────────────────> │                 │
│                 │                                  │                 │
│                 │     HTTP/JSON (Statsig)         │                 │
│                 │ ───────────────────────────────> │  Statsig        │
│                 │     https://ab.chatgpt.com/otlp │  (internal)     │
└─────────────────┘                                  └─────────────────┘
```

---

## 风险、边界与改进建议

### 已知风险

#### 1. 敏感数据泄露风险

**风险描述**：虽然 SessionTelemetry 实现了双轨导出策略，但开发者可能误用 `log_event!` 宏将敏感数据发送到 Trace 轨道。

**缓解措施**：
- 代码审查时重点关注 `trace_event!` 宏的使用
- 测试用例 `otel_export_routing_policy.rs` 验证敏感字段不会出现在 Trace 中

**改进建议**：
- 考虑在编译期通过类型系统区分 Log-only 和 Trace-safe 数据

#### 2. 指标命名冲突

**风险描述**：`MetricsClient` 使用惰性创建的仪器（instrument），如果不同代码路径使用相同名称但不同类型的指标，可能导致运行时错误。

**当前状态**：OpenTelemetry SDK 会处理同名仪器的复用，但类型不匹配可能导致 panic。

**改进建议**：
- 添加指标名称注册表，在初始化时检测命名冲突

#### 3. TLS 证书加载失败

**风险描述**：`build_http_client` 在 TLS 配置错误时会返回错误，但错误信息可能不够详细。

**改进建议**：
- 添加证书文件路径和格式的详细诊断信息

#### 4. Tokio 运行时检测

**风险描述**：`current_tokio_runtime_is_multi_thread()` 用于决定使用同步还是异步 HTTP 客户端，但检测逻辑依赖于 `tokio::runtime::Handle::try_current()`，在某些边缘场景可能不准确。

**改进建议**：
- 添加显式的运行时类型配置选项，覆盖自动检测

### 边界条件

#### 1. 高并发指标收集

- `MetricsClientInner` 使用 `Mutex` 保护仪器缓存，高并发场景可能成为瓶颈
- 当前设计假设指标收集频率较低（< 1K/s）

#### 2. 长会话内存使用

- 仪器缓存（`counters`, `histograms`）不会自动清理
- 长时间运行的会话如果使用大量不同的标签组合，可能导致内存持续增长

#### 3. 网络不可用时

- OTLP 导出器有默认超时（通过环境变量 `OTEL_EXPORTER_OTLP_TIMEOUT` 配置）
- 批量导出失败时，OpenTelemetry SDK 会丢弃数据（非阻塞设计）

### 改进建议

| 优先级 | 建议 | 预期收益 |
|-------|------|---------|
| P1 | 添加指标仪器缓存大小限制 | 防止长会话内存泄漏 |
| P2 | 支持指标标签值自动脱敏（正则匹配）| 减少敏感数据泄露风险 |
| P2 | 添加 OTLP 导出重试和退避策略 | 提高网络不稳定时的数据可靠性 |
| P3 | 支持 Prometheus 拉取模式（除推送外）| 简化本地开发调试 |
| P3 | 添加指标收集性能剖析（自监控）| 便于诊断性能问题 |

### 测试覆盖率

当前测试覆盖以下场景：
- ✅ 指标发送和标签合并
- ✅ Timer 和 Duration 记录
- ✅ 命名和标签校验
- ✅ 运行时快照
- ✅ SessionTelemetry 标签附加
- ✅ RuntimeMetricsSummary 聚合
- ✅ Log/Trace 双轨导出策略
- ✅ OTLP HTTP 端到端（loopback）

**待补充测试**：
- OTLP gRPC 导出器测试
- TLS mTLS 配置测试
- 高并发指标收集性能测试
- 网络故障恢复测试

---

## 附录：指标名称清单

### Tool 相关
- `codex.tool.call` - 工具调用次数
- `codex.tool.call.duration_ms` - 工具调用耗时

### API 相关
- `codex.api_request` - API 请求次数
- `codex.api_request.duration_ms` - API 请求耗时

### SSE 相关
- `codex.sse_event` - SSE 事件次数
- `codex.sse_event.duration_ms` - SSE 事件处理耗时

### WebSocket 相关
- `codex.websocket.request` - WebSocket 请求次数
- `codex.websocket.request.duration_ms` - WebSocket 请求耗时
- `codex.websocket.event` - WebSocket 事件次数
- `codex.websocket.event.duration_ms` - WebSocket 事件处理耗时

### Responses API 性能细分
- `codex.responses_api_overhead.duration_ms` - 除引擎和工具外的开销
- `codex.responses_api_inference_time.duration_ms` - 推理时间
- `codex.responses_api_engine_iapi_ttft.duration_ms` - 引擎内部 API 首 Token 时间
- `codex.responses_api_engine_service_ttft.duration_ms` - 引擎服务首 Token 时间
- `codex.responses_api_engine_iapi_tbt.duration_ms` - 引擎内部 API  Token 间隔
- `codex.responses_api_engine_service_tbt.duration_ms` - 引擎服务 Token 间隔

### Turn 级别
- `codex.turn.e2e_duration_ms` - Turn 端到端耗时
- `codex.turn.ttft.duration_ms` - 首 Token 时间
- `codex.turn.ttfm.duration_ms` - 首消息时间
- `codex.turn.network_proxy` - 网络代理相关
- `codex.turn.tool.call` - Turn 内工具调用
- `codex.turn.token_usage` - Token 使用量

### 其他
- `codex.startup_prewarm.duration_ms` - 启动预热耗时
- `codex.startup_prewarm.age_at_first_turn_ms` - 首次 Turn 时预热年龄
- `codex.thread.started` - 线程启动次数
