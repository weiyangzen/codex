# Research: codex-rs/core/src/memories

## 场景与职责

`codex-rs/core/src/memories` 是 Codex CLI 的**记忆系统（Memory System）**核心实现，负责在会话启动时自动提取和整合历史会话记忆，帮助未来的 Agent 更好地理解用户偏好、复用已验证的工作流程、避免已知问题。

### 核心职责

1. **启动时记忆管道（Startup Memory Pipeline）**：在根会话启动时异步运行，从 State DB 中提取符合条件的 rollouts 进行处理
2. **两阶段记忆处理**：
   - Phase 1（Rollout 提取）：并行提取多个 rollouts 的结构化记忆
   - Phase 2（全局整合）：串行整合记忆到文件系统产物
3. **记忆产物管理**：维护 `~/.codex/memories/` 目录下的文件结构
4. **记忆引用跟踪**：处理 Agent 对记忆文件的引用和引用计数

### 触发条件

记忆管道仅在以下情况触发：
- 会话不是临时的（`!config.ephemeral`）
- MemoryTool 功能已启用（`config.features.enabled(Feature::MemoryTool)`）
- 不是子 Agent 会话（`!matches(source, SessionSource::SubAgent(_))`）
- State DB 可用（`session.services.state_db.is_some()`）

## 功能点目的

### 1. Phase 1: Rollout 提取（`phase1.rs`）

**目的**：从历史 rollouts 中提取结构化的原始记忆（raw memories）和 rollout 摘要。

**关键流程**：
1. **声明启动任务**：从 State DB 声明符合条件的 rollout 任务（`claim_stage1_jobs_for_startup`）
2. **过滤 rollout 内容**：只保留与记忆相关的响应项，过滤掉开发者消息和内存排除的上下文片段
3. **LLM 提取**：使用 `gpt-5.1-codex-mini` 模型并行处理 rollouts，生成：
   - `raw_memory`: 详细的 Markdown 格式原始记忆
   - `rollout_summary`: 紧凑的摘要行
   - `rollout_slug`: 可选的文件名 slug
4. **敏感信息脱敏**：使用 `codex_secrets::redact_secrets` 自动脱敏 secrets
5. **结果存储**：将成功提取的记忆存储到 State DB 的 `stage1_outputs` 表

**任务结果类型**：
- `SucceededWithOutput`: 成功生成记忆
- `SucceededNoOutput`: 成功运行但无有效输出
- `Failed`: 失败（带重试退避）

### 2. Phase 2: 全局整合（`phase2.rs`）

**目的**：将 Stage-1 输出整合到文件系统记忆产物，并运行专门的整合 Agent。

**关键流程**：
1. **声明全局任务**：获取全局 Phase-2 任务锁（确保只有一个整合任务运行）
2. **查询记忆输入**：从 State DB 获取 Phase-2 输入选择（包含当前选择、之前选择、保留/新增/移除的 diff）
3. **同步文件系统产物**：
   - `rollout_summaries/`: 每个保留 rollout 的摘要文件
   - `raw_memories.md`: 合并的原始记忆文件
4. **清理过期产物**：删除不再保留的 rollout 摘要文件
5. **生成整合提示**：构建包含输入 diff 的 consolidation prompt
6. **启动整合 Agent**：作为内部子 Agent 运行（无审批、无网络、仅本地写入）
7. **监控 Agent 状态**：心跳维护任务租约，直到 Agent 完成

**Agent 配置**：
- 模型：`gpt-5.3-codex`
- 审批策略：`AskForApproval::Never`
- 沙盒策略：`WorkspaceWrite`（仅 codex_home 可写）
- 禁用功能：`SpawnCsv`, `Collab`, `MemoryTool`（防止递归）

### 3. 存储管理（`storage.rs`）

**目的**：管理记忆文件系统产物的读写和清理。

**核心功能**：
- `rebuild_raw_memories_file_from_memories`: 从 DB 记忆重建 `raw_memories.md`
- `sync_rollout_summaries_from_memories`: 同步 rollout 摘要文件
- `rollout_summary_file_stem`: 生成规范的文件名（格式：`{timestamp}-{short_hash}[-{slug}]`）

