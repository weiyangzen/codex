# DIR Research: codex-rs/otel/src/metrics

> **研究范围**: `codex-rs/otel/src/metrics/` 目录  
> **研究时间**: 2026-03-21  
> **文档版本**: v1.0

---

## 1. 场景与职责

### 1.1 模块定位

`codex-rs/otel/src/metrics` 是 Codex 项目的 **OpenTelemetry 指标采集与导出核心模块**，负责：

1. **指标采集**: 收集 Codex 运行时的各类性能指标（API 调用、工具调用、WebSocket 事件、内存处理等）
2. **指标导出**: 通过 OTLP (OpenTelemetry Protocol) 将指标导出到远程收集器（如 Statsig、自定义 OTLP 端点）
3. **运行时快照**: 支持在运行时获取指标快照，用于调试和监控
4. **会话遥测集成**: 与 `SessionTelemetry` 集成，为每个会话提供独立的指标上下文

### 1.2 使用场景

| 场景 | 说明 |
|------|------|
| **API 调用监控** | 记录 OpenAI API 请求的延迟、成功率、状态码分布 |
| **工具调用追踪** | 记录 shell、文件操作等工具调用的次数和耗时 |
| **WebSocket 事件** | 监控实时通信事件的频率和处理时间 |
| **内存系统指标** | 追踪记忆提取（Phase 1/2）的 E2E 延迟和 Token 使用量 |
| **启动预热监控** | 记录会话启动预热的耗时和首次 Turn 的响应时间 |

### 1.3 架构位置

```
codex-rs/
├── otel/src/
│   ├── metrics/          # <-- 本模块
│   │   ├── mod.rs        # 全局指标客户端管理
│   │   ├── client.rs     # MetricsClient 实现
│   │   ├── config.rs     # 配置结构体
│   │   ├── error.rs      # 错误类型
│   │   ├── names.rs      # 指标名称常量
│   │   ├── runtime_metrics.rs  # 运行时指标汇总
│   │   ├── tags.rs       # 标签管理
│   │   ├── timer.rs      # 计时器工具
│   │   └── validation.rs # 名称/标签校验
│   ├── events/
│   │   └── session_telemetry.rs  # 会话级遥测（调用方）
│   ├── provider.rs       # OtelProvider（初始化入口）
│   └── ...
├── core/src/
│   ├── memories/         # 记忆系统（调用方）
│   ├── tasks/mod.rs      # Turn 处理（调用方）
│   ├── codex.rs          # 主入口（调用方）
│   └── ...
└── ...
```

---

## 2. 功能点目的

### 2.1 核心功能模块

#### 2.1.1 MetricsClient（client.rs）

**目的**: 提供线程安全的指标记录客户端

**功能**:
- `counter()`: 计数器递增（如 API 调用次数）
- `histogram()`: 直方图记录（如自定义数值分布）
- `record_duration()`: 时长记录（自动转换为毫秒）
- `start_timer()`: 启动计时器（返回 Timer 对象，Drop 时自动记录）
- `snapshot()`: 获取运行时指标快照（需启用 `runtime_reader`）
- `shutdown()`: 优雅关闭，刷新并关闭底层 Provider

**设计特点**:
- 使用 `Arc<MetricsClientInner>` 实现 Clone-on-write 语义
- 内部使用 `Mutex<HashMap>` 缓存 Counter/Histogram 实例，避免重复创建
- 支持默认标签（default_tags）自动附加到所有指标

#### 2.1.2 全局指标管理（mod.rs）

**目的**: 提供进程级单例指标客户端

```rust
static GLOBAL_METRICS: OnceLock<MetricsClient> = OnceLock::new();

pub(crate) fn install_global(metrics: MetricsClient) { ... }
pub fn global() -> Option<MetricsClient> { ... }
```

**使用模式**:
- 在 `OtelProvider::from()` 中初始化并安装全局客户端
- 业务代码通过 `codex_otel::metrics::global()` 获取客户端
- 如果未初始化，返回 `None`，业务代码需优雅处理

#### 2.1.3 指标名称常量（names.rs）

**目的**: 集中管理所有指标名称，避免硬编码和命名冲突

