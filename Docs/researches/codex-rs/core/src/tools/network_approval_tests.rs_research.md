# network_approval_tests.rs 研究文档

## 场景与职责

`network_approval_tests.rs` 是 `network_approval.rs` 的配套测试模块，负责验证网络访问审批服务的核心功能。测试覆盖了审批去重、会话缓存、并发等待、决策映射等关键场景。

## 功能点目的

### 测试覆盖范围

1. **审批去重测试**
   - 同一主机、协议、端口的请求应共享审批
   - 不同端口的请求应独立审批

2. **会话缓存测试**
   - 批准的会话主机应正确缓存
   - 会话主机同步应正确工作

3. **并发等待测试**
   - 等待者应收到所有者的决策

4. **决策映射测试**
   - 各种决策到网络决策的映射

5. **策略配置测试**
   - 不同 approval policy 对审批流程的影响

6. **阻塞请求记录测试**
   - 策略拒绝应正确记录为调用结果
   - 用户拒绝应优先于策略拒绝
   - 多调用场景下不应错误归因

## 具体技术实现

### 测试用例详情

#### 1. `pending_approvals_are_deduped_per_host_protocol_and_port`
```rust
let service = NetworkApprovalService::default();
let key = HostApprovalKey {
    host: "example.com".to_string(),
    protocol: "http",
    port: 443,
};

let (first, first_is_owner) = service.get_or_create_pending_approval(key.clone()).await;
let (second, second_is_owner) = service.get_or_create_pending_approval(key).await;

assert!(first_is_owner);
assert!(!second_is_owner);
assert!(Arc::ptr_eq(&first, &second));
```
**验证点**：
- 同一 key 的第一次创建返回 `is_owner = true`
- 同一 key 的后续获取返回 `is_owner = false`
- 返回的 `Arc` 指向同一对象

#### 2. `pending_approvals_do_not_dedupe_across_ports`
```rust
let first_key = HostApprovalKey {
    host: "example.com".to_string(),
    protocol: "https",
    port: 443,
};
let second_key = HostApprovalKey {
    host: "example.com".to_string(),
    protocol: "https",
    port: 8443,
};

let (first, first_is_owner) = service.get_or_create_pending_approval(first_key).await;
let (second, second_is_owner) = service.get_or_create_pending_approval(second_key).await;

assert!(first_is_owner);
assert!(second_is_owner);
assert!(!Arc::ptr_eq(&first, &second));
```
**验证点**：
- 不同端口创建独立的审批对象
- 两者都是所有者

#### 3. `session_approved_hosts_preserve_protocol_and_port_scope`
```rust
// 在源服务中添加多个批准主机（不同协议和端口）
let source = NetworkApprovalService::default();
source.session_approved_hosts.lock().await.extend([
    HostApprovalKey { host: "example.com", protocol: "https", port: 443 },
    HostApprovalKey { host: "example.com", protocol: "https", port: 8443 },
    HostApprovalKey { host: "example.com", protocol: "http", port: 80 },
]);

// 同步到目标服务
let seeded = NetworkApprovalService::default();
source.sync_session_approved_hosts_to(&seeded).await;

// 验证所有主机都被复制
```
**验证点**：
- 同步复制所有批准的 host + protocol + port 组合
- 保持完整的粒度

#### 4. `sync_session_approved_hosts_to_replaces_existing_target_hosts`
```rust
// 源服务有 source.example.com:443
// 目标服务有 stale.example.com:8443
// 同步后目标服务应只有 source.example.com:443
```
**验证点**：
- 同步是替换而非合并
- 目标服务的旧缓存被清除

#### 5. `pending_waiters_receive_owner_decision`
```rust
let pending = Arc::new(PendingHostApproval::new());

let waiter = tokio::spawn(async move {
    pending.wait_for_decision().await
});

pending.set_decision(PendingApprovalDecision::AllowOnce).await;

let decision = waiter.await.expect("waiter should complete");
assert_eq!(decision, PendingApprovalDecision::AllowOnce);
```
**验证点**：
- 等待者正确等待决策
- 决策设置后等待者立即收到通知
- 收到的决策与设置的决策一致

