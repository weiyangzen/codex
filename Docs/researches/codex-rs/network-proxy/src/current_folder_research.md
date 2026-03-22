# codex-rs/network-proxy/src 深度研究文档

## 1. 场景与职责

`codex-network-proxy` 是 Codex 项目的网络沙箱代理组件，负责在本地执行环境中实施细粒度的网络访问控制策略。该 crate 的核心使命是：**在 AI 代理执行代码时，强制实施网络安全策略，防止未经授权的网络访问**。

### 1.1 核心场景

| 场景 | 描述 |
|------|------|
| **AI 代码执行沙箱** | 当 Codex 执行用户请求的代码（如 Python 脚本、Shell 命令）时，代理拦截所有网络请求 |
| **网络访问审批** | 对于不在允许列表中的域名，代理可触发审批流程，由用户决定是否允许访问 |
| **只读模式执行** | 在 "limited" 模式下，仅允许 GET/HEAD/OPTIONS 请求，阻止数据外泄 |
| **本地服务保护** | 防止 AI 代理访问本地私有网络（127.0.0.1、10.0.0.0/8 等），防御 SSRF 攻击 |
| **Unix Socket 代理** | 支持通过 HTTP 代理访问本地 Unix Socket（如 Docker socket），但需显式授权 |

### 1.2 架构定位

```
┌─────────────────────────────────────────────────────────────────┐
│                        Codex Core                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ Exec Policy  │  │ Network      │  │ Sandbox (seatbelt/   │  │
│  │ (执行策略)    │◄─┤ Proxy Loader │  │  landlock)           │  │
│  └──────────────┘  └──────┬───────┘  └──────────────────────┘  │
│                           │                                     │
│                           ▼                                     │
│                  ┌─────────────────┐                           │
│                  │ NetworkProxy    │◄── 配置热重载              │
│                  │ (本 crate)      │                           │
│                  └────────┬────────┘                           │
│                           │                                     │
└───────────────────────────┼─────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│  HTTP Proxy   │   │  SOCKS5 Proxy │   │  MITM (可选)  │
│  (127.0.0.1:  │   │  (127.0.0.1:  │   │  HTTPS 拦截   │
│   3128 默认)   │   │   8081 默认)   │   │               │
└───────┬───────┘   └───────┬───────┘   └───────┬───────┘
        │                   │                   │
        └───────────────────┴───────────────────┘
                            │
                    ┌───────▼───────┐
                    │  策略决策引擎  │
                    │  - 允许列表   │
                    │  - 拒绝列表   │
                    │  - 本地绑定   │
                    │  - 方法限制   │
                    └───────────────┘
```

---

## 2. 功能点目的

### 2.1 双协议代理服务

| 协议 | 默认地址 | 用途 | 配置项 |
|------|----------|------|--------|
| HTTP Proxy | `127.0.0.1:3128` | HTTP/HTTPS 请求代理 | `network.proxy_url` |
| SOCKS5 Proxy | `127.0.0.1:8081` | TCP/UDP 流量代理 | `network.socks_url` |

**设计目的**：
- HTTP 代理：兼容大多数应用程序的代理设置（curl、npm、pip 等）
- SOCKS5 代理：支持非 HTTP 流量（SSH、数据库连接等）

### 2.2 网络模式

```rust
pub enum NetworkMode {
    /// 只读模式：仅允许 GET/HEAD/OPTIONS
    Limited,
    /// 完全模式：允许所有 HTTP 方法
    Full,
}
```

**Limited 模式的特殊处理**：
- HTTPS CONNECT 隧道默认无法实施方法限制（隧道内流量加密）
- 解决方案：启用 MITM（Man-in-the-Middle）模式，终止 TLS 连接，检查内部 HTTP 请求

### 2.3 域名策略系统

| 策略类型 | 优先级 | 说明 |
|----------|--------|------|
| `denied_domains` | 最高 | 明确拒绝的域名，永远不允许 |
| `allowed_domains` | 中 | 允许列表，支持通配符模式 |
| 本地/私有网络检查 | 高 | 解析到私有 IP 的域名被拒绝（即使白名单） |

**通配符模式**：
- `*.example.com`：匹配子域名，不匹配 apex
- `**.example.com`：匹配 apex 和所有子域名
- `*`：全局通配符被**明确拒绝**（安全设计）

### 2.4 本地网络保护

