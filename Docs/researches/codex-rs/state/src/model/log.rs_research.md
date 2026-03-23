# log.rs 研究文档

## 场景与职责

`log.rs` 是 Codex 状态管理模块中负责**日志数据模型定义**的核心文件。它定义了日志条目（LogEntry）、日志行（LogRow）和日志查询（LogQuery）的数据结构，为整个系统的日志持久化和查询提供基础。

### 核心职责
1. **日志条目定义**：定义内存中的日志条目结构，支持 tracing 框架集成
2. **日志查询接口**：提供灵活的日志查询参数结构
3. **数据库映射**：定义数据库行结构与领域模型的映射关系

### 业务背景
Codex 需要持久化运行日志以支持：
- 故障排查和调试
- 用户反馈日志（feedback logs）收集
- 按线程/进程分区的日志检索
- 日志保留和自动清理

## 功能点目的

### 1. LogEntry - 日志条目（写模型）

```rust
#[derive(Clone, Debug, Serialize)]
pub struct LogEntry {
    pub ts: i64,                       // Unix 时间戳（秒）
    pub ts_nanos: i64,                 // 纳秒部分
    pub level: String,                 // 日志级别（TRACE/DEBUG/INFO/WARN/ERROR）
    pub target: String,                // 日志目标模块
    pub message: Option<String>,       // 原始消息（向后兼容）
    pub feedback_log_body: Option<String>, // 反馈日志体（主要字段）
    pub thread_id: Option<String>,     // 关联的线程 ID
    pub process_uuid: Option<String>,  // 进程 UUID
    pub module_path: Option<String>,   // 模块路径
    pub file: Option<String>,          // 源文件
    pub line: Option<i64>,             // 行号
}
```

**设计要点**：
- `message` 和 `feedback_log_body` 同时存在是为了向后兼容
- 新代码应优先使用 `feedback_log_body`
- `thread_id` 用于将日志关联到特定对话线程
- `process_uuid` 用于区分不同进程实例的无线程日志

### 2. LogRow - 日志行（读模型）

```rust
#[derive(Clone, Debug, FromRow)]
pub struct LogRow {
    pub id: i64,                       // 自增 ID
    pub ts: i64,
    pub ts_nanos: i64,
    pub level: String,
    pub target: String,
    pub message: Option<String>,       // 查询时映射 feedback_log_body
    pub thread_id: Option<String>,
    pub process_uuid: Option<String>,
    pub file: Option<String>,
    pub line: Option<i64>,
}
```

**与 LogEntry 的区别**：
- 包含数据库自增 `id` 字段
- 不包含 `module_path` 和 `feedback_log_body`
- `message` 字段在查询时通过 SQL 映射 `feedback_log_body`

### 3. LogQuery - 日志查询参数

```rust
#[derive(Clone, Debug, Default)]
pub struct LogQuery {
    pub level_upper: Option<String>,   // 精确匹配日志级别
    pub from_ts: Option<i64>,          // 开始时间戳
    pub to_ts: Option<i64>,            // 结束时间戳
    pub module_like: Vec<String>,      // 模块路径模糊匹配（LIKE）
    pub file_like: Vec<String>,        // 文件路径模糊匹配（LIKE）
    pub thread_ids: Vec<String>,       // 线程 ID 列表（OR 条件）
    pub search: Option<String>,        // 消息内容搜索（INSTR）
    pub include_threadless: bool,      // 是否包含无线程日志
    pub after_id: Option<i64>,         // ID 游标（用于分页）
    pub limit: Option<usize>,          // 结果限制
    pub descending: bool,              // 是否降序（最新在前）
}
```

**查询能力**：
- 时间范围过滤
- 日志级别过滤
- 模块/文件路径模糊匹配
- 多线程筛选（支持同时查询多个线程）
- 内容全文搜索（子串匹配）
- 分页支持（基于自增 ID）

## 具体技术实现

### 数据库 Schema 演进

**初始版本** (`0002_logs.sql`):
```sql
CREATE TABLE logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts INTEGER NOT NULL,
    ts_nanos INTEGER NOT NULL,
    level TEXT NOT NULL,
    target TEXT NOT NULL,
    message TEXT,
    module_path TEXT,
    file TEXT,
    line INTEGER,
    thread_id TEXT,
    process_uuid TEXT
);
```

**当前版本** (`0012_logs_estimated_bytes.sql`):
```sql
-- 新增 estimated_bytes 用于分区大小限制
ALTER TABLE logs ADD COLUMN estimated_bytes INTEGER NOT NULL DEFAULT 0;

-- 新增 feedback_log_body 替代 message
ALTER TABLE logs ADD COLUMN feedback_log_body TEXT;

-- 索引优化
CREATE INDEX idx_logs_thread_id ON logs(thread_id);
CREATE INDEX idx_logs_thread_id_ts ON logs(thread_id, ts);
CREATE INDEX idx_logs_ts ON logs(ts);
CREATE INDEX idx_logs_process_uuid_threadless_ts 
    ON logs(process_uuid, ts) WHERE thread_id IS NULL;
```

### 分区大小限制

日志系统实现了**按分区保留策略**：
- 每个 `thread_id` 一个分区
- 每个 `process_uuid`（无线程日志）一个分区
- 每个分区限制：10 MiB 或 1000 条记录

```rust
// runtime.rs 中的常量
const LOG_PARTITION_SIZE_LIMIT_BYTES: i64 = 10 * 1024 * 1024;  // 10 MiB
const LOG_PARTITION_ROW_LIMIT: i64 = 1_000;
```

