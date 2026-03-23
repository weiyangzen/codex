# codex-rs/otel/tests/tests.rs 研究文档

## 文件位置
- **目标文件**: `codex-rs/otel/tests/tests.rs`
- **所属 Crate**: `codex-otel`
- **测试类型**: 集成测试（Integration Tests）

---

## 场景与职责

### 整体定位
`tests.rs` 是 `codex-otel` crate 的集成测试入口文件，负责组织和加载所有 OpenTelemetry 相关的集成测试。该文件本身仅包含模块声明，实际的测试逻辑分布在 `harness/` 和 `suite/` 子模块中。

### 核心测试场景

| 场景类别 | 说明 |
|---------|------|
| **Metrics 客户端测试** | 验证指标收集、标签合并、直方图记录、定时器功能 |
| **SessionTelemetry 测试** | 验证会话级遥测数据收集，包括元数据标签附加 |
| **OTLP 导出测试** | 验证 HTTP/gRPC 导出器与 Collector 的通信 |
| **路由策略测试** | 验证日志与追踪事件的分流策略（敏感数据 vs 安全数据） |
| **Runtime 指标汇总** | 验证运行时指标聚合与汇总功能 |
| **数据验证测试** | 验证指标名称、标签键值的合法性校验 |

### 在项目中的角色
- **被调用方**: 被 `cargo test` 调用执行
- **调用方**: 调用 `harness/` 和 `suite/` 中的测试辅助模块
- **依赖**: 依赖 `codex-otel` 库的所有公共 API

---

## 功能点目的

### 1. 模块组织结构

```rust
mod harness;  // 测试辅助工具库
mod suite;    // 实际测试用例集合
```

### 2. Harness 模块功能

位于 `tests/harness/mod.rs`，提供测试基础设施：

| 函数 | 用途 |
|-----|------|
| `build_metrics_with_defaults()` | 构建带默认标签的 MetricsClient 和 InMemoryMetricExporter |
| `latest_metrics()` | 从 exporter 获取最新的 ResourceMetrics |
| `find_metric()` | 在 ResourceMetrics 中按名称查找指标 |
| `attributes_to_map()` | 将 OpenTelemetry 属性转换为 BTreeMap 便于断言 |
| `histogram_data()` | 提取直方图的边界、桶计数、总和、数量 |

### 3. Suite 模块功能

位于 `tests/suite/mod.rs`，包含 8 个测试子模块：

| 子模块 | 测试目的 |
|-------|---------|
| `manager_metrics.rs` | SessionTelemetry 的元数据标签附加功能 |
| `otel_export_routing_policy.rs` | 日志/追踪事件路由策略（敏感数据分离） |
| `otlp_http_loopback.rs` | OTLP HTTP 导出器与本地 Collector 的集成 |
| `runtime_summary.rs` | 运行时指标汇总功能 |
| `send.rs` | MetricsClient 的基础发送功能 |
| `snapshot.rs` | 运行时指标快照功能（不关闭 provider） |
| `timing.rs` | 定时器与持续时间记录功能 |
| `validation.rs` | 指标名称和标签的合法性验证 |

---

## 具体技术实现

### 关键技术栈

```
OpenTelemetry SDK (opentelemetry_sdk)
├── metrics::InMemoryMetricExporter    # 内存导出器（测试用）
├── logs::InMemoryLogExporter          # 内存日志导出器
├── trace::InMemorySpanExporter        # 内存追踪导出器
└── metrics::data::ResourceMetrics     # 指标数据结构

OpenTelemetry OTLP (opentelemetry_otlp)
├── MetricExporter                     # OTLP 指标导出器
├── LogExporter                        # OTLP 日志导出器
└── SpanExporter                       # OTLP 追踪导出器

Tracing 生态
├── tracing                            # 结构化日志
├── tracing-opentelemetry              # tracing 与 OTel 桥接
└── tracing-subscriber                 # 订阅者实现
```

### 关键数据结构

