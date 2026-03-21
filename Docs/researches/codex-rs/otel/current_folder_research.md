# codex-rs/otel 深度研究文档

## 1. 场景与职责

`codex-otel` 是 Codex 项目的 OpenTelemetry 集成 crate，负责为 Codex CLI、TUI、exec 等组件提供统一的遥测（Telemetry）能力。其核心职责包括：

### 1.1 主要使用场景

- **日志收集（Logs）**：收集 Codex 运行时的结构化日志事件，如用户提示、工具调用结果、API 请求等
- **链路追踪（Traces）**：记录请求链路，支持 W3C Trace Context 传播，实现分布式追踪
- **指标收集（Metrics）**：收集计数器（Counter）、直方图（Histogram）等度量数据，如工具调用次数、API 延迟等
- **会话遥测（Session Telemetry）**：为每个用户会话建立统一的遥测上下文，自动附加会话元数据

### 1.2 架构定位

```
┌─────────────────────────────────────────────────────────────────┐
│                        调用方 (Dependents)                       │
├─────────────┬─────────────┬─────────────┬─────────────────────────┤
│  codex-cli  │  codex-tui  │ codex-exec  │    codex-app-server     │
│  (CLI入口)   │  (TUI界面)   │  (执行器)   │    (应用服务器)          │
└──────┬──────┴──────┬──────┴──────┬──────┴───────────┬─────────────┘
       │             │             │                  │
       └─────────────┴─────────────┴──────────────────┘
                           │
                    ┌──────▼──────┐
                    │  codex-otel │
                    │ (本研究对象) │
                    └──────┬──────┘
                           │
       ┌───────────────────┼───────────────────┐
       │                   │                   │
┌──────▼──────┐    ┌──────▼──────┐    ┌──────▼──────┐
│ OTLP/HTTP   │    │ OTLP/gRPC   │    │   Statsig   │
│  (日志/追踪) │    │  (日志/追踪) │    │  (指标收集)  │
└─────────────┘    └─────────────┘    └─────────────┘
```

### 1.3 关键设计原则

1. **双轨导出策略**：敏感数据（完整日志）与非敏感数据（追踪事件）分离导出
2. **会话隔离**：每个会话拥有独立的遥测上下文，支持多会话并发
3. **运行时自适应**：根据 tokio 运行时类型（单线程/多线程）自动调整导出策略
4. **零开销禁用**：通过 feature flag 可在测试环境完全禁用网络导出

---

## 2. 功能点目的

### 2.1 核心功能模块

| 模块 | 文件路径 | 功能目的 |
|------|----------|----------|
| **Provider** | `src/provider.rs` | 初始化 OTEL 导出器，配置日志/追踪/指标三层导出 |
| **SessionTelemetry** | `src/events/session_telemetry.rs` | 会话级遥测管理，自动附加会话元数据到所有事件 |
| **MetricsClient** | `src/metrics/client.rs` | 指标收集客户端，支持 Counter/Histogram/Duration 记录 |
| **TraceContext** | `src/trace_context.rs` | W3C Trace Context 传播，支持跨服务链路追踪 |
| **OTLP** | `src/otlp.rs` | OTLP 协议底层实现，支持 HTTP/gRPC 双协议 |

### 2.2 功能详细说明

#### 2.2.1 OtelProvider - 全局导出器管理

```rust
pub struct OtelProvider {
    pub logger: Option<SdkLoggerProvider>,      // 日志导出器
    pub tracer_provider: Option<SdkTracerProvider>, // 追踪导出器
    pub tracer: Option<Tracer>,                // 追踪器实例
    pub metrics: Option<MetricsClient>,        // 指标客户端
}
```

- 支持独立配置日志、追踪、指标的导出目标
- 自动设置全局 tracer provider 和 propagator
- 提供 `logger_layer()` 和 `tracing_layer()` 供 tracing_subscriber 使用

