# codex-rs/otel/src/otlp.rs 研究文档

## 场景与职责

`otlp.rs` 是 `codex-otel` crate 的 OTLP (OpenTelemetry Protocol) 协议实现模块。它负责构建和配置 OTLP 导出器所需的 HTTP/gRPC 客户端，包括 TLS 配置、超时设置和运行时适配。

**核心职责：**
1. 构建 HTTP Header 映射（用于 gRPC metadata 和 HTTP headers）
2. 构建 gRPC TLS 配置（支持 mTLS）
3. 构建同步/异步 HTTP 客户端（支持自定义 CA 和客户端证书）
4. 解析 OTLP 超时环境变量
5. 适配不同 Tokio 运行时类型（多线程 vs 当前线程）

## 功能点目的

### 1. Header 映射构建

`build_header_map` 将 `HashMap<String, String>` 转换为 `reqwest::header::HeaderMap`，用于 HTTP 导出器的自定义 header：

```rust
pub(crate) fn build_header_map(headers: &std::collections::HashMap<String, String>) -> HeaderMap
```

**特点：**
- 静默跳过无效的 header name 或 value
- 用于 OTLP/HTTP 和 OTLP/gRPC 两种协议

### 2. gRPC TLS 配置构建

`build_grpc_tls_config` 为 Tonic gRPC 客户端构建 TLS 配置：

```rust
pub(crate) fn build_grpc_tls_config(
    endpoint: &str,
    tls_config: ClientTlsConfig,
    tls: &OtelTlsConfig,
) -> Result<ClientTlsConfig, Box<dyn Error>>
```

**功能：**
- 从 endpoint 解析 host 设置 SNI
- 加载自定义 CA 证书
- 支持 mTLS（客户端证书 + 私钥）
- 验证证书和私钥必须成对提供

### 3. HTTP 客户端构建

**同步客户端（用于指标导出）：**
```rust
pub(crate) fn build_http_client(
    tls: &OtelTlsConfig,
    timeout_var: &str,
) -> Result<reqwest::blocking::Client, Box<dyn Error>>
```

**异步客户端（用于追踪导出）：**
```rust
pub(crate) fn build_async_http_client(
    tls: Option<&OtelTlsConfig>,
    timeout_var: &str,
) -> Result<reqwest::Client, Box<dyn Error>>
```

**关键设计决策：**
- 使用 `reqwest::blocking::Client` 因为 OTEL 指标导出器运行在独立 OS 线程上，不一定由 Tokio 支持
- 支持自定义 CA 证书（禁用内置根证书）
- 支持 mTLS（合并证书和私钥 PEM）

### 4. Tokio 运行时适配

`current_tokio_runtime_is_multi_thread` 检测当前是否在多线程 Tokio 运行时中：

```rust
pub(crate) fn current_tokio_runtime_is_multi_thread() -> bool
```

**用途：**
- 在多线程运行时中使用 `tokio::task::block_in_place` 避免阻塞
- 在当前线程运行时中需要 spawn 新线程来构建阻塞客户端

### 5. 超时解析

`resolve_otlp_timeout` 解析 OTEL 标准环境变量：

```rust
pub(crate) fn resolve_otlp_timeout(signal_var: &str) -> Duration
```

**优先级：**
1. 信号特定变量（如 `OTEL_EXPORTER_OTLP_TRACES_TIMEOUT`）
2. 通用变量 `OTEL_EXPORTER_OTLP_TIMEOUT`
3. 默认值 `OTEL_EXPORTER_OTLP_TIMEOUT_DEFAULT` (10s)

## 具体技术实现

### TLS 证书加载

```rust
fn read_bytes(path: &AbsolutePathBuf) -> Result<(Vec<u8>, PathBuf), Box<dyn Error>> {
    match fs::read(path) {
        Ok(bytes) => Ok((bytes, path.to_path_buf())),
        Err(error) => Err(Box::new(io::Error::new(
            error.kind(),
            format!("failed to read {}: {error}", path.display()),
        ))),
    }
}
```

### mTLS 证书合并

```rust
// 对于 reqwest，需要将证书和私钥合并到一个 PEM 中
let (mut cert_pem, cert_location) = read_bytes(cert_path)?;
let (key_pem, key_location) = read_bytes(key_path)?;
cert_pem.extend_from_slice(key_pem.as_slice());
let identity = ReqwestIdentity::from_pem(cert_pem.as_slice())?;
```

### 运行时适配逻辑

