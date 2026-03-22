# review_session.rs 研究文档

## 场景与职责

`review_session.rs` 是 Guardian 子代理系统的会话管理层，负责：
1. 管理 Guardian 审查会话的生命周期（创建、复用、销毁）
2. 实现会话复用策略（trunk + ephemeral forks）
3. 处理并发审查请求（并行审查的 fork 机制）
4. 配置 Guardian 审查会话的安全约束（只读沙箱、禁用功能）
5. 实现超时和取消机制

**核心定位：**
该模块是 Guardian 系统的"基础设施层"，确保审查会话的高效、安全执行。

## 功能点目的

### 1. 会话管理架构

采用 **Trunk + Ephemeral Forks** 架构：

```
GuardianReviewSessionManager
├── state: Arc<Mutex<GuardianReviewSessionState>>
│   ├── trunk: Option<Arc<GuardianReviewSession>>
│   │   ├── 长期存活的主会话
│   │   ├── 用于顺序审查请求
│   │   └── 支持 prompt cache 复用
│   └── ephemeral_reviews: Vec<Arc<GuardianReviewSession>>
│       ├── 临时 fork 会话
│       ├── 用于并行审查请求
│       └── 从 trunk 的最后提交状态 fork
```

**设计原理：**
- **Trunk**：缓存 Guardian 策略提示词，减少重复传输
- **Ephemeral Forks**：当 trunk 忙时，从最后提交状态 fork，不阻塞新请求
- **Reuse Key**：基于配置计算，配置变更时自动重建 trunk

### 2. 会话复用键（GuardianReviewSessionReuseKey）

决定会话是否可以复用的关键配置项：

```rust
struct GuardianReviewSessionReuseKey {
    model: Option<String>,
    model_provider_id: String,
    model_provider: ModelProviderInfo,
    model_context_window: Option<i64>,
    model_auto_compact_token_limit: Option<i64>,
    model_reasoning_effort: Option<ReasoningEffortConfig>,
    model_reasoning_summary: Option<ReasoningSummaryConfig>,
    permissions: Permissions,
    developer_instructions: Option<String>,
    base_instructions: Option<String>,
    user_instructions: Option<String>,
    compact_prompt: Option<String>,
    cwd: PathBuf,
    mcp_servers: Constrained<HashMap<String, McpServerConfig>>,
    // ... 各种可执行文件路径
    features: ManagedFeatures,
    include_apply_patch_tool: bool,
    use_experimental_unified_exec_tool: bool,
}
```

**设计考量：**
- 只包含影响会话行为的配置
- 忽略不相关的配置（如日志级别）
- 配置变更时自动使缓存失效

### 3. 审查执行流程（run_review）

**阶段 1：获取 Trunk 候选**
- 计算新的 reuse_key
- 检查现有 trunk 是否匹配
- 如果不匹配，标记为 stale 并创建新 trunk

**阶段 2：Trunk 可用性检查**
- 尝试获取 trunk 的 review_lock
- 如果 trunk 被占用，创建 ephemeral fork

**阶段 3：执行审查**
- 在 trunk 或 ephemeral 会话上执行
- 成功后刷新 trunk 的 rollout items

**阶段 4：清理**
- 如果审查失败，关闭并移除 trunk
- Ephemeral 会话在完成后自动清理

### 4. Ephemeral Fork 机制

当 trunk 忙时，创建临时 fork：

```rust
async fn run_ephemeral_review(...) -> GuardianReviewSessionOutcome {
    // 1. 创建 fork 配置（ephemeral = true）
    let mut fork_config = params.spawn_config.clone();
    fork_config.ephemeral = true;
    
    // 2. 创建新会话，从 trunk 的最后提交状态 fork
    let review_session = spawn_guardian_review_session(
        &params, fork_config, reuse_key, 
        spawn_cancel_token.clone(),
        initial_history  // 从 trunk fork 的历史
    ).await?;
    
    // 3. 注册到活跃 ephemeral 列表
    self.register_active_ephemeral(Arc::clone(&review_session)).await;
    
    // 4. 执行审查
    let (outcome, _) = run_review_on_session(review_session.as_ref(), &params, deadline).await;
    
    // 5. 清理
    if let Some(review_session) = self.take_active_ephemeral(&review_session).await {
        review_session.shutdown_in_background();
    }
    outcome
}
```

### 5. 配置构建（build_guardian_review_session_config）

创建 Guardian 专用的安全约束配置：

**安全约束：**
1. **只读沙箱**：`SandboxPolicy::new_read_only_policy()`
2. **永不批准**：`AskForApproval::Never`（Guardian 不应触发进一步批准）
3. **禁用功能**：
   - `SpawnCsv`：防止 CSV 导出
   - `Collab`：防止多 Agent 协作
   - `WebSearchRequest`：防止网络搜索
   - `WebSearchCached`：防止缓存搜索

**配置继承：**
- 继承父会话的网络代理配置（用于只读检查）
- 使用父会话的活动模型（或首选 Guardian 模型）
- 使用 workspace 自定义策略（如有）或默认策略

### 6. 超时和取消机制

