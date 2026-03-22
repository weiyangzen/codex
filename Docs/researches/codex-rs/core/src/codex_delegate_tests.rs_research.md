# codex_delegate_tests.rs 深度研究文档

## 场景与职责

`codex_delegate_tests.rs` 是 `codex_delegate.rs` 的配套测试模块，采用 Rust 内联测试模式（`#[cfg(test)] #[path = "codex_delegate_tests.rs"] mod tests;`）。该测试文件专注于验证**子代理（Sub-agent）委托机制**的核心行为，包括：

1. **事件转发可靠性**：确保子代理事件能正确转发给父会话
2. **审批路由正确性**：验证 Guardian 自动审批与人工审批的路由逻辑
3. **取消传播机制**：测试取消令牌在父子代理间的正确传播
4. **上下文保持**：验证 trace 上下文在转发过程中不丢失

这些测试对于保障 Codex 的多层代理架构稳定性至关重要，特别是在 Guardian 自动审批这一安全关键路径上。

## 功能点目的

### 1. 取消时的事件转发关闭测试
**测试函数**：`forward_events_cancelled_while_send_blocked_shuts_down_delegate`

- **目的**：验证当取消令牌被触发且事件发送被阻塞时，子代理能正确关闭
- **关键验证点**：
  - `forward_events` 任务能正确响应取消信号
  - 子代理收到 `Interrupt` 和 `Shutdown` 操作
  - 预填充的事件能被正确接收

### 2. 操作转发的 Trace 上下文保持
**测试函数**：`forward_ops_preserves_submission_trace_context`

- **目的**：验证通过 `forward_ops` 转发的 `Submission` 保持 W3C trace 上下文
- **关键验证点**：
  - `traceparent` 和 `tracestate` 字段在转发后不丢失
  - 支持分布式追踪场景

### 3. 权限请求的 Round-trip
**测试函数**：`handle_request_permissions_uses_tool_call_id_for_round_trip`

- **目的**：验证权限请求能正确地从子代理流向父会话，再返回答复
- **关键验证点**：
  - `call_id` 在请求和响应中保持一致
  - 正确的 `Op::RequestPermissionsResponse` 被提交

### 4. Guardian 审批的 ID 分离
**测试函数**：`handle_exec_approval_uses_call_id_for_guardian_review_and_approval_id_for_reply`

- **目的**：验证 Guardian 评审使用 `call_id`，而审批响应使用 `approval_id`
- **关键验证点**：
  - `GuardianAssessmentEvent` 使用 `call_id` 作为 `id`
  - `Op::ExecApproval` 使用 `approval_id` 作为 `id`
  - 取消时正确返回 `ReviewDecision::Abort`

### 5. MCP Guardian 拒绝处理
**测试函数**：`delegated_mcp_guardian_abort_returns_synthetic_decline_answer`

- **目的**：验证当 Guardian 拒绝 MCP 工具调用时，返回合成的 decline 响应
- **关键验证点**：
  - 使用 `MCP_TOOL_APPROVAL_DECLINE_SYNTHETIC` 作为拒绝标识
  - 正确映射到 `RequestUserInputResponse` 结构

## 具体技术实现

### 测试基础设施

```rust
// 测试辅助：创建模拟的 Session 和 TurnContext
let (parent_session, parent_ctx, rx_events) = 
    crate::codex::make_session_and_context_with_rx().await;

// 创建模拟的 Codex 实例
let codex = Arc::new(Codex {
    tx_sub,           // 操作发送通道
    rx_event,         // 事件接收通道
    agent_status,     // 代理状态
    session,          // 会话引用
    session_loop_termination, // 会话终止信号
});
```

### 关键测试模式

#### 模式 1：事件驱动验证
```rust
// 等待特定事件
let request_event = timeout(Duration::from_secs(1), rx_events.recv())
    .await
    .expect("request_permissions event timed out")
    .expect("request_permissions event missing");

// 验证事件类型和内容
let EventMsg::RequestPermissions(request) = request_event.msg else {
    panic!("expected RequestPermissions event");
};
assert_eq!(request.call_id, call_id.clone());
```

