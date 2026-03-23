# client.rs 深度研究文档

## 场景与职责

`client.rs` 是 Codex OpenTelemetry 指标系统的核心客户端实现，负责：

1. **指标收集与上报**：作为 OpenTelemetry SDK 的封装层，提供 Counter、Histogram 等指标的记录能力
2. **多协议导出支持**：支持 OTLP/gRPC 和 OTLP/HTTP 两种导出协议，以及内存导出（用于测试）
3. **运行时指标快照**：支持在不关闭 provider 的情况下获取当前指标状态
4. **资源属性管理**：自动注入服务版本、环境、操作系统信息等资源属性

该模块是 Codex 可观测性架构的核心组件，被 `SessionTelemetry` 和 `OtelProvider` 调用，最终通过 OpenTelemetry 协议将指标数据上报到 Statsig 或其他 OTLP 兼容后端。

## 功能点目的

### 1. MetricsClient - 主客户端结构

```rust
pub struct MetricsClient(std::sync::Arc<MetricsClientInner>);
```

- 使用 Arc 包装内部状态，支持克隆共享
- 提供线程安全的指标操作接口
- 封装 OpenTelemetry SDK 的复杂性

### 2. 指标类型支持

| 类型 | 用途 | 方法 |
|------|------|------|
| Counter | 计数类指标（如 API 调用次数） | `counter(name, inc, tags)` |
| Histogram | 数值分布（如延迟） | `histogram(name, value, tags)` |
| Duration Histogram | 持续时间记录（自动转毫秒） | `record_duration()`, `start_timer()` |

### 3. 双 Reader 架构

```rust
struct MetricsClientInner {
    meter_provider: SdkMeterProvider,
    meter: Meter,
    counters: Mutex<HashMap<String, Counter<u64>>>,
    histograms: Mutex<HashMap<String, Histogram<f64>>>,
    duration_histograms: Mutex<HashMap<String, Histogram<f64>>>,
    runtime_reader: Option<Arc<ManualReader>>,  // 运行时快照用
    default_tags: BTreeMap<String, String>,
}
```

- **PeriodicReader**: 定期导出指标到后端
- **ManualReader (runtime_reader)**: 支持按需快照，用于运行时指标查询

### 4. 导出协议支持

- **OTLP/gRPC**: 使用 tonic 实现，支持 TLS/mTLS
- **OTLP/HTTP**: 支持 Binary 和 JSON 两种序列化格式
- **InMemory**: 用于测试，指标存储在内存中

## 具体技术实现

### 关键流程

#### 1. 客户端初始化流程

```rust
pub fn new(config: MetricsConfig) -> Result<Self> {
    // 1. 验证默认标签
    validate_tags(&default_tags)?;
    
    // 2. 构建资源属性（服务版本、环境、OS信息）
    let resource = Resource::builder()
        .with_service_name(service_name)
        .with_attributes(resource_attributes)
        .build();
    
    // 3. 根据配置创建运行时 reader（可选）
    let runtime_reader = runtime_reader.then(|| Arc::new(ManualReader::builder()...));
    
    // 4. 构建 exporter 和 provider
    let (meter_provider, meter) = match exporter {
        MetricsExporter::InMemory(exporter) => build_provider(...),
        MetricsExporter::Otlp(exporter) => {
            let exporter = build_otlp_metric_exporter(exporter, Temporality::Delta)?;
            build_provider(...)
        }
    };
}
```

#### 2. Counter 记录流程

```rust
fn counter(&self, name: &str, inc: i64, tags: &[(&str, &str)]) -> Result<()> {
    // 1. 验证指标名
    validate_metric_name(name)?;
    // 2. 拒绝负值增量
    if inc < 0 { return Err(...); }
    // 3. 构建属性（合并默认标签和传入标签）
    let attributes = self.attributes(tags)?;
    // 4. 懒加载获取或创建 Counter
    let counter = counters.entry(name.to_string())
        .or_insert_with(|| self.meter.u64_counter(name.to_string()).build());
    // 5. 记录
    counter.add(inc as u64, &attributes);
}
```

#### 3. OTLP Exporter 构建

```rust
fn build_otlp_metric_exporter(exporter: OtelExporter, temporality: Temporality) 
    -> Result<opentelemetry_otlp::MetricExporter> {
    match exporter {
        OtelExporter::OtlpGrpc { endpoint, headers, tls } => {
            // 配置 gRPC TLS
            let tls_config = build_grpc_tls_config(&endpoint, base_tls_config, tls)?;
            opentelemetry_otlp::MetricExporter::builder()
                .with_tonic()
                .with_endpoint(endpoint)
                .with_temporality(temporality)
                .with_metadata(MetadataMap::from_headers(header_map))
                .with_tls_config(tls_config)
                .build()
        }
        OtelExporter::OtlpHttp { endpoint, headers, protocol, tls } => {
            // 配置 HTTP 客户端和协议
            let protocol = match protocol { Binary => HttpBinary, Json => HttpJson };
            opentelemetry_otlp::MetricExporter::builder()
                .with_http()
                .with_endpoint(endpoint)
                .with_protocol(protocol)
                .with_headers(headers)
                .build()
        }
    }
}
```

