# network_policy.rs 深度研究文档

## 场景与职责

`network_policy.rs` 是 Codex 网络代理的核心策略决策模块，负责评估网络请求是否符合安全策略，并决定是否允许或拒绝请求。该模块实现了网络请求的访问控制逻辑，包括：

1. **策略决策引擎**：基于配置的策略规则（允许列表/拒绝列表）评估网络请求
2. **审计日志记录**：记录所有策略决策事件，支持安全审计和合规性要求
3. **可扩展的决策机制**：支持通过 `NetworkPolicyDecider` trait 注入自定义决策逻辑
4. **多种网络协议支持**：支持 HTTP、HTTPS CONNECT、SOCKS5 TCP/UDP 等协议的策略评估

该模块是网络代理安全架构的核心组件，确保只有经过授权的网络请求才能通过代理。

## 功能点目的

### 1. 网络协议识别 (`NetworkProtocol`)

定义支持的四种网络协议：
- `Http`：普通 HTTP 代理请求
- `HttpsConnect`：HTTPS CONNECT 隧道请求
- `Socks5Tcp`：SOCKS5 TCP 代理
- `Socks5Udp`：SOCKS5 UDP 中继

每种协议映射到策略配置中的字符串标识，用于审计日志和策略匹配。

### 2. 策略决策类型 (`NetworkPolicyDecision`)

- `Deny`：明确拒绝请求
- `Ask`：请求需要用户确认（交互式决策）

### 3. 决策来源追踪 (`NetworkDecisionSource`)

追踪决策的来源，便于审计和故障排查：
- `BaselinePolicy`：基础策略（允许/拒绝列表）
- `ModeGuard`：网络模式保护（Limited/Full 模式）
- `ProxyState`：代理状态（启用/禁用）
- `Decider`：自定义决策器

### 4. 策略请求封装 (`NetworkPolicyRequest`)

封装策略评估所需的所有信息：
- 协议类型、目标主机、端口
- 客户端地址、HTTP 方法
- 命令信息、执行策略提示

### 5. 决策结果 (`NetworkDecision`)

- `Allow`：允许请求通过
- `Deny`：拒绝请求，包含原因、来源和决策类型

### 6. 审计事件系统

完整的审计日志记录机制：
- 域级别决策事件（基于主机的策略决策）
- 非域级别决策事件（如代理禁用、方法不允许等）
- 支持 OpenTelemetry 格式的结构化日志

### 7. 策略决策器 trait (`NetworkPolicyDecider`)

异步 trait 定义，允许注入自定义决策逻辑：
- 支持函数式实现（闭包）
- 支持 Arc 包装（共享决策器）
- 用于实现交互式策略覆盖（如用户确认对话框）

## 具体技术实现

### 核心决策流程 (`evaluate_host_policy`)

```rust
pub(crate) async fn evaluate_host_policy(
    state: &NetworkProxyState,
    decider: Option<&Arc<dyn NetworkPolicyDecider>>,
    request: &NetworkPolicyRequest,
) -> Result<NetworkDecision>
```

决策流程：

1. **主机阻塞检查**：调用 `state.host_blocked()` 检查主机是否被阻塞
   - 如果被拒绝列表匹配 → 返回 `Denied`
   - 如果不在允许列表 → 进入决策器逻辑
   - 如果允许 → 返回 `Allowed`

2. **决策器覆盖**：当主机被阻塞但提供了自定义决策器时
   - 调用 `decider.decide()` 获取决策
   - 如果决策器允许 → 标记为 `policy_override = true`
   - 保留原始阻塞原因用于审计

3. **审计事件发射**：无论决策结果如何，都记录审计事件
   - 域级别事件：针对具体主机的策略决策
   - 包含丰富的上下文信息（协议、端口、客户端、决策来源等）

### 审计事件结构

```rust
fn emit_policy_audit_event(state: &NetworkProxyState, args: PolicyAuditEventArgs<'_>) {
    tracing::event!(
        target: AUDIT_TARGET,  // "codex_otel.network_proxy"
        tracing::Level::INFO,
        event.name = POLICY_DECISION_EVENT_NAME,  // "codex.network_proxy.policy_decision"
        event.timestamp = %audit_timestamp(),
        // 元数据字段
        conversation.id = metadata.conversation_id.as_deref(),
        app.version = metadata.app_version.as_deref(),
        // 策略字段
        network.policy.scope = args.scope,        // "domain" | "non_domain"
        network.policy.decision = args.decision,  // "allow" | "deny" | "ask"
        network.policy.source = args.source,      // 决策来源
        network.policy.reason = args.reason,      // 拒绝原因
        network.policy.override = args.policy_override,  // 是否被覆盖
        // 网络字段
        network.transport.protocol = args.protocol.as_policy_protocol(),
        server.address = args.server_address,
        server.port = args.server_port,
        http.request.method = args.method.unwrap_or(DEFAULT_METHOD),
        client.address = args.client_addr.unwrap_or(DEFAULT_CLIENT_ADDRESS),
    );
}
```

