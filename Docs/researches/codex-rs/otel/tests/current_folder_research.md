# DIR codex-rs/otel/tests 研究文档

## 概述

`codex-rs/otel/tests` 是 Codex CLI 项目中 OpenTelemetry (OTel) 模块的集成测试目录。该测试套件全面验证了指标收集、追踪、日志导出以及会话遥测等核心功能，确保 OTel 基础设施在各种场景下的正确性和可靠性。

---

## 场景与职责

### 核心职责

1. **指标客户端测试**：验证 `MetricsClient` 的计数器、直方图、计时器等指标类型的正确记录和导出
2. **会话遥测测试**：测试 `SessionTelemetry` 如何收集和附加元数据标签到指标
3. **OTLP 导出测试**：验证通过 HTTP/gRPC 协议将指标和追踪数据发送到 OTel Collector 的功能
4. **路由策略测试**：确保敏感数据（如用户提示、工具参数）在日志和追踪之间的正确分离
5. **运行时指标测试**：验证运行时性能指标的收集和汇总
6. **数据验证测试**：确保指标名称、标签键值符合规范，拒绝无效输入

### 测试场景覆盖

| 场景 | 测试文件 | 说明 |
|------|----------|------|
| 基础指标发送 | `send.rs` | Counter/Histogram 的基本功能 |
| 标签合并 | `send.rs` | 默认标签与调用标签的合并逻辑 |
| 会话元数据 | `manager_metrics.rs` | SessionTelemetry 的元数据标签附加 |
| 快照采集 | `snapshot.rs` | 不关闭 provider 的情况下采集指标 |
| 计时器功能 | `timing.rs` | 自动记录代码块执行时间 |
| 输入验证 | `validation.rs` | 标签键值、指标名称的合法性检查 |
| 日志追踪路由 | `otel_export_routing_policy.rs` | 敏感数据分离策略 |
| HTTP 导出 | `otlp_http_loopback.rs` | OTLP HTTP 协议端到端测试 |
| 运行时汇总 | `runtime_summary.rs` | 运行时性能指标聚合 |

---

## 功能点目的

### 1. 指标发送与标签管理 (`send.rs`)

**目的**：验证指标客户端能够正确发送计数器和直方图数据，并正确处理标签合并逻辑。

**关键测试**：
- `send_builds_payload_with_tags_and_histograms`：验证 Counter 和 Histogram 的基本功能，确保标签正确附加
- `send_merges_default_tags_per_line`：验证默认标签与每行调用标签的合并逻辑，后调用标签可覆盖默认标签
- `client_sends_enqueued_metric`：验证后台工作线程正确传递队列中的指标
- `shutdown_flushes_in_memory_exporter`：验证 shutdown 正确刷新内存导出器
- `shutdown_without_metrics_exports_nothing`：验证无指标时不产生空导出

### 2. 会话遥测管理 (`manager_metrics.rs`)

**目的**：验证 `SessionTelemetry` 如何管理指标客户端，并自动附加会话元数据作为标签。

**关键测试**：
- `manager_attaches_metadata_tags_to_metrics`：验证 SessionTelemetry 自动附加 model、auth_mode、originator 等元数据标签
- `manager_allows_disabling_metadata_tags`：验证可通过 `with_metrics_without_metadata_tags` 禁用元数据标签
- `manager_attaches_optional_service_name_tag`：验证自定义 service_name 标签的附加

### 3. 运行时快照 (`snapshot.rs`)

**目的**：验证在不关闭 MeterProvider 的情况下采集当前指标状态，用于运行时调试和监控。

**关键测试**：
- `snapshot_collects_metrics_without_shutdown`：验证 `MetricsClient::snapshot()` 可在不关闭 provider 的情况下采集指标
- `manager_snapshot_metrics_collects_without_shutdown`：验证 SessionTelemetry 的 `snapshot_metrics()` 方法

### 4. 计时器功能 (`timing.rs`)

**目的**：验证自动计时功能，用于测量代码块执行时间并记录为直方图。

**关键测试**：
- `record_duration_records_histogram`：验证 `record_duration` 正确记录持续时间直方图
- `timer_result_records_success`：验证 `start_timer` 创建的 Timer 在 Drop 时自动记录持续时间

### 5. 输入验证 (`validation.rs`)

