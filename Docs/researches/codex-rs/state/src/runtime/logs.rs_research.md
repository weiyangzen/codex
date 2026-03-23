# Logs Runtime 研究文档

## 文件信息
- **源文件**: `codex-rs/state/src/runtime/logs.rs`
- **文件大小**: 55,898 bytes (1524 行)
- **所属模块**: `codex-state` crate 的 runtime 子模块

---

## 一、场景与职责

### 1.1 核心定位
`logs.rs` 是 Codex 状态管理系统的**日志存储与查询引擎**，负责管理应用程序日志的持久化、查询、自动清理和反馈日志生成。它使用独立的 SQLite 数据库（logs.db）存储日志，与主状态数据库分离以减少锁竞争。

### 1.2 主要使用场景
1. **日志持久化**: 接收来自 `tracing` 框架的日志事件并写入数据库
2. **日志查询**: 支持按时间、级别、线程、模块等条件查询日志
3. **反馈日志**: 为特定线程生成用于 AI 反馈的日志内容
4. **日志清理**: 自动按分区（线程/进程）大小和行数限制清理旧日志
5. **日志流**: 支持类似 `tail -f` 的实时日志流（通过 `logs_client.rs`）

### 1.3 架构位置
```
┌─────────────────────────────────────────────────────────────────────────┐
│                              Applications                               │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │ bin/logs_client.rs                                                │  │
│  │ - CLI 工具，用于实时查看日志                                       │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                              │                                          │
│                              ▼                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │ codex-state                                                       │  │
│  │ ┌─────────────────────┐  ┌─────────────────────────────────────┐  │  │
│  │ │ log_db.rs           │  │ runtime/logs.rs ◄── 本文件           │  │  │
│  │ │ - tracing Layer     │  │ - 日志 CRUD 操作                     │  │  │
│  │ │ - 批量插入          │  │ - 分区清理策略                       │  │  │
│  │ │ - 后台任务          │  │ - 查询和过滤                         │  │  │
│  │ └─────────────────────┘  └─────────────────────────────────────┘  │  │
│  │ ┌─────────────────────┐  ┌─────────────────────────────────────┐  │  │
│  │ │ model/log.rs        │  │ logs_migrations/                    │  │  │
│  │ │ - LogEntry          │  │ - 0002_logs.sql                     │  │  │
│  │ │ - LogQuery          │  │ - 0012_logs_estimated_bytes.sql     │  │  │
│  │ └─────────────────────┘  └─────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 二、功能点目的

### 2.1 功能概览

| 功能类别 | 方法名 | 目的 |
|---------|--------|------|
| **日志写入** | `insert_log` | 插入单条日志 |
| | `insert_logs` | 批量插入日志（事务）|
| **日志查询** | `query_logs` | 通用日志查询 |
| | `query_feedback_logs` | 查询线程反馈日志 |
| | `max_log_id` | 获取最大日志 ID |
| **日志清理** | `delete_logs_before` | 删除指定时间前的日志 |
| | `prune_logs_after_insert` | 插入后自动清理（私有）|

### 2.2 分区清理策略

日志系统维护**三个独立的分区预算**：

```
┌─────────────────────────────────────────────────────────────────┐
│                      日志分区预算                                │
├─────────────────────────────────────────────────────────────────┤
│  分区类型 1: Thread Logs                                        │
│  - 条件: thread_id IS NOT NULL                                  │
│  - 分区键: thread_id                                            │
│  - 限制: 10 MiB / 1000 行 每线程                                 │
├─────────────────────────────────────────────────────────────────┤
│  分区类型 2: Threadless Process Logs                            │
│  - 条件: thread_id IS NULL AND process_uuid IS NOT NULL         │
│  - 分区键: process_uuid                                         │
│  - 限制: 10 MiB / 1000 行 每进程                                 │
├─────────────────────────────────────────────────────────────────┤
│  分区类型 3: Threadless Null Process Logs                       │
│  - 条件: thread_id IS NULL AND process_uuid IS NULL             │
│  - 分区键: NULL（视为独立分区）                                  │
│  - 限制: 10 MiB / 1000 行                                       │
└─────────────────────────────────────────────────────────────────┘
```

### 2.3 反馈日志机制

反馈日志用于将系统日志提供给 AI 作为上下文：

```
┌─────────────────────────────────────────────────────────────────┐
│  query_feedback_logs(thread_id)                                 │
│                                                                 │
│  1. 找到该线程最新的 process_uuid                               │
│     SELECT process_uuid FROM logs                               │
│     WHERE thread_id = ? ORDER BY ts DESC LIMIT 1                │
│                                                                 │
│  2. 收集两类日志:                                               │
│     a) 该线程的所有日志 (thread_id = ?)                         │
│     b) 同进程的无线程日志 (thread_id IS NULL                   │
│        AND process_uuid = 最新 process_uuid)                    │
│                                                                 │
│  3. 按时间排序，限制 10 MiB                                     │
│                                                                 │
│  4. 格式化为 RFC3339 格式:                                      │
│     "2024-01-15T10:30:00.123456Z  INFO message"                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 三、具体技术实现

