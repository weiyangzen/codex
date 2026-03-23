# codex-rs/state/src/runtime/memories.rs 深度研究文档

## 1. 场景与职责

### 1.1 文件定位

`memories.rs` 是 Codex 项目状态管理层的核心模块，位于 `codex-rs/state/src/runtime/` 目录下。它实现了**记忆系统（Memory System）**的持久化运行时接口，负责管理两阶段记忆流水线（Stage-1 / Phase-2）的数据库操作。

### 1.2 核心职责

该文件承担以下关键职责：

1. **Stage-1 记忆提取作业管理**：为每个线程（thread）的 rollout 提取原始记忆（raw memory）和 rollout 摘要
2. **Phase-2 全局整合作业管理**：协调跨线程的记忆整合（consolidation）过程
3. **作业调度与租约管理**：实现分布式作业认领（claim）、心跳（heartbeat）、成功/失败标记
4. **数据保留与清理**：管理记忆数据的过期清理和存储优化
5. **记忆污染处理**：支持标记线程记忆为"污染"（polluted）状态并触发重新整合

### 1.3 业务场景

- **启动时记忆恢复**：当 Codex CLI/TUI 启动时，从历史 rollout 中提取记忆来增强上下文
- **增量记忆更新**：跟踪线程的更新时间，仅对更新的 rollout 重新提取记忆
- **记忆整合**：将多个线程的原始记忆整合为结构化的 memory_summary.md 和 skills/
- **记忆引用追踪**：记录哪些记忆被实际使用过，用于数据保留决策

---

## 2. 功能点目的

### 2.1 数据清除与重置

| 方法 | 目的 |
|------|------|
| `clear_memory_data()` | 删除所有 stage1_outputs 和 memory 相关的 jobs 行，保留线程的 memory_mode |
| `reset_memory_data_for_fresh_start()` | 清除数据的同时，将所有线程的 memory_mode 设为 'disabled'，用于干净启动 |

### 2.2 Stage-1 作业生命周期管理

| 方法 | 目的 |
|------|------|
| `claim_stage1_jobs_for_startup()` | 启动时扫描符合条件的线程，批量认领 Stage-1 提取作业 |
| `try_claim_stage1_job()` | 尝试认领单个线程的 Stage-1 作业，包含并发控制和去重逻辑 |
| `mark_stage1_job_succeeded()` | 标记作业成功，持久化 raw_memory/rollout_summary，触发 Phase-2 排队 |
| `mark_stage1_job_succeeded_no_output()` | 标记成功但无输出，删除已有的 stage1_outputs 行 |
| `mark_stage1_job_failed()` | 标记作业失败，设置重试退避时间，递减重试计数 |

### 2.3 Phase-2 全局整合作业管理

| 方法 | 目的 |
|------|------|
| `enqueue_global_consolidation()` | 将全局整合作业加入队列或推进其 input_watermark |
| `try_claim_global_phase2_job()` | 尝试认领全局 Phase-2 整合作业的独占锁 |
| `heartbeat_global_phase2_job()` | 续约 Phase-2 作业租约，防止被其他 worker 抢占 |
| `mark_global_phase2_job_succeeded()` | 标记 Phase-2 成功，更新 selected_for_phase2 基准 |
| `mark_global_phase2_job_failed()` | 标记 Phase-2 失败，设置重试逻辑 |
| `mark_global_phase2_job_failed_if_unowned()` | 降级失败处理，支持无主作业的状态恢复 |

### 2.4 数据查询与保留

| 方法 | 目的 |
|------|------|
| `list_stage1_outputs_for_global()` | 列出最新的非空 Stage-1 输出供 Phase-2 使用 |
| `get_phase2_input_selection()` | 获取 Phase-2 输入集及其与上一次基准的差异（added/retained/removed） |
| `prune_stage1_outputs_for_retention()` | 根据保留策略清理过期未使用的 Stage-1 输出 |
| `record_stage1_output_usage()` | 记录 Stage-1 输出被引用的情况，更新 usage_count 和 last_usage |
| `mark_thread_memory_mode_polluted()` | 标记线程记忆为污染状态，如参与过 Phase-2 则触发重新整合 |

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 数据库表结构