**分类**:
| 类别 | 指标示例 |
|------|----------|
| 工具调用 | `codex.tool.call`, `codex.tool.call.duration_ms` |
| API 请求 | `codex.api_request`, `codex.api_request.duration_ms` |
| SSE 事件 | `codex.sse_event`, `codex.sse_event.duration_ms` |
| WebSocket | `codex.websocket.request`, `codex.websocket.event` |
| Responses API | `codex.responses_api_overhead.duration_ms`, `codex.responses_api_inference_time.duration_ms` |
| Turn 级别 | `codex.turn.e2e_duration_ms`, `codex.turn.ttft.duration_ms` |
| 启动预热 | `codex.startup_prewarm.duration_ms`, `codex.startup_prewarm.age_at_first_turn_ms` |
| 线程管理 | `codex.thread.started` |

#### 2.1.4 运行时指标汇总（runtime_metrics.rs）

**目的**: 从 OpenTelemetry 的 `ResourceMetrics` 快照中提取结构化摘要

**核心结构**:
```rust
pub struct RuntimeMetricsSummary {
    pub tool_calls: RuntimeMetricTotals,           // 工具调用次数和总耗时
    pub api_calls: RuntimeMetricTotals,            // API 调用次数和总耗时
    pub streaming_events: RuntimeMetricTotals,     // SSE 事件统计
    pub websocket_calls: RuntimeMetricTotals,      // WebSocket 请求统计
    pub websocket_events: RuntimeMetricTotals,     // WebSocket 事件统计
    pub responses_api_overhead_ms: u64,            // Responses API 开销
    pub responses_api_inference_time_ms: u64,      // 推理时间
    pub responses_api_engine_iapi_ttft_ms: u64,    // 引擎 TTFT
    pub turn_ttft_ms: u64,                         // Turn 级别 TTFT
    pub turn_ttfm_ms: u64,                         // Turn 级别 TTFM
    // ...
}
```

**使用场景**: 
- 在 `SessionTelemetry::runtime_metrics_summary()` 中用于获取当前会话的指标摘要
- 用于调试输出、性能分析和遥测上报

#### 2.1.5 计时器（timer.rs）

**目的**: 提供 RAII 风格的自动计时

```rust
pub struct Timer {
    name: String,
    tags: Vec<(String, String)>,
    client: MetricsClient,
    start_time: Instant,
}

impl Drop for Timer {
    fn drop(&mut self) {
        // 自动记录时长
        if let Err(e) = self.record(&[]) { ... }
    }
}
```

**使用示例**:
```rust
let _timer = session.services.session_telemetry
    .start_timer(metrics::MEMORY_PHASE_ONE_E2E_MS, &[])
    .ok();
// 函数退出时自动记录时长
```

#### 2.1.6 标签管理（tags.rs）

**目的**: 标准化会话级标签的生成和校验

**预定义标签键**:
- `app.version`: 应用版本
- `auth_mode`: 认证模式（api_key, chatgpt）
- `model`: 使用的模型
- `originator`: 调用来源（codex_cli, codex_tui 等）
- `service_name`: 服务名称
- `session_source`: 会话来源（cli, exec, tui 等）

**SessionMetricTagValues**: 将会话元数据转换为标签向量，自动进行校验

#### 2.1.7 配置（config.rs）

**目的**: 定义指标客户端的初始化配置

```rust
pub struct MetricsConfig {
    pub(crate) environment: String,           // 环境（prod, staging, dev）
    pub(crate) service_name: String,          // 服务名称
    pub(crate) service_version: String,       // 服务版本
    pub(crate) exporter: MetricsExporter,     // 导出器类型
    pub(crate) export_interval: Option<Duration>, // 导出间隔
    pub(crate) runtime_reader: bool,          // 是否启用运行时快照
    pub(crate) default_tags: BTreeMap<String, String>, // 默认标签
}
```

**导出器类型**:
- `MetricsExporter::Otlp(OtelExporter)`: OTLP 远程导出
- `MetricsExporter::InMemory(InMemoryMetricExporter)`: 内存导出（测试用）

#### 2.1.8 校验（validation.rs）

