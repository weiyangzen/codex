# network_approval.rs 研究文档

## 场景与职责

`network_approval.rs` 是 Codex 工具系统的网络访问审批管理模块，负责处理工具执行过程中的网络访问权限请求。它实现了完整的网络访问审批流程，包括：

1. **即时审批 (Immediate)**：同步等待用户决策
2. **延迟审批 (Deferred)**：异步记录审批结果，稍后处理

该模块是 Codex 安全模型的关键组件，确保网络访问符合用户配置的策略。

## 功能点目的

### 1. 审批模式 (`NetworkApprovalMode`)
定义网络审批的执行模式：
- `Immediate`：同步等待审批决策
- `Deferred`：异步记录，稍后统一处理

### 2. 网络审批规范 (`NetworkApprovalSpec`)
封装网络审批的配置：
- `network`：可选的网络代理配置
- `mode`：审批模式

### 3. 主机审批键 (`HostApprovalKey`)
唯一标识需要审批的网络目标：
- `host`：主机名（小写）
- `protocol`：协议（http/https/socks5-tcp/socks5-udp）
- `port`：端口号

### 4. 网络审批服务 (`NetworkApprovalService`)
核心服务，管理审批状态：
- 活动调用跟踪（`active_calls`）
- 调用结果记录（`call_outcomes`）
- 待处理审批管理（`pending_host_approvals`）
- 会话级批准/拒绝缓存（`session_approved_hosts` / `session_denied_hosts`）

### 5. 审批生命周期管理
- `begin_network_approval`：开始网络审批流程
- `finish_immediate_network_approval`：完成即时审批
- `finish_deferred_network_approval`：完成延迟审批

## 具体技术实现

### 关键数据结构

```rust
// 审批模式
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum NetworkApprovalMode {
    Immediate,
    Deferred,
}

// 审批规范
#[derive(Clone, Debug)]
pub(crate) struct NetworkApprovalSpec {
    pub network: Option<NetworkProxy>,
    pub mode: NetworkApprovalMode,
}

// 延迟审批句柄
#[derive(Clone, Debug)]
pub(crate) struct DeferredNetworkApproval {
    registration_id: String,
}

// 活动审批
#[derive(Debug)]
pub(crate) struct ActiveNetworkApproval {
    registration_id: Option<String>,
    mode: NetworkApprovalMode,
}

// 主机审批键（用于去重和缓存）
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
struct HostApprovalKey {
    host: String,
    protocol: &'static str,
    port: u16,
}

// 待处理审批
struct PendingHostApproval {
    decision: Mutex<Option<PendingApprovalDecision>>,
    notify: Notify,
}

// 审批决策
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum PendingApprovalDecision {
    AllowOnce,
    AllowForSession,
    Deny,
}

// 审批结果
#[derive(Clone, Debug, Eq, PartialEq)]
enum NetworkApprovalOutcome {
    DeniedByUser,
    DeniedByPolicy(String),
}

// 核心服务
pub(crate) struct NetworkApprovalService {
    active_calls: Mutex<IndexMap<String, Arc<ActiveNetworkApprovalCall>>>,
    call_outcomes: Mutex<HashMap<String, NetworkApprovalOutcome>>,
    pending_host_approvals: Mutex<HashMap<HostApprovalKey, Arc<PendingHostApproval>>>,
    session_approved_hosts: Mutex<HashSet<HostApprovalKey>>,
    session_denied_hosts: Mutex<HashSet<HostApprovalKey>>,
}
```

### 核心流程

#### 1. 内联策略请求处理 (`handle_inline_policy_request`)
```
NetworkPolicyRequest → NetworkDecision
    ├── 检查 session_denied_hosts → 直接拒绝
    ├── 检查 session_approved_hosts → 直接允许
    ├── 检查 pending_host_approvals → 等待现有审批
    └── 创建新审批流程
        ├── 获取活跃 Turn 上下文
        ├── 检查 approval_policy
        ├── 路由到 Guardian 或本地审批
        ├── 处理用户决策
        │   ├── Approved → AllowOnce
        │   ├── ApprovedForSession → 缓存并允许
        │   ├── NetworkPolicyAmendment → 持久化策略
        │   └── Denied → 记录拒绝
        └── 清理 pending_approvals
```

