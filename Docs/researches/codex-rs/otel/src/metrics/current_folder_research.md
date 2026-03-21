# 研究文档: codex-rs/otel/src/metrics

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

`codex-rs/otel/src/metrics` 是 Codex 项目的 OpenTelemetry 指标采集与导出模块，负责：

1. **指标采集**：提供 Counter（计数器）和 Histogram（直方图）两种核心指标类型，支持工具调用、API 请求、WebSocket 事件等业务场景的度量
2. **指标导出**：通过 OTLP (OpenTelemetry Protocol) 协议将指标导出到外部收集器（如 Statsig、自建 OTLP 后端）
3. **运行时指标快照**：支持在运行时不关闭 Provider 的情况下采集当前指标状态，用于会话结束时的遥测汇总
4. **标签管理**：支持默认标签（全局）和调用时标签（局部）的合并，自动附加会话元数据（模型、认证模式、来源等）
5. **指标命名规范**：集中管理所有指标名称常量，确保命名一致性

该模块被 `SessionTelemetry` 大量使用，用于记录 Codex  CLI 和 TUI 的各种业务事件指标。

---

## 功能点目的

### 1. MetricsClient - 核心指标客户端

`MetricsClient` 是对 OpenTelemetry SDK 的封装，提供简化的 API：

- `counter(name, inc, tags)`：递增计数器，用于记录事件次数（如工具调用次数）
- `histogram(name, value, tags)`：记录直方图样本，用于记录数值分布（如延迟）
- `record_duration(name, duration, tags)`：专门用于记录持续时间（自动转换为毫秒）
- `start_timer(name, tags)`：启动一个计时器，Drop 时自动记录持续时间
- `snapshot()`：在不关闭 Provider 的情况下采集当前指标快照
- `shutdown()`：刷新并关闭指标导出器

### 2. 指标名称常量 (names.rs)

集中定义所有指标名称，按业务场景分类：

| 类别 | 指标名称 | 说明 |
|------|----------|------|
| 工具调用 | `codex.tool.call` / `codex.tool.call.duration_ms` | 工具调用次数和耗时 |
| API 请求 | `codex.api_request` / `codex.api_request.duration_ms` | API 请求次数和耗时 |
| SSE 事件 | `codex.sse_event` / `codex.sse_event.duration_ms` | Server-Sent Events 次数和耗时 |
| WebSocket | `codex.websocket.request` / `codex.websocket.event` | WebSocket 请求和事件 |
| 响应 API | `codex.responses_api_*.duration_ms` | 响应 API 各阶段耗时（TTFT、TBT 等）|
| 回合统计 | `codex.turn.e2e_duration_ms` / `codex.turn.ttft.duration_ms` | 单轮对话统计 |
| 启动预热 | `codex.startup_prewarm.duration_ms` | 启动预热耗时 |

### 3. 运行时指标汇总 (runtime_metrics.rs)

`RuntimeMetricsSummary` 结构体用于汇总会话期间的指标：

- `tool_calls`: 工具调用次数和总耗时
- `api_calls`: API 调用次数和总耗时
- `streaming_events`: SSE 事件次数和总耗时
- `websocket_calls/events`: WebSocket 请求和事件统计
- `responses_api_*_ms`: 响应 API 各阶段耗时
- `turn_ttft_ms` / `turn_ttfm_ms`: 首 token 时间和首消息时间

通过 `from_snapshot()` 方法从 `ResourceMetrics` 快照中提取并聚合指标数据。

### 4. 标签管理 (tags.rs)

`SessionMetricTagValues` 结构体定义了会话级别的标准标签：

- `auth_mode`: 认证模式（api_key / chatgpt）
- `session_source`: 会话来源（cli / tui / vscode）
- `originator`: 发起者标识
- `service_name`: 服务名称
- `model`: 使用的模型
- `app.version`: 应用版本

### 5. 验证机制 (validation.rs)

严格的命名规范验证：

- 指标名：只允许 ASCII 字母数字、点、下划线、连字符
- 标签键/值：允许 ASCII 字母数字、点、下划线、连字符、斜杠
- 禁止空字符串
- 计数器增量必须非负

### 6. 配置与导出器 (config.rs)

`MetricsConfig` 支持两种导出模式：

- `Otlp(OtelExporter)`: 通过 OTLP 协议导出到远程收集器
- `InMemory(InMemoryMetricExporter)`: 内存导出器，仅用于测试

配置选项包括：
- 环境、服务名、服务版本
- 导出间隔
- 是否启用运行时指标读取器
- 默认标签

---

## 具体技术实现

### 关键数据结构

```rust
// MetricsClient 内部结构
struct MetricsClientInner {
    meter_provider: SdkMeterProvider,     // OTEL SDK 计量器提供者
    meter: Meter,                         // 计量器实例
    counters: Mutex<HashMap<String, Counter<u64>>>,       // 计数器缓存
    histograms: Mutex<HashMap<String, Histogram<f64>>>,   // 直方图缓存
    duration_histograms: Mutex<HashMap<String, Histogram<f64>>>, // 持续时间直方图缓存
    runtime_reader: Option<Arc<ManualReader>>, // 手动读取器（用于快照）
    default_tags: BTreeMap<String, String>, // 默认标签
}

// 公共接口
pub struct MetricsClient(std::sync::Arc<MetricsClientInner>);
```

