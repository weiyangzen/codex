# codex-rs/otel/src 深度研究文档

## 1. 场景与职责

### 1.1 定位与目标

`codex-otel` 是 Codex 项目的 OpenTelemetry 集成 crate，负责提供统一的**可观测性（Observability）**基础设施。它桥接 Codex 业务逻辑与 OpenTelemetry 生态，实现：

- **指标（Metrics）**：业务指标收集与导出（Counter、Histogram、Timer）
- **链路追踪（Tracing）**：分布式追踪上下文传递与 Span 生成
- **日志（Logs）**：结构化日志事件导出
- **会话遥测（Session Telemetry）**：Codex 特定的业务事件抽象层

### 1.2 使用场景

| 场景 | 说明 |
|------|------|
| CLI/TUI 应用 | 通过 `OtelProvider` 初始化 OTEL 基础设施，集成到 tracing_subscriber |
| App Server | 服务端指标收集，支持 Statsig 内部分析平台 |
| 测试环境 | InMemoryExporter 用于断言验证，disable-default-metrics-exporter feature 禁用网络导出 |
| 运行时诊断 | RuntimeMetricsSummary 提供会话级性能汇总 |

### 1.3 架构位置

```
codex-cli/codex-exec/codex-tui/codex-app-server
    ↓
codex-core (业务逻辑)
    ↓
codex-otel (可观测性抽象层)
    ↓
opentelemetry-rs SDK / OTLP Exporter
    ↓
Statsig / Jaeger / 其他 OTLP Collector
```

---

## 2. 功能点目的

### 2.1 核心模块功能矩阵

| 模块 | 文件 | 功能目的 |
|------|------|----------|
| `lib.rs` | 根模块 | 公共 API 导出、全局 Timer 快捷函数、ToolDecisionSource/TelemetryAuthMode 类型定义 |
| `config.rs` | 配置定义 | OtelSettings、OtelExporter 枚举（None/Statsig/OtlpHttp/OtlpGrpc）、TLS 配置 |
| `provider.rs` | 提供者 | OtelProvider 统一入口，管理 Logger/Tracer/Metrics 三件套生命周期 |
| `trace_context.rs` | 追踪上下文 | W3C Trace Context 解析与注入，支持 TRACEPARENT 环境变量 |
| `otlp.rs` | OTLP 工具 | HTTP/gRPC 客户端构建、TLS/mTLS 配置、Tokio 运行时检测 |
| `targets.rs` | 目标过滤 | tracing target 前缀常量与过滤函数（log_only vs trace_safe） |
| `events/` | 事件模块 | SessionTelemetry 业务事件封装与宏定义 |
| `metrics/` | 指标模块 | MetricsClient、指标名称常量、标签管理、运行时指标汇总 |

### 2.2 SessionTelemetry 业务事件

SessionTelemetry 是 Codex 业务语义的核心抽象，封装了：

- **身份元数据**：conversation_id、account_id、auth_mode、originator
- **模型元数据**：model、slug、session_source
- **隐私控制**：log_user_prompts 开关控制敏感数据是否记录
- **指标代理**：可选的 MetricsClient 用于发送业务指标

主要事件类型：
- `conversation_starts`: 会话启动配置快照
- `user_prompt`: 用户输入（支持文本/图片/本地图片）
- `tool_result`: 工具执行结果（支持 MCP 工具标记）
- `api_request`/`websocket_connect`/`websocket_request`: 网络层事件
- `auth_recovery`: 认证恢复流程
- `sse_event`/`websocket_event`: 流式事件

### 2.3 指标类型与命名规范

指标名称定义于 `metrics/names.rs`：

```rust
// 工具调用
codex.tool.call / codex.tool.call.duration_ms

// API 请求
codex.api_request / codex.api_request.duration_ms

// SSE 流事件
codex.sse_event / codex.sse_event.duration_ms

// WebSocket
codex.websocket.request / codex.websocket.event

// 响应 API 性能分解
codex.responses_api_overhead.duration_ms
codex.responses_api_inference_time.duration_ms
codex.responses_api_engine_iapi_ttft.duration_ms
...

// 回合级指标
codex.turn.e2e_duration_ms / codex.turn.ttft.duration_ms / codex.turn.ttfm.duration_ms
```