**超时处理：**
- 全局超时：`GUARDIAN_REVIEW_TIMEOUT` (90s)
- 中断超时：`GUARDIAN_INTERRUPT_DRAIN_TIMEOUT` (5s)

**取消处理：**
- 支持外部 `CancellationToken`
- 超时或取消时，尝试优雅中断审查会话
- 等待会话进入终止状态（`TurnAborted` 或 `TurnComplete`）

```rust
async fn interrupt_and_drain_turn(codex: &Codex) -> anyhow::Result<()> {
    // 1. 发送中断信号
    let _ = codex.submit(Op::Interrupt).await;
    
    // 2. 等待终止（带超时）
    tokio::time::timeout(GUARDIAN_INTERRUPT_DRAIN_TIMEOUT, async {
        loop {
            let event = codex.next_event().await?;
            if matches!(event.msg, TurnAborted(_) | TurnComplete(_)) {
                return Ok(());
            }
        }
    }).await
}
```

## 具体技术实现

### GuardianReviewSession 结构

```rust
struct GuardianReviewSession {
    codex: Codex,                                    // 底层 Codex 实例
    cancel_token: CancellationToken,                 // 取消令牌
    reuse_key: GuardianReviewSessionReuseKey,        // 复用键
    review_lock: Mutex<()>,                          // 并发控制锁
    last_committed_rollout_items: Mutex<Option<Vec<RolloutItem>>>, // 最后提交状态
}
```

### 会话状态管理

```rust
#[derive(Default)]
struct GuardianReviewSessionState {
    trunk: Option<Arc<GuardianReviewSession>>,
    ephemeral_reviews: Vec<Arc<GuardianReviewSession>>,
}
```

使用 `Arc<Mutex<...>>` 模式支持并发访问。

### EphemeralReviewCleanup

RAII 模式的清理辅助结构：

```rust
struct EphemeralReviewCleanup {
    state: Arc<Mutex<GuardianReviewSessionState>>,
    review_session: Option<Arc<GuardianReviewSession>>,
}

impl Drop for EphemeralReviewCleanup {
    fn drop(&mut self) {
        // 从 ephemeral_reviews 列表移除并关闭会话
    }
}
```

确保即使 panic 也能清理资源。

### 会话创建

```rust
async fn spawn_guardian_review_session(
    params: &GuardianReviewSessionParams,
    spawn_config: Config,
    reuse_key: GuardianReviewSessionReuseKey,
    cancel_token: CancellationToken,
    initial_history: Option<InitialHistory>,
) -> anyhow::Result<GuardianReviewSession> {
    // 使用 run_codex_thread_interactive 创建交互式 Codex 会话
    let codex = run_codex_thread_interactive(
        spawn_config,
        params.parent_session.services.auth_manager.clone(),
        params.parent_session.services.models_manager.clone(),
        Arc::clone(&params.parent_session),
        Arc::clone(&params.parent_turn),
        cancel_token.clone(),
        SubAgentSource::Other(GUARDIAN_REVIEWER_NAME.to_string()),
        initial_history,
    ).await?;
    
    Ok(GuardianReviewSession { ... })
}
```

### 审查执行

```rust
async fn run_review_on_session(
    review_session: &GuardianReviewSession,
    params: &GuardianReviewSessionParams,
    deadline: tokio::time::Instant,
) -> (GuardianReviewSessionOutcome, bool) {
    // 1. 同步网络批准主机列表
    params.parent_session.services.network_approval
        .sync_session_approved_hosts_to(&review_session.codex.session.services.network_approval)
        .await;
    
    // 2. 提交用户 turn（包含 Guardian 提示词）
    review_session.codex.submit(Op::UserTurn {
        items: params.prompt_items.clone(),
        approval_policy: AskForApproval::Never,  // Guardian 不应触发批准
        sandbox_policy: SandboxPolicy::new_read_only_policy(),  // 只读沙箱
        final_output_json_schema: Some(params.schema.clone()),  // 强制 JSON 输出
        ...
    }).await?;
    
    // 3. 等待结果
    wait_for_guardian_review(review_session, deadline, params.external_cancel.as_ref()).await
}
```

## 关键代码路径与文件引用

### 调用关系图

```
review.rs::run_guardian_review_session()
    ↓
GuardianReviewSessionManager::run_review()
    ├── 获取/创建 trunk
    │   └── spawn_guardian_review_session()
    │       └── run_codex_thread_interactive()
    ├── 执行审查（trunk 或 ephemeral）
    │   └── run_review_on_session()
    │       ├── sync_session_approved_hosts_to()
    │       ├── codex.submit(Op::UserTurn)
    │       └── wait_for_guardian_review()
    └── 清理/刷新状态

build_guardian_review_session_config()
├── 设置只读沙箱
├── 设置 approval_policy = Never
├── 禁用危险功能
└── 继承网络配置
```

### 外部调用方

| 文件 | 函数 | 场景 |
|------|------|------|
| `review.rs` | `GuardianReviewSessionManager::run_review` | 执行 Guardian 审查 |
| `review.rs` | `build_guardian_review_session_config` | 构建 Guardian 配置 |

### 内部模块

