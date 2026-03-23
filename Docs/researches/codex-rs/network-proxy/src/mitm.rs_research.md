# mitm.rs 深度研究文档

## 场景与职责

`mitm.rs` 是 Codex 网络代理模块的 **MITM (Man-In-The-Middle) 拦截核心实现**，负责：

1. **TLS 终止**：使用动态生成的证书终止客户端 TLS 连接
2. **HTTPS 流量检查**：解密并检查内部 HTTP 请求内容
3. **策略强制执行**：在 Limited 模式下验证 HTTP 方法
4. **请求转发**：将检查后的请求转发到真实上游服务器

### 核心使用场景

1. **Limited 模式 HTTPS 审计**：在只读模式下，必须解密 HTTPS 才能检查 HTTP 方法
2. **请求体检查**（可选）：记录请求/响应体大小用于调试
3. **DNS 重绑定防护**：在 TLS 终止后重新验证目标地址

---

## 功能点目的

### 1. MitmState - MITM 状态管理

```rust
pub struct MitmState {
    ca: ManagedMitmCa,           // CA 证书管理器
    upstream: UpstreamClient,    // 上游 HTTP 客户端
    inspect: bool,               // 是否检查请求体
    max_body_bytes: usize,       // 最大检查体大小
}
```

**设计目的**：
- 封装 MITM 所需的所有资源
- 提供线程安全的共享状态（通过 `Arc<MitmState>`）
- 控制请求体检查行为（当前默认关闭）

### 2. mitm_tunnel - MITM 隧道主入口

```rust
pub(crate) async fn mitm_tunnel(upgraded: Upgraded) -> Result<()>
```

**流程**：
1. 从升级后的连接中提取 `MitmState`、`NetworkProxyState`、`ProxyTarget`
2. 为目标主机生成 TLS 证书
3. 构建 HTTPS 服务（带 TLS 终止层）
4. 服务内部 HTTP 请求

### 3. 请求处理流程

```rust
async fn handle_mitm_request(req: Request, request_ctx: Arc<MitmRequestContext>) 
    -> Result<Response, Infallible>
```

**处理步骤**：
1. 策略检查（`mitm_blocking_response`）
2. 请求转发到上游
3. 响应返回客户端

### 4. 策略检查点

```rust
async fn mitm_blocking_response(req: &Request, policy: &MitmPolicyContext) 
    -> Result<Option<Response>>
```

**检查项**：
- 拒绝嵌套 CONNECT（不支持 CONNECT  inside MITM）
- Host 头匹配验证（防止请求走私）
- 本地/私有地址重新检查（DNS 重绑定防护）
- HTTP 方法限制（Limited 模式）

---

## 具体技术实现

### 1. TLS 终止层构建

```rust
let https_service = TlsAcceptorLayer::new(acceptor_data)
    .with_store_client_hello(true)
    .into_layer(http_service);
```

**Rama Layer 栈**：
1. `RemoveResponseHeaderLayer::hop_by_hop()`: 移除 Hop-by-Hop 响应头
2. `RemoveRequestHeaderLayer::hop_by_hop()`: 移除 Hop-by-Hop 请求头
3. `TlsAcceptorLayer`: TLS 终止，使用动态生成的证书

**证书生成**：
```rust
let acceptor_data = mitm.tls_acceptor_data_for_host(&target_host)?;
// 内部调用 certs.rs::ManagedMitmCa::tls_acceptor_data_for_host()
```

### 2. 请求重写

```rust
async fn forward_request(req: Request, request_ctx: &MitmRequestContext) -> Result<Response>
```

**重写逻辑**：
1. 提取原始请求的方法、路径
2. 构建新的 HTTPS URI：`https://{authority}{path}`
3. 设置 Host 头为上游服务器地址
4. 可选：包装请求体进行大小检查

```rust
let authority = authority_header_value(&target_host, target_port);
parts.uri = build_https_uri(&authority, &path)?;
parts.headers.insert(HOST, HeaderValue::from_str(&authority)?);
```

### 3. 请求体检查（可选）

```rust
const MITM_INSPECT_BODIES: bool = false;
const MITM_MAX_BODY_BYTES: usize = 4096;
```

**实现机制**：
```rust
fn inspect_body<T: BodyLoggable>(body: Body, max_body_bytes: usize, ctx: T) -> Body {
    Body::from_stream(InspectStream {
        inner: Box::pin(body.into_data_stream()),
        ctx: Some(Box::new(ctx)),
        len: 0,
        max_body_bytes,
    })
}
```

**日志输出**：
```
MITM inspected request body (host=example.com, method=POST, path=/api, body_len=1234, truncated=false)
MITM inspected response body (host=example.com, method=POST, path=/api, status=200, body_len=5678, truncated=true)
```

### 4. DNS 重绑定防护

```rust
// CONNECT 时已经检查过一次，但 DNS 可能在此期间变化
if matches!(
    policy.app_state.host_blocked(&policy.target_host, policy.target_port).await?,
    HostBlockDecision::Blocked(HostBlockReason::NotAllowedLocal)
) {
    // 阻止请求
}
```

**防护逻辑**：
- CONNECT 阶段检查目标主机是否允许
- MITM 内部请求阶段**再次检查**
- 如果目标解析到本地/私有地址且未明确允许，则阻止

### 5. Host 头验证

```rust
if let Some(request_host) = extract_request_host(req) {
    let normalized = normalize_host(&request_host);
    if !normalized.is_empty() && normalized != policy.target_host {
        warn!("MITM host mismatch (target={}, request_host={normalized})", policy.target_host);
        return Ok(Some(text_response(StatusCode::BAD_REQUEST, "host mismatch")));
    }
}
```

**目的**：防止客户端在 CONNECT 后发送针对不同主机的请求

