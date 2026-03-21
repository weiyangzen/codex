# codex-rs/network-proxy 深度研究文档

## 目录
- [场景与职责](#场景与职责)
- [功能点目的](#功能点目的)
- [具体技术实现](#具体技术实现)
- [关键代码路径与文件引用](#关键代码路径与文件引用)
- [依赖与外部交互](#依赖与外部交互)
- [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

`codex-network-proxy` 是 Codex 的本地网络策略执行代理，作为网络沙箱的核心组件，负责：

1. **网络流量代理**：同时运行 HTTP 代理（默认 127.0.0.1:3128）和 SOCKS5 代理（默认 127.0.0.1:8081）
2. **策略强制执行**：基于允许/拒绝列表（allowlist/denylist）和模式（full/limited）控制网络访问
3. **安全防护**：防止本地/私有网络未授权访问、DNS 重绑定攻击、SSRF 攻击
4. **MITM 支持**：在 limited 模式下通过 TLS 终止实现 HTTPS 流量内容检查
5. **Unix Socket 代理**：macOS 平台支持通过 HTTP 代理访问本地 Unix Socket

### 核心使用场景

| 场景 | 说明 |
|------|------|
| 沙箱网络隔离 | 子进程通过代理访问网络，主进程控制策略 |
| 只读网络模式 | Limited 模式仅允许 GET/HEAD/OPTIONS 方法 |
| 本地服务访问 | 通过 x-unix-socket header 访问 Docker 等本地服务 |
| 策略动态更新 | 运行时添加允许/拒绝域名，无需重启代理 |

---

## 功能点目的

### 1. 双协议代理服务

- **HTTP 代理**：处理 HTTP/HTTPS 请求，支持 CONNECT 隧道
- **SOCKS5 代理**：处理 TCP/UDP 流量，支持 UDP 关联（需显式启用）

### 2. 网络模式控制

| 模式 | 描述 |
|------|------|
| `full` | 允许所有 HTTP 方法，HTTPS CONNECT 直接隧道 |
| `limited` | 仅允许 GET/HEAD/OPTIONS，HTTPS 需 MITM 才能检查内容 |

### 3. 域名策略系统

- **允许列表（allowed_domains）**：精确匹配或通配符（`*.example.com`, `**.example.com`）
- **拒绝列表（denied_domains）**：优先级高于允许列表
- **本地绑定控制**：`allow_local_binding` 控制是否允许访问本地/私有 IP

### 4. MITM（中间人）功能

- 自动生成 CA 证书和 per-host 叶子证书
- 在 limited 模式下终止 HTTPS 以检查请求方法
- 证书存储于 `$CODEX_HOME/proxy/`（ca.pem + ca.key）

### 5. Unix Socket 代理（macOS 限定）

- 通过 `x-unix-socket: /path/to/socket` header 路由请求
- 支持显式白名单或 `dangerously_allow_all_unix_sockets` 模式

---

## 具体技术实现

### 3.1 核心数据结构

```rust
// 配置结构（config.rs）
pub struct NetworkProxyConfig {
    pub network: NetworkProxySettings,
}

pub struct NetworkProxySettings {
    pub enabled: bool,                           // 总开关
    pub mode: NetworkMode,                       // full/limited
    pub allowed_domains: Vec<String>,           // 允许域名列表
    pub denied_domains: Vec<String>,            // 拒绝域名列表
    pub allow_local_binding: bool,              // 允许本地/私有 IP
    pub allow_unix_sockets: Vec<String>,        // 允许的 Unix Socket 路径
    pub mitm: bool,                             // 启用 MITM
    pub allow_upstream_proxy: bool,             // 尊重上游代理环境变量
    pub dangerously_allow_non_loopback_proxy: bool,  // 允许非回环绑定
    pub dangerously_allow_all_unix_sockets: bool,    // 允许所有 Unix Socket
}

// 运行时状态（runtime.rs）
pub struct NetworkProxyState {
    state: Arc<RwLock<ConfigState>>,
    reloader: Arc<dyn ConfigReloader>,
    blocked_request_observer: Arc<RwLock<Option<Arc<dyn BlockedRequestObserver>>>>,
    audit_metadata: NetworkProxyAuditMetadata,
}

pub struct ConfigState {
    pub config: NetworkProxyConfig,
    pub allow_set: GlobSet,          // 编译后的允许规则
    pub deny_set: GlobSet,           // 编译后的拒绝规则
    pub mitm: Option<Arc<MitmState>>,
    pub constraints: NetworkProxyConstraints,
    pub blocked: VecDeque<BlockedRequest>,  // 阻塞请求历史
    pub blocked_total: u64,
}
```

### 3.2 策略决策流程

```
请求到达
    ↓
检查 enabled → 否 → 返回 proxy_disabled
    ↓
检查 mode guard → limited 模式拒绝非安全方法
    ↓
检查 deny_set → 匹配 → 返回 denied
    ↓
检查 allow_local_binding → 否 → 检查本地/私有 IP
    ↓
检查 allow_set → 不匹配 → 调用 policy_decider（如有）
    ↓
返回 Allow / Deny / Ask
```

关键代码（network_policy.rs:289-359）：

```rust
pub(crate) async fn evaluate_host_policy(
    state: &NetworkProxyState,
    decider: Option<&Arc<dyn NetworkPolicyDecider>>,
    request: &NetworkPolicyRequest,
) -> Result<NetworkDecision> {
    let host_decision = state.host_blocked(&request.host, request.port).await?;
    let (decision, policy_override) = match host_decision {
        HostBlockDecision::Allowed => (NetworkDecision::Allow, false),
        HostBlockDecision::Blocked(HostBlockReason::NotAllowed) => {
            // 尝试通过 policy_decider 覆盖
            if let Some(decider) = decider {
                let decider_decision = map_decider_decision(decider.decide(request.clone()).await);
                let policy_override = matches!(decider_decision, NetworkDecision::Allow);
                (decider_decision, policy_override)
            } else {
                (NetworkDecision::deny_with_source(...), false)
            }
        }
        HostBlockDecision::Blocked(reason) => (...)
    };
    // 发送审计事件
    emit_policy_audit_event(state, ...);
    Ok(decision)
}
```

### 3.3 HTTP 代理实现

基于 Rama 框架的 HTTP/1 服务（http_proxy.rs）：

```rust
async fn run_http_proxy_with_listener(...) -> Result<()> {
    let http_service = HttpServer::http1().service(
        (
            UpgradeLayer::new(  // 处理 CONNECT 方法
                MethodMatcher::CONNECT,
                service_fn(http_connect_accept),   // 接受/拒绝 CONNECT
                service_fn(http_connect_proxy),    // 建立隧道
            ),
            RemoveResponseHeaderLayer::hop_by_hop(),
        )
            .into_layer(service_fn(http_plain_proxy)),  // 普通 HTTP 代理
    );
    listener.serve(AddInputExtensionLayer::new(state).into_layer(http_service)).await;
}
```

**CONNECT 处理流程**：
1. `http_connect_accept`：验证策略、检查 MITM 需求
2. `http_connect_proxy`：建立隧道或启动 MITM
3. `forward_connect_tunnel`：使用 TcpConnector + TlsConnectorLayer 转发

**普通 HTTP 处理**：
1. 检查 `x-unix-socket` header → 路由到 Unix Socket
2. 验证 Host 策略
3. 检查方法限制
4. 转发到上游（直接或通过上游代理）

### 3.4 SOCKS5 代理实现

基于 `rama-socks5`（socks5.rs）：

```rust
async fn run_socks5_with_listener(...) -> Result<()> {
    let tcp_connector = TcpConnector::default();
    let policy_tcp_connector = service_fn(move |req: TcpRequest| {
        handle_socks5_tcp(req, tcp_connector, policy_decider)
    });
    
    let socks_connector = DefaultConnector::default().with_connector(policy_tcp_connector);
    let base = Socks5Acceptor::new().with_connector(socks_connector);
    
    if enable_socks5_udp {
        let udp_relay = DefaultUdpRelay::default().with_async_inspector(...);
        let socks_acceptor = base.with_udp_associator(udp_relay);
        listener.serve(...).await;
    }
}
```

### 3.5 MITM 实现

证书管理（certs.rs）：

```rust
pub(super) struct ManagedMitmCa {
    issuer: Issuer<'static, KeyPair>,  // CA 签发者
}

impl ManagedMitmCa {
    pub(super) fn load_or_create() -> Result<Self> {
        // 从 $CODEX_HOME/proxy/ 加载或生成 CA
        // 使用 rcgen 生成 ECDSA P-256 证书
    }
    
    pub(super) fn tls_acceptor_data_for_host(&self, host: &str) -> Result<TlsAcceptorData> {
        // 为特定 host 签发叶子证书
        // 使用 rustls 构建 ServerConfig
    }
}
```

MITM 隧道（mitm.rs:117-181）：

```rust
pub(crate) async fn mitm_tunnel(upgraded: Upgraded) -> Result<()> {
    let acceptor_data = mitm.tls_acceptor_data_for_host(&target_host)?;
    
    let https_service = TlsAcceptorLayer::new(acceptor_data)
        .into_layer(http_service);
    
    https_service.serve(upgraded).await
}
```

### 3.6 约束验证系统

用于管理配置限制（state.rs:86-365）：

```rust
pub fn validate_policy_against_constraints(
    config: &NetworkProxyConfig,
    constraints: &NetworkProxyConstraints,
) -> Result<(), NetworkProxyConstraintError> {
    // 验证 enabled、mode、allow_upstream_proxy 等字段
    // 验证 allowed_domains 是否为约束的子集
    // 验证 denied_domains 是否包含所有必需的条目
}
```

### 3.7 审计日志

OTEL 兼容的事件格式（network_policy.rs:228-255）：

```rust
fn emit_policy_audit_event(state: &NetworkProxyState, args: PolicyAuditEventArgs<'_>) {
    tracing::event!(
        target: "codex_otel.network_proxy",
        event.name = "codex.network_proxy.policy_decision",
        network.policy.scope = args.scope,           // domain/non_domain
        network.policy.decision = args.decision,     // allow/deny/ask
        network.policy.source = args.source,         // baseline_policy/mode_guard/proxy_state/decider
        network.policy.reason = args.reason,
        network.transport.protocol = args.protocol.as_policy_protocol(),
        server.address = args.server_address,
        server.port = args.server_port,
        http.request.method = args.method.unwrap_or("none"),
        client.address = args.client_addr.unwrap_or("unknown"),
        network.policy.override = args.policy_override,
        // ... 元数据字段
    );
}
```

---

## 关键代码路径与文件引用

### 核心模块文件

| 文件 | 职责 |
|------|------|
| `src/lib.rs` | 模块导出、公共 API |
| `src/proxy.rs` | NetworkProxy/Builder/Handle，环境变量注入 |
| `src/config.rs` | 配置解析、地址解析、绑定限制 |
| `src/runtime.rs` | NetworkProxyState、配置重载、阻塞请求记录 |
| `src/state.rs` | ConfigState、约束验证、构建逻辑 |
| `src/policy.rs` | Host 解析、GlobSet 编译、域名模式匹配 |
| `src/network_policy.rs` | 策略决策 trait、审计事件、评估逻辑 |
| `src/http_proxy.rs` | HTTP/HTTPS 代理服务实现 |
| `src/socks5.rs` | SOCKS5 代理服务实现 |
| `src/mitm.rs` | HTTPS MITM 隧道实现 |
| `src/certs.rs` | CA 和叶子证书管理 |
| `src/responses.rs` | 阻塞响应生成、错误消息 |
| `src/reasons.rs` | 阻塞原因常量 |

### 关键流程代码路径

1. **代理启动**：`proxy.rs:127-191` (builder) → `proxy.rs:428-494` (run)
2. **HTTP 请求处理**：`http_proxy.rs:423-747` (http_plain_proxy)
3. **CONNECT 处理**：`http_proxy.rs:152-315` (http_connect_accept) → `http_proxy.rs:317-376` (http_connect_proxy)
4. **策略评估**：`network_policy.rs:289-359` (evaluate_host_policy)
5. **主机阻塞检查**：`runtime.rs:337-402` (host_blocked)
6. **SOCKS5 TCP 处理**：`socks5.rs:132-294` (handle_socks5_tcp)
7. **MITM 隧道**：`mitm.rs:117-181` (mitm_tunnel)

### 测试文件

| 文件 | 覆盖内容 |
|------|----------|
| `src/mitm_tests.rs` | MITM 策略拦截测试 |
| `src/proxy.rs:563-819` | 代理构建器单元测试 |
| `src/config.rs:354-605` | 配置解析单元测试 |
| `src/policy.rs:312-435` | 域名匹配单元测试 |
| `src/network_policy.rs:531-890` | 策略决策单元测试 |
| `src/runtime.rs:785-1000+` | 运行时状态单元测试 |
| `src/socks5.rs:484-609` | SOCKS5 单元测试 |

---

## 依赖与外部交互

### 外部依赖（Cargo.toml）

| 依赖 | 用途 |
|------|------|
| `rama-*` (0.3.0-alpha.4) | HTTP/SOCKS5 代理框架 |
| `globset` | 域名通配符匹配 |
| `tokio` | 异步运行时 |
| `serde` | 配置序列化 |
| `chrono`/`time` | 时间戳处理 |
| `codex-utils-*` | 内部工具（路径、home 目录、rustls） |

### 调用方（上游依赖）

| Crate | 使用方式 |
|-------|----------|
| `codex-core` | `network_proxy_loader.rs` 构建代理状态，`network_policy_decision.rs` 处理策略决策 |
| `codex-tui` | 通过 core 使用网络代理 |
| `codex-cli` | 命令行启动时代理配置 |

### 核心集成点

**codex-core/src/network_proxy_loader.rs**：
- 构建 `NetworkProxyState` 和 `MtimeConfigReloader`
- 从配置层加载网络设置
- 应用 execpolicy 网络规则

**codex-core/src/network_policy_decision.rs**：
- 转换 `NetworkPolicyDecisionPayload`
- 生成 `NetworkApprovalContext`
- 处理阻塞请求消息

---

## 风险、边界与改进建议

### 已知风险

1. **DNS 重绑定攻击**
   - 缓解：运行时 DNS 解析检查（`host_resolves_to_non_public_ip`）
   - 限制：2 秒超时，失败时默认允许
   - 建议：在生产环境结合防火墙/VPC 策略

2. **MITM CA 安全**
   - 缓解：私钥文件权限 0o600，拒绝符号链接
   - 风险：CA 私钥泄露可导致中间人攻击
   - 建议：定期轮换 CA，使用硬件安全模块

3. **Unix Socket 代理风险**
   - 缓解：macOS 限定、绝对路径要求、白名单机制
   - 风险：`dangerously_allow_all_unix_sockets` 可访问任意 socket
   - 建议：避免在生产环境启用 `dangerously_*` 选项

4. **Limited 模式绕过**
   - 缓解：无 MITM 时拒绝 HTTPS CONNECT
   - 风险：客户端可能通过 SOCKS5 绕过（但 limited 模式也阻塞 SOCKS5）

### 边界限制

| 限制 | 说明 |
|------|------|
| 平台限制 | Unix Socket 代理仅 macOS |
| 通配符限制 | 不支持全局 `*`，仅支持 `*.` 和 `**.` 前缀 |
| 阻塞历史 | 最多保留 200 条阻塞请求 |
| DNS 超时 | 2 秒，超时后默认允许 |
| 证书存储 | 固定路径 `$CODEX_HOME/proxy/` |

### 改进建议

1. **性能优化**
   - 使用 LRU 缓存 DNS 解析结果
   - 减少 `RwLock` 持有时间，考虑使用 `arc-swap` 进行配置热更新

2. **可观测性**
   - 添加指标导出（阻塞率、延迟、缓存命中率）
   - 支持结构化日志输出到文件

3. **功能扩展**
   - 支持 HTTP/2 代理（当前仅 HTTP/1）
   - 支持基于时间的策略（工作时间限制）
   - 支持按进程/用户细粒度控制

4. **安全加固**
   - 实现证书固定（pinning）防止 CA 替换
   - 添加请求/响应体大小限制
   - 支持 TLS 1.3 强制

5. **代码质量**
   - 增加集成测试覆盖 SOCKS5 UDP 场景
   - 统一错误类型，减少 `anyhow` 在库代码中的使用
   - 提取公共的 "策略决策" 逻辑到独立 crate

---

*文档生成时间：2026-03-21*
*研究对象版本：基于 codex-rs/network-proxy 源代码*
