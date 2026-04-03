# codex-rs/state/logs_migrations 深度研究文档

## 目录
1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 目录定位

`codex-rs/state/logs_migrations/` 是 Codex 项目中专门用于管理**日志数据库 (logs database)** 的 SQL 迁移脚本目录。它与 `codex-rs/state/migrations/`（管理主状态数据库）平行存在，共同构成 Codex 的 SQLite 数据库版本管理系统。

### 核心职责

1. **独立日志存储**: 日志数据被存储在独立的 SQLite 数据库文件（`logs_1.sqlite`）中，与主状态数据库（`state_5.sqlite`）分离，以减少锁竞争并提高性能。

2. **数据库模式演进**: 管理日志数据库的表结构变更，包括：
   - 初始表结构创建
   - 字段重命名（`message` → `feedback_log_body`）
   - 索引优化

3. **数据迁移**: 在模式变更时确保现有数据的无损迁移。

### 架构背景

Codex 项目采用**双数据库架构**:

```
~/.codex/
├── state_5.sqlite      # 主状态数据库 (threads, agent_jobs, memories 等)
└── logs_1.sqlite       # 日志数据库 (logs 表)
```

分离的原因（来自 `codex-rs/state/src/lib.rs` 注释）:
> "keeping logs in a dedicated file to reduce lock contention with the rest of the state store"

---

## 功能点目的

### Migration 0001: 初始日志表创建

**文件**: `0001_logs.sql`

**目的**: 建立基础的日志存储结构，支持 Codex 的日志追踪和反馈系统。

**表结构设计**:
```sql
CREATE TABLE logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts INTEGER NOT NULL,           -- 秒级时间戳
    ts_nanos INTEGER NOT NULL,     -- 纳秒部分
    level TEXT NOT NULL,           -- 日志级别 (TRACE/DEBUG/INFO/WARN/ERROR)
    target TEXT NOT NULL,          -- 日志目标模块
    message TEXT,                  -- 日志消息内容
    module_path TEXT,              -- 模块路径
    file TEXT,                     -- 源文件
    line INTEGER,                  -- 行号
    thread_id TEXT,                -- 关联的线程ID
    process_uuid TEXT,             -- 进程UUID
    estimated_bytes INTEGER NOT NULL DEFAULT 0  -- 估算字节数
);
```

**索引策略**:
- `idx_logs_ts`: 按时间倒序查询
- `idx_logs_thread_id`: 按线程ID查询
- `idx_logs_process_uuid`: 按进程UUID查询
- `idx_logs_thread_id_ts`: 复合索引，支持线程日志的时间范围查询
- `idx_logs_process_uuid_threadless_ts`: 部分索引，仅包含 `thread_id IS NULL` 的行，用于查询无线程日志

### Migration 0002: feedback_log_body 字段重构

**文件**: `0002_logs_feedback_log_body.sql`

**目的**: 将 `message` 字段重命名为 `feedback_log_body`，以更准确地反映其用途——存储格式化的反馈日志正文。

**迁移策略** (SQLite 不支持直接重命名列):
```sql
-- 1. 重命名旧表
ALTER TABLE logs RENAME TO logs_old;

-- 2. 创建新表（使用新字段名）
CREATE TABLE logs (...feedback_log_body TEXT...);

-- 3. 迁移数据
INSERT INTO logs SELECT ..., message AS feedback_log_body, ... FROM logs_old;

-- 4. 删除旧表
DROP TABLE logs_old;

-- 5. 重建索引
CREATE INDEX ...
```

**设计意图**:
- `feedback_log_body` 存储的是**渲染后的完整日志内容**，包括 span 层级结构和字段信息
- 与 `LogEntry.message` 区分：后者是原始消息，前者是格式化后的反馈可用内容
- 支持 `/feedback` API 的日志检索功能

---

## 具体技术实现

### 1. 迁移执行机制

