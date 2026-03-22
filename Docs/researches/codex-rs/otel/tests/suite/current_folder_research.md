# codex-rs/otel/tests/suite 深度研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 目录定位

`codex-rs/otel/tests/suite` 是 `codex-otel` crate 的集成测试套件目录，负责验证 OpenTelemetry (OTEL) 指标、日志和追踪功能的正确性。该目录包含 9 个测试文件，覆盖从基础指标发送到复杂的路由策略验证的全方位测试场景。

### 1.2 核心职责

| 职责领域 | 描述 |
|---------|------|
| **指标系统验证** | 验证 Counter、Histogram、Duration 等指标的生成、聚合和导出 |
| **标签系统验证** | 验证默认标签与每调用标签的合并逻辑、标签验证规则 |
| **SessionTelemetry 验证** | 验证会话级遥测管理器的元数据附加、事件记录功能 |
| **导出路由策略验证** | 验证日志与追踪的分流策略（敏感数据进日志，安全摘要进追踪） |
| **OTLP HTTP 回环测试** | 验证 OTLP HTTP 导出器与外部收集器的实际交互 |
| **运行时指标摘要** | 验证工具调用、API 调用、WebSocket 事件的运行时统计 |

### 1.3 测试架构关系

```
codex-rs/otel/tests/
├── tests.rs          # 测试入口，声明 harness 和 suite 模块
├── harness/
│   └── mod.rs        # 测试辅助工具（构建客户端、查找指标、属性转换）
└── suite/
    ├── mod.rs        # 测试套件模块声明
    ├── send.rs       # 指标发送与标签合并测试
    ├── validation.rs # 标签/指标名验证测试
    ├── timing.rs     # 持续时间记录与计时器测试
    ├── snapshot.rs   # 运行时指标快照测试
    ├── runtime_summary.rs # 运行时指标摘要聚合测试
    ├── manager_metrics.rs # SessionTelemetry 指标管理测试
    ├── otel_export_routing_policy.rs # 日志/追踪路由策略测试
    └── otlp_http_loopback.rs # OTLP HTTP 端到端测试
```

---

## 功能点目的

### 2.1 指标发送与标签系统 (send.rs)

**目的**：验证 `MetricsClient` 的核心指标发送能力和标签合并逻辑。

**测试场景**：
- `send_builds_payload_with_tags_and_histograms`: 验证 Counter 和 Histogram 的基本发送，以及默认标签与每调用标签的合并
- `send_merges_default_tags_per_line`: 验证每行调用的标签独立合并，以及每调用标签对默认标签的覆盖
- `client_sends_enqueued_metric`: 验证后台工作线程成功投递队列中的指标
- `shutdown_flushes_in_memory_exporter`: 验证 shutdown 时正确刷新内存导出器
- `shutdown_without_metrics_exports_nothing`: 验证无指标时不产生空导出

**关键断言**：
- Counter 数据点值正确（`U64` -> `Sum` 聚合类型）
- Histogram 边界、桶计数、总和、计数正确（`F64` -> `Histogram` 聚合类型）
- 标签合并遵循 "默认标签 + 每调用标签，后者优先覆盖" 的规则

### 2.2 输入验证 (validation.rs)

**目的**：验证 `MetricsClient` 对非法输入的拒绝行为，确保数据质量。

**验证规则**：
| 验证项 | 规则 | 错误类型 |
|-------|------|---------|
| Tag Key | 非空，仅允许 ASCII 字母数字 + `.` `_` `-` `/` | `InvalidTagComponent` |
| Tag Value | 同上 | `InvalidTagComponent` |
| Metric Name | 非空，仅允许 ASCII 字母数字 + `.` `_` `-` | `InvalidMetricName` |
| Counter Increment | 必须非负 | `NegativeCounterIncrement` |

**测试场景**：
- 配置构建时非法标签被拒绝
- `counter()` 调用时非法标签键被拒绝
- `histogram()` 调用时非法标签值被拒绝
- 非法指标名被拒绝
- 负计数器增量被拒绝

