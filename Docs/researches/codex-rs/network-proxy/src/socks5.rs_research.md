# socks5.rs 研究文档

## 场景与职责

`socks5.rs` 实现 SOCKS5 代理服务器功能，为 Codex 提供 TCP 和 UDP 流量的代理转发能力。它是网络代理系统的两大入口点之一（另一个是 HTTP 代理），负责处理通过 SOCKS5 协议发起的网络请求。

### 核心职责

1. **SOCKS5 协议实现**：基于 `rama-socks5` crate 构建 SOCKS5 服务器
2. **TCP 连接代理**：处理 SOCKS5 CONNECT 请求，建立到目标主机的 TCP 连接
3. **UDP 中继代理**：支持 SOCKS5 UDP ASSOCIATE，转发 UDP 数据包
4. **访问控制集成**：与网络策略系统集成，执行主机级别的访问控制
5. **审计日志记录**：记录所有访问决策到审计系统

## 功能点目的

### 1. SOCKS5 服务器启动

```rust
pub async fn run_socks5(
    state: Arc<NetworkProxyState>,
    addr: SocketAddr,
    policy_decider: Option<Arc<dyn NetworkPolicyDecider>>,
    enable_socks5_udp: bool,
) -> Result<()>
```

**设计目的**：
- 提供标准化的 SOCKS5 代理入口
- 支持可选的 UDP 中继（`enable_socks5_udp`）
- 集成策略决策器，支持动态访问控制

**变体**：
- `run_socks5_with_std_listener`：使用预创建的 TCP listener（用于端口预分配场景）
- `run_socks5_with_listener`：内部实现，统一处理逻辑

### 2. TCP 连接处理

```rust
async fn handle_socks5_tcp(
    req: TcpRequest,
    tcp_connector: TcpConnector,
    policy_decider: Option<Arc<dyn NetworkPolicyDecider>>,
) -> Result<EstablishedClientConnection<TcpStream, TcpRequest>, BoxError>
```

**处理流程**：
1. 提取目标主机和端口
2. 检查代理是否启用
3. 检查网络模式（Limited 模式拒绝 SOCKS5）
4. 执行主机策略评估
5. 建立 TCP 连接或返回拒绝错误

**Limited 模式限制**：
```rust
match app_state.network_mode().await {
    Ok(NetworkMode::Limited) => {
        // 拒绝 SOCKS5 连接
        // 原因：Limited 模式只允许 GET/HEAD/OPTIONS
        // SOCKS5 CONNECT 无法检查内部 HTTP 方法
    }
    ...
}
```

### 3. UDP 中继处理

```rust
async fn inspect_socks5_udp(
    request: RelayRequest,
    state: Arc<NetworkProxyState>,
    policy_decider: Option<Arc<dyn NetworkPolicyDecider>>,
) -> io::Result<RelayResponse>
```

**设计考虑**：
- UDP 无连接特性，需要在每个数据包层面做决策
- 使用 `DefaultUdpRelay` 的 `async_inspector` 机制
- 同样受 Limited 模式限制

### 4. 审计事件生成

```rust
fn emit_socks_block_decision_audit_event(
    state: &NetworkProxyState,
    source: NetworkDecisionSource,
    reason: &str,
    protocol: NetworkProtocol,
    host: &str,
    port: u16,
    client_addr: Option<&str>,
)
```

**审计字段**：
- 决策来源（ProxyState, ModeGuard, BaselinePolicy, Decider）
- 阻止原因
- 协议类型（Socks5Tcp / Socks5Udp）
- 目标地址和端口
- 客户端地址

## 具体技术实现

### 依赖的 Rama 组件

```rust
use rama_socks5::Socks5Acceptor;
use rama_socks5::server::DefaultConnector;
use rama_socks5::server::DefaultUdpRelay;
use rama_socks5::server::udp::{RelayRequest, RelayResponse};
use rama_tcp::TcpStream;
use rama_tcp::client::Request as TcpRequest;
use rama_tcp::client::service::TcpConnector;
use rama_tcp::server::TcpListener;
use rama_core::layer::AddInputExtensionLayer;
```

