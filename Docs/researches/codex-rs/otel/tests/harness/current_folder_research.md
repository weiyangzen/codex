# codex-rs/otel/tests/harness 研究文档

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

`codex-rs/otel/tests/harness` 是 OpenTelemetry (OTEL) 模块的**测试基础设施目录**，位于测试套件的核心位置：

```
codex-rs/otel/tests/
├── harness/           # 测试基础设施（本研究对象）
│   └── mod.rs         # 提供测试辅助函数和工具
├── suite/             # 实际测试用例
│   ├── mod.rs
│   ├── manager_metrics.rs
│   ├── otel_export_routing_policy.rs
│   ├── otlp_http_loopback.rs
│   ├── runtime_summary.rs
│   ├── send.rs
│   ├── snapshot.rs
│   ├── timing.rs
│   └── validation.rs
└── tests.rs           # 测试入口
```

### 1.2 核心职责

`harness/mod.rs` 作为测试共享基础设施，承担以下职责：

| 职责 | 说明 |
|------|------|
| **MetricsClient 构建** | 提供带默认标签的内存指标客户端构建函数 |
| **指标数据提取** | 从 `InMemoryMetricExporter` 中提取和解析指标数据 |
| **指标查找** | 按名称在资源指标中查找特定指标 |
| **属性转换** | 将 OpenTelemetry 属性转换为可比较的 BTreeMap |
| **直方图数据提取** | 提取直方图的边界、桶计数、总和和计数 |

### 1.3 被测系统概述

被测系统 `codex-otel` 是一个 OpenTelemetry 封装库，为 Codex CLI 提供：

1. **MetricsClient** - 指标收集客户端（计数器、直方图、定时器）
2. **SessionTelemetry** - 会话级遥测管理器，自动附加元数据标签
3. **OtelProvider** - OTEL 提供者，管理日志、追踪和指标导出
4. **RuntimeMetricsSummary** - 运行时指标汇总

---

## 功能点目的

### 2.1 测试基础设施功能

#### 2.1.1 `build_metrics_with_defaults`

**目的**：快速构建配置好的测试用 MetricsClient

**功能**：
- 创建 `InMemoryMetricExporter`（内存导出器，不发送网络请求）
- 使用 `MetricsConfig::in_memory()` 配置内存模式
- 支持注入默认标签（如 service、env 等）
- 返回 `(MetricsClient, InMemoryMetricExporter)` 元组，便于验证

**使用场景**：
- 所有需要验证指标输出的测试用例
- 需要隔离网络依赖的单元测试

#### 2.1.2 `latest_metrics`

**目的**：从内存导出器获取最新的指标快照

**功能**：
- 调用 `exporter.get_finished_metrics()` 获取已完成的指标
- 返回最后一个 `ResourceMetrics`（最新的指标集合）
- 如果指标缺失或出错则 panic（测试快速失败）

**使用场景**：
- 验证指标是否正确记录
- 在 `shutdown()` 后检查导出的指标

#### 2.1.3 `find_metric`

**目的**：在资源指标中按名称查找特定指标

**功能**：
- 遍历 `scope_metrics -> metrics` 层级
- 按 `metric.name()` 匹配
- 返回 `Option<&Metric>`

**使用场景**：
- 验证特定指标是否存在
- 获取指标进行进一步断言

#### 2.1.4 `attributes_to_map`

**目的**：将 OpenTelemetry 属性转换为可比较的 Rust 数据结构

**功能**：
- 将 `KeyValue` 迭代器转换为 `BTreeMap<String, String>`
- 使用 BTreeMap 保证确定性排序（便于测试断言）

**使用场景**：
- 验证指标标签是否正确
- 比较实际标签与预期标签

#### 2.1.5 `histogram_data`

**目的**：提取直方图的详细数据

**功能**：
- 返回 `(Vec<f64>, Vec<u64>, f64, u64)` 四元组：
  - 边界值（bounds）
  - 桶计数（bucket_counts）
  - 总和（sum）
  - 总计数（count）