### 3.1 数据库 Schema

#### logs 表
```sql
CREATE TABLE logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts INTEGER NOT NULL,                    -- 秒级时间戳
    ts_nanos INTEGER NOT NULL,              -- 纳秒部分
    level TEXT NOT NULL,                    -- TRACE/DEBUG/INFO/WARN/ERROR
    target TEXT NOT NULL,                   -- 日志目标模块
    feedback_log_body TEXT,                 -- 反馈日志内容
    module_path TEXT,                       -- 模块路径
    file TEXT,                              -- 源文件
    line INTEGER,                           -- 行号
    thread_id TEXT,                         -- 关联线程 ID
    process_uuid TEXT,                      -- 进程 UUID
    estimated_bytes INTEGER NOT NULL        -- 预估字节数（用于清理）
);

-- 索引
CREATE INDEX idx_logs_ts ON logs(ts DESC, ts_nanos DESC, id DESC);
CREATE INDEX idx_logs_thread_id ON logs(thread_id);
CREATE INDEX idx_logs_thread_id_ts ON logs(thread_id, ts DESC);
CREATE INDEX idx_logs_process_uuid_threadless_ts 
    ON logs(process_uuid, ts DESC) WHERE thread_id IS NULL;
```

### 3.2 关键数据结构

#### LogEntry (写入结构)
```rust
#[derive(Clone, Debug, Serialize)]
pub struct LogEntry {
    pub ts: i64,                           // Unix 秒
    pub ts_nanos: i64,                     // 纳秒
    pub level: String,                     // 日志级别
    pub target: String,                    // 目标模块
    pub message: Option<String>,           // 原始消息（向后兼容）
    pub feedback_log_body: Option<String>, // 反馈日志内容
    pub thread_id: Option<String>,         // 线程 ID
    pub process_uuid: Option<String>,      // 进程 UUID
    pub module_path: Option<String>,       // 模块路径
    pub file: Option<String>,             // 文件
    pub line: Option<i64>,                // 行号
}
```

#### LogRow (查询结果)
```rust
#[derive(Clone, Debug, FromRow)]
pub struct LogRow {
    pub id: i64,
    pub ts: i64,
    pub ts_nanos: i64,
    pub level: String,
    pub target: String,
    pub message: Option<String>,  // feedback_log_body 的别名
    pub thread_id: Option<String>,
    pub process_uuid: Option<String>,
    pub file: Option<String>,
    pub line: Option<i64>,
}
```

#### LogQuery (查询参数)
```rust
#[derive(Clone, Debug, Default)]
pub struct LogQuery {
    pub level_upper: Option<String>,    // 精确匹配日志级别
    pub from_ts: Option<i64>,           // 开始时间
    pub to_ts: Option<i64>,             // 结束时间
    pub module_like: Vec<String>,       // 模块路径模糊匹配
    pub file_like: Vec<String>,         // 文件路径模糊匹配
    pub thread_ids: Vec<String>,        // 线程 ID 列表
    pub search: Option<String>,         // 内容搜索
    pub include_threadless: bool,       // 包含无线程日志
    pub after_id: Option<i64>,          // 分页游标
    pub limit: Option<usize>,           // 限制条数
    pub descending: bool,               // 降序/升序
}
```

### 3.3 核心算法

#### 3.3.1 批量插入与清理（行 9-284）