**Migrator 定义** (`codex-rs/state/src/migrations.rs`):
```rust
use sqlx::migrate::Migrator;

pub(crate) static STATE_MIGRATOR: Migrator = sqlx::migrate!("./migrations");
pub(crate) static LOGS_MIGRATOR: Migrator = sqlx::migrate!("./logs_migrations");
```

**执行时机** (`codex-rs/state/src/runtime.rs`):
```rust
pub async fn init(codex_home: PathBuf, default_provider: String) -> anyhow::Result<Arc<Self>> {
    // ...
    let logs_pool = match open_sqlite(&logs_path, &LOGS_MIGRATOR).await {
        Ok(db) => Arc::new(db),
        Err(err) => {
            warn!("failed to open logs db at {}: {err}", logs_path.display());
            return Err(err);
        }
    };
    // ...
}

async fn open_sqlite(path: &Path, migrator: &'static Migrator) -> anyhow::Result<SqlitePool> {
    let options = SqliteConnectOptions::new()
        .filename(path)
        .create_if_missing(true)
        .journal_mode(SqliteJournalMode::Wal)      // WAL 模式
        .synchronous(SqliteSynchronous::Normal)
        .busy_timeout(Duration::from_secs(5))
        .log_statements(LevelFilter::Off);
    
    let pool = SqlitePoolOptions::new()
        .max_connections(5)
        .connect_with(options)
        .await?;
    
    migrator.run(&pool).await?;  // <-- 执行迁移
    Ok(pool)
}
```

### 2. 日志写入流程

**LogDbLayer** (`codex-rs/state/src/log_db.rs`):

作为 `tracing_subscriber::Layer` 的实现，捕获 tracing 事件并写入数据库：

```rust
pub struct LogDbLayer {
    sender: mpsc::Sender<LogDbCommand>,
    process_uuid: String,
}

pub fn start(state_db: Arc<StateRuntime>) -> LogDbLayer {
    let process_uuid = current_process_log_uuid().to_string();
    let (sender, receiver) = mpsc::channel(LOG_QUEUE_CAPACITY);
    
    // 启动插入任务
    tokio::spawn(run_inserter(Arc::clone(&state_db), receiver));
    // 启动清理任务
    tokio::spawn(run_retention_cleanup(state_db));
    
    LogDbLayer { sender, process_uuid }
}
```

**批处理与刷新策略**:
```rust
const LOG_QUEUE_CAPACITY: usize = 512;
const LOG_BATCH_SIZE: usize = 128;
const LOG_FLUSH_INTERVAL: Duration = Duration::from_secs(2);
const LOG_RETENTION_DAYS: i64 = 10;
```

**反馈日志正文格式化**:
```rust
fn format_feedback_log_body<S>(
    event: &Event<'_>,
    ctx: &tracing_subscriber::layer::Context<'_, S>,
) -> String
where
    S: tracing::Subscriber + for<'a> LookupSpan<'a>,
{
    let mut feedback_log_body = String::new();
    
    // 1. 构建 span 层级路径
    if let Some(scope) = ctx.event_scope(event) {
        for span in scope.from_root() {
            feedback_log_body.push_str(&log_context.name);
            if !log_context.formatted_fields.is_empty() {
                feedback_log_body.push('{');
                feedback_log_body.push_str(&log_context.formatted_fields);
                feedback_log_body.push('}');
            }
            feedback_log_body.push(':');
        }
        if !feedback_log_body.is_empty() {
            feedback_log_body.push(' ');
        }
    }
    
    // 2. 追加事件字段
    feedback_log_body.push_str(&format_fields(event));
    feedback_log_body
}
```

### 3. 分区裁剪 (Partition Pruning)

**预算控制** (`codex-rs/state/src/runtime.rs`):
```rust
// 每个分区保留的日志内容上限
const LOG_PARTITION_SIZE_LIMIT_BYTES: i64 = 10 * 1024 * 1024;  // 10 MiB
const LOG_PARTITION_ROW_LIMIT: i64 = 1_000;  // 行数上限
```

