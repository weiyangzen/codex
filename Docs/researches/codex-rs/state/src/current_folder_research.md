# codex-rs/state/src 深度研究文档

## 1. 场景与职责

### 1.1 模块定位

`codex-state` crate 是 Codex 项目的 **SQLite-backed 状态存储层**，负责持久化以下核心数据：

1. **Thread 元数据** - 对话会话的索引和属性
2. **Agent Jobs** - 批量任务执行的状态管理
3. **Memory 系统** - 两阶段记忆提取与整合（Stage-1 / Phase-2）
4. **日志存储** - 独立的日志数据库，支持 tracing 集成
5. **Backfill 状态** - rollout 元数据回填的协调状态

### 1.2 架构设计原则

- **小而专注**: 仅负责元数据提取和镜像，不处理 rollout 扫描逻辑（由 `codex-core` 处理）
- **双数据库设计**: 
  - `state_{VERSION}.sqlite` - 核心状态数据
  - `logs_{VERSION}.sqlite` - 独立日志存储，减少锁竞争
- **WAL 模式**: 使用 SQLite Write-Ahead Logging 提高并发性能
- **版本化数据库文件**: 通过版本号管理 schema 迁移，自动清理旧版本文件

### 1.3 使用场景

| 场景 | 描述 |
|------|------|
| Thread 列表查询 | 快速分页查询对话列表，无需扫描 rollout 文件 |
| Agent 批量任务 | 创建、执行、监控批量处理任务（如批量代码审查） |
| 记忆系统 | 自动提取对话记忆并整合到全局知识库 |
| 日志检索 | 支持按 thread、时间、级别等多维度查询 |
| 启动回填 | 首次启动时扫描历史 rollout 建立索引 |

---

## 2. 功能点目的

### 2.1 Thread 元数据管理 (`runtime/threads.rs`)

**目的**: 维护对话会话的完整元数据索引，支持快速查询而无需遍历 rollout 文件。

**核心功能**:
- `upsert_thread()` - 插入或更新 thread 元数据
- `list_threads()` - 分页查询 thread 列表，支持多种过滤条件
- `get_thread()` - 获取单个 thread 的完整元数据
- `mark_archived/unarchived()` - 归档/取消归档状态管理
- `apply_rollout_items()` - 从 rollout 事件增量更新元数据

**关键设计**:
- 使用 `ThreadMetadataBuilder` 模式构建元数据
- 支持 `SortKey` 排序（CreatedAt/UpdatedAt）
- 分页使用 `Anchor` 游标（timestamp + UUID）
- 自动检测并清理 stale rollout 路径

### 2.2 Agent Jobs 管理 (`runtime/agent_jobs.rs`)

**目的**: 支持批量任务执行，如批量代码审查、批量重构等。

**核心功能**:
- `create_agent_job()` - 创建批量任务（含任务项）
- `mark_agent_job_*` - 任务状态流转（Running/Completed/Failed/Cancelled）
- `mark_agent_job_item_*` - 任务项状态管理
- `report_agent_job_item_result()` - 报告子任务执行结果
- `get_agent_job_progress()` - 获取任务进度统计

**状态机**:
```
Pending -> Running -> Completed
   |          |
   v          v
Cancelled   Failed
```

### 2.3 Memory 系统 (`runtime/memories.rs`)

**目的**: 实现两阶段记忆提取管道，自动从对话中提取有价值的信息。

**Stage-1（单 Thread 提取）**:
- `claim_stage1_jobs_for_startup()` - 启动时扫描并认领待处理任务
- `try_claim_stage1_job()` - 尝试认领单个 thread 的提取任务
- `mark_stage1_job_succeeded()` - 标记提取成功并存储结果
- `mark_stage1_job_failed()` - 失败处理与重试退避

**Phase-2（全局整合）**:
- `try_claim_global_phase2_job()` - 尝试认领全局整合任务
- `get_phase2_input_selection()` - 获取当前输入选择集
- `mark_global_phase2_job_succeeded()` - 标记整合完成

