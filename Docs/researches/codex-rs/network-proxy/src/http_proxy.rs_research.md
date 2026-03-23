# http_proxy.rs 深度研究文档

## 场景与职责

`http_proxy.rs` 是 Codex 网络代理模块的 **HTTP/HTTPS 代理服务器核心实现**，基于 Rama 框架构建，提供：

1. **HTTP 正向代理**：处理普通 HTTP 请求的转发
2. **HTTPS CONNECT 隧道**：处理 HTTPS 代理的 CONNECT 方法
3. **MITM 拦截**：在 Limited 模式下终止 TLS 并检查内部请求
4. **Unix Socket 代理**：通过 `x-unix-socket` 头访问本地服务
5. **访问控制**：集成网络策略（allowlist/denylist/mode）

### 核心使用场景

1. **普通 HTTP 代理**：客户端通过代理访问 HTTP 资源
2. **HTTPS 隧道**：客户端使用 CONNECT 方法建立端到端加密隧道
3. **受限模式审计**：Limited 模式下拦截 HTTPS 并检查 HTTP 方法
4. **本地服务访问**：通过 Unix Socket 访问 Docker、数据库等本地服务

---

## 功能点目的

### 1. HTTP 代理服务入口

```rust
pub async fn run_http_proxy(
    state: Arc<NetworkProxyState>,
    addr: SocketAddr,
    policy_decider: Option<Arc<dyn NetworkPolicyDecider>>,
) -> Result<()>
```

**设计目的**：
- 启动 HTTP 代理监听服务
- 支持策略决策器注入（用于动态策略覆盖）
- 使用 Rama 的 HTTP/1 服务器（避免版本嗅探延迟）

### 2. CONNECT 处理流程

```rust
async fn http_connect_accept(...) -> Result<(Response, Request), Response>
async fn http_connect_proxy(upgraded: Upgraded) -> Result<(), Infallible>
```

**两阶段设计**：
1. **Accept 阶段**：验证策略、检查 MITM 需求、准备上下文
2. **Proxy 阶段**：建立隧道或启动 MITM 拦截

### 3. 普通 HTTP 代理

```rust
async fn http_plain_proxy(
    policy_decider: Option<Arc<dyn NetworkPolicyDecider>>,
    mut req: Request,
) -> Result<Response, Infallible>
```

**功能**：
- 处理非 CONNECT 请求
- 支持 Unix Socket 代理（`x-unix-socket` 头）
- 方法限制检查（Limited 模式）
- Host 头验证（防止请求走私）

### 4. 策略集成点

| 检查点 | 触发条件 | 响应 |
|--------|----------|------|
| 代理启用检查 | `!enabled` | 503 Service Unavailable |
| 主机策略检查 | `host_blocked()` | 403 Forbidden + 详细原因 |
| 方法限制检查 | `!method_allowed` | 403 Forbidden + `blocked-by-method-policy` |
| MITM 需求检查 | `Limited && !mitm` | 403 Forbidden + `blocked-by-mitm-required` |

---

## 具体技术实现

### 1. 服务架构

```rust
let http_service = HttpServer::http1().service(
    (
        UpgradeLayer::new(
            MethodMatcher::CONNECT,
            service_fn(http_connect_accept),
            service_fn(http_connect_proxy),
        ),
        RemoveResponseHeaderLayer::hop_by_hop(),
    )
        .into_layer(service_fn(http_plain_proxy)),
);
```

**Rama Layer 栈**：
1. `UpgradeLayer`: 处理 CONNECT 方法升级
2. `RemoveResponseHeaderLayer::hop_by_hop()`: 自动移除 Hop-by-Hop 头
3. `AddInputExtensionLayer`: 注入 `NetworkProxyState`

### 2. CONNECT 隧道建立

```rust
async fn forward_connect_tunnel(upgraded: Upgraded, proxy: Option<ProxyAddress>) -> Result<(), BoxError>
```