```rust
// 被阻止的 IP 范围（当 allow_local_binding = false）
- IPv4: 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
       169.254.0.0/16, 100.64.0.0/10 (CGNAT), 等
- IPv6: ::1, fe80::/10, fc00::/7
```

**DNS Rebinding 防护**：
- 不仅检查域名是否在白名单
- 还进行 DNS 解析，检查解析结果是否为私有 IP
- 即使域名在白名单，解析到私有 IP 仍被拒绝

### 2.5 Unix Socket 代理（macOS 专属）

通过自定义 HTTP 头 `x-unix-socket: /path/to/socket` 实现：

```bash
# 示例：通过代理访问 Docker socket
curl -H "x-unix-socket: /var/run/docker.sock" \
     http://localhost/containers/json
```

**安全限制**：
- 仅 macOS 支持（`unix_socket_permissions_supported()`）
- 必须显式配置 `allow_unix_sockets` 白名单
- 或设置 `dangerously_allow_all_unix_sockets = true`（危险）
- 启用后，代理强制绑定到 loopback（防止远程访问本地 socket）

### 2.6 MITM（中间人）模式

**目的**：在 Limited 模式下，能够检查 HTTPS 请求的内部内容，实施方法限制。

**实现机制**：
1. 自动生成 CA 证书（存储于 `$CODEX_HOME/proxy/ca.pem` 和 `ca.key`）
2. 为每个目标主机动态签发叶子证书
3. 终止客户端 TLS 连接，解密检查 HTTP 内容
4. 重新加密发送到上游服务器

**安全考虑**：
- CA 私钥权限严格限制（0o600）
- 拒绝符号链接（防止路径遍历）
- 证书原子写入，防止部分写入

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 配置结构

```rust
// codex-rs/network-proxy/src/config.rs
pub struct NetworkProxyConfig {
    pub network: NetworkProxySettings,
}

pub struct NetworkProxySettings {
    pub enabled: bool,                          // 总开关
    pub proxy_url: String,                      // HTTP 代理地址
    pub enable_socks5: bool,                    // 是否启用 SOCKS5
    pub socks_url: String,                      // SOCKS5 地址
    pub enable_socks5_udp: bool,                // SOCKS5 UDP 支持
    pub allow_upstream_proxy: bool,             // 是否允许上游代理
    pub dangerously_allow_non_loopback_proxy: bool,  // 允许非 loopback 绑定
    pub dangerously_allow_all_unix_sockets: bool,    // 允许所有 unix socket
    pub mode: NetworkMode,                      // 网络模式
    pub allowed_domains: Vec<String>,           // 允许列表
    pub denied_domains: Vec<String>,            // 拒绝列表
    pub allow_unix_sockets: Vec<String>,        // Unix socket 白名单
    pub allow_local_binding: bool,              // 允许本地绑定
    pub mitm: bool,                             // 启用 MITM
}
```

#### 3.1.2 运行时状态

```rust
// codex-rs/network-proxy/src/runtime.rs
pub struct NetworkProxyState {
    state: Arc<RwLock<ConfigState>>,
    reloader: Arc<dyn ConfigReloader>,        // 配置热重载
    blocked_request_observer: Arc<RwLock<Option<Arc<dyn BlockedRequestObserver>>>>,
    audit_metadata: NetworkProxyAuditMetadata, // OTEL 审计元数据
}

pub struct ConfigState {
    pub config: NetworkProxyConfig,
    pub allow_set: GlobSet,                    // 编译后的允许模式
    pub deny_set: GlobSet,                     // 编译后的拒绝模式
    pub mitm: Option<Arc<MitmState>>,         // MITM 状态
    pub constraints: NetworkProxyConstraints,  // 管理约束
    pub blocked: VecDeque<BlockedRequest>,    // 被阻止请求缓冲区
    pub blocked_total: u64,                   // 总计数
}
```

#### 3.1.3 策略决策

```rust
// codex-rs/network-proxy/src/network_policy.rs
pub enum NetworkDecision {
    Allow,
    Deny {
        reason: String,
        source: NetworkDecisionSource,
        decision: NetworkPolicyDecision,  // Deny | Ask
    },
}

pub enum NetworkPolicyDecision {
    Deny,   // 明确拒绝
    Ask,    // 询问用户（可审批）
}

pub enum NetworkDecisionSource {
    BaselinePolicy,  // 基础策略（白名单/黑名单）
    ModeGuard,       // 模式守卫（Limited 模式限制）
    ProxyState,      // 代理状态（如 disabled）
    Decider,         // 外部决策器（如用户审批）
}
```