### 2.3 时间记录 (timing.rs)

**目的**：验证持续时间记录和计时器功能。

**测试场景**：
- `record_duration_records_histogram`: 验证 `record_duration()` 将 Duration 记录为毫秒精度的 Histogram
- `timer_result_records_success`: 验证 `start_timer()` 创建的 `Timer` 在 Drop 时自动记录持续时间

**技术细节**：
- 持续时间单位固定为 `"ms"`
- 描述固定为 `"Duration in milliseconds."`
- 使用 `Duration::as_millis()` 转换，溢出时钳位到 `i64::MAX`

### 2.4 指标快照 (snapshot.rs)

**目的**：验证无需 shutdown 即可获取当前指标状态的能力。

**测试场景**：
- `snapshot_collects_metrics_without_shutdown`: 验证 `MetricsClient::snapshot()` 通过 `ManualReader` 收集当前指标，而不触发周期性导出
- `manager_snapshot_metrics_collects_without_shutdown`: 验证 `SessionTelemetry::snapshot_metrics()` 整合元数据标签后的快照能力

**关键机制**：
- `MetricsConfig::with_runtime_reader()` 启用 `ManualReader`
- `ManualReader` 使用 `Temporality::Delta` 增量聚合
- 快照收集后，`InMemoryMetricExporter` 中的已完成指标保持为空（未触发周期性导出）

### 2.5 运行时指标摘要 (runtime_summary.rs)

**目的**：验证 `SessionTelemetry::runtime_metrics_summary()` 对各类运行时事件的聚合统计。

**统计维度**：
| 维度 | 指标名 | 说明 |
|-----|-------|------|
| 工具调用 | `codex.tool.call` + `duration_ms` | 工具调用次数和耗时 |
| API 调用 | `codex.api_request` + `duration_ms` | HTTP API 调用次数和耗时 |
| SSE 事件 | `codex.sse_event` + `duration_ms` | 服务器发送事件次数和耗时 |
| WebSocket 调用 | `codex.websocket.request` + `duration_ms` | WebSocket 请求次数和耗时 |
| WebSocket 事件 | `codex.websocket.event` + `duration_ms` | WebSocket 事件次数和耗时 |
| Responses API 开销 | `codex.responses_api_overhead.duration_ms` | 引擎外开销 |
| Responses API 推理时间 | `codex.responses_api_inference_time.duration_ms` | 引擎总耗时 |
| TTFT/TBT 指标 | 多维度引擎延迟指标 | 首 token 时间、token 间时间 |

**测试场景**：
- 综合测试所有运行时事件类型的记录和聚合
- 验证 WebSocket 定时消息解析（`responsesapi.websocket_timing`）
- 验证 `RuntimeMetricsSummary` 结构体的正确填充

### 2.6 SessionTelemetry 指标管理 (manager_metrics.rs)

**目的**：验证 `SessionTelemetry` 对 `MetricsClient` 的封装和元数据标签附加。

**元数据标签**：
- `app.version`: 应用版本
- `auth_mode`: 认证模式（`api_key` / `chatgpt`）
- `model`: 使用的模型
- `originator`: 发起者标识
- `service`: 服务名
- `session_source`: 会话来源（`cli` / `tui` 等）
- `service_name`: 可选的自定义服务名

**测试场景**：
- `manager_attaches_metadata_tags_to_metrics`: 验证元数据标签自动附加到指标
- `manager_allows_disabling_metadata_tags`: 验证可通过 `with_metrics_without_metadata_tags()` 禁用元数据标签
- `manager_attaches_optional_service_name_tag`: 验证自定义服务名标签附加

### 2.7 OTEL 导出路由策略 (otel_export_routing_policy.rs)

**目的**：验证敏感数据的分流导出策略——详细数据进日志，安全摘要进追踪。

**路由策略**：
| 目标 | 过滤条件 | 数据敏感度 |
|-----|---------|-----------|
| Log Only | `target: "codex_otel.log_only"` | 高（包含用户提示、工具参数/输出） |
| Trace Safe | `target: "codex_otel.trace_safe"` | 低（仅长度统计、计数） |

