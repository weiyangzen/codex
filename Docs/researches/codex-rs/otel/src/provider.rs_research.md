# codex-rs/otel/src/provider.rs 研究文档

## 场景与职责

`provider.rs` 是 `codex-otel` crate 的核心模块，实现了 `OtelProvider` 结构体——整个 OTEL 系统的中央协调器。它负责初始化和管理日志、追踪、指标三大遥测系统的导出器，并提供与 `tracing` 生态系统的集成层。

**核心职责：**
1. 从 `OtelSettings` 构建和配置 OTEL Provider
2. 初始化日志导出器（SdkLoggerProvider）
3. 初始化追踪导出器（SdkTracerProvider）和 Tracer
4. 初始化指标客户端（MetricsClient）
5. 提供 `tracing_subscriber` 集成层（Layer）
6. 实现资源（Resource）属性管理
7. 实现日志和追踪的目标过滤

## 功能点目的

### 1. OtelProvider 结构体

```rust
pub struct OtelProvider {
    pub logger: Option<SdkLoggerProvider>,
    pub tracer_provider: Option<SdkTracerProvider>,
    pub tracer: Option<Tracer>,
    pub metrics: Option<MetricsClient>,
}
```

**设计意图：**
- 所有字段都是 `Option`，允许部分启用（如仅指标、仅追踪等）
- 提供统一的关闭接口（`shutdown` 方法和 `Drop` 实现）
- 通过 `logger_layer()` 和 `tracing_layer()` 与 `tracing_subscriber` 集成

### 2. Provider 构建流程

`OtelProvider::from(&OtelSettings)` 的构建逻辑：

```
1. 解析 metrics_exporter（处理 Statsig 简写）
2. 如果 metrics_exporter 不是 None，构建 MetricsClient
3. 安装全局指标客户端（用于 start_global_timer）
4. 如果所有导出器都是 None，返回 Ok(None)（完全禁用 OTEL）
5. 构建日志 Resource（包含 host.name）
6. 构建追踪 Resource（不包含 host.name）
7. 构建 Logger（如果 exporter 不是 None）
8. 构建 TracerProvider 和 Tracer（如果 trace_exporter 不是 None）
9. 设置全局 TracerProvider 和 Propagator
```

### 3. 资源属性管理

```rust
fn make_resource(settings: &OtelSettings, kind: ResourceKind) -> Resource
```

**资源属性：**
- `service.name`: 服务名称（来自 settings）
- `service.version`: 服务版本
- `env`: 环境（dev/staging/prod）
- `host.name`: 主机名（仅日志资源）
- `os`, `os_version`: 操作系统信息（来自 metrics/client.rs）

**设计决策：**
- 日志和追踪使用不同的 Resource，因为日志需要 host.name 用于日志聚合
- 主机名通过 `gethostname` crate 获取并规范化

### 4. 导出器构建

**日志导出器 (`build_logger`):**
- 支持 OTLP/gRPC 和 OTLP/HTTP 两种协议
- gRPC 使用 Tonic 客户端，支持 mTLS
- HTTP 使用 `opentelemetry_otlp::LogExporter`，支持 Binary/JSON 协议

**追踪导出器 (`build_tracer_provider`):**
- 支持 OTLP/gRPC 和 OTLP/HTTP 两种协议
- **关键差异**: HTTP 协议根据运行时类型选择不同的 SpanProcessor
  - 多线程 Tokio: 使用 `TokioBatchSpanProcessor`（异步运行时集成）
  - 单线程/无 Tokio: 使用标准 `BatchSpanProcessor`

### 5. Tracing 集成层

**日志层 (`logger_layer`):**
```rust
pub fn logger_layer<S>(&self) -> Option<impl Layer<S> + Send + Sync>
```
- 使用 `OpenTelemetryTracingBridge` 将 `tracing` 事件转换为 OTEL 日志
- 应用 `log_export_filter` 过滤目标

**追踪层 (`tracing_layer`):**
```rust
pub fn tracing_layer<S>(&self) -> Option<impl Layer<S> + Send + Sync>
```
- 使用 `tracing_opentelemetry` 将 `tracing` span 转换为 OTEL span
- 应用 `trace_export_filter` 过滤目标

### 6. 目标过滤

```rust
pub fn log_export_filter(meta: &tracing::Metadata<'_>) -> bool {
    is_log_export_target(meta.target())
}

pub fn trace_export_filter(meta: &tracing::Metadata<'_>) -> bool {
    meta.is_span() || is_trace_safe_target(meta.target())
}
```

**过滤规则：**
- `log_export_filter`: 目标以 `codex_otel` 开头，但不以 `codex_otel.trace_safe` 开头
- `trace_export_filter`: 是 span，或目标以 `codex_otel.trace_safe` 开头

这实现了**双轨事件系统**：
- `codex_otel.log_only`: 仅发送到日志后端（如 Loki）
- `codex_otel.trace_safe`: 发送到日志和追踪后端
- 其他 `codex_otel.*`: 仅发送到日志后端

## 具体技术实现

### 资源构建

```rust
fn resource_attributes(
    settings: &OtelSettings,
    host_name: Option<&str>,
    kind: ResourceKind,
) -> Vec<KeyValue> {
    let mut attributes = vec![
        KeyValue::new(semconv::attribute::SERVICE_VERSION, settings.service_version.clone()),
        KeyValue::new(ENV_ATTRIBUTE, settings.environment.clone()),
    ];
    if kind == ResourceKind::Logs && let Some(host_name) = host_name.and_then(normalize_host_name) {
        attributes.push(KeyValue::new(HOST_NAME_ATTRIBUTE, host_name));
    }
    attributes
}
```

