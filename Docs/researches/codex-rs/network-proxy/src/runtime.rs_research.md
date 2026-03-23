# runtime.rs 研究文档

## 场景与职责

`runtime.rs` 是 `codex-network-proxy` crate 的核心运行时模块，负责网络代理的状态管理、配置热重载、访问控制决策和审计日志记录。它是整个网络代理系统的"大脑"，协调配置、策略执行和监控。

### 核心职责

1. **配置状态管理**：维护网络代理的实时配置状态，支持动态重载
2. **访问控制决策**：评估主机是否被允许访问（基于 allowlist/denylist）
3. **审计与监控**：记录被阻止的请求，支持审计日志和实时监控
4. **策略约束验证**：确保配置变更符合管理策略约束
5. **Unix Socket 权限控制**：管理本地 Unix socket 的访问权限（macOS 专用）

## 功能点目的

### 1. NetworkProxyState - 核心状态管理器

```rust
pub struct NetworkProxyState {
    state: Arc<RwLock<ConfigState>>,
    reloader: Arc<dyn ConfigReloader>,
    blocked_request_observer: Arc<RwLock<Option<Arc<dyn BlockedRequestObserver>>>>,
    audit_metadata: NetworkProxyAuditMetadata,
}
```

**设计目的**：
- 使用 `RwLock` 实现并发安全的读写访问
- 通过 `ConfigReloader` trait 抽象配置来源，支持文件、内存等多种来源
- 支持动态配置重载，无需重启服务

### 2. 主机访问控制决策

```rust
pub async fn host_blocked(&self, host: &str, port: u16) -> Result<HostBlockDecision>
```

**决策优先级**（从高到低）：
1. **显式拒绝（denylist）**：如果主机匹配 denylist，直接拒绝
2. **本地/私有网络检查**：如果 `allow_local_binding=false`，检查主机是否为本地地址
3. **Allowlist 检查**：如果配置了 allowlist，只有匹配的主机才被允许

**DNS 安全检查**：
```rust
async fn host_resolves_to_non_public_ip(host: &str, port: u16) -> bool
```
- 对非 IP 地址执行 DNS 解析（2 秒超时）
- 检查解析结果是否包含私有/本地 IP
- 防止 DNS rebinding 攻击

### 3. 配置热重载机制

```rust
#[async_trait]
pub trait ConfigReloader: Send + Sync {
    fn source_label(&self) -> String;
    async fn maybe_reload(&self) -> Result<Option<ConfigState>>;
    async fn reload_now(&self) -> Result<ConfigState>;
}
```

**重载流程**：
1. 每次访问配置前调用 `reload_if_needed()`
2. `maybe_reload()` 检查配置是否变更
3. 如有变更，构建新的 `ConfigState` 并原子替换
4. 保留被阻止请求的历史记录

### 4. 被阻止请求的记录与通知

```rust
pub async fn record_blocked(&self, entry: BlockedRequest) -> Result<()>
```

**功能**：
- 维护最多 200 条被阻止请求的环形缓冲区（`MAX_BLOCKED_EVENTS`）
- 输出结构化日志：`CODEX_NETWORK_POLICY_VIOLATION {json}`
- 支持通过 `BlockedRequestObserver` trait 进行实时通知

### 5. 动态域名列表管理

```rust
pub async fn add_allowed_domain(&self, host: &str) -> Result<()>
pub async fn add_denied_domain(&self, host: &str) -> Result<()>
```

**特性**：
- 自动从对立列表中移除重复项
- 支持约束验证（防止扩展超出管理基线）
- 使用乐观并发控制（compare-and-swap 模式）

### 6. Unix Socket 权限控制（macOS 专用）

```rust
pub async fn is_unix_socket_allowed(&self, path: &str) -> Result<bool>
```

**安全检查**：
- 仅支持绝对路径
- 支持符号链接解析（canonicalization）
- 支持 `dangerously_allow_all_unix_sockets` 绕过检查

