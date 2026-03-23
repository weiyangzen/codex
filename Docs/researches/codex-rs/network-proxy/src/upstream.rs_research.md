# upstream.rs 研究文档

## 场景与职责

`upstream.rs` 负责管理网络代理到上游服务器的连接，包括直接连接、通过 HTTP 代理连接以及 Unix socket 连接。它是网络代理的出口层，处理所有向外的 HTTP/HTTPS 请求。

### 核心职责

1. **上游连接管理**：建立和维护到目标服务器的连接
2. **代理链支持**：支持通过上游 HTTP 代理转发请求
3. **Unix Socket 支持**：支持通过 Unix socket 连接本地服务（macOS 专用）
4. **TLS 处理**：自动处理 HTTPS 连接的 TLS 握手
5. **环境变量集成**：从环境变量读取代理配置

## 功能点目的

### 1. UpstreamClient - 上游客户端

```rust
#[derive(Clone)]
pub(crate) struct UpstreamClient {
    connector: BoxService<
        Request<Body>,
        EstablishedClientConnection<HttpClientService<Body>, Request<Body>>,
        BoxError,
    >,
    proxy_config: ProxyConfig,
}
```

**设计目的**：
- 封装连接建立细节，提供统一的请求接口
- 支持动态代理选择（基于请求协议）
- 实现 Rama `Service` trait，可集成到服务链

### 2. 代理配置解析

```rust
#[derive(Clone, Default)]
struct ProxyConfig {
    http: Option<ProxyAddress>,
    https: Option<ProxyAddress>,
    all: Option<ProxyAddress>,
}
```

**环境变量支持**：
- `HTTP_PROXY` / `http_proxy`
- `HTTPS_PROXY` / `https_proxy`
- `ALL_PROXY` / `all_proxy`

**优先级**：
- HTTPS 请求：`HTTPS_PROXY` > `HTTP_PROXY` > `ALL_PROXY`
- HTTP 请求：`HTTP_PROXY` > `ALL_PROXY`

### 3. 连接构建器

```rust
fn build_http_connector() -> BoxService<...>
```

**连接栈**（从内到外）：
1. `TcpConnector` - TCP 传输层
2. `HttpProxyConnectorLayer` - 可选的 HTTP 代理层
3. `TlsConnectorLayer` - TLS 加密层（自动检测）
4. `RequestVersionAdapter` - HTTP 版本适配
5. `HttpConnector` - HTTP 协议层

### 4. Unix Socket 支持（macOS 专用）

```rust
#[cfg(target_os = "macos")]
pub(crate) fn unix_socket(path: &str) -> Self
```

**实现**：
- 使用 `rama_unix::client::UnixConnector`
- 绕过 TCP 栈，直接连接 Unix socket
- 用于访问本地服务（如 Docker daemon）

## 具体技术实现

### 依赖的 Rama 组件

```rust
use rama_core::{Layer, Service, error::BoxError};
use rama_http::{Body, Request, Response};
use rama_http_backend::client::{HttpClientService, HttpConnector};
use rama_http_backend::client::proxy::layer::HttpProxyConnectorLayer;
use rama_net::address::ProxyAddress;
use rama_net::client::EstablishedClientConnection;
use rama_tcp::client::service::TcpConnector;
use rama_tls_rustls::client::{TlsConnectorDataBuilder, TlsConnectorLayer};
#[cfg(target_os = "macos")]
use rama_unix::client::UnixConnector;
```

**Rama 架构理解**：
- `Layer` trait：用于包装服务，添加功能
- `Service` trait：处理请求的核心抽象
- `BoxService`：类型擦除的服务包装

### 代理配置解析

```rust
fn read_proxy_env(keys: &[&str]) -> Option<ProxyAddress> {
    for key in keys {
        let Ok(value) = std::env::var(key) else { continue };
        let value = value.trim();
        if value.is_empty() { continue; }
        match ProxyAddress::try_from(value) {
            Ok(proxy) => {
                // 验证协议是否为 HTTP
                if proxy.protocol.as_ref().map(|p| p.is_http()).unwrap_or(true) {
                    return Some(proxy);
                }
                warn!("ignoring {key}: non-http proxy protocol");
            }
            Err(err) => {
                warn!("ignoring {key}: invalid proxy address ({err})");
            }
        }
    }
    None
}
```

