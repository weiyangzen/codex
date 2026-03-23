# codex-rs/otel/src/config.rs 研究文档

## 场景与职责

`config.rs` 是 `codex-otel` crate 的配置模块，负责定义和管理 OpenTelemetry (OTEL) 导出器的配置结构。它是整个 OTEL 系统的配置入口，为日志、追踪和指标三种遥测数据提供统一的配置抽象。

**核心职责：**
1. 定义 OTEL 导出器的配置枚举和结构体
2. 提供 Statsig 导出器的默认配置解析（Codex 内部使用的指标收集服务）
3. 支持多种导出协议：gRPC、HTTP/JSON、HTTP/Binary
4. 支持 mTLS 客户端证书配置

## 功能点目的

### 1. Statsig 导出器集成

Statsig 是 Codex 内部使用的指标收集和分析平台。`resolve_exporter` 函数将 `OtelExporter::Statsig` 解析为实际的 OTLP/HTTP JSON 配置：

```rust
pub(crate) const STATSIG_OTLP_HTTP_ENDPOINT: &str = "https://ab.chatgpt.com/otlp/v1/metrics";
pub(crate) const STATSIG_API_KEY_HEADER: &str = "statsig-api-key";
pub(crate) const STATSIG_API_KEY: &str = "client-MkRuleRQBd6qakfnDYqJVR9JuXcY57Ljly3vi5JVUIO";
```

**安全考虑：**
- 在测试环境或启用 `disable-default-metrics-exporter` feature 时，Statsig 导出器会被禁用（返回 `OtelExporter::None`）
- API Key 硬编码在源码中，这是 Codex 内部服务的预配置

### 2. 导出器配置类型

**`OtelExporter` 枚举：**
- `None`: 禁用导出
- `Statsig`: Statsig 指标导出（仅用于指标）
- `OtlpGrpc`: OTLP/gRPC 协议导出
- `OtlpHttp`: OTLP/HTTP 协议导出（支持 JSON 或 Binary protobuf）

**`OtelHttpProtocol` 枚举：**
- `Binary`: HTTP + protobuf 二进制格式
- `Json`: HTTP + JSON 格式

**`OtelTlsConfig` 结构体：**
- `ca_certificate`: 自定义 CA 证书路径
- `client_certificate`: 客户端证书路径（mTLS）
- `client_private_key`: 客户端私钥路径（mTLS）

### 3. OTEL 设置聚合

`OtelSettings` 结构体聚合了所有 OTEL 相关的配置：
- `environment`: 运行环境（dev/staging/prod）
- `service_name`: 服务名称
- `service_version`: 服务版本
- `codex_home`: Codex 主目录路径
- `exporter`: 日志导出器配置
- `trace_exporter`: 追踪导出器配置
- `metrics_exporter`: 指标导出器配置
- `runtime_metrics`: 是否启用运行时指标

## 具体技术实现

### 关键数据结构

```rust
#[derive(Clone, Debug)]
pub struct OtelSettings {
    pub environment: String,
    pub service_name: String,
    pub service_version: String,
    pub codex_home: PathBuf,
    pub exporter: OtelExporter,
    pub trace_exporter: OtelExporter,
    pub metrics_exporter: OtelExporter,
    pub runtime_metrics: bool,
}

#[derive(Clone, Debug)]
pub enum OtelHttpProtocol {
    Binary,
    Json,
}

#[derive(Clone, Debug, Default)]
pub struct OtelTlsConfig {
    pub ca_certificate: Option<AbsolutePathBuf>,
    pub client_certificate: Option<AbsolutePathBuf>,
    pub client_private_key: Option<AbsolutePathBuf>,
}

#[derive(Clone, Debug)]
pub enum OtelExporter {
    None,
    Statsig,
    OtlpGrpc { endpoint: String, headers: HashMap<String, String>, tls: Option<OtelTlsConfig> },
    OtlpHttp { endpoint: String, headers: HashMap<String, String>, protocol: OtelHttpProtocol, tls: Option<OtelTlsConfig> },
}
```

### Statsig 解析逻辑

```rust
pub(crate) fn resolve_exporter(exporter: &OtelExporter) -> OtelExporter {
    match exporter {
        OtelExporter::Statsig => {
            // 测试环境禁用
            if cfg!(test) || cfg!(feature = "disable-default-metrics-exporter") {
                return OtelExporter::None;
            }
            // 解析为 OTLP/HTTP JSON 配置
            OtelExporter::OtlpHttp { ... }
        }
        _ => exporter.clone(),
    }
}
```

## 关键代码路径与文件引用

### 当前文件内引用
- `resolve_exporter`: 被 `provider.rs` 和 `metrics/client.rs` 调用
- `OtelSettings`: 被 `provider.rs` 的 `OtelProvider::from()` 使用
- `OtelExporter`: 被整个 crate 广泛使用

### 外部调用方

**`codex-rs/core/src/otel_init.rs`:**
```rust
use codex_otel::config::{OtelExporter, OtelHttpProtocol, OtelSettings, OtelTlsConfig};
// 将 Config 转换为 OtelSettings
```

**`codex-rs/otel/src/provider.rs`:**
```rust
let metric_exporter = crate::config::resolve_exporter(&settings.metrics_exporter);
```

**`codex-rs/otel/src/metrics/client.rs`:**
```rust
fn build_otlp_metric_exporter(exporter: OtelExporter, ...) {
    OtelExporter::Statsig => build_otlp_metric_exporter(
        crate::config::resolve_exporter(&OtelExporter::Statsig),
        ...
    ),
}
```

## 依赖与外部交互

### 内部依赖
- `codex_utils_absolute_path::AbsolutePathBuf`: 用于安全的绝对路径处理

### 外部依赖
- 无直接外部 crate 依赖（仅使用标准库）

### 配置流转
```
Config (codex-core)
    ↓
otel_init::build_provider() (转换 Config → OtelSettings)
    ↓
OtelProvider::from(&OtelSettings) (otel crate)
    ↓
resolve_exporter() (解析 Statsig 等简写)
    ↓
具体 Exporter 构建 (LogExporter/SpanExporter/MetricExporter)
```

## 风险、边界与改进建议

### 安全风险
1. **硬编码 API Key**: `STATSIG_API_KEY` 硬编码在源码中，虽然这是内部服务配置，但存在泄露风险
   - 建议：考虑从环境变量或配置文件读取

2. **测试环境泄漏**: 虽然测试环境会禁用 Statsig，但 feature flag 检查依赖于编译时配置
   - 建议：增加运行时环境检测

### 边界情况
1. **TLS 配置不完整**: `client_certificate` 和 `client_private_key` 必须同时提供，否则会在运行时报错
   - 当前在 `otlp.rs` 中进行检查

2. **路径验证**: `AbsolutePathBuf` 确保路径是绝对路径，但不验证文件是否存在或可读

### 改进建议
1. **配置验证**: 增加 `OtelSettings` 的验证方法，在构建前检查配置合法性
2. **文档完善**: Statsig 导出器的用途和限制需要更详细的文档
3. **协议默认值**: `OtelHttpProtocol` 可以考虑默认使用 `Binary`（更高效）而非 `Json`
4. **环境变量覆盖**: 考虑支持标准 OTEL 环境变量（如 `OTEL_EXPORTER_OTLP_ENDPOINT`）作为配置覆盖

### 测试相关
- `disable-default-metrics-exporter` feature 专门用于测试场景，确保单元测试不会意外发送真实指标