### SpanProcessor 选择逻辑

```rust
if crate::otlp::current_tokio_runtime_is_multi_thread() {
    // 多线程 Tokio：使用 TokioBatchSpanProcessor
    let processor = TokioBatchSpanProcessor::builder(exporter_builder.build()?, runtime::Tokio).build();
    return Ok(SdkTracerProvider::builder()
        .with_resource(resource.clone())
        .with_span_processor(processor)
        .build());
}

// 单线程/无 Tokio：使用标准 BatchSpanProcessor
let processor = BatchSpanProcessor::builder(span_exporter).build();
```

### 全局传播器设置

```rust
if let Some(provider) = tracer_provider.clone() {
    global::set_tracer_provider(provider);
    global::set_text_map_propagator(TraceContextPropagator::new());
}
```

这确保了：
1. `tracing_opentelemetry` 可以获取到 Tracer
2. W3C Trace Context 可以在进程间传播

## 关键代码路径与文件引用

### 模块依赖图

```
provider.rs
├── config.rs
│   └── OtelSettings, OtelExporter, resolve_exporter
├── metrics/mod.rs
│   └── MetricsClient, install_global
├── targets.rs
│   └── is_log_export_target, is_trace_safe_target
└── otlp.rs
    ├── build_header_map
    ├── build_grpc_tls_config
    ├── build_http_client
    ├── build_async_http_client
    └── current_tokio_runtime_is_multi_thread
```

### 外部调用方

**`codex-rs/core/src/otel_init.rs`:**
```rust
use codex_otel::OtelProvider;
// 构建 OtelSettings 后调用 OtelProvider::from(&settings)
```

**`codex-rs/tui/src/app.rs`:**
```rust
if let Some(provider) = OtelProvider::from(&settings)? {
    let registry = tracing_subscriber::registry()
        .with(provider.logger_layer())
        .with(provider.tracing_layer());
    registry.init();
}
```

**`codex-rs/app-server/src/app_server_tracing.rs`:**
```rust
use codex_otel::OtelProvider;
// 初始化 App Server 的追踪系统
```

## 依赖与外部交互

### 外部 crate 依赖

**OpenTelemetry 生态:**
- `opentelemetry`: 核心 API
- `opentelemetry_sdk`: SDK 实现（Resource, TracerProvider, LoggerProvider）
- `opentelemetry_otlp`: OTLP 导出器
- `opentelemetry_semantic_conventions`: 标准属性名
- `opentelemetry_appender_tracing`: tracing 到 OTEL 日志的桥接
- `tracing_opentelemetry`: tracing 到 OTEL 追踪的桥接

**Tracing 生态:**
- `tracing`: 日志和追踪 facade
- `tracing_subscriber`: 订阅者实现

**其他:**
- `gethostname`: 获取主机名

### 内部依赖
- `config`: 配置类型和解析
- `metrics`: 指标客户端
- `targets`: 目标过滤
- `otlp`: OTLP 客户端构建

## 风险、边界与改进建议

### 资源管理风险

1. **Drop 顺序依赖**: `Drop` 实现中先 flush tracer，再 metrics，最后 logger
   - 如果存在跨系统的依赖（如日志中包含追踪 ID），顺序很重要
   - 当前顺序是合理的，但需要维护

2. **全局状态污染**: `global::set_tracer_provider` 设置全局状态
   - 如果多个 Provider 被创建，后者会覆盖前者
   - 建议：添加警告日志或返回错误

### 运行时适配风险

1. **SpanProcessor 选择**: 运行时检测在构建时进行，如果运行时类型后续改变会出问题
   - 实际上运行时类型不会改变，这是安全的

2. **Tokio 依赖**: `TokioBatchSpanProcessor` 依赖 Tokio 运行时
   - 如果在非 Tokio 运行时中使用会导致 panic
   - 当前通过 `current_tokio_runtime_is_multi_thread` 保护

### 配置风险

1. **Statsig 解析**: `resolve_exporter` 在 `OtelProvider::from` 中被多次调用
   - 每次调用都会创建新的 `HashMap`，有轻微性能开销
   - 建议：在 `OtelSettings` 构建时预解析

2. **部分失败**: 如果日志导出器构建成功但追踪导出器失败，整个 Provider 构建失败
   - 建议：考虑部分成功模式，允许某些系统禁用

### 测试覆盖

当前测试：
- `resource_attributes_include_host_name_when_present`: 资源属性包含主机名
- `resource_attributes_omit_host_name_when_missing_or_empty`: 资源属性省略空主机名
- `log_export_target_excludes_trace_safe_events`: 日志过滤排除 trace_safe 事件
- `trace_export_target_only_includes_trace_safe_prefix`: 追踪过滤仅包含 trace_safe 前缀

缺失测试：
- Provider 构建成功/失败路径
- 导出器配置传递
- Drop/关闭行为
- 与 tracing_subscriber 的集成

### 改进建议

1. **Builder 模式**: 为 `OtelProvider` 提供 Builder API，简化配置
2. **部分初始化**: 允许某些导出器失败时继续初始化其他导出器
3. **健康检查**: 提供方法检查导出器连接状态
4. **动态重载**: 支持运行时更新配置（如日志级别）
5. **指标暴露**: 暴露 Provider 自身的指标（如导出延迟、失败率）
6. **结构化日志**: 在关键路径添加结构化日志，便于调试

### 架构建议

当前 `OtelProvider` 是一个"上帝对象"，管理所有 OTEL 系统。可以考虑：
- 拆分为 `LogProvider`, `TraceProvider`, `MetricsProvider`
- 使用组合模式保持 `OtelProvider` 作为统一入口
- 每个子 Provider 独立配置和生命周期管理
