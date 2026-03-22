# codex-rs/state/src/runtime 深度研究文档

## 目录
1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 模块定位

`codex-rs/state/src/runtime` 是 Codex CLI 项目的**核心状态管理层**，负责将 rollout 元数据从 JSONL 文件提取并镜像到本地 SQLite 数据库中。该模块是 `codex-state` crate 的核心实现，为整个应用程序提供持久化状态管理能力。

### 1.2 核心职责

| 职责领域 | 说明 |
|---------|------|
| **线程元数据管理** | 存储和管理对话线程的元数据（创建时间、模型、token 使用量等） |
| **Agent 任务管理** | 支持批量 Agent 任务的创建、执行和状态跟踪 |
| **日志存储与查询** | 提供结构化日志存储，支持按线程、级别、时间范围查询 |
| **内存系统支持** | 为两阶段内存系统（Stage-1 提取 + Stage-2 整合）提供数据层支持 |
| **数据回填** | 管理历史 rollout 文件的元数据回填过程 |

### 1.3 架构位置

```
┌─────────────────────────────────────────────────────────────┐
│                      调用方 (Consumers)                      │
├─────────────────────────────────────────────────────────────┤
│  codex-cli    codex-app-server    codex-tui    codex-core   │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              codex-state (StateRuntime)                     │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────┐   │
│  │   threads   │ │  agent_jobs │ │       logs          │   │
│  └─────────────┘ └─────────────┘ └─────────────────────┘   │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────┐   │
│  │  memories   │ │   backfill  │ │    test_support     │   │
│  └─────────────┘ └─────────────┘ └─────────────────────┘   │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              SQLite (state_5.sqlite + logs_1.sqlite)         │
└─────────────────────────────────────────────────────────────┘
```

---

## 功能点目的

### 2.1 主要功能模块

#### 2.1.1 StateRuntime - 核心运行时

`StateRuntime` 是状态管理的主入口，采用**双数据库架构**：

- **State DB** (`state_5.sqlite`): 存储线程元数据、Agent 任务、内存系统状态
- **Logs DB** (`logs_1.sqlite`): 独立存储日志，减少锁竞争

```rust
#[derive(Clone)]
pub struct StateRuntime {
    codex_home: PathBuf,
    default_provider: String,
    pool: Arc<sqlx::SqlitePool>,      // State DB 连接池
    logs_pool: Arc<sqlx::SqlitePool>, // Logs DB 连接池
}
```

#### 2.1.2 线程管理 (threads.rs)

| 功能 | 方法 | 说明 |
|-----|------|------|
| 获取线程 | `get_thread()` | 通过 ID 获取线程元数据 |
| 列表查询 | `list_threads()` | 支持分页、排序、过滤的线程列表 |
| 增量更新 | `apply_rollout_items()` | 从 rollout 事件增量更新元数据 |
| 动态工具 | `persist_dynamic_tools()` | 存储线程级别的动态工具定义 |
| 归档管理 | `mark_archived/unarchived()` | 线程归档状态管理 |

#### 2.1.3 Agent 任务管理 (agent_jobs.rs)

支持**批量任务处理模式**：

```rust
pub async fn create_agent_job(
    &self,
    params: &AgentJobCreateParams,
    items: &[AgentJobItemCreateParams],
) -> anyhow::Result<AgentJob>
```

任务状态流转：`Pending → Running → Completed/Failed/Cancelled`

#### 2.1.4 日志管理 (logs.rs)

**分区保留策略**：
- 按 `thread_id` 分区（线程相关日志）
- 按 `process_uuid` 分区（无线程日志）
- 每个分区限制：**10 MiB** 或 **1000 条记录**

```rust
const LOG_PARTITION_SIZE_LIMIT_BYTES: i64 = 10 * 1024 * 1024;
const LOG_PARTITION_ROW_LIMIT: i64 = 1_000;
```

#### 2.1.5 内存系统 (memories.rs)

两阶段内存架构的数据层支持：

| 阶段 | 表/任务 | 说明 |
|-----|---------|------|
| Stage-1 | `stage1_outputs` | 单线程记忆提取结果 |
| Stage-1 | `jobs` (memory_stage1) | 提取任务队列 |
| Stage-2 | `jobs` (memory_consolidate_global) | 全局整合任务 |

**关键特性**：
- 基于租约（lease）的分布式任务认领
- 自动重试机制（默认 3 次重试）
- 全局并发控制（`max_running_jobs`）

#### 2.1.6 数据回填 (backfill.rs)

