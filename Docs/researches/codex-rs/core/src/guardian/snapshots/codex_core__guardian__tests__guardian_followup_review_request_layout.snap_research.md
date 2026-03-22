# Guardian Follow-up Review Request Layout Snapshot 研究文档

## 场景与职责

此 snapshot 文件是 Codex 核心 Guardian（安全审查）模块的测试快照，记录了**连续多次 Guardian 审查请求**的 prompt 结构，重点验证：

1. **Prompt Cache Key 复用**：后续审查请求与首次请求共享相同的 `prompt_cache_key`
2. **历史审查结果传递**：后续请求包含之前 Guardian 评估的 rationale（理由）

**关键场景**：
- 首次请求：用户请求推送文档修复，Codex 尝试 `git push`，被 Guardian 评估为低风险（risk_score: 5）
- 后续请求：同一操作需要重试（添加 `--force-with-lease` 参数），Guardian 需要参考之前的评估理由

## 功能点目的

### 1. Prompt Cache Key 复用验证
确保 Guardian 会话缓存机制正确工作：
- 首次审查创建 trunk 会话并生成 `prompt_cache_key`
- 后续审查复用相同的 cache key，减少 API 调用成本
- 验证 `shared_prompt_cache_key: true` 断言

### 2. 历史 Rationale 传递验证
确保 Guardian 能够访问之前的评估结果：
- 首次评估的 rationale："first guardian rationale from the prior review"
- 后续请求的 prompt 包含前次评估的完整 JSON 输出
- 验证 `followup_contains_first_rationale: true` 断言

### 3. 会话连续性保证
验证 Guardian 审查会话的连续性：
- 相同会话上下文下的多次审批请求
- 历史评估结果作为新评估的参考
- 支持渐进式风险评估（风险分数从 5 上升到 7）

## 具体技术实现

### 会话管理架构

```rust
// review_session.rs:GuardianReviewSessionManager
pub(crate) struct GuardianReviewSessionManager {
    state: Arc<Mutex<GuardianReviewSessionState>>,
}

struct GuardianReviewSessionState {
    trunk: Option<Arc<GuardianReviewSession>>,      // 主会话（可复用）
    ephemeral_reviews: Vec<Arc<GuardianReviewSession>>, // 临时会话（并行时）
}

struct GuardianReviewSession {
    codex: Codex,
    cancel_token: CancellationToken,
    reuse_key: GuardianReviewSessionReuseKey,  // 会话复用标识
    review_lock: Mutex<()>,                    // 串行化审查
    last_committed_rollout_items: Mutex<Option<Vec<RolloutItem>>>,
}
```

### Cache Key 复用机制

1. **Reuse Key 计算** (`GuardianReviewSessionReuseKey::from_spawn_config`)
   ```rust
   struct GuardianReviewSessionReuseKey {
       model: Option<String>,
       model_provider_id: String,
       model_provider: ModelProviderInfo,
       model_context_window: Option<i64>,
       // ... 其他影响会话行为的配置
       permissions: Permissions,
       developer_instructions: Option<String>,
       // ...
   }
   ```