#### 2. 审批决策映射
```rust
impl PendingApprovalDecision {
    fn to_network_decision(self) -> NetworkDecision {
        match self {
            Self::AllowOnce | Self::AllowForSession => NetworkDecision::Allow,
            Self::Deny => NetworkDecision::deny("not_allowed"),
        }
    }
}
```

#### 3. 会话主机同步
```rust
pub(crate) async fn sync_session_approved_hosts_to(&self, other: &Self) {
    // 将源会话的批准主机复制到目标会话
    // 用于会话恢复或迁移场景
}
```

#### 4. 阻塞请求记录
```rust
pub(crate) async fn record_blocked_request(&self, blocked: BlockedRequest) {
    // 将策略拒绝记录为调用结果
    // 用于后续向用户展示拒绝原因
}
```

### 关键代码路径

| 类型/函数 | 行号 | 职责 |
|-----------|------|------|
| `NetworkApprovalMode` | 33-37 | 审批模式枚举 |
| `NetworkApprovalSpec` | 39-43 | 审批规范结构 |
| `DeferredNetworkApproval` | 45-54 | 延迟审批句柄 |
| `ActiveNetworkApproval` | 56-75 | 活动审批结构 |
| `HostApprovalKey` | 77-92 | 主机审批键 |
| `PendingApprovalDecision` | 103-128 | 审批决策枚举 |
| `NetworkApprovalOutcome` | 110-114 | 审批结果枚举 |
| `PendingHostApproval` | 130-160 | 待处理审批结构 |
| `NetworkApprovalService` | 167-185 | 核心服务结构 |
| `sync_session_approved_hosts_to` | 188-195 | 会话主机同步 |
| `handle_inline_policy_request` | 288-516 | 主处理逻辑 |
| `build_blocked_request_observer` | 519-528 | 构建阻塞请求观察者 |
| `build_network_policy_decider` | 530-546 | 构建策略决策器 |
| `begin_network_approval` | 548-570 | 开始审批流程 |
| `finish_immediate_network_approval` | 572-599 | 完成即时审批 |
| `finish_deferred_network_approval` | 601-613 | 完成延迟审批 |

### 审批 ID 生成
```rust
fn approval_id_for_key(key: &HostApprovalKey) -> String {
    format!("network#{}#{}#{}", key.protocol, key.host, key.port)
}
// 示例: "network#https#example.com#443"
```

### 网络目标格式化
```rust
fn format_network_target(protocol: &str, host: &str, port: u16) -> String {
    format!("{protocol}://{host}:{port}")
}
// 示例: "https://example.com:443"
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::codex::Session` | 会话上下文 |
| `crate::guardian::*` | Guardian 审批集成 |
| `crate::network_policy_decision::*` | 网络策略决策 |

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_network_proxy::*` | 网络代理和决策类型 |
| `codex_protocol::approvals::*` | 审批协议类型 |
| `codex_protocol::protocol::*` | 协议事件类型 |
| `indexmap::IndexMap` | 有序映射（保持插入顺序）|
| `tokio::sync::{Mutex, Notify, RwLock}` | 异步同步原语 |
| `uuid::Uuid` | 生成唯一注册 ID |

### 调用关系

```
工具编排器 (orchestrator.rs)
    └── begin_network_approval
        └── NetworkApprovalService::register_call
            
工具运行时 (runtimes/)
    └── 网络请求
        └── NetworkPolicyDecider (通过 build_network_policy_decider 构建)
            └── NetworkApprovalService::handle_inline_policy_request
                ├── 检查缓存
                ├── 创建 PendingHostApproval
                └── 等待用户决策
                    ├── Guardian 审批
                    └── 本地审批 (request_command_approval)
        
网络代理 (codex_network_proxy)
    └── 阻塞请求
        └── BlockedRequestObserver (通过 build_blocked_request_observer 构建)
            └── NetworkApprovalService::record_blocked_request