**关键逻辑**：
- 按优先级遍历环境变量
- 验证代理地址格式
- 仅支持 HTTP 协议代理
- 记录被忽略的配置和原因

### HTTP 连接器构建

```rust
fn build_http_connector() -> BoxService<...> {
    // 1. TCP 传输层
    let transport = TcpConnector::default();
    
    // 2. HTTP 代理层（可选）
    let proxy = HttpProxyConnectorLayer::optional().into_layer(transport);
    
    // 3. TLS 层
    let tls_config = TlsConnectorDataBuilder::new()
        .with_alpn_protocols_http_auto()
        .build();
    let tls = TlsConnectorLayer::auto()
        .with_connector_data(tls_config)
        .into_layer(proxy);
    
    // 4. HTTP 版本适配
    let tls = RequestVersionAdapter::new(tls);
    
    // 5. HTTP 协议层
    let connector = HttpConnector::new(tls);
    connector.boxed()
}
```

**TLS 配置**：
- 使用 `rustls` 作为 TLS 后端
- 自动协商 ALPN（HTTP/1.1 或 HTTP/2）
- `TlsConnectorLayer::auto()` 自动检测是否需要 TLS

### Unix 连接器构建（macOS）

```rust
#[cfg(target_os = "macos")]
fn build_unix_connector(path: &str) -> BoxService<...> {
    let transport = UnixConnector::fixed(path);
    let connector = HttpConnector::new(transport);
    connector.boxed()
}
```

**简化设计**：
- Unix socket 连接不涉及代理链
- 不需要 TLS（本地通信）
- 使用固定路径的连接器

### Service 实现

```rust
impl Service<Request<Body>> for UpstreamClient {
    type Output = Response;
    type Error = OpaqueError;

    async fn serve(&self, mut req: Request<Body>) -> Result<Self::Output, Self::Error> {
        // 1. 根据请求选择代理
        if let Some(proxy) = self.proxy_config.proxy_for_request(&req) {
            req.extensions_mut().insert(proxy);
        }

        let uri = req.uri().clone();
        
        // 2. 建立连接
        let EstablishedClientConnection { input: mut req, conn: http_connection } = 
            self.connector.serve(req).await.map_err(...)?;

        // 3. 复制连接扩展
        req.extensions_mut().extend(http_connection.extensions().clone());

        // 4. 发送请求
        http_connection.serve(req).await.map_err(...)
            .with_context(|| format!("http request failure for uri: {uri}"))
    }
}
```

**关键机制**：
- 代理地址通过 `extensions` 传递给底层连接器
- `EstablishedClientConnection` 包含连接和（可能修改的）请求
- 连接级别的扩展（如 TLS 信息）复制到请求扩展

## 关键代码路径与文件引用

### 主要类型

| 类型 | 行号 | 说明 |
|------|------|------|
| `ProxyConfig` | 27-59 | 代理配置结构 |
| `UpstreamClient` | 94-128 | 上游客户端 |

### 主要函数

| 函数 | 行号 | 说明 |
|------|------|------|
| `ProxyConfig::from_env` | 35-40 | 从环境变量解析 |
| `ProxyConfig::proxy_for_request` | 42-47 | 请求代理选择 |
| `read_proxy_env` | 61-88 | 环境变量读取 |
| `proxy_for_connect` | 90-92 | 获取 CONNECT 代理 |
| `UpstreamClient::direct` | 105-107 | 直接连接 |
| `UpstreamClient::from_env_proxy` | 109-111 | 从环境变量创建 |
| `UpstreamClient::unix_socket` | 113-120 | Unix socket 连接（macOS） |
| `build_http_connector` | 161-177 | HTTP 连接器构建 |
| `build_unix_connector` | 179-190 | Unix 连接器构建（macOS） |

### 关键代码片段

#### 代理选择逻辑（行 42-58）