2. **Trunk 会话复用逻辑** (`run_review` 方法）
   ```rust
   if state.trunk.is_none() {
       // 创建新的 trunk 会话
       state.trunk = Some(Arc::new(review_session));
   }
   
   if trunk.reuse_key != next_reuse_key {
       // 配置变更，创建临时会话
       return self.run_ephemeral_review(...).await;
   }
   ```

### Follow-up Prompt 构建

```rust
// prompt.rs:build_guardian_prompt_items
pub(crate) async fn build_guardian_prompt_items(
    session: &Session,
    retry_reason: Option<String>,  // "Second retry reason"
    request: GuardianApprovalRequest,
) -> serde_json::Result<Vec<UserInput>>
```

Follow-up 请求与首次请求的区别：
1. **额外的 message/assistant 条目**：包含前次 Guardian 的评估结果
2. **更新的 retry_reason**：反映新的重试原因
3. **更新的 planned_action**：反映修改后的命令（添加 `--force-with-lease`）

### Snapshot 中的 Prompt 结构对比

**首次请求 (Initial Guardian Review Request)**：
```
00:message/developer:<PERMISSIONS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/developer:You are performing... (Guardian 策略)
03:message/user[16]: (审查请求详情)
    [01-07] 对话历史
    [08-16] 计划动作: git push
```

**后续请求 (Follow-up Guardian Review Request)**：
```
00:message/developer:<PERMISSIONS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/developer:You are performing... (Guardian 策略)
03:message/user[16]: (首次审查请求详情 - 同上)
04:message/assistant:{"risk_level":"low","risk_score":5,...}  # ★ 新增：前次评估结果
05:message/user[16]: (新的审查请求详情)
    [01-07] 对话历史
    [08-16] 计划动作: git push --force-with-lease  # ★ 修改：添加 --force-with-lease
```

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|------|------|
| `codex-rs/core/src/guardian/review_session.rs` | 会话管理、trunk/ephemeral 逻辑、cache key 管理 |
| `codex-rs/core/src/guardian/prompt.rs` | Prompt 构建、历史条目收集 |
| `codex-rs/core/src/guardian/review.rs` | 审查流程、结果解析 |
| `codex-rs/core/src/guardian/tests.rs` | 测试用例，包含本 snapshot 的生成逻辑 |

### 测试代码路径

```rust
// tests.rs:guardian_reuses_prompt_cache_key_and_appends_prior_reviews (约第 581-708 行)
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn guardian_reuses_prompt_cache_key_and_appends_prior_reviews() -> anyhow::Result<()> {
    // 1. 设置 mock 服务器，配置两次 SSE 响应
    let request_log = mount_sse_sequence(&server, vec![
        sse(vec![...]),  // 首次评估响应
        sse(vec![...]),  // 后续评估响应
    ]).await;
    
    // 2. 执行首次审查
    let first_prompt = build_guardian_prompt_items(...).await?;
    let first_outcome = run_guardian_review_session_for_test(...).await;
    
    // 3. 执行后续审查（不同命令）
    let second_prompt = build_guardian_prompt_items(...).await?;
    let second_outcome = run_guardian_review_session_for_test(...).await;
    
    // 4. 验证 cache key 复用
    let requests = request_log.requests();
    assert_eq!(first_body["prompt_cache_key"], second_body["prompt_cache_key"]);
    
    // 5. 验证 rationale 传递
    assert!(second_body.to_string().contains(first_rationale));
    
    // 6. 生成 snapshot
    assert_snapshot!("codex_core__guardian__tests__guardian_followup_review_request_layout", ...);
}
```

### 关键函数调用链

```
run_guardian_review_session
  ├── build_guardian_review_session_config  # 构建 Guardian 配置
  ├── GuardianReviewSessionManager::run_review
  │     ├── 检查 trunk 会话是否存在且 reuse_key 匹配
  │     ├── 若匹配：复用 trunk 会话
  │     ├── 若不匹配：创建 ephemeral 会话
  │     └── run_review_on_session
  │           ├── sync_session_approved_hosts_to  # 同步网络授权
  │           └── codex.submit(Op::UserTurn)      # 提交审查请求
  └── parse_guardian_assessment  # 解析评估结果
```

## 依赖与外部交互

### 内部依赖

1. **Session 历史管理**
   ```rust
   // codex.rs:Session
   async fn clone_history(&self) -> HistorySnapshot
   async fn record_into_history(&self, items: &[ResponseItem], turn: &TurnContext)
   ```
   - Guardian 评估结果作为 assistant message 记录到历史
   - 后续审查从历史中提取前次评估

2. **Rollout 记录器**
   ```rust
   // rollout/recorder.rs
   async fn load_rollout_items_for_fork(session: &Session) -> anyhow::Result<Option<Vec<RolloutItem>>>
   ```
   - 用于 fork trunk 会话的历史快照

3. **网络授权同步**
   ```rust
   // 将父会话的网络授权同步到 Guardian 会话
   network_approval.sync_session_approved_hosts_to(&review_session.codex.session.services.network_approval)
   ```

### 外部交互

1. **OpenAI Responses API**
   - `prompt_cache_key` 由 API 响应返回
   - 后续请求携带相同的 `prompt_cache_key` 实现缓存复用
   - 节省 token 成本和延迟

2. **配置继承**
   - Guardian 会话继承父会话的网络代理配置
   - 但使用独立的沙箱策略（read-only）
   - 独立的审批策略（never ask for approval）

## 风险、边界与改进建议

### 当前风险与边界

1. **Cache Key 失效场景**
   - 配置变更导致 reuse_key 不匹配
   - 模型切换导致无法复用缓存
   - 网络代理配置变更
   - 边界：任何配置变更都触发新的 trunk 会话创建

2. **历史累积问题**
   - 多次重试后，prompt 中累积的 rationale 越来越多
   - 可能超出 token 预算，导致早期历史被截断
   - 边界：当前实现未限制累积的 rationale 数量

3. **并行审查限制**
   - Trunk 会话同一时间只能处理一个审查
   - 并行审查需要创建 ephemeral 会话
   - 边界：高并发场景下可能创建大量 ephemeral 会话

4. **会话生命周期管理**
   - Trunk 会话长期存活，可能占用资源
   - 没有显式的会话过期机制
   - 边界：长时间运行的会话可能积累大量历史

### 改进建议

1. **智能 Cache Key 管理**
   - 实现更细粒度的 reuse_key，区分关键/非关键配置变更
   - 添加 cache key 命中率监控
   - 考虑实现 cache key 预热机制

2. **历史 Rationale 压缩**
   - 对累积的 rationale 进行智能摘要
   - 只保留最近 N 次评估的完整 rationale
   - 早期 rationale 仅保留风险等级和分数

3. **会话资源优化**
   - 实现 trunk 会话空闲超时机制
   - 限制同时存在的 ephemeral 会话数量
   - 添加会话内存使用监控

4. **测试覆盖扩展**
   - 添加配置变更场景测试
   - 测试大量累积 rationale 的边界条件
   - 验证并行审查的资源隔离

5. **可观测性增强**
   - 记录 cache key 复用率指标
   - 追踪 trunk vs ephemeral 会话使用比例
   - 监控 Guardian 审查延迟分布

6. **故障恢复机制**
   - 当 trunk 会话异常时，自动降级到 ephemeral 会话
   - 实现会话健康检查
   - 提供手动刷新 Guardian 会话的接口