---

## 3. 具体技术实现

### 3.1 OtelProvider 初始化流程

```rust
// provider.rs:67-120
pub fn from(settings: &OtelSettings) -> Result<Option<Self>, Box<dyn Error>> {
    // 1. 解析 metrics_exporter（支持 Statsig 特殊处理）
    let metric_exporter = crate::config::resolve_exporter(&settings.metrics_exporter);
    let metrics = if matches!(metric_exporter, OtelExporter::None) { ... }
    
    // 2. 安装全局 MetricsClient（供 start_global_timer 使用）
    if let Some(metrics) = metrics.as_ref() {
        crate::metrics::install_global(metrics.clone());
    }
    
    // 3. 构建 Resource（服务名、版本、环境、主机名）
    let log_resource = make_resource(settings, ResourceKind::Logs);
    let trace_resource = make_resource(settings, ResourceKind::Traces);
    
    // 4. 构建 LoggerProvider（支持 OTLP HTTP/gRPC）
    let logger = log_enabled.then(|| build_logger(...)).transpose()?;
    
    // 5. 构建 TracerProvider（支持 BatchSpanProcessor）
    let tracer_provider = trace_enabled.then(|| build_tracer_provider(...)).transpose()?;
    
    // 6. 注册全局 propagator（W3C Trace Context）
    global::set_tracer_provider(provider);
    global::set_text_map_propagator(TraceContextPropagator::new());
}
```

### 3.2 Statsig 集成机制

```rust
// config.rs:6-28
pub(crate) const STATSIG_OTLP_HTTP_ENDPOINT: &str = "https://ab.chatgpt.com/otlp/v1/metrics";
pub(crate) const STATSIG_API_KEY_HEADER: &str = "statsig-api-key";
pub(crate) const STATSIG_API_KEY: &str = "client-MkRuleRQBd6qakfnDYqJVR9JuXcY57Ljly3vi5JVUIO";

pub(crate) fn resolve_exporter(exporter: &OtelExporter) -> OtelExporter {
    match exporter {
        OtelExporter::Statsig => {
            // 测试环境或 disable-default-metrics-exporter feature 时禁用
            if cfg!(test) || cfg!(feature = "disable-default-metrics-exporter") {
                return OtelExporter::None;
            }
            // 解析为 OTLP/HTTP JSON 配置
            OtelExporter::OtlpHttp { endpoint: STATSIG_OTLP_HTTP_ENDPOINT, ... }
        }
        _ => exporter.clone(),
    }
}
```

### 3.3 日志与追踪分离策略

通过 `targets.rs` 定义的目标前缀实现双轨导出：

```rust
pub(crate) const OTEL_LOG_ONLY_TARGET: &str = "codex_otel.log_only";
pub(crate) const OTEL_TRACE_SAFE_TARGET: &str = "codex_otel.trace_safe";

pub(crate) fn is_log_export_target(target: &str) -> bool {
    target.starts_with(OTEL_TARGET_PREFIX) && !is_trace_safe_target(target)
}

pub(crate) fn is_trace_safe_target(target: &str) -> bool {
    target.starts_with(OTEL_TRACE_SAFE_TARGET)
}
```

**设计意图**：
- `log_only`: 包含敏感信息（用户提示、工具参数/输出），仅导出到日志系统
- `trace_safe`: 脱敏后的统计信息（长度、计数），可导出到分布式追踪系统

宏封装（`events/shared.rs`）：
```rust
macro_rules! log_event {
    // 使用 OTEL_LOG_ONLY_TARGET，包含完整敏感数据
}
macro_rules! trace_event {
    // 使用 OTEL_TRACE_SAFE_TARGET，仅包含统计信息
}
macro_rules! log_and_trace_event {
    // 同时触发两者，common 字段共享，log/trace 字段分离
}
```

### 3.4 MetricsClient 实现细节

```rust
// metrics/client.rs:81-90
struct MetricsClientInner {
    meter_provider: SdkMeterProvider,
    meter: Meter,
    counters: Mutex<HashMap<String, Counter<u64>>>,  // 懒加载缓存
    histograms: Mutex<HashMap<String, Histogram<f64>>>,
    duration_histograms: Mutex<HashMap<String, Histogram<f64>>>,
    runtime_reader: Option<Arc<ManualReader>>,  // 用于 snapshot()
    default_tags: BTreeMap<String, String>,
}
```