**分区定义**:
1. **Thread logs**: `thread_id IS NOT NULL`，按 `thread_id` 分区
2. **Threadless process logs**: `thread_id IS NULL AND process_uuid IS NOT NULL`，按 `process_uuid` 分区
3. **Threadless null process**: `thread_id IS NULL AND process_uuid IS NULL`，单独分区

**裁剪实现** (`codex-rs/state/src/runtime/logs.rs`):
```rust
async fn prune_logs_after_insert(
    &self,
    entries: &[LogEntry],
    tx: &mut SqliteConnection,
) -> anyhow::Result<()> {
    // 使用窗口函数计算累积字节数
    let mut prune_threads = QueryBuilder::<Sqlite>::new(
        r#"
DELETE FROM logs
WHERE id IN (
    SELECT id
    FROM (
        SELECT
            id,
            SUM(estimated_bytes) OVER (
                PARTITION BY thread_id
                ORDER BY ts DESC, ts_nanos DESC, id DESC
            ) AS cumulative_bytes,
            ROW_NUMBER() OVER (
                PARTITION BY thread_id
                ORDER BY ts DESC, ts_nanos DESC, id DESC
            ) AS row_number
        FROM logs
        WHERE thread_id IN (...)
    )
    WHERE cumulative_bytes > ? OR row_number > ?
)
"#,
    );
    // ...
}
```

### 4. 反馈日志查询

**query_feedback_logs** (`codex-rs/state/src/runtime/logs.rs`):

用于 `/feedback` API，返回特定线程的日志：

```rust
pub async fn query_feedback_logs(&self, thread_id: &str) -> anyhow::Result<Vec<u8>> {
    let rows = sqlx::query_as::<_, FeedbackLogRow>(
        r#"
WITH latest_process AS (
    -- 获取该线程最新的进程UUID
    SELECT process_uuid
    FROM logs
    WHERE thread_id = ? AND process_uuid IS NOT NULL
    ORDER BY ts DESC, ts_nanos DESC, id DESC
    LIMIT 1
),
feedback_logs AS (
    SELECT ts, ts_nanos, level, feedback_log_body, estimated_bytes, id
    FROM logs
    WHERE feedback_log_body IS NOT NULL AND (
        thread_id = ?
        OR (
            thread_id IS NULL
            AND process_uuid IN (SELECT process_uuid FROM latest_process)
        )
    )
),
bounded_feedback_logs AS (
    SELECT
        ts, ts_nanos, level, feedback_log_body, id,
        SUM(estimated_bytes) OVER (
            ORDER BY ts DESC, ts_nanos DESC, id DESC
        ) AS cumulative_estimated_bytes
    FROM feedback_logs
)
SELECT ts, ts_nanos, level, feedback_log_body
FROM bounded_feedback_logs
WHERE cumulative_estimated_bytes <= ?
ORDER BY ts DESC, ts_nanos DESC, id DESC
"#,
    )
    .bind(thread_id)
    .bind(thread_id)
    .bind(LOG_PARTITION_SIZE_LIMIT_BYTES)
    .fetch_all(self.logs_pool.as_ref())
    .await?;
    
    // 格式化为最终输出
    let mut lines = Vec::new();
    for row in rows {
        let line = format_feedback_log_line(row.ts, row.ts_nanos, &row.level, &row.feedback_log_body);
        lines.push(line);
    }
    // ...
}
```

---

## 关键代码路径与文件引用

### 文件结构

```
codex-rs/state/
├── logs_migrations/                    # <-- 本研究目录
│   ├── 0001_logs.sql                   # 初始表结构
│   └── 0002_logs_feedback_log_body.sql # 字段重命名迁移
├── migrations/                         # 主状态数据库迁移
│   ├── 0002_logs.sql                   # 早期 logs 表（已废弃）
│   ├── 0010_logs_process_id.sql        # 添加 process_uuid
│   ├── 0011_logs_partition_prune_indexes.sql
│   └── 0012_logs_estimated_bytes.sql   # 添加 estimated_bytes
├── src/
│   ├── migrations.rs                   # Migrator 定义
│   ├── lib.rs                          # 模块导出
│   ├── log_db.rs                       # LogDbLayer 实现
│   ├── model/log.rs                    # LogEntry/LogRow/LogQuery 定义
│   ├── runtime.rs                      # StateRuntime 初始化
│   ├── runtime/logs.rs                 # 日志相关方法
│   └── bin/logs_client.rs              # CLI 工具
├── Cargo.toml
└── BUILD.bazel
```

