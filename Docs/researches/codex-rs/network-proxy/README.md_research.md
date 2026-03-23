# codex-rs/network-proxy/README.md 研究文档

## 场景与职责

`README.md` 是 `codex-network-proxy` crate 的用户文档和 API 参考手册。该 crate 是 Codex 项目的本地网络策略执行代理，提供：

- **HTTP 代理**（默认 `127.0.0.1:3128`）
- **SOCKS5 代理**（默认 `127.0.0.1:8081`，默认启用）

核心职责是强制执行网络访问的允许/拒绝策略，并提供"limited"只读模式用于限制网络访问。

## 功能点目的

### 1. 网络访问控制
- 基于域名的允许列表（allowlist）和拒绝列表（denylist）
- 支持通配符模式（`*.example.com`, `**.example.com`）
- 拒绝全局通配符 `*`（安全设计）

### 2. 模式控制
- **Full 模式**：允许所有 HTTP 方法，HTTPS CONNECT 隧道直通
- **Limited 模式**：仅允许 GET/HEAD/OPTIONS，阻止修改性操作

### 3. 本地网络保护
- 阻止对本地/私有 IP 的访问（防止 SSRF 攻击）
- DNS 重绑定防护（解析后检查 IP 类型）
- Unix socket 代理（macOS 专属，需显式授权）

### 4. MITM HTTPS 拦截
- 用于在 Limited 模式下检查 HTTPS 流量
- 自动生成和管理本地 CA 证书
- 可选的请求/响应体检查

## 具体技术实现

### 配置系统

配置通过 Codex 的 `config.toml` 管理，位于权限配置文件中：

```toml
[permissions.workspace.network]
enabled = true
proxy_url = "http://127.0.0.1:3128"
enable_socks5 = true
socks_url = "http://127.0.0.1:8081"
enable_socks5_udp = true
allow_upstream_proxy = true
dangerously_allow_non_loopback_proxy = false
mode = "full"  # 或 "limited"
mitm = false
allowed_domains = ["*.openai.com", "localhost", "127.0.0.1", "::1"]
denied_domains = ["evil.example"]
allow_local_binding = false
allow_unix_sockets = ["/tmp/example.sock"]
dangerously_allow_all_unix_sockets = false
```

### 核心组件架构

```
┌─────────────────────────────────────────────────────────────┐
│                    NetworkProxy (proxy.rs)                   │
│  ┌─────────────────┐  ┌─────────────────┐                    │
│  │  HTTP Proxy     │  │  SOCKS5 Proxy   │                    │
│  │  (http_proxy.rs)│  │  (socks5.rs)    │                    │
│  └────────┬────────┘  └────────┬────────┘                    │
│           │                    │                             │
│           └────────┬───────────┘                             │
│                    │                                         │
│           ┌────────▼────────┐                                │
│           │  Policy Engine  │                                │
│           │ (policy.rs)     │                                │
│           └────────┬────────┘                                │
│                    │                                         │
│           ┌────────▼────────┐                                │
│           │ NetworkProxyState│                               │
│           │ (state/runtime) │                                │
│           └─────────────────┘                                │
└─────────────────────────────────────────────────────────────┘
```

### 策略决策流程

```rust
// network_policy.rs: evaluate_host_policy
pub(crate) async fn evaluate_host_policy(
    state: &NetworkProxyState,
    decider: Option<&Arc<dyn NetworkPolicyDecider>>,
    request: &NetworkPolicyRequest,
) -> Result<NetworkDecision> {
    // 1. 检查基础策略（allowlist/denylist）
    let host_decision = state.host_blocked(&request.host, request.port).await?;
    
    match host_decision {
        HostBlockDecision::Allowed => Ok(NetworkDecision::Allow),
        HostBlockDecision::Blocked(HostBlockReason::NotAllowed) => {
            // 2. 如果未在 allowlist 中，咨询外部决策器
            if let Some(decider) = decider {
                decider.decide(request.clone()).await
            } else {
                Ok(NetworkDecision::deny_with_source(...))
            }
        }
        HostBlockDecision::Blocked(reason) => {
            // 3. 明确拒绝的域名
            Ok(NetworkDecision::deny_with_source(...))
        }
    }
}
```

### 主机阻断检查（host_blocked）