#### 1. MetricsClientInner（内部结构）
```rust
struct MetricsClientInner {
    meter_provider: SdkMeterProvider,
    meter: Meter,
    counters: Mutex<HashMap<String, Counter<u64>>>,
    histograms: Mutex<HashMap<String, Histogram<f64>>>,
    duration_histograms: Mutex<HashMap<String, Histogram<f64>>>,
    runtime_reader: Option<Arc<ManualReader>>,
    default_tags: BTreeMap<String, String>,
}
```

#### 2. SessionTelemetryMetadata
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

#### 3. RuntimeMetricsSummary
```rust
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct RuntimeMetricsSummary {
    pub tool_calls: RuntimeMetricTotals,
    pub api_calls: RuntimeMetricTotals,
    pub streaming_events: RuntimeMetricTotals,
    pub websocket_calls: RuntimeMetricTotals,
    pub websocket_events: RuntimeMetricTotals,
    pub responses_api_overhead_ms: u64,
    pub responses_api_inference_time_ms: u64,
    // ... 更多字段
}
```

### 关键流程

#### 1. 指标收集流程
```
应用代码
    ↓
MetricsClient::counter(name, inc, tags)
    ↓
MetricsClientInner::counter()
    ├── validate_metric_name(name)          # 验证名称合法性
    ├── attributes(tags)                    # 合并默认标签与调用标签
    │   ├── validate_tag_key()              # 验证标签键
    │   └── validate_tag_value()            # 验证标签值
    └── Counter::add(inc, &attributes)      # 记录到 OTel SDK
```

#### 2. 事件路由流程（敏感数据分离）
```
SessionTelemetry::user_prompt()
    ↓
log_event!() ───────────────────────────────→ OTEL_LOG_ONLY_TARGET
    ├── 包含完整 prompt 内容（敏感）
    └── 发送到日志后端（如 Statsig）

trace_event!() ─────────────────────────────→ OTEL_TRACE_SAFE_TARGET
    ├── 仅包含 prompt_length（安全）
    └── 发送到追踪后端（如 Jaeger）
```

#### 3. OTLP HTTP 导出流程
```
MetricsClient::new(MetricsConfig::otlp(...))
    ↓
build_otlp_metric_exporter()
    ├── 解析 endpoint、headers、protocol
    ├── 配置 TLS（如需要）
    └── 构建 MetricExporter
        ↓
PeriodicReader::builder(exporter)
    .with_interval(interval)
    .build()
        ↓
SdkMeterProvider::builder()
    .with_reader(reader)
    .build()
```

### 测试关键代码路径

#### 路径 1: 标签合并测试（send.rs）
```rust
// 默认标签: [("service", "codex-cli"), ("env", "prod")]
// 调用标签: [("model", "gpt-5.1"), ("env", "dev")]
// 结果标签: [("service", "codex-cli"), ("env", "dev"), ("model", "gpt-5.1")]
metrics.counter("codex.turns", 1, &[("model", "gpt-5.1"), ("env", "dev")])?;
```

#### 路径 2: 元数据标签附加（manager_metrics.rs）
```rust
let manager = SessionTelemetry::new(...)
    .with_metrics(metrics);  // 启用元数据标签

manager.counter("codex.session_started", 1, &[("source", "tui")]);
// 自动附加: app.version, auth_mode, model, originator, service, session_source
```

#### 路径 3: 路由策略验证（otel_export_routing_policy.rs）
```rust
// 验证所有日志都发送到 codex_otel.log_only 目标
assert!(logs.iter().all(|log| {
    log.record.target().map(Cow::as_ref) == Some("codex_otel.log_only")
}));

// 验证追踪事件不包含敏感字段
assert!(!prompt_trace_attrs.contains_key("prompt"));
assert!(!prompt_trace_attrs.contains_key("user.email"));
```

#### 路径 4: 运行时指标汇总（runtime_summary.rs）
```rust
manager.reset_runtime_metrics();
// ... 执行各种操作 ...
let summary = manager.runtime_metrics_summary().expect("summary");
// summary 包含: tool_calls, api_calls, streaming_events 等汇总数据
```