```rust
pub async fn insert_logs(&self, entries: &[LogEntry]) -> anyhow::Result<()> {
    if entries.is_empty() {
        return Ok(());
    }

    let mut tx = self.logs_pool.begin().await?;
    let mut builder = QueryBuilder::<Sqlite>::new(
        "INSERT INTO logs (...)",
    );
    
    // 批量构建 INSERT
    builder.push_values(entries, |mut row, entry| {
        let estimated_bytes = calculate_size(entry);
        row.push_bind(entry.ts)
            .push_bind(entry.ts_nanos)
            // ... 其他字段
            .push_bind(estimated_bytes);
    });
    
    builder.build().execute(&mut *tx).await?;
    
    // 关键：在同一事务中执行清理
    self.prune_logs_after_insert(entries, &mut tx).await?;
    
    tx.commit().await?;
    Ok(())
}
```

#### 3.3.2 分区清理算法（行 60-284）

清理算法使用 **SQL 窗口函数** 实现高效批量删除：

```rust
async fn prune_logs_after_insert(
    &self,
    entries: &[LogEntry],
    tx: &mut SqliteConnection,
) -> anyhow::Result<()> {
    // 1. 收集受影响的线程 ID
    let thread_ids: BTreeSet<&str> = entries
        .iter()
        .filter_map(|e| e.thread_id.as_deref())
        .collect();
    
    if !thread_ids.is_empty() {
        // 2. 预检查：找出超出限制的分区
        let over_limit_threads: Vec<String> = sqlx::query(
            "SELECT thread_id FROM logs 
             WHERE thread_id IN (...)
             GROUP BY thread_id 
             HAVING SUM(estimated_bytes) > 10MiB 
                OR COUNT(*) > 1000"
        ).fetch_all(&mut *tx).await?;
        
        if !over_limit_threads.is_empty() {
            // 3. 使用窗口函数删除旧日志
            sqlx::query(
                "DELETE FROM logs WHERE id IN (
                    SELECT id FROM (
                        SELECT id,
                            SUM(estimated_bytes) OVER (
                                PARTITION BY thread_id 
                                ORDER BY ts DESC, ts_nanos DESC, id DESC
                            ) AS cumulative_bytes,
                            ROW_NUMBER() OVER (
                                PARTITION BY thread_id 
                                ORDER BY ts DESC, ts_nanos DESC, id DESC
                            ) AS row_number
                        FROM logs WHERE thread_id IN (...)
                    )
                    WHERE cumulative_bytes > 10MiB OR row_number > 1000
                )"
            ).execute(&mut *tx).await?;
        }
    }
    
    // 类似逻辑处理 threadless 日志...
}
```

**窗口函数解释：**
- `SUM(...) OVER (PARTITION BY ... ORDER BY ...)`：计算每个分区按时间倒序的累计字节数
- `ROW_NUMBER() OVER (...)`：计算每行在分区内的序号
- 删除条件：`cumulative_bytes > 10MiB`（超大小）或 `row_number > 1000`（超行数）

#### 3.3.3 反馈日志查询（行 317-383）