#### 2.2.2 SessionTelemetry - 会话遥测

```rust
pub struct SessionTelemetry {
    pub(crate) metadata: SessionTelemetryMetadata,  // 会话元数据
    pub(crate) metrics: Option<MetricsClient>,      // 指标客户端
    pub(crate) metrics_use_metadata_tags: bool,     // 是否自动附加元数据标签
}
```

核心能力：
- **自动元数据附加**：会话 ID、模型、认证模式、终端类型等自动附加到所有指标
- **双轨事件记录**：
  - `log_event!` → 完整数据（含敏感信息）→ 日志系统
  - `trace_event!` → 脱敏数据（仅统计）→ 追踪系统
- **业务事件封装**：封装 `user_prompt`, `tool_result`, `api_request` 等业务事件

#### 2.2.3 MetricsClient - 指标收集

支持指标类型：
- **Counter**：计数器，如 `codex.tool.call`
- **Histogram**：直方图，如 `codex.tool.call.duration_ms`
- **Duration Histogram**：自动记录持续时间，单位毫秒

运行时指标（Runtime Metrics）：
- 工具调用统计（次数/耗时）
- API 请求统计
- WebSocket 事件统计
- SSE 事件统计
- Responses API 性能指标（TTFT/TBT/Overhead）

#### 2.2.4 Trace Context 传播

```rust
// 从环境变量加载父级 Trace Context
pub fn traceparent_context_from_env() -> Option<Context>

// 从 W3C Trace Context 设置当前 span 的父级
pub fn set_parent_from_w3c_trace_context(span: &Span, trace: &W3cTraceContext) -> bool

// 获取当前 span 的 W3C Trace Context
pub fn current_span_w3c_trace_context() -> Option<W3cTraceContext>
```

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 导出器配置

```rust
// src/config.rs
#[derive(Clone, Debug)]
pub enum OtelExporter {
    None,
    Statsig,  // Statsig 专用快捷配置
    OtlpGrpc { endpoint: String, headers: HashMap<String, String>, tls: Option<OtelTlsConfig> },
    OtlpHttp { endpoint: String, headers: HashMap<String, String>, protocol: OtelHttpProtocol, tls: Option<OtelTlsConfig> },
}

pub struct OtelSettings {
    pub environment: String,
    pub service_name: String,
    pub service_version: String,
    pub codex_home: PathBuf,
    pub exporter: OtelExporter,        // 日志导出器
    pub trace_exporter: OtelExporter,  // 追踪导出器
    pub metrics_exporter: OtelExporter, // 指标导出器
    pub runtime_metrics: bool,         // 是否启用运行时指标
}
```

#### 3.1.2 指标数据结构

```rust
// src/metrics/client.rs
#[derive(Debug)]
struct MetricsClientInner {
    meter_provider: SdkMeterProvider,
    meter: Meter,
    counters: Mutex<HashMap<String, Counter<u64>>>,
    histograms: Mutex<HashMap<String, Histogram<f64>>>,
    duration_histograms: Mutex<HashMap<String, Histogram<f64>>>,
    runtime_reader: Option<Arc<ManualReader>>,  // 运行时快照读取器
    default_tags: BTreeMap<String, String>,
}
```

#### 3.1.3 运行时指标汇总

```rust
// src/metrics/runtime_metrics.rs
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct RuntimeMetricsSummary {
    pub tool_calls: RuntimeMetricTotals,
    pub api_calls: RuntimeMetricTotals,
    pub streaming_events: RuntimeMetricTotals,
    pub websocket_calls: RuntimeMetricTotals,
    pub websocket_events: RuntimeMetricTotals,
    pub responses_api_overhead_ms: u64,
    pub responses_api_inference_time_ms: u64,
    pub responses_api_engine_iapi_ttft_ms: u64,
    pub responses_api_engine_service_ttft_ms: u64,
    pub responses_api_engine_iapi_tbt_ms: u64,
    pub responses_api_engine_service_tbt_ms: u64,
    pub turn_ttft_ms: u64,
    pub turn_ttfm_ms: u64,
}
```