---

## 关键代码路径与文件引用

### 被测试的源文件

| 源文件 | 被测试功能 |
|-------|-----------|
| `src/metrics/client.rs` | MetricsClient 的创建、指标记录、关闭 |
| `src/metrics/config.rs` | MetricsConfig 的构建与配置 |
| `src/metrics/validation.rs` | 指标名称和标签的合法性验证 |
| `src/metrics/timer.rs` | Timer 定时器实现 |
| `src/metrics/runtime_metrics.rs` | RuntimeMetricsSummary 汇总逻辑 |
| `src/events/session_telemetry.rs` | SessionTelemetry 事件记录 |
| `src/provider.rs` | OtelProvider 的构建与导出器配置 |
| `src/targets.rs` | 日志/追踪目标过滤逻辑 |

### 测试文件详细映射

```
codex-rs/otel/tests/
├── tests.rs                          # 入口模块声明
├── harness/
│   └── mod.rs                        # 测试辅助函数
└── suite/
    ├── mod.rs                        # 子模块声明
    ├── manager_metrics.rs            # 测试 SessionTelemetry 元数据标签
    ├── otel_export_routing_policy.rs # 测试事件路由策略
    ├── otlp_http_loopback.rs         # 测试 OTLP HTTP 导出器
    ├── runtime_summary.rs            # 测试运行时指标汇总
    ├── send.rs                       # 测试 MetricsClient 基础功能
    ├── snapshot.rs                   # 测试运行时快照
    ├── timing.rs                     # 测试定时器功能
    └── validation.rs                 # 测试数据验证
```

### 核心测试断言模式

```rust
// 1. 指标存在性断言
let metric = find_metric(&resource_metrics, "codex.turns")
    .expect("counter metric missing");

// 2. 属性值断言
let attrs = attributes_to_map(points[0].attributes());
assert_eq!(attrs.get("model").map(String::as_str), Some("gpt-5.1"));

// 3. 直方图数据断言
let (bounds, bucket_counts, sum, count) = histogram_data(&resource_metrics, "codex.tool_latency");
assert_eq!(bucket_counts.iter().sum::<u64>(), 1);
assert_eq!(sum, 25.0);

// 4. 错误类型断言
assert!(matches!(err, MetricsError::InvalidTagComponent { label, value }
    if label == "tag key" && value == "bad key"
));
```

---

## 依赖与外部交互

### 内部依赖

```rust
// 同 crate 内模块
codex_otel::metrics::MetricsClient
codex_otel::metrics::MetricsConfig
codex_otel::SessionTelemetry
codex_otel::OtelProvider
codex_otel::config::OtelSettings

// 其他 workspace crates
codex_protocol::ThreadId
codex_protocol::protocol::SessionSource
codex_protocol::user_input::UserInput
codex_api::ApiError
codex_utils_string::sanitize_metric_tag_value
```

### 外部依赖

| Crate | 用途 |
|-------|------|
| `opentelemetry_sdk` | InMemoryMetricExporter, InMemoryLogExporter, InMemorySpanExporter |
| `opentelemetry` | KeyValue, 基础类型 |
| `tracing` | 结构化日志事件 |
| `tracing-subscriber` | 订阅者注册与过滤 |
| `tracing-opentelemetry` | tracing 与 OTel 桥接 |
| `opentelemetry-appender-tracing` | tracing 到 OTel 日志的桥接 |
| `pretty_assertions` | 测试断言美化 |
| `tokio` | 异步运行时测试 |
| `tokio-tungstenite` | WebSocket 消息类型 |
| `eventsource-stream` | SSE 事件类型 |

### 网络交互（测试期间）

```rust
// otlp_http_loopback.rs 中的本地 HTTP 服务器
let listener = TcpListener::bind("127.0.0.1:0")?;
// 用于接收 OTLP HTTP 导出请求，验证导出功能
```

---

## 风险、边界与改进建议

### 已知风险