**目的**: 确保指标名称和标签符合 OpenTelemetry 规范

**规则**:
- 指标名称: ASCII 字母数字 + `.` `_` `-`
- 标签键: ASCII 字母数字 + `.` `_` `-` `/`
- 标签值: ASCII 字母数字 + `.` `_` `-` `/`
- 非空校验

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 初始化流程

```
OtelProvider::from(settings)
├── resolve_exporter(&settings.metrics_exporter)
│   └── 如果是 Statsig，解析为 OTLP HTTP 端点
├── MetricsConfig::otlp(env, service_name, version, exporter)
│   └── 可选: with_runtime_reader(), with_tag()
├── MetricsClient::new(config)
│   ├── validate_tags(default_tags)
│   ├── 构建 Resource（包含 service_name, env, os_info）
│   ├── 创建 ManualReader（如果启用 runtime_reader）
│   ├── 根据 exporter 类型构建 Provider
│   │   ├── InMemory -> 使用 InMemoryMetricExporter
│   │   └── Otlp -> build_otlp_metric_exporter()
│   │       ├── OtlpGrpc -> tonic exporter with TLS
│   │       └── OtlpHttp -> HTTP exporter with TLS
│   └── 返回 MetricsClient(Arc<MetricsClientInner>)
├── install_global(metrics.clone())  # 安装全局客户端
└── 返回 OtelProvider { metrics: Some(client), ... }
```

#### 3.1.2 指标记录流程

**Counter 记录**:
```rust
// 1. 校验指标名称
validate_metric_name(name)?;
// 2. 校验递增值非负
if inc < 0 { return Err(...); }
// 3. 构建属性（合并默认标签和传入标签）
let attributes = self.attributes(tags)?;
// 4. 获取或创建 Counter 实例
let counter = counters.entry(name).or_insert_with(|| meter.u64_counter(name).build());
// 5. 记录
counter.add(inc as u64, &attributes);
```

**Duration 记录**:
```rust
// 1. 转换为毫秒（避免溢出）
let ms = duration.as_millis().min(i64::MAX as u128) as i64;
// 2. 使用专门的 duration_histogram（带单位 ms 和描述）
self.0.duration_histogram(name, ms, tags)
```

#### 3.1.3 运行时快照流程

```rust
// 1. 检查 runtime_reader 是否启用
let Some(reader) = &self.0.runtime_reader else { return Err(...); };
// 2. 创建空的 ResourceMetrics
let mut snapshot = ResourceMetrics::default();
// 3. 从 ManualReader 收集数据
reader.collect(&mut snapshot)?;
// 4. 返回快照
Ok(snapshot)
```

**注意**: ManualReader 使用 `Temporality::Delta`，每次收集后会重置计数器，适合获取增量数据。

### 3.2 关键数据结构

#### 3.2.1 MetricsClientInner

```rust
struct MetricsClientInner {
    meter_provider: SdkMeterProvider,                    // OTEL SDK Provider
    meter: Meter,                                        // 指标创建器
    counters: Mutex<HashMap<String, Counter<u64>>>,      // Counter 缓存
    histograms: Mutex<HashMap<String, Histogram<f64>>>,  // Histogram 缓存
    duration_histograms: Mutex<HashMap<String, Histogram<f64>>>, // Duration 专用缓存
    runtime_reader: Option<Arc<ManualReader>>,           // 运行时快照 Reader
    default_tags: BTreeMap<String, String>,              // 默认标签
}
```

#### 3.2.2 SharedManualReader

```rust
#[derive(Clone, Debug)]
struct SharedManualReader {
    inner: Arc<ManualReader>,
}

impl MetricReader for SharedManualReader {
    // 代理所有方法到 inner
}
```

**设计原因**: `ManualReader` 本身不是 Clone 的，但需要被多个组件共享（Provider 和 MetricsClient），因此使用 Arc 包装并实现 MetricReader trait。

### 3.3 协议与导出

#### 3.3.1 OTLP gRPC 导出

