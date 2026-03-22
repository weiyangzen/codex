# codex-rs/state/migrations 研究文档

## 1. 场景与职责

### 1.1 目录定位
`codex-rs/state/migrations` 是 Codex CLI 项目 Rust 代码库中的 **SQLite 数据库迁移脚本目录**，负责管理 `codex-state` crate 使用的核心状态数据库（state DB）的 Schema 演进。

### 1.2 核心职责
- **Schema 版本管理**：通过递增编号的 SQL 文件（0001-0020）管理数据库结构的演进
- **数据持久化**：存储线程元数据（threads）、日志（logs）、记忆（memories）、Agent 任务（agent_jobs）等核心数据
- **向后兼容**：通过 sqlx 的迁移框架确保旧数据平滑升级
- **多数据库支持**：与 `logs_migrations` 目录配合，支持状态库与日志库的分离存储

### 1.3 业务场景
| 场景 | 说明 |
|------|------|
| 线程管理 | 存储对话线程的元数据（标题、模型、沙箱策略等） |
| 日志存储 | 支持 tracing 日志的持久化与查询 |
| 记忆系统 | Stage1/Stage2 记忆提取与合并的状态管理 |
| Agent 批处理 | 批量 Agent 任务的创建、执行与结果追踪 |
| 数据回填 | 历史 rollout 文件的元数据扫描与导入 |

---

## 2. 功能点目的

### 2.1 迁移文件演进历程

#### 基础架构阶段（0001-0003）
- **0001_threads.sql**：创建核心 `threads` 表，存储对话线程元数据
- **0002_logs.sql**：创建 `logs` 表，支持 tracing 日志存储
- **0003_logs_thread_id.sql**：为日志表添加 `thread_id` 关联，支持按线程查询日志

#### 功能扩展阶段（0004-0013）
- **0004_thread_dynamic_tools.sql**：支持线程级别的动态工具（Dynamic Tools）存储
- **0005_threads_cli_version.sql**：记录创建线程的 CLI 版本
- **0006_memories.sql**：引入记忆系统核心表（`stage1_outputs` 和 `jobs`）
- **0007_threads_first_user_message.sql**：存储用户第一条消息，用于线程列表展示
- **0008_backfill_state.sql**：添加回填状态表，管理历史数据迁移进度
- **0009_stage1_outputs_rollout_slug.sql**：为 Stage1 输出添加 rollout slug 字段
- **0010_logs_process_id.sql**：添加进程 UUID 关联，支持多进程日志隔离
- **0011_logs_partition_prune_indexes.sql**：优化日志表索引，支持分区清理
- **0012_logs_estimated_bytes.sql**：添加日志大小估算，支持存储配额管理
- **0013_threads_agent_nickname.sql**：支持 Agent 昵称和角色存储

#### 高级功能阶段（0014-0020）
- **0014_agent_jobs.sql**：添加 Agent 批处理任务表（`agent_jobs` 和 `agent_job_items`）
- **0015_agent_jobs_max_runtime_seconds.sql**：支持任务最大运行时间限制
- **0016_memory_usage.sql**：记录 Stage1 输出的使用次数和最后使用时间
- **0017_phase2_selection_flag.sql**：添加 Phase2 选择标记，支持记忆合并流程
- **0018_phase2_selection_snapshot.sql**：记录 Phase2 选择的快照时间戳
- **0019_thread_dynamic_tools_defer_loading.sql**：支持动态工具延迟加载标记
- **0020_threads_model_reasoning_effort.sql**：存储模型和推理努力度（reasoning effort）

### 2.2 配套日志迁移（logs_migrations）

| 文件 | 目的 |
|------|------|
| 0001_logs.sql | 创建独立的日志数据库 Schema |
| 0002_logs_feedback_log_body.sql | 将 `message` 列重构为 `feedback_log_body`，支持更丰富的日志内容 |

---

## 3. 具体技术实现

### 3.1 迁移框架集成