管理历史 rollout 文件的元数据迁移：
- 单例回填 worker（通过 `try_claim_backfill()` 实现）
- 支持断点续传（`last_watermark`）
- 自动清理旧版本数据库文件

---

## 具体技术实现

### 3.1 数据库架构

#### 3.1.1 State DB Schema

**核心表结构**（简化）：

```sql
-- 线程元数据表
CREATE TABLE threads (
    id TEXT PRIMARY KEY,
    rollout_path TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    source TEXT NOT NULL,
    model_provider TEXT NOT NULL,
    cwd TEXT NOT NULL,
    title TEXT NOT NULL,
    sandbox_policy TEXT NOT NULL,
    approval_mode TEXT NOT NULL,
    tokens_used INTEGER NOT NULL DEFAULT 0,
    archived INTEGER NOT NULL DEFAULT 0,
    archived_at INTEGER,
    git_sha TEXT,
    git_branch TEXT,
    git_origin_url TEXT,
    memory_mode TEXT DEFAULT 'enabled'
);

-- Stage-1 记忆输出表
CREATE TABLE stage1_outputs (
    thread_id TEXT PRIMARY KEY,
    source_updated_at INTEGER NOT NULL,
    raw_memory TEXT NOT NULL,
    rollout_summary TEXT NOT NULL,
    rollout_slug TEXT,
    generated_at INTEGER NOT NULL,
    usage_count INTEGER DEFAULT 0,
    last_usage INTEGER,
    selected_for_phase2 INTEGER DEFAULT 0,
    selected_for_phase2_source_updated_at INTEGER
);

-- 任务队列表（通用任务 + 内存任务）
CREATE TABLE jobs (
    kind TEXT NOT NULL,
    job_key TEXT NOT NULL,
    status TEXT NOT NULL,
    worker_id TEXT,
    ownership_token TEXT,
    started_at INTEGER,
    finished_at INTEGER,
    lease_until INTEGER,
    retry_at INTEGER,
    retry_remaining INTEGER NOT NULL,
    last_error TEXT,
    input_watermark INTEGER,
    last_success_watermark INTEGER,
    PRIMARY KEY (kind, job_key)
);

-- Agent 批量任务表
CREATE TABLE agent_jobs (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    status TEXT NOT NULL,
    instruction TEXT NOT NULL,
    output_schema_json TEXT,
    input_headers_json TEXT NOT NULL,
    input_csv_path TEXT NOT NULL,
    output_csv_path TEXT NOT NULL,
    auto_export INTEGER NOT NULL DEFAULT 1,
    max_runtime_seconds INTEGER,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    started_at INTEGER,
    completed_at INTEGER,
    last_error TEXT
);

CREATE TABLE agent_job_items (
    job_id TEXT NOT NULL,
    item_id TEXT NOT NULL,
    row_index INTEGER NOT NULL,
    source_id TEXT,
    row_json TEXT NOT NULL,
    status TEXT NOT NULL,
    assigned_thread_id TEXT,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    result_json TEXT,
    last_error TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    completed_at INTEGER,
    reported_at INTEGER,
    PRIMARY KEY (job_id, item_id)
);
```

#### 3.1.2 Logs DB Schema

```sql
CREATE TABLE logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts INTEGER NOT NULL,
    ts_nanos INTEGER NOT NULL,
    level TEXT NOT NULL,
    target TEXT NOT NULL,
    feedback_log_body TEXT,
    module_path TEXT,
    file TEXT,
    line INTEGER,
    thread_id TEXT,
    process_uuid TEXT,
    estimated_bytes INTEGER NOT NULL DEFAULT 0
);
```

### 3.2 关键数据流

#### 3.2.1 Rollout 元数据提取流程

```
rollout.jsonl → RolloutItem → apply_rollout_item() → ThreadMetadata → SQLite
```

**事件类型映射**：

| RolloutItem 类型 | 处理的元数据字段 |
|-----------------|----------------|
| `SessionMeta` | source, agent_nickname, agent_role, model_provider, cwd, git_* |
| `TurnContext` | model, reasoning_effort, sandbox_policy, approval_mode |
| `EventMsg::TokenCount` | tokens_used |
| `EventMsg::UserMessage` | title, first_user_message |

#### 3.2.2 日志插入与修剪流程