**stage1_outputs 表**（迁移文件 0006_memories.sql, 0016-0018）：
```sql
CREATE TABLE stage1_outputs (
    thread_id TEXT PRIMARY KEY,
    source_updated_at INTEGER NOT NULL,  -- 线程的 updated_at 时间戳
    raw_memory TEXT NOT NULL,            -- 提取的原始记忆（markdown）
    rollout_summary TEXT NOT NULL,       -- rollout 摘要
    generated_at INTEGER NOT NULL,       -- 生成时间
    rollout_slug TEXT,                   -- rollout 标识（可选）
    usage_count INTEGER,                 -- 被引用次数（0016_migration）
    last_usage INTEGER,                  -- 最后被引用时间（0016_migration）
    selected_for_phase2 INTEGER DEFAULT 0, -- 是否被 Phase-2 选中（0017_migration）
    selected_for_phase2_source_updated_at INTEGER, -- 选中时的源时间戳（0018_migration）
    FOREIGN KEY(thread_id) REFERENCES threads(id) ON DELETE CASCADE
);
```

**jobs 表**（通用作业表，用于记忆系统）：
```sql
CREATE TABLE jobs (
    kind TEXT NOT NULL,                  -- 'memory_stage1' 或 'memory_consolidate_global'
    job_key TEXT NOT NULL,               -- thread_id（stage1）或 'global'（phase2）
    status TEXT NOT NULL,                -- 'pending' | 'running' | 'done' | 'error'
    worker_id TEXT,                      -- 当前执行者（ThreadId）
    ownership_token TEXT,                -- UUID 租约令牌
    started_at INTEGER,
    finished_at INTEGER,
    lease_until INTEGER,                 -- 租约过期时间
    retry_at INTEGER,                    -- 下次重试时间
    retry_remaining INTEGER DEFAULT 3,   -- 剩余重试次数
    last_error TEXT,
    input_watermark INTEGER,             -- 输入源的时间戳
    last_success_watermark INTEGER,      -- 最后成功处理的时间戳
    PRIMARY KEY (kind, job_key)
);
```

#### 3.1.2 Rust 模型类型（codex-rs/state/src/model/memories.rs）

```rust
/// Stage-1 记忆输出
pub struct Stage1Output {
    pub thread_id: ThreadId,
    pub rollout_path: PathBuf,
    pub source_updated_at: DateTime<Utc>,
    pub raw_memory: String,
    pub rollout_summary: String,
    pub rollout_slug: Option<String>,
    pub cwd: PathBuf,
    pub git_branch: Option<String>,
    pub generated_at: DateTime<Utc>,
}

/// Phase-2 输入选择结果
pub struct Phase2InputSelection {
    pub selected: Vec<Stage1Output>,           -- 当前选中的记忆
    pub previous_selected: Vec<Stage1Output>,  -- 上次 Phase-2 选中的记忆
    pub retained_thread_ids: Vec<ThreadId>,    -- 保留下来的线程 ID
    pub removed: Vec<Stage1OutputRef>,         -- 被移除的记忆引用
}

/// Stage-1 作业认领结果
pub enum Stage1JobClaimOutcome {
    Claimed { ownership_token: String },
    SkippedUpToDate,           -- 已有更新或相同的输出
    SkippedRunning,            -- 其他 worker 正在执行
    SkippedRetryBackoff,       -- 处于重试退避期
    SkippedRetryExhausted,     -- 重试次数已耗尽
}

/// Phase-2 作业认领结果
pub enum Phase2JobClaimOutcome {
    Claimed { ownership_token: String, input_watermark: i64 },
    SkippedNotDirty,           -- 无需整合（input_watermark <= last_success_watermark）
    SkippedRunning,            -- 其他 worker 正在执行
}
```