### 3.2 关键流程

#### 3.2.1 Provider 初始化流程

```
OtelProvider::from(settings)
    ├── resolve_exporter(&settings.metrics_exporter)
    │   └── Statsig → OtlpHttp (内置 endpoint 和 API key)
    ├── MetricsClient::new(config) [可选]
    │   ├── 验证 default_tags
    │   ├── 构建 Resource (service.name, service.version, env, os)
    │   ├── 创建 ManualReader [如启用 runtime_metrics]
    │   └── 构建 PeriodicReader + SdkMeterProvider
    ├── install_global(metrics) [全局指标客户端]
    ├── build_logger() [如启用日志]
    │   ├── OTLP/gRPC: 使用 tonic + TLS 配置
    │   └── OTLP/HTTP: 使用 reqwest + 协议选择(Binary/JSON)
    ├── build_tracer_provider() [如启用追踪]
    │   └── 根据运行时类型选择 BatchSpanProcessor
    └── global::set_tracer_provider() + set_text_map_propagator()
```

#### 3.2.2 双轨事件导出流程

```rust
// src/events/shared.rs

// 宏展开示例：log_and_trace_event!
log_and_trace_event!(
    self,
    common: { event.name = "codex.user_prompt", prompt_length = %len },
    log:   { prompt = %prompt },           // 仅日志（含敏感数据）
    trace: { text_input_count = 1 },      // 仅追踪（统计数据）
);

// 展开后：
tracing::event!(
    target: "codex_otel.log_only",  // 日志目标
    Level::INFO,
    event.name = "codex.user_prompt",
    prompt_length = %len,
    prompt = %prompt,  // 敏感数据
    // ... 元数据字段
);

tracing::event!(
    target: "codex_otel.trace_safe", // 追踪目标
    Level::INFO,
    event.name = "codex.user_prompt",
    prompt_length = %len,
    text_input_count = 1,  // 统计数据
    // ... 元数据字段（不含敏感信息）
);
```

过滤逻辑：
```rust
// src/targets.rs
pub(crate) fn is_log_export_target(target: &str) -> bool {
    target.starts_with("codex_otel") && !is_trace_safe_target(target)
}

pub(crate) fn is_trace_safe_target(target: &str) -> bool {
    target.starts_with("codex_otel.trace_safe")
}
```

#### 3.2.3 指标记录流程

```rust
// 全局指标（通过 start_global_timer）
start_global_timer("codex.api_request.duration_ms", &[("route", "/responses")])
    └── Timer::new(name, tags, global_client)
        └── Drop::drop() 自动记录持续时间

// SessionTelemetry 指标
session.counter("codex.tool.call", 1, &[("tool", "shell")])
    ├── tags_with_metadata()  // 合并会话元数据标签
    │   └── SessionMetricTagValues::into_tags()
    │       ├── auth_mode, session_source, originator
    │       ├── service_name, model, app_version
    │       └── 验证标签键值
    └── metrics.counter(name, inc, merged_tags)
        ├── validate_metric_name()
        ├── attributes()  // 合并 default_tags
        └── Counter::add()
```

### 3.3 协议实现

#### 3.3.1 OTLP HTTP 客户端构建

```rust
// src/otlp.rs

// 关键函数：处理 tokio 运行时兼容性
pub(crate) fn build_http_client(
    tls: &OtelTlsConfig,
    timeout_var: &str,
) -> Result<reqwest::blocking::Client> {
    if current_tokio_runtime_is_multi_thread() {
        // 多线程运行时：使用 block_in_place 避免阻塞
        tokio::task::block_in_place(|| build_http_client_inner(tls, timeout_var))
    } else if tokio::runtime::Handle::try_current().is_ok() {
        // 单线程运行时：spawn 新线程避免阻塞当前线程
        std::thread::spawn(move || build_http_client_inner(&tls, &timeout_var))
            .join()
            .map_err(...)
    } else {
        // 非 tokio 环境：直接构建
        build_http_client_inner(tls, timeout_var)
    }
}
```