### 3.2 关键流程

#### 3.2.1 HTTP 代理请求处理流程

```
┌─────────────┐
│  接收请求   │
└──────┬──────┘
       ▼
┌─────────────┐     ┌─────────────┐
│ 提取目标    │────►│ 检查 enabled│────► 503 Service Unavailable
│ 主机和端口  │     └──────┬──────┘
└─────────────┘            │
                           ▼
                  ┌─────────────┐
                  │ 评估策略    │
                  │ evaluate_   │
                  │ host_policy │
                  └──────┬──────┘
                         │
           ┌─────────────┼─────────────┐
           ▼             ▼             ▼
      ┌────────┐   ┌────────┐   ┌──────────┐
      │Allowed │   │Denied  │   │NotAllowed│
      │        │   │        │   │(无decider)│
      └───┬────┘   └───┬────┘   └────┬─────┘
          │            │             │
          ▼            ▼             ▼
     转发请求      403 Forbidden   403 Forbidden
     到上游        (blocked-by-    (blocked-by-
                  denylist)        allowlist)
                         │
           ┌─────────────┘
           ▼
    ┌──────────────┐
    │ 有 decider?  │
    └──────┬───────┘
           │
     ┌─────┴─────┐
     ▼           ▼
┌─────────┐  ┌─────────┐
│调用     │  │直接拒绝 │
│decider  │  │         │
└────┬────┘  └─────────┘
     │
     ▼
┌─────────┐  ┌─────────┐
│Allow    │  │Deny/Ask │
│(override)│  │         │
└────┬────┘  └────┬────┘
     │            │
     ▼            ▼
  转发请求    403 Forbidden
  到上游      (decision=ask/deny)
```

**代码路径**：`http_proxy.rs:423-747` (`http_plain_proxy` 函数)

#### 3.2.2 HTTPS CONNECT 处理流程

```
客户端 CONNECT example.com:443
         │
         ▼
┌─────────────────┐
│ http_connect_   │
│ accept          │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 1. 检查 enabled │────► 503 (proxy_disabled)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 2. 评估主机策略  │────► 403 (blocked)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 3. 检查模式     │
│    Limited?     │
└────────┬────────┘
         │
    ┌────┴────┐
    ▼         ▼
┌────────┐  ┌─────────────┐
│Full    │  │MITM enabled?│
│模式    │  └──────┬──────┘
│        │         │
│直接隧道 │    ┌────┴────┐
│        │    ▼         ▼
│        │ ┌────────┐  ┌────────┐
│        │ │Yes     │  │No      │
│        │ │        │  │        │
│        │ │MITM隧道 │  │403     │
│        │ │        │  │(mitm_  │
│        │ │        │  │required)│
└────────┘ └────────┘  └────────┘
```

**代码路径**：`http_proxy.rs:152-315` (`http_connect_accept` 函数)

#### 3.2.3 MITM 隧道处理流程

```
┌─────────────────┐
│ mitm_tunnel     │
│ (Upgraded 连接) │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 1. 提取目标信息  │
│    - target_host│
│    - target_port│
│    - mode       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 2. 生成主机证书  │
│    (动态签发)    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 3. 创建 TLS     │
│    acceptor     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 4. 服务 HTTPS   │
│    请求         │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ handle_mitm_    │
│ request         │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 5. 重新检查策略  │
│    - 本地/私有IP │
│    - 方法限制   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 6. 转发到上游    │
│    (重新加密)   │
└─────────────────┘
```

**代码路径**：`mitm.rs:117-181` (`mitm_tunnel` 函数)

### 3.3 协议实现细节

#### 3.3.1 基于 Rama 的代理架构