```rust
pub async fn query_feedback_logs(&self, thread_id: &str) -> anyhow::Result<Vec<u8>> {
    let max_bytes = 10 * 1024 * 1024; // 10 MiB
    
    let rows = sqlx::query_as::<_, FeedbackLogRow>(
        r#"
WITH latest_process AS (
    -- 找到该线程最新的进程 UUID
    SELECT process_uuid FROM logs
    WHERE thread_id = ? AND process_uuid IS NOT NULL
    ORDER BY ts DESC, ts_nanos DESC, id DESC
    LIMIT 1
),
feedback_logs AS (
    -- 收集线程日志和同进程的无线程日志
    SELECT ts, ts_nanos, level, feedback_log_body, estimated_bytes, id
    FROM logs
    WHERE feedback_log_body IS NOT NULL AND (
        thread_id = ?
        OR (thread_id IS NULL AND process_uuid IN (SELECT process_uuid FROM latest_process))
    )
),
bounded_feedback_logs AS (
    -- 计算累计大小，限制在预算内
    SELECT ts, ts_nanos, level, feedback_log_body, id,
        SUM(estimated_bytes) OVER (ORDER BY ts DESC, ts_nanos DESC, id DESC) 
            AS cumulative_estimated_bytes
    FROM feedback_logs
)
SELECT ts, ts_nanos, level, feedback_log_body
FROM bounded_feedback_logs
WHERE cumulative_estimated_bytes <= ?  -- 10 MiB 限制
ORDER BY ts DESC, ts_nanos DESC, id DESC
        "#,
    )
    .bind(thread_id)
    .bind(thread_id)
    .bind(LOG_PARTITION_SIZE_LIMIT_BYTES)
    .fetch_all(self.logs_pool.as_ref()).await?;

    // 格式化为字节数组
    let mut lines = Vec::new();
    let mut total_bytes = 0usize;
    for row in rows {
        let line = format_feedback_log_line(row.ts, row.ts_nanos, &row.level, &row.feedback_log_body);
        if total_bytes.saturating_add(line.len()) > max_bytes {
            break;
        }
        total_bytes += line.len();
        lines.push(line);
    }
    
    // 反转顺序（从旧到新）
    let mut ordered_bytes = Vec::with_capacity(total_bytes);
    for line in lines.into_iter().rev() {
        ordered_bytes.extend_from_slice(line.as_bytes());
    }
    Ok(ordered_bytes)
}
```

### 3.4 查询过滤实现（行 422-485）

```rust
fn push_log_filters<'a>(builder: &mut QueryBuilder<'a, Sqlite>, query: &'a LogQuery) {
    // 日志级别精确匹配
    if let Some(level_upper) = query.level_upper.as_ref() {
        builder.push(" AND UPPER(level) = ").push_bind(level_upper.as_str());
    }
    
    // 时间范围
    if let Some(from_ts) = query.from_ts {
        builder.push(" AND ts >= ").push_bind(from_ts);
    }
    if let Some(to_ts) = query.to_ts {
        builder.push(" AND ts <= ").push_bind(to_ts);
    }
    
    // 模块/文件模糊匹配 (LIKE '%pattern%')
    push_like_filters(builder, "module_path", &query.module_like);
    push_like_filters(builder, "file", &query.file_like);
    
    // 线程过滤
    if !query.thread_ids.is_empty() || query.include_threadless {
        builder.push(" AND (");
        // ... OR 条件构建
        builder.push(")");
    }
    
    // 分页游标
    if let Some(after_id) = query.after_id {
        builder.push(" AND id > ").push_bind(after_id);
    }
    
    // 内容搜索 (INSTR 函数)
    if let Some(search) = query.search.as_ref() {
        builder.push(" AND INSTR(COALESCE(feedback_log_body, ''), ")
              .push_bind(search.as_str()).push(") > 0");
    }
}
```

---

## 四、关键代码路径与文件引用

### 4.1 内部依赖

| 文件路径 | 用途 |
|---------|------|
| `model/log.rs` | LogEntry, LogRow, LogQuery 定义 |
| `model/mod.rs` | 模块导出 |
| `runtime.rs` | 常量定义 (LOG_PARTITION_SIZE_LIMIT_BYTES, LOG_PARTITION_ROW_LIMIT) |
| `log_db.rs` | tracing Layer 实现，调用 insert_logs |
| `migrations/0002_logs.sql` | 初始表结构 |
| `migrations/0012_logs_estimated_bytes.sql` | estimated_bytes 字段迁移 |

### 4.2 外部调用方

| 文件路径 | 调用方式 | 用途 |
|---------|---------|------|
| `log_db.rs` | `insert_logs()` | tracing Layer 批量写入 |
| `bin/logs_client.rs` | `query_logs()`, `max_log_id()` | CLI 日志查看 |
| `core/` | `query_feedback_logs()` | AI 反馈上下文生成 |

### 4.3 关键代码片段

#### 4.3.1 分区清理核心 SQL（行 96-139）
```rust
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
prune_threads.push_bind(LOG_PARTITION_SIZE_LIMIT_BYTES);  // 10 MiB
prune_threads.push_bind(LOG_PARTITION_ROW_LIMIT);         // 1000
```