### 关键代码引用

| 功能 | 文件路径 | 行号/区域 |
|------|----------|-----------|
| Migrator 定义 | `src/migrations.rs` | 第4行 |
| 数据库初始化 | `src/runtime.rs` | 第83-124行 (`init`) |
| 迁移执行 | `src/runtime.rs` | 第132-146行 (`open_sqlite`) |
| 日志层创建 | `src/log_db.rs` | 第47-67行 (`start`) |
| 事件处理 | `src/log_db.rs` | 第135-164行 (`on_event`) |
| 反馈日志格式化 | `src/log_db.rs` | 第242-271行 (`format_feedback_log_body`) |
| 批量插入 | `src/runtime/logs.rs` | 第8-45行 (`insert_logs`) |
| 分区裁剪 | `src/runtime/logs.rs` | 第60-284行 (`prune_logs_after_insert`) |
| 反馈查询 | `src/runtime/logs.rs` | 第317-383行 (`query_feedback_logs`) |
| 数据模型 | `src/model/log.rs` | 全文 |
| CLI 工具 | `src/bin/logs_client.rs` | 全文 |

### 版本常量

```rust
// codex-rs/state/src/lib.rs
pub const LOGS_DB_FILENAME: &str = "logs";
pub const LOGS_DB_VERSION: u32 = 1;
pub const STATE_DB_FILENAME: &str = "state";
pub const STATE_DB_VERSION: u32 = 5;
```

生成的文件名：`logs_1.sqlite`, `state_5.sqlite`

---

## 依赖与外部交互

### 内部依赖

```rust
// 同 crate 内模块
codex-state/src/migrations.rs       → LOGS_MIGRATOR
codex-state/src/runtime.rs          → StateRuntime::init, logs_pool
codex-state/src/runtime/logs.rs     → insert_logs, query_logs, query_feedback_logs
codex-state/src/log_db.rs           → LogDbLayer
codex-state/src/model/log.rs        → LogEntry, LogRow, LogQuery
```

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `sqlx` | SQLite 数据库访问和迁移 |
| `tokio` | 异步运行时、channel、定时器 |
| `tracing` | 日志事件捕获 |
| `tracing-subscriber` | Layer 实现 |
| `chrono` | 时间处理 |
| `uuid` | 进程 UUID 生成 |

### 上游调用方

```rust
// 被调用方分析（通过 grep 发现）

// 1. TUI 应用
codex-rs/tui/src/main.rs           → LogDbLayer::start()

// 2. CLI 工具
codex-rs/state/src/bin/logs_client.rs  → StateRuntime::query_logs()

// 3. App Server
codex-rs/app-server/src/main.rs    → 可能使用日志功能
```

### Bazel 构建配置

```starlark
# codex-rs/state/BUILD.bazel
codex_rust_crate(
    name = "state",
    crate_name = "codex_state",
    compile_data = glob(["logs_migrations/**", "migrations/**"]),  # <-- 包含迁移文件
)
```

**重要**: 迁移文件必须通过 `compile_data` 包含，因为 `sqlx::migrate!` 宏在编译时读取这些文件。

---

## 风险、边界与改进建议

### 已知风险

#### 1. 迁移文件路径依赖

**风险**: `sqlx::migrate!("./logs_migrations")` 使用相对路径，依赖于编译时的工作目录。

**缓解**: Bazel 的 `compile_data` 确保文件在编译时可用，且 AGENTS.md 特别说明：
> "Bazel does not automatically make source-tree files available to compile-time Rust file access. If you add `include_str!`, `include_bytes!`, `sqlx::migrate!`, or similar build-time file or directory reads, update the crate's `BUILD.bazel` (`compile_data`, `build_script_data`, or test data)"

