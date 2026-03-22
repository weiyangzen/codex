# phase2.rs - 研究文档

## 场景与职责

`phase2.rs` 实现了记忆系统的第二阶段（Phase 2）：Global Consolidation。这是记忆管道的协调组件，负责将 Phase 1 提取的记忆整合到文件系统工件中，并启动专门的整合子代理。

### 核心职责

1. **全局作业声明**: 声明单个全局 Phase 2 作业锁
2. **记忆选择**: 从数据库加载符合条件的 stage-1 输出
3. **工件同步**: 同步本地记忆工件（`raw_memories.md`、`rollout_summaries/`）
4. **子代理生成**: 生成并监控整合子代理
5. **状态管理**: 更新作业状态和水印

## 功能点目的

### 主要数据结构

```rust
/// 作业声明信息
#[derive(Debug, Clone, Default)]
struct Claim {
    token: String,      // 所有权令牌
    watermark: i64,     // 输入水印
}

/// 计数器
#[derive(Debug, Clone, Default)]
struct Counters {
    input: i64,         // 输入记忆数量
}
```

### 主流程

```rust
pub(super) async fn run(session: &Arc<Session>, config: Arc<Config>) {
    // 1. 启动 E2E 计时器
    let phase_two_e2e_timer = session.services.session_telemetry
        .start_timer(metrics::MEMORY_PHASE_TWO_E2E_MS, &[])
        .ok();

    let Some(db) = session.services.state_db.as_deref() else {
        return;
    };
    let root = memory_root(&config.codex_home);
    let max_raw_memories = config.memories.max_raw_memories_for_consolidation;
    let max_unused_days = config.memories.max_unused_days;

    // 2. 声明作业
    let claim = match job::claim(session, db).await {
        Ok(claim) => claim,
        Err(e) => {
            session.services.session_telemetry.counter(...);
            return;
        }
    };

    // 3. 获取代理配置
    let Some(agent_config) = agent::get_config(config.clone()) else {
        tracing::error!("failed to get agent config");
        job::failed(session, db, &claim, "failed_sandbox_policy").await;
        return;
    };

    // 4. 查询记忆选择
    let selection = match db.get_phase2_input_selection(max_raw_memories, max_unused_days).await {
        Ok(selection) => selection,
        Err(err) => {
            tracing::error!("failed to list stage1 outputs...");
            job::failed(session, db, &claim, "failed_load_stage1_outputs").await;
            return;
        }
    };
    let raw_memories = selection.selected.to_vec();
    let artifact_memories = artifact_memories_for_phase2(&selection);
    let new_watermark = get_watermark(claim.watermark, &raw_memories);

    // 5. 同步文件系统工件
    if let Err(err) = sync_rollout_summaries_from_memories(&root, &artifact_memories, ...).await {
        tracing::error!("failed syncing local memory artifacts...");
        job::failed(session, db, &claim, "failed_sync_artifacts").await;
        return;
    }
    if let Err(err) = rebuild_raw_memories_file_from_memories(&root, &artifact_memories, ...).await {
        tracing::error!("failed rebuilding raw memories...");
        job::failed(session, db, &claim, "failed_rebuild_raw_memories").await;
        return;
    }

    // 6. 空输入处理
    if raw_memories.is_empty() {
        job::succeed(session, db, &claim, new_watermark, &[], "succeeded_no_input").await;
        return;
    }

    // 7. 生成子代理
    let prompt = agent::get_prompt(config, &selection);
    let source = SessionSource::SubAgent(SubAgentSource::MemoryConsolidation);
    let thread_id = match session.services.agent_control.spawn_agent(agent_config, prompt, Some(source)).await {
        Ok(thread_id) => thread_id,
        Err(err) => {
            tracing::error!("failed to spawn global memory consolidation agent...");
            job::failed(session, db, &claim, "failed_spawn_agent").await;
            return;
        }
    };

    // 8. 处理代理
    agent::handle(session, claim, new_watermark, raw_memories.clone(), thread_id, phase_two_e2e_timer);

    // 9. 发出指标
    let counters = Counters { input: raw_memories.len() as i64 };
    emit_metrics(session, counters);
}
```