```rust
pub async fn insert_logs(&self, entries: &[LogEntry]) -> anyhow::Result<()> {
    // 1. 批量插入
    let mut tx = self.logs_pool.begin().await?;
    builder.push_values(entries, |mut row, entry| { ... });
    builder.build().execute(&mut *tx).await?;
    
    // 2. 触发修剪（同事务内）
    self.prune_logs_after_insert(entries, &mut tx).await?;
    tx.commit().await?;
}
```

**修剪策略**：
- 使用窗口函数计算累积字节数
- 删除超出预算的最旧记录
- 按 `thread_id` 和 `process_uuid` 分别处理

#### 3.2.3 Stage-1 任务认领流程

```rust
pub async fn try_claim_stage1_job(
    &self,
    thread_id: ThreadId,
    worker_id: ThreadId,
    source_updated_at: i64,
    lease_seconds: i64,
    max_running_jobs: usize,
) -> anyhow::Result<Stage1JobClaimOutcome>
```

**认领条件**（SQL 层面原子判断）：
1. 现有输出不是最新的（`source_updated_at` 检查）
2. 没有正在运行的有效租约
3. 全局运行任务数未超过上限
4. 重试次数未耗尽或源数据已更新

### 3.3 事务与并发控制

#### 3.3.1 SQLite 配置

```rust
async fn open_sqlite(path: &Path, migrator: &'static Migrator) -> anyhow::Result<SqlitePool> {
    let options = SqliteConnectOptions::new()
        .filename(path)
        .create_if_missing(true)
        .journal_mode(SqliteJournalMode::Wal)  // WAL 模式
        .synchronous(SqliteSynchronous::Normal)
        .busy_timeout(Duration::from_secs(5));
    
    let pool = SqlitePoolOptions::new()
        .max_connections(5)
        .connect_with(options)
        .await?;
    migrator.run(&pool).await?;
    Ok(pool)
}
```

#### 3.3.2 关键事务模式

| 场景 | 事务隔离 | 说明 |
|-----|---------|------|
| Stage-1 任务认领 | `BEGIN IMMEDIATE` | 防止并发冲突 |
| Stage-2 任务认领 | `BEGIN IMMEDIATE` | 全局单例任务 |
| Agent 任务创建 | 默认 | 插入 job + items |
| 日志插入+修剪 | 默认 | 保证原子性 |

---

## 关键代码路径与文件引用

### 4.1 核心文件结构

```
codex-rs/state/src/
├── lib.rs                    # 模块导出、常量定义
├── runtime.rs                # StateRuntime 定义与初始化
├── runtime/
│   ├── threads.rs            # 线程元数据管理 (1000+ 行)
│   ├── agent_jobs.rs         # Agent 任务管理 (684 行)
│   ├── logs.rs               # 日志存储与查询 (1524 行)
│   ├── memories.rs           # 内存系统支持 (1900+ 行)
│   ├── backfill.rs           # 数据回填 (311 行)
│   └── test_support.rs       # 测试工具 (68 行)
├── model/
│   ├── mod.rs                # 模型模块导出
│   ├── thread_metadata.rs    # ThreadMetadata 定义
│   ├── agent_job.rs          # AgentJob 相关类型
│   ├── memories.rs           # Stage1Output 等类型
│   ├── log.rs                # LogEntry 定义
│   └── backfill_state.rs     # BackfillState 定义
├── extract.rs                # RolloutItem 处理逻辑
├── migrations.rs             # 迁移管理
└── paths.rs                  # 路径工具
```

### 4.2 关键代码路径

#### 4.2.1 初始化路径

```
StateRuntime::init()
  ├── tokio::fs::create_dir_all(&codex_home)
  ├── remove_legacy_db_files()           # 清理旧版本数据库
  ├── open_sqlite(state_path)            # 打开 State DB
  │   └── STATE_MIGRATOR.run()           # 执行迁移
  ├── open_sqlite(logs_path)             # 打开 Logs DB
  │   └── LOGS_MIGRATOR.run()            # 执行迁移
  └── Arc::new(StateRuntime { ... })
```

**文件**: `codex-rs/state/src/runtime.rs:77-124`

#### 4.2.2 Rollout 增量更新路径

```
StateRuntime::apply_rollout_items()
  ├── get_thread()                       # 获取现有元数据
  ├── builder.build()                    # 构建新元数据
  ├── apply_rollout_item()               # 应用每个 RolloutItem
  │   ├── apply_session_meta()
  │   ├── apply_turn_context()
  │   ├── apply_event_msg()
  │   └── apply_response_item()
  ├── upsert_thread()                    # 写入数据库
  ├── set_thread_memory_mode()           # 更新记忆模式
  └── persist_dynamic_tools()            # 保存动态工具
```