```rust
fn proxy_for_request(&self, req: &Request) -> Option<ProxyAddress> {
    let is_secure = RequestContext::try_from(req)
        .map(|ctx| ctx.protocol.is_secure())
        .unwrap_or(false);
    self.proxy_for_protocol(is_secure)
}

fn proxy_for_protocol(&self, is_secure: bool) -> Option<ProxyAddress> {
    if is_secure {
        self.https.clone()
            .or_else(|| self.http.clone())
            .or_else(|| self.all.clone())
    } else {
        self.http.clone().or_else(|| self.all.clone())
    }
}
```

#### Service 实现（行 131-158）

```rust
async fn serve(&self, mut req: Request<Body>) -> Result<Self::Output, Self::Error> {
    if let Some(proxy) = self.proxy_config.proxy_for_request(&req) {
        req.extensions_mut().insert(proxy);
    }

    let uri = req.uri().clone();
    let EstablishedClientConnection {
        input: mut req,
        conn: http_connection,
    } = self.connector.serve(req).await.map_err(...)?;

    req.extensions_mut().extend(http_connection.extensions().clone());

    http_connection.serve(req).await.map_err(...)
}
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| 无直接内部依赖 | 独立模块，仅依赖 Rama 生态 |

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `rama_core` | 核心服务抽象 |
| `rama_http` | HTTP 类型定义 |
| `rama_http_backend` | HTTP 客户端实现 |
| `rama_net` | 网络地址和代理抽象 |
| `rama_tcp` | TCP 连接器 |
| `rama_tls_rustls` | TLS 支持 |
| `rama_unix` | Unix socket 支持（macOS） |
| `tracing` | 日志记录 |

### 调用方

- `http_proxy.rs`：`UpstreamClient::direct()`, `UpstreamClient::from_env_proxy()`
- `http_proxy.rs`（macOS）：`UpstreamClient::unix_socket()`
- 用于转发经过策略检查的 HTTP 请求

## 风险、边界与改进建议

### 潜在风险

1. **代理循环**
   - 如果上游代理配置指向自身，可能导致无限循环
   - 当前无循环检测机制
   - 建议：添加 `X-Forwarded-For` 或类似头部检测

2. **TLS 证书验证**
   - 使用默认 `rustls` 配置
   - 可能拒绝自签名证书（企业内网场景）
   - 建议：考虑支持自定义 CA 配置

3. **Unix Socket 安全风险**
   - Unix socket 绕过网络策略检查
   - 依赖 `is_unix_socket_allowed` 前置检查
   - 建议：确保所有调用点都执行权限检查

4. **环境变量敏感信息泄露**
   - 代理 URL 可能包含用户名/密码
   - 环境变量可能被其他进程读取
   - 建议：考虑支持从文件或密钥管理服务读取

### 边界情况

1. **代理 URL 格式**
   - 支持 `http://host:port` 格式
   - 不支持 SOCKS 代理（由 `socks5.rs` 处理）
   - 非 HTTP 协议代理被忽略并记录警告

2. **连接失败处理**
   - 连接器失败返回 `OpaqueError`
   - 包含原始 URI 信息便于调试
   - 不实现重试逻辑（由调用方处理）

3. **HTTP/2 支持**
   - 通过 `TlsConnectorDataBuilder::with_alpn_protocols_http_auto()` 启用 ALPN
   - 实际协议协商由 `rustls` 处理
   - 回退到 HTTP/1.1 如果服务器不支持

### 改进建议

1. **功能增强**
   - 支持连接池复用
   - 支持请求/响应拦截器
   - 支持自定义超时配置
   - 支持 HTTP/3 (QUIC)

2. **安全加固**
   - 添加代理循环检测
   - 支持证书固定（pinning）
   - 支持 mTLS 客户端认证

3. **可观测性**
   - 添加连接指标（建立时间、复用率）
   - 支持分布式追踪
   - 记录详细的连接诊断信息

4. **性能优化**
   - 实现连接池（ Rama 的 `HttpClientService` 可能已支持）
   - 支持 Happy Eyeballs（双栈连接优化）
   - 支持 DNS 缓存

5. **代码质量**
   - 当前文件较短（190 行），结构清晰
   - 可考虑添加更多单元测试
   - 文档注释较简略，可补充更多示例

6. **平台支持**
   - Unix socket 当前仅支持 macOS
   - 可考虑扩展到 Linux（需要 `rama_unix` 支持）
   - Windows 命名管道支持（如果需要）