#### 6. `allow_once_and_allow_for_session_both_allow_network`
```rust
assert_eq!(
    PendingApprovalDecision::AllowOnce.to_network_decision(),
    NetworkDecision::Allow
);
assert_eq!(
    PendingApprovalDecision::AllowForSession.to_network_decision(),
    NetworkDecision::Allow
);
```
**验证点**：
- 两种允许决策都映射为 `NetworkDecision::Allow`

#### 7. `only_never_policy_disables_network_approval_flow`
```rust
assert!(!allows_network_approval_flow(AskForApproval::Never));
assert!(allows_network_approval_flow(AskForApproval::OnRequest));
assert!(allows_network_approval_flow(AskForApproval::OnFailure));
assert!(allows_network_approval_flow(AskForApproval::UnlessTrusted));
```
**验证点**：
- 只有 `Never` 策略禁用审批流程
- 其他策略都允许审批流程

#### 8. `record_blocked_request_sets_policy_outcome_for_owner_call`
```rust
let service = NetworkApprovalService::default();
service.register_call("registration-1".to_string(), "turn-1".to_string()).await;

service.record_blocked_request(denied_blocked_request("example.com")).await;

assert_eq!(
    service.take_call_outcome("registration-1").await,
    Some(NetworkApprovalOutcome::DeniedByPolicy(
        "Network access to \"example.com\" was blocked: ...".to_string()
    ))
);
```
**验证点**：
- 阻塞请求记录为策略拒绝
- 消息包含主机名

#### 9. `blocked_request_policy_does_not_override_user_denial_outcome`
```rust
// 先记录用户拒绝
service.record_call_outcome("registration-1", NetworkApprovalOutcome::DeniedByUser).await;
// 再记录策略拒绝
service.record_blocked_request(denied_blocked_request("example.com")).await;

// 用户拒绝应保留
assert_eq!(
    service.take_call_outcome("registration-1").await,
    Some(NetworkApprovalOutcome::DeniedByUser)
);
```
**验证点**：
- 用户拒绝优先于策略拒绝
- 策略拒绝不会覆盖已存在的用户拒绝

#### 10. `record_blocked_request_ignores_ambiguous_unattributed_blocked_requests`
```rust
// 注册两个活动调用
service.register_call("registration-1".to_string(), "turn-1".to_string()).await;
service.register_call("registration-2".to_string(), "turn-1".to_string()).await;

// 记录阻塞请求
service.record_blocked_request(denied_blocked_request("example.com")).await;

// 两个调用都不应有结果
assert_eq!(service.take_call_outcome("registration-1").await, None);
assert_eq!(service.take_call_outcome("registration-2").await, None);
```
**验证点**：
- 多调用场景下不错误归因
- 避免将策略拒绝关联到错误调用

## 关键代码路径与文件引用

| 测试函数 | 被测函数/类型 | 所在文件 |
|----------|--------------|----------|
| `pending_approvals_are_deduped_per_host_protocol_and_port` | `get_or_create_pending_approval` | network_approval.rs:225 |
| `pending_approvals_do_not_dedupe_across_ports` | `get_or_create_pending_approval` | network_approval.rs:225 |
| `session_approved_hosts_preserve_protocol_and_port_scope` | `sync_session_approved_hosts_to` | network_approval.rs:188 |
| `sync_session_approved_hosts_to_replaces_existing_target_hosts` | `sync_session_approved_hosts_to` | network_approval.rs:188 |
| `pending_waiters_receive_owner_decision` | `PendingHostApproval::wait_for_decision` | network_approval.rs:143 |
| `allow_once_and_allow_for_session_both_allow_network` | `PendingApprovalDecision::to_network_decision` | network_approval.rs:122 |
| `only_never_policy_disables_network_approval_flow` | `allows_network_approval_flow` | network_approval.rs:117 |
| `record_blocked_request_sets_policy_outcome_for_owner_call` | `record_blocked_request` | network_approval.rs:263 |
| `blocked_request_policy_does_not_override_user_denial_outcome` | `record_call_outcome` | network_approval.rs:252 |
| `record_blocked_request_ignores_ambiguous_unattributed_blocked_requests` | `resolve_single_active_call` | network_approval.rs:216 |

## 依赖与外部交互

### 测试依赖

| 依赖 | 用途 |
|------|------|
| `super::*` | 被测模块的所有公有项 |
| `codex_network_proxy::BlockedRequestArgs` | 创建测试用的 BlockedRequest |
| `codex_protocol::protocol::AskForApproval` | 审批策略枚举 |
| `pretty_assertions::assert_eq` | 清晰的差异输出 |