- 断言只有一个数据点（测试场景简化）

**使用场景**：
- 验证直方图指标值
- 检查持续时间记录

### 2.2 测试覆盖的功能领域

| 测试文件 | 覆盖功能 |
|---------|---------|
| `send.rs` | 指标发送、标签合并、关闭刷新 |
| `timing.rs` | 持续时间记录、定时器 |
| `validation.rs` | 标签/指标名称验证、错误处理 |
| `snapshot.rs` | 运行时指标快照（不关闭） |
| `manager_metrics.rs` | SessionTelemetry 元数据标签附加 |
| `runtime_summary.rs` | 运行时指标汇总计算 |
| `otel_export_routing_policy.rs` | 日志 vs 追踪路由策略 |
| `otlp_http_loopback.rs` | OTLP HTTP 导出器集成测试 |

---

## 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 测试基础设施类型

```rust
// harness/mod.rs 中的函数签名

pub(crate) fn build_metrics_with_defaults(
    default_tags: &[(&str, &str)],
) -> Result<(MetricsClient, InMemoryMetricExporter)>;

pub(crate) fn latest_metrics(
    exporter: &InMemoryMetricExporter,
) -> ResourceMetrics;

pub(crate) fn find_metric<'a>(
    resource_metrics: &'a ResourceMetrics,
    name: &str,
) -> Option<&'a Metric>;

pub(crate) fn attributes_to_map<'a>(
    attributes: impl Iterator<Item = &'a KeyValue>,
) -> BTreeMap<String, String>;

pub(crate) fn histogram_data(
    resource_metrics: &ResourceMetrics,
    name: &str,
) -> (Vec<f64>, Vec<u64>, f64, u64);
```

#### 3.1.2 被测系统核心类型

**MetricsClient** (`src/metrics/client.rs`):
```rust
#[derive(Clone, Debug)]
pub struct MetricsClient(std::sync::Arc<MetricsClientInner>);

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

**SessionTelemetry** (`src/events/session_telemetry.rs`):
```rust
#[derive(Debug, Clone)]
pub struct SessionTelemetry {
    pub(crate) metadata: SessionTelemetryMetadata,
    pub(crate) metrics: Option<MetricsClient>,
    pub(crate) metrics_use_metadata_tags: bool,
}
```

**MetricsConfig** (`src/metrics/config.rs`):
```rust
#[derive(Clone, Debug)]
pub struct MetricsConfig {
    pub(crate) environment: String,
    pub(crate) service_name: String,
    pub(crate) service_version: String,
    pub(crate) exporter: MetricsExporter,
    pub(crate) export_interval: Option<Duration>,
    pub(crate) runtime_reader: bool,
    pub(crate) default_tags: BTreeMap<String, String>,
}
```

### 3.2 关键流程

#### 3.2.1 测试指标记录流程

```
测试用例
    │
    ▼
build_metrics_with_defaults(&[("service", "codex-cli")])
    │
    ├──► MetricsConfig::in_memory(env, service, version, exporter)
    │
    ├──► 为每个默认标签调用 config.with_tag(key, value)
    │       └── 验证标签键值 → 插入 default_tags BTreeMap
    │
    └──► MetricsClient::new(config)
            │
            ├──► validate_tags(&default_tags) - 验证所有标签
            │
            ├──► 构建 Resource（服务名称、版本、环境、OS 属性）
            │
            ├──► 根据配置构建 exporter（InMemory 或 OTLP）
            │
            └──► 构建 SdkMeterProvider 和 Meter
                    │
                    └── 返回 MetricsClient
    │
    ▼
metrics.counter("codex.turns", 1, &[("model", "gpt-5.1")])
    │
    ├──► validate_metric_name("codex.turns")
    │
    ├──► attributes(tags) - 合并默认标签和调用标签
    │       └── 标签优先级：调用标签 > 默认标签
    │
    └──► 获取或创建 Counter → add(inc, &attributes)
    │
    ▼