```rust
// codex-rs/state/src/migrations.rs
use sqlx::migrate::Migrator;

pub(crate) static STATE_MIGRATOR: Migrator = sqlx::migrate!("./migrations");
pub(crate) static LOGS_MIGRATOR: Migrator = sqlx::migrate!("./logs_migrations");
```

**关键技术点**：
- 使用 `sqlx::migrate!` 宏在编译时嵌入迁移脚本
- 支持 Bazel 构建：通过 `compile_data` 将迁移文件作为编译数据包含

```starlark
# codex-rs/state/BUILD.bazel
codex_rust_crate(
    name = "state",
    crate_name = "codex_state",
    compile_data = glob(["logs_migrations/**", "migrations/**"]),
)
```

### 3.2 数据库初始化流程

```rust
// codex-rs/state/src/runtime.rs
pub async fn init(codex_home: PathBuf, default_provider: String) -> anyhow::Result<Arc<Self>> {
    // 1. 清理旧版本数据库文件
    remove_legacy_db_files(&codex_home, current_state_name.as_str(), STATE_DB_FILENAME, "state").await;
    remove_legacy_db_files(&codex_home, current_logs_name.as_str(), LOGS_DB_FILENAME, "logs").await;
    
    // 2. 打开并迁移状态数据库
    let pool = match open_sqlite(&state_path, &STATE_MIGRATOR).await {
        Ok(db) => Arc::new(db),
        Err(err) => { warn!(...); return Err(err); }
    };
    
    // 3. 打开并迁移日志数据库
    let logs_pool = match open_sqlite(&logs_path, &LOGS_MIGRATOR).await {
        Ok(db) => Arc::new(db),
        Err(err) => { warn!(...); return Err(err); }
    };
    
    Ok(Arc::new(Self { pool, logs_pool, codex_home, default_provider }))
}

async fn open_sqlite(path: &Path, migrator: &'static Migrator) -> anyhow::Result<SqlitePool> {
    let options = SqliteConnectOptions::new()
        .filename(path)
        .create_if_missing(true)
        .journal_mode(SqliteJournalMode::Wal)  // WAL 模式提升并发性能
        .synchronous(SqliteSynchronous::Normal)
        .busy_timeout(Duration::from_secs(5))
        .log_statements(LevelFilter::Off);
    
    let pool = SqlitePoolOptions::new()
        .max_connections(5)
        .connect_with(options)
        .await?;
    
    migrator.run(&pool).await?;  // 执行迁移
    Ok(pool)
}
```

### 3.3 版本控制策略

```rust
// codex-rs/state/src/lib.rs
pub const LOGS_DB_FILENAME: &str = "logs";
pub const LOGS_DB_VERSION: u32 = 1;
pub const STATE_DB_FILENAME: &str = "state";
pub const STATE_DB_VERSION: u32 = 5;

// 生成带版本号的数据库文件名
fn db_filename(base_name: &str, version: u32) -> String {
    format!("{base_name}_{version}.sqlite")
}

pub fn state_db_filename() -> String {
    db_filename(STATE_DB_FILENAME, STATE_DB_VERSION)
}
```

**版本升级机制**：
- 数据库文件名包含版本号（如 `state_5.sqlite`）
- 启动时自动清理旧版本文件（包括 `-wal`, `-shm`, `-journal` 后缀文件）
- 保留非版本化文件（如备份文件）

### 3.4 核心表结构详解

#### threads 表（0001_threads.sql）
```sql
CREATE TABLE threads (
    id TEXT PRIMARY KEY,                    -- 线程 UUID
    rollout_path TEXT NOT NULL,             -- rollout 文件路径
    created_at INTEGER NOT NULL,            -- 创建时间戳
    updated_at INTEGER NOT NULL,            -- 更新时间戳
    source TEXT NOT NULL,                   -- 来源（cli/agent-control）
    model_provider TEXT NOT NULL,           -- 模型提供商
    cwd TEXT NOT NULL,                      -- 工作目录
    title TEXT NOT NULL,                    -- 线程标题
    sandbox_policy TEXT NOT NULL,           -- 沙箱策略
    approval_mode TEXT NOT NULL,            -- 审批模式
    tokens_used INTEGER NOT NULL DEFAULT 0, -- Token 使用量
    has_user_event INTEGER NOT NULL DEFAULT 0,
    archived INTEGER NOT NULL DEFAULT 0,    -- 是否归档
    archived_at INTEGER,                    -- 归档时间
    git_sha TEXT,                           -- Git commit
    git_branch TEXT,                        -- Git 分支
    git_origin_url TEXT,                    -- Git 仓库 URL
    -- 后续迁移添加的字段：
    -- cli_version (0005)
    -- first_user_message (0007)
    -- agent_nickname, agent_role (0013)
    -- memory_mode (0018)
    -- model, reasoning_effort (0020)
);
```