**目的**：确保指标名称、标签键值符合 OpenTelemetry 命名规范，防止无效数据污染指标系统。

**关键测试**：
- `invalid_tag_component_is_rejected`：验证配置阶段拒绝无效标签键
- `counter_rejects_invalid_tag_key`：验证 Counter 调用时拒绝无效标签键
- `histogram_rejects_invalid_tag_value`：验证 Histogram 调用时拒绝无效标签值
- `counter_rejects_invalid_metric_name`：验证拒绝无效指标名称
- `counter_rejects_negative_increment`：验证 Counter 拒绝负增量（Counter 必须单调递增）

### 6. OTLP 导出路由策略 (`otel_export_routing_policy.rs`)

**目的**：验证敏感数据（用户提示、工具参数、认证信息）在日志和追踪之间的正确分离，确保隐私合规。

**关键测试**：
- `otel_export_routing_policy_routes_user_prompt_log_and_trace_events`：验证用户提示内容只进入日志，追踪中只记录长度统计
- `otel_export_routing_policy_routes_tool_result_log_and_trace_events`：验证工具参数和输出只进入日志，追踪中只记录长度
- `otel_export_routing_policy_routes_auth_recovery_log_and_trace_events`：验证认证恢复事件的字段分布
- `otel_export_routing_policy_routes_api_request_auth_observability`：验证 API 请求的认证可观测性字段
- `otel_export_routing_policy_routes_websocket_connect_auth_observability`：验证 WebSocket 连接的认证可观测性
- `otel_export_routing_policy_routes_websocket_request_transport_observability`：验证 WebSocket 请求的传输层可观测性

### 7. OTLP HTTP 环回测试 (`otlp_http_loopback.rs`)

**目的**：端到端验证 OTLP HTTP 导出器能够正确将指标和追踪数据发送到 HTTP 端点。

**关键测试**：
- `otlp_http_exporter_sends_metrics_to_collector`：验证指标通过 OTLP HTTP 发送到 Collector
- `otlp_http_exporter_sends_traces_to_collector`：验证追踪通过 OTLP HTTP 发送到 Collector（同步运行时）
- `otlp_http_exporter_sends_traces_to_collector_in_tokio_runtime`：验证在多线程 Tokio 运行时中发送追踪
- `otlp_http_exporter_sends_traces_to_collector_in_current_thread_tokio_runtime`：验证在单线程 Tokio 运行时中发送追踪

### 8. 运行时指标汇总 (`runtime_summary.rs`)

**目的**：验证从指标快照中提取运行时性能汇总数据的功能。

**关键测试**：
- `runtime_metrics_summary_collects_tool_api_and_streaming_metrics`：验证从快照中正确汇总工具调用、API 调用、流式事件、WebSocket 等指标

---

## 具体技术实现

### 测试 Harness 架构

```
tests/
├── tests.rs          # 测试模块入口，声明 harness 和 suite
├── harness/
│   └── mod.rs        # 测试辅助函数和工具
└── suite/
    ├── mod.rs        # 测试套件入口
    ├── send.rs       # 基础指标发送测试
    ├── manager_metrics.rs  # 会话遥测测试
    ├── snapshot.rs   # 快照采集测试
    ├── timing.rs     # 计时器测试
    ├── validation.rs # 输入验证测试
    ├── otel_export_routing_policy.rs  # 日志追踪路由策略测试
    ├── otlp_http_loopback.rs  # OTLP HTTP 环回测试
    └── runtime_summary.rs     # 运行时指标汇总测试
```

### 关键数据结构

#### 1. 测试 Harness 辅助函数 (`harness/mod.rs`)

```rust
// 构建带默认标签的 MetricsClient 和 InMemoryMetricExporter
pub(crate) fn build_metrics_with_defaults(
    default_tags: &[(&str, &str)],
) -> Result<(MetricsClient, InMemoryMetricExporter)>

// 从 exporter 获取最新的 ResourceMetrics
pub(crate) fn latest_metrics(exporter: &InMemoryMetricExporter) -> ResourceMetrics

// 在 ResourceMetrics 中查找指定名称的指标
pub(crate) fn find_metric<'a>(
    resource_metrics: &'a ResourceMetrics,
    name: &str,
) -> Option<&'a Metric>

// 将属性迭代器转换为 BTreeMap
pub(crate) fn attributes_to_map<'a>(
    attributes: impl Iterator<Item = &'a KeyValue>,
) -> BTreeMap<String, String>

// 提取直方图数据（边界、桶计数、总和、计数）
pub(crate) fn histogram_data(
    resource_metrics: &ResourceMetrics,
    name: &str,
) -> (Vec<f64>, Vec<u64>, f64, u64)
```