#### 3.3.2 TLS 配置

```rust
// gRPC TLS 配置
fn build_grpc_tls_config(
    endpoint: &str,
    tls_config: ClientTlsConfig,
    tls: &OtelTlsConfig,
) -> Result<ClientTlsConfig> {
    let uri: Uri = endpoint.parse()?;
    let host = uri.host().ok_or_else(...)?;
    let mut config = tls_config.domain_name(host.to_owned());
    
    // CA 证书
    if let Some(path) = tls.ca_certificate.as_ref() {
        let (pem, _) = read_bytes(path)?;
        config = config.ca_certificate(TonicCertificate::from_pem(pem));
    }
    
    // mTLS 客户端证书
    match (&tls.client_certificate, &tls.client_private_key) {
        (Some(cert_path), Some(key_path)) => {
            let (cert_pem, _) = read_bytes(cert_path)?;
            let (key_pem, _) = read_bytes(key_path)?;
            config = config.identity(TonicIdentity::from_pem(cert_pem, key_pem));
        }
        ...
    }
    Ok(config)
}
```

### 3.4 命令与配置

#### 3.4.1 Statsig 内置配置

```rust
// src/config.rs
pub(crate) const STATSIG_OTLP_HTTP_ENDPOINT: &str = "https://ab.chatgpt.com/otlp/v1/metrics";
pub(crate) const STATSIG_API_KEY_HEADER: &str = "statsig-api-key";
pub(crate) const STATSIG_API_KEY: &str = "client-MkRuleRQBd6qakfnDYqJVR9JuXcY57Ljly3vi5JVUIO";

pub(crate) fn resolve_exporter(exporter: &OtelExporter) -> OtelExporter {
    match exporter {
        OtelExporter::Statsig => {
            // 测试环境禁用
            if cfg!(test) || cfg!(feature = "disable-default-metrics-exporter") {
                return OtelExporter::None;
            }
            // 解析为 OTLP/HTTP JSON
            OtelExporter::OtlpHttp { ... }
        }
        _ => exporter.clone(),
    }
}
```

#### 3.4.2 环境变量支持