### 核心流程

#### 1. 初始化流程 (MetricsClient::new)

```
1. 验证默认标签
2. 构建 Resource（包含 service.name, service.version, env, os 信息）
3. 根据配置创建 runtime_reader（如果需要快照功能）
4. 根据 exporter 类型构建导出器：
   - InMemory: 直接使用 InMemoryMetricExporter
   - Otlp: 调用 build_otlp_metric_exporter() 构建 OTLP 导出器
5. 构建 SdkMeterProvider，配置 PeriodicReader（定期导出）和可选的 SharedManualReader（快照）
6. 返回 MetricsClient 实例
```

#### 2. 指标记录流程 (counter/histogram)

```
1. 验证指标名称合法性
2. 合并默认标签和调用时标签（调用时标签优先级更高）
3. 验证所有标签键值合法性
4. 从缓存获取或创建 Counter/Histogram 实例
5. 调用 OTEL SDK 记录指标值
```

#### 3. OTLP 导出器构建 (build_otlp_metric_exporter)

支持两种传输协议：

**gRPC 模式** (`OtlpGrpc`):
```rust
opentelemetry_otlp::MetricExporter::builder()
    .with_tonic()
    .with_endpoint(endpoint)
    .with_temporality(Temporality::Delta)  // Delta 临时性
    .with_metadata(MetadataMap::from_headers(header_map))
    .with_tls_config(tls_config)
    .build()
```

**HTTP 模式** (`OtlpHttp`):
```rust
opentelemetry_otlp::MetricExporter::builder()
    .with_http()
    .with_endpoint(endpoint)
    .with_temporality(Temporality::Delta)
    .with_protocol(Protocol::HttpBinary / Protocol::HttpJson)
    .with_headers(headers)
    .with_http_client(client)  // 可选自定义 HTTP 客户端（用于 TLS）
    .build()
```

#### 4. 快照采集流程 (snapshot)

```
1. 检查 runtime_reader 是否存在（需通过 with_runtime_reader() 启用）
2. 调用 ManualReader.collect(&mut ResourceMetrics) 采集当前指标
3. 返回 ResourceMetrics 结构（包含所有 ScopeMetrics 和 Metrics）
```

#### 5. 运行时指标汇总流程 (RuntimeMetricsSummary::from_snapshot)

```
1. 遍历 ResourceMetrics.scope_metrics().metrics()
2. 根据指标名称匹配：
   - 计数器类型：累加 SumDataPoint.value()
   - 直方图类型：累加 HistogramDataPoint.sum() 并转换为 u64
3. 填充 RuntimeMetricsSummary 各字段
```

### Timer 实现

`Timer` 结构体利用 Rust 的 Drop trait 实现自动计时：

```rust
impl Drop for Timer {
    fn drop(&mut self) {
        if let Err(e) = self.record(&[]) {
            tracing::error!("metrics client error: {}", e);
        }
    }
}
```

使用方式：
```rust
{
    let _timer = metrics.start_timer("codex.operation", &[("op", "read")])?;
    // ... 执行操作
} // Drop 时自动记录耗时
```

### 全局指标实例

通过 `std::sync::OnceLock` 实现全局单例：

```rust
static GLOBAL_METRICS: OnceLock<MetricsClient> = OnceLock::new();

pub(crate) fn install_global(metrics: MetricsClient) {
    let _ = GLOBAL_METRICS.set(metrics);
}

pub fn global() -> Option<MetricsClient> {
    GLOBAL_METRICS.get().cloned()
}
```

`SessionTelemetry::new()` 默认使用 `global()` 获取全局指标客户端。

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 | 关键类型/函数 |
|------|------|---------------|
| `mod.rs` | 模块入口，全局实例管理 | `GLOBAL_METRICS`, `install_global()`, `global()` |
| `client.rs` | MetricsClient 实现 | `MetricsClient`, `MetricsClientInner`, `build_otlp_metric_exporter()` |
| `config.rs` | 配置结构体 | `MetricsConfig`, `MetricsExporter` |
| `error.rs` | 错误类型定义 | `MetricsError` |
| `names.rs` | 指标名称常量 | `*_METRIC` 常量 |
| `runtime_metrics.rs` | 运行时指标汇总 | `RuntimeMetricsSummary`, `RuntimeMetricTotals` |
| `tags.rs` | 标签管理 | `SessionMetricTagValues` |
| `timer.rs` | 自动计时器 | `Timer` |
| `validation.rs` | 命名验证 | `validate_metric_name()`, `validate_tag_key()`, `validate_tag_value()` |

### 调用方代码路径