### 3.2 关键流程实现

#### 3.2.1 Stage-1 作业认领流程（try_claim_stage1_job）

```
1. 开启 IMMEDIATE 事务（BEGIN IMMEDIATE）
2. 检查 stage1_outputs：如果 source_updated_at >= 请求的 source_updated_at，返回 SkippedUpToDate
3. 检查 jobs 表的 last_success_watermark：如果 >= 请求的 source_updated_at，返回 SkippedUpToDate
4. 执行复杂的 INSERT ... ON CONFLICT ... DO UPDATE：
   - 仅当全局 running 作业数 < max_running_jobs 时允许插入
   - 冲突时更新：重置状态为 running，更新租约和令牌
   - 条件检查：
     * 当前状态不是 running 或租约已过期
     * 无重试退避或退避已过期或源已更新
     * 剩余重试次数 > 0 或源已更新
5. 如果更新行数 > 0，返回 Claimed
6. 否则查询当前状态并返回具体的跳过原因
```

**关键 SQL 片段**（行 590-667）：
```rust
// INSERT 的 WHERE 子句限制全局并发
WHERE (
    SELECT COUNT(*)
    FROM jobs
    WHERE kind = ? AND status = 'running' AND lease_until IS NOT NULL AND lease_until > ?
) < ?

// ON CONFLICT 时重置 retry_remaining（当源更新时）
retry_remaining = CASE
    WHEN excluded.input_watermark > COALESCE(jobs.input_watermark, -1) THEN ?
    ELSE jobs.retry_remaining
END
```

#### 3.2.2 Phase-2 全局整合流程

```
1. enqueue_global_consolidation_with_executor:
   - UPSERT jobs 表，kind='memory_consolidate_global', job_key='global'
   - 状态逻辑：running 保持 running，其他变为 pending
   - input_watermark 取 max(现有, 新值) 或递增

2. try_claim_global_phase2_job:
   - 检查 input_watermark <= last_success_watermark → SkippedNotDirty
   - 检查 retry_remaining <= 0 → SkippedNotDirty
   - 检查 retry_at > now → SkippedNotDirty
   - 检查 status='running' 且 lease_until > now → SkippedRunning
   - 更新为 running 状态，设置租约和令牌

3. mark_global_phase2_job_succeeded:
   - 验证 ownership_token 和 running 状态
   - 更新 status='done', last_success_watermark=max(现有, completed_watermark)
   - 重置所有 selected_for_phase2=0
   - 为每个选中的输出设置 selected_for_phase2=1 和 snapshot 时间戳
```

#### 3.2.3 Phase-2 输入选择算法（get_phase2_input_selection）

```rust
// 当前选择：非空输出 + 在保留窗口内 + 按使用频率排序
SELECT ... FROM stage1_outputs AS so
LEFT JOIN threads AS t ON t.id = so.thread_id
WHERE t.memory_mode = 'enabled'
  AND (length(trim(so.raw_memory)) > 0 OR length(trim(so.rollout_summary)) > 0)
  AND ((so.last_usage IS NOT NULL AND so.last_usage >= ?)
       OR (so.last_usage IS NULL AND so.source_updated_at >= ?))
ORDER BY COALESCE(so.usage_count, 0) DESC,
         COALESCE(so.last_usage, so.source_updated_at) DESC,
         so.source_updated_at DESC,
         so.thread_id DESC
LIMIT ?

// 之前的选择：所有 selected_for_phase2=1 的行
SELECT ... WHERE so.selected_for_phase2 = 1

// 计算差异：
// - retained: 当前选中且 source_updated_at 匹配之前 snapshot 的
// - removed: 之前选中但现在不在 current_thread_ids 中的
```

### 3.3 并发控制机制