关键设计：
- **懒加载**：Counter/Histogram 按需创建并缓存，避免重复注册
- **标签合并**：default_tags 与调用时 tags 合并，调用时标签优先级更高
- **运行时快照**：通过 `ManualReader` 实现不关闭 provider 的指标采集

### 3.5 TLS/mTLS 支持

```rust
// otlp.rs:34-68
pub(crate) fn build_grpc_tls_config(
    endpoint: &str,
    tls_config: ClientTlsConfig,
    tls: &OtelTlsConfig,
) -> Result<ClientTlsConfig, Box<dyn Error>> {
    let uri: Uri = endpoint.parse()?;
    let host = uri.host().ok_or_else(...)?;
    let mut config = tls_config.domain_name(host.to_owned());
    
    // CA 证书
    if let Some(path) = tls.ca_certificate.as_ref() { ... }
    
    // mTLS 双向认证
    match (&tls.client_certificate, &tls.client_private_key) {
        (Some(cert_path), Some(key_path)) => { ... }
        (Some(_), None) | (None, Some(_)) => {
            return Err(config_error("client_certificate and client_private_key must both be provided for mTLS"));
        }
        (None, None) => {}
    }
}
```

### 3.6 Tokio 运行时适配

```rust
// otlp.rs:94-99
pub(crate) fn current_tokio_runtime_is_multi_thread() -> bool {
    match tokio::runtime::Handle::try_current() {
        Ok(handle) => handle.runtime_flavor() == tokio::runtime::RuntimeFlavor::MultiThread,
        Err(_) => false,
    }
}
```

影响：
- **多线程运行时**：使用 `TokioBatchSpanProcessor` 异步处理 span
- **当前线程运行时**：使用阻塞 HTTP 客户端，避免在单线程运行时产生死锁

### 3.7 Timer 自动记录机制

```rust
// metrics/timer.rs:13-19
impl Drop for Timer {
    fn drop(&mut self) {
        if let Err(e) = self.record(&[]) {
            tracing::error!("metrics client error: {}", e);
        }
    }
}
```

使用 RAII 模式，Timer 离开作用域时自动记录持续时间。

---

## 4. 关键代码路径与文件引用

### 4.1 初始化路径

```
codex-core/src/otel_init.rs:build_provider
    ↓ 转换 Config → OtelSettings
codex-otel/src/provider.rs:OtelProvider::from
    ↓
codex-otel/src/config.rs:resolve_exporter  // Statsig 特殊处理
    ↓
build_logger / build_tracer_provider / MetricsClient::new
```

### 4.2 业务事件记录路径

```
SessionTelemetry::user_prompt / tool_result / record_api_request / ...
    ↓
events/shared.rs:log_and_trace_event! 宏
    ↓
tracing::event!(
    target: OTEL_LOG_ONLY_TARGET / OTEL_TRACE_SAFE_TARGET,
    ...
)
    ↓
provider.rs:logger_layer / tracing_layer
    ↓
OpenTelemetryTracingBridge / tracing_opentelemetry::layer
```

### 4.3 指标发送路径

```
SessionTelemetry::counter / histogram / record_duration
    ↓
MetricsClient::counter / histogram / record_duration
    ↓
MetricsClientInner::counter / histogram / duration_histogram
    ↓
validate_metric_name / validate_tag_key / validate_tag_value
    ↓
opentelemetry::Counter::add / Histogram::record
```

### 4.4 追踪上下文传递路径

```
W3C Trace Context (HTTP Header / Env)
    ↓
trace_context.rs:context_from_w3c_trace_context
    ↓
trace_context.rs:set_parent_from_w3c_trace_context
    ↓
tracing_opentelemetry::OpenTelemetrySpanExt::set_parent
```

### 4.5 运行时指标汇总路径

```
SessionTelemetry::runtime_metrics_summary
    ↓
MetricsClient::snapshot
    ↓
ManualReader::collect → ResourceMetrics
    ↓
runtime_metrics.rs:RuntimeMetricsSummary::from_snapshot
    ↓
sum_counter / sum_histogram_ms 聚合
```

---