| 模块 | 用途 |
|------|------|
| `codex_delegate` | `run_codex_thread_interactive` 创建 Codex 会话 |
| `config` | `Config`, `Constrained`, `ManagedFeatures` 等配置类型 |
| `features` | `Feature` 功能开关定义 |
| `protocol` | `SandboxPolicy`, `AskForApproval` 等协议类型 |
| `rollout::recorder` | `RolloutRecorder` 历史记录管理 |

### 测试覆盖

`tests.rs` 中的相关测试：

| 测试 | 验证内容 |
|------|----------|
| `guardian_review_session_config_change_invalidates_cached_session` | 配置变更使缓存失效 |
| `guardian_review_session_config_preserves_parent_network_proxy` | 网络配置继承 |
| `guardian_review_session_config_overrides_parent_developer_instructions` | 策略覆盖 |
| `guardian_review_session_config_uses_live_network_proxy_state` | 实时网络状态 |
| `guardian_review_session_config_rejects_pinned_collab_feature` | 功能禁用验证 |
| `guardian_review_session_config_uses_parent_active_model` | 模型选择 |
| `guardian_review_session_config_uses_requirements_guardian_override` | 自定义策略 |
| `guardian_review_session_config_uses_default_guardian_policy` | 默认策略 |
| `run_before_review_deadline_times_out_before_future_completes` | 超时机制 |
| `run_before_review_deadline_aborts_when_cancelled` | 取消机制 |
| `run_before_review_deadline_with_cancel_cancels_token_on_timeout` | 取消令牌传播 |
| `run_before_review_deadline_with_cancel_preserves_token_on_success` | 成功时保留令牌 |

## 依赖与外部交互

### 外部依赖

| Crate/模块 | 用途 |
|------------|------|
| `tokio::sync::Mutex` | 异步互斥锁 |
| `tokio_util::sync::CancellationToken` | 取消支持 |
| `std::collections::HashMap` | 会话存储 |
| `tracing::warn` | 日志记录 |
| `anyhow` | 错误处理 |

### 内部依赖

| 模块 | 依赖内容 |
|------|----------|
| `codex` | `Codex`, `Session`, `TurnContext` |
| `codex_delegate` | `run_codex_thread_interactive` |
| `config` | `Config`, `Constrained`, `ManagedFeatures`, `NetworkProxySpec` |
| `features` | `Feature` |
| `model_provider_info` | `ModelProviderInfo` |
| `protocol` | `SandboxPolicy`, `AskForApproval`, `InitialHistory`, `Op`, `RolloutItem`, `SubAgentSource` |
| `rollout::recorder` | `RolloutRecorder` |

### 配置关联

- `guardian_developer_instructions`：自定义 Guardian 策略
- `permissions.network`：网络代理配置
- `features`：功能开关（Guardian 会禁用部分功能）
- `model` / `model_reasoning_effort`：模型选择

## 风险、边界与改进建议

### 已知风险

1. **资源泄漏**：
   - Ephemeral 会话在极端情况下可能无法及时清理
   - 虽然 `EphemeralReviewCleanup` 提供了保障，但依赖 Drop 触发

2. **Fork 不一致**：
   - Ephemeral fork 从 trunk 的最后提交状态 fork
   - 如果 trunk 在 fork 后、新请求前提交了新的审查，fork 会错过该上下文

3. **配置敏感**：
   - Reuse key 包含大量字段，容易遗漏影响行为的配置
   - 新增配置时可能忘记添加到 reuse key

4. **并发限制**：
   - 当前实现支持任意数量的 ephemeral 会话
   - 可能耗尽系统资源

### 边界情况

1. **快速连续请求**：
   - 第一个请求创建 trunk
   - 第二个请求到达时 trunk 可能仍在创建中
   - 需要正确处理中间状态

2. **配置快速变更**：
   - 如果配置在审查过程中变更
   - 当前实现可能使用过期的配置完成审查

3. **网络同步失败**：
   - `sync_session_approved_hosts_to` 失败不会阻止审查
   - 可能导致 Guardian 无法访问已批准的主机

4. **模型不可用**：
   - 如果首选和备用模型都不可用
   - 会话创建会失败

### 改进建议

1. **资源限制**：
   - 限制并发 ephemeral 会话数量
   - 添加队列机制，超出限制时排队等待

2. **Fork 优化**：
   - 考虑使用 copy-on-write 机制
   - 或实现真正的会话分支（而非重建）

3. **配置验证**：
   - 添加 CI 检查确保新配置字段被添加到 reuse key
   - 或使用宏自动生成 reuse key

4. **健康检查**：
   - 定期验证 trunk 会话的健康状态
   - 自动重建不健康的 trunk

5. **Metrics**：
   - 添加会话创建/销毁计数
   - 记录 trunk 命中率
   - 监控 ephemeral 会话数量

6. **优雅降级**：
   - 当 Guardian 不可用时，自动降级到用户确认
   - 而非直接失败

7. **会话预热**：
   - 在系统启动时预创建 trunk 会话
   - 减少首次审查的延迟

8. **审查历史持久化**：
   - 考虑将审查历史持久化到磁盘
   - 支持跨进程会话复用
