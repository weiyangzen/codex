# codex-rs/network-proxy 深度研究文档

## 1. 场景与职责

`codex-network-proxy` 是 Codex 的本地网络策略执行代理，作为 Codex 生态系统的网络沙箱核心组件。其主要职责包括：

### 1.1 核心定位
- **网络访问控制网关**：所有 Codex 子进程的网络流量必须通过此代理
- **策略执行点**：强制执行允许/拒绝列表、Limited/Full 模式、本地网络保护等安全策略
- **审计与可观测性**：记录所有网络策略决策，支持 OTEL 格式的事件导出

### 1.2 运行模式
- **Managed by Codex**（默认）：代理由 Codex 管理，自动绑定到回环 ephemeral 端口
- **Standalone**：独立运行，可配置自定义监听地址

### 1.3 关键场景
1. **沙箱网络隔离**：配合 Seatbelt/Landlock 等沙箱机制，提供网络层隔离
2. **企业合规**：通过 managed config 限制用户可访问的域名范围
3. **安全审计**：完整记录被阻止的请求，支持合规审计
4. **本地开发保护**：防止 AI 助手意外访问本地服务（如 docker.sock、metadata endpoints）

---

## 2. 功能点目的

### 2.1 双协议代理服务

| 协议 | 默认地址 | 用途 |
|------|----------|------|
| HTTP Proxy | 127.0.0.1:3128 | HTTP/HTTPS 流量代理，支持 CONNECT 隧道 |
| SOCKS5 Proxy | 127.0.0.1:8081 | TCP/UDP 流量代理，支持更广泛的协议 |

### 2.2 网络模式（NetworkMode）

```rust
pub enum NetworkMode {
    Limited,  // 只读模式：仅允许 GET/HEAD/OPTIONS
    Full,     // 完整模式：允许所有 HTTP 方法
}
```

**Limited 模式的关键限制**：
- HTTP 请求只允许 GET/HEAD/OPTIONS
- HTTPS CONNECT 需要 MITM 支持才能执行方法检查
- SOCKS5 完全禁用（因为无法检查内部流量）

### 2.3 域名策略

**允许列表（Allowlist）**：
- 支持精确匹配：`example.com`
- 支持子域名通配：`*.example.com`（不匹配 apex）
- 支持 apex+子域通配：`**.example.com`（匹配 apex 和所有子域）
- **拒绝全局通配符 `*`**（安全设计）

**拒绝列表（Denylist）**：
- 优先级高于允许列表
- 支持相同的通配符语法

### 2.4 本地网络保护

当 `allow_local_binding = false` 时：
- 阻止所有本地/私有 IP 范围（127.0.0.0/8, 10.0.0.0/8, 192.168.0.0/16 等）
- 即使域名在允许列表中，如果解析到本地 IP，也会被阻止（DNS 重绑定防护）
- 需要显式将 `localhost` 或具体 IP 加入允许列表才能访问

### 2.5 MITM（中间人）支持

**目的**：在 Limited 模式下检查 HTTPS 流量中的 HTTP 方法

**实现**：
- 自动生成/加载本地 CA（存储在 `$CODEX_HOME/proxy/ca.pem` + `ca.key`）
- 为每个目标主机签发临时叶子证书
- 终止 TLS 连接，检查内部 HTTP 请求，然后重新加密转发

**安全考虑**：
- CA 私钥文件权限严格限制为 0o600
- 拒绝使用符号链接的 CA 密钥
- 原子写入防止部分文件残留

### 2.6 Unix Socket 代理（macOS 专用）

**用途**：允许代理到本地 Unix Socket（如 Docker socket）

**安全控制**：
- 仅 macOS 支持
- 必须通过 `allow_unix_sockets` 显式允许特定路径
- 或设置 `dangerously_allow_all_unix_sockets`（危险选项）
- 启用后强制代理监听回环地址（防止远程桥接攻击）

### 2.7 上游代理支持