## 5. 依赖与外部交互

### 5.1 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `opentelemetry` | OTEL API（Counter、Histogram、Tracer 等） |
| `opentelemetry_sdk` | SDK 实现（Provider、Exporter、Resource） |
| `opentelemetry_otlp` | OTLP 导出器（HTTP/gRPC） |
| `opentelemetry-appender-tracing` | tracing → OTEL Logs 桥接 |
| `tracing-opentelemetry` | tracing → OTEL Traces 桥接 |
| `opentelemetry-semantic-conventions` | 标准属性名（service.name 等） |
| `reqwest` | HTTP 客户端（阻塞 + 异步） |
| `tokio` | 运行时检测与异步支持 |
| `gethostname` | 主机名获取 |
| `os_info` | 操作系统信息采集 |
| `chrono` | 时间戳格式化 |
| `serde/serde_json` | JSON 序列化 |

### 5.2 内部 Crate 依赖

| Crate | 交互方式 |
|-------|----------|
| `codex-protocol` | ThreadId、SessionSource、W3cTraceContext、ResponseEvent、ResponseItem、UserInput |
| `codex-api` | ApiError |
| `codex-utils-string` | sanitize_metric_tag_value |
| `codex-utils-absolute-path` | AbsolutePathBuf（TLS 证书路径） |

### 5.3 调用方分析

| 调用方 | 用途 |
|--------|------|
| `codex-core` | 主要消费者，通过 `otel_init.rs` 初始化，在 `Codex` 结构体中持有 `SessionTelemetry` |
| `codex-tui` | TUI 应用初始化 OTEL，集成到 ratatui 事件循环 |
| `codex-tui_app_server` | App Server 模式下的遥测 |
| `codex-exec` | 执行模式下的轻量遥测 |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 位置 | 说明 |
|------|------|------|
| **硬编码 API Key** | `config.rs:8` | Statsig API Key 硬编码在源码中，存在泄露风险 |
| **Panics in Drop** | `timer.rs:14-17` | Timer::drop 中调用 record 可能 panic，虽捕获错误但可能丢失指标 |
| **Mutex Poisoning** | `client.rs:103-106` | 使用 `unwrap_or_else(std::sync::PoisonError::into_inner)` 处理 poison，可能掩盖并发 bug |
| **Tokio 运行时检测局限** | `otlp.rs:94-99` | 仅在构建时检测运行时类型，运行时切换可能导致行为不一致 |
| **TLS 证书路径验证** | `otlp.rs:215-223` | 证书文件读取错误仅包装为 io::Error，缺乏详细上下文 |

### 6.2 边界条件

| 边界 | 行为 |
|------|------|
| 空指标名 | `MetricsError::EmptyMetricName` |
| 负计数器增量 | `MetricsError::NegativeCounterIncrement` |
| 非法标签字符 | `MetricsError::InvalidTagComponent`（key 仅允许 `[a-zA-Z0-9._-]`，value 额外允许 `/`） |
| 缺失 TRACEPARENT | `traceparent_context_from_env()` 返回 None，不中断流程 |
| 无效 TRACEPARENT | 打印 warning，返回 None |
| 未初始化全局 Metrics | `start_global_timer` 返回 `MetricsError::ExporterDisabled` |

### 6.3 改进建议

#### 6.3.1 安全性

1. **Statsig API Key 外部化**
   ```rust
   // 建议：从环境变量或配置文件读取
   pub(crate) const STATSIG_API_KEY: &str = env!("STATSIG_API_KEY", "fallback-key");
   ```

2. **敏感数据脱敏增强**
   - 当前 `log_user_prompts` 是布尔开关，建议改为分级策略（None/Hash/Full）
   - 工具输出可考虑截断策略，避免超大输出导致内存压力

#### 6.3.2 可靠性

1. **MetricsClient 优雅降级**
   - 当前 `counter`/`histogram` 失败时返回 Err，建议增加 `try_counter` 与 `counter_or_log` 变体
   - 考虑添加指标发送缓冲区，避免网络抖动导致指标丢失

2. **Timer Drop 优化**
   ```rust
   // 建议：使用 try_record 避免 panic 风险
   impl Drop for Timer {
       fn drop(&mut self) {
           let _ = self.record(&[]);  // 已是无视错误，但内部仍有 unwrap
       }
   }
   ```