**测试场景**：
- `otel_export_routing_policy_routes_user_prompt_log_and_trace_events`: 用户提示分流
  - Log: 完整提示内容、`user.email`
  - Trace: 提示长度、文本/图片输入计数
- `otel_export_routing_policy_routes_tool_result_log_and_trace_events`: 工具结果分流
  - Log: 完整参数、完整输出、`mcp_server`
  - Trace: 参数长度、输出长度、输出行数、工具来源
- `otel_export_routing_policy_routes_auth_recovery_log_and_trace_events`: 认证恢复事件
- `otel_export_routing_policy_routes_api_request_auth_observability`: API 请求认证可观测性
- `otel_export_routing_policy_routes_websocket_connect_auth_observability`: WebSocket 连接认证
- `otel_export_routing_policy_routes_websocket_request_transport_observability`: WebSocket 请求传输层

### 2.8 OTLP HTTP 回环测试 (otlp_http_loopback.rs)

**目的**：验证 OTLP HTTP 导出器与真实 HTTP 端点的交互能力。

**测试场景**：
- `otlp_http_exporter_sends_metrics_to_collector`: 同步运行时，指标导出到本地 HTTP 服务器
- `otlp_http_exporter_sends_traces_to_collector`: 同步运行时，追踪导出到本地 HTTP 服务器
- `otlp_http_exporter_sends_traces_to_collector_in_tokio_runtime`: 多线程 Tokio 运行时
- `otlp_http_exporter_sends_traces_to_collector_in_current_thread_tokio_runtime`: 单线程 Tokio 运行时

**技术细节**：
- 使用 `std::net::TcpListener` 创建本地 HTTP 服务器
- 协议支持：JSON (`application/json`) 和 Binary (Protobuf)
- 验证请求路径：`/v1/metrics`, `/v1/traces`
- 验证请求体包含预期的指标/追踪名称

---

## 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 MetricsClient 内部结构

```rust
// codex-rs/otel/src/metrics/client.rs
struct MetricsClientInner {
    meter_provider: SdkMeterProvider,
    meter: Meter,
    counters: Mutex<HashMap<String, Counter<u64>>>,
    histograms: Mutex<HashMap<String, Histogram<f64>>>,
    duration_histograms: Mutex<HashMap<String, Histogram<f64>>>,
    runtime_reader: Option<Arc<ManualReader>>,  // 用于快照
    default_tags: BTreeMap<String, String>,
}
```

#### 3.1.2 SessionTelemetry 结构

```rust
// codex-rs/otel/src/events/session_telemetry.rs
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

#### 3.1.3 RuntimeMetricsSummary 结构

```rust
// codex-rs/otel/src/metrics/runtime_metrics.rs
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

#### 3.2.1 指标发送流程

```
MetricsClient::counter(name, inc, tags)
  └─> MetricsClientInner::counter(name, inc, tags)
      ├─> validate_metric_name(name)           // 验证指标名
      ├─> check inc >= 0                       // 验证非负增量
      ├─> attributes(tags)                     // 合并默认标签 + 验证
      │   ├─> validate_tag_key(key)            // 验证标签键
      │   └─> validate_tag_value(value)        // 验证标签值
      └─> Counter::add(inc, &attributes)       // OTEL SDK 调用
```

#### 3.2.2 快照收集流程

```
MetricsClient::snapshot()
  └─> 检查 runtime_reader 是否存在
      └─> ManualReader::collect(&mut ResourceMetrics)
          └─> 返回当前聚合的指标数据（不触发导出）
```

#### 3.2.3 日志/追踪分流流程

