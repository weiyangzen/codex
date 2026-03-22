# codex_delegate.rs 深度研究文档

## 场景与职责

`codex_delegate.rs` 是 Codex 核心库中负责**子代理（Sub-agent）生命周期管理**的关键模块。它实现了父会话与子 Codex 实例之间的代理委托模式，主要用于以下场景：

1. **Guardian 自动审批流程**：当启用 Guardian 审批模式时，需要创建独立的子代理来评估操作风险
2. **多轮对话中的子线程**：支持创建交互式子线程处理特定任务
3. **一次性任务执行**：通过 one-shot 模式执行单次任务并自动清理

该模块的核心价值在于**解耦父子会话的审批流程**——子代理产生的审批请求会被路由回父会话处理，而非直接暴露给终端用户。

## 功能点目的

### 1. 交互式子线程 (`run_codex_thread_interactive`)
- **目的**：创建一个可长期运行的子 Codex 实例，支持双向通信
- **特点**：
  - 子代理的审批请求自动路由到父会话
  - 非审批事件通过 `events_rx` 通道传递给调用方
  - 支持通过 `ops_tx` 向子代理提交额外操作

### 2. 一次性子线程 (`run_codex_thread_one_shot`)
- **目的**：执行单次任务后自动关闭
- **特点**：
  - 自动提交初始输入
  - 监听 `TurnComplete`/`TurnAborted` 事件自动触发关闭
  - 返回关闭的 `tx_sub` 防止后续操作

### 3. 事件转发与过滤 (`forward_events`)
- **核心职责**：
  - 过滤掉 Delta 事件（`AgentMessageDelta`, `AgentReasoningDelta`）
  - 拦截审批请求（`ExecApprovalRequest`, `ApplyPatchApprovalRequest`）并路由到父会话
  - 缓存 MCP 工具调用上下文（`pending_mcp_invocations`）
  - 支持取消令牌机制实现优雅关闭

### 4. 审批处理流水线
- **执行审批** (`handle_exec_approval`)：处理 shell 命令执行审批
- **补丁审批** (`handle_patch_approval`)：处理文件变更审批
- **权限请求** (`handle_request_permissions`)：处理权限提升请求
- **用户输入请求** (`handle_request_user_input`)：处理需要用户输入的场景

## 具体技术实现

### 关键数据结构

```rust
// 子代理创建参数（简化）
pub(crate) async fn run_codex_thread_interactive(
    config: Config,
    auth_manager: Arc<AuthManager>,
    models_manager: Arc<ModelsManager>,
    parent_session: Arc<Session>,      // 父会话引用
    parent_ctx: Arc<TurnContext>,      // 父回合上下文
    cancel_token: CancellationToken,   // 取消令牌
    subagent_source: SubAgentSource,   // 子代理来源标识
    initial_history: Option<InitialHistory>,
) -> Result<Codex, CodexErr>
```

### 核心流程：事件转发

```
┌─────────────────┐
│   Sub-agent     │
│  (子Codex实例)   │
└────────┬────────┘
         │ Event流
         ▼
┌─────────────────┐     ┌──────────────────┐
│ forward_events  │────▶│  过滤Delta事件    │
│   (事件转发器)   │     └──────────────────┘
└────────┬────────┘
         │
    ┌────┴────┬────────────┬──────────────┬──────────────┐
    ▼         ▼            ▼              ▼              ▼
ExecApproval  ApplyPatch  RequestPermissions  RequestUserInput  其他事件
    │         │            │              │              │
    ▼         ▼            ▼              ▼              ▼
handle_exec_approval  handle_patch_approval  ...     直接转发到tx_sub
    │         │
    ▼         ▼
父会话审批流程   Guardian自动审批
```

### MCP 工具调用上下文缓存

```rust
// 缓存结构：call_id -> McpInvocation
let pending_mcp_invocations = Arc::new(Mutex::new(HashMap::<String, McpInvocation>::new()));

// 生命周期管理：
// 1. McpToolCallBegin -> 插入缓存
// 2. McpToolCallEnd   -> 移除缓存
// 3. RequestUserInput(含MCP审批) -> 从缓存恢复完整上下文
```

### 审批路由逻辑

```rust
// 判断是否路由到 Guardian
if routes_approval_to_guardian(parent_ctx) {
    // 创建 Guardian 审批请求
    let review_rx = spawn_guardian_review(
        parent_session, parent_ctx, request, reason, review_cancel
    );
    await_approval_with_cancel(...).await
} else {
    // 路由到父会话的人工审批
    parent_session.request_command_approval(...).await
}
```

### 取消令牌层级结构

```
Parent CancelToken
       │
       ├──▶ cancel_token_events (事件转发任务)
       │
       └──▶ cancel_token_ops (操作转发任务)
            │
            └──▶ review_cancel (Guardian审批任务)
```

## 关键代码路径与文件引用

### 本文件关键函数