**文件名生成规则**：
- 时间戳：从 UUID v7 提取或回退到 `source_updated_at`
- 短哈希：UUID 后 4 位或 thread_id 的哈希
- Slug：清理后的 rollout_slug（最多 60 字符，小写+数字+下划线）

### 4. 提示模板（`prompts.rs`）

**目的**：使用 Askama 模板引擎构建 LLM 提示。

**模板文件**（位于 `codex-rs/core/templates/memories/`）：
- `stage_one_system.md`: Phase 1 系统提示（569 行详细指令）
- `stage_one_input.md`: Phase 1 用户输入模板
- `consolidation.md`: Phase 2 整合提示（835 行详细指令）
- `read_path.md`: Memory Tool 开发者指令模板

### 5. 引用跟踪（`citations.rs`）

**目的**：解析 Agent 对记忆文件的引用。

**解析格式**：
```xml
<oai-mem-citation>
<citation_entries>
MEMORY.md:234-236|note=[...]
rollout_summaries/2026-02-17T21-23-02-LN3m-weekly_memory_report.md:10-12|note=[...]
</citation_entries>
<rollout_ids>
019c6e27-e55b-73d1-87d8-4e01f1f75043
</rollout_ids>
</oai-mem-citation>
```

### 6. 使用统计（`usage.rs`）

**目的**：跟踪记忆文件被工具读取的使用情况。

**监控的文件类型**：
- `MEMORY.md`
- `memory_summary.md`
- `raw_memories.md`
- `rollout_summaries/`
- `skills/`

### 7. 控制操作（`control.rs`）

**目的**：提供记忆目录的清理功能。

**安全特性**：
- 拒绝清理符号链接目录（防止误删外部目录）
- 保留根目录本身，只清理内容

## 具体技术实现

### 关键数据结构

```rust
// Phase 1 模型输出（位于 phase1.rs）
struct StageOneOutput {
    raw_memory: String,
    rollout_summary: String,
    rollout_slug: Option<String>,
}

// Phase 1 请求上下文
struct RequestContext {
    model_info: ModelInfo,
    session_telemetry: SessionTelemetry,
    reasoning_effort: Option<ReasoningEffortConfig>,
    reasoning_summary: ReasoningSummaryConfig,
    service_tier: Option<ServiceTier>,
    turn_metadata_header: Option<String>,
}

// Phase 2 声明结果
struct Claim {
    token: String,
    watermark: i64,
}

// 统计计数器
struct Counters {
    input: i64,
}
```

### 配置常量（位于 `mod.rs`）

```rust
mod phase_one {
    const MODEL: &str = "gpt-5.1-codex-mini";
    const REASONING_EFFORT: ReasoningEffort = ReasoningEffort::Low;
    const CONCURRENCY_LIMIT: usize = 8;
    const DEFAULT_STAGE_ONE_ROLLOUT_TOKEN_LIMIT: usize = 150_000;
    const CONTEXT_WINDOW_PERCENT: i64 = 70;
    const JOB_LEASE_SECONDS: i64 = 3_600;
    const JOB_RETRY_DELAY_SECONDS: i64 = 3_600;
    const THREAD_SCAN_LIMIT: usize = 5_000;
    const PRUNE_BATCH_SIZE: usize = 200;
}

mod phase_two {
    const MODEL: &str = "gpt-5.3-codex";
    const REASONING_EFFORT: ReasoningEffort = ReasoningEffort::Medium;
    const JOB_LEASE_SECONDS: i64 = 3_600;
    const JOB_RETRY_DELAY_SECONDS: i64 = 3_600;
    const JOB_HEARTBEAT_SECONDS: u64 = 90;
}
```

### State DB 交互（位于 `codex-rs/state/src/runtime/memories.rs`）

**核心方法**：
- `claim_stage1_jobs_for_startup`: 声明 Stage-1 启动任务
- `try_claim_stage1_job`: 尝试声明单个 Stage-1 任务
- `mark_stage1_job_succeeded`: 标记 Stage-1 任务成功并存储输出
- `mark_stage1_job_succeeded_no_output`: 标记成功但无输出
- `mark_stage1_job_failed`: 标记 Stage-1 任务失败并设置重试
- `try_claim_global_phase2_job`: 声明全局 Phase-2 任务
- `mark_global_phase2_job_succeeded`: 标记 Phase-2 成功并更新基线
- `mark_global_phase2_job_failed`: 标记 Phase-2 失败
- `heartbeat_global_phase2_job`: 心跳维护 Phase-2 租约
- `get_phase2_input_selection`: 获取 Phase-2 输入选择（含 diff）
- `prune_stage1_outputs_for_retention`: 清理过期 Stage-1 输出
- `record_stage1_output_usage`: 记录记忆使用