当 `allow_upstream_proxy = true` 时：
- 尊重 `HTTP_PROXY`/`HTTPS_PROXY`/`ALL_PROXY` 环境变量
- 支持通过企业代理出站
- CONNECT 隧道可级联到上游代理

---

## 3. 具体技术实现

### 3.1 架构概览

```
┌─────────────────────────────────────────────────────────────┐
│                     NetworkProxy (主入口)                     │
│  ┌─────────────────┐  ┌─────────────────┐                   │
│  │  HTTP Proxy     │  │  SOCKS5 Proxy   │                   │
│  │  (http_proxy)   │  │  (socks5)       │                   │
│  └────────┬────────┘  └────────┬────────┘                   │
│           │                    │                            │
│           └────────┬───────────┘                            │
│                    ▼                                        │
│         ┌─────────────────────┐                             │
│         │  NetworkProxyState  │                             │
│         │  - 配置管理          │                             │
│         │  - 策略评估          │                             │
│         │  - 审计日志          │                             │
│         └─────────────────────┘                             │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 关键数据结构

#### 3.2.1 NetworkProxyConfig

```rust
pub struct NetworkProxyConfig {
    pub network: NetworkProxySettings,
}

pub struct NetworkProxySettings {
    pub enabled: bool,                           // 总开关
    pub proxy_url: String,                       // HTTP 代理监听地址
    pub enable_socks5: bool,                     // 是否启用 SOCKS5
    pub socks_url: String,                       // SOCKS5 监听地址
    pub enable_socks5_udp: bool,                 // SOCKS5 UDP 中继
    pub allow_upstream_proxy: bool,              // 尊重上游代理环境变量
    pub dangerously_allow_non_loopback_proxy: bool,  // 允许非回环绑定
    pub dangerously_allow_all_unix_sockets: bool,    // 允许所有 Unix socket
    pub mode: NetworkMode,                       // Limited/Full
    pub allowed_domains: Vec<String>,            // 允许列表
    pub denied_domains: Vec<String>,             // 拒绝列表
    pub allow_unix_sockets: Vec<String>,         // 允许的 Unix socket 路径
    pub allow_local_binding: bool,               // 允许本地/私有网络
    pub mitm: bool,                              // 启用 MITM
}
```

#### 3.2.2 NetworkProxyState

```rust
pub struct NetworkProxyState {
    state: Arc<RwLock<ConfigState>>,           // 配置状态（支持热重载）
    reloader: Arc<dyn ConfigReloader>,         // 配置重载器
    blocked_request_observer: Arc<RwLock<Option<Arc<dyn BlockedRequestObserver>>>>,
    audit_metadata: NetworkProxyAuditMetadata, // 审计元数据
}

pub struct ConfigState {
    pub config: NetworkProxyConfig,
    pub allow_set: GlobSet,      // 编译后的允许列表（globset）
    pub deny_set: GlobSet,       // 编译后的拒绝列表
    pub mitm: Option<Arc<MitmState>>,
    pub constraints: NetworkProxyConstraints,  // 托管约束
    pub blocked: VecDeque<BlockedRequest>,     // 被阻止请求缓冲区
    pub blocked_total: u64,
}
```

#### 3.2.3 策略决策类型

```rust
pub enum NetworkDecision {
    Allow,
    Deny {
        reason: String,
        source: NetworkDecisionSource,
        decision: NetworkPolicyDecision,  // Deny / Ask
    },
}

pub enum NetworkDecisionSource {
    BaselinePolicy,   // 基础策略（允许/拒绝列表）
    ModeGuard,        // 模式守卫（Limited 模式限制）
    ProxyState,       // 代理状态（如 disabled）
    Decider,          // 自定义策略决策器
}
```

### 3.3 关键流程

#### 3.3.1 HTTP 请求处理流程（http_proxy.rs）

```
1. 接收 HTTP 请求
   ├── 检查 proxy enabled 状态
   ├── 提取目标 host 和 port
   └── 验证 Host 头与目标一致（防止请求走私）