### 作业声明

```rust
mod job {
    pub(super) async fn claim(
        session: &Arc<Session>,
        db: &StateRuntime,
    ) -> Result<Claim, &'static str> {
        let session_telemetry = &session.services.session_telemetry;
        let claim = db
            .try_claim_global_phase2_job(session.conversation_id, phase_two::JOB_LEASE_SECONDS)
            .await
            .map_err(|e| {
                tracing::error!("failed to claim job: {}", e);
                "failed_claim"
            })?;
        
        match claim {
            codex_state::Phase2JobClaimOutcome::Claimed { ownership_token, input_watermark } => {
                session_telemetry.counter(metrics::MEMORY_PHASE_TWO_JOBS, 1, &[("status", "claimed")]);
                Ok(Claim { token: ownership_token, watermark: input_watermark })
            }
            codex_state::Phase2JobClaimOutcome::SkippedNotDirty => Err("skipped_not_dirty"),
            codex_state::Phase2JobClaimOutcome::SkippedRunning => Err("skipped_running"),
        }
    }

    pub(super) async fn failed(
        session: &Arc<Session>,
        db: &StateRuntime,
        claim: &Claim,
        reason: &'static str,
    ) {
        session.services.session_telemetry.counter(...);
        // 尝试标记失败，如果拥有权已丢失则尝试无条件标记
        if matches!(
            db.mark_global_phase2_job_failed(&claim.token, reason, phase_two::JOB_RETRY_DELAY_SECONDS).await,
            Ok(false)
        ) {
            let _ = db.mark_global_phase2_job_failed_if_unowned(&claim.token, reason, phase_two::JOB_RETRY_DELAY_SECONDS).await;
        }
    }

    pub(super) async fn succeed(
        session: &Arc<Session>,
        db: &StateRuntime,
        claim: &Claim,
        completion_watermark: i64,
        selected_outputs: &[codex_state::Stage1Output],
        reason: &'static str,
    ) {
        session.services.session_telemetry.counter(...);
        let _ = db.mark_global_phase2_job_succeeded(&claim.token, completion_watermark, selected_outputs).await;
    }
}
```

### 代理配置

```rust
mod agent {
    pub(super) fn get_config(config: Arc<Config>) -> Option<Config> {
        let root = memory_root(&config.codex_home);
        let mut agent_config = config.as_ref().clone();

        // 设置工作目录
        agent_config.cwd = root;
        
        // 批准策略：永不询问
        agent_config.permissions.approval_policy = Constrained::allow_only(AskForApproval::Never);
        
        // 禁用特定功能
        let _ = agent_config.features.disable(Feature::SpawnCsv);
        let _ = agent_config.features.disable(Feature::Collab);
        let _ = agent_config.features.disable(Feature::MemoryTool);

        // 沙盒策略：仅本地写入
        let mut writable_roots = Vec::new();
        match AbsolutePathBuf::from_absolute_path(agent_config.codex_home.clone()) {
            Ok(codex_home) => writable_roots.push(codex_home),
            Err(err) => warn!("..."),
        }
        let consolidation_sandbox_policy = SandboxPolicy::WorkspaceWrite {
            writable_roots,
            read_only_access: Default::default(),
            network_access: false,
            exclude_tmpdir_env_var: false,
            exclude_slash_tmp: false,
        };
        agent_config.permissions.sandbox_policy.set(consolidation_sandbox_policy).ok()?;

        // 模型配置
        agent_config.model = Some(config.memories.consolidation_model.clone().unwrap_or(phase_two::MODEL.to_string()));
        agent_config.model_reasoning_effort = Some(phase_two::REASONING_EFFORT);

        Some(agent_config)
    }

    pub(super) fn get_prompt(
        config: Arc<Config>,
        selection: &codex_state::Phase2InputSelection,
    ) -> Vec<UserInput> {
        let root = memory_root(&config.codex_home);
        let prompt = build_consolidation_prompt(&root, selection);
        vec![UserInput::Text { text: prompt, text_elements: vec![] }]
    }
}
```