```
SessionTelemetry::user_prompt(items)
  ├─> log_event!()                             // 目标: codex_otel.log_only
  │   └─> 包含: 完整提示、user.email
  └─> trace_event!()                           // 目标: codex_otel.trace_safe
      └─> 包含: prompt_length、text_input_count、image_input_count

// 订阅者配置（测试中）
tracing_subscriber::registry()
  .with(OpenTelemetryTracingBridge::new(&logger_provider)
        .with_filter(filter_fn(OtelProvider::log_export_filter)))  // 仅 log_only
  .with(tracing_opentelemetry::layer()
        .with_filter(filter_fn(OtelProvider::trace_export_filter))) // 仅 trace_safe
```

#### 3.2.4 运行时指标摘要聚合流程

```
SessionTelemetry::runtime_metrics_summary()
  ├─> snapshot_metrics()                       // 获取 ResourceMetrics
  └─> RuntimeMetricsSummary::from_snapshot()
      ├─> sum_counter(snapshot, metric_name)   // 累加 Counter
      └─> sum_histogram_ms(snapshot, metric_name) // 累加 Histogram (ms)
```

### 3.3 验证规则实现

```rust
// codex-rs/otel/src/metrics/validation.rs

fn is_metric_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-')
}

fn is_tag_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-' | '/')
}

pub(crate) fn validate_metric_name(name: &str) -> Result<()> {
    if name.is_empty() {
        return Err(MetricsError::EmptyMetricName);
    }
    if !name.chars().all(is_metric_char) {
        return Err(MetricsError::InvalidMetricName { name: name.to_string() });
    }
    Ok(())
}
```

### 3.4 标签合并算法

```rust
// codex-rs/otel/src/metrics/client.rs

fn attributes(&self, tags: &[(&str, &str)]) -> Result<Vec<KeyValue>> {
    if tags.is_empty() {
        return Ok(self.default_tags.iter()
            .map(|(k, v)| KeyValue::new(k.clone(), v.clone()))
            .collect());
    }

    let mut merged = self.default_tags.clone();  // 克隆默认标签
    for (key, value) in tags {
        validate_tag_key(key)?;
        validate_tag_value(value)?;
        merged.insert((*key).to_string(), (*value).to_string());  // 覆盖或添加
    }

    Ok(merged.into_iter()
        .map(|(k, v)| KeyValue::new(k, v))
        .collect())
}
```

---

## 关键代码路径与文件引用

### 4.1 测试文件清单

| 文件 | 行数 | 测试函数数 | 主要职责 |
|-----|------|-----------|---------|
| `mod.rs` | 8 | 0 | 模块声明 |
| `send.rs` | 205 | 5 | 指标发送、标签合并、shutdown 行为 |
| `validation.rs` | 87 | 5 | 输入验证、错误处理 |
| `timing.rs` | 77 | 2 | 持续时间记录、计时器 |
| `snapshot.rs` | 125 | 2 | 指标快照、运行时读取器 |
| `runtime_summary.rs` | 139 | 1 | 运行时指标摘要聚合 |
| `manager_metrics.rs` | 155 | 3 | SessionTelemetry 指标管理 |
| `otel_export_routing_policy.rs` | 852 | 6 | 日志/追踪分流策略 |
| `otlp_http_loopback.rs` | 561 | 4 | OTLP HTTP 端到端测试 |

### 4.2 被测源代码路径

| 被测功能 | 源代码路径 |
|---------|-----------|
| MetricsClient | `codex-rs/otel/src/metrics/client.rs` |
| MetricsConfig | `codex-rs/otel/src/metrics/config.rs` |
| 验证逻辑 | `codex-rs/otel/src/metrics/validation.rs` |
| Timer | `codex-rs/otel/src/metrics/timer.rs` |
| RuntimeMetricsSummary | `codex-rs/otel/src/metrics/runtime_metrics.rs` |
| 指标名常量 | `codex-rs/otel/src/metrics/names.rs` |
| SessionTelemetry | `codex-rs/otel/src/events/session_telemetry.rs` |
| 事件宏 | `codex-rs/otel/src/events/shared.rs` |
| OtelProvider | `codex-rs/otel/src/provider.rs` |
| 目标过滤 | `codex-rs/otel/src/targets.rs` |

### 4.3 测试辅助工具 (harness)