#### 2. 内存导出器模式

所有测试使用 `InMemoryMetricExporter` 替代真实的 OTLP 导出器，允许在测试中直接检查导出的指标数据：

```rust
let exporter = InMemoryMetricExporter::default();
let config = MetricsConfig::in_memory(
    "test",                    // environment
    "codex-cli",              // service_name
    env!("CARGO_PKG_VERSION"), // service_version
    exporter.clone(),         // in-memory exporter
);
let metrics = MetricsClient::new(config)?;
```

#### 3. 日志/追踪分离测试模式

路由策略测试使用 `InMemoryLogExporter` 和 `InMemorySpanExporter` 分别捕获日志和追踪输出：

```rust
let log_exporter = InMemoryLogExporter::default();
let logger_provider = SdkLoggerProvider::builder()
    .with_simple_exporter(log_exporter.clone())
    .build();

let span_exporter = InMemorySpanExporter::default();
let tracer_provider = SdkTracerProvider::builder()
    .with_simple_exporter(span_exporter.clone())
    .build();

// 配置 tracing subscriber 同时使用日志和追踪层
let subscriber = tracing_subscriber::registry()
    .with(OpenTelemetryTracingBridge::new(&logger_provider)
        .with_filter(filter_fn(OtelProvider::log_export_filter)))
    .with(tracing_opentelemetry::layer()
        .with_tracer(tracer)
        .with_filter(filter_fn(OtelProvider::trace_export_filter)));
```

### 关键流程

#### 1. 指标发送流程

```
测试调用
    ↓
MetricsClient::counter() / ::histogram() / ::record_duration()
    ↓
验证指标名称和标签合法性
    ↓
合并默认标签与调用标签（调用标签优先级更高）
    ↓
获取或创建 Counter/Histogram 仪器
    ↓
记录数据点（带属性标签）
    ↓
PeriodicReader 定期导出到 InMemoryMetricExporter
    ↓
测试通过 exporter.get_finished_metrics() 验证结果
```

#### 2. 快照采集流程

```
测试调用
    ↓
MetricsClient::snapshot()
    ↓
检查 runtime_reader 是否存在（通过 with_runtime_reader() 启用）
    ↓
调用 ManualReader::collect() 采集当前指标状态
    ↓
返回 ResourceMetrics（不关闭 Provider，可重复采集）
```

#### 3. 敏感数据分离流程

```
SessionTelemetry::user_prompt() / ::tool_result_with_tags()
    ↓
log_event! 宏 → 目标: "codex_otel.log_only"
    → 包含完整内容（prompt、arguments、output）
    → 由 OtelProvider::log_export_filter 路由到日志导出器
    ↓
trace_event! 宏 → 目标: "codex_otel.trace_safe"
    → 仅包含统计信息（length、count）
    → 由 OtelProvider::trace_export_filter 路由到追踪导出器
```

#### 4. OTLP HTTP 环回测试流程

```
测试启动
    ↓
绑定 TCP 监听器到 127.0.0.1:0（随机端口）
    ↓
在独立线程中运行 HTTP 服务器，捕获请求到 channel
    ↓
创建 MetricsClient/OtelProvider，配置 OTLP HTTP 导出器指向测试服务器
    ↓
记录指标/追踪数据
    ↓
调用 shutdown() 触发导出
    ↓
测试服务器接收请求，验证路径、Content-Type、请求体内容
    ↓
通过 channel 接收捕获的请求，断言验证
```

### 协议与格式

#### 1. 指标名称规范

- 格式：`codex.<category>.<name>`
- 示例：`codex.turns`, `codex.tool_latency`, `codex.request_latency`
- 正则验证：`^[a-zA-Z_][a-zA-Z0-9_.]*$`

#### 2. 标签键值规范

- 键格式：`^[a-zA-Z_][a-zA-Z0-9_]*$`（不允许空格、特殊字符）
- 值格式：`^[a-zA-Z0-9_.:/@-]*$`（有限特殊字符集）
- 违规值触发 `MetricsError::InvalidTagComponent`