metrics.shutdown()
    │
    └──► meter_provider.force_flush() → meter_provider.shutdown()
    │
    ▼
latest_metrics(&exporter)
    │
    └──► exporter.get_finished_metrics() → 取最后一个 ResourceMetrics
    │
    ▼
find_metric(&resource_metrics, "codex.turns")
    │
    └──► 遍历 scope_metrics → metrics → 按名称匹配
    │
    ▼
attributes_to_map(points[0].attributes())
    │
    └──► 转换为 BTreeMap 进行断言比较
```

#### 3.2.2 SessionTelemetry 元数据标签附加流程

```
SessionTelemetry::new(...)
    │
    └──► 创建 SessionTelemetryMetadata（会话 ID、模型、认证模式等）
    │
    ▼
.with_metrics(metrics) 或 .with_metrics_without_metadata_tags(metrics)
    │
    └──► 设置 metrics_use_metadata_tags 标志
    │
    ▼
manager.counter("codex.session_started", 1, &[("source", "tui")])
    │
    ├──► tags_with_metadata(tags) - 合并元数据标签
    │       │
    │       ├──► metadata_tag_refs() - 如果启用元数据标签
    │       │       └── SessionMetricTagValues::into_tags()
    │       │           ├── app.version
    │       │           ├── auth_mode
    │       │           ├── model
    │       │           ├── originator
    │       │           ├── service_name
    │       │           └── session_source
    │       │
    │       └──► 合并调用者传入的标签
    │
    └──► metrics.counter(name, inc, &merged_tags)
```

#### 3.2.3 运行时指标快照流程

```
MetricsConfig::in_memory(...).with_runtime_reader()
    │
    └──► runtime_reader = true
    │
    ▼
MetricsClient::new(config)
    │
    └──► 创建 ManualReader（Delta 时间性）
    │       └── runtime_reader = Some(Arc<ManualReader>)
    │
    ▼
metrics.snapshot()
    │
    ├──► 检查 runtime_reader 是否存在
    │
    └──► reader.collect(&mut snapshot)
    │
    ▼
RuntimeMetricsSummary::from_snapshot(&snapshot)
    │
    ├──► sum_counter() - 累加计数器值
    │
    └──► sum_histogram_ms() - 累加直方图总和（毫秒）
            │
            └── 提取各项运行时指标：
                ├── tool_calls (工具调用次数和耗时)
                ├── api_calls (API 调用次数和耗时)
                ├── streaming_events (SSE 事件)
                ├── websocket_calls (WebSocket 请求)
                ├── websocket_events (WebSocket 事件)
                ├── responses_api_overhead_ms (API 开销)
                ├── responses_api_inference_time_ms (推理时间)
                ├── turn_ttft_ms (首 token 时间)
                └── turn_ttfm_ms (首消息时间)