### 关键数据结构

```rust
// SharedManualReader: 包装 Arc<ManualReader> 实现 MetricReader trait
#[derive(Clone, Debug)]
struct SharedManualReader {
    inner: Arc<ManualReader>,
}

// MetricsClientInner: 客户端内部状态
#[derive(Debug)]
struct MetricsClientInner {
    meter_provider: SdkMeterProvider,
    meter: Meter,
    counters: Mutex<HashMap<String, Counter<u64>>>,      // 缓存 Counter 实例
    histograms: Mutex<HashMap<String, Histogram<f64>>>,  // 缓存 Histogram 实例
    duration_histograms: Mutex<HashMap<String, Histogram<f64>>>, // 持续时间专用
    runtime_reader: Option<Arc<ManualReader>>,           // 快照 reader
    default_tags: BTreeMap<String, String>,              // 默认标签
}
```

### 资源属性构建

```rust
fn os_resource_attributes() -> Vec<KeyValue> {
    let os_info = os_info::get();
    let os_type = sanitize_metric_tag_value(os_info.os_type().to_string().as_str());
    let os_version = sanitize_metric_tag_value(os_info.version().to_string().as_str());
    // 返回 os 和 os_version 属性（如果不是 "unspecified"）
}
```

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `config.rs` | `MetricsConfig`, `MetricsExporter` 配置结构 |
| `error.rs` | `MetricsError`, `Result` 错误类型 |
| `timer.rs` | `Timer` 结构，用于自动记录耗时 |
| `validation.rs` | 指标名和标签的验证函数 |
| `../config.rs` | `OtelExporter`, `OtelHttpProtocol` 导出配置 |
| `../otlp.rs` | `build_header_map`, `build_grpc_tls_config`, `build_http_client` |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `opentelemetry` | OpenTelemetry API |
| `opentelemetry_sdk` | SDK 实现（MeterProvider, Resource, Reader） |
| `opentelemetry_otlp` | OTLP 导出器 |
| `opentelemetry_semantic_conventions` | 语义约定常量 |
| `os_info` | 获取操作系统信息 |
| `codex_utils_string::sanitize_metric_tag_value` | 标签值清理 |

### 调用方

| 文件 | 调用方式 |
|------|----------|
| `provider.rs` | `MetricsClient::new(config)` 创建客户端并设置为全局 |
| `events/session_telemetry.rs` | 通过 `SessionTelemetry` 包装调用指标方法 |
| `metrics/timer.rs` | `Timer` 内部调用 `record_duration()` |

## 依赖与外部交互

### OpenTelemetry SDK 集成

```
MetricsClient
    ├─ SdkMeterProvider (with PeriodicReader + Optional ManualReader)
    ├─ Meter ("codex" 名称)
    ├─ Counter<u64> / Histogram<f64> (懒加载缓存)
    └─ Resource (service.name, service.version, env, os, os_version)
```

### 导出流程

```
指标记录 → Meter → PeriodicReader → MetricExporter → OTLP Endpoint
                                    ↓
                              ManualReader (快照查询)
```

### TLS 配置

- gRPC: 使用 `tonic::transport::ClientTlsConfig`
- HTTP: 使用 `reqwest` 的证书和身份配置
- 支持 mTLS（客户端证书 + 私钥）

## 风险、边界与改进建议

### 当前风险

1. **Mutex Poisoning**: 使用 `Mutex::unwrap_or_else(std::sync::PoisonError::into_inner)` 处理 poison，但可能导致数据不一致
2. **f64 转 u64 精度丢失**: `duration.as_millis()` 转 `i64` 时可能溢出（使用 `min(i64::MAX as u128)` 缓解）
3. **Counter 负值**: 运行时检查拒绝负增量，但错误处理依赖调用方

### 边界情况

1. **空标签**: `attributes()` 方法对空标签优化，直接返回默认标签
2. **重复指标名**: 使用 HashMap 缓存，相同名称复用同一 OTel Instrument
3. **Statsig 导出器**: 在测试环境或特定 feature 下自动禁用

### 改进建议

1. **性能优化**:
   - 考虑使用 `RwLock` 替代 `Mutex` 提高读并发
   - 标签合并可以优化为避免克隆（使用 Cow）

2. **错误处理**:
   - 考虑使用 `thiserror` 的 `#[from]` 自动转换
   - 添加更多上下文到错误信息

3. **功能增强**:
   - 支持 Gauge 类型指标
   - 支持 UpDownCounter（允许负值）
   - 支持自定义直方图边界

4. **可观测性**:
   - 添加内部指标（如导出延迟、失败率）
   - 支持指标导出批量大小的配置

5. **测试**:
   - 添加更多边界测试（如超长标签、特殊字符）
   - 测试 TLS/mTLS 配置