```rust
// src/trace_context.rs
const TRACEPARENT_ENV_VAR: &str = "TRACEPARENT";
const TRACESTATE_ENV_VAR: &str = "TRACESTATE";

// src/otlp.rs - 超时配置
const OTEL_EXPORTER_OTLP_TIMEOUT: &str = "OTEL_EXPORTER_OTLP_TIMEOUT";
const OTEL_EXPORTER_OTLP_TIMEOUT_DEFAULT: Duration = Duration::from_millis(10000);

fn resolve_otlp_timeout(signal_var: &str) -> Duration {
    // 优先级：信号特定变量 > 通用变量 > 默认值
    read_timeout_env(signal_var)
        .or_else(|| read_timeout_env(OTEL_EXPORTER_OTLP_TIMEOUT))
        .unwrap_or(OTEL_EXPORTER_OTLP_TIMEOUT_DEFAULT)
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心源码文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `src/lib.rs` | 51 | crate 根模块，导出公共 API |
| `src/provider.rs` | 462 | OtelProvider 实现，日志/追踪/指标初始化 |
| `src/config.rs` | 76 | 导出器配置，Statsig 解析 |
| `src/otlp.rs` | 272 | OTLP 协议底层，TLS/HTTP 客户端构建 |
| `src/trace_context.rs` | 174 | W3C Trace Context 传播 |
| `src/targets.rs` | 11 | 日志/追踪目标过滤常量 |
| `src/events/session_telemetry.rs` | 1093 | SessionTelemetry 实现 |
| `src/events/shared.rs` | 60 | 事件记录宏（log_event!, trace_event!） |
| `src/metrics/client.rs` | 406 | MetricsClient 实现 |
| `src/metrics/config.rs` | 83 | MetricsConfig 构建器 |
| `src/metrics/names.rs` | 33 | 指标名称常量 |
| `src/metrics/tags.rs` | 108 | 会话标签值构建 |
| `src/metrics/timer.rs` | 41 | Timer 自动记录持续时间 |
| `src/metrics/validation.rs` | 55 | 指标名称/标签验证 |
| `src/metrics/runtime_metrics.rs` | 216 | 运行时指标汇总 |
| `src/metrics/error.rs` | 46 | 指标错误类型 |

### 4.2 测试文件

| 文件 | 职责 |
|------|------|
| `tests/tests.rs` | 测试入口 |
| `tests/harness/mod.rs` | 测试工具（InMemoryMetricExporter 封装） |
| `tests/suite/send.rs` | 指标发送/标签合并测试 |
| `tests/suite/manager_metrics.rs` | SessionTelemetry 元数据标签测试 |
| `tests/suite/snapshot.rs` | 运行时指标快照测试 |
| `tests/suite/timing.rs` | Timer/Duration 记录测试 |
| `tests/suite/validation.rs` | 指标名称/标签验证测试 |
| `tests/suite/runtime_summary.rs` | RuntimeMetricsSummary 收集测试 |
| `tests/suite/otel_export_routing_policy.rs` | 双轨导出策略测试 |
| `tests/suite/otlp_http_loopback.rs` | OTLP HTTP 端到端测试 |

### 4.3 关键调用链

#### 4.3.1 指标记录完整链路

```
codex_core::tools::orchestrator::execute_tool()
    └── session_telemetry.log_tool_result_with_tags()
        ├── metrics.counter(TOOL_CALL_COUNT_METRIC)
        │   └── MetricsClientInner::counter()
        │       ├── validate_metric_name()
        │       ├── attributes() [合并 default_tags + 传入 tags + 会话元数据]
        │       └── Counter::add()
        ├── metrics.duration_histogram(TOOL_CALL_DURATION_METRIC)
        │   └── MetricsClientInner::duration_histogram()
        └── log_and_trace_event!()
            ├── tracing::event!(target: "codex_otel.log_only", ...)  // 完整日志
            └── tracing::event!(target: "codex_otel.trace_safe", ...) // 脱敏追踪
```

#### 4.3.2 Provider 初始化调用链

```
codex_core::otel_init::build_provider()
    ├── to_otel_exporter(&config.otel.exporter)
    │   └── 转换 Config 中的 OtelExporterKind → OtelExporter
    └── OtelProvider::from(&OtelSettings)
        ├── resolve_exporter() [Statsig 解析]
        ├── MetricsClient::new() [如启用]
        ├── build_logger() [如启用]
        ├── build_tracer_provider() [如启用]
        └── global::set_tracer_provider()