### 日志插入与修剪流程

```rust
pub async fn insert_logs(&self, entries: &[LogEntry]) -> anyhow::Result<()> {
    // 1. 开始事务
    let mut tx = self.logs_pool.begin().await?;
    
    // 2. 批量插入
    let mut builder = QueryBuilder::<Sqlite>::new(
        "INSERT INTO logs (ts, ts_nanos, level, target, feedback_log_body, ..."
    );
    builder.push_values(entries, |mut row, entry| {
        // 计算 estimated_bytes
        let estimated_bytes = feedback_log_body.map_or(0, String::len) as i64
            + entry.level.len() as i64
            + ...;
        row.push_bind(entry.ts)
            .push_bind(entry.ts_nanos)
            ...
            .push_bind(estimated_bytes);
    });
    builder.build().execute(&mut *tx).await?;
    
    // 3. 修剪超量分区（同一事务内）
    self.prune_logs_after_insert(entries, &mut tx).await?;
    
    // 4. 提交事务
    tx.commit().await?;
    Ok(())
}
```

## 关键代码路径与文件引用

### 模型定义位置
- **文件**：`codex-rs/state/src/model/log.rs`（本文件）
- **导出**：`codex-rs/state/src/model/mod.rs` 通过 `pub use log::*` 导出

### 数据库操作实现
- **文件**：`codex-rs/state/src/runtime/logs.rs`
- **核心方法**：
  - `insert_log()` / `insert_logs()` - 插入日志
  - `query_logs()` - 通用日志查询
  - `query_feedback_logs()` - 查询反馈日志（按线程聚合）
  - `max_log_id()` - 获取最大日志 ID（用于分页）
  - `delete_logs_before()` - 按时间清理日志
  - `prune_logs_after_insert()` - 分区修剪（私有）

### Tracing 集成
- **文件**：`codex-rs/state/src/log_db.rs`
- **功能**：实现 `tracing_subscriber::Layer` trait
- **核心结构**：
  - `LogDbLayer` - tracing layer 实现
  - `SpanLogContext` - span 级别的日志上下文
  - `run_inserter()` - 后台批量插入任务
  - `run_retention_cleanup()` - 后台清理任务

### 调用方
- **TUI 聊天组件**：`codex-rs/tui/src/chatwidget.rs` - 查询并显示日志
- **TUI App Server**：`codex-rs/tui_app_server/src/chatwidget.rs` - 服务端日志查询
- **Git 信息模块**：`codex-rs/core/src/git_info.rs` - 记录 Git 操作日志

### 测试
- **单元测试**：`codex-rs/state/src/runtime/logs.rs` 底部包含测试模块
- **集成测试**：`codex-rs/core/tests/suite/sqlite_state.rs`
- **TUI 测试**：`codex-rs/tui/src/chatwidget/tests.rs`

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `serde::Serialize` | LogEntry 序列化（用于 tracing 集成） |
| `sqlx::FromRow` | LogRow 数据库行映射 |

### 内部模块交互
```
log.rs (模型定义)
    ↓
mod.rs (统一导出)
    ↓
runtime/logs.rs (数据库操作)
    ↓
log_db.rs (tracing Layer 实现)
    ↓
lib.rs (公开 API)
```

## 风险、边界与改进建议

### 风险点

1. **数据库分离**
   - 日志使用独立的 SQLite 文件（`logs_{version}.sqlite`）
   - **风险**：状态数据库和日志数据库可能不一致
   - **缓解**：日志是辅助信息，不影响核心功能

2. **分区修剪竞争**
   - 修剪逻辑在事务内执行，但高并发插入可能导致瞬时分区超限
   - **缓解**：修剪与插入同一事务，确保原子性

3. **全文搜索性能**
   - `search` 使用 `INSTR()` 函数，是线性扫描
   - **风险**：大表时查询性能下降
   - **缓解**：限制查询时间范围，使用索引过滤先缩小范围

### 边界情况

1. **超大日志条目**
   - 单条日志超过 10 MiB 时，插入后会被立即修剪
   - **行为**：该分区只保留这一条（如果它自己 > 10 MiB）或为空

2. **无线程日志**
   - `thread_id IS NULL` 的日志按 `process_uuid` 分区
   - 如果 `process_uuid` 也为 NULL，归入特殊分区

3. **时间戳精度**
   - 秒级时间戳 + 纳秒偏移，足够排序但非真正纳秒精度

### 改进建议

1. **FTS 全文搜索**
   - 当前使用 `INSTR()` 进行子串搜索
   - 建议：使用 SQLite FTS5 扩展实现高效全文搜索

2. **结构化日志字段**
   - 当前 `feedback_log_body` 是纯文本
   - 建议：增加 JSON 字段存储结构化日志数据，便于过滤和聚合

3. **日志级别索引**
   - 当前没有专门针对 level 的索引
   - 建议：如果频繁按级别查询，增加 `(level, ts)` 索引

4. **批量插入优化**
   - 当前批量大小固定为 128
   - 建议：根据负载动态调整批量大小

5. **日志压缩**
   - 历史日志可以压缩存储
   - 建议：对超过一定时间的日志进行压缩

### 代码质量

1. **字段冗余**
   - `message` 和 `feedback_log_body` 同时存在
   - 建议：迁移完成后移除 `message` 字段

2. **时间戳类型**
   - 使用 `i64` 存储时间戳，需要手动转换
   - 建议：考虑使用 `chrono::DateTime<Utc>` 配合 sqlx 的类型支持