```rust
opentelemetry_otlp::MetricExporter::builder()
    .with_tonic()
    .with_endpoint(endpoint)
    .with_temporality(temporality)  // Delta
    .with_metadata(MetadataMap::from_headers(header_map))
    .with_tls_config(tls_config)    // 支持 mTLS
    .build()
```

#### 3.3.2 OTLP HTTP 导出

```rust
opentelemetry_otlp::MetricExporter::builder()
    .with_http()
    .with_endpoint(endpoint)
    .with_temporality(temporality)
    .with_protocol(protocol)        // HttpBinary or HttpJson
    .with_headers(headers)
    .with_http_client(client)       // 自定义 reqwest client（TLS 支持）
    .build()
```

#### 3.3.3 Statsig 集成

Statsig 是默认的指标收集端点：

```rust
// config.rs
pub(crate) const STATSIG_OTLP_HTTP_ENDPOINT: &str = "https://ab.chatgpt.com/otlp/v1/metrics";
pub(crate) const STATSIG_API_KEY: &str = "client-MkRuleRQBd6qakfnDYqJVR9JuXcY57Ljly3vi5JVUIO";

// resolve_exporter 函数将 Statsig 解析为 OtlpHttp
OtelExporter::Statsig => {
    if cfg!(test) || cfg!(feature = "disable-default-metrics-exporter") {
        return OtelExporter::None;  // 测试时禁用
    }
    OtelExporter::OtlpHttp { ... }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件

| 文件 | 职责 | 关键类型/函数 |
|------|------|---------------|
| `mod.rs` | 模块入口、全局客户端管理 | `GLOBAL_METRICS`, `install_global()`, `global()` |
| `client.rs` | MetricsClient 实现 | `MetricsClient`, `MetricsClientInner`, `build_otlp_metric_exporter()` |
| `config.rs` | 配置结构体 | `MetricsConfig`, `MetricsExporter` |
| `error.rs` | 错误类型 | `MetricsError` |
| `names.rs` | 指标名称常量 | `*_METRIC` 常量 |
| `runtime_metrics.rs` | 运行时指标汇总 | `RuntimeMetricsSummary`, `RuntimeMetricTotals` |
| `tags.rs` | 标签管理 | `SessionMetricTagValues`, `*_TAG` 常量 |
| `timer.rs` | 计时器 | `Timer` |
| `validation.rs` | 校验逻辑 | `validate_metric_name()`, `validate_tag_key()`, `validate_tag_value()` |

### 4.2 调用方代码路径

#### 4.2.1 会话遥测（otel/src/events/session_telemetry.rs）

```rust
// 记录 API 请求
self.counter(API_CALL_COUNT_METRIC, 1, &[("status", status_str), ("success", success_str)]);
self.record_duration(API_CALL_DURATION_METRIC, duration, &tags);

// 记录工具调用
self.counter(TOOL_CALL_COUNT_METRIC, 1, &[("tool", tool_name), ("success", success_str)]);
self.record_duration(TOOL_CALL_DURATION_METRIC, duration, &tags);

// 记录 WebSocket 事件
self.counter(WEBSOCKET_EVENT_COUNT_METRIC, 1, &[("kind", kind_str), ("success", success_str)]);

// 获取运行时摘要
pub fn runtime_metrics_summary(&self) -> Option<RuntimeMetricsSummary> {
    let snapshot = self.snapshot_metrics().ok()?;
    let summary = RuntimeMetricsSummary::from_snapshot(&snapshot);
    ...
}
```

#### 4.2.2 记忆系统（core/src/memories/）

**Phase 1** (`phase1.rs`):
```rust
// E2E 计时
let _phase_one_e2e_timer = session.services.session_telemetry
    .start_timer(metrics::MEMORY_PHASE_ONE_E2E_MS, &[])
    .ok();

// 任务计数
session.services.session_telemetry.counter(
    metrics::MEMORY_PHASE_ONE_JOBS,
    1,
    &[("status", "succeeded_with_output")],
);