```

---

## 5. 依赖与外部交互

### 5.1 外部依赖

| Crate | 用途 |
|-------|------|
| `opentelemetry` | OTEL API（日志、追踪、指标） |
| `opentelemetry_sdk` | OTEL SDK 实现 |
| `opentelemetry_otlp` | OTLP 导出器（HTTP/gRPC） |
| `opentelemetry-appender-tracing` | tracing 到 OTEL 日志桥接 |
| `tracing-opentelemetry` | tracing 到 OTEL 追踪桥接 |
| `tracing-subscriber` | tracing 订阅者基础设施 |
| `reqwest` | HTTP 客户端（阻塞 + 异步） |
| `tokio` | 异步运行时适配 |
| `serde/serde_json` | JSON 序列化 |
| `chrono` | 时间戳格式化 |
| `gethostname` | 主机名获取 |
| `os_info` | 操作系统信息采集 |

### 5.2 内部依赖

| Crate | 用途 |
|-------|------|
| `codex-protocol` | ThreadId, W3cTraceContext, SessionSource 等协议类型 |
| `codex-api` | ApiError, ResponseEvent 等 API 类型 |
| `codex-utils-string` | sanitize_metric_tag_value |
| `codex-utils-absolute-path` | AbsolutePathBuf |

### 5.3 被依赖关系

| Crate | 用途 |
|-------|------|
| `codex-core` | 核心遥测初始化（otel_init.rs, auth_env_telemetry.rs） |
| `codex-tui` | TUI 会话遥测（SessionTelemetry 使用） |
| `codex-exec` | exec 模式遥测 |
| `codex-app-server` | 应用服务器遥测 |
| `codex-app-server-test-client` | 测试客户端遥测 |
| `codex-cloud-requirements` | 云端需求遥测 |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 敏感数据泄露风险

**风险点**：`log_event!` 宏会记录完整提示词和工具输出。

**缓解措施**：
- `SessionTelemetryMetadata.log_user_prompts` 开关控制是否记录完整提示词
- 双轨策略确保敏感数据只进入日志系统，不进入追踪系统
- 用户可通过配置禁用遥测

**代码位置**：`src/events/session_telemetry.rs:817-858`

#### 6.1.2 运行时兼容性风险

**风险点**：tokio 运行时类型（单线程/多线程）影响 HTTP 客户端构建方式。

**缓解措施**：
- `current_tokio_runtime_is_multi_thread()` 自动检测运行时类型
- 单线程运行时使用 `std::thread::spawn` 避免阻塞

**代码位置**：`src/otlp.rs:70-99`

#### 6.1.3 指标名称/标签验证

**限制**：指标名称和标签有严格的字符限制（仅允许 ASCII 字母数字、`.`、`_`、`-`，标签额外允许 `/`）。

**潜在问题**：非法字符会导致指标记录失败。

**代码位置**：`src/metrics/validation.rs`

### 6.2 边界情况

#### 6.2.1 全局指标客户端

- 通过 `OnceLock` 设置，只能初始化一次
- 测试中使用 `InMemoryMetricExporter` 需启用 `with_runtime_reader()` 才能获取快照

#### 6.2.2 Statsig 导出器

- 测试环境自动禁用（`cfg!(test)`）
- 通过 feature `disable-default-metrics-exporter` 可显式禁用

#### 6.2.3 TLS 配置

- mTLS 需要同时提供客户端证书和私钥
- CA 证书配置会禁用内置根证书

### 6.3 改进建议

#### 6.3.1 可观测性增强

1. **指标记录失败告警**：当前指标记录失败仅通过 `tracing::warn!` 输出，建议增加错误统计指标
2. **导出延迟监控**：增加 OTLP 导出延迟的直方图指标
3. **导出失败重试**：当前无自动重试机制，建议增加指数退避重试

#### 6.3.2 性能优化

1. **标签缓存**：`attributes()` 每次合并标签时创建新 Vec，高频场景可考虑缓存
2. **批量指标**：当前每次调用立即记录，考虑增加本地缓冲批量发送

#### 6.3.3 代码结构

1. **SessionTelemetry 拆分**：当前文件超过 1000 行，建议按事件类型拆分为子模块
2. **错误类型细化**：`MetricsError` 可进一步细分以支持更精确的错误处理

#### 6.3.4 测试覆盖

1. **gRPC 端到端测试**：当前仅 HTTP 有 loopback 测试
2. **TLS/mTLS 测试**：需要证书 fixtures 支持
3. **并发场景测试**：多线程指标记录的正确性

### 6.4 配置建议

```toml
# 生产环境推荐配置
[otel]
environment = "prod"
exporter = { kind = "OtlpHttp", endpoint = "...", protocol = "Binary" }
trace_exporter = { kind = "OtlpHttp", endpoint = "...", protocol = "Binary" }
metrics_exporter = "Statsig"  # 使用内置 Statsig 配置