1. **SQLite WAL 模式**：通过 `BEGIN IMMEDIATE` 获取写锁
2. **租约机制**：`lease_until` 字段防止作业被无限期占用
3. **令牌验证**：`ownership_token` 确保只有合法持有者可以更新作业状态
4. **全局并发限制**：Stage-1 通过子查询限制同时运行的作业数

---

## 4. 关键代码路径与文件引用

### 4.1 内部依赖

| 文件 | 用途 |
|------|------|
| `codex-rs/state/src/runtime.rs` | `StateRuntime` 结构体定义，提供 `pool: Arc<SqlitePool>` |
| `codex-rs/state/src/runtime/threads.rs` | `push_thread_filters()`, `push_thread_order_and_limit()` 辅助函数 |
| `codex-rs/state/src/model/memories.rs` | 数据结构定义：`Stage1Output`, `Phase2InputSelection`, `Stage1JobClaimOutcome` 等 |
| `codex-rs/state/src/model/thread_metadata.rs` | `ThreadMetadata`, `ThreadRow` 用于作业认领结果 |
| `codex-rs/state/migrations/0006_memories.sql` | 初始表结构 |
| `codex-rs/state/migrations/0016-0018_*.sql` | 增量迁移：usage 追踪、Phase-2 选择标记 |

### 4.2 外部调用方

| 文件 | 调用方法 | 用途 |
|------|----------|------|
| `codex-rs/core/src/memories/phase1.rs` | `claim_stage1_jobs_for_startup`, `try_claim_stage1_job`, `mark_stage1_job_succeeded/failed` | Stage-1 提取流水线 |
| `codex-rs/core/src/memories/phase2.rs` | `try_claim_global_phase2_job`, `mark_global_phase2_job_succeeded/failed`, `heartbeat_global_phase2_job`, `get_phase2_input_selection` | Phase-2 整合流水线 |
| `codex-rs/core/src/memories/start.rs` | `prune_stage1_outputs_for_retention` (via phase1::prune) | 启动清理 |
| `codex-rs/core/src/memories/usage.rs` | `record_stage1_output_usage` | 记忆引用追踪 |
| `codex-rs/core/src/memories/storage.rs` | `list_stage1_outputs_for_global` | 文件系统同步 |
| `codex-rs/cli/tests/debug_clear_memories.rs` | `clear_memory_data`, `reset_memory_data_for_fresh_start` | CLI 调试命令 |

### 4.3 核心代码行号参考