#### 模式 2：操作拦截验证
```rust
// 接收子代理提交的操作
let submission = timeout(Duration::from_secs(1), rx_sub.recv())
    .await
    .expect("request_permissions response timed out")
    .expect("request_permissions response missing");

// 验证操作类型和字段
assert_eq!(
    submission.op,
    Op::RequestPermissionsResponse {
        id: call_id,
        response: expected_response,
    }
);
```

#### 模式 3：取消传播验证
```rust
// 创建取消令牌
let cancel = CancellationToken::new();

// 启动任务
let forward = tokio::spawn(forward_events(..., cancel.clone(), ...));

// 触发取消
cancel.cancel();

// 验证任务正确退出
timeout(Duration::from_millis(1000), forward)
    .await
    .expect("forward_events hung")
    .expect("forward_events join error");
```

### Guardian 测试的特殊配置

```rust
// 配置 Guardian 审批模式
let mut parent_ctx = Arc::try_unwrap(parent_ctx).expect("single turn context ref");
let mut config = (*parent_ctx.config).clone();
config.approvals_reviewer = ApprovalsReviewer::GuardianSubagent;
parent_ctx.config = Arc::new(config);
parent_ctx
    .approval_policy
    .set(AskForApproval::OnRequest)
    .expect("set on-request policy");
let parent_ctx = Arc::new(parent_ctx);
```

## 关键代码路径与文件引用

### 本文件测试函数

| 测试函数 | 行号 | 测试目标 |
|----------|------|----------|
| `forward_events_cancelled_while_send_blocked_shuts_down_delegate` | 35-107 | 取消时的事件转发 |
| `forward_ops_preserves_submission_trace_context` | 110-151 | Trace 上下文保持 |
| `handle_request_permissions_uses_tool_call_id_for_round_trip` | 154-239 | 权限请求 round-trip |
| `handle_exec_approval_uses_call_id_for_guardian_review_and_approval_id_for_reply` | 242-348 | Guardian 审批 ID 分离 |
| `delegated_mcp_guardian_abort_returns_synthetic_decline_answer` | 351-406 | MCP Guardian 拒绝 |

### 被测代码路径

```
codex_delegate_tests.rs
    测试调用
        ├──▶ codex_delegate.rs
        │       ├── forward_events()          [测试1]
        │       ├── forward_ops()             [测试2]
        │       ├── handle_request_permissions() [测试3]
        │       ├── handle_exec_approval()    [测试4]
        │       └── maybe_auto_review_mcp_request_user_input() [测试5]
        │
        └──▶ codex.rs (测试辅助)
                └── make_session_and_context_with_rx()
```

### 依赖的协议类型

```rust
// 来自 codex_protocol::protocol
codex_protocol::protocol::{
    AgentStatus,
    EventMsg,
    ExecApprovalRequestEvent,
    GuardianAssessmentEvent,
    GuardianAssessmentStatus,
    RawResponseItemEvent,
    ReviewDecision,
    TurnAbortReason,
    TurnAbortedEvent,
}

// 来自 codex_protocol::request_permissions
codex_protocol::request_permissions::{
    RequestPermissionProfile,
    RequestPermissionsEvent,
    RequestPermissionsResponse,
}

// 来自 codex_protocol::request_user_input
codex_protocol::request_user_input::{
    RequestUserInputAnswer,
    RequestUserInputEvent,
    RequestUserInputQuestion,
    RequestUserInputResponse,
}
```

## 依赖与外部交互

### 测试依赖的 Crate

| Crate | 用途 |
|-------|------|
| `tokio` | 异步测试运行时 (`#[tokio::test]`) |
| `async-channel` | 模拟通道 |
| `tokio::sync::watch` | 模拟状态通道 |
| `tokio::time::timeout` | 测试超时控制 |
| `pretty_assertions` | 更好的断言输出 |
| `serde_json` | JSON 构造 |

### 被测模块的依赖注入

测试通过以下方式实现依赖注入：