# 测试环境配置
[otel]
metrics_exporter = "None"  # 完全禁用指标导出
```

---

## 7. 附录

### 7.1 指标名称常量列表

```rust
// src/metrics/names.rs
pub const TOOL_CALL_COUNT_METRIC: &str = "codex.tool.call";
pub const TOOL_CALL_DURATION_METRIC: &str = "codex.tool.call.duration_ms";
pub const API_CALL_COUNT_METRIC: &str = "codex.api_request";
pub const API_CALL_DURATION_METRIC: &str = "codex.api_request.duration_ms";
pub const SSE_EVENT_COUNT_METRIC: &str = "codex.sse_event";
pub const SSE_EVENT_DURATION_METRIC: &str = "codex.sse_event.duration_ms";
pub const WEBSOCKET_REQUEST_COUNT_METRIC: &str = "codex.websocket.request";
pub const WEBSOCKET_REQUEST_DURATION_METRIC: &str = "codex.websocket.request.duration_ms";
pub const WEBSOCKET_EVENT_COUNT_METRIC: &str = "codex.websocket.event";
pub const WEBSOCKET_EVENT_DURATION_METRIC: &str = "codex.websocket.event.duration_ms";
pub const RESPONSES_API_OVERHEAD_DURATION_METRIC: &str = "codex.responses_api_overhead.duration_ms";
pub const RESPONSES_API_INFERENCE_TIME_DURATION_METRIC: &str = "codex.responses_api_inference_time.duration_ms";
pub const RESPONSES_API_ENGINE_IAPI_TTFT_DURATION_METRIC: &str = "codex.responses_api_engine_iapi_ttft.duration_ms";
pub const RESPONSES_API_ENGINE_SERVICE_TTFT_DURATION_METRIC: &str = "codex.responses_api_engine_service_ttft.duration_ms";
pub const RESPONSES_API_ENGINE_IAPI_TBT_DURATION_METRIC: &str = "codex.responses_api_engine_iapi_tbt.duration_ms";
pub const RESPONSES_API_ENGINE_SERVICE_TBT_DURATION_METRIC: &str = "codex.responses_api_engine_service_tbt.duration_ms";
pub const TURN_E2E_DURATION_METRIC: &str = "codex.turn.e2e_duration_ms";
pub const TURN_TTFT_DURATION_METRIC: &str = "codex.turn.ttft.duration_ms";
pub const TURN_TTFM_DURATION_METRIC: &str = "codex.turn.ttfm.duration_ms";
pub const TURN_NETWORK_PROXY_METRIC: &str = "codex.turn.network_proxy";
pub const TURN_TOOL_CALL_METRIC: &str = "codex.turn.tool.call";
pub const TURN_TOKEN_USAGE_METRIC: &str = "codex.turn.token_usage";
pub const STARTUP_PREWARM_DURATION_METRIC: &str = "codex.startup_prewarm.duration_ms";
pub const STARTUP_PREWARM_AGE_AT_FIRST_TURN_METRIC: &str = "codex.startup_prewarm.age_at_first_turn_ms";
pub const THREAD_STARTED_METRIC: &str = "codex.thread.started";
```

### 7.2 会话标签常量列表

```rust
// src/metrics/tags.rs
pub const APP_VERSION_TAG: &str = "app.version";
pub const AUTH_MODE_TAG: &str = "auth_mode";
pub const MODEL_TAG: &str = "model";
pub const ORIGINATOR_TAG: &str = "originator";
pub const SERVICE_NAME_TAG: &str = "service_name";
pub const SESSION_SOURCE_TAG: &str = "session_source";
```

---

*文档生成时间：2026-03-21*
*研究对象：codex-rs/otel 目录*
*版本：基于仓库最新 main 分支*