**数据流**:
```
rollout files -> Stage-1 extraction -> stage1_outputs table
                                           |
                                           v
Phase-2 consolidation <- selected outputs <-'
```

### 2.4 日志系统 (`log_db.rs`, `runtime/logs.rs`)

**目的**: 提供高性能、可查询的日志存储，支持 tracing 集成。

**核心设计**:
- **独立数据库**: `logs_{VERSION}.sqlite`，避免与状态数据竞争
- **分区存储策略**: 
  - Thread 日志: 按 `thread_id` 分区，10MiB/1000行上限
  - Threadless 日志: 按 `process_uuid` 分区
- **自动清理**: 10天保留期 + 分区大小限制
- **Tracing Layer**: `LogDbLayer` 实现 `tracing_subscriber::Layer`

**关键配置**:
```rust
const LOG_PARTITION_SIZE_LIMIT_BYTES: i64 = 10 * 1024 * 1024; // 10 MiB
const LOG_PARTITION_ROW_LIMIT: i64 = 1_000;
const LOG_RETENTION_DAYS: i64 = 10;
```

### 2.5 Backfill 系统 (`runtime/backfill.rs`)

**目的**: 协调 rollout 元数据的历史回填，确保 SQLite 索引完整。

**核心功能**:
- `try_claim_backfill()` - 尝试获取回填工作权（基于租约）
- `checkpoint_backfill()` - 记录进度水印
- `mark_backfill_complete()` - 标记回填完成

**租约机制**:
- 使用 `lease_seconds` 防止多个进程同时回填
- 支持 stale lease 检测和接管

---

## 3. 具体技术实现

### 3.1 数据库 Schema

#### State DB (`migrations/`)

**threads 表** (0001_threads.sql):
```sql
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
    memory_mode TEXT DEFAULT 'enabled',
    agent_nickname TEXT,
    agent_role TEXT,
    model TEXT,
    reasoning_effort TEXT,
    cli_version TEXT NOT NULL DEFAULT '',
    first_user_message TEXT NOT NULL DEFAULT ''
);
```

**stage1_outputs 表** (0006_memories.sql):
```sql
CREATE TABLE stage1_outputs (
    thread_id TEXT PRIMARY KEY,
    source_updated_at INTEGER NOT NULL,
    raw_memory TEXT NOT NULL,
    rollout_summary TEXT NOT NULL,
    rollout_slug TEXT,
    generated_at INTEGER NOT NULL,
    usage_count INTEGER,
    last_usage INTEGER,
    selected_for_phase2 INTEGER NOT NULL DEFAULT 0,
    selected_for_phase2_source_updated_at INTEGER,
    FOREIGN KEY(thread_id) REFERENCES threads(id) ON DELETE CASCADE
);
```

**jobs 表** (0006_memories.sql):
```sql
CREATE TABLE jobs (
    kind TEXT NOT NULL,
    job_key TEXT NOT NULL,
    status TEXT NOT NULL,  -- 'pending', 'running', 'done', 'error'
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
```

**agent_jobs 表** (0014_agent_jobs.sql):
```sql
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
```

**backfill_state 表** (0008_backfill_state.sql):
```sql
CREATE TABLE backfill_state (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    status TEXT NOT NULL,
    last_watermark TEXT,
    last_success_at INTEGER,
    updated_at INTEGER NOT NULL
);
```

#### Logs DB (`logs_migrations/`)

**logs 表**:
```sql
CREATE TABLE logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts INTEGER NOT NULL,
    ts_nanos INTEGER NOT NULL,
    level TEXT NOT NULL,
    target TEXT NOT NULL,
    feedback_log_body TEXT,  -- 渲染后的日志内容
    module_path TEXT,
    file TEXT,
    line INTEGER,
    thread_id TEXT,
    process_uuid TEXT,
    estimated_bytes INTEGER NOT NULL DEFAULT 0
);
```