### 文件系统产物结构

```
~/.codex/memories/
├── raw_memories.md          # 合并的原始记忆（Phase 2 输入）
├── MEMORY.md                # 整合后的记忆手册（Phase 2 输出）
├── memory_summary.md        # 记忆摘要（加载到系统提示）
├── rollout_summaries/       # 每个 rollout 的摘要文件
│   ├── 2026-03-20T10-30-00-a1b2-foo_task.md
│   └── 2026-03-19T15-45-00-c3d4-bar_task.md
└── skills/                  # 可复用技能包
    └── skill-name/
        ├── SKILL.md
        ├── scripts/
        ├── templates/
        └── examples/
```

### 入口点

**启动任务**（`start.rs`）：
```rust
pub(crate) fn start_memories_startup_task(
    session: &Arc<Session>,
    config: Arc<Config>,
    source: &SessionSource,
)
```

**调用位置**（`codex.rs`）：
1. 会话创建时（`Session::new` 后，第 1980 行）
2. 手动更新记忆时（`update_memories` 方法，第 4917 行）

**清理记忆**（`codex.rs` 第 4879-4880 行）：
```rust
let memory_root = crate::memories::memory_root(&config.codex_home);
crate::memories::clear_memory_root_contents(&memory_root).await;
```

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 | 行数 |
|------|------|------|
| `mod.rs` | 模块入口、常量定义、路径函数 | 115 |
| `start.rs` | 启动任务入口 | 44 |
| `phase1.rs` | Phase 1 提取逻辑 | 619 |
| `phase2.rs` | Phase 2 整合逻辑 | 498 |
| `storage.rs` | 文件系统存储管理 | 260 |
| `prompts.rs` | 提示模板构建 | 183 |
| `citations.rs` | 引用解析 | 89 |
| `usage.rs` | 使用统计 | 129 |
| `control.rs` | 清理控制 | 33 |
| `tests.rs` | 集成测试 | 920 |

### 模板文件

| 文件 | 用途 | 行数 |
|------|------|------|
| `templates/memories/stage_one_system.md` | Phase 1 系统提示 | 569 |
| `templates/memories/stage_one_input.md` | Phase 1 输入模板 | 11 |
| `templates/memories/consolidation.md` | Phase 2 整合提示 | 835 |
| `templates/memories/read_path.md` | Memory Tool 开发者指令 | 129 |

### 外部依赖

| 模块 | 用途 |
|------|------|
| `codex_state::runtime::memories` | State DB 记忆操作 |
| `codex_protocol::memory_citation` | 记忆引用类型 |
| `codex_secrets::redact_secrets` | 敏感信息脱敏 |
| `askama::Template` | 提示模板渲染 |

## 依赖与外部交互

### 上游依赖（调用方）

1. **`codex.rs`**：
   - `Session::new` 后启动记忆管道
   - `drop_memories` 命令清理记忆
   - `update_memories` 命令手动触发更新
   - `build_memory_tool_developer_instructions` 构建开发者指令

2. **`stream_events_utils.rs`**：
   - 使用 `parse_memory_citation` 解析记忆引用
   - 使用 `get_thread_id_from_citations` 提取 thread IDs

3. **`tools/registry.rs`**：
   - 调用 `emit_metric_for_tool_read` 记录记忆文件读取

### 下游依赖（被调用方）

1. **`codex_state`**：
   - `StateRuntime` 提供记忆相关的数据库操作
   - `Stage1Output`, `Phase2InputSelection` 等数据类型

2. **`codex_protocol`**：
   - `ThreadId`, `SessionSource`, `SubAgentSource`
   - `MemoryCitation`, `MemoryCitationEntry`

3. **`codex_secrets`**：
   - `redact_secrets` 函数用于脱敏