#### stage1_outputs 表（0006_memories.sql + 扩展）
```sql
CREATE TABLE stage1_outputs (
    thread_id TEXT PRIMARY KEY,
    source_updated_at INTEGER NOT NULL,     -- 源数据更新时间
    raw_memory TEXT NOT NULL,               -- 原始记忆内容
    rollout_summary TEXT NOT NULL,          -- Rollout 摘要
    generated_at INTEGER NOT NULL,          -- 生成时间
    -- 后续迁移添加：
    -- rollout_slug (0009)
    -- usage_count, last_usage (0016)
    -- selected_for_phase2 (0017)
    -- selected_for_phase2_source_updated_at (0018)
);
```

#### jobs 表（0006_memories.sql）
```sql
CREATE TABLE jobs (
    kind TEXT NOT NULL,                     -- 任务类型（memory_stage1/memory_consolidate_global）
    job_key TEXT NOT NULL,                  -- 任务键（通常是 thread_id）
    status TEXT NOT NULL,                   -- 状态（pending/running/done/error）
    worker_id TEXT,                         -- 执行者 ID
    ownership_token TEXT,                   -- 所有权令牌（分布式锁）
    started_at INTEGER,                     -- 开始时间
    finished_at INTEGER,                    -- 完成时间
    lease_until INTEGER,                    -- 租约过期时间
    retry_at INTEGER,                       -- 下次重试时间
    retry_remaining INTEGER NOT NULL,       -- 剩余重试次数
    last_error TEXT,                        -- 最后错误信息
    input_watermark INTEGER,                -- 输入水位
    last_success_watermark INTEGER,         -- 最后成功水位
    PRIMARY KEY (kind, job_key)
);
```

#### agent_jobs 表（0014_agent_jobs.sql）
```sql
CREATE TABLE agent_jobs (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    status TEXT NOT NULL,                   -- pending/running/completed/failed/cancelled
    instruction TEXT NOT NULL,              -- Agent 指令
    output_schema_json TEXT,                -- 输出 JSON Schema
    input_headers_json TEXT NOT NULL,       -- 输入 CSV 表头
    input_csv_path TEXT NOT NULL,           -- 输入文件路径
    output_csv_path TEXT NOT NULL,          -- 输出文件路径
    auto_export INTEGER NOT NULL DEFAULT 1, -- 是否自动导出
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    started_at INTEGER,
    completed_at INTEGER,
    last_error TEXT,
    -- 0015 添加：max_runtime_seconds
);

CREATE TABLE agent_job_items (
    job_id TEXT NOT NULL,
    item_id TEXT NOT NULL,
    row_index INTEGER NOT NULL,             -- CSV 行号
    source_id TEXT,                         -- 源标识
    row_json TEXT NOT NULL,                 -- 行数据 JSON
    status TEXT NOT NULL,
    assigned_thread_id TEXT,                -- 分配的线程 ID
    attempt_count INTEGER NOT NULL DEFAULT 0,
    result_json TEXT,                       -- 执行结果
    last_error TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    completed_at INTEGER,
    reported_at INTEGER,                    -- 结果报告时间
    PRIMARY KEY (job_id, item_id),
    FOREIGN KEY(job_id) REFERENCES agent_jobs(id) ON DELETE CASCADE
);
```

---

## 4. 关键代码路径与文件引用

### 4.1 迁移相关文件