### 代理生命周期管理

```rust
pub(super) fn handle(
    session: &Arc<Session>,
    claim: Claim,
    new_watermark: i64,
    selected_outputs: Vec<codex_state::Stage1Output>,
    thread_id: ThreadId,
    phase_two_e2e_timer: Option<codex_otel::Timer>,
) {
    let Some(db) = session.services.state_db.clone() else {
        return;
    };
    let session = session.clone();

    tokio::spawn(async move {
        let _phase_two_e2e_timer = phase_two_e2e_timer;
        let agent_control = session.services.agent_control.clone();

        // 订阅代理状态
        let rx = match agent_control.subscribe_status(thread_id).await {
            Ok(rx) => rx,
            Err(err) => {
                tracing::error!("agent_control.subscribe_status failed: {err:?}");
                job::failed(&session, &db, &claim, "failed_subscribe_status").await;
                return;
            }
        };

        // 循环直到最终状态
        let final_status = loop_agent(db.clone(), claim.token.clone(), new_watermark, thread_id, rx).await;

        // 处理结果
        if matches!(final_status, AgentStatus::Completed(_)) {
            if let Some(token_usage) = agent_control.get_total_token_usage(thread_id).await {
                emit_token_usage_metrics(&session, &token_usage);
            }
            job::succeed(&session, &db, &claim, new_watermark, &selected_outputs, "succeeded").await;
        } else {
            job::failed(&session, &db, &claim, "failed_agent").await;
        }

        // 清理：关闭代理
        if !matches!(final_status, AgentStatus::Shutdown | AgentStatus::NotFound) {
            tokio::spawn(async move {
                if let Err(err) = agent_control.shutdown_agent(thread_id).await {
                    warn!("failed to auto-close global memory consolidation agent {thread_id}: {err}");
                }
            });
        }
    });
}

async fn loop_agent(
    db: Arc<StateRuntime>,
    token: String,
    _new_watermark: i64,
    thread_id: ThreadId,
    mut rx: watch::Receiver<AgentStatus>,
) -> AgentStatus {
    let mut heartbeat_interval = tokio::time::interval(
        Duration::from_secs(phase_two::JOB_HEARTBEAT_SECONDS)  // 90 秒
    );
    heartbeat_interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);

    loop {
        let status = rx.borrow().clone();
        if is_final_agent_status(&status) {
            break status;
        }

        tokio::select! {
            update = rx.changed() => {
                if update.is_err() {
                    tracing::warn!("lost status updates for global memory consolidation agent {thread_id}");
                    break status;
                }
            }
            _ = heartbeat_interval.tick() => {
                // 心跳：更新租约
                match db.heartbeat_global_phase2_job(&token, phase_two::JOB_LEASE_SECONDS).await {
                    Ok(true) => {}  // 成功
                    Ok(false) => {
                        break AgentStatus::Errored("lost global phase-2 ownership during heartbeat".to_string());
                    }
                    Err(err) => {
                        break AgentStatus::Errored(format!("phase-2 heartbeat update failed: {err}"));
                    }
                }
            }
        }
    }
}
```

### 水印计算

```rust
pub(super) fn get_watermark(
    claimed_watermark: i64,
    latest_memories: &[codex_state::Stage1Output],
) -> i64 {
    latest_memories
        .iter()
        .map(|memory| memory.source_updated_at.timestamp())
        .max()
        .unwrap_or(claimed_watermark)
        .max(claimed_watermark)  // 确保不倒退
}
```