**流程**：
1. 从扩展中提取 `ProxyTarget`（目标地址）
2. 构建 `TcpRequest` 带 HTTPS 协议标记
3. 创建 `HttpProxyConnector`（支持上游代理）
4. 添加 `TlsConnectorLayer` 进行 TLS 握手
5. 使用 `StreamForwardService` 双向转发数据

### 3. MITM 拦截流程

```rust
// 在 http_connect_accept 中
if mode == NetworkMode::Limited && mitm_state.is_some() {
    req.extensions_mut().insert(mitm_state);
    // 返回 200 OK，进入 http_connect_proxy
}

// 在 http_connect_proxy 中
if mode == NetworkMode::Limited && has_mitm_state {
    mitm::mitm_tunnel(upgraded).await?;
}
```

**MITM 启动条件**：
- 模式为 `Limited`
- MITM 状态已配置（`mitm: true` 且 CA 证书有效）

### 4. Unix Socket 代理

```rust
async fn proxy_via_unix_socket(req: Request, socket_path: &str) -> Result<Response>
```

**macOS 专属实现**：
```rust
#[cfg(target_os = "macos")]
{
    let client = UpstreamClient::unix_socket(socket_path);
    // 重写 URI 为路径部分
    // 移除 x-unix-socket 头
    // 转发请求
}
```

**安全控制**：
- 仅 macOS 支持（`unix_socket_permissions_supported()`）
- 路径必须在 `allow_unix_sockets` 白名单中
- 仅接受绝对路径

### 5. Host 头验证

```rust
fn validate_absolute_form_host_header(req: &Request, request_ctx: &RequestContext) -> Result<(), &'static str>
```

**验证逻辑**：
1. 如果 URI 没有 scheme（非绝对形式）：跳过验证
2. 提取 Host 头
3. 比较 Host 头的主机部分与请求目标的主机
4. 比较端口（考虑默认端口）

**目的**：防止 HTTP 请求走私攻击（Request Smuggling）

### 6. Hop-by-Hop 头处理

```rust
fn remove_hop_by_hop_request_headers(headers: &mut HeaderMap)
```

**移除的头**：
- `Connection` 及其列出的所有头
- `Keep-Alive`
- `Proxy-Connection`
- `Proxy-Authorization`
- `Trailer`
- `Transfer-Encoding`
- `Upgrade`
- `TE`（通过字节 `[0x74, 0x65]` 匹配）

---

## 关键代码路径与文件引用

### 核心调用链

```
run_http_proxy()
├── TcpListener::bind(addr)
└── run_http_proxy_with_listener()
    └── listener.serve(http_service)
        ├── http_connect_accept() [CONNECT 请求]
        │   ├── 提取 authority
        │   ├── 检查 enabled
        │   ├── evaluate_host_policy() [network_policy.rs]
        │   ├── 检查 mode + mitm
        │   └── 返回 200 OK 或 403
        └── http_connect_proxy() [升级后的连接]
            ├── 检查 mode + mitm
            ├── mitm::mitm_tunnel() [MITM 路径]
            └── forward_connect_tunnel() [普通隧道路径]
                ├── HttpProxyConnector
                ├── TlsConnectorLayer
                └── StreamForwardService

http_plain_proxy() [非 CONNECT 请求]
├── 检查 x-unix-socket 头
│   └── proxy_via_unix_socket() [macOS]
├── 提取 authority
├── 检查 enabled
├── validate_absolute_form_host_header()
├── evaluate_host_policy()
├── 检查 method_allowed
└── UpstreamClient::serve() [转发]
```

### 依赖关系

| 依赖 | 用途 |
|------|------|
| `rama_core` | 服务框架核心 |
| `rama_http` | HTTP 类型和工具 |
| `rama_http_backend` | HTTP 服务器和客户端 |
| `rama_tcp` | TCP 连接 |
| `rama_tls_rustls` | TLS 处理 |
| `mitm.rs` | MITM 拦截实现 |
| `network_policy.rs` | 策略评估 |
| `upstream.rs` | 上游客户端 |