| 文件 | 职责 |
|------|------|
| `migrations.rs` | 定义 STATE_MIGRATOR 和 LOGS_MIGRATOR |
| `0001-0020.sql` | 状态数据库迁移脚本 |
| `logs_migrations/0001-0002.sql` | 日志数据库迁移脚本 |
| `BUILD.bazel` | Bazel 构建配置，包含迁移文件 |

### 4.2 核心调用代码

```
StateRuntime::init()
  └── runtime.rs:83-124
      ├── remove_legacy_db_files()  // 清理旧版本数据库
      ├── open_sqlite()             // 打开数据库
      │   └── migrator.run(&pool)   // 执行迁移
      └── StateRuntime { pool, logs_pool, ... }
```

### 4.3 数据访问层

| 模块 | 文件 | 职责 |
|------|------|------|
| runtime/threads.rs | 线程元数据 CRUD、动态工具管理 |
| runtime/logs.rs | 日志插入、查询、清理、反馈日志获取 |
| runtime/memories.rs | Stage1/Stage2 记忆任务管理 |
| runtime/agent_jobs.rs | Agent 批处理任务管理 |
| runtime/backfill.rs | 历史数据回填状态管理 |

### 4.4 模型定义

| 模型 | 文件 | 对应表 |
|------|------|--------|
| ThreadMetadata | model/thread_metadata.rs | threads |
| Stage1Output | model/memories.rs | stage1_outputs |
| AgentJob/AgentJobItem | model/agent_job.rs | agent_jobs/agent_job_items |
| LogEntry/LogRow | model/log.rs | logs |
| BackfillState | model/backfill_state.rs | backfill_state |

---

## 5. 依赖与外部交互

### 5.1 外部依赖

```toml
# codex-rs/state/Cargo.toml
[dependencies]
sqlx = { workspace = true }           # 核心 ORM 和迁移框架
chrono = { workspace = true }         # 时间处理
serde = { workspace = true }          # 序列化
codex-protocol = { workspace = true } # 协议类型（ThreadId 等）
tokio = { workspace = true }          # 异步运行时
tracing = { workspace = true }        # 日志框架集成
```

### 5.2 上下游调用关系

```
上游调用方：
├── codex-core          # 核心逻辑，通过 StateRuntime 访问数据
├── codex-tui           # TUI 界面，查询线程列表和日志
├── codex-cli           # CLI 入口，初始化 StateRuntime
└── logs_client.rs      # 独立日志查询工具

下游依赖：
├── sqlx (migrate::Migrator)  # 迁移执行
├── SQLite (WAL 模式)         # 底层存储
└── tokio::fs                 # 文件操作
```

### 5.3 配置与环境变量

```rust
// lib.rs
pub const SQLITE_HOME_ENV: &str = "CODEX_SQLITE_HOME";  // 数据库目录覆盖

// runtime.rs - 数据库版本常量
pub const STATE_DB_VERSION: u32 = 5;
pub const LOGS_DB_VERSION: u32 = 1;
```

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### 迁移脚本风险
| 风险 | 说明 | 缓解措施 |
|------|------|----------|
| 迁移失败 | 大数据量 ALTER TABLE 可能超时 | WAL 模式 + 5秒 busy_timeout |
| 版本冲突 | 多进程同时执行迁移 | SQLite 文件锁机制 |
| 回滚困难 | sqlx 迁移不支持回滚 | 严格测试迁移脚本，保留备份 |

#### 数据一致性风险
- **WAL 模式**：虽然提升并发，但需要确保 `-wal` 文件正确同步
- **跨库事务**：状态库和日志库分离，无法保证原子性
- **租约过期**：jobs 表的分布式锁依赖时钟同步

### 6.2 边界情况

```rust
// 1. 日志分区清理边界（runtime/logs.rs）
const LOG_PARTITION_SIZE_LIMIT_BYTES: i64 = 10 * 1024 * 1024;  // 10 MiB
const LOG_PARTITION_ROW_LIMIT: i64 = 1_000;

// 2. 重试机制边界（runtime/memories.rs）
const DEFAULT_RETRY_REMAINING: i64 = 3;  // Stage1 任务默认重试 3 次

// 3. 回填租约边界（runtime/backfill.rs）
// try_claim_backfill(lease_seconds) - 租约过期后才能重新认领
```