**Rama 架构理解**：
- `Socks5Acceptor`：SOCKS5 协议处理器，处理握手和请求解析
- `DefaultConnector`：默认的 TCP 连接建立器
- `AddInputExtensionLayer`：将 `NetworkProxyState` 注入到每个请求的 extensions 中

### 服务链构建

```rust
let tcp_connector = TcpConnector::default();
let policy_tcp_connector = service_fn({
    let policy_decider = policy_decider.clone();
    move |req: TcpRequest| {
        let tcp_connector = tcp_connector.clone();
        let policy_decider = policy_decider.clone();
        async move { handle_socks5_tcp(req, tcp_connector, policy_decider).await }
    }
});

let socks_connector = DefaultConnector::default().with_connector(policy_tcp_connector);
let base = Socks5Acceptor::new().with_connector(socks_connector);
```

**设计模式**：
- 使用 `service_fn` 将异步函数转换为 Rama `Service`
- 通过 `with_connector` 链式组装自定义连接逻辑
- 策略检查在连接建立前执行

### UDP 中继配置

```rust
if enable_socks5_udp {
    let udp_state = state.clone();
    let udp_decider = policy_decider.clone();
    let udp_relay = DefaultUdpRelay::default().with_async_inspector(service_fn({
        move |request: RelayRequest| {
            let udp_state = udp_state.clone();
            let udp_decider = udp_decider.clone();
            async move { inspect_socks5_udp(request, udp_state, udp_decider).await }
        }
    }));
    let socks_acceptor = base.with_udp_associator(udp_relay);
    ...
}
```

**关键机制**：
- `with_async_inspector` 允许异步检查每个 UDP 中继请求
- 返回 `RelayResponse` 控制是否允许转发

### 错误处理策略

```rust
fn policy_denied_error(reason: &str, details: &PolicyDecisionDetails<'_>) -> io::Error {
    io::Error::new(
        io::ErrorKind::PermissionDenied,
        blocked_message_with_policy(reason, details),
    )
}
```

- 将策略拒绝转换为标准 `io::Error`
- 使用 `PermissionDenied` 错误类型，符合 SOCKS5 协议语义
- 包含人类可读的错误信息

## 关键代码路径与文件引用

### 主要函数

| 函数 | 行号 | 说明 |
|------|------|------|
| `run_socks5` | 47-62 | 主入口，绑定到地址 |
| `run_socks5_with_std_listener` | 64-73 | 使用预创建 listener |
| `run_socks5_with_listener` | 75-130 | 核心实现 |
| `handle_socks5_tcp` | 132-294 | TCP 连接处理 |
| `inspect_socks5_udp` | 296-452 | UDP 中继检查 |
| `emit_socks_block_decision_audit_event` | 454-475 | 审计事件生成 |
| `policy_denied_error` | 477-482 | 错误构造 |

### 关键流程代码片段

#### TCP 处理中的决策链（行 154-291）

```rust
// 1. 检查代理启用状态
match app_state.enabled().await {
    Ok(true) => {}
    Ok(false) => { /* 记录并拒绝 */ }
    Err(err) => { /* 返回错误 */ }
}

// 2. 检查网络模式
match app_state.network_mode().await {
    Ok(NetworkMode::Limited) => { /* 拒绝 SOCKS5 */ }
    Ok(NetworkMode::Full) => {}
    Err(err) => { /* 返回错误 */ }
}

// 3. 主机策略评估
match evaluate_host_policy(&app_state, policy_decider.as_ref(), &request).await {
    Ok(NetworkDecision::Deny { ... }) => { /* 记录并拒绝 */ }
    Ok(NetworkDecision::Allow) => { /* 允许 */ }
    Err(err) => { /* 返回错误 */ }
}

// 4. 建立连接
tcp_connector.serve(req).await
```