### 被调用方

- `proxy.rs`: 启动代理服务
- `mitm.rs`: MITM 隧道处理

---

## 依赖与外部交互

### HTTP 协议支持

| 功能 | 支持状态 | 说明 |
|------|----------|------|
| HTTP/1.0 | ✓ | 基础支持 |
| HTTP/1.1 | ✓ | 完整支持（Keep-Alive, Chunked） |
| HTTP/2 | ✗ | 代理层不支持（CONNECT 隧道内可支持） |
| CONNECT | ✓ | HTTPS 隧道 |
| WebSocket | ✓ | 通过 CONNECT 隧道 |

### 请求头处理

**特殊头**：
- `x-unix-socket`: 触发 Unix Socket 代理（仅 macOS）
- `Host`: 验证和转发
- `Connection`: 解析并移除相关头

### 响应头

**添加的头**：
- `x-proxy-error`: 阻塞原因标识（如 `blocked-by-allowlist`）

**状态码映射**：
| 场景 | 状态码 |
|------|--------|
| 代理禁用 | 503 Service Unavailable |
| 主机被拒绝 | 403 Forbidden |
| 方法不允许 | 403 Forbidden |
| 需要 MITM | 403 Forbidden |
| 内部错误 | 500 Internal Server Error |
| 上游失败 | 502 Bad Gateway |

---

## 风险、边界与改进建议

### 安全风险

1. **HTTP 请求走私**
   - 通过 `validate_absolute_form_host_header` 缓解
   - 但仍需关注 Rama 框架的解析一致性

2. **CONNECT 隧道滥用**
   - 攻击者可能使用 CONNECT 连接到内部服务
   - **缓解**：`host_blocked()` 在 CONNECT 时检查目标

3. **Unix Socket 路径遍历**
   - 如果允许相对路径，可能导致路径遍历
   - **缓解**：仅允许绝对路径，使用 `AbsolutePathBuf` 规范化

4. **MITM 证书信任**
   - 用户必须手动信任生成的 CA 证书
   - 如果 CA 私钥泄露，攻击者可签发任意证书

### 边界条件

| 场景 | 行为 |
|------|------|
| 缺少 Host 头 | 400 Bad Request |
| Host 头不匹配 | 400 Bad Request |
| CONNECT 无 authority | 400 Bad Request |
| 代理禁用 | 503 Service Unavailable |
| 策略评估失败 | 500 Internal Server Error |
| 上游连接失败 | 502 Bad Gateway |
| Unix Socket 不存在 | 502 Bad Gateway |

### 性能考虑

1. **DNS 解析**
   - `host_blocked()` 可能触发 DNS 查询（2秒超时）
   - 建议添加 DNS 缓存

2. **连接池**
   - 当前 `UpstreamClient` 未显示使用连接池
   - 高并发场景可能性能受限

### 改进建议

1. **HTTP/2 支持**
   ```rust
   // 当前使用 HttpServer::http1()
   // 建议支持自动协商
   let http_service = HttpServer::auto(executor).service(...);
   ```

2. **连接池优化**
   ```rust
   // 添加连接池配置
   pub struct UpstreamClientConfig {
       pool_size: usize,
       idle_timeout: Duration,
       // ...
   }
   ```

3. **请求体大小限制**
   - 当前无请求体大小限制
   - 建议添加可配置限制防止内存耗尽

4. **更详细的审计日志**
   ```rust
   // 记录完整的请求/响应信息（可选，用于调试）
   info!(
       http.request.method = %method,
       http.request.uri = %uri,
       http.response.status = %status,
       // ...
   );
   ```

5. **WebSocket 升级支持**
   - 当前 WebSocket 通过 CONNECT 隧道支持
   - 可考虑直接支持 `Upgrade: websocket`

6. **测试覆盖扩展**
   - 添加压力测试（并发 CONNECT）
   - 添加模糊测试（畸形 HTTP 请求）
   - 添加 MITM 完整流程测试