1. **SessionTelemetry** (`src/events/session_telemetry.rs`):
   - 使用 `counter()`/`histogram()`/`record_duration()` 记录业务指标
   - 使用 `runtime_metrics_summary()` 获取会话汇总
   - 通过 `tags_with_metadata()` 自动附加会话标签

2. **OtelProvider** (`src/provider.rs`):
   - 调用 `MetricsClient::new()` 创建指标客户端
   - 调用 `install_global()` 设置全局实例
   - 在 `shutdown()` 中调用 `metrics.shutdown()`

3. **全局计时器** (`src/lib.rs`):
   - `start_global_timer()` 使用全局指标实例启动计时器

### 被调用方代码路径

1. **OTEL SDK** (`opentelemetry_sdk`):
   - `SdkMeterProvider`, `Meter`, `Counter`, `Histogram`
   - `PeriodicReader`, `ManualReader`
   - `Resource`, `ResourceMetrics`

2. **OTLP Exporter** (`opentelemetry_otlp`):
   - `MetricExporter::builder()`
   - `Protocol`, `Temporality`

3. **工具库**:
   - `codex_utils_string::sanitize_metric_tag_value`: 清理标签值
   - `os_info::get()`: 获取操作系统信息

---

## 依赖与外部交互

### 外部依赖

| Crate | 用途 |
|-------|------|
| `opentelemetry` | OTEL API 定义（KeyValue, Meter 等） |
| `opentelemetry_sdk` | OTEL SDK 实现（SdkMeterProvider, PeriodicReader 等） |
| `opentelemetry_otlp` | OTLP 导出器实现 |
| `opentelemetry_semantic_conventions` | OTEL 语义约定常量 |
| `codex_utils_string` | `sanitize_metric_tag_value` 工具函数 |
| `os_info` | 获取操作系统类型和版本 |
| `thiserror` | 错误类型派生宏 |

### 配置依赖

- `OtelExporter` 定义在 `src/config.rs`，支持 Statsig 预设配置
- `OtelTlsConfig` 用于 mTLS 证书配置
- `build_http_client()` / `build_grpc_tls_config()` 定义在 `src/otlp.rs`

### 测试依赖

- `opentelemetry_sdk::metrics::InMemoryMetricExporter`: 内存导出器用于测试断言
- `pretty_assertions`: 测试断言美化

---

## 风险、边界与改进建议

### 已知风险

1. **Mutex  poison 风险**：
   - `counters`, `histograms`, `duration_histograms` 使用 `std::sync::Mutex`
   - 当前代码使用 `unwrap_or_else(std::sync::PoisonError::into_inner)` 处理 poison，可能导致数据不一致
   - **建议**：考虑使用 `parking_lot::Mutex` 或 `RwLock` 替代

2. **全局实例生命周期**：
   - `GLOBAL_METRICS` 使用 `OnceLock`，一旦设置不可更改
   - 不支持动态切换指标后端
   - **建议**：如需动态切换，考虑使用 `Arc<RwLock<Option<MetricsClient>>>`

3. **Timer Drop 错误处理**：
   - `Timer::drop()` 中记录指标失败仅记录日志，调用方无法感知
   - **建议**：如需严格保证指标记录，提供同步 `record()` 方法供显式调用

4. **f64 到 u64 转换精度**：
   - `f64_to_u64()` 在 `runtime_metrics.rs` 中转换直方图 sum 值
   - 大数值可能丢失精度（超过 2^53）
   - **建议**：评估是否需要使用 f64 存储汇总值

### 边界条件

1. **标签数量限制**：
   - OTEL 规范建议属性（标签）数量不超过 32 个
   - 当前实现无硬性限制，但过多标签可能影响性能和存储成本

2. **指标名称长度**：
   - 验证函数限制字符集，但无长度限制
   - 某些后端（如 Statsig）可能有长度限制

3. **导出超时**：
   - OTLP 导出器使用 `OTEL_EXPORTER_OTLP_METRICS_TIMEOUT` 环境变量控制超时
   - 默认 10 秒，网络不稳定时可能需要调整

### 改进建议

1. **性能优化**：
   - 考虑使用 `dashmap` 替代 `Mutex<HashMap>` 减少锁竞争
   - 批量记录 API 减少 SDK 调用开销

2. **可观测性增强**：
   - 添加内部指标（metrics about metrics）：记录丢弃的指标数、导出延迟等
   - 支持指标采样率配置

3. **功能扩展**：
   - 支持 Gauge（仪表盘）类型指标
   - 支持 UpDownCounter（可增减计数器）
   - 支持指标属性（标签）的自动注入（如 trace_id、span_id）

4. **配置增强**：
   - 支持从配置文件（非代码）配置指标导出
   - 支持多个导出器并行导出

5. **测试覆盖**：
   - 当前测试主要使用 InMemoryExporter，建议添加 OTLP  Mock Server 测试
   - 添加压力测试验证高并发场景下的性能

---

*文档生成时间: 2026-03-21*
*研究范围: codex-rs/otel/src/metrics/*