## 具体技术实现

### 关键数据结构

#### HostBlockDecision / HostBlockReason

```rust
pub enum HostBlockDecision {
    Allowed,
    Blocked(HostBlockReason),
}

pub enum HostBlockReason {
    Denied,           // 匹配 denylist
    NotAllowed,       // 不在 allowlist 中
    NotAllowedLocal,  // 本地/私有地址被禁止
}
```

#### ConfigState

```rust
pub struct ConfigState {
    pub config: NetworkProxyConfig,
    pub allow_set: GlobSet,      // 编译后的 allowlist glob 模式
    pub deny_set: GlobSet,       // 编译后的 denylist glob 模式
    pub mitm: Option<Arc<MitmState>>,
    pub constraints: NetworkProxyConstraints,
    pub blocked: VecDeque<BlockedRequest>,  // 被阻止请求历史
    pub blocked_total: u64,      // 总计数器
}
```

#### BlockedRequest

```rust
#[derive(Clone, Debug, Serialize)]
pub struct BlockedRequest {
    pub host: String,
    pub reason: String,
    pub client: Option<String>,
    pub method: Option<String>,
    pub mode: Option<NetworkMode>,
    pub protocol: String,
    pub decision: Option<String>,
    pub source: Option<String>,
    pub port: Option<u16>,
    pub timestamp: i64,
}
```

### 关键流程

#### 主机访问决策流程

```
host_blocked(host, port)
    ↓
解析 Host 字符串
    ↓
检查 deny_set 匹配？ → 是 → Blocked(Denied)
    ↓ 否
allow_local_binding=false？
    ↓ 是
检查本地/环回地址？ → 是 → 检查显式 allowlist → 否 → Blocked(NotAllowedLocal)
    ↓
DNS 解析检查私有 IP？ → 是 → Blocked(NotAllowedLocal)
    ↓
allowlist 为空？ → 是 → Blocked(NotAllowed)
    ↓
匹配 allow_set？ → 否 → Blocked(NotAllowed)
    ↓ 是
Allowed
```

#### 配置更新流程（以 add_allowed_domain 为例）

```
add_allowed_domain(host)
    ↓
解析并规范化主机名
    ↓
循环（乐观并发控制）：
    读取当前配置和约束
    检查是否已在目标列表中
    从对立列表移除
    添加到目标列表
    验证约束
    构建新 ConfigState
    比较并替换（CAS）
    成功则退出循环，失败则重试
```

### 安全相关实现

#### 本地地址检测

```rust
fn is_explicit_local_allowlisted(allowed_domains: &[String], host: &Host) -> bool
```

- 拒绝通配符模式（`*`, `*.`, `**.`）匹配本地地址
- 要求显式完整主机名匹配
- 防止意外开放本地服务访问

#### DNS 解析超时保护

```rust
const DNS_LOOKUP_TIMEOUT: Duration = Duration::from_secs(2);
```
- 防止 DNS 查询阻塞代理
- 解析失败默认视为"非本地"（fail-open 策略）

## 关键代码路径与文件引用

### 主要类型定义

| 类型 | 行号 | 说明 |
|------|------|------|
| `NetworkProxyAuditMetadata` | 41-52 | 审计元数据结构 |
| `HostBlockReason` | 54-69 | 阻止原因枚举 |
| `HostBlockDecision` | 77-81 | 访问决策枚举 |
| `BlockedRequest` | 83-98 | 被阻止请求记录 |
| `ConfigState` | 153-162 | 配置状态结构 |
| `ConfigReloader` | 164-174 | 配置重载 trait |
| `BlockedRequestObserver` | 176-179 | 阻止通知 trait |
| `NetworkProxyState` | 199-204 | 核心状态管理器 |

### 关键方法