```rust
// runtime.rs: host_blocked 方法
pub async fn host_blocked(&self, host: &str, port: u16) -> Result<HostBlockDecision> {
    // 决策顺序：
    // 1. 明确 deny 列表始终优先
    if deny_set.is_match(host_str) {
        return Ok(HostBlockDecision::Blocked(HostBlockReason::Denied));
    }
    
    // 2. 本地/私有网络保护
    if !allow_local_binding {
        // 检查是否为本地 IP 字面量
        if is_loopback_host(&host) || is_non_public_ip(ip) {
            if !is_explicit_local_allowlisted(&allowed_domains, &host) {
                return Ok(HostBlockDecision::Blocked(HostBlockReason::NotAllowedLocal));
            }
        }
        // DNS 解析后检查（防止 DNS 重绑定）
        if host_resolves_to_non_public_ip(host_str, port).await {
            return Ok(HostBlockDecision::Blocked(HostBlockReason::NotAllowedLocal));
        }
    }
    
    // 3. allowlist 检查
    if allowed_domains_empty || !is_allowlisted {
        Ok(HostBlockDecision::Blocked(HostBlockReason::NotAllowed))
    } else {
        Ok(HostBlockDecision::Allowed)
    }
}
```

### MITM 实现

```rust
// mitm.rs: mitm_tunnel
pub(crate) async fn mitm_tunnel(upgraded: Upgraded) -> Result<()> {
    // 1. 获取 MITM 状态和目标信息
    let mitm = upgraded.extensions().get::<Arc<MitmState>>().cloned()?;
    let target = upgraded.extensions().get::<ProxyTarget>()?.0.clone();
    
    // 2. 为目标主机生成证书
    let acceptor_data = mitm.tls_acceptor_data_for_host(&target_host)?;
    
    // 3. 构建 HTTPS 服务
    let http_service = HttpServer::auto(executor).service(...);
    let https_service = TlsAcceptorLayer::new(acceptor_data).into_layer(http_service);
    
    // 4. 服务升级后的连接
    https_service.serve(upgraded).await
}
```

### CA 证书管理

```rust
// certs.rs: ManagedMitmCa
pub(super) struct ManagedMitmCa {
    issuer: Issuer<'static, KeyPair>,
}

impl ManagedMitmCa {
    pub(super) fn load_or_create() -> Result<Self> {
        // 1. 尝试加载现有 CA
        // 2. 如不存在则生成新 CA
        // 3. 存储在 $CODEX_HOME/proxy/ (ca.pem + ca.key)
        // 4. 密钥文件权限设置为 0o600
    }
    
    pub(super) fn tls_acceptor_data_for_host(&self, host: &str) -> Result<TlsAcceptorData> {
        // 为特定主机签发叶子证书
    }
}
```

### 审计事件系统

```rust
// network_policy.rs: 审计事件常量
const AUDIT_TARGET: &str = "codex_otel.network_proxy";
const POLICY_DECISION_EVENT_NAME: &str = "codex.network_proxy.policy_decision";

// 事件字段：
// - event.name, event.timestamp
// - conversation.id, app.version, user.account_id
// - network.policy.scope (domain/non_domain)
// - network.policy.decision (allow/deny/ask)
// - network.policy.source (baseline_policy/mode_guard/proxy_state/decider)
// - network.policy.reason
// - network.transport.protocol
// - server.address, server.port
// - http.request.method
// - client.address
// - network.policy.override
```

## 关键代码路径与文件引用

### 入口与 API

| 文件 | 职责 | 关键导出 |
|------|------|----------|
| `src/lib.rs` | Crate 入口 | `NetworkProxy`, `NetworkPolicyDecider`, `NetworkDecision` |
| `src/proxy.rs` | 主代理逻辑 | `NetworkProxy`, `NetworkProxyBuilder`, `NetworkProxyHandle` |

### 代理实现

| 文件 | 职责 | 关键函数/结构 |
|------|------|--------------|
| `src/http_proxy.rs` | HTTP/HTTPS 代理 | `run_http_proxy`, `http_connect_accept`, `http_plain_proxy` |
| `src/socks5.rs` | SOCKS5 代理 | `run_socks5`, `handle_socks5_tcp`, `inspect_socks5_udp` |
| `src/mitm.rs` | MITM 拦截 | `mitm_tunnel`, `handle_mitm_request` |

### 策略与配置

| 文件 | 职责 | 关键函数/结构 |
|------|------|--------------|
| `src/config.rs` | 配置结构 | `NetworkProxyConfig`, `NetworkProxySettings`, `NetworkMode` |
| `src/policy.rs` | 域名匹配 | `compile_globset`, `normalize_host`, `DomainPattern` |
| `src/network_policy.rs` | 策略决策 | `NetworkPolicyDecider`, `evaluate_host_policy` |
| `src/state.rs` | 状态约束 | `NetworkProxyConstraints`, `validate_policy_against_constraints` |
| `src/runtime.rs` | 运行时状态 | `NetworkProxyState`, `host_blocked`, `ConfigReloader` |

### 支持模块

| 文件 | 职责 | 关键函数/结构 |
|------|------|--------------|
| `src/certs.rs` | CA 证书管理 | `ManagedMitmCa`, `load_or_create_ca` |
| `src/upstream.rs` | 上游连接 | `UpstreamClient`, `proxy_for_connect` |
| `src/responses.rs` | 响应构造 | `blocked_text_response`, `json_response` |
| `src/reasons.rs` | 阻断原因常量 | `REASON_DENIED`, `REASON_NOT_ALLOWED` 等 |

