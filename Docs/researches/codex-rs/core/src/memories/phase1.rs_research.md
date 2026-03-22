# phase1.rs - 研究文档

## 场景与职责

`phase1.rs` 实现了记忆系统的第一阶段（Phase 1）：Rollout Extraction。这是记忆管道的核心组件，负责从历史会话 rollouts 中提取结构化记忆。

### 核心职责

1. **作业声明**: 从状态数据库中声明符合条件的 rollout 作业
2. **内容过滤**: 过滤 rollout 内容，仅保留记忆相关的响应项
3. **并行提取**: 使用 LLM 并行处理多个 rollouts
4. **输出生成**: 生成 `raw_memory`、`rollout_summary` 和 `rollout_slug`
5. **状态管理**: 将结果存储回数据库并管理作业生命周期

## 功能点目的

### 主要数据结构

```rust
/// Phase 1 请求上下文
#[derive(Clone, Debug)]
pub(in crate::memories) struct RequestContext {
    pub(in crate::memories) model_info: ModelInfo,
    pub(in crate::memories) session_telemetry: SessionTelemetry,
    pub(in crate::memories) reasoning_effort: Option<ReasoningEffortConfig>,
    pub(in crate::memories) reasoning_summary: ReasoningSummaryConfig,
    pub(in crate::memories) service_tier: Option<ServiceTier>,
    pub(in crate::memories) turn_metadata_header: Option<String>,
}

/// 作业结果
struct JobResult {
    outcome: JobOutcome,
    token_usage: Option<TokenUsage>,
}

/// 作业结果类型
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum JobOutcome {
    SucceededWithOutput,    // 成功生成记忆
    SucceededNoOutput,      // 成功但无输出
    Failed,                 // 失败
}

/// Stage 1 模型输出
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
struct StageOneOutput {
    #[serde(rename = "raw_memory")]
    pub(crate) raw_memory: String,
    #[serde(rename = "rollout_summary")]
    pub(crate) rollout_summary: String,
    #[serde(default, rename = "rollout_slug")]
    pub(crate) rollout_slug: Option<String>,
}
```

### 主流程

```rust
pub(in crate::memories) async fn run(session: &Arc<Session>, config: &Config) {
    // 1. 启动 E2E 计时器
    let _phase_one_e2e_timer = session.services.session_telemetry
        .start_timer(metrics::MEMORY_PHASE_ONE_E2E_MS, &[])
        .ok();

    // 2. 声明启动作业
    let Some(claimed_candidates) = claim_startup_jobs(session, &config.memories).await else {
        return;
    };
    if claimed_candidates.is_empty() {
        // 记录跳过指标
        return;
    }

    // 3. 构建请求上下文
    let stage_one_context = build_request_context(session, config).await;

    // 4. 并行运行作业
    let outcomes = run_jobs(session, claimed_candidates, stage_one_context).await;

    // 5. 聚合统计和指标
    let counts = aggregate_stats(outcomes);
    emit_metrics(session, &counts);
    info!("memory stage-1 extraction complete: ...");
}
```

### 作业声明

```rust
async fn claim_startup_jobs(
    session: &Arc<Session>,
    memories_config: &MemoriesConfig,
) -> Option<Vec<codex_state::Stage1JobClaim>> {
    let state_db = session.services.state_db.as_deref()?;
    
    let allowed_sources = INTERACTIVE_SESSION_SOURCES
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>();

    state_db
        .claim_stage1_jobs_for_startup(
            session.conversation_id,
            codex_state::Stage1StartupClaimParams {
                scan_limit: phase_one::THREAD_SCAN_LIMIT,
                max_claimed: memories_config.max_rollouts_per_startup,
                max_age_days: memories_config.max_rollout_age_days,
                min_rollout_idle_hours: memories_config.min_rollout_idle_hours,
                allowed_sources: allowed_sources.as_slice(),
                lease_seconds: phase_one::JOB_LEASE_SECONDS,
            },
        )
        .await
        .ok()
}
```

### 并行作业执行

```rust
async fn run_jobs(
    session: &Arc<Session>,
    claimed_candidates: Vec<codex_state::Stage1JobClaim>,
    stage_one_context: RequestContext,
) -> Vec<JobResult> {
    futures::stream::iter(claimed_candidates.into_iter())
        .map(|claim| {
            let session = Arc::clone(session);
            let stage_one_context = stage_one_context.clone();
            async move { job::run(session.as_ref(), claim, &stage_one_context).await }
        })
        .buffer_unordered(phase_one::CONCURRENCY_LIMIT)  // 并发限制：8
        .collect::<Vec<_>>()
        .await
}
```

### 单个作业执行