| 方法 | 行号 | 说明 |
|------|------|------|
| `NetworkProxyState::with_reloader_*` | 226-272 | 构造方法族 |
| `host_blocked` | 337-402 | 主机访问决策 |
| `record_blocked` | 404-440 | 记录被阻止请求 |
| `is_unix_socket_allowed` | 460-510 | Unix socket 权限检查 |
| `add_allowed_domain` | 561-563 | 添加允许域名 |
| `add_denied_domain` | 565-567 | 添加拒绝域名 |
| `reload_if_needed` | 625-649 | 按需重载配置 |
| `host_resolves_to_non_public_ip` | 696-716 | DNS 安全检查 |

### 测试覆盖

| 测试函数 | 行号 | 测试场景 |
|----------|------|----------|
| `host_blocked_denied_wins_over_allowed` | 828-840 | denylist 优先 |
| `host_blocked_requires_allowlist_match` | 842-859 | allowlist 匹配 |
| `add_allowed_domain_removes_matching_deny_entry` | 862-877 | 列表互斥 |
| `host_blocked_rejects_loopback_when_local_binding_disabled` | 1093-1108 | 本地地址拒绝 |
| `unix_socket_allowlist_is_respected_on_macos` | 1599-1614 | Unix socket 权限 |

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::config::*` | 配置结构和验证 |
| `crate::policy::*` | 主机解析、globset 编译、IP 分类 |
| `crate::state::*` | 约束验证、ConfigState 构建 |
| `crate::mitm::MitmState` | MITM 状态管理 |
| `crate::reasons::*` | 阻止原因常量 |

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `anyhow` | 错误处理 |
| `async_trait` | 异步 trait 支持 |
| `globset` | Glob 模式匹配 |
| `serde` | 序列化（审计日志） |
| `time` | Unix 时间戳 |
| `tokio` | 异步运行时（`RwLock`, `timeout`, `lookup_host`） |
| `tracing` | 日志和审计 |
| `codex_utils_absolute_path` | 绝对路径处理 |

### 调用方

- `http_proxy.rs`：`host_blocked()`, `record_blocked()`, `method_allowed()`
- `socks5.rs`：`host_blocked()`, `record_blocked()`, `network_mode()`
- `proxy.rs`：`current_cfg()`, `add_allowed_domain()`, `add_denied_domain()`

## 风险、边界与改进建议

### 潜在风险

1. **DNS 解析阻塞**
   - 虽然设置了 2 秒超时，但大量并发请求仍可能导致资源竞争
   - 建议：考虑使用 LRU 缓存 DNS 结果

2. **配置重载竞争**
   - 乐观并发控制使用循环重试，极端情况下可能活锁
   - 建议：添加最大重试次数限制

3. **内存使用**
   - `blocked` 缓冲区固定 200 条，但每条记录包含多个 String
   - 建议：考虑使用 arena 分配或限制单个记录大小

4. **平台差异**
   - Unix socket 支持仅限 macOS，代码中有大量 `#[cfg(target_os = "macos")]`
   - 建议：考虑统一抽象，减少条件编译

### 边界情况

1. **IPv6 范围地址**：`fe80::1%lo0` 格式的 scoped IPv6 地址处理
2. **符号链接循环**：`is_unix_socket_allowed` 中的 `canonicalize` 可能遇到循环链接
3. **DNS 返回多个 IP**：`host_resolves_to_non_public_ip` 检查所有返回的地址
4. **空 allowlist**：表示"拒绝所有"而非"允许所有"

### 改进建议

1. **性能优化**
   - 添加 DNS 结果缓存（TTL 控制）
   - 使用 `dashmap` 替代 `RwLock<HashMap>` 提高并发性能

2. **可观测性**
   - 添加指标导出（被阻止请求数、决策延迟等）
   - 支持 OpenTelemetry 追踪

3. **安全增强**
   - 支持 CIDR 格式的 allowlist/denylist
   - 添加速率限制防止审计日志洪水

4. **代码质量**
   - `host_blocked` 方法较长（~65 行），可拆分为更小的函数
   - 部分逻辑重复（如本地地址检查），可提取共享函数