```rust
// codex-rs/otel/tests/harness/mod.rs

pub(crate) fn build_metrics_with_defaults(
    default_tags: &[(&str, &str)]
) -> Result<(MetricsClient, InMemoryMetricExporter)>

pub(crate) fn latest_metrics(exporter: &InMemoryMetricExporter) -> ResourceMetrics

pub(crate) fn find_metric<'a>(
    resource_metrics: &'a ResourceMetrics,
    name: &str
) -> Option<&'a Metric>

pub(crate) fn attributes_to_map<'a>(
    attributes: impl Iterator<Item = &'a KeyValue>
) -> BTreeMap<String, String>

pub(crate) fn histogram_data(
    resource_metrics: &ResourceMetrics,
    name: &str
) -> (Vec<f64>, Vec<u64>, f64, u64)  // (bounds, bucket_counts, sum, count)
```

### 4.4 关键测试断言模式

```rust
// Counter 断言模式
let counter = find_metric(&resource_metrics, "codex.turns").expect("counter metric missing");
let points = match counter.data() {
    opentelemetry_sdk::metrics::data::AggregatedMetrics::U64(data) => match data {
        opentelemetry_sdk::metrics::data::MetricData::Sum(sum) => {
            sum.data_points().collect::<Vec<_>>()
        }
        _ => panic!("unexpected counter aggregation"),
    }
    _ => panic!("unexpected counter data type"),
};
assert_eq!(points.len(), 1);
assert_eq!(points[0].value(), 1);

// Histogram 断言模式
let (bounds, bucket_counts, sum, count) = histogram_data(&resource_metrics, "codex.tool_latency");
assert!(!bounds.is_empty());
assert_eq!(bucket_counts.iter().sum::<u64>(), 1);
assert_eq!(sum, 25.0);
assert_eq!(count, 1);
```

---

## 依赖与外部交互

### 5.1 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `opentelemetry` | OTEL API（指标、日志、追踪） |
| `opentelemetry_sdk` | OTEL SDK 实现，含 `InMemoryMetricExporter`、`ManualReader` |
| `opentelemetry_otlp` | OTLP 导出器（HTTP/gRPC） |
| `opentelemetry-appender-tracing` | tracing 到 OTEL 日志的桥接 |
| `tracing-opentelemetry` | tracing 到 OTEL 追踪的桥接 |
| `tracing-subscriber` | 订阅者注册和过滤 |
| `pretty_assertions` | 测试断言美化 |
| `tokio` | 异步运行时（用于 Tokio 相关测试） |
| `tokio-tungstenite` | WebSocket 消息类型 |
| `eventsource-stream` | SSE 事件类型 |

### 5.2 内部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_otel` | 被测库本身 |
| `codex_protocol` | `ThreadId`、`SessionSource`、`UserInput` 等类型 |
| `codex_api` | `ApiError`、`ResponseEvent` 等类型 |

### 5.3 网络交互

`otlp_http_loopback.rs` 中的测试会启动本地 TCP 服务器：

```rust
let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
let addr = listener.local_addr().expect("local_addr");
// 服务器线程处理 HTTP 请求，验证 OTLP 导出
```

**注意**：这些测试在隔离环境中运行，不依赖外部网络。

### 5.4 并发模型

| 测试文件 | 并发模型 |
|---------|---------|
| `send.rs` | 同步（单线程） |
| `validation.rs` | 同步（单线程） |
| `timing.rs` | 同步（单线程） |
| `snapshot.rs` | 同步（单线程） |
| `runtime_summary.rs` | 同步（单线程） |
| `manager_metrics.rs` | 同步（单线程） |
| `otel_export_routing_policy.rs` | 同步（tracing subscriber） |
| `otlp_http_loopback.rs` | 混合（同步 + 多线程 Tokio + 单线程 Tokio） |

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 标签验证过于严格

**风险**：标签字符集限制（仅 ASCII 字母数字 + 少量符号）可能导致合法的多语言标签被拒绝。

**代码位置**：`codex-rs/otel/src/metrics/validation.rs:49-54`