#### 1. 测试间状态污染风险
- **风险**: `GLOBAL_METRICS` 全局状态可能在测试间泄漏
- **缓解**: 使用 `InMemoryMetricExporter` 隔离每个测试
- **文件**: `src/metrics/mod.rs` 中的 `static GLOBAL_METRICS: OnceLock<MetricsClient>`

#### 2. 异步运行时兼容性
- **风险**: OTLP HTTP 导出器在不同 Tokio 运行时（多线程 vs 单线程）行为可能不同
- **测试覆盖**: `otlp_http_loopback.rs` 包含三种运行时测试：
  - 同步运行时
  - Tokio 多线程运行时
  - Tokio 单线程运行时

#### 3. 敏感数据泄露风险
- **风险**: 用户 prompt、工具参数等敏感数据可能误入追踪系统
- **缓解**: `otel_export_routing_policy.rs` 测试验证敏感数据仅发送到日志目标
- **关键代码**: `src/targets.rs` 中的 `is_log_export_target()` 和 `is_trace_safe_target()`

### 边界情况

| 边界情况 | 测试覆盖 | 说明 |
|---------|---------|------|
| 空标签列表 | `send.rs` | `metrics.counter("x", 1, &[])` |
| 标签键冲突 | `send.rs` | 调用标签覆盖默认标签 |
| 负数计数器 | `validation.rs` | 拒绝负数增量 |
| 非法字符 | `validation.rs` | 拒绝包含空格的标签键/值 |
| 空指标名称 | `validation.rs` | 拒绝空字符串名称 |
| 无指标关闭 | `send.rs` | `shutdown_without_metrics_exports_nothing` |
| 无运行时 reader | `snapshot.rs` | `RuntimeSnapshotUnavailable` 错误 |

### 改进建议

#### 1. 测试覆盖率增强
```rust
// 建议添加：并发写入测试
#[test]
fn concurrent_counter_increments_are_accurate() {
    // 验证多线程环境下计数器准确性
}

// 建议添加：大负载测试
#[test]
fn large_histogram_dataset_performance() {
    // 验证大量直方图数据点的性能
}
```

#### 2. 错误场景测试
- 建议添加网络超时场景测试（模拟 Collector 无响应）
- 建议添加 TLS 证书错误场景测试
- 建议添加 OTLP 协议版本不兼容测试

#### 3. 文档改进
- `harness/mod.rs` 中的辅助函数缺少文档注释
- 建议为每个测试模块添加更详细的测试目的说明

#### 4. 测试隔离性
```rust
// 当前：使用全局 static GLOBAL_METRICS
// 建议：使用线程本地存储或显式传递 MetricsClient
thread_local! {
    static TEST_METRICS: RefCell<Option<MetricsClient>> = const { RefCell::new(None) };
}
```

#### 5. 性能基准测试
```rust
// 建议添加 benches/ 目录
#[bench]
fn bench_counter_recording(b: &mut Bencher) {
    let (metrics, _) = build_metrics_with_defaults(&[]).unwrap();
    b.iter(|| {
        metrics.counter("test", 1, &[("key", "value")]).unwrap();
    });
}
```

### 配置相关注意事项

```toml
# Cargo.toml 中的测试特性
[features]
disable-default-metrics-exporter = []  # 测试时使用，防止网络导出
```

- 测试必须启用 `disable-default-metrics-exporter` 特性，否则可能尝试连接真实 Collector
- `cfg!(test)` 在 `config.rs` 中用于禁用 Statsig 导出器

---

## 总结

`codex-rs/otel/tests/tests.rs` 及其子模块构成了 `codex-otel` crate 的全面集成测试套件，覆盖了：

1. **功能正确性**: 指标收集、标签合并、事件路由
2. **数据完整性**: 验证导出的 OTel 数据结构
3. **安全合规**: 敏感数据与追踪数据分离
4. **运行时兼容**: 支持同步/异步多种运行时
5. **错误处理**: 验证非法输入的拒绝行为

测试设计遵循了 OpenTelemetry 的最佳实践，使用内存导出器实现快速、可重复的测试，同时通过本地 HTTP 服务器验证真实导出功能。