**文件**: `codex-rs/state/src/runtime/threads.rs:472-526`

#### 4.2.3 Stage-1 任务认领路径

```
StateRuntime::try_claim_stage1_job()
  ├── BEGIN IMMEDIATE                    # 获取排他锁
  ├── 检查现有 stage1_outputs            # 是否已是最新
  ├── 检查现有 jobs 记录                 # 是否已是最新
  ├── INSERT/UPDATE jobs                 # 尝试认领
  │   └── 子查询检查全局运行任务数
  └── 返回 Stage1JobClaimOutcome
```

**文件**: `codex-rs/state/src/runtime/memories.rs:536-708`

#### 4.2.4 日志修剪路径

```
StateRuntime::prune_logs_after_insert()
  ├── 收集涉及的 thread_ids
  ├── 预检查超出限制的线程
  │   └── 按 thread_id 分组 HAVING SUM(estimated_bytes) > limit
  ├── 执行删除（窗口函数）
  │   └── SUM(estimated_bytes) OVER (PARTITION BY thread_id ORDER BY ts DESC)
  ├── 重复上述流程处理 threadless logs
  └── 处理 NULL process_uuid 的特殊情况
```

**文件**: `codex-rs/state/src/runtime/logs.rs:60-284`

### 4.3 数据库迁移文件

| 迁移文件 | 说明 |
|---------|------|
| `migrations/0001_threads.sql` | 初始线程表 |
| `migrations/0006_memories.sql` | Stage-1 输出表 + 任务队列表 |
| `migrations/0014_agent_jobs.sql` | Agent 批量任务表 |
| `migrations/0016_memory_usage.sql` | 记忆使用统计字段 |
| `migrations/0017_phase2_selection_flag.sql` | Phase-2 选择标记 |
| `logs_migrations/0001_logs.sql` | 初始日志表 |
| `logs_migrations/0002_logs_feedback_log_body.sql` | 反馈日志字段 |

---

## 依赖与外部交互

### 5.1 外部依赖

#### 5.1.1 核心依赖 (Cargo.toml)

```toml
[dependencies]
anyhow = { workspace = true }
chrono = { workspace = true }
clap = { workspace = true, features = ["derive", "env"] }
codex-protocol = { workspace = true }    # 协议类型
dirs = { workspace = true }
log = { workspace = true }
owo-colors = { workspace = true }
serde = { workspace = true }
serde_json = { workspace = true }
sqlx = { workspace = true }              # 异步 SQLite
tokio = { workspace = true }             # 异步运行时
tracing = { workspace = true }
uuid = { workspace = true }
```

#### 5.1.2 SQLx 迁移

```rust
// migrations.rs
pub(crate) static STATE_MIGRATOR: Migrator = sqlx::migrate!("./migrations");
pub(crate) static LOGS_MIGRATOR: Migrator = sqlx::migrate!("./logs_migrations");
```

### 5.2 调用方模块

| 调用方 | 用途 |
|-------|------|
| `codex-cli` | 初始化状态数据库，启动回填 |
| `codex-app-server` | 线程列表、元数据查询、动态工具 |
| `codex-tui` | 线程列表、状态显示 |
| `codex-core` | Rollout 记录、内存系统、状态同步 |

### 5.3 关键接口调用示例

#### 5.3.1 Core 层封装 (core/src/state_db.rs)

```rust
/// Core-facing handle to the SQLite-backed state runtime.
pub type StateDbHandle = Arc<codex_state::StateRuntime>;

pub(crate) async fn init(config: &Config) -> Option<StateDbHandle> {
    let runtime = codex_state::StateRuntime::init(
        config.sqlite_home.clone(),
        config.model_provider_id.clone(),
    ).await.ok()?;
    
    // 检查并触发回填
    if backfill_state.status != codex_state::BackfillStatus::Complete {
        tokio::spawn(async move {
            metadata::backfill_sessions(runtime_for_backfill.as_ref(), &config).await;
        });
    }
    Some(runtime)
}
```

#### 5.3.2 内存系统调用 (core/src/memories/phase2.rs)

```rust
// 获取 Phase-2 输入选择
let selection = state
    .get_phase2_input_selection(n, max_unused_days)
    .await?;

// 认领全局整合任务
let claim = state
    .try_claim_global_phase2_job(worker_id, lease_seconds)
    .await?;

// 标记成功
state.mark_global_phase2_job_succeeded(
    ownership_token,
    completed_watermark,
    &selected_outputs,
).await?;
```

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 数据库并发