### 3.2 关键数据结构

#### ThreadMetadata (`model/thread_metadata.rs`)

```rust
pub struct ThreadMetadata {
    pub id: ThreadId,
    pub rollout_path: PathBuf,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub source: String,           // "cli", "vscode", etc.
    pub agent_nickname: Option<String>,
    pub agent_role: Option<String>,
    pub model_provider: String,
    pub model: Option<String>,
    pub reasoning_effort: Option<ReasoningEffort>,
    pub cwd: PathBuf,
    pub cli_version: String,
    pub title: String,
    pub sandbox_policy: String,
    pub approval_mode: String,
    pub tokens_used: i64,
    pub first_user_message: Option<String>,
    pub archived_at: Option<DateTime<Utc>>,
    pub git_sha: Option<String>,
    pub git_branch: Option<String>,
    pub git_origin_url: Option<String>,
}
```

#### Stage1Output (`model/memories.rs`)

```rust
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
```

#### AgentJob (`model/agent_job.rs`)

```rust
pub struct AgentJob {
    pub id: String,
    pub name: String,
    pub status: AgentJobStatus,  // Pending, Running, Completed, Failed, Cancelled
    pub instruction: String,
    pub auto_export: bool,
    pub max_runtime_seconds: Option<u64>,
    pub output_schema_json: Option<Value>,
    pub input_headers: Vec<String>,
    pub input_csv_path: String,
    pub output_csv_path: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub started_at: Option<DateTime<Utc>>,
    pub completed_at: Option<DateTime<Utc>>,
    pub last_error: Option<String>,
}
```

### 3.3 关键流程

#### Rollout 元数据提取流程 (`extract.rs`)

```rust
pub fn apply_rollout_item(
    metadata: &mut ThreadMetadata,
    item: &RolloutItem,
    default_provider: &str,
) {
    match item {
        RolloutItem::SessionMeta(meta_line) => apply_session_meta(metadata, meta_line),
        RolloutItem::TurnContext(turn_ctx) => apply_turn_context(metadata, turn_ctx),
        RolloutItem::EventMsg(event) => apply_event_msg(metadata, event),
        RolloutItem::ResponseItem(item) => apply_response_item(metadata, item),
        RolloutItem::Compacted(_) => {}
    }
}
```

**字段映射规则**:
| RolloutItem 类型 | 提取字段 |
|-----------------|----------|
| SessionMeta | id, source, agent_nickname, agent_role, model_provider, cli_version, cwd, git_* |
| TurnContext | model, reasoning_effort, sandbox_policy, approval_mode, cwd (fallback) |
| EventMsg::TokenCount | tokens_used |
| EventMsg::UserMessage | first_user_message, title |

#### Stage-1 Job 认领流程 (`runtime/memories.rs`)

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

**认领条件检查**（按顺序）:
1. `stage1_outputs.source_updated_at >= source_updated_at` → `SkippedUpToDate`
2. `jobs.last_success_watermark >= source_updated_at` → `SkippedUpToDate`
3. 全局运行任务数 >= `max_running_jobs` → `SkippedRunning`
4. 现有任务处于 running 状态且 lease 未过期 → `SkippedRunning`
5. `retry_at` 在未来时间 → `SkippedRetryBackoff`
6. `retry_remaining <= 0` → `SkippedRetryExhausted`

**成功认领**: 插入/更新 jobs 表，设置 `status='running'`, `ownership_token`, `lease_until`

#### 日志分区清理流程 (`runtime/logs.rs`)

```rust
async fn prune_logs_after_insert(
    &self,
    entries: &[LogEntry],
    tx: &mut SqliteConnection,
) -> anyhow::Result<()>
```

**清理策略**:
1. 识别受影响的 thread_ids 和 process_uuids
2. 预检查：仅对超出限制的分区执行清理
3. 使用窗口函数计算累积字节数
4. 删除超出限制的旧记录（按时间倒序）