```rust
mod job {
    pub(in crate::memories) async fn run(
        session: &Session,
        claim: codex_state::Stage1JobClaim,
        stage_one_context: &RequestContext,
    ) -> JobResult {
        let thread = claim.thread;
        
        // 1. 采样（调用模型）
        let (stage_one_output, token_usage) = match sample(
            session,
            &thread.rollout_path,
            &thread.cwd,
            stage_one_context,
        ).await {
            Ok(output) => output,
            Err(reason) => {
                result::failed(session, thread.id, &claim.ownership_token, &reason.to_string()).await;
                return JobResult { outcome: JobOutcome::Failed, token_usage: None };
            }
        };

        // 2. 检查结果
        if stage_one_output.raw_memory.is_empty() || stage_one_output.rollout_summary.is_empty() {
            return JobResult {
                outcome: result::no_output(session, thread.id, &claim.ownership_token).await,
                token_usage,
            };
        }

        // 3. 标记成功
        JobResult {
            outcome: result::success(
                session,
                thread.id,
                &claim.ownership_token,
                thread.updated_at.timestamp(),
                &stage_one_output.raw_memory,
                &stage_one_output.rollout_summary,
                stage_one_output.rollout_slug.as_deref(),
            ).await,
            token_usage,
        }
    }
}
```

### 模型采样

```rust
async fn sample(
    session: &Session,
    rollout_path: &Path,
    rollout_cwd: &Path,
    stage_one_context: &RequestContext,
) -> anyhow::Result<(StageOneOutput, Option<TokenUsage>)> {
    // 1. 加载 rollout 项目
    let (rollout_items, _, _) = RolloutRecorder::load_rollout_items(rollout_path).await?;
    let rollout_contents = serialize_filtered_rollout_response_items(&rollout_items)?;

    // 2. 构建提示
    let prompt = Prompt {
        input: vec![ResponseItem::Message {
            id: None,
            role: "user".to_string(),
            content: vec![ContentItem::InputText {
                text: build_stage_one_input_message(
                    &stage_one_context.model_info,
                    rollout_path,
                    rollout_cwd,
                    &rollout_contents,
                )?,
            }],
            end_turn: None,
            phase: None,
        }],
        tools: Vec::new(),
        parallel_tool_calls: false,
        base_instructions: BaseInstructions {
            text: phase_one::PROMPT.to_string(),
        },
        personality: None,
        output_schema: Some(output_schema()),
    };

    // 3. 流式调用模型
    let mut client_session = session.services.model_client.new_session();
    let mut stream = client_session.stream(...).await?;

    // 4. 收集输出
    let mut result = String::new();
    let mut token_usage = None;
    while let Some(message) = stream.next().await.transpose()? {
        match message {
            ResponseEvent::OutputTextDelta(delta) => result.push_str(&delta),
            ResponseEvent::OutputItemDone(item) => { /* 处理完整项目 */ }
            ResponseEvent::Completed { token_usage: usage, .. } => {
                token_usage = usage;
                break;
            }
            _ => {}
        }
    }

    // 5. 解析并编辑 secrets
    let mut output: StageOneOutput = serde_json::from_str(&result)?;
    output.raw_memory = redact_secrets(output.raw_memory);
    output.rollout_summary = redact_secrets(output.rollout_summary);
    output.rollout_slug = output.rollout_slug.map(redact_secrets);

    Ok((output, token_usage))
}
```

### 内容过滤

```rust
fn serialize_filtered_rollout_response_items(
    items: &[RolloutItem],
) -> crate::error::Result<String> {
    let filtered = items
        .iter()
        .filter_map(|item| {
            if let RolloutItem::ResponseItem(item) = item {
                sanitize_response_item_for_memories(item)
            } else {
                None
            }
        })
        .collect::<Vec<_>>();
    serde_json::to_string(&filtered).map_err(...)
}

fn sanitize_response_item_for_memories(item: &ResponseItem) -> Option<ResponseItem> {
    let ResponseItem::Message { id, role, content, end_turn, phase } = item else {
        return should_persist_response_item_for_memories(item).then(|| item.clone());
    };

    // 跳过开发者消息
    if role == "developer" {
        return None;
    }

    // 非用户消息直接保留
    if role != "user" {
        return Some(item.clone());
    }

    // 过滤用户消息中的特定内容
    let content = content
        .iter()
        .filter(|content_item| !is_memory_excluded_contextual_user_fragment(content_item))
        .cloned()
        .collect::<Vec<_>>();
    
    if content.is_empty() {
        return None;
    }

    Some(ResponseItem::Message { id: id.clone(), role: role.clone(), content, end_turn: *end_turn, phase: phase.clone() })
}
```

### 输出 Schema