2. 策略评估
   ├── 检查允许/拒绝列表（evaluate_host_policy）
   │   ├── 拒绝列表匹配 → 阻止
   │   ├── 本地 IP 检查 → 如未允许则阻止
   │   └── 允许列表匹配 → 通过
   └── 如未在允许列表中 → 调用 PolicyDecider（如有）

3. 方法检查
   └── Limited 模式下只允许 GET/HEAD/OPTIONS

4. 特殊处理
   ├── x-unix-socket 头 → Unix Socket 代理（macOS）
   └── CONNECT 方法 → 建立隧道或 MITM

5. 转发请求
   └── 通过 UpstreamClient 发送到目标
```

#### 3.3.2 HTTPS CONNECT 处理流程

```
1. 接收 CONNECT 请求

2. 策略评估（同 HTTP）

3. Limited 模式检查
   ├── MITM 启用 → 进入 MITM 流程
   └── MITM 禁用 → 阻止（需要 MITM 才能检查内部方法）

4. Full 模式
   └── 建立直通隧道（可选级联到上游代理）
```

#### 3.3.3 MITM 流程（mitm.rs）

```
1. 接收已升级的 CONNECT 连接

2. 加载/生成目标主机的叶子证书
   └── 使用 ManagedMitmCa 签发证书

3. 终止 TLS，解密内部 HTTP 请求

4. 策略检查
   ├── 重新检查本地/私有 IP（DNS 重绑定防护）
   └── 检查 HTTP 方法（Limited 模式）

5. 转发到上游
   └── 重新加密发送到目标服务器
```

#### 3.3.4 SOCKS5 处理流程（socks5.rs）

```
1. 接收 SOCKS5 连接

2. 检查 enabled 状态

3. Limited 模式检查
   └── Limited 模式下完全阻止 SOCKS5

4. 策略评估
   └── 同 HTTP 流程（evaluate_host_policy）

5. 建立 TCP 连接或 UDP 中继
```

### 3.4 策略评估实现（policy.rs + runtime.rs）

```rust
// 主机阻止决策
pub async fn host_blocked(&self, host: &str, port: u16) -> Result<HostBlockDecision> {
    // 1. 拒绝列表检查（最高优先级）
    if deny_set.is_match(host) {
        return Ok(HostBlockDecision::Blocked(HostBlockReason::Denied));
    }

    // 2. 本地/私有网络检查
    if !allow_local_binding {
        // 检查是否为本地 IP 字面量
        if is_loopback_host(&host) || is_non_public_ip(ip) {
            if !is_explicit_local_allowlisted(&allowed_domains, &host) {
                return Ok(HostBlockDecision::Blocked(HostBlockReason::NotAllowedLocal));
            }
        }
        // DNS 解析检查（防止 DNS 重绑定）
        if host_resolves_to_non_public_ip(host, port).await {
            return Ok(HostBlockDecision::Blocked(HostBlockReason::NotAllowedLocal));
        }
    }

    // 3. 允许列表检查
    if allowed_domains_empty || !allow_set.is_match(host) {
        return Ok(HostBlockDecision::Blocked(HostBlockReason::NotAllowed));
    }

    Ok(HostBlockDecision::Allowed)
}
```

### 3.5 审计事件格式

```rust
// OTEL 兼容的事件结构
tracing::event!(
    target: "codex_otel.network_proxy",
    event.name = "codex.network_proxy.policy_decision",
    event.timestamp = %audit_timestamp(),
    conversation.id = metadata.conversation_id,
    app.version = metadata.app_version,
    network.policy.scope = "domain",  // 或 "non_domain"
    network.policy.decision = "allow" | "deny" | "ask",
    network.policy.source = "baseline_policy" | "mode_guard" | "proxy_state" | "decider",
    network.policy.reason = reason,
    network.transport.protocol = "http" | "https_connect" | "socks5_tcp" | "socks5_udp",
    server.address = host,
    server.port = port,
    http.request.method = method,
    client.address = client_addr,
    network.policy.override = policy_override,
);
```

### 3.6 环境变量注入

代理启动后会向子进程注入以下环境变量：

```rust
// HTTP 代理变量
HTTP_PROXY=http://127.0.0.1:3128
HTTPS_PROXY=http://127.0.0.1:3128
WS_PROXY=http://127.0.0.1:3128
WSS_PROXY=http://127.0.0.1:3128