**SQL 窗口函数示例**:
```sql
DELETE FROM logs
WHERE id IN (
    SELECT id
    FROM (
        SELECT id,
            SUM(estimated_bytes) OVER (
                PARTITION BY thread_id
                ORDER BY ts DESC, ts_nanos DESC, id DESC
            ) AS cumulative_bytes,
            ROW_NUMBER() OVER (...) AS row_number
        FROM logs
        WHERE thread_id IN (...)
    )
    WHERE cumulative_bytes > ? OR row_number > ?
)
```

---

## 4. 关键代码路径与文件引用

### 4.1 模块结构

```
codex-rs/state/src/
├── lib.rs                    # 公共 API 导出
├── runtime.rs                # StateRuntime 主结构
├── runtime/
│   ├── threads.rs            # Thread 元数据操作
│   ├── agent_jobs.rs         # Agent Jobs 管理
│   ├── memories.rs           # Memory 系统（Stage-1/Phase-2）
│   ├── logs.rs               # 日志查询与清理
│   ├── backfill.rs           # Backfill 状态管理
│   └── test_support.rs       # 测试辅助函数
├── model/
│   ├── mod.rs                # 模型模块导出
│   ├── thread_metadata.rs    # ThreadMetadata 定义
│   ├── agent_job.rs          # AgentJob 定义
│   ├── memories.rs           # Stage1Output 等定义
│   ├── backfill_state.rs     # BackfillState 定义
│   └── log.rs                # LogEntry/LogQuery 定义
├── extract.rs                # Rollout 元数据提取逻辑
├── log_db.rs                 # Tracing Layer 实现
├── migrations.rs             # SQLx 迁移配置
├── paths.rs                  # 文件路径工具
└── bin/
    └── logs_client.rs        # CLI 日志查看工具
```

### 4.2 关键代码路径

#### 初始化路径

```rust
// lib.rs
pub use runtime::StateRuntime;

// runtime.rs
impl StateRuntime {
    pub async fn init(codex_home: PathBuf, default_provider: String) -> anyhow::Result<Arc<Self>> {
        // 1. 创建 codex_home 目录
        // 2. 清理旧版本数据库文件
        // 3. 打开 state 数据库并执行迁移
        // 4. 打开 logs 数据库并执行迁移
        // 5. 返回 Arc<StateRuntime>
    }
}
```

#### Rollout 应用路径

```rust
// runtime/threads.rs
pub async fn apply_rollout_items(
    &self,
    builder: &ThreadMetadataBuilder,
    items: &[RolloutItem],
    new_thread_memory_mode: Option<&str>,
    updated_at_override: Option<DateTime<Utc>>,
) -> anyhow::Result<()>

// extract.rs - 核心提取逻辑
pub fn apply_rollout_item(
    metadata: &mut ThreadMetadata,
    item: &RolloutItem,
    default_provider: &str,
)

// 调用链:
// core/src/state_db.rs::apply_rollout_items() 
//   -> StateRuntime::apply_rollout_items()
//      -> extract::apply_rollout_item() (逐个处理 RolloutItem)
```

#### Memory Job 认领路径

```rust
// runtime/memories.rs
pub async fn claim_stage1_jobs_for_startup(
    &self,
    current_thread_id: ThreadId,
    params: Stage1StartupClaimParams<'_>,
) -> anyhow::Result<Vec<Stage1JobClaim>>

// 内部调用:
//   -> try_claim_stage1_job() (逐个尝试认领)

pub async fn try_claim_stage1_job(
    &self,
    thread_id: ThreadId,
    worker_id: ThreadId,
    source_updated_at: i64,
    lease_seconds: i64,
    max_running_jobs: usize,
) -> anyhow::Result<Stage1JobClaimOutcome>
```

#### 日志写入路径