```
codex-rs/state/src/runtime/memories.rs
├── 常量定义 (20-24)
│   ├── JOB_KIND_MEMORY_STAGE1: &str = "memory_stage1"
│   ├── JOB_KIND_MEMORY_CONSOLIDATE_GLOBAL: &str = "memory_consolidate_global"
│   ├── MEMORY_CONSOLIDATION_JOB_KEY: &str = "global"
│   └── DEFAULT_RETRY_REMAINING: i64 = 3
│
├── 数据清除 (26-83)
│   ├── clear_memory_data() -> anyhow::Result<()>
│   ├── reset_memory_data_for_fresh_start() -> anyhow::Result<()>
│   └── clear_memory_data_inner() 实际实现
│
├── 使用追踪 (85-120)
│   └── record_stage1_output_usage() 更新 usage_count 和 last_usage
│
├── Stage-1 批量认领 (122-252)
│   └── claim_stage1_jobs_for_startup() 启动时扫描和认领
│
├── Stage-1 数据查询 (254-340)
│   ├── list_stage1_outputs_for_global() 列出最新输出
│   └── prune_stage1_outputs_for_retention() 过期清理
│
├── Phase-2 输入选择 (342-473)
│   └── get_phase2_input_selection() 计算 added/retained/removed
│
├── 污染标记 (475-518)
│   └── mark_thread_memory_mode_polluted() 标记污染并触发 Phase-2
│
├── Stage-1 单作业管理 (520-915)
│   ├── try_claim_stage1_job() 核心认领逻辑（590-708 行复杂 SQL）
│   ├── mark_stage1_job_succeeded() 成功处理（710-794）
│   ├── mark_stage1_job_succeeded_no_output() 无输出成功（796-870）
│   └── mark_stage1_job_failed() 失败处理（872-915）
│
├── Phase-2 作业管理 (917-1226)
│   ├── enqueue_global_consolidation() 入队（923-925）
│   ├── try_claim_global_phase2_job() 认领（936-1032）
│   ├── heartbeat_global_phase2_job() 心跳（1034-1063）
│   ├── mark_global_phase2_job_succeeded() 成功（1065-1142）
│   ├── mark_global_phase2_job_failed() 失败（1144-1184）
│   └── mark_global_phase2_job_failed_if_unowned() 无主失败（1186-1226）
│
├── 内部辅助函数 (1229-1278)
│   └── enqueue_global_consolidation_with_executor() 实际 UPSERT 实现
│
└── 单元测试 (1280-2998+)
    ├── stage1_claim_skips_when_up_to_date (1299-1355)
    ├── stage1_running_stale_can_be_stolen (1357-1401)
    ├── stage1_concurrent_claim_for_same_thread_is_conflict_safe (1403-1466)
    ├── claim_stage1_jobs_filters_by_age_idle_and_current_thread (1531-1618)
    ├── get_phase2_input_selection_reports_added_retained_and_removed (2734-2843)
    └── ... 共 20+ 个测试用例
```

---

## 5. 依赖与外部交互

### 5.1 数据库依赖

- **SQLite**（通过 `sqlx` crate）：所有数据持久化
- **WAL 模式**：`SqliteJournalMode::Wal` 支持并发读写
- **外键约束**：`stage1_outputs.thread_id -> threads.id ON DELETE CASCADE`

### 5.2 外部系统交互

| 系统 | 交互方式 | 用途 |
|------|----------|------|
| OpenAI API | 通过 `codex-rs/core/src/memories/phase1.rs` | Stage-1 记忆提取的模型调用 |
| 文件系统 | 通过 `codex-rs/core/src/memories/storage.rs` | 写入 `memories/raw_memories.md` 和 `memories/rollout_summaries/` |
| Agent 系统 | 通过 `codex-rs/core/src/memories/phase2.rs` | Phase-2 作为子 Agent 启动 |
| 遥测/指标 | 通过 `session.services.session_telemetry` | 记录 `codex.memory.phase1/phase2.*` 指标 |

### 5.3 Crate 依赖