// SOCKS5 代理变量（当启用时）
ALL_PROXY=socks5h://127.0.0.1:8081
FTP_PROXY=socks5h://127.0.0.1:8081

// 不代理列表（防止代理循环）
NO_PROXY=localhost,127.0.0.1,::1,*.local,.local,169.254.0.0/16,...

// 本地绑定权限标记
CODEX_NETWORK_ALLOW_LOCAL_BINDING=0|1

// macOS SSH 代理命令
GIT_SSH_COMMAND=ssh -o ProxyCommand='nc -X 5 -x 127.0.0.1:8081 %h %p'
```

---

## 4. 关键代码路径与文件引用

### 4.1 模块结构

```
codex-rs/network-proxy/src/
├── lib.rs              # 模块导出，公共 API
├── proxy.rs            # NetworkProxy 主结构，Builder 模式
├── config.rs           # 配置解析，地址解析，绑定限制
├── state.rs            # 配置状态，约束验证
├── runtime.rs          # NetworkProxyState，策略评估，审计
├── policy.rs           # 域名匹配，GlobSet 编译，IP 分类
├── network_policy.rs   # 策略决策 trait，审计事件发射
├── http_proxy.rs       # HTTP 代理服务实现
├── socks5.rs           # SOCKS5 代理服务实现
├── mitm.rs             # MITM TLS 终止实现
├── certs.rs            # CA 证书管理，叶子证书签发
├── upstream.rs         # 上游连接，Unix Socket 连接器
├── responses.rs        # HTTP 响应构造，错误消息
└── reasons.rs          # 阻止原因常量
```

### 4.2 关键代码路径

| 功能 | 文件 | 关键函数/结构 |
|------|------|--------------|
| 代理启动 | `proxy.rs` | `NetworkProxy::builder().build().await`, `NetworkProxy::run()` |
| HTTP 请求处理 | `http_proxy.rs` | `http_plain_proxy()`, `http_connect_accept()` |
| SOCKS5 处理 | `socks5.rs` | `handle_socks5_tcp()`, `inspect_socks5_udp()` |
| 策略评估 | `runtime.rs` | `NetworkProxyState::host_blocked()` |
| 域名匹配 | `policy.rs` | `compile_globset()`, `DomainPattern` |
| MITM 处理 | `mitm.rs` | `mitm_tunnel()`, `mitm_blocking_response()` |
| 证书管理 | `certs.rs` | `ManagedMitmCa::load_or_create()` |
| 审计事件 | `network_policy.rs` | `evaluate_host_policy()`, `emit_policy_audit_event()` |
| 配置热重载 | `runtime.rs` | `NetworkProxyState::reload_if_needed()` |
| 约束验证 | `state.rs` | `validate_policy_against_constraints()` |

### 4.3 外部调用接口

**被 core 模块调用**（`core/src/network_proxy_loader.rs`）：
```rust
pub async fn build_network_proxy_state() -> Result<NetworkProxyState>
```

**被 core 模块调用**（`core/src/config/network_proxy_spec.rs`）：
```rust
NetworkProxySpec::start_proxy(...)
NetworkProxy::builder()
    .state(Arc::new(state))
    .policy_decider(decider)
    .blocked_request_observer(observer)
    .build()
    .await