```rust
// log_db.rs - Tracing Layer
impl<S> Layer<S> for LogDbLayer {
    fn on_event(&self, event: &Event<'_>, ctx: Context<'_, S>) {
        // 1. 提取 event 字段
        // 2. 构建 LogEntry
        // 3. 通过 channel 发送到后台任务
    }
}

// 后台任务
async fn run_inserter(
    state_db: Arc<StateRuntime>,
    receiver: mpsc::Receiver<LogDbCommand>,
) {
    // 批量收集日志
    // 定期 flush 或达到批次大小
    // 调用 StateRuntime::insert_logs()
}

// runtime/logs.rs
pub async fn insert_logs(&self, entries: &[LogEntry]) -> anyhow::Result<()> {
    // 1. 批量插入 logs 表
    // 2. 调用 prune_logs_after_insert() 清理超限分区
}
```

### 4.3 测试路径

| 测试文件 | 覆盖功能 |
|---------|---------|
| `runtime/threads.rs` (tests) | Thread CRUD、apply_rollout_items |
| `runtime/agent_jobs.rs` (tests) | Agent Job 生命周期、状态流转 |
| `runtime/memories.rs` (tests) | Stage-1 认领、Phase-2 整合、并发控制 |
| `runtime/backfill.rs` (tests) | Backfill 状态机、租约机制 |
| `runtime/logs.rs` (tests) | 日志插入、分区清理、查询 |
| `extract.rs` (tests) | Rollout 元数据提取规则 |
| `log_db.rs` (tests) | Tracing Layer 集成 |

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| Crate | 用途 |
|-------|------|
| `codex-protocol` | `ThreadId`, `RolloutItem`, `SessionMeta` 等协议类型 |
| `codex-core` | 调用 StateRuntime 进行状态管理（通过 `state_db.rs` 封装） |
| `codex-app-server` | 集成日志 Layer，查询 thread 状态 |

### 5.2 外部依赖

| Crate | 用途 |
|-------|------|
| `sqlx` | SQLite 异步访问、迁移管理 |
| `tokio` | 异步运行时、文件操作、channel |
| `chrono` | 时间戳处理 |
| `serde`/`serde_json` | 序列化/反序列化 |
| `tracing`/`tracing-subscriber` | 日志集成 |
| `uuid` | Token 和 ID 生成 |
| `anyhow` | 错误处理 |

### 5.3 数据库配置

```rust
// runtime.rs
async fn open_sqlite(path: &Path, migrator: &'static Migrator) -> anyhow::Result<SqlitePool> {
    let options = SqliteConnectOptions::new()
        .filename(path)
        .create_if_missing(true)
        .journal_mode(SqliteJournalMode::Wal)        // WAL 模式
        .synchronous(SqliteSynchronous::Normal)      // 正常同步模式
        .busy_timeout(Duration::from_secs(5))        // 5秒忙等待超时
        .log_statements(LevelFilter::Off);
    
    let pool = SqlitePoolOptions::new()
        .max_connections(5)
        .connect_with(options)
        .await?;
    
    migrator.run(&pool).await?;  // 执行迁移
    Ok(pool)
}
```

### 5.4 环境变量

| 变量 | 用途 |
|------|------|
| `CODEX_SQLITE_HOME` | 覆盖 SQLite 数据库主目录 |
| `CODEX_HOME` | 默认 Codex 主目录（~/.codex） |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 1. 并发控制
- **风险**: Stage-1 job 认领使用 `BEGIN IMMEDIATE` 事务，高并发时可能遇到 `database is locked`
- **缓解**: 调用方（如 `core/src/memories/`）实现了重试逻辑
- **代码**: `runtime/memories.rs:551` - `tx.begin_with("BEGIN IMMEDIATE").await`

#### 2. 分区清理性能
- **风险**: 日志分区清理使用窗口函数，大数据量时可能影响插入性能
- **缓解**: 预检查机制，仅对超限分区执行清理
- **代码**: `runtime/logs.rs:72-92` - over_limit_threads_query 预检查