### 6.3 改进建议

#### 短期改进
1. **迁移脚本验证**：添加 CI 检查确保迁移脚本语法正确
2. **版本号管理**：考虑使用 `user_version` PRAGMA 双重校验
3. **迁移日志**：记录迁移执行历史到独立表

#### 中期改进
1. **分库策略**：当单表数据量超过 100万行时，考虑按时间分表
2. **索引优化**：定期分析查询模式，优化索引（如 `idx_jobs_kind_status_retry_lease`）
3. **数据归档**：历史线程数据自动归档到冷存储

#### 长期改进
1. **迁移框架增强**：考虑引入 `refinery` 或自定义迁移框架，支持回滚
2. **Schema 版本化**：API 级别的 Schema 兼容性保证
3. **多后端支持**：抽象存储层，支持 PostgreSQL 等企业级数据库

### 6.4 测试覆盖

当前测试（基于代码分析）：
- ✅ 迁移脚本语法正确性（通过编译时检查）
- ✅ 数据库初始化和清理逻辑（backfill.rs 测试）
- ✅ 日志分区清理边界（logs.rs 测试）
- ✅ Agent Job 生命周期（agent_jobs.rs 测试）

建议补充：
- ⬜ 大规模数据迁移性能测试
- ⬜ 并发迁移冲突测试
- ⬜ 数据库损坏恢复测试

---

## 附录：迁移文件完整列表

### 状态数据库迁移（migrations/）
| 编号 | 文件 | 主要内容 |
|------|------|----------|
| 0001 | 0001_threads.sql | 创建 threads 表及索引 |
| 0002 | 0002_logs.sql | 创建 logs 表（后迁移到独立库） |
| 0003 | 0003_logs_thread_id.sql | logs 表添加 thread_id |
| 0004 | 0004_thread_dynamic_tools.sql | 创建 thread_dynamic_tools 表 |
| 0005 | 0005_threads_cli_version.sql | threads 表添加 cli_version |
| 0006 | 0006_memories.sql | 创建 stage1_outputs 和 jobs 表 |
| 0007 | 0007_threads_first_user_message.sql | threads 表添加 first_user_message |
| 0008 | 0008_backfill_state.sql | 创建 backfill_state 表 |
| 0009 | 0009_stage1_outputs_rollout_slug.sql | stage1_outputs 添加 rollout_slug |
| 0010 | 0010_logs_process_id.sql | logs 表添加 process_uuid |
| 0011 | 0011_logs_partition_prune_indexes.sql | 优化 logs 表索引 |
| 0012 | 0012_logs_estimated_bytes.sql | logs 表添加 estimated_bytes |
| 0013 | 0013_threads_agent_nickname.sql | threads 添加 agent_nickname/agent_role |
| 0014 | 0014_agent_jobs.sql | 创建 agent_jobs/agent_job_items 表 |
| 0015 | 0015_agent_jobs_max_runtime_seconds.sql | agent_jobs 添加 max_runtime_seconds |
| 0016 | 0016_memory_usage.sql | stage1_outputs 添加 usage_count/last_usage |
| 0017 | 0017_phase2_selection_flag.sql | stage1_outputs 添加 selected_for_phase2 |
| 0018 | 0018_phase2_selection_snapshot.sql | 添加 selected_for_phase2_source_updated_at 和 memory_mode |
| 0019 | 0019_thread_dynamic_tools_defer_loading.sql | thread_dynamic_tools 添加 defer_loading |
| 0020 | 0020_threads_model_reasoning_effort.sql | threads 添加 model 和 reasoning_effort |

### 日志数据库迁移（logs_migrations/）
| 编号 | 文件 | 主要内容 |
|------|------|----------|
| 0001 | 0001_logs.sql | 创建独立 logs 表（完整 Schema） |
| 0002 | 0002_logs_feedback_log_body.sql | 重构 message 为 feedback_log_body |