### 测试支持模块

提供完整的测试基础设施：

1. **事件捕获器 (`EventCollector`)**：实现 `tracing::Subscriber` 捕获所有审计事件
2. **字段访问器 (`CapturedEvent`)**：便于测试断言验证特定字段值
3. **辅助函数**：`capture_events()`、`find_event_by_name()`

## 关键代码路径与文件引用

### 核心类型定义

| 类型 | 行号 | 描述 |
|------|------|------|
| `NetworkProtocol` | 22-28 | 网络协议枚举 |
| `NetworkPolicyDecision` | 41-55 | 策略决策枚举 |
| `NetworkDecisionSource` | 57-75 | 决策来源枚举 |
| `NetworkPolicyRequest` | 77-96 | 策略请求结构 |
| `NetworkDecision` | 121-129 | 决策结果枚举 |

### 核心函数

| 函数 | 行号 | 描述 |
|------|------|------|
| `evaluate_host_policy` | 289-359 | 主策略评估函数 |
| `emit_policy_audit_event` | 228-255 | 审计事件发射 |
| `emit_block_decision_audit_event` | 179-184 | 阻塞决策审计 |
| `emit_allow_decision_audit_event` | 186-191 | 允许决策审计 |
| `map_decider_decision` | 361-372 | 决策器结果映射 |

### 测试支持

| 类型/函数 | 行号 | 描述 |
|-----------|------|------|
| `CapturedEvent` | 395-405 | 捕获的事件结构 |
| `EventCollector` | 407-458 | 事件收集器实现 |
| `capture_events` | 509-519 | 事件捕获辅助函数 |
| `find_event_by_name` | 521-528 | 按名称查找事件 |

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::reasons` | 引入拒绝原因常量（REASON_POLICY_DENIED 等） |
| `crate::runtime` | `HostBlockDecision`、`HostBlockReason` |
| `crate::state` | `NetworkProxyState` |

### 外部 crate 依赖

| crate | 用途 |
|-------|------|
| `anyhow` | 错误处理 |
| `async_trait` | 异步 trait 支持 |
| `chrono` | 时间戳生成（RFC3339） |
| `tracing` | 结构化日志和审计事件 |

### 调用方

1. **`http_proxy.rs`**：
   - `http_connect_accept()`：评估 HTTPS CONNECT 请求
   - `http_plain_proxy()`：评估普通 HTTP 请求

2. **`socks5.rs`**：
   - `handle_socks5_tcp()`：评估 SOCKS5 TCP 连接
   - `inspect_socks5_udp()`：评估 SOCKS5 UDP 中继

### 被调用方

- `NetworkProxyState::host_blocked()`：检查主机是否被阻塞
- 自定义 `NetworkPolicyDecider` 实现（如 TUI 中的交互式确认）

## 风险、边界与改进建议

### 潜在风险

1. **DNS 重绑定攻击**：
   - 当前实现依赖 `host_blocked()` 中的 DNS 解析来检测本地/私有 IP
   - DNS 查询超时为 2 秒，可能被利用进行定时攻击
   - 建议：考虑缓存 DNS 结果或增加更严格的验证

2. **审计日志伪造**：
   - 审计事件依赖于 `tracing` 基础设施
   - 如果 tracing 配置不当，可能丢失审计事件
   - 建议：确保审计事件有独立的日志通道

3. **决策器性能**：
   - 自定义决策器是异步的，可能阻塞请求处理
   - 建议：为决策器调用添加超时机制

### 边界情况

1. **空主机名**：
   - `Host::parse()` 可能失败，导致请求被阻塞
   - 已在调用方处理（如 `http_proxy.rs` 中的验证）

2. **IPv6 范围 ID**：
   - 支持 `fe80::1%lo0` 格式的范围 ID
   - 在 `is_loopback_host()` 中正确处理

3. **大写/小写主机名**：
   - 通过 `normalize_host()` 统一处理为小写

### 改进建议

1. **性能优化**：
   - 考虑对 `host_blocked()` 结果进行缓存，减少重复的 DNS 查询
   - 使用 LRU 缓存存储最近的主机决策结果

2. **可观测性**：
   - 添加决策延迟的指标（histogram）
   - 记录决策器调用的成功率

3. **安全增强**：
   - 为自定义决策器添加超时和熔断机制
   - 考虑添加速率限制，防止审计日志被淹没

4. **代码简化**：
   - `NetworkPolicyRequest` 和 `NetworkPolicyRequestArgs` 结构可以合并简化
   - 审计事件字段可以通过宏生成，减少重复代码

### 测试覆盖

该模块有完善的测试覆盖（约 300 行测试代码），包括：
- 决策器覆盖场景
- 基础策略拒绝场景
- 审计事件字段验证
- 元数据字段发射验证
- 非域级别事件发射

建议添加：
- 并发决策压力测试
- 决策器超时场景测试
- DNS 重绑定攻击模拟测试