```rust
// 1. 使用 async_channel 替代真实通道
let (tx_sub, rx_sub) = bounded(SUBMISSION_CHANNEL_CAPACITY);
let (_tx_events, rx_events_child) = bounded(SUBMISSION_CHANNEL_CAPACITY);

// 2. 使用 watch channel 模拟 agent_status
let (_agent_status_tx, agent_status) = watch::channel(AgentStatus::PendingInit);

// 3. 使用测试辅助函数创建 Session
let (session, _ctx, _rx_evt) = crate::codex::make_session_and_context_with_rx().await;

// 4. 构造 Codex 实例进行测试
let codex = Arc::new(Codex {
    tx_sub,
    rx_event: rx_events_child,
    agent_status,
    session: Arc::clone(&parent_session),
    session_loop_termination: completed_session_loop_termination(),
});
```

## 风险、边界与改进建议

### 测试覆盖分析

| 功能点 | 覆盖状态 | 说明 |
|--------|----------|------|
| 事件转发取消 | ✅ 已覆盖 | `forward_events_cancelled_while_send_blocked_shuts_down_delegate` |
| Trace 上下文 | ✅ 已覆盖 | `forward_ops_preserves_submission_trace_context` |
| 权限请求 | ✅ 已覆盖 | `handle_request_permissions_uses_tool_call_id_for_round_trip` |
| Guardian 执行审批 | ✅ 已覆盖 | `handle_exec_approval_uses_call_id_for_guardian_review_and_approval_id_for_reply` |
| MCP Guardian 拒绝 | ✅ 已覆盖 | `delegated_mcp_guardian_abort_returns_synthetic_decline_answer` |
| 补丁审批 | ⚠️ 未覆盖 | `handle_patch_approval` 无直接测试 |
| 用户输入处理 | ⚠️ 部分覆盖 | 仅通过 MCP 场景间接测试 |
| 操作转发取消 | ⚠️ 未覆盖 | `forward_ops` 取消场景 |

### 边界条件测试

当前测试已覆盖的边界：
1. **超时处理**：使用 `timeout(Duration::from_secs(1), ...)` 验证异步操作不挂起
2. **取消传播**：验证取消令牌能正确终止 `forward_events`
3. **通道关闭**：`drop(tx_events)` 模拟子代理事件通道关闭

建议补充的边界测试：
1. **高并发事件**：验证事件顺序和丢失处理
2. **内存压力**：`pending_mcp_invocations` 缓存满载行为
3. **网络分区**：Guardian 评审超时场景

### 改进建议

1. **测试组织优化**
   ```rust
   // 当前：所有测试在单个文件
   // 建议：按功能分组
   mod event_forwarding_tests { ... }
   mod approval_routing_tests { ... }
   mod guardian_integration_tests { ... }
   ```

2. **测试辅助函数提取**
   ```rust
   // 当前：每个测试重复构造 Codex 实例
   // 建议：提取通用辅助函数
   async fn setup_test_codex() -> (Arc<Codex>, TestChannels) { ... }
   ```

3. **属性测试引入**
   ```rust
   // 使用 proptest 验证各种输入组合
   proptest! {
       #[test]
       fn test_various_call_id_formats(call_id in "[a-zA-Z0-9_-]{1,100}") {
           // 验证各种 call_id 格式都能正确处理
       }
   }
   ```

4. **Mock 替代真实 Session**
   ```rust
   // 当前：使用 make_session_and_context_with_rx
   // 建议：使用 mockall 创建 MockSession
   let mut mock_session = MockSession::new();
   mock_session.expect_request_command_approval()
       .returning(|...| async { ReviewDecision::Approved });
   ```

### 潜在风险点

1. **测试间状态污染**
   - 风险：`make_session_and_context_with_rx` 可能共享全局状态
   - 缓解：确保每个测试使用独立的会话实例

2. **超时值敏感性**
   - 风险：`Duration::from_secs(1)` 在慢速 CI 环境可能不稳定
   - 建议：使用环境变量或常量配置超时

3. **Guardian 测试的模型依赖**
   - 风险：Guardian 测试依赖特定模型配置
   - 现状：测试使用 `ApprovalsReviewer::GuardianSubagent` 配置，不依赖真实模型调用