#### 3. OTLP HTTP 协议

- Content-Type：`application/json` 或 `application/x-protobuf`
- 端点：
  - 指标：`/v1/metrics`
  - 追踪：`/v1/traces`
  - 日志：`/v1/logs`
- 方法：POST
- 响应：202 Accepted

---

## 关键代码路径与文件引用

### 被测试的源代码文件

| 测试文件 | 被测试的源代码 |
|----------|----------------|
| `send.rs`, `snapshot.rs`, `timing.rs`, `validation.rs` | `codex-rs/otel/src/metrics/client.rs` |
| `send.rs`, `snapshot.rs`, `timing.rs`, `validation.rs` | `codex-rs/otel/src/metrics/config.rs` |
| `manager_metrics.rs`, `snapshot.rs`, `runtime_summary.rs` | `codex-rs/otel/src/events/session_telemetry.rs` |
| `otel_export_routing_policy.rs` | `codex-rs/otel/src/events/shared.rs` |
| `otel_export_routing_policy.rs` | `codex-rs/otel/src/targets.rs` |
| `otel_export_routing_policy.rs` | `codex-rs/otel/src/provider.rs` |
| `otlp_http_loopback.rs` | `codex-rs/otel/src/otlp.rs` |
| `runtime_summary.rs` | `codex-rs/otel/src/metrics/runtime_metrics.rs` |
| `validation.rs` | `codex-rs/otel/src/metrics/validation.rs` |

### 关键代码路径

#### 1. 指标记录路径

```
codex-rs/otel/src/metrics/client.rs
├── MetricsClient::new()          # 创建客户端，配置 exporter
├── MetricsClient::counter()      # 记录计数器
│   └── MetricsClientInner::counter()
│       ├── validate_metric_name()
│       ├── self.attributes()     # 合并标签
│       └── Counter::add()
├── MetricsClient::histogram()    # 记录直方图
│   └── MetricsClientInner::histogram()
└── MetricsClient::record_duration()  # 记录持续时间
    └── MetricsClientInner::duration_histogram()
```

#### 2. 会话遥测路径

```
codex-rs/otel/src/events/session_telemetry.rs
├── SessionTelemetry::new()       # 创建会话遥测实例
├── SessionTelemetry::with_metrics()  # 附加指标客户端
├── SessionTelemetry::counter()   # 带元数据标签的计数器
│   └── tags_with_metadata()      # 合并会话元数据标签
├── SessionTelemetry::histogram() # 带元数据标签的直方图
└── SessionTelemetry::snapshot_metrics()  # 采集快照
```

#### 3. 日志追踪路由路径

```
codex-rs/otel/src/events/shared.rs
├── log_event! 宏                 # 目标: "codex_otel.log_only"
├── trace_event! 宏               # 目标: "codex_otel.trace_safe"
└── log_and_trace_event! 宏       # 同时发送两者

codex-rs/otel/src/targets.rs
├── is_log_export_target()        # 检查目标是否为日志导出
└── is_trace_safe_target()        # 检查目标是否为追踪安全

codex-rs/otel/src/provider.rs
├── OtelProvider::log_export_filter()   # 日志导出过滤器
└── OtelProvider::trace_export_filter() # 追踪导出过滤器
```

---

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `opentelemetry` | OpenTelemetry API，定义指标、追踪、日志接口 |
| `opentelemetry_sdk` | SDK 实现，包括 InMemoryExporter、ManualReader、PeriodicReader |
| `opentelemetry_otlp` | OTLP 导出器，支持 HTTP/gRPC 协议 |
| `opentelemetry-appender-tracing` | 将 tracing 日志桥接到 OpenTelemetry |
| `tracing` | 结构化日志和追踪框架 |
| `tracing-opentelemetry` | tracing 与 OpenTelemetry 的集成 |
| `tracing-subscriber` | tracing 的订阅者实现 |
| `tokio` | 异步运行时（用于 Tokio 运行时测试） |
| `tokio-tungstenite` | WebSocket 支持（用于 WebSocket 事件测试） |
| `eventsource-stream` | SSE 流解析（用于 SSE 事件测试） |
| `pretty_assertions` | 测试断言的更好差异显示 |