该 crate 使用 [Rama](https://github.com/plabayo/rama) 框架（版本 0.3.0-alpha.4）构建代理服务：

| 模块 | Rama 组件 | 用途 |
|------|-----------|------|
| HTTP Proxy | `rama_http_backend::server::HttpServer` | HTTP/1.1 服务器 |
| SOCKS5 | `rama_socks5::Socks5Acceptor` | SOCKS5 协议实现 |
| TLS | `rama_tls_rustls` | TLS 终止和发起 |
| TCP | `rama_tcp` | TCP 连接管理 |
| Unix Socket | `rama_unix` | Unix domain socket (macOS) |

#### 3.3.2 环境变量注入

代理启动时，会向下游进程注入标准代理环境变量：

```rust
// proxy.rs:308-377
fn apply_proxy_env_overrides(
    env: &mut HashMap<String, String>,
    http_addr: SocketAddr,
    socks_addr: SocketAddr,
    socks_enabled: bool,
    allow_local_binding: bool,
) {
    // HTTP 代理变量
    set_env_keys(env, &["HTTP_PROXY", "HTTPS_PROXY", ...], &http_proxy_url);
    
    // WebSocket 代理变量
    set_env_keys(env, WEBSOCKET_PROXY_ENV_KEYS, &http_proxy_url);
    
    // NO_PROXY 设置
    set_env_keys(env, NO_PROXY_ENV_KEYS, DEFAULT_NO_PROXY_VALUE);
    
    // SOCKS5 代理变量（如果启用）
    if socks_enabled {
        set_env_keys(env, ALL_PROXY_ENV_KEYS, &socks_proxy_url);
    }
    
    // macOS SSH 代理命令
    #[cfg(target_os = "macos")]
    if socks_enabled {
        env.entry("GIT_SSH_COMMAND".to_string())
            .or_insert_with(|| format!("ssh -o ProxyCommand='nc -X 5 -x {socks_addr} %h %p'"));
    }
}
```

### 3.4 审计与可观测性

#### 3.4.1 OTEL 兼容审计事件

每个策略决策都会发出结构化日志事件：

```rust
// network_policy.rs:228-255
fn emit_policy_audit_event(state: &NetworkProxyState, args: PolicyAuditEventArgs<'_>) {
    let metadata = state.audit_metadata();
    tracing::event!(
        target: "codex_otel.network_proxy",
        tracing::Level::INFO,
        event.name = "codex.network_proxy.policy_decision",
        event.timestamp = %audit_timestamp(),
        conversation.id = metadata.conversation_id.as_deref(),
        app.version = metadata.app_version.as_deref(),
        // ... 更多字段
        network.policy.decision = args.decision,    // "allow" | "deny" | "ask"
        network.policy.source = args.source,        // "baseline_policy" | "mode_guard" | ...
        network.policy.reason = args.reason,
        server.address = args.server_address,
        server.port = args.server_port,
        http.request.method = args.method.unwrap_or("none"),
        client.address = args.client_addr.unwrap_or("unknown"),
        network.policy.override = args.policy_override,
    );
}
```

#### 3.4.2 阻止请求遥测

```rust
// runtime.rs:404-440
pub async fn record_blocked(&self, entry: BlockedRequest) -> Result<()> {
    // 序列化为 JSON
    let violation_line = format!("CODEX_NETWORK_POLICY_VIOLATION {}", 
                                 serde_json::to_string(&entry)?);
    
    // 记录到日志
    debug!("{violation_line}");
    
    // 通知观察者（如 UI）
    if let Some(observer) = blocked_request_observer {
        observer.on_blocked_request(blocked_for_observer).await;
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心模块文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `lib.rs` | 51 | 模块导出和公共 API |
| `proxy.rs` | 819 | 主代理结构体 `NetworkProxy`，Builder 模式，环境变量注入 |
| `config.rs` | 605 | 配置解析、地址解析、绑定地址限制 |
| `runtime.rs` | 1671 | 运行时状态管理、策略评估、配置热重载、阻止请求记录 |
| `state.rs` | 406 | 配置状态构建、约束验证、配置变更检测 |
| `policy.rs` | 435 | 域名模式匹配、GlobSet 编译、IP 分类（私有/公共） |
| `network_policy.rs` | 890 | 策略决策 trait、审计事件、决策评估逻辑 |

### 4.2 协议实现文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `http_proxy.rs` | 1300 | HTTP 代理服务器、CONNECT 处理、MITM 集成、Unix Socket 代理 |
| `socks5.rs` | 609 | SOCKS5 代理服务器、TCP/UDP 处理 |
| `upstream.rs` | 190 | 上游连接管理、TLS 配置、代理链支持 |

### 4.3 辅助模块文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `mitm.rs` | 482 | MITM 状态管理、TLS 终止、HTTPS 请求处理 |
| `certs.rs` | 344 | CA 证书管理、动态证书签发、安全文件操作 |
| `responses.rs` | 125 | HTTP 响应构建、错误消息、JSON 序列化 |
| `reasons.rs` | 8 | 阻止原因常量定义 |

### 4.4 测试文件

| 文件 | 职责 |
|------|------|
| `mitm_tests.rs` | MITM 策略测试 |

### 4.5 关键函数路径

```
策略评估核心:
├── network_policy.rs:289-359   evaluate_host_policy() - 主策略评估函数
├── runtime.rs:337-402          host_blocked() - 主机阻止检查
├── policy.rs:154-179           compile_globset() - 模式编译
└── policy.rs:44-97             is_non_public_ip() - IP 分类

HTTP 代理处理:
├── http_proxy.rs:152-315       http_connect_accept() - CONNECT 处理
├── http_proxy.rs:317-376       http_connect_proxy() - 隧道代理
├── http_proxy.rs:423-747       http_plain_proxy() - 普通 HTTP 代理
└── http_proxy.rs:749-775       proxy_via_unix_socket() - Unix Socket 代理

SOCKS5 代理处理:
├── socks5.rs:132-294           handle_socks5_tcp() - TCP 处理
└── socks5.rs:296-451           inspect_socks5_udp() - UDP 处理

MITM 实现:
├── mitm.rs:117-181             mitm_tunnel() - MITM 隧道入口
├── mitm.rs:183-195             handle_mitm_request() - MITM 请求处理
├── mitm.rs:245-331             mitm_blocking_response() - MITM 策略检查
└── certs.rs:38-64              ManagedMitmCa::load_or_create() - CA 管理

配置管理:
├── runtime.rs:625-649          reload_if_needed() - 热重载检测
├── state.rs:57-84              build_config_state() - 状态构建
└── state.rs:86-365             validate_policy_against_constraints() - 约束验证
```

---

## 5. 依赖与外部交互

### 5.1 外部依赖

| Crate | 版本 | 用途 |
|-------|------|------|
| `rama-*` | 0.3.0-alpha.4 | 代理服务器框架（HTTP、SOCKS5、TLS、TCP） |
| `globset` | workspace | 域名模式匹配 |
| `tokio` | workspace | 异步运行时 |
| `serde` | workspace | 配置序列化 |
| `anyhow` | workspace | 错误处理 |
| `async-trait` | workspace | 异步 trait |
| `chrono` | workspace | 时间戳处理 |
| `time` | workspace | Unix 时间戳 |
| `tracing` | workspace | 日志和审计 |
| `url` | workspace | URL 解析 |
| `thiserror` | workspace | 错误类型定义 |

### 5.2 内部依赖

| Crate | 用途 |
|-------|------|
| `codex-utils-absolute-path` | 绝对路径处理（Unix Socket） |
| `codex-utils-home-dir` | 查找 CODEX_HOME 目录 |
| `codex-utils-rustls-provider` | rustls 加密提供程序初始化 |

### 5.3 调用方（上游）

| 模块 | 文件 | 用途 |
|------|------|------|
| `codex-core` | `network_proxy_loader.rs` | 配置加载、状态构建、热重载 |
| `codex-core` | `network_policy_decision.rs` | 决策转换、审批上下文 |
| `codex-core` | `sandboxing/mod.rs` | 沙箱集成 |
| `codex-core` | `spawn.rs` | 子进程代理环境注入 |
| `codex-core` | `exec.rs` | 执行时网络策略 |

### 5.4 配置集成

配置通过 `codex-core` 的 `ConfigLayerStack` 加载：

```
配置层级（从低到高优先级）：
1. System 配置 (/etc/codex/config.toml)
2. User 配置 (~/.codex/config.toml)
3. Project 配置 (./.codex/config.toml)
4. Session 标志（命令行）
5. Exec Policy（执行策略文件）
```

**约束机制**：
- 非用户控制的配置层（如系统管理配置）可以设置约束
- 约束限制用户能否修改特定设置（如不能扩大允许列表）
- 实现多租户/企业场景下的策略锁定

---

## 6. 风险、边界与改进建议

### 6.1 安全风险与缓解

| 风险 | 严重性 | 现状 | 缓解措施 |
|------|--------|------|----------|
| **DNS Rebinding** | 中 | 部分缓解 | DNS 解析检查，但存在 TOCTOU 窗口 |
| **MITM CA 泄露** | 高 | 已缓解 | 私钥权限 0o600，拒绝符号链接，原子写入 |
| **Unix Socket 遍历** | 中 | 已缓解 | 仅 macOS，强制绝对路径，启用后强制 loopback |
| **全局通配符绕过** | 高 | 已缓解 | 明确拒绝 `*` 模式 |
| **配置竞态条件** | 低 | 已缓解 | 配置更新使用 compare-and-swap 模式 |
| **内存耗尽** | 低 | 已缓解 | 阻止请求缓冲区限制（MAX_BLOCKED_EVENTS = 200） |

### 6.2 已知限制

1. **Limited 模式 HTTPS 限制**：
   - 无 MITM 时，CONNECT 隧道完全无法限制内部方法
   - 有 MITM 时，需要客户端信任自签名 CA

2. **平台限制**：
   - Unix Socket 代理仅 macOS 支持
   - 某些功能（如 `GIT_SSH_COMMAND`）仅 macOS

3. **DNS 解析窗口**：
   ```rust
   // runtime.rs:696-716
   async fn host_resolves_to_non_public_ip(host: &str, port: u16) -> bool {
       // DNS 解析和连接之间存在时间窗口
       // 恶意 DNS 服务器可能在检查时返回公共 IP，连接时返回私有 IP
   }
   ```

4. **上游代理信任**：
   - 当 `allow_upstream_proxy = true` 时，信任系统环境变量中的代理设置
   - 可能存在代理绕过或劫持风险

### 6.3 改进建议

#### 6.3.1 高优先级

1. **DNS Pinning（DNS 固定）**
   ```rust
   // 建议：在连接时验证 IP 与策略评估时一致
   pub struct PinnedConnection {
       original_resolution: Vec<IpAddr>,
       target: SocketAddr,
   }
   ```

2. **连接级策略执行**
   - 当前策略在应用层（HTTP/SOCKS5）评估
   - 建议在网络层（socket 连接前）再次验证目标 IP

3. **MITM CA 轮换**
   - 当前 CA 证书长期有效
   - 建议定期轮换，或支持外部 PKI 集成

#### 6.3.2 中优先级

4. **增强审计**
   - 当前审计不包含请求体/响应体大小（仅 MITM 模式下有）
   - 建议添加流量统计（字节数、连接时长）

5. **性能优化**
   - `host_blocked()` 每次调用都获取读锁
   - 建议对高频访问的域名添加 LRU 缓存

6. **IPv6 支持完善**
   - 当前 IPv6 处理在某些边界情况下可能不完整
   - 建议增加更多 IPv6 测试用例

#### 6.3.3 低优先级

7. **跨平台 Unix Socket**
   - 当前仅 macOS 支持
   - Linux 可通过类似机制实现

8. **WebSocket 原生支持**
   - 当前 WebSocket 通过 CONNECT 隧道处理
   - 可考虑原生支持以实施更细粒度的策略

9. **gRPC 支持**
   - HTTP/2 特定的协议支持
   - 可能需要特定的消息检查能力

### 6.4 测试覆盖分析

| 模块 | 测试类型 | 覆盖度 | 缺口 |
|------|----------|--------|------|
| `policy.rs` | 单元测试 | 高 | IPv6 边界情况 |
| `runtime.rs` | 单元测试 | 高 | 并发配置更新竞态 |
| `http_proxy.rs` | 集成测试 | 中 | 大规模并发连接 |
| `socks5.rs` | 集成测试 | 中 | UDP 中继压力测试 |
| `mitm.rs` | 单元测试 | 中 | 证书轮换、复杂 TLS 场景 |
| `certs.rs` | 单元测试 | 高 | 文件系统错误恢复 |

---

## 7. 总结

`codex-network-proxy` 是一个设计精良的网络安全代理，通过多层防御机制保护 AI 代码执行环境：

1. **策略层**：白名单/黑名单、模式匹配、DNS 检查
2. **传输层**：HTTP/SOCKS5 双协议、TLS MITM（可选）
3. **平台层**：Unix Socket 限制、本地网络保护
4. **审计层**：结构化日志、OTEL 兼容、可观测性

该 crate 的安全模型以**默认拒绝**为核心，通过显式授权降低 AI 代理的潜在攻击面。在企业/多租户场景中，约束机制确保管理员可以锁定关键安全设置。

**关键成功因素**：
- 与 Rama 框架的深度集成，获得生产级代理能力
- 配置热重载支持，无需重启即可更新策略
- 丰富的审计日志，满足合规要求
- 多层防御（DNS、IP、域名、方法）降低单点失效风险
