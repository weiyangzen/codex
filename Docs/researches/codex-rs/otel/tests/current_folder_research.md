# Research: codex-rs/otel/tests

## 场景与职责

`codex-rs/otel/tests` 是 `codex-otel` crate 的集成测试目录，负责验证 OpenTelemetry 集成模块的核心功能。该测试套件确保 Codex CLI 的遥测系统（包括指标收集、日志记录、链路追踪）能够正确工作，并符合 OpenTelemetry 标准。

**核心职责：**
1. 验证 `MetricsClient` 的指标收集、标签合并、直方图记录功能
2. 验证 `SessionTelemetry` 的会话级事件记录和元数据标签附加
3. 验证 OTEL 导出路由策略（日志 vs 链路追踪的分流策略）
4. 验证 OTLP HTTP 导出器与外部收集器的通信
5. 验证运行时指标汇总（Runtime Metrics Summary）功能
6. 验证指标快照（Snapshot）功能
7. 验证输入验证和错误处理

---

## 功能点目的

### 1. 指标收集与导出测试 (`send.rs`)
- **目的**：验证 `MetricsClient` 能够正确记录计数器和直方图指标
- **关键测试点**：
  - 默认标签与每次调用标签的合并逻辑
  - 标签覆盖优先级（调用时标签覆盖默认标签）
  - 后台工作线程的指标投递
  - 关闭时的刷新（flush）行为
  - 空指标情况下的关闭处理

### 2. 会话遥测管理器测试 (`manager_metrics.rs`)
- **目的**：验证 `SessionTelemetry` 如何附加元数据标签到指标
- **关键测试点**：
  - 自动附加会话元数据（auth_mode、model、originator、session_source、app.version）
  - 可选禁用元数据标签功能
  - 自定义服务名称标签的附加

### 3. OTEL 导出路由策略测试 (`otel_export_routing_policy.rs`)
- **目的**：验证敏感数据的分流策略——哪些数据进入日志（log_only），哪些进入链路追踪（trace_safe）
- **关键测试点**：
  - `user_prompt`：日志记录完整 prompt，链路追踪仅记录长度统计
  - `tool_result`：日志记录完整参数和输出，链路追踪仅记录长度和行数
  - `auth_recovery`：日志和链路追踪都记录完整认证恢复信息
  - `api_request`/`websocket_connect`/`websocket_request`：认证可观测性数据的双向记录

### 4. OTLP HTTP 环回测试 (`otlp_http_loopback.rs`)
- **目的**：验证 OTLP HTTP 导出器能够实际发送数据到外部收集器
- **关键测试点**：
  - 指标通过 OTLP/HTTP JSON 发送到本地 TCP 收集器
  - 链路追踪（traces）通过 OTLP/HTTP JSON 发送
  - 在 Tokio 多线程运行时中的行为
  - 在 Tokio 当前线程运行时中的行为

### 5. 运行时指标汇总测试 (`runtime_summary.rs`)
- **目的**：验证 `RuntimeMetricsSummary` 能够正确汇总各类运行时指标
- **关键测试点**：
  - 工具调用计数和持续时间
  - API 调用计数和持续时间
  - SSE 流事件计数和持续时间
  - WebSocket 调用和事件计数
  - Responses API 的详细时序指标（overhead、inference、TTFT、TBT）
  - 回合级 TTFT/TTFM 指标

### 6. 指标快照测试 (`snapshot.rs`)
- **目的**：验证 `snapshot()` API 能够在不关闭 provider 的情况下收集当前指标
- **关键测试点**：
  - `MetricsClient::snapshot()` 返回 `ResourceMetrics` 而不触发周期性导出
  - `SessionTelemetry::snapshot_metrics()` 返回带元数据标签的快照

### 7. 时序记录测试 (`timing.rs`)
- **目的**：验证持续时间记录和计时器功能
- **关键测试点**：
  - `record_duration` 将毫秒记录到直方图
  - 直方图单位（ms）和描述（"Duration in milliseconds."）
  - `start_timer` 自动记录经过时间

### 8. 输入验证测试 (`validation.rs`)
- **目的**：验证指标名称和标签的输入验证
- **关键测试点**：
  - 无效标签键（如包含空格）被拒绝
  - 无效标签值被拒绝
  - 无效指标名称被拒绝
  - 负计数器增量被拒绝

---

## 具体技术实现

### 关键流程

#### 1. 测试 Harness 初始化流程
```rust
// harness/mod.rs
pub(crate) fn build_metrics_with_defaults(
    default_tags: &[(&str, &str)],
) -> Result<(MetricsClient, InMemoryMetricExporter)> {
    let exporter = InMemoryMetricExporter::default();
    let mut config = MetricsConfig::in_memory(
        "test", "codex-cli", env!("CARGO_PKG_VERSION"), exporter.clone(),
    );
    for (key, value) in default_tags {
        config = config.with_tag(*key, *value)?;
    }
    let metrics = MetricsClient::new(config)?;
    Ok((metrics, exporter))
}
```