### 工件记忆选择

```rust
fn artifact_memories_for_phase2(
    selection: &codex_state::Phase2InputSelection,
) -> Vec<Stage1Output> {
    let mut seen = HashSet::new();
    let mut memories = selection.selected.clone();
    
    // 添加当前选择
    for memory in &selection.selected {
        seen.insert(rollout_summary_file_stem(memory));
    }
    
    // 添加之前选择（用于在遗忘期间保留证据）
    for memory in &selection.previous_selected {
        if seen.insert(rollout_summary_file_stem(memory)) {
            memories.push(memory.clone());
        }
    }
    memories
}
```

## 关键代码路径与文件引用

### 主要函数

| 函数 | 行号 | 描述 |
|------|------|------|
| `run` | 43 | Phase 2 主入口 |
| `artifact_memories_for_phase2` | 163 | 工件记忆选择 |
| `job::claim` | 182 | 作业声明 |
| `job::failed` | 213 | 作业失败处理 |
| `job::succeed` | 243 | 作业成功处理 |
| `agent::get_config` | 265 | 代理配置构建 |
| `agent::get_prompt` | 312 | 代理提示构建 |
| `agent::handle` | 325 | 代理生命周期处理 |
| `agent::loop_agent` | 394 | 代理状态循环 |
| `get_watermark` | 446 | 水印计算 |
| `emit_metrics` | 458 | 指标发出 |
| `emit_token_usage_metrics` | 471 | Token 使用指标 |

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::agent::AgentStatus` | 代理状态 |
| `crate::agent::status::is_final` | 最终状态检查 |
| `crate::codex::Session` | 会话上下文 |
| `crate::config::Config` | 配置 |
| `crate::features::Feature` | 功能标志 |
| `crate::memories::memory_root` | 路径构建 |
| `crate::memories::prompts::build_consolidation_prompt` | 提示构建 |
| `crate::memories::storage::*` | 存储操作 |
| `codex_state::StateRuntime` | 数据库操作 |
| `codex_protocol` | 类型定义 |
| `codex_config::Constrained` | 配置约束 |
| `codex_utils_absolute_path::AbsolutePathBuf` | 路径处理 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `tokio::sync::watch` | 状态订阅 |
| `tokio::time` | 心跳定时器 |
| `tracing` | 日志 |

## 风险、边界与改进建议

### 已知风险

1. **竞争条件**:
   - 注释中提到 "TODO(jif) we might have a very small race here"
   - 代理状态订阅和心跳之间可能存在竞争

2. **租约管理**:
   - 心跳间隔 90 秒，租约 3600 秒
   - 网络延迟可能导致租约过期

3. **错误处理**:
   - 某些错误仅记录而不传播
   - 代理失败时可能丢失详细错误信息

4. **资源泄漏**:
   - 如果 `loop_agent` 提前退出，代理可能未被清理
   - 虽然有清理逻辑，但依赖于最终状态检查

### 边界条件

1. **空选择**: 当没有记忆时，清理陈旧工件并标记成功
2. **配置失败**: 沙盒策略无法覆盖时标记重试
3. **同步失败**: 文件系统同步失败时标记重试
4. **生成失败**: 代理生成失败时标记重试

### 改进建议

1. **消除竞争条件**:
   - 审查并修复 TODO 中提到的竞争
   - 考虑使用更严格的同步机制

2. **增强可观测性**:
   - 添加更多详细的 span 和事件
   - 记录代理内部状态变化

3. **改进错误处理**:
   - 使用结构化错误类型
   - 保留更多错误上下文

4. **优雅关闭**:
   - 添加取消令牌支持
   - 支持长时间运行的整合作业取消

5. **配置验证**:
   - 在 `get_config` 中添加更多验证
   - 提前检测无效配置

6. **测试覆盖**:
   - 添加更多单元测试
   - 添加模拟代理行为的集成测试