#### 3. Stale Rollout 路径
- **风险**: 数据库中存储的 rollout 路径可能因文件移动而失效
- **缓解**: `list_threads_db()` 会验证路径存在性，自动删除 stale 记录
- **代码**: `core/src/state_db.rs:246-259`

#### 4. 租约过期
- **风险**: 进程崩溃可能导致 job lease 未释放，阻塞后续认领
- **缓解**: lease 基于时间戳，stale lease（超过 lease_seconds）可被其他进程接管
- **代码**: `runtime/memories.rs:631-636`

### 6.2 边界情况

| 场景 | 行为 |
|------|------|
| 单条日志 > 10MiB | 插入后立即被清理（prune 保留最新记录直到超限） |
| 并发 claim 同一 thread | 只有一个成功，其他返回 `SkippedRunning` |
| backfill 中断 | 下次启动时从 `last_watermark` 继续 |
| agent job item 多次失败 | 达到 retry 上限后标记为 Failed，不再自动重试 |
| memory_mode = 'disabled' | Stage-1 job 认领时自动跳过 |
| memory_mode = 'polluted' | 触发 Phase-2 forgetting，从知识库中移除 |

### 6.3 改进建议

#### 1. 监控与可观测性
- **建议**: 添加 Prometheus 风格的指标导出
- **当前**: 仅定义了常量指标名（`DB_ERROR_METRIC`, `DB_METRIC_BACKFILL`），未实际使用
- **代码位置**: `lib.rs:62-66`

#### 2. 配置化
- **建议**: 将硬编码的阈值（10MiB、1000行、10天）改为可配置
- **当前**: 
  ```rust
  const LOG_PARTITION_SIZE_LIMIT_BYTES: i64 = 10 * 1024 * 1024;
  const LOG_PARTITION_ROW_LIMIT: i64 = 1_000;
  const LOG_RETENTION_DAYS: i64 = 10;
  ```

#### 3. 批量优化
- **建议**: Agent job item 的批量创建可使用 `UNION ALL` 或 `INSERT ... SELECT` 优化
- **当前**: 逐个插入，每次 round-trip
- **代码**: `runtime/agent_jobs.rs:59-91`

#### 4. 索引优化
- **建议**: 为 `threads.memory_mode` 添加索引（Stage-1 扫描频繁过滤）
- **当前**: 依赖复合索引，可能不够高效

#### 5. 错误处理
- **建议**: 区分可重试错误（如 busy）和永久错误（如 constraint violation）
- **当前**: 统一使用 `anyhow::Result`，调用方难以区分

#### 6. 测试覆盖
- **建议**: 添加压力测试（并发 claim、大量日志插入）
- **当前**: 单元测试覆盖良好，但缺乏集成压力测试

### 6.4 技术债务

| 位置 | 描述 | 建议 |
|------|------|------|
| `extract.rs:82-83` | `output_schema_json` 字段 TODO | 实现 JSON Schema 验证 |
| `runtime/threads.rs:276` | `memory_mode` 硬编码默认值 | 提取到配置常量 |
| `runtime/memories.rs:24` | `DEFAULT_RETRY_REMAINING = 3` 硬编码 | 配置化 |
| `log_db.rs:47-50` | 日志队列参数硬编码 | 配置化或自适应 |

---

## 7. 总结

`codex-state` crate 是 Codex 项目的数据持久化基石，通过 SQLite 提供了轻量级但功能完整的状态管理能力。其设计亮点包括：

1. **双数据库架构** - 分离状态与日志，减少锁竞争
2. **版本化 Schema** - 通过文件版本管理迁移，自动清理旧版本
3. **租约机制** - 支持分布式场景下的任务协调
4. **分区清理** - 智能日志保留策略，防止无限增长
5. **Tracing 集成** - 无缝接入 Rust 生态的日志系统

主要使用方包括 `codex-core`（核心状态管理）、`codex-app-server`（日志与 thread 查询）和 CLI 工具（`logs_client`）。