// Token 使用量
session.services.session_telemetry.histogram(
    metrics::MEMORY_PHASE_ONE_TOKEN_USAGE,
    input_tokens,
    &[("type", "input")],
);
```

**Phase 2** (`phase2.rs`):
```rust
// 类似模式，使用 MEMORY_PHASE_TWO_* 指标
```

#### 4.2.3 Turn 处理（core/src/tasks/mod.rs）

```rust
// 网络代理指标
session_telemetry.counter(
    TURN_NETWORK_PROXY_METRIC,
    1,
    &[("active", active), ("tmp_mem", tmp_mem)],
);

// Token 使用
session_telemetry.histogram(
    TURN_TOKEN_USAGE_METRIC,
    token_usage.total_tokens as i64,
    &[("type", "total")],
);

// 工具调用计数
for (tool_name, count) in tool_call_counts {
    session_telemetry.counter(
        TURN_TOOL_CALL_METRIC,
        count,
        &[("tool", tool_name)],
    );
}
```

#### 4.2.4 全局指标调用（core/src/codex.rs 等）

```rust
// 直接使用全局客户端
if let Some(metrics) = codex_otel::metrics::global() {
    metrics.counter(THREAD_STARTED_METRIC, 1, &[("is_git", is_git_str)]);
}
```

### 4.3 初始化代码路径

**OtelProvider** (`otel/src/provider.rs`):
```rust
pub fn from(settings: &OtelSettings) -> Result<Option<Self>, Box<dyn Error>> {
    let metric_exporter = crate::config::resolve_exporter(&settings.metrics_exporter);
    let metrics = if matches!(metric_exporter, OtelExporter::None) {
        None
    } else {
        let mut config = MetricsConfig::otlp(...);
        if settings.runtime_metrics {
            config = config.with_runtime_reader();
        }
        Some(MetricsClient::new(config)?)
    };
    
    if let Some(metrics) = metrics.as_ref() {
        crate::metrics::install_global(metrics.clone());
    }
    ...
}
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖模块 | 用途 |
|----------|------|
| `otel/src/config.rs` | `OtelExporter`, `OtelSettings`, `resolve_exporter()` |
| `otel/src/otlp.rs` | TLS 配置构建、`build_header_map()` |
| `otel/src/events/session_telemetry.rs` | 主要调用方，会话级指标记录 |
| `otel/src/provider.rs` | 初始化入口 |

### 5.2 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `opentelemetry` | OTEL API（`KeyValue`, `Counter`, `Histogram`, `Meter`） |
| `opentelemetry_sdk` | OTEL SDK（`SdkMeterProvider`, `ManualReader`, `PeriodicReader`, `Resource`） |
| `opentelemetry_otlp` | OTLP 导出器（`MetricExporter`, `Protocol`, `WithExportConfig`） |
| `opentelemetry_semantic_conventions` | 语义约定（`semconv::attribute::SERVICE_VERSION`） |
| `os_info` | 获取操作系统信息用于资源属性 |
| `codex_utils_string::sanitize_metric_tag_value` | 标签值清理 |

### 5.3 上游调用方

| 模块 | 调用方式 | 用途 |
|------|----------|------|
| `core/src/codex.rs` | `codex_otel::metrics::global()` | 线程启动指标 |
| `core/src/tasks/mod.rs` | `session_telemetry.*` | Turn 级别指标 |
| `core/src/memories/phase1.rs` | `session_telemetry.*` | 记忆 Phase 1 指标 |
| `core/src/memories/phase2.rs` | `session_telemetry.*` | 记忆 Phase 2 指标 |
| `core/src/turn_timing.rs` | `session_telemetry.*` | TTFT/TTFM 指标 |
| `core/src/session_startup_prewarm.rs` | `session_telemetry.*` | 启动预热指标 |
| `core/src/exec.rs` | `codex_otel::metrics::global()` | 执行指标 |
| `core/src/mcp_connection_manager.rs` | `codex_otel::metrics::global()` | MCP 连接指标 |
| `core/src/windows_sandbox.rs` | `codex_otel::metrics::global()` | Windows 沙箱指标 |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 锁竞争风险

**问题**: `MetricsClientInner` 使用 `Mutex<HashMap>` 缓存 Counter/Histogram 实例，高并发场景下可能成为瓶颈。