```rust
pub fn output_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "rollout_summary": { "type": "string" },
            "rollout_slug": { "type": ["string", "null"] },
            "raw_memory": { "type": "string" }
        },
        "required": ["rollout_summary", "rollout_slug", "raw_memory"],
        "additionalProperties": false
    })
}
```

### 清理过期记忆

```rust
pub(in crate::memories) async fn prune(session: &Arc<Session>, config: &Config) {
    if let Some(db) = session.services.state_db.as_deref() {
        let max_unused_days = config.memories.max_unused_days;
        match db.prune_stage1_outputs_for_retention(max_unused_days, PRUNE_BATCH_SIZE).await {
            Ok(pruned) => {
                if pruned > 0 {
                    info!("memory startup pruned {pruned} stale stage-1 output row(s)...");
                }
            }
            Err(err) => {
                warn!("state db prune_stage1_outputs_for_retention failed...");
            }
        }
    }
}
```

## 关键代码路径与文件引用

### 主要函数

| 函数 | 行号 | 描述 |
|------|------|------|
| `run` | 86 | Phase 1 主入口 |
| `prune` | 126 | 清理过期记忆 |
| `output_schema` | 150 | JSON Schema 定义 |
| `RequestContext::from_turn_context` | 164 | 上下文构建 |
| `claim_startup_jobs` | 180 | 作业声明 |
| `build_request_context` | 222 | 请求上下文构建 |
| `run_jobs` | 241 | 并行作业执行 |
| `job::run` | 260 | 单个作业执行 |
| `job::sample` | 313 | 模型采样 |
| `job::result::*` | 392 | 结果处理 |
| `serialize_filtered_rollout_response_items` | 467 | 内容序列化 |
| `sanitize_response_item_for_memories` | 485 | 内容过滤 |
| `aggregate_stats` | 524 | 统计聚合 |
| `emit_metrics` | 554 | 指标发出 |

### 内部模块

| 模块 | 行号 | 描述 |
|------|------|------|
| `job` | 257-522 | 作业执行逻辑 |
| `job::result` | 392-464 | 结果处理子模块 |
| `tests` | 617-619 | 测试模块 |

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::Prompt` | 提示结构 |
| `crate::RolloutRecorder` | Rollout 加载 |
| `crate::codex::Session` | 会话上下文 |
| `crate::config::Config` | 配置 |
| `crate::rollout::INTERACTIVE_SESSION_SOURCES` | 允许的来源 |
| `crate::rollout::policy::should_persist_response_item_for_memories` | 内容保留策略 |
| `crate::contextual_user_message::is_memory_excluded_contextual_user_fragment` | 内容排除 |
| `crate::truncate` | 文本截断 |
| `crate::memories::prompts::build_stage_one_input_message` | 提示构建 |
| `codex_secrets::redact_secrets` | Secrets 编辑 |
| `codex_state` | 数据库操作 |
| `codex_protocol` | 类型定义 |
| `codex_otel` | 遥测 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `futures::StreamExt` | 流处理 |
| `serde::Deserialize` | JSON 反序列化 |
| `serde_json` | JSON 处理 |
| `tracing` | 日志 |

## 风险、边界与改进建议

### 已知风险

1. **内存使用**:
   - `serialize_filtered_rollout_response_items` 可能在大 rollouts 上消耗大量内存
   - 整个 rollout 内容被加载到内存中

2. **模型依赖**:
   - 依赖模型正确遵循 JSON Schema
   - 模型可能生成不符合 schema 的输出

3. **并发竞争**:
   - 多个并发 Phase 1 作业依赖数据库租约协调
   - 时钟不同步可能导致意外行为

4. **Secrets 编辑**:
   - `redact_secrets` 可能遗漏某些敏感信息
   - 依赖正则表达式模式匹配

### 边界条件

1. **空 Rollout**: 过滤后可能无内容，返回空结果
2. **超大 Rollout**: 受 `DEFAULT_STAGE_ONE_ROLLOUT_TOKEN_LIMIT` 限制
3. **模型失败**: 重试机制最多 3 次
4. **数据库不可用**: 优雅跳过，记录警告

### 改进建议

1. **流式处理**:
   - 考虑流式加载 rollout 项目以减少内存使用
   - 使用迭代器而非收集到 Vec

2. **验证增强**:
   - 添加 JSON Schema 验证
   - 检查输出字段长度和格式

3. **错误分类**:
   - 区分可重试错误和永久错误
   - 添加更详细的错误指标

4. **进度追踪**:
   - 添加每个作业的进度事件
   - 支持长时间运行的作业取消

5. **缓存优化**:
   - 缓存已处理的 rollout 哈希
   - 避免重复处理未更改的 rollouts

6. **模型选择**:
   - 根据 rollout 大小动态选择模型
   - 小 rollout 使用更快/更便宜的模型