```rust
fn is_tag_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-' | '/')
}
```

**建议**：考虑对标签值放宽限制（如允许 Unicode），或提供标签值自动转义/规范化。

#### 6.1.2 计数器溢出风险

**风险**：`counter()` 接受 `i64` 但内部转换为 `u64`，溢出时行为未明确定义。

**代码位置**：`codex-rs/otel/src/metrics/client.rs:110`

```rust
counter.add(inc as u64, &attributes);  // 负值已检查，但大正值可能溢出
```

**建议**：添加 `inc > u64::MAX` 检查，或明确文档说明限制。

#### 6.1.3 测试中的竞争条件

**风险**：`otlp_http_loopback.rs` 中的测试使用线程睡眠和超时，在慢速 CI 环境中可能不稳定。

**代码位置**：`otlp_http_loopback.rs:146-166`

```rust
while Instant::now() < deadline {
    match listener.accept() {
        // ...
        Err(err) if err.kind() == std::io::ErrorKind::WouldBlock => {
            thread::sleep(Duration::from_millis(10));
        }
        // ...
    }
}
```

**建议**：增加超时时间或使用更可靠的同步原语（如 `std::sync::Barrier`）。

### 6.2 边界情况

#### 6.2.1 空标签列表

当 `tags` 为空时，`attributes()` 直接返回默认标签的克隆，避免不必要的验证开销。

#### 6.2.2 重复标签键

每调用标签会覆盖默认标签中的同名键，这是设计行为但需文档明确。

#### 6.2.3 快照与周期性导出的互斥

`ManualReader` 和 `PeriodicReader` 是独立的，快照收集不会影响周期性导出的数据。

### 6.3 改进建议

#### 6.3.1 测试覆盖率

| 建议 | 优先级 |
|-----|-------|
| 添加 gRPC OTLP 端到端测试 | 中 |
| 添加 TLS 配置测试 | 中 |
| 添加指标导出失败重试测试 | 低 |
| 添加高并发指标发送压力测试 | 低 |

#### 6.3.2 代码质量

| 建议 | 优先级 |
|-----|-------|
| 提取测试中的重复断言模式为宏 | 中 |
| 统一使用 `pretty_assertions::assert_eq` | 低 |
| 添加测试文档注释说明测试意图 | 低 |

#### 6.3.3 功能增强

| 建议 | 优先级 |
|-----|-------|
| 支持指标标签的动态删除 | 低 |
| 支持运行时修改默认标签 | 低 |
| 支持指标名前缀自定义 | 低 |

### 6.4 维护注意事项

1. **OpenTelemetry SDK 升级**：`opentelemetry_sdk` 的实验性功能（如 `experimental_metrics_custom_reader`）可能在版本升级时发生变化，需关注变更日志。

2. **指标名变更**：`codex-rs/otel/src/metrics/names.rs` 中的指标名变更会影响下游监控仪表盘，需保持向后兼容或提供迁移指南。

3. **测试数据隔离**：`InMemoryMetricExporter` 在测试间共享状态的风险已通过 `build_metrics_with_defaults` 中的新实例创建避免，但需注意未来新增测试时的隔离性。

---

## 附录：测试运行命令

```bash
# 运行所有测试
cargo test -p codex-otel

# 运行特定测试文件
cargo test -p codex-otel --test tests -- suite::send
cargo test -p codex-otel --test tests -- suite::validation
cargo test -p codex-otel --test tests -- suite::timing
cargo test -p codex-otel --test tests -- suite::snapshot
cargo test -p codex-otel --test tests -- suite::runtime_summary
cargo test -p codex-otel --test tests -- suite::manager_metrics
cargo test -p codex-otel --test tests -- suite::otel_export_routing_policy
cargo test -p codex-otel --test tests -- suite::otlp_http_loopback

# 运行特定测试函数
cargo test -p codex-otel send_builds_payload_with_tags_and_histograms
```

---

*文档生成时间: 2026-03-22*
*基于 commit: 研究时 HEAD*