#### 6.3.3 可维护性

1. **指标名称常量化管理**
   - `names.rs` 已定义常量，但部分代码仍使用字符串字面量（如测试中的 `"codex.turns"`），建议统一

2. **SessionTelemetry 方法拆分**
   - 当前 `session_telemetry.rs` 超过 1000 行，建议按事件类型拆分为子模块：
     ```
     events/
       mod.rs
       session_telemetry.rs  // 核心结构体
       conversation.rs       // conversation_starts
       network.rs            // api_request, websocket_*
       tools.rs              // tool_result, tool_decision
       streaming.rs          // sse_event, websocket_event
     ```

3. **配置验证增强**
   - `OtelSettings` 构建时验证 endpoint URL 格式
   - TLS 配置验证证书文件存在性（当前延迟到 exporter 构建时）

#### 6.3.4 性能

1. **标签分配优化**
   - 当前 `tags_with_metadata` 每次分配 Vec，高频调用场景可考虑对象池
   - `SessionMetricTagValues::into_tags` 返回 `Vec<(&str, &str)>`，生命周期约束复杂，可考虑 `'static` 缓存

2. **指标批处理**
   - 当前每个 `counter`/`histogram` 调用立即记录，考虑增加本地批处理减少锁竞争

#### 6.3.5 测试

1. **覆盖率缺口**
   - `otlp.rs` 的 `build_grpc_tls_config` 缺乏测试（需要 mock tonic）
   - `trace_context.rs` 的 `traceparent_context_from_env` 依赖环境变量，测试隔离性不足

2. **集成测试增强**
   - 建议添加与 `wiremock` 或 `mockito` 的集成测试，验证 OTLP HTTP 导出行为
   - 当前 `otlp_http_loopback.rs` 使用原始 TCP，可考虑替换为更稳定的 mock

---

## 附录：文件清单

```
codex-rs/otel/
├── Cargo.toml              # 依赖定义，features: disable-default-metrics-exporter
├── BUILD.bazel             # Bazel 构建配置
├── README.md               # 使用文档
├── src/
│   ├── lib.rs              # 根模块，公共 API 导出
│   ├── config.rs           # OtelSettings、OtelExporter、TLS 配置
│   ├── provider.rs         # OtelProvider：Logger/Tracer/Metrics 统一管理
│   ├── trace_context.rs    # W3C Trace Context 解析与注入
│   ├── otlp.rs             # OTLP HTTP/gRPC 客户端构建
│   ├── targets.rs          # tracing target 常量与过滤
│   ├── events/
│   │   ├── mod.rs          # 事件模块入口
│   │   ├── session_telemetry.rs  # SessionTelemetry 实现（1000+ 行）
│   │   └── shared.rs       # log_event!/trace_event! 宏定义
│   └── metrics/
│       ├── mod.rs          # 指标模块入口，全局 MetricsClient
│       ├── client.rs       # MetricsClient 实现
│       ├── config.rs       # MetricsConfig 构建器
│       ├── error.rs        # MetricsError 枚举
│       ├── names.rs        # 指标名称常量
│       ├── tags.rs         # SessionMetricTagValues 标签管理
│       ├── timer.rs        # Timer RAII 实现
│       ├── validation.rs   # 指标名/标签验证
│       └── runtime_metrics.rs  # RuntimeMetricsSummary 汇总
└── tests/
    ├── tests.rs            # 测试入口
    ├── harness/
    │   └── mod.rs          # 测试工具函数
    └── suite/
        ├── mod.rs          # 测试套件入口
        ├── manager_metrics.rs    # SessionTelemetry 标签测试
        ├── otel_export_routing_policy.rs  # 日志/追踪分离策略测试
        ├── otlp_http_loopback.rs  # OTLP HTTP 端到端测试
        ├── runtime_summary.rs     # 运行时指标汇总测试
        ├── send.rs                # MetricsClient 发送测试
        ├── snapshot.rs            # 指标快照测试
        ├── timing.rs              # Timer 测试
        └── validation.rs          # 验证逻辑测试
```

---

*文档生成时间：2026-03-22*
*研究范围：codex-rs/otel/src 及其测试、依赖、调用方*