---

## 关键代码路径与文件引用

### 核心调用链

```
http_proxy.rs::http_connect_proxy()
└── mitm::mitm_tunnel(upgraded)
    ├── 提取 MitmState, NetworkProxyState, ProxyTarget
    ├── mitm.tls_acceptor_data_for_host(&target_host)
    │   └── certs.rs::ManagedMitmCa::tls_acceptor_data_for_host()
    │       └── issue_host_certificate_pem()
    ├── 构建 MitmRequestContext
    ├── HttpServer::auto().service(...)
    │   └── handle_mitm_request()
    │       ├── mitm_blocking_response()
    │       │   ├── 拒绝嵌套 CONNECT
    │       │   ├── Host 头匹配检查
    │       │   ├── host_blocked() [DNS 重绑定检查]
    │       │   └── mode.allows_method() [方法限制]
    │       └── forward_request()
    │           ├── 重写 URI 为 HTTPS
    │           ├── 设置 Host 头
    │           ├── inspect_body() [可选]
    │           ├── upstream.serve() [转发]
    │           └── respond_with_inspection() [可选]
    └── https_service.serve(upgraded)
```

### 依赖关系

| 依赖 | 用途 |
|------|------|
| `certs.rs` | CA 证书和主机证书生成 |
| `upstream.rs` | 转发请求到真实服务器 |
| `responses.rs` | 构建错误响应 |
| `runtime.rs` | `NetworkProxyState`, `HostBlockDecision` |
| `policy.rs` | `normalize_host` |
| `rama_tls_rustls` | TLS 终止层 |

### 被调用方

- `http_proxy.rs`: `http_connect_proxy()` 在 Limited + MITM 模式下调用

---

## 依赖与外部交互

### TLS 配置

| 参数 | 值 | 说明 |
|------|-----|------|
| 证书算法 | ECDSA P-256 SHA256 | 现代、高效 |
| TLS 版本 | ALL_VERSIONS | 支持 TLS 1.0-1.3 |
| ALPN | h2, http/1.1 | 支持 HTTP/2 和 HTTP/1.1 |

### HTTP 协议支持

| 功能 | 支持状态 | 说明 |
|------|----------|------|
| HTTP/1.0 | ✓ | 基础支持 |
| HTTP/1.1 | ✓ | 完整支持 |
| HTTP/2 | ✓ | 通过 ALPN 协商 |
| WebSocket | ✗ | 当前不支持 |
| CONNECT | ✗ | 明确拒绝（嵌套 CONNECT） |

### 上下文扩展（Extensions）

MITM 隧道依赖以下 Rama 扩展：
- `Arc<MitmState>`: MITM 配置和证书
- `Arc<NetworkProxyState>`: 代理状态和策略
- `ProxyTarget`: 原始 CONNECT 目标
- `NetworkMode`: 当前网络模式
- `Executor`: 异步执行器

---

## 风险、边界与改进建议

### 安全风险

1. **证书信任问题**
   - 用户必须手动信任生成的 CA 证书
   - 如果 CA 私钥泄露，攻击者可签发任意域名证书
   - **缓解**：私钥权限 0o600，符号链接检测

2. **DNS 重绑定攻击**
   - 攻击者可能利用 DNS TTL 在 CONNECT 和 MITM 请求间切换 IP
   - **缓解**：在 MITM 阶段重新检查 `host_blocked()`

3. **请求走私风险**
   - Host 头验证可防止部分攻击，但 HTTP/2 转换可能引入风险
   - **缓解**：使用 Rama 的自动 HTTP 版本适配

4. **信息泄露**
   - 请求体检查功能（即使关闭）可能被恶意开启
   - **缓解**：使用编译时常量 `MITM_INSPECT_BODIES`，非运行时配置

### 边界条件

| 场景 | 行为 |
|------|------|
| 嵌套 CONNECT | 405 Method Not Allowed |
| Host 头不匹配 | 400 Bad Request |
| DNS 重绑定到本地地址 | 403 Forbidden |
| 方法不允许（Limited） | 403 Forbidden |
| 证书生成失败 | 500 Internal Server Error |
| 上游连接失败 | 502 Bad Gateway |

### 性能考虑

1. **证书生成开销**
   - 每个新主机首次访问需要生成证书（~10-50ms）
   - 建议：缓存生成的证书

2. **请求体检查开销**
   - 流式检查引入额外的数据拷贝
   - 当前默认关闭，影响可控

3. **内存使用**
   - `InspectStream` 持有请求上下文
   - 大请求体可能导致内存压力

### 改进建议

1. **证书缓存**
   ```rust
   // 添加 LRU 缓存
   struct CertCache {
       cache: LruCache<String, TlsAcceptorData>,
   }
   ```

2. **WebSocket 支持**
   ```rust
   // 检测 Upgrade: websocket 头
   if is_websocket_upgrade(&req) {
       // 建立 WebSocket 隧道
   }
   ```

3. **可配置的请求体检查**
   ```rust
   // 从配置而非编译时常量
   pub struct MitmConfig {
       inspect_bodies: bool,
       max_body_bytes: usize,
       inspect_content_types: Vec<String>,
   }
   ```

4. **证书透明度**
   - 考虑将签发的证书记录到本地日志，便于审计

5. **SNI 验证**
   ```rust
   // 验证 ClientHello 中的 SNI 与目标匹配
   .with_store_client_hello(true)  // 已启用
   // 添加验证逻辑
   ```

6. **错误处理细化**
   - 区分证书错误、连接错误、策略错误
   - 提供更详细的错误信息（内部使用）

7. **测试覆盖扩展**
   - 添加完整 HTTPS 握手测试
   - 添加并发 MITM 连接测试
   - 添加大请求体处理测试