```

---

## 5. 依赖与外部交互

### 5.1 外部依赖（Cargo.toml）

**核心依赖**：
- `rama-*` (0.3.0-alpha.4): 代理服务器框架
  - `rama-core`: 核心服务抽象
  - `rama-http`: HTTP 协议处理
  - `rama-http-backend`: HTTP 服务器/客户端后端
  - `rama-net`: 网络地址、代理协议
  - `rama-socks5`: SOCKS5 协议实现
  - `rama-tcp`: TCP 连接器
  - `rama-tls-rustls`: TLS 支持（rustls 后端）
  - `rama-unix`: Unix Socket 支持（macOS）
- `globset`: 域名通配符匹配
- `rustls` (via rama): TLS 加密
- `rcgen` (via rama): 证书生成

**工具依赖**：
- `tokio`: 异步运行时
- `serde`/`serde_json`: 配置序列化
- `anyhow`: 错误处理
- `thiserror`: 自定义错误类型
- `tracing`: 日志和审计
- `chrono`/`time`: 时间处理
- `async-trait`: 异步 trait
- `clap`: CLI 参数（仅 binary）

**内部依赖**：
- `codex-utils-absolute-path`: 绝对路径处理
- `codex-utils-home-dir`: Codex home 目录解析
- `codex-utils-rustls-provider`: rustls 加密提供者初始化

### 5.2 调用方模块

| 调用方 | 用途 |
|--------|------|
| `codex-core` | 构建代理状态，启动代理，配置加载 |
| `codex-tui` | 调试配置展示 |
| `codex-tui_app_server` | 应用服务器会话中的网络代理管理 |
| `codex-app-server` | 命令执行时的网络代理集成 |

### 5.3 被调用服务

| 服务 | 用途 |
|------|------|
| DNS 解析器 | `tokio::net::lookup_host` 用于 DNS 重绑定防护 |
| 文件系统 | CA 证书存储（`$CODEX_HOME/proxy/`） |
| Unix Socket | 本地服务代理（macOS） |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 DNS 重绑定攻击

**风险**：攻击者控制 DNS 服务器，先返回公共 IP 通过检查，再返回私有 IP。

**当前缓解**：
- 请求时进行 DNS 解析检查（`host_resolves_to_non_public_ip`）
- MITM 模式下在 CONNECT 后再次检查

**限制**：
- 2 秒超时后默认允许（避免可用性问题）
- DNS TTL 窗口期内仍可能被攻击

**建议**：
- 考虑在传输层实施 IP 地址固定（pinning）
- 企业环境建议配合防火墙/VPC 策略

#### 6.1.2 MITM CA 私钥泄露

**风险**：本地 CA 私钥被恶意软件获取，可签发任意域名的伪造证书。

**当前缓解**：
- 文件权限 0o600
- 拒绝符号链接
- 原子写入防止部分文件

**建议**：
- 考虑使用系统密钥链存储私钥
- 定期轮换 CA 证书

#### 6.1.3 Unix Socket 远程桥接

**风险**：如果代理监听非回环地址，攻击者可利用 Unix Socket 代理访问本地服务。

**当前缓解**：
- 启用 Unix Socket 时强制回环绑定
- 绝对路径要求

#### 6.1.4 策略决策器（Policy Decider）绕过

**风险**：自定义 decider 实现不当可能绕过安全策略。

**当前缓解**：
- 显式拒绝（denylist）始终优先于 decider
- 本地 IP 阻止在 decider 之前执行

### 6.2 边界条件

| 边界 | 行为 |
|------|------|
| 允许列表为空 | 阻止所有请求（安全默认） |
| DNS 解析失败 | 默认允许（避免误杀），依赖后续连接失败 |
| DNS 解析超时（2s） | 默认允许 |
| 配置热重载失败 | 保留旧配置，记录警告 |
| CA 证书损坏 | 启动失败，需要手动删除 `$CODEX_HOME/proxy/` |
| Unix Socket 不存在 | 连接时失败（BAD_GATEWAY） |
| SOCKS5 UDP | 需要显式启用，Limited 模式下阻止 |

### 6.3 改进建议

#### 6.3.1 短期改进

1. **增强 DNS 重绑定防护**
   - 实现 DNS 响应缓存，减少重复查询
   - 考虑在连接建立时再次验证 IP

2. **配置验证增强**
   - 启动时验证所有允许列表域名是否可解析
   - 检测并警告潜在的配置错误（如 `*.com` 过于宽泛）

3. **审计改进**
   - 支持结构化日志输出（JSON）
   - 添加请求/响应大小统计

#### 6.3.2 中期改进

1. **性能优化**
   - GlobSet 匹配优化（当前每次请求都重新读取配置）
   - 连接池复用（当前每个请求新建连接）

2. **可观测性**
   - 添加 Prometheus 指标导出
   - 支持分布式追踪（OpenTelemetry）

3. **配置管理**
   - 支持配置变更 webhook/回调
   - 允许运行时修改允许列表而不重启

#### 6.3.3 长期改进

1. **协议支持**
   - HTTP/2 代理支持（当前仅 HTTP/1.1）
   - QUIC/HTTP3 支持

2. **安全增强**
   - 证书透明度（CT）日志检查
   - 证书固定（Certificate Pinning）支持

3. **多平台支持**
   - Unix Socket 代理支持 Linux
   - Windows 命名管道支持

---

## 7. 测试覆盖

### 7.1 单元测试

| 测试文件 | 覆盖内容 |
|----------|----------|
| `config.rs` (tests) | 地址解析，绑定限制，配置默认值 |
| `policy.rs` (tests) | 域名匹配，GlobSet 编译，IP 分类 |
| `runtime.rs` (tests) | 策略评估，允许/拒绝列表更新，约束验证 |
| `network_policy.rs` (tests) | 审计事件，decider 集成 |
| `http_proxy.rs` (tests) | CONNECT 处理，方法限制，Host 头验证 |
| `socks5.rs` (tests) | SOCKS5 TCP/UDP 策略执行 |
| `mitm_tests.rs` | MITM 方法限制，主机不匹配检测 |
| `certs.rs` (tests) | CA 密钥权限验证，符号链接拒绝 |

### 7.2 集成测试

- `core/src/network_proxy_loader_tests.rs`: 配置加载器集成测试
- 端到端测试通过 `codex-core` 的测试套件执行

---

## 8. 配置示例

### 8.1 基础配置（config.toml）

```toml
default_permissions = "workspace"