#### 2. 指标验证流程
```rust
// 从 InMemoryMetricExporter 获取最新指标
pub(crate) fn latest_metrics(exporter: &InMemoryMetricExporter) -> ResourceMetrics {
    let Ok(metrics) = exporter.get_finished_metrics() else { panic!("finished metrics error") };
    let Some(metrics) = metrics.into_iter().last() else { panic!("metrics export missing") };
    metrics
}

// 在 ResourceMetrics 中查找指定名称的指标
pub(crate) fn find_metric<'a>(resource_metrics: &'a ResourceMetrics, name: &str) -> Option<&'a Metric> {
    for scope_metrics in resource_metrics.scope_metrics() {
        for metric in scope_metrics.metrics() {
            if metric.name() == name { return Some(metric); }
        }
    }
    None
}
```

#### 3. 导出路由策略实现
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

测试中使用 `tracing_subscriber::filter::filter_fn` 分别过滤：
- `log_export_filter`：仅允许 `log_only` 目标
- `trace_export_filter`：允许所有 span 和 `trace_safe` 目标

#### 4. OTLP HTTP 环回测试服务器
```rust
// otlp_http_loopback.rs
struct CapturedRequest {
    path: String,
    content_type: Option<String>,
    body: Vec<u8>,
}

// 手动实现的 HTTP 请求解析器
fn read_http_request(stream: &mut TcpStream) -> std::io::Result<(String, HashMap<String, String>, Vec<u8>)> {
    // 解析 HTTP 请求行、头部、正文
    // 支持 Content-Length 分块读取
}
```

#### 5. 运行时指标汇总数据结构
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
    // ... TTFT/TBT 等详细指标
}
```

---

## 关键代码路径与文件引用

### 测试文件结构
```
codex-rs/otel/tests/
├── tests.rs              # 测试入口，声明 harness 和 suite 模块
├── harness/
│   └── mod.rs            # 测试辅助函数（构建客户端、查找指标、属性转换）
└── suite/
    ├── mod.rs            # suite 模块声明
    ├── manager_metrics.rs    # SessionTelemetry 元数据标签测试
    ├── otel_export_routing_policy.rs  # 日志/链路追踪分流策略测试
    ├── otlp_http_loopback.rs # OTLP HTTP 导出器集成测试
    ├── runtime_summary.rs    # 运行时指标汇总测试
    ├── send.rs               # MetricsClient 基础功能测试
    ├── snapshot.rs           # 指标快照功能测试
    ├── timing.rs             # 时序记录测试
    └── validation.rs         # 输入验证测试
```

### 被测源代码引用

| 测试文件 | 被测源代码 |
|---------|-----------|
| `send.rs` | `src/metrics/client.rs` (`MetricsClient`), `src/metrics/config.rs` (`MetricsConfig`) |
| `manager_metrics.rs` | `src/events/session_telemetry.rs` (`SessionTelemetry`) |
| `otel_export_routing_policy.rs` | `src/provider.rs` (`OtelProvider`), `src/targets.rs` |
| `otlp_http_loopback.rs` | `src/provider.rs`, `src/config.rs` (`OtelSettings`, `OtelExporter`) |
| `runtime_summary.rs` | `src/metrics/runtime_metrics.rs` (`RuntimeMetricsSummary`) |
| `snapshot.rs` | `src/metrics/client.rs` (`snapshot()`), `src/events/session_telemetry.rs` |
| `timing.rs` | `src/metrics/client.rs` (`record_duration`, `start_timer`), `src/metrics/timer.rs` |
| `validation.rs` | `src/metrics/validation.rs`, `src/metrics/error.rs` (`MetricsError`) |

### 关键数据结构

```rust
// src/metrics/config.rs
pub struct MetricsConfig {
    pub(crate) environment: String,
    pub(crate) service_name: String,
    pub(crate) service_version: String,
    pub(crate) exporter: MetricsExporter,  // Otlp(OtelExporter) | InMemory(InMemoryMetricExporter)
    pub(crate) export_interval: Option<Duration>,
    pub(crate) runtime_reader: bool,       // 启用 ManualReader 以支持快照
    pub(crate) default_tags: BTreeMap<String, String>,
}