```

## 风险、边界与改进建议

### 已知风险

1. **内存泄漏风险**
   - `active_calls` 使用 `IndexMap`，如果 `unregister_call` 未被调用，可能导致内存泄漏
   - 建议：添加超时清理机制

2. **并发竞争风险**
   - `pending_host_approvals` 的获取和插入不是原子操作
   - 多个并发请求同一主机时可能创建多个 `PendingHostApproval`

3. **策略变更不生效**
   - `session_approved_hosts` 和 `session_denied_hosts` 在会话期间持久存在
   - 如果策略中途变更，已缓存的决策不会失效

4. **单活动调用假设**
   ```rust
   async fn resolve_single_active_call(&self) -> Option<Arc<ActiveNetworkApprovalCall>> {
       let active_calls = self.active_calls.lock().await;
       if active_calls.len() == 1 {
           return active_calls.values().next().cloned();
       }
       None
   }
   ```
   当有多个活动调用时，阻塞请求无法归因到具体调用。

### 边界情况

| 场景 | 处理方式 |
|------|----------|
| 无活跃 Turn | 拒绝并清理 pending |
| approval_policy = Never | 直接拒绝 |
| 用户拒绝后策略拒绝 | 优先保留用户拒绝结果 |
| 多个并发请求同一主机 | 共享 PendingHostApproval，等待者等待所有者决策 |
| 会话迁移 | 通过 `sync_session_approved_hosts_to` 复制批准缓存 |
| 无效注册 ID | `take_call_outcome` 返回 None |

### 改进建议

1. **添加超时机制**
   ```rust
   impl NetworkApprovalService {
       pub async fn cleanup_stale_calls(&self, max_age: Duration) {
           // 清理超过 max_age 的活动调用
       }
   }
   ```

2. **原子化 pending 创建**
   ```rust
   async fn get_or_create_pending_approval(
       &self,
       key: HostApprovalKey,
   ) -> (Arc<PendingHostApproval>, bool) {
       // 使用 entry API 或一次性锁操作
       let mut pending = self.pending_host_approvals.lock().await;
       match pending.entry(key) {
           Entry::Occupied(e) => (e.get().clone(), false),
           Entry::Vacant(e) => {
               let created = Arc::new(PendingHostApproval::new());
               e.insert(created.clone());
               (created, true)
           }
       }
   }
   ```

3. **策略版本控制**
   ```rust
   struct SessionNetworkState {
       approved_hosts: HashSet<HostApprovalKey>,
       denied_hosts: HashSet<HostApprovalKey>,
       policy_version: u64, // 新增
   }
   ```

4. **改进多调用场景**
   ```rust
   // 为每个网络请求关联具体调用
   struct PendingHostApproval {
       decision: Mutex<Option<PendingApprovalDecision>>,
       notify: Notify,
       owner_call_id: String, // 新增
   }
   ```

5. **添加指标和日志**
   ```rust
   // 记录审批统计
   metrics.counter("codex.network_approval.requested", 1);
   metrics.counter("codex.network_approval.approved", 1);
   metrics.counter("codex.network_approval.denied", 1);
   metrics.gauge("codex.network_approval.pending", pending_count);
   ```

6. **支持更细粒度的策略**
   ```rust
   // 支持路径级别的策略
   struct HostApprovalKey {
       host: String,
       protocol: &'static str,
       port: u16,
       path_prefix: Option<String>, // 新增
   }
   ```

7. **添加测试覆盖**
   - 当前测试在 `network_approval_tests.rs`
   - 建议添加更多并发测试和超时测试

### 设计决策说明

1. **为何使用 `IndexMap` 而非 `HashMap`**
   - 保持调用注册顺序
   - 便于调试和日志记录
   - `shift_remove` 支持按 key 删除同时保持顺序

2. **为何分离 `Immediate` 和 `Deferred` 模式**
   - `Immediate`：同步等待，适合交互式场景
   - `Deferred`：异步处理，适合批量或后台场景

3. **为何缓存到会话级别**
   - 避免重复询问用户同一主机
   - 会话隔离保证安全性
   - 重启后重置，避免永久授权