### 内部依赖

| 模块 | 用途 |
|------|------|
| `codex_protocol` | ThreadId、SessionSource、UserInput 等协议类型 |
| `codex_api` | ApiError、ResponseEvent 等 API 类型 |

### 测试隔离机制

1. **内存导出器**：所有测试使用 `InMemoryMetricExporter` 而非真实网络导出，确保测试隔离和快速执行
2. **独立 Provider**：每个测试创建独立的 `SdkMeterProvider`/`SdkLoggerProvider`/`SdkTracerProvider`，避免状态污染
3. **随机端口**：OTLP HTTP 环回测试使用 `127.0.0.1:0` 绑定随机端口，避免端口冲突
4. **超时控制**：HTTP 环回测试设置 2-3 秒超时，防止测试挂起

---

## 风险、边界与改进建议

### 已知风险

#### 1. 并发测试风险
- **风险**：`otlp_http_loopback.rs` 中的多线程 Tokio 测试可能与系统其他测试竞争资源
- **缓解**：使用随机端口、独立运行时实例、超时控制

#### 2. 时序敏感测试
- **风险**：`timing.rs` 中的计时器测试依赖实际时间，可能在慢速环境中不稳定
- **缓解**：测试使用相对宽松的断言（验证计数而非精确时间）

#### 3. 全局状态污染
- **风险**：`opentelemetry::global` 设置 tracer provider 可能影响其他测试
- **缓解**：测试使用 `tracing::subscriber::with_default` 限制订阅者范围，不依赖全局状态

### 边界情况

#### 1. 标签键值长度限制
- 当前验证器对标签键值长度没有明确限制，仅限制字符集
- 建议：添加长度限制防止内存溢出攻击

#### 2. 直方图边界溢出
- `histogram_data()` 辅助函数假设只有一个数据点
- 边界情况：多个数据点时只返回第一个

#### 3. 负增量检测
- Counter 拒绝负增量，但测试仅覆盖 `-1` 的情况
- 建议：添加更大负值、i64::MIN 等边界测试

### 改进建议

#### 1. 测试覆盖率增强

```rust
// 建议添加：并发指标记录测试
#[test]
fn concurrent_counter_increments_are_safe() {
    // 验证多线程环境下计数器正确累加
}

// 建议添加：大量标签测试
#[test]
fn large_number_of_tags_are_handled() {
    // 验证大量标签时的性能和正确性
}

// 建议添加：特殊字符标签值测试
#[test]
fn tag_values_with_unicode_are_sanitized() {
    // 验证 Unicode 字符的标签值处理
}
```

#### 2. 错误场景测试

```rust
// 建议添加：导出失败重试测试
#[test]
fn exporter_retries_on_transient_failure() {
    // 验证导出失败时的重试逻辑
}

// 建议添加：网络超时测试
#[test]
fn http_exporter_handles_timeout() {
    // 验证网络超时时的错误处理
}
```

#### 3. 性能基准测试

```rust
// 建议添加：指标记录性能基准
#[bench]
fn bench_counter_record(b: &mut Bencher) {
    // 测量高频指标记录性能
}
```

#### 4. 文档改进

- 为每个测试添加更详细的注释，说明测试的具体场景和预期行为
- 添加测试架构图，说明 harness 和 suite 的关系
- 记录测试运行要求（如网络隔离、资源限制）

#### 5. 测试组织优化

- 考虑将 `otlp_http_loopback.rs` 中的 HTTP 服务器辅助函数提取到 harness，供其他测试复用
- 为路由策略测试添加更多边界场景（如空字符串、超长内容）

---

## 总结

`codex-rs/otel/tests` 提供了全面的 OpenTelemetry 功能测试覆盖，包括：

1. **功能正确性**：验证指标记录、标签合并、会话元数据附加等核心功能
2. **数据隔离**：验证敏感数据在日志和追踪之间的正确分离
3. **协议兼容性**：验证 OTLP HTTP 导出器与 Collector 的协议兼容性
4. **输入验证**：验证指标名称和标签的合法性检查
5. **运行时监控**：验证运行时性能指标的采集和汇总

测试架构清晰，使用内存导出器实现快速、隔离的测试执行，同时通过环回测试验证真实网络导出功能。建议未来增强并发测试、错误场景测试和性能基准测试。