[permissions.workspace.network]
enabled = true
proxy_url = "http://127.0.0.1:3128"
enable_socks5 = true
socks_url = "http://127.0.0.1:8081"
allow_upstream_proxy = true
mode = "full"
allowed_domains = ["*.openai.com", "localhost", "127.0.0.1", "::1"]
denied_domains = ["evil.example.com"]
allow_local_binding = false
mitm = false
```

### 8.2 Limited 模式配置

```toml
[permissions.workspace.network]
enabled = true
mode = "limited"  # 只读模式
mitm = true       # 需要 MITM 来检查 HTTPS 方法
allowed_domains = ["api.github.com"]
```

### 8.3 Unix Socket 配置（macOS）

```toml
[permissions.workspace.network]
enabled = true
allow_unix_sockets = ["/var/run/docker.sock"]
# dangerously_allow_all_unix_sockets = false  # 危险选项
```

---

## 9. 总结

`codex-network-proxy` 是 Codex 安全架构的关键组件，通过多层防御机制（允许/拒绝列表、本地网络保护、Limited 模式、MITM 检查）为 AI 助手提供受控的网络访问能力。其设计充分考虑了企业合规、安全审计和易用性需求，同时通过热重载、OTEL 审计等特性满足生产环境要求。

主要技术亮点：
- 基于 Rama 框架的高性能异步代理
- 灵活的域名策略（支持多级通配符）
- 完善的 DNS 重绑定防护
- 可选的 MITM 支持用于 HTTPS 深度检查
- 全面的审计日志（OTEL 兼容）
- 配置热重载和托管约束支持