## 依赖与外部交互

### 外部依赖

**Rama 框架**（核心代理功能）：
- `rama-core`：Service/Layer 抽象
- `rama-http`：HTTP 协议处理
- `rama-socks5`：SOCKS5 协议实现
- `rama-tls-rustls`：TLS 加密

**Tokio 生态**：
- `tokio`：异步运行时
- `tokio::sync::RwLock`：并发状态管理

**其他关键依赖**：
- `globset`：高效的 glob 模式匹配
- `serde`：配置和响应序列化
- `chrono`：审计日志时间戳

### 内部依赖

- `codex-utils-home-dir`：解析 `$CODEX_HOME`
- `codex-utils-absolute-path`：安全的路径处理
- `codex-utils-rustls-provider`：初始化 rustls 加密提供器

### 环境交互

**文件系统**：
- `$CODEX_HOME/proxy/ca.pem` - CA 证书
- `$CODEX_HOME/proxy/ca.key` - CA 私钥（权限 0o600）

**网络**：
- 绑定地址：可配置，默认 127.0.0.1:3128 (HTTP) 和 127.0.0.1:8081 (SOCKS5)
- 上游代理：读取 `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY` 环境变量

**环境变量**：
- `CODEX_NETWORK_ALLOW_LOCAL_BINDING` - 子进程是否允许本地绑定
- 标准代理环境变量（由代理自动设置）

## 风险、边界与改进建议

### 安全风险

#### 1. DNS 重绑定攻击 ⚠️

**现状**：已实现 DNS 解析后 IP 检查（`host_resolves_to_non_public_ip`）

**局限**：
- 2 秒超时可能绕过检查
- 无法防止后续的 DNS TTL 刷新攻击
- 多 IP 主机可能部分绕过检查

**建议**：
- 考虑实现 DNS 结果缓存和固定
- 在 TLS 层再次验证目标 IP

#### 2. MITM CA 安全

**现状**：
- CA 密钥存储在 `$CODEX_HOME/proxy/ca.key`
- 权限检查 0o600
- 拒绝符号链接

**风险**：
- 用户家目录权限不当可能导致密钥泄露
- 无密码保护的私钥

**建议**：
- 考虑使用系统密钥链（macOS Keychain, Linux Secret Service）
- 添加 CA 证书过期和轮换机制

#### 3. 平台支持不一致

**现状**：Unix socket 代理仅限 macOS

**风险**：
- Linux 用户无法使用 Docker socket 代理等功能
- 代码中大量 `#[cfg(target_os = "macos")]` 降低可维护性

**建议**：
- 评估扩展到 Linux 的技术可行性
- 或明确文档化平台限制

### 功能边界

#### 1. Limited 模式限制

**CONNECT 隧道**：
- 无 MITM 时，Limited 模式完全阻止 HTTPS CONNECT
- 这可能导致部分应用无法工作

**SOCKS5**：
- Limited 模式下完全阻止 SOCKS5（包括 TCP 和 UDP）

#### 2. 上游代理支持

**限制**：
- 仅支持 HTTP/HTTPS 上游代理
- SOCKS5 上游代理不支持（`proxy_for_connect` 仅检查 HTTP 代理变量）

### 性能考虑

#### 1. DNS 查询

**现状**：每个非 IP 主机名都触发 DNS 查询（2 秒超时）

**影响**：
- 首次请求延迟增加
- 大量并发请求时 DNS 压力

**建议**：
- 实现 DNS 结果缓存
- 使用异步 DNS 解析器（如 trust-dns）

#### 2. 策略检查

**现状**：每次请求都重新加载配置（`reload_if_needed`）

**优化**：
- 配置已使用乐观锁优化
- 但仍有 RwLock 读开销

### 改进建议

#### 短期

1. **文档完善**：
   - 添加架构图
   - 详细说明策略决策顺序
   - 提供故障排查指南

2. **测试增强**：
   - 添加 DNS 重绑定攻击的集成测试
   - 测试 CA 证书轮换场景

#### 中期

1. **功能扩展**：
   - 支持 SOCKS5 上游代理
   - 实现 DNS 结果缓存
   - 添加请求速率限制

2. **跨平台支持**：
   - 评估 Linux Unix socket 支持
   - 统一平台抽象层

#### 长期

1. **安全增强**：
   - 集成系统密钥链
   - 实现证书固定（Certificate Pinning）
   - 添加流量分析防护

2. **可观测性**：
   - 添加 Prometheus 指标导出
   - 实现分布式追踪支持
   - 增强审计日志结构化

---

**文档生成时间**：2026-03-23  
**对应代码版本**：基于仓库当前 HEAD 分析