```toml
# 核心依赖（通过 use 语句分析）
- sqlx = { version = "0.8", features = ["sqlite", "runtime-tokio"] }
- chrono = "0.4"           # 时间戳处理
- uuid = "1"               # ownership_token 生成
- anyhow = "1"             # 错误处理
- codex_protocol           # ThreadId 等协议类型
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 并发风险

- **SQLite 锁竞争**：`BEGIN IMMEDIATE` 在高压下可能导致 `database is locked` 错误
  - 缓解：测试中已实现重试逻辑（见 `stage1_concurrent_claim_for_same_thread_is_conflict_safe`）
  - 代码位置：测试文件 1426-1442 行

- **租约过期窗口**：如果 worker 在 `lease_until` 过期前崩溃，作业可能处于"假死"状态直到租约过期
  - 缓解：租约过期后其他 worker 可以"窃取"作业

#### 6.1.2 数据一致性风险

- **Phase-2 选中标记与数据不一致**：`selected_for_phase2` 和 `selected_for_phase2_source_updated_at` 可能因崩溃而处于中间状态
  - 缓解：每次 Phase-2 成功时重置所有标记再重新设置

- **外键级联删除**：`threads` 行删除会级联删除 `stage1_outputs`，但 `jobs` 表无级联
  - 可能导致孤儿作业记录

#### 6.1.3 性能风险

- **Stage-1 批量认领的 N+1 查询**：`claim_stage1_jobs_for_startup` 先查询线程列表，然后逐个调用 `try_claim_stage1_job`
  - 每个认领都有独立的 `BEGIN IMMEDIATE` 事务
  - 在高并发启动时可能成为瓶颈

- **Phase-2 输入选择的双查询**：`get_phase2_input_selection` 执行两个大查询（当前选择 + 之前选择）
  - 当记忆数据量大时可能慢

### 6.2 边界条件

| 边界 | 处理 |
|------|------|
| `scan_limit=0` 或 `max_claimed=0` | 立即返回空 Vec |
| `n=0`（查询限制） | 立即返回空结果或 default |
| `limit=0`（清理限制） | 立即返回 0 |
| 空 `thread_ids` | `record_stage1_output_usage` 立即返回 0 |
| `max_age_days` 或 `min_rollout_idle_hours` 为负 | 使用 `.max(0)` 强制为非负 |
| `lease_seconds` 为负 | 使用 `.max(0)` 强制为非负 |
| 重试次数耗尽 | 返回 `SkippedRetryExhausted`，但新源时间戳可重置计数 |

### 6.3 改进建议

#### 6.3.1 架构层面

1. **批量认领优化**：
   - 考虑将 `claim_stage1_jobs_for_startup` 改为真正的批量操作，减少事务数量
   - 可使用 `INSERT ... SELECT` 配合 `RETURNING` 一次性认领多个作业

2. **作业恢复机制**：
   - 添加定期扫描任务，自动重置过期租约的作业状态
   - 或添加心跳超时检测，自动将超时作业标记为可认领

3. **指标增强**：
   - 添加 `codex.memory.stage1.claim_conflict` 计数器，监控锁竞争
   - 添加 `codex.memory.stage1.pruned` 计数器，跟踪清理效果

#### 6.3.2 代码层面

1. **SQL 复杂度**：
   - `try_claim_stage1_job` 中的 SQL（行 590-667）非常复杂，建议拆分为：
     - 先查询当前状态和全局计数
     - 再执行更新
   - 虽然会增加往返次数，但可提高可读性和可维护性

2. **错误处理**：
   - 部分方法使用 `unwrap_or(0)` 处理可选时间戳，可能掩盖数据问题
   - 建议添加 `tracing::warn` 记录异常情况

3. **测试覆盖**：
   - 缺少对 `heartbeat_global_phase2_job` 失败场景的测试
   - 缺少对 `mark_global_phase2_job_failed_if_unowned` 的测试

#### 6.3.3 运维层面

1. **可观测性**：
   - 添加 `selected_for_phase2` 分布的 gauge 指标
   - 添加 `stage1_outputs` 表行数和水位线的监控

2. **配置调优**：
   - `THREAD_SCAN_LIMIT=5000` 和 `PRUNE_BATCH_SIZE=200` 等常量可考虑改为配置项
   - `DEFAULT_RETRY_REMAINING=3` 和重试延迟也可配置化

---

## 7. 总结

`memories.rs` 是 Codex 记忆系统的核心持久化层，实现了复杂的两阶段流水线（Stage-1 提取 + Phase-2 整合）的作业调度。其设计亮点包括：

1. **租约机制**：通过 `ownership_token` 和 `lease_until` 实现安全的分布式作业认领
2. **水位线追踪**：`input_watermark` 和 `last_success_watermark` 确保增量处理正确性
3. **差异计算**：`Phase2InputSelection` 精确追踪记忆的增删改，支持增量整合
4. **容错设计**：重试机制、无主作业恢复、污染标记等处理各种边界情况

该模块与 `codex-rs/core/src/memories/` 下的 `phase1.rs`, `phase2.rs`, `storage.rs` 紧密协作，构成了完整的记忆生命周期管理。