| 函数名 | 行号 | 职责 |
|--------|------|------|
| `run_codex_thread_interactive` | 63-136 | 创建交互式子线程 |
| `run_codex_thread_one_shot` | 142-217 | 创建一次性子线程 |
| `forward_events` | 219-367 | 事件转发与过滤主循环 |
| `handle_exec_approval` | 418-498 | 执行审批处理 |
| `handle_patch_approval` | 501-602 | 补丁审批处理 |
| `handle_request_user_input` | 604-640 | 用户输入请求处理 |
| `maybe_auto_review_mcp_request_user_input` | 649-717 | MCP工具自动审批 |
| `spawn_guardian_review` | 719-745 | 在独立线程运行Guardian评审 |
| `shutdown_delegate` | 370-385 | 优雅关闭子代理 |

### 跨文件依赖

```
codex_delegate.rs
    ├──▶ codex.rs
    │       ├── Codex::spawn()          [创建子代理]
    │       ├── Codex::submit()         [提交操作]
    │       ├── Codex::next_event()     [获取事件]
    │       ├── Session                 [会话状态]
    │       └── TurnContext             [回合上下文]
    │
    ├──▶ guardian/mod.rs
    │       ├── routes_approval_to_guardian()     [判断是否走Guardian]
    │       ├── review_approval_request_with_cancel() [Guardian评审]
    │       └── GuardianApprovalRequest           [审批请求类型]
    │
    ├──▶ mcp_tool_call.rs
    │       ├── is_mcp_tool_approval_question_id()  [识别MCP审批]
    │       ├── build_guardian_mcp_tool_review_request() [构建请求]
    │       └── lookup_mcp_tool_metadata()          [查询工具元数据]
    │
    └──▶ codex_protocol::protocol::*
            ├── Event, EventMsg           [事件类型]
            ├── Op                        [操作类型]
            ├── ReviewDecision            [审批决策]
            └── SessionSource/SubAgentSource [来源标识]
```

## 依赖与外部交互

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `async-channel` | 异步通道用于事件/操作传输 |
| `tokio` | 异步运行时、取消令牌 |
| `serde_json` | JSON 序列化 |
| `codex_protocol` | 协议类型定义 |
| `codex_async_utils` | `OrCancelExt` 取消扩展 |

### 与父会话的交互

```rust
// 审批请求通过父会话的方法处理
parent_session.request_command_approval(...)
parent_session.request_patch_approval(...)
parent_session.request_user_input(...)
parent_session.request_permissions(...)

// 审批结果通知
parent_session.notify_approval(approval_id, decision)
parent_session.notify_user_input_response(sub_id, response)
```

### 与 Guardian 的交互

```rust
// 在独立线程中运行 Guardian 评审
std::thread::spawn(move || {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    let decision = runtime.block_on(review_approval_request_with_cancel(...));
    tx.send(decision)
});
```

## 风险、边界与改进建议

### 已知风险

1. **MCP 上下文缓存泄漏**
   - 风险：如果 `McpToolCallEnd` 事件丢失，缓存中的 `McpInvocation` 可能无法清理
   - 缓解：使用 LRU 或 TTL 机制限制缓存大小

2. **Guardian 评审超时**
   - 风险：`spawn_guardian_review` 使用 90 秒超时，但超时时返回 `Denied` 可能过于严格
   - 现状：代码中已实现超时处理，但需监控实际超时率

3. **取消令牌传播**
   - 风险：父取消令牌被取消时，子任务可能无法及时响应
   - 缓解：使用 `biased` select 优先检查取消状态

### 边界条件

| 场景 | 处理方式 |
|------|----------|
| 父会话已关闭 | `forward_event_or_shutdown` 捕获发送失败并关闭子代理 |
| 子代理事件通道满 | 依赖 `async-channel` 的背压机制 |
| Guardian 评审失败 | 失败关闭（fail-closed）策略，返回 `Denied` |
| MCP 工具元数据缺失 | `lookup_mcp_tool_metadata` 返回 `None`，降级处理 |

### 改进建议

1. **缓存大小限制**
   ```rust
   // 当前实现无大小限制
   let pending_mcp_invocations = Arc::new(Mutex::new(HashMap::new()));
   
   // 建议：使用 LRU Cache
   let pending_mcp_invocations = Arc::new(Mutex::new(LruCache::new(1000)));
   ```

2. **审批路由配置化**
   - 当前 `routes_approval_to_guardian` 逻辑硬编码在 `guardian/review.rs`
   - 建议：支持更灵活的路由策略配置

3. **监控与可观测性**
   - 添加子代理生命周期指标（创建数、活跃数、关闭数）
   - 记录审批路由决策原因

4. **错误处理细化**
   - `spawn_guardian_review` 中 runtime 创建失败直接返回 `Denied`
   - 建议：区分系统错误与业务拒绝，便于排查

### 测试覆盖

测试文件 `codex_delegate_tests.rs` 覆盖了：
- 取消时的事件转发关闭
- 操作转发的 trace 上下文保持
- 权限请求的 round-trip
- Guardian 审批的 call_id/approval_id 分离
- MCP Guardian 拒绝时的合成 decline 响应

建议补充：
- 高并发场景下的缓存一致性测试
- 父会话关闭时的优雅降级测试