// src/events/session_telemetry.rs
pub struct SessionTelemetry {
    pub(crate) metadata: SessionTelemetryMetadata,
    pub(crate) metrics: Option<MetricsClient>,
    pub(crate) metrics_use_metadata_tags: bool,
}
```

---

## 依赖与外部交互

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `opentelemetry` | OTEL API（KeyValue、logs、trace） |
| `opentelemetry_sdk` | SDK 实现（InMemoryMetricExporter、InMemoryLogExporter、InMemorySpanExporter、ResourceMetrics） |
| `opentelemetry_otlp` | OTLP 导出器（HTTP/gRPC） |
| `opentelemetry_appender_tracing` | tracing 到 OTEL logs 的桥接 |
| `tracing_opentelemetry` | tracing 到 OTEL traces 的桥接 |
| `tracing_subscriber` | tracing 订阅者注册和过滤 |
| `pretty_assertions` | 测试断言美化 |
| `eventsource_stream` | SSE 事件类型（用于运行时指标测试） |
| `tokio_tungstenite` | WebSocket 消息类型（用于运行时指标测试） |

### 内部 Workspace 依赖

| Crate | 用途 |
|-------|------|
| `codex_otel` | 被测 crate（通过 `crate::` 或 `codex_otel::` 引用） |
| `codex_protocol` | `ThreadId`, `SessionSource`, `UserInput`, `AskForApproval`, `SandboxPolicy`, `ReasoningSummary` |
| `codex_api` | `ApiError`, `ResponseEvent` |

### 测试架构交互图

```
测试代码
    │
    ├───> MetricsClient ──> InMemoryMetricExporter (验证指标数据)
    │
    ├───> SessionTelemetry ──> MetricsClient
    │                              │
    │                              └───> InMemoryMetricExporter
    │
    ├───> OtelProvider ──> SdkLoggerProvider + SdkTracerProvider
    │                          │
    │                          ├───> InMemoryLogExporter (验证日志事件)
    │                          └───> InMemorySpanExporter (验证链路追踪)
    │
    └───> TcpListener (环回测试) <── OTLP HTTP Exporter
```

---

## 风险、边界与改进建议

### 当前风险与边界

1. **测试覆盖范围边界**
   - OTLP gRPC 导出器未在集成测试中覆盖（仅测试了 HTTP）
   - Statsig 导出器未测试（代码中标记为 `unreachable!`）
   - TLS 配置未在测试中验证

2. **并发与运行时边界**
   - `otlp_http_loopback.rs` 使用线程睡眠和超时轮询，可能不稳定
   - Tokio 当前线程运行时的测试使用 `thread::spawn` + `mpsc::channel`，复杂度较高

3. **数据验证边界**
   - 指标数据验证主要依赖 `find_metric` 和属性匹配，未验证完整的 OTEL 数据模型
   - 直方图测试仅验证桶计数和总和，未验证具体的桶分布

4. **测试隔离性**
   - `InMemoryMetricExporter` 是共享的，如果测试并行运行可能需要额外同步
   - `tracing::subscriber::with_default` 在并发测试中可能相互干扰

### 改进建议

1. **增强测试覆盖**
   - 添加 OTLP gRPC 环回测试（可使用 `tonic` 的测试服务器）
   - 添加 Statsig 导出器的 mock 测试
   - 添加 TLS 配置的单元测试（使用自签名证书）

2. **提高测试稳定性**
   - 使用 `tokio::net::TcpListener` 替代 `std::net::TcpListener` 以更好地集成异步运行时
   - 使用 `wiremock` 或类似的 HTTP mock 库替代手动 TCP 服务器

3. **增强验证粒度**
   - 验证完整的 `ResourceMetrics` 结构，包括资源属性
   - 验证直方图的桶边界和分布
   - 验证 OTEL 上下文传播（trace_id、span_id）

4. **代码组织改进**
   - 将 `harness/mod.rs` 中的辅助函数拆分为更专注的模块（如 `metrics_assertions.rs`、`otel_helpers.rs`）
   - 添加属性宏或过程宏简化测试中的重复模式（如指标查找和验证）

5. **文档与示例**
   - 添加更多测试作为使用示例，展示如何配置和使用 `MetricsClient`
   - 文档化测试中的 OTEL 数据模型期望（如属性命名规范）

### 关键指标名称清单（测试中使用的）

```rust
// src/metrics/names.rs
pub const TOOL_CALL_COUNT_METRIC: &str = "codex.tool.calls";
pub const TOOL_CALL_DURATION_METRIC: &str = "codex.tool.duration_ms";
pub const API_CALL_COUNT_METRIC: &str = "codex.api.calls";
pub const API_CALL_DURATION_METRIC: &str = "codex.api.duration_ms";
pub const SSE_EVENT_COUNT_METRIC: &str = "codex.sse.events";
pub const SSE_EVENT_DURATION_METRIC: &str = "codex.sse.duration_ms";
pub const WEBSOCKET_REQUEST_COUNT_METRIC: &str = "codex.ws.requests";
pub const WEBSOCKET_REQUEST_DURATION_METRIC: &str = "codex.ws.request_duration_ms";
pub const WEBSOCKET_EVENT_COUNT_METRIC: &str = "codex.ws.events";
pub const WEBSOCKET_EVENT_DURATION_METRIC: &str = "codex.ws.event_duration_ms";
pub const RESPONSES_API_OVERHEAD_DURATION_METRIC: &str = "codex.responses.overhead_ms";
pub const RESPONSES_API_INFERENCE_TIME_DURATION_METRIC: &str = "codex.responses.inference_ms";
// ... TTFT/TBT 指标
```

---

## 总结

`codex-rs/otel/tests` 是一个全面的集成测试套件，覆盖了 `codex-otel` crate 的核心功能。测试设计良好，使用了 OpenTelemetry SDK 提供的内存导出器进行验证，并通过手动 TCP 服务器验证了 OTLP HTTP 导出器的实际网络通信。主要改进空间在于增强 gRPC 和 TLS 的测试覆盖，以及使用更现代的异步测试工具替代手动线程管理。