### 辅助函数

```rust
fn denied_blocked_request(host: &str) -> BlockedRequest {
    BlockedRequest::new(BlockedRequestArgs {
        host: host.to_string(),
        reason: "not_allowed".to_string(),
        client: None,
        method: None,
        mode: None,
        protocol: "http".to_string(),
        decision: Some("deny".to_string()),
        source: Some("decider".to_string()),
        port: Some(80),
    })
}
```

## 风险、边界与改进建议

### 当前测试覆盖缺口

1. **未覆盖的审批模式**
   - `Immediate` 模式的完整流程
   - `Deferred` 模式的完整流程

2. **未覆盖的决策类型**
   - `NetworkPolicyAmendment` 的处理
   - `ApprovedExecpolicyAmendment` 的处理

3. **未覆盖的错误场景**
   - 无活跃 Turn 的处理
   - `approval_policy = Never` 的处理
   - Guardian 审批路径

4. **未覆盖的并发场景**
   - 多个并发请求不同主机
   - 审批超时场景
   - 决策设置前的取消

5. **未覆盖的缓存场景**
   - `session_denied_hosts` 的使用
   - 缓存命中后的快速路径

### 改进建议

1. **添加完整流程测试**
   ```rust
   #[tokio::test]
   async fn immediate_approval_flow_allows_after_user_approval() {
       // 模拟完整的即时审批流程
       // 验证用户批准后网络请求被允许
   }
   ```

2. **添加 Guardian 集成测试**
   ```rust
   #[tokio::test]
   async fn guardian_approval_path_records_outcome() {
       // 测试 routes_approval_to_guardian = true 的路径
       // 验证 Guardian 决策正确记录
   }
   ```

3. **添加并发压力测试**
   ```rust
   #[tokio::test]
   async fn concurrent_requests_to_same_host_share_approval() {
       // 并发发起 100 个同一主机的请求
       // 验证只创建一个 PendingHostApproval
       // 验证所有请求收到相同决策
   }
   ```

4. **添加超时测试**
   ```rust
   #[tokio::test]
   async fn pending_approval_can_be_cancelled() {
       // 测试 PendingHostApproval 的取消机制
       // 验证取消后等待者收到错误
   }
   ```

5. **添加策略变更测试**
   ```rust
   #[tokio::test]
   async fn policy_amendment_persists_and_applies() {
       // 测试网络策略修正的持久化
       // 验证持久化后新请求使用修正后的策略
   }
   ```

6. **改进测试组织**
   ```rust
   mod pending_approval_tests { ... }
   mod session_cache_tests { ... }
   mod blocked_request_tests { ... }
   mod integration_tests { ... }
   ```

7. **添加性能基准测试**
   ```rust
   #[tokio::test]
   async fn approval_lookup_performance() {
       // 测试大量主机缓存下的查找性能
       let service = NetworkApprovalService::default();
       // 添加 10000 个缓存主机
       // 验证查找时间在可接受范围内
   }
   ```

### 测试风格建议

1. **使用表驱动测试**
   ```rust
   #[tokio::test]
   async fn various_policies_allow_or_deny_approval_flow() {
       let cases = vec![
           (AskForApproval::Never, false),
           (AskForApproval::OnRequest, true),
           (AskForApproval::OnFailure, true),
           (AskForApproval::UnlessTrusted, true),
       ];
       
       for (policy, expected) in cases {
           assert_eq!(allows_network_approval_flow(policy), expected);
       }
   }
   ```

2. **添加测试文档**
   ```rust
   /// Test that user denial takes precedence over policy denial.
   ///
   /// This ensures that when a user explicitly denies a request,
   /// subsequent policy blocks don't change the outcome to appear
   /// as if the user didn't make a choice.
   #[tokio::test]
   async fn blocked_request_policy_does_not_override_user_denial_outcome() {
       // ...
   }
   ```

3. **使用测试固件 (fixtures)**
   ```rust
   async fn setup_service_with_active_call(registration_id: &str) -> NetworkApprovalService {
       let service = NetworkApprovalService::default();
       service.register_call(registration_id.to_string(), "turn-1".to_string()).await;
       service
   }
   ```