```

### 3.3 验证规则

#### 3.3.1 指标名称验证 (`src/metrics/validation.rs`)

```rust
fn is_metric_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-')
}
```

- 允许：字母、数字、点、下划线、连字符
- 不允许：空格、斜杠（除标签外）等特殊字符

#### 3.3.2 标签键值验证

```rust
fn is_tag_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-' | '/')
}
```

- 标签值允许斜杠（`/`），标签键不允许
- 两者都不允许空格

#### 3.3.3 标签合并优先级

```rust
fn attributes(&self, tags: &[(&str, &str)]) -> Result<Vec<KeyValue>> {
    let mut merged = self.default_tags.clone();  // 1. 从默认标签开始
    for (key, value) in tags {
        merged.insert((*key).to_string(), (*value).to_string());  // 2. 调用标签覆盖
    }
    // ...
}
```

优先级：**调用标签 > 默认标签**

---

## 关键代码路径与文件引用

### 4.1 测试基础设施文件

| 文件 | 行数 | 关键内容 |
|------|------|---------|
| `harness/mod.rs` | 81 | `build_metrics_with_defaults`, `latest_metrics`, `find_metric`, `attributes_to_map`, `histogram_data` |

### 4.2 测试用例文件

| 文件 | 行数 | 测试覆盖 |
|------|------|---------|
| `suite/send.rs` | 205 | 指标发送、标签合并、关闭刷新、空关闭 |
| `suite/timing.rs` | 77 | 持续时间记录、定时器 |
| `suite/validation.rs` | 87 | 标签/指标名称验证、负计数器拒绝 |
| `suite/snapshot.rs` | 125 | 运行时指标快照 |
| `suite/manager_metrics.rs` | 155 | SessionTelemetry 元数据标签 |
| `suite/runtime_summary.rs` | 139 | 运行时指标汇总 |
| `suite/otel_export_routing_policy.rs` | 852 | 日志 vs 追踪路由策略（大文件） |
| `suite/otlp_http_loopback.rs` | 561 | OTLP HTTP 导出器集成测试 |

### 4.3 被测系统源文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `src/lib.rs` | 51 | 模块导出、全局定时器函数 |
| `src/metrics/mod.rs` | 25 | MetricsClient 导出、全局指标 |
| `src/metrics/client.rs` | 406 | MetricsClient 实现 |
| `src/metrics/config.rs` | 83 | MetricsConfig 构建器 |
| `src/metrics/validation.rs` | 55 | 名称/标签验证规则 |
| `src/metrics/names.rs` | 33 | 指标名称常量 |
| `src/metrics/tags.rs` | 108 | 会话标签值管理 |
| `src/metrics/timer.rs` | 41 | Timer 结构体（RAII 定时） |
| `src/metrics/runtime_metrics.rs` | 216 | RuntimeMetricsSummary 计算 |
| `src/metrics/error.rs` | 46 | MetricsError 枚举 |
| `src/events/session_telemetry.rs` | 1093 | SessionTelemetry 实现 |
| `src/events/shared.rs` | 60 | 日志/追踪事件宏 |
| `src/provider.rs` | 462 | OtelProvider 实现 |
| `src/config.rs` | 76 | OtelSettings、OtelExporter 配置 |
| `src/targets.rs` | 11 | 日志/追踪目标常量 |
| `src/otlp.rs` | 272 | OTLP 导出器构建、TLS 配置 |

### 4.4 关键代码引用

#### 4.4.1 测试辅助函数实现

```rust
// harness/mod.rs:12-27
pub(crate) fn build_metrics_with_defaults(
    default_tags: &[(&str, &str)],
) -> Result<(MetricsClient, InMemoryMetricExporter)> {
    let exporter = InMemoryMetricExporter::default();
    let mut config = MetricsConfig::in_memory(
        "test",
        "codex-cli",
        env!("CARGO_PKG_VERSION"),
        exporter.clone(),
    );
    for (key, value) in default_tags {
        config = config.with_tag(*key, *value)?;
    }
    let metrics = MetricsClient::new(config)?;
    Ok((metrics, exporter))
}
```

#### 4.4.2 指标查找实现

```rust
// harness/mod.rs:39-51
pub(crate) fn find_metric<'a>(
    resource_metrics: &'a ResourceMetrics,
    name: &str,
) -> Option<&'a Metric> {
    for scope_metrics in resource_metrics.scope_metrics() {
        for metric in scope_metrics.metrics() {
            if metric.name() == name {
                return Some(metric);
            }
        }
    }
    None
}
```

#### 4.4.3 直方图数据提取

```rust
// harness/mod.rs:61-81
pub(crate) fn histogram_data(
    resource_metrics: &ResourceMetrics,
    name: &str,
) -> (Vec<f64>, Vec<u64>, f64, u64) {
    let metric =
        find_metric(resource_metrics, name).unwrap_or_else(|| panic!("metric {name} missing"));
    match metric.data() {
        AggregatedMetrics::F64(data) => match data {
            MetricData::Histogram(histogram) => {
                let points: Vec<_> = histogram.data_points().collect();
                assert_eq!(points.len(), 1);
                let point = points[0];
                let bounds = point.bounds().collect();
                let bucket_counts = point.bucket_counts().collect();
                (bounds, bucket_counts, point.sum(), point.count())
            }
            _ => panic!("unexpected histogram aggregation"),
        },
        _ => panic!("unexpected metric data type"),
    }
}
```

---

## 依赖与外部交互

### 5.1 外部依赖

#### 5.1.1 OpenTelemetry 生态

| Crate | 用途 |
|-------|------|
| `opentelemetry` | 核心 API（KeyValue、指标类型） |
| `opentelemetry_sdk` | SDK 实现（InMemoryMetricExporter、ResourceMetrics、ManualReader） |
| `opentelemetry_otlp` | OTLP 导出器（HTTP/gRPC） |
| `opentelemetry-appender-tracing` | tracing 到 OTEL 日志的桥接 |
| `opentelemetry-semantic-conventions` | 语义约定（service.name 等） |

#### 5.1.2 其他关键依赖

| Crate | 用途 |
|-------|------|
| `tracing` / `tracing-subscriber` | 结构化日志和追踪 |
| `tokio` | 异步运行时（测试中使用 multi_thread flavor） |
| `serde` / `serde_json` | 序列化（配置、事件数据） |
| `thiserror` | 错误定义 |
| `pretty_assertions` | 测试断言美化 |

### 5.2 内部依赖

| 模块 | 依赖关系 |
|------|---------|
| `codex-protocol` | ThreadId、SessionSource、UserInput、ReasoningSummary 等 |
| `codex-api` | ApiError、ResponseEvent |
| `codex-utils-string` | sanitize_metric_tag_value |
| `codex-utils-absolute-path` | AbsolutePathBuf |

### 5.3 测试架构交互

```
┌─────────────────────────────────────────────────────────────┐
│                     测试用例 (suite/*.rs)                     │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────────────────┐ │
│  │ send.rs │ │timing.rs│ │snapshot │ │otel_export_routing  │ │
│  └────┬────┘ └────┬────┘ └────┬────┘ └──────────┬──────────┘ │
│       └────────────┴───────────┴────────────────┘            │
│                         │                                    │
│                         ▼                                    │
│              ┌─────────────────────┐                         │
│              │   harness/mod.rs    │                         │
│              │  (测试基础设施)      │                         │
│              └─────────────────────┘                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    被测系统 (src/*.rs)                        │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────────┐ │
│  │MetricsClient│ │SessionTelemetry│ │    OtelProvider      │ │
│  └─────────────┘ └─────────────┘ └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              OpenTelemetry SDK / OTLP Exporter               │
└─────────────────────────────────────────────────────────────┘
```

---

## 风险、边界与改进建议

### 6.1 当前风险与边界

#### 6.1.1 测试基础设施限制

| 风险点 | 说明 | 影响 |
|--------|------|------|
| **单数据点假设** | `histogram_data` 断言只有一个数据点 | 多数据点测试会 panic |
| **panic 风格** | `latest_metrics` 和 `histogram_data` 在失败时 panic | 测试无法优雅处理缺失指标 |
| **硬编码常量** | "test", "codex-cli" 等硬编码在 `build_metrics_with_defaults` | 无法灵活配置测试环境 |
| **无并发测试** | 基础设施未考虑并发指标记录场景 | 可能遗漏并发问题 |

#### 6.1.2 被测系统边界

| 边界 | 说明 |
|------|------|
| **标签值长度** | 无明确长度限制，但 OTEL 后端可能有 |
| **标签数量** | 无明确限制，但过多会影响性能 |
| **指标名称长度** | 无明确限制 |
| **计数器增量** | 拒绝负值（返回 `NegativeCounterIncrement` 错误） |
| **时间精度** | 持续时间转换为毫秒，可能丢失微秒精度 |

#### 6.1.3 测试覆盖缺口

| 缺口 | 说明 |
|------|------|
| **OTLP gRPC 测试** | `otlp_http_loopback.rs` 仅测试 HTTP，无 gRPC 测试 |
| **TLS 测试** | 无 mTLS 或自定义 CA 证书测试 |
| **并发指标记录** | 无多线程并发记录相同指标的测试 |
| **错误恢复** | 无导出失败后的重试或降级测试 |
| **内存压力** | 无大量指标下的内存使用测试 |

### 6.2 改进建议

#### 6.2.1 测试基础设施改进

1. **增加灵活的配置选项**
   ```rust
   // 建议：允许自定义服务名和环境
   pub(crate) fn build_metrics_with_config(
       service_name: &str,
       environment: &str,
       default_tags: &[(&str, &str)],
   ) -> Result<(MetricsClient, InMemoryMetricExporter)>
   ```

2. **优雅处理缺失指标**
   ```rust
   // 建议：返回 Result 而非 panic
   pub(crate) fn try_find_metric<'a>(
       resource_metrics: &'a ResourceMetrics,
       name: &str,
   ) -> Result<&'a Metric, MetricsNotFoundError>
   ```

3. **支持多数据点直方图**
   ```rust
   // 建议：不强制单数据点
   pub(crate) fn histogram_data_points(
       resource_metrics: &ResourceMetrics,
       name: &str,
   ) -> Vec<(Vec<f64>, Vec<u64>, f64, u64)>
   ```

4. **增加并发测试辅助函数**
   ```rust
   // 建议：并发记录指标并验证
   pub(crate) async fn record_concurrent_metrics(
       metrics: &MetricsClient,
       workers: usize,
       iterations: usize,
   ) -> Result<()>
   ```

#### 6.2.2 测试覆盖扩展

| 优先级 | 测试类型 | 说明 |
|--------|---------|------|
| 高 | OTLP gRPC 回环测试 | 验证 gRPC 导出器工作正常 |
| 高 | TLS/mTLS 配置测试 | 验证证书加载和身份验证 |
| 中 | 并发指标记录测试 | 验证线程安全 |
| 中 | 大量指标压力测试 | 验证内存和性能 |
| 低 | 网络故障恢复测试 | 验证导出失败处理 |

#### 6.2.3 代码质量改进

1. **文档完善**
   - 为 `harness` 函数添加更多使用示例
   - 说明标签合并优先级的文档

2. **错误信息改进**
   - 在 `histogram_data` panic 时包含可用指标列表
   - 在 `latest_metrics` panic 时说明可能原因

3. **类型安全**
   - 考虑为指标名称使用 newtype 模式
   - 考虑为标签键使用常量或枚举

### 6.3 维护注意事项

| 注意事项 | 说明 |
|---------|------|
| **OpenTelemetry 版本升级** | OTEL SDK API 变化可能影响测试 |
| **指标名称变更** | 修改 `names.rs` 中的常量需同步更新测试 |
| **新标签添加** | 添加新元数据标签需更新 `tags.rs` 和测试 |
| **运行时指标扩展** | 新增运行时指标需更新 `runtime_metrics.rs` 和测试 |

---

## 附录：测试执行命令

```bash
# 运行所有 otel 测试
cd codex-rs && cargo test -p codex-otel

# 运行特定测试文件
cargo test -p codex-otel send
cargo test -p codex-otel timing
cargo test -p codex-otel validation

# 运行带日志输出的测试
cargo test -p codex-otel -- --nocapture

# 使用 nextest（如果安装）
cargo nextest run -p codex-otel
```

---

*文档生成时间：2026-03-22*
*研究范围：codex-rs/otel/tests/harness 及其相关上下文*