#### 4.3.2 反馈日志格式化（行 404-420）
```rust
fn format_feedback_log_line(
    ts: i64,
    ts_nanos: i64,
    level: &str,
    feedback_log_body: &str,
) -> String {
    let nanos = u32::try_from(ts_nanos).unwrap_or(0);
    let timestamp = match DateTime::<Utc>::from_timestamp(ts, nanos) {
        Some(dt) => dt.to_rfc3339_opts(chrono::SecondsFormat::Micros, true),
        None => format!("{ts}.{ts_nanos:09}Z"),
    };
    let mut line = format!("{timestamp} {level:>5} {feedback_log_body}");
    if !line.ends_with('\n') {
        line.push('\n');
    }
    line
}
```

---

## 五、依赖与外部交互

### 5.1 直接依赖

| 依赖 | 用途 |
|-----|------|
| `sqlx` | SQLite 异步操作 |
| `chrono` | 时间戳处理 |
| `serde_json` | JSON 处理 |
| `anyhow` | 错误处理 |

### 5.2 数据库交互

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        SQLite DB (logs.db)                              │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                            logs                                 │    │
│  ├─────────────────────────────────────────────────────────────────┤    │
│  │ id: INTEGER PK AUTOINCREMENT                                    │    │
│  │ ts, ts_nanos: INTEGER (时间戳)                                   │    │
│  │ level: TEXT (日志级别)                                           │    │
│  │ target: TEXT (目标模块)                                          │    │
│  │ feedback_log_body: TEXT (反馈内容)                               │    │
│  │ thread_id: TEXT (线程标识)                                       │    │
│  │ process_uuid: TEXT (进程标识)                                    │    │
│  │ estimated_bytes: INTEGER (大小估算)                              │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                         │
│  Indexes:                                                               │
│  - idx_logs_ts: (ts DESC, ts_nanos DESC, id DESC)                      │
│  - idx_logs_thread_id: (thread_id)                                     │
│  - idx_logs_thread_id_ts: (thread_id, ts DESC)                         │
│  - idx_logs_process_uuid_threadless_ts:                                │
│    (process_uuid, ts DESC) WHERE thread_id IS NULL                     │
└─────────────────────────────────────────────────────────────────────────┘
```

### 5.3 双数据库架构

```
┌─────────────────────────────────────────────────────────────────┐
│                     StateRuntime                                │
│  ┌─────────────────────┐      ┌─────────────────────────────┐   │
│  │ pool: SqlitePool    │      │ logs_pool: SqlitePool       │   │
│  │                     │      │                             │   │
│  │ state_5.sqlite      │      │ logs_1.sqlite               │   │
│  │ - threads           │      │ - logs                      │   │
│  │ - agent_jobs        │      │                             │   │
│  │ - backfill_state    │      │                             │   │
│  │ - memories          │      │                             │   │
│  └─────────────────────┘      └─────────────────────────────┘   │
│         │                                │                      │
│         ▼                                ▼                      │
│  业务数据（低写入频率）            日志数据（高写入频率）            │
│  - 减少锁竞争                     - 独立压缩和备份策略              │
│  - 支持 WAL 模式                  - 可单独清理历史                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 六、风险、边界与改进建议

### 6.1 已知风险

| 风险类别 | 描述 | 严重程度 |
|---------|------|---------|
| **清理性能** | 窗口函数在超大数据集上可能性能下降 | 中 |
| **大小估算** | estimated_bytes 是近似值，非精确字节数 | 低 |
| **事务超时** | 大批量插入 + 清理可能导致长事务 | 中 |
| **反馈日志顺序** | 多进程并发时反馈日志顺序可能不严格 | 低 |

### 6.2 边界条件

1. **分区限制**:
   - 大小: 10 MiB (`LOG_PARTITION_SIZE_LIMIT_BYTES`)
   - 行数: 1000 行 (`LOG_PARTITION_ROW_LIMIT`)

2. **批量插入**:
   - 来自 `log_db.rs` 的 `LOG_BATCH_SIZE = 128`
   - 缓冲区满或 2 秒超时触发写入

3. **保留策略**:
   - 默认 10 天 (`LOG_RETENTION_DAYS = 10`)
   - 由 `log_db.rs` 的 `run_retention_cleanup` 执行

4. **反馈日志限制**:
   - 硬限制: 10 MiB
   - 整行保留（不截断单条日志）