**代码位置**:
```rust
// client.rs:103-110
let mut counters = self
    .counters
    .lock()
    .unwrap_or_else(std::sync::PoisonError::into_inner);
let counter = counters
    .entry(name.to_string())
    .or_insert_with(|| self.meter.u64_counter(name.to_string()).build());
```

**缓解措施**:
- 指标名称数量有限（预定义常量），HashMap 不会无限增长
- 实际瓶颈可能在 OTEL SDK 的批量处理而非此锁

#### 6.1.2 Panic 恢复

**问题**: 使用 `unwrap_or_else(std::sync::PoisonError::into_inner)` 在 Mutex 被污染后继续运行，可能导致状态不一致。

**建议**: 考虑使用 `parking_lot::Mutex` 替代，它不会中毒，且性能更好。

#### 6.1.3 负值计数器

**问题**: Counter 只接受非负值，但接口接受 `i64`，运行时检查可能遗漏。

```rust
pub fn counter(&self, name: &str, inc: i64, tags: &[(&str, &str)]) -> Result<()> {
    self.0.counter(name, inc, tags)
}
```

**建议**: 考虑使用 `u64` 作为参数类型，在编译期保证非负。

### 6.2 边界条件

#### 6.2.1 时长溢出

**处理**: `record_duration` 中对毫秒值进行溢出保护

```rust
let ms = duration.as_millis().min(i64::MAX as u128) as i64;
```

**边界**: 如果单次调用超过 `i64::MAX` 毫秒（约 2.9 亿年），会被截断。

#### 6.2.2 标签数量限制

**问题**: OpenTelemetry 后端可能对标签数量有限制，本模块未做限制。

**建议**: 考虑添加标签数量上限校验。

#### 6.2.3 指标名称长度

**问题**: 未对指标名称长度做限制，极长名称可能导致后端拒绝。

### 6.3 改进建议

#### 6.3.1 性能优化

1. **使用 `parking_lot::Mutex`**: 替代标准库 Mutex，避免中毒问题，提升性能
2. **指标缓存预热**: 在初始化时预创建常用 Counter/Histogram，避免首次记录时的锁竞争
3. **批量记录**: 考虑支持批量记录 API，减少锁获取次数

#### 6.3.2 可观测性增强

1. **指标记录失败统计**: 添加内部计数器，记录指标记录失败的次数和原因
2. **导出器健康检查**: 提供接口查询导出器连接状态
3. **指标采样**: 支持高频指标的采样记录，减少网络开销

#### 6.3.3 代码质量

1. **类型安全**: 为指标名称和标签键使用 Newtype 模式，避免字符串拼写错误
   ```rust
   pub struct MetricName(&'static str);
   pub struct TagKey(&'static str);
   ```

2. **文档完善**: 为每个指标常量添加 RustDoc 说明其用途、标签和示例值

3. **测试覆盖**: 添加更多边界条件测试（如超长标签、特殊字符等）

#### 6.3.4 配置灵活性

1. **动态标签**: 支持在运行时动态添加/删除默认标签
2. **指标过滤**: 支持按名称前缀过滤要记录的指标
3. **多级导出**: 支持同时导出到多个后端（如本地文件 + 远程 OTLP）

### 6.4 测试策略

**现有测试**:
- `tags.rs` 包含单元测试，验证标签生成逻辑
- `validation.rs` 可通过单元测试验证校验逻辑

**建议添加**:
- 集成测试：验证 OTLP 导出器正确构建
- Mock 测试：使用 `InMemoryMetricExporter` 验证指标记录准确性
- 压力测试：高并发场景下的性能和正确性

---

## 7. 总结

`codex-rs/otel/src/metrics` 是一个设计良好的 OpenTelemetry 指标模块，具有以下特点：

1. **清晰的架构**: 分层设计（Client -> Inner -> OTEL SDK），职责明确
2. **灵活的配置**: 支持 OTLP gRPC/HTTP、内存导出、Statsig 等多种后端
3. **丰富的指标**: 覆盖 API 调用、工具调用、WebSocket、内存系统等多个维度
4. **便捷的工具**: Timer 自动记录、全局客户端访问、运行时快照

主要改进方向是性能优化（锁机制）和可观测性增强（内部统计、健康检查）。