4. **内部模块**：
   - `RolloutRecorder::load_rollout_items` 加载 rollout
   - `AgentControl::spawn_agent` 启动整合 Agent
   - `SessionTelemetry` 记录指标

### 配置依赖

**`MemoriesConfig`**（`config/types.rs` 第 424-436 行）：
```rust
pub struct MemoriesConfig {
    pub no_memories_if_mcp_or_web_search: bool,
    pub generate_memories: bool,
    pub use_memories: bool,
    pub max_raw_memories_for_consolidation: usize,  // 默认 256
    pub max_unused_days: i64,                       // 默认 30
    pub max_rollout_age_days: i64,                  // 默认 30
    pub max_rollouts_per_startup: usize,            // 默认 16
    pub min_rollout_idle_hours: i64,                // 默认 6
    pub extract_model: Option<String>,
    pub consolidation_model: Option<String>,
}
```

**Feature Flag**：`Feature::MemoryTool`（`features.rs` 第 136 行）
- 阶段：`UnderDevelopment`
- 默认：禁用
- 键名：`"memories"`

## 风险、边界与改进建议

### 已知风险

1. **并发竞争**：
   - Phase 1 使用 `buffer_unordered(CONCURRENCY_LIMIT)` 并行处理，但依赖 State DB 的租约机制防止重复处理
   - Phase 2 使用全局任务锁确保单实例运行，但存在小概率的 race condition（代码注释 TODO）

2. **资源消耗**：
   - Phase 1 可能同时处理最多 8 个 rollouts，每个 rollout 可能包含大量 token
   - Phase 2 启动的整合 Agent 会消耗额外的 LLM tokens

3. **数据一致性**：
   - 文件系统产物和 State DB 之间可能存在不一致（如进程崩溃后）
   - `raw_memories.md` 和 `rollout_summaries/` 是冗余存储，需要同步维护

4. **隐私泄露风险**：
   - 虽然使用 `redact_secrets` 脱敏，但无法保证 100% 覆盖所有敏感模式
   - rollouts 可能包含用户敏感信息，需要谨慎处理

### 边界情况

1. **空记忆处理**：
   - 当没有符合条件的 rollouts 时，Phase 1 跳过，Phase 2 清理现有产物
   - 当所有记忆都被移除时，清理 `MEMORY.md`, `memory_summary.md`, `skills/` 目录

2. **符号链接安全**：
   - `clear_memory_root_contents` 明确拒绝清理符号链接目录，防止误删

3. **重试机制**：
   - Stage-1 和 Phase-2 都有重试机制（默认 3 次），但需要手动触发或等待下次启动

4. **租约过期**：
   - 任务租约默认 1 小时，过期后可被其他 worker 抢占
   - Phase-2 有心跳机制（90 秒间隔）维护租约

### 改进建议

1. **可观测性**：
   - 当前指标主要关注任务数量和 token 使用，建议增加：
     - 记忆质量评分（用户反馈循环）
     - 记忆命中率（实际被引用的比例）
     - 整合 Agent 产出的文件变更统计

2. **性能优化**：
   - Phase 1 的 rollout 过滤可以在加载前进行更激进的裁剪
   - 考虑增量更新 `raw_memories.md` 而非全量重建

3. **可靠性**：
   - 添加文件系统产物和 DB 状态的一致性检查机制
   - 考虑添加记忆备份/恢复功能

4. **功能扩展**：
   - 支持用户手动标记重要记忆（提升优先级）
   - 支持记忆的版本控制和回滚
   - 支持跨设备的记忆同步

5. **安全加固**：
   - 增强 secret 检测模式，覆盖更多类型的敏感信息
   - 添加记忆内容的加密存储选项

### 测试覆盖

测试文件 `tests.rs` 包含 920 行测试代码，覆盖：
- 路径函数测试
- JSON Schema 验证
- 清理操作测试（包括符号链接拒绝）
- 文件同步测试
- 文件名生成测试
- Phase 2 水印逻辑测试
- Phase 2 任务调度测试（跳过、重试、失败处理）

建议补充：
- Phase 1 的 LLM 调用 mock 测试
- 整合 Agent 的端到端测试
- 并发竞争场景的压力测试