### 6.3 改进建议

#### 6.3.1 短期改进

1. **添加清理统计**
   ```rust
   pub struct PruneStats {
       pub thread_partitions_pruned: u64,
       pub threadless_partitions_pruned: u64,
       pub rows_deleted: u64,
   }
   ```

2. **优化大分区清理**
   ```rust
   // 当前：一次性删除所有超预算行
   // 建议：分批删除，避免长事务
   const PRUNE_BATCH_SIZE: usize = 1000;
   ```

3. **添加清理钩子**
   ```rust
   // 允许外部监听清理事件
   pub async fn on_prune<F>(&self, callback: F) 
   where F: Fn(PruneEvent) + Send + Sync
   ```

#### 6.3.2 长期改进

1. **分层存储**:
   - 热数据：SQLite（最近 24 小时）
   - 温数据：Parquet 文件（最近 7 天）
   - 冷数据：对象存储（历史）

2. **日志采样**:
   - 高频日志自动采样，减少存储压力

3. **结构化日志**:
   - 支持 JSON 格式日志的字段提取和索引

4. **实时流**:
   - WebSocket/SSE 接口支持实时日志流

### 6.4 测试覆盖

当前测试（行 487-1524）覆盖：
- ✅ 独立日志数据库验证
- ✅ 数据库迁移（message → feedback_log_body）
- ✅ 搜索功能
- ✅ 线程分区清理（大小和行数限制）
- ✅ 无线程进程分区清理
- ✅ NULL process_uuid 分区清理
- ✅ 反馈日志查询和排序
- ✅ 反馈日志大小限制
- ✅ 同进程无线程日志包含

建议补充：
- ⬜ 极端并发写入测试
- ⬜ 大分区（100k+ 行）清理性能测试
- ⬜ 数据库损坏恢复测试
- ⬜ 长时间运行稳定性测试

---

## 七、附录

### 7.1 相关常量

```rust
// runtime.rs
const LOG_PARTITION_SIZE_LIMIT_BYTES: i64 = 10 * 1024 * 1024;  // 10 MiB
const LOG_PARTITION_ROW_LIMIT: i64 = 1_000;

// log_db.rs
const LOG_QUEUE_CAPACITY: usize = 512;
const LOG_BATCH_SIZE: usize = 128;
const LOG_FLUSH_INTERVAL: Duration = Duration::from_secs(2);
const LOG_RETENTION_DAYS: i64 = 10;
```

### 7.2 监控指标

| 指标名 | 类型 | 说明 |
|-------|------|------|
| `codex.db.error` | Counter | 数据库错误 |
| `codex.logs.inserted` | Counter | 插入日志条数 |
| `codex.logs.pruned` | Counter | 清理日志条数 |
| `codex.logs.query.duration_ms` | Timer | 查询耗时 |

### 7.3 版本历史

| 版本 | 文件 | 变更 |
|-----|------|------|
| 0002 | `migrations/0002_logs.sql` | 初始表结构 |
| 0003 | `migrations/0003_logs_thread_id.sql` | 添加 thread_id |
| 0010 | `migrations/0010_logs_process_id.sql` | 添加 process_uuid |
| 0011 | `migrations/0011_logs_partition_prune_indexes.sql` | 清理优化索引 |
| 0012 | `migrations/0012_logs_estimated_bytes.sql` | 添加 estimated_bytes |

### 7.4 调用时序图

```
Application
    │
    ▼
┌─────────────────┐
│  tracing event  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────┐
│   log_db.rs     │────►│  mpsc channel   │
│   LogDbLayer    │     │  (buffer 512)   │
└─────────────────┘     └────────┬────────┘
                                 │
                    ┌────────────┼────────────┐
                    ▼            ▼            ▼
              buffer full    interval     flush cmd
              (128 items)    (2s)         (manual)
                    │            │            │
                    └────────────┼────────────┘
                                 ▼
                    ┌─────────────────────────┐
                    │   insert_logs()         │
                    │   - INSERT batch        │
                    │   - prune_logs_*        │
                    │   - COMMIT              │
                    └─────────────────────────┘
                                 │
                                 ▼
                    ┌─────────────────────────┐
                    │    logs.db (SQLite)     │
                    └─────────────────────────┘
```