#### UDP 检查（行 318-451）

UDP 检查逻辑与 TCP 类似，但：
- 操作的是 `RelayRequest` / `RelayResponse`
- 成功时返回原始 payload
- 失败时返回 `io::Error`

### 测试覆盖

| 测试函数 | 行号 | 测试场景 |
|----------|------|----------|
| `handle_socks5_tcp_emits_block_decision_for_proxy_disabled` | 537-571 | 代理禁用时的拒绝和审计 |
| `inspect_socks5_udp_emits_block_decision_for_mode_guard_deny` | 573-608 | Limited 模式 UDP 拒绝 |

**测试辅助结构**：
- `StaticReloader`：测试用的固定配置重载器
- `state_for_settings`：从设置快速创建测试状态

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::config::NetworkMode` | 网络模式检查 |
| `crate::network_policy::*` | 策略决策、审计事件 |
| `crate::policy::normalize_host` | 主机名规范化 |
| `crate::reasons::*` | 阻止原因常量 |
| `crate::responses::*` | 响应消息构造 |
| `crate::state::*` | 状态管理和阻止记录 |
| `crate::runtime::NetworkProxyState` | 核心状态 |

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `rama_core` | 核心服务抽象（`Layer`, `Service`, `BoxError`） |
| `rama_socks5` | SOCKS5 协议实现 |
| `rama_tcp` | TCP 连接和监听 |
| `rama_net` | 网络地址和连接抽象 |
| `anyhow` | 错误处理 |
| `async_trait` | 异步 trait |
| `tracing` | 日志记录 |

### 调用方

- `proxy.rs`：`run_socks5` / `run_socks5_with_std_listener`
- 通过 `NetworkProxy::run()` 启动 SOCKS5 服务

## 风险、边界与改进建议

### 潜在风险

1. **Limited 模式完全禁用 SOCKS5**
   - 当前实现：任何 SOCKS5 请求在 Limited 模式下都被拒绝
   - 风险：某些工具（如 curl、git）可能优先使用 SOCKS5
   - 缓解：HTTP 代理在 Limited 模式下可用，工具应回退到 HTTP 代理

2. **UDP 检查性能**
   - 每个 UDP 数据包都触发策略评估
   - 高频 UDP 流量可能导致性能瓶颈
   - 建议：考虑添加 UDP 流的缓存/会话机制

3. **错误信息泄露**
   - `policy_denied_error` 包含详细的阻止原因
   - 可能向客户端泄露内部策略信息
   - 建议：区分内部日志和对外错误信息

### 边界情况

1. **SOCKS5 认证**
   - 当前实现使用 `DefaultConnector`，无认证
   - 依赖本地环回绑定保证安全
   - 非环回绑定时需考虑添加认证

2. **IPv6 地址处理**
   - `normalize_host` 处理 IPv6 字面量
   - UDP `server_address.ip_addr` 直接解析为字符串

3. **DNS 解析时机**
   - SOCKS5 协议允许客户端发送域名
   - 策略评估在代理端解析域名
   - 与客户端解析结果可能不一致（DNS 污染场景）

### 改进建议

1. **功能增强**
   - 支持 SOCKS5 用户/密码认证（非环回场景）
   - 添加 UDP 会话缓存，减少重复策略评估
   - 支持 SOCKS5 BIND 命令（FTP 主动模式）

2. **性能优化**
   - 使用连接池复用目标连接
   - 评估是否可以使用零拷贝转发

3. **安全加固**
   - 限制单客户端并发连接数
   - 添加连接速率限制
   - 区分内部和外部错误信息

4. **可观测性**
   - 添加 SOCKS5 专用指标（连接数、字节数、延迟）
   - 支持连接级别的追踪 ID

5. **代码质量**
   - `handle_socks5_tcp` 和 `inspect_socks5_udp` 有大量重复逻辑
   - 建议提取共享的策略评估和审计记录函数