| 风险 | 描述 | 缓解措施 |
|-----|------|---------|
| SQLite 写锁竞争 | 高并发写入可能导致 `database is locked` | WAL 模式 + 5秒 busy_timeout |
| 长时间事务 | 日志修剪在事务内执行可能阻塞 | 预检查 + 批量限制 |

#### 6.1.2 数据一致性

| 风险 | 描述 | 缓解措施 |
|-----|------|---------|
| 文件系统与 DB 不一致 | rollout 文件被删除但 DB 记录残留 | `read_repair_rollout_path()` 修复 |
| 回填中断 | 回填过程崩溃可能导致部分数据 | `last_watermark` 断点续传 |

#### 6.1.3 资源限制

| 风险 | 描述 | 缓解措施 |
|-----|------|---------|
| 日志分区超限 | 单线程日志超过 10MiB | 自动修剪 |
| Stage-1 任务堆积 | 大量线程等待记忆提取 | 全局并发限制 + 重试退避 |

### 6.2 边界情况

#### 6.2.1 日志修剪边界

```rust
// 单条日志超过 10MiB 的情况
let eleven_mebibytes = "d".repeat(11 * 1024 * 1024);
// 结果：该日志插入后立即被修剪，查询返回空
```

**测试覆盖**: `insert_logs_prunes_single_thread_row_when_it_exceeds_size_limit`

#### 6.2.2 任务认领边界

```rust
// 并发认领同一任务
let (claim_a, claim_b) = tokio::join!(
    runtime.try_claim_stage1_job(thread_id, owner_a, ...),
    runtime.try_claim_stage1_job(thread_id, owner_b, ...),
);
// 结果：只有一个成功，另一个返回 SkippedRunning
```

**测试覆盖**: `stage1_concurrent_claim_for_same_thread_is_conflict_safe`

#### 6.2.3 数据库版本升级

```rust
// 旧版本数据库文件自动清理
remove_legacy_db_files(&codex_home, current_name, base_name, "state").await;
// 清理模式：state_*.sqlite, state.sqlite, 及相关 wal/shm/journal 文件
```

### 6.3 改进建议

#### 6.3.1 性能优化

| 建议 | 优先级 | 说明 |
|-----|-------|------|
| 日志表分区 | 中 | 按时间分区，加速历史数据清理 |
| Stage-1 批量认领 | 高 | 当前逐条认领，可优化为批量 |
| 索引优化 | 中 | 根据查询模式评估新增索引 |

#### 6.3.2 可观测性

| 建议 | 优先级 | 说明 |
|-----|-------|------|
| 慢查询日志 | 中 | 记录执行时间超过阈值的 SQL |
| 任务队列监控 | 高 | 暴露 pending/running 任务指标 |
| DB 大小监控 | 低 | 跟踪数据库文件增长 |

#### 6.3.3 可靠性增强

| 建议 | 优先级 | 说明 |
|-----|-------|------|
| 回填进度持久化 | 中 | 更细粒度的 checkpoint |
| 任务租约续期 | 高 | 长任务需要心跳续期 |
| 数据校验 | 低 | 定期校验 DB 与文件系统一致性 |

### 6.4 测试覆盖

当前测试覆盖情况（基于代码统计）：

| 模块 | 测试行数 | 主要测试场景 |
|-----|---------|-------------|
| `logs.rs` | ~1500 行 | 插入、查询、修剪、反馈日志 |
| `memories.rs` | ~800 行 | 任务认领、成功/失败标记、并发 |
| `threads.rs` | ~400 行 | CRUD、apply_rollout_items |
| `backfill.rs` | ~200 行 | 状态流转、文件清理 |
| `agent_jobs.rs` | ~150 行 | 任务创建、状态流转 |

**测试工具**: `test_support.rs` 提供 `unique_temp_dir()` 和 `test_thread_metadata()`

---

## 附录

### A. 术语表

| 术语 | 说明 |
|-----|------|
| Rollout | Codex 对话的 JSONL 记录文件 |
| Stage-1 | 单线程记忆提取阶段 |
| Stage-2 | 全局记忆整合阶段 |
| Backfill | 历史数据回填 |
| Thread | 对话线程 |
| Agent Job | 批量 Agent 任务 |

### B. 参考资料

- `codex-rs/state/src/lib.rs` - 模块文档
- `codex-rs/core/src/state_db.rs` - Core 层封装
- `codex-rs/state/migrations/` - 数据库迁移
- `AGENTS.md` - 项目级开发规范