#### 2. 数据保留策略

**当前策略**:
- 全局：10 天 (`LOG_RETENTION_DAYS: i64 = 10`)
- 每分区：10 MiB + 1000 行

**风险**: 如果单个日志条目超过 10 MiB，它会被立即删除（插入后裁剪）。

**测试验证** (`codex-rs/state/src/runtime/logs.rs` 第776-812行):
```rust
#[tokio::test]
async fn insert_logs_prunes_single_thread_row_when_it_exceeds_size_limit() {
    let eleven_mebibytes = "d".repeat(11 * 1024 * 1024);
    // 插入后查询结果为空
    assert!(rows.is_empty());
}
```

#### 3. 迁移不可逆

Migration 0002 使用 "CREATE NEW → MIGRATE → DROP OLD" 模式，如果迁移中断可能导致数据丢失。

**缓解**: SQLite 的事务机制确保原子性，且 `sqlx::migrate` 使用默认的事务包装。

### 边界情况

#### 1. Thread ID 与 Process UUID 的关联

**设计**: `query_feedback_logs` 不仅返回指定 thread_id 的日志，还返回同一进程中 `thread_id IS NULL` 的日志（通过 `latest_process` CTE）。

**边界**: 如果进程切换（新的 process_uuid），旧进程的 threadless 日志不会出现在反馈中。

#### 2. 日志级别过滤

`LogQuery.level_upper` 使用精确匹配（`UPPER(level) = ?`），不支持范围查询（如 INFO 及以上）。

#### 3. 并发写入

虽然 SQLite WAL 模式支持并发读取，但写入仍然是串行的。高频率日志写入可能导致：
- Channel 满（512 容量）时 `try_send` 失败，日志丢失
- 批量插入延迟（最多 2 秒或 128 条）

### 改进建议

#### 1. 迁移管理

**建议**: 添加迁移版本校验和回滚机制。

```rust
// 可能的改进：在启动时验证迁移状态
pub async fn verify_migration_state(&self) -> anyhow::Result<()> {
    let row: (i64,) = sqlx::query_as("SELECT MAX(version) FROM _sqlx_migrations")
        .fetch_one(self.logs_pool.as_ref())
        .await?;
    ensure!(row.0 == EXPECTED_LOGS_MIGRATION_VERSION, "Migration mismatch");
    Ok(())
}
```

#### 2. 可观测性

**建议**: 添加指标监控：
- 日志丢弃率（channel 满）
- 插入延迟
- 裁剪频率和数量

#### 3. 查询优化

**建议**: `query_feedback_logs` 的 CTE 可以进一步优化：
- 为 `latest_process` 子查询添加更高效的索引
- 考虑物化视图缓存常用查询结果

#### 4. 配置化

**建议**: 当前硬编码的常量可通过配置暴露：
```rust
pub struct LogConfig {
    pub retention_days: i64,
    pub partition_size_limit: i64,
    pub partition_row_limit: i64,
    pub batch_size: usize,
    pub flush_interval: Duration,
}
```

#### 5. 迁移文件命名规范

**建议**: 当前使用 `000X_description.sql` 格式，建议增加日期前缀以避免冲突：
```
20240315_0001_logs.sql
20240320_0002_logs_feedback_log_body.sql
```

---

## 总结

`codex-rs/state/logs_migrations/` 是 Codex 日志子系统的核心基础设施，负责：

1. **模式演进**: 通过 SQL 迁移脚本管理数据库结构变更
2. **数据隔离**: 独立的数据库文件减少与主状态存储的锁竞争
3. **性能优化**: 分区裁剪策略控制存储增长
4. **反馈支持**: `feedback_log_body` 字段支持 `/feedback` API 的日志检索

该目录与 `src/log_db.rs`、`src/runtime/logs.rs` 紧密协作，构成了完整的日志采集、存储、查询和清理流水线。