```rust
pub(crate) fn build_http_client(tls: &OtelTlsConfig, timeout_var: &str) -> Result<...> {
    if current_tokio_runtime_is_multi_thread() {
        // 多线程运行时：使用 block_in_place
        tokio::task::block_in_place(|| build_http_client_inner(tls, timeout_var))
    } else if tokio::runtime::Handle::try_current().is_ok() {
        // 当前线程运行时：spawn 新线程
        let tls = tls.clone();
        let timeout_var = timeout_var.to_string();
        std::thread::spawn(move || {
            build_http_client_inner(&tls, &timeout_var).map_err(|err| err.to_string())
        })
        .join()
        .map_err(...)?
        .map_err(...)
    } else {
        // 无 Tokio 运行时：直接构建
        build_http_client_inner(tls, timeout_var)
    }
}
```

## 关键代码路径与文件引用

### 被调用方

**`provider.rs` - 日志导出器：**
```rust
let header_map = crate::otlp::build_header_map(&headers);
let tls_config = crate::otlp::build_grpc_tls_config(&endpoint, base_tls_config, tls)?;
let client = crate::otlp::build_http_client(tls, OTEL_EXPORTER_OTLP_LOGS_TIMEOUT)?;
```

**`provider.rs` - 追踪导出器：**
```rust
if crate::otlp::current_tokio_runtime_is_multi_thread() {
    let client = crate::otlp::build_async_http_client(tls.as_ref(), OTEL_EXPORTER_OTLP_TRACES_TIMEOUT)?;
} else {
    let client = crate::otlp::build_http_client(tls, OTEL_EXPORTER_OTLP_TRACES_TIMEOUT)?;
}
```

**`metrics/client.rs` - 指标导出器：**
```rust
let header_map = crate::otlp::build_header_map(&headers);
let tls_config = crate::otlp::build_grpc_tls_config(&endpoint, base_tls_config, tls)?;
let client = crate::otlp::build_http_client(tls, OTEL_EXPORTER_OTLP_METRICS_TIMEOUT)?;
```

### 环境变量

| 变量名 | 用途 | 默认值 |
|--------|------|--------|
| `OTEL_EXPORTER_OTLP_TIMEOUT` | 通用超时 | 10000ms |
| `OTEL_EXPORTER_OTLP_TRACES_TIMEOUT` | 追踪特定超时 | 继承通用 |
| `OTEL_EXPORTER_OTLP_LOGS_TIMEOUT` | 日志特定超时 | 继承通用 |
| `OTEL_EXPORTER_OTLP_METRICS_TIMEOUT` | 指标特定超时 | 继承通用 |

## 依赖与外部交互

### 外部 crate 依赖

**HTTP/TLS:**
- `http::Uri`: 解析 endpoint URL
- `reqwest`: HTTP 客户端（阻塞和非阻塞）
- `opentelemetry_otlp::tonic_types`: Tonic gRPC 类型

**标准库:**
- `std::fs`: 文件读取
- `std::env`: 环境变量
- `std::time::Duration`: 超时处理

### 内部依赖
- `crate::config::OtelTlsConfig`: TLS 配置结构体
- `codex_utils_absolute_path::AbsolutePathBuf`: 安全路径处理

## 风险、边界与改进建议

### 运行时风险

1. **线程阻塞风险**: 在当前线程 Tokio 运行时中构建 HTTP 客户端会 spawn 新线程
   - 如果频繁创建/销毁 OTEL provider，可能导致线程爆炸
   - 建议：考虑使用连接池或缓存客户端

2. **运行时检测竞态**: `current_tokio_runtime_is_multi_thread` 在调用时检测，可能在不同调用间结果不一致
   - 建议：在 Provider 构建时确定运行时类型并复用

### TLS 风险

1. **证书格式限制**: 仅支持 PEM 格式
   - DER 格式证书需要手动转换

2. **证书链不完整**: 如果服务器需要中间证书，但仅配置了根证书，可能验证失败
   - 建议：文档说明需要完整的证书链

3. **私钥安全性**: 私钥以明文形式加载到内存
   - 这是标准做法，但需要注意内存安全

### 错误处理

1. **错误信息**: 当前错误信息包含文件路径，可能泄露敏感信息
   - 建议：在生产环境中考虑脱敏处理

2. **静默跳过**: `build_header_map` 静默跳过无效 header
   - 建议：考虑添加警告日志

### 测试覆盖

当前测试覆盖：
- `current_tokio_runtime_is_multi_thread_detects_runtime_flavor`: 运行时检测
- `build_http_client_works_in_current_thread_runtime`: 当前线程运行时客户端构建

缺失测试：
- mTLS 配置测试
- 自定义 CA 测试
- 超时解析测试
- 错误路径测试（无效证书、缺失文件等）

### 改进建议

1. **客户端缓存**: 考虑缓存 HTTP 客户端实例，避免重复构建
2. **异步构建**: 提供纯异步的客户端构建接口
3. **证书热重载**: 支持证书文件变更检测和自动重载
4. **指标暴露**: 暴露 TLS 握手耗时等指标
5. **日志增强**: 在关键路径添加结构化日志
