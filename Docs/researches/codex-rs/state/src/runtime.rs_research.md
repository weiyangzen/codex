# runtime.rs 深度研究文档

## 场景与职责

`runtime.rs` 是 `codex-state` crate 的核心模块，定义了 `StateRuntime` 结构体——这是与 SQLite 状态数据库交互的主要入口点。该模块负责数据库连接管理、迁移执行、以及提供各种状态操作的高层 API。

### 架构定位

```
┌─────────────────────────────────────────────────────────────┐
│                      StateRuntime                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                    核心字段                           │  │
│  │  • codex_home: PathBuf        # Codex 主目录         │  │
│  │  • default_provider: String   # 默认模型提供者       │  │
│  │  • pool: Arc<SqlitePool>      # 状态数据库连接池     │  │
│  │  • logs_pool: Arc<SqlitePool> # 日志数据库连接池     │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                    子模块 API                         │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ │  │
│  │  │ threads  │ │   logs   │ │ memories │ │backfill  │ │  │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘ │  │
│  │  ┌──────────┐ ┌──────────┐                           │  │
│  │  │agent_jobs│ │test_supp │                           │  │
│  │  └──────────┘ └──────────┘                           │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 核心职责

1. **数据库生命周期管理**：初始化、连接池配置、迁移执行
2. **双数据库架构**：管理状态数据库和日志数据库两个独立的 SQLite 实例
3. **遗留文件清理**：自动清理旧版本的数据库文件
4. **配置暴露**：提供数据库路径和文件名生成函数

## 功能点目的

### 1. `StateRuntime` 结构体

```rust
#[derive(Clone)]
pub struct StateRuntime {
    codex_home: PathBuf,
    default_provider: String,
    pool: Arc<sqlx::SqlitePool>,
    logs_pool: Arc<sqlx::SqlitePool>,
}
```

**设计决策**：
- 使用 `Arc` 包装连接池，允许多个组件共享同一个运行时
- 分离状态池和日志池，减少锁竞争
- 存储 `default_provider` 用于元数据构建时的默认值

### 2. `StateRuntime::init` - 初始化

```rust
pub async fn init(codex_home: PathBuf, default_provider: String) -> anyhow::Result<Arc<Self>>
```

**初始化流程**：
```
1. 创建 codex_home 目录
2. 生成当前数据库文件名（state_5.sqlite, logs_1.sqlite）
3. 清理遗留数据库文件
4. 打开状态数据库（执行迁移）
5. 打开日志数据库（执行迁移）
6. 返回 Arc<StateRuntime>
```

### 3. `open_sqlite` - 数据库连接

```rust
async fn open_sqlite(path: &Path, migrator: &'static Migrator) -> anyhow::Result<SqlitePool>
```

**连接配置**：
```rust
let options = SqliteConnectOptions::new()
    .filename(path)
    .create_if_missing(true)
    .journal_mode(SqliteJournalMode::Wal)      // WAL 模式
    .synchronous(SqliteSynchronous::Normal)    // 同步模式
    .busy_timeout(Duration::from_secs(5))       // 忙等待超时
    .log_statements(LevelFilter::Off);          // 关闭 SQL 日志

let pool = SqlitePoolOptions::new()
    .max_connections(5)                        // 最大连接数
    .connect_with(options)
    .await?;

migrator.run(&pool).await?;  // 执行迁移
```

**关键配置说明**：
- **WAL 模式**：提高并发性能，允许多读者单写者
- **5 秒忙等待**：避免立即返回锁定错误
- **5 连接限制**：SQLite 的推荐设置

### 4. 数据库文件名生成

```rust
pub fn state_db_filename() -> String   // "state_5.sqlite"
pub fn logs_db_filename() -> String    // "logs_1.sqlite"
pub fn state_db_path(codex_home: &Path) -> PathBuf
pub fn logs_db_path(codex_home: &Path) -> PathBuf
```

**命名规则**：`{base_name}_{version}.sqlite`
- 版本号来自 `lib.rs` 中的常量
- 允许并行存在多个版本的数据库文件

### 5. 遗留文件清理

```rust
async fn remove_legacy_db_files(
    codex_home: &Path,
    current_name: &str,
    base_name: &str,
    db_label: &str,
)
```

**清理策略**：
```
对于 codex_home 中的每个文件：
    如果不是文件 → 跳过
    如果文件名匹配当前版本 → 跳过
    如果文件名匹配旧版本模式 → 删除
    包括相关的 -wal, -shm, -journal 文件
```

**旧版本模式**：
- `state.sqlite`（无版本号）
- `state_{n}.sqlite`（n < 当前版本）

### 6. 日志分区限制常量

```rust
const LOG_PARTITION_SIZE_LIMIT_BYTES: i64 = 10 * 1024 * 1024;  // 10 MiB
const LOG_PARTITION_ROW_LIMIT: i64 = 1_000;
```

**分区定义**：
- 每个非空 thread_id 一个分区
- 每个 threadless + 非空 process_uuid 一个分区
- threadless + process_uuid IS NULL 一个分区

## 具体技术实现

### 文件结构

```rust
// runtime.rs 主模块
mod agent_jobs;    // Agent 作业操作
mod backfill;      // 回填操作
mod logs;          // 日志操作
mod memories;      // 记忆操作
#[cfg(test)]
mod test_support;  // 测试支持
mod threads;       // 线程操作
```

### 子模块实现模式

每个子模块使用 `impl StateRuntime` 块扩展主结构体：

```rust
// runtime/threads.rs
use super::*;

impl StateRuntime {
    pub async fn get_thread(&self, id: ThreadId) -> anyhow::Result<Option<ThreadMetadata>> { ... }
    pub async fn list_threads(&self, ...) -> anyhow::Result<ThreadsPage> { ... }
    pub async fn upsert_thread(&self, metadata: &ThreadMetadata) -> anyhow::Result<()> { ... }
    // ...
}
```

### 错误处理策略

- 使用 `anyhow::Result` 统一错误类型
- 数据库错误通过 `warn!` 记录
- 关键错误（如数据库打开失败）返回 Err

## 关键代码路径与文件引用

### 内部模块结构

```
runtime/
├── mod.rs              # 本文件 - StateRuntime 定义和初始化
├── agent_jobs.rs       # 684 lines - Agent 作业 CRUD 和状态管理
├── backfill.rs         # 311 lines - 回填状态管理
├── logs.rs             # 1000+ lines - 日志插入、查询、修剪
├── memories.rs         # 1000+ lines - 记忆 stage1/stage2 作业管理
├── test_support.rs     # 68 lines - 测试辅助函数
└── threads.rs          # 1000+ lines - 线程元数据操作
```

### 依赖关系

```
runtime.rs (核心)
    ├──► migrations.rs (迁移器)
    ├──► model/* (数据模型)
    │       ├── agent_job.rs
    │       ├── backfill_state.rs
    │       ├── log.rs
    │       ├── memories.rs
    │       └── thread_metadata.rs
    └──► paths.rs (文件时间工具)

子模块:
    threads.rs ──► extract.rs (元数据提取)
    logs.rs ──► log_db.rs (日志模型)
    memories.rs ──► 复杂 SQL 查询
    agent_jobs.rs ──► 事务管理
    backfill.rs ──► 简单的状态表操作
```

### 外部依赖

| Crate | 用途 |
|-------|------|
| `sqlx` | SQLite 异步操作、迁移 |
| `tokio` | 异步文件操作、时间 |
| `chrono` | 时间处理 |
| `codex-protocol` | ThreadId, DynamicToolSpec, RolloutItem |
| `serde_json` | JSON 处理 |
| `tracing` | 日志记录 |

## 依赖与外部交互

### 上游调用方

1. **codex-core**：主要的调用方，创建 StateRuntime 实例
2. **log_db.rs**：使用 StateRuntime 进行日志持久化
3. **测试代码**：使用 `StateRuntime::init` 创建测试数据库

### 下游被调用方

1. **migrations.rs**：`STATE_MIGRATOR`, `LOGS_MIGRATOR`
2. **model/***：各种数据模型
3. **extract.rs**：元数据提取函数

### 初始化示例

```rust
use codex_state::StateRuntime;

let codex_home = dirs::data_dir().unwrap().join("codex");
let runtime = StateRuntime::init(codex_home, "openai".to_string()).await?;

// 使用 runtime 进行操作
let thread = runtime.get_thread(thread_id).await?;
```

## 风险、边界与改进建议

### 潜在风险

1. **单点故障**：StateRuntime 是状态管理的中心，崩溃会影响所有状态操作
2. **连接池耗尽**：5 个连接在极端并发下可能不足
3. **迁移失败**：数据库迁移失败会导致整个初始化失败
4. **遗留文件清理**：可能误删其他组件需要的文件

### 边界情况

1. **并发初始化**：多个进程同时初始化可能竞争创建目录
2. **磁盘满**：数据库写入可能因磁盘满而失败
3. **权限问题**：目录创建或文件写入可能因权限失败
4. **损坏的数据库**：SQLite 文件损坏可能导致未定义行为

### 改进建议

1. **连接池配置**：
   ```rust
   // 使连接数可配置
   pub async fn init_with_options(
       codex_home: PathBuf,
       default_provider: String,
       max_connections: u32,
   ) -> anyhow::Result<Arc<Self>>
   ```

2. **健康检查**：
   ```rust
   pub async fn health_check(&self) -> anyhow::Result<()>
   ```

3. **指标导出**：
   - 连接池使用率
   - 查询延迟直方图
   - 错误率

4. **优雅关闭**：
   ```rust
   pub async fn shutdown(self) -> anyhow::Result<()>
   ```

5. **备份支持**：
   ```rust
   pub async fn backup(&self, path: &Path) -> anyhow::Result<()>
   ```

6. **测试增强**：
   - 并发测试
   - 故障注入测试
   - 大容量数据测试

### 代码质量评估

- **模块化**：★★★★★ - 清晰的子模块划分
- **可维护性**：★★★★☆ - 结构清晰，但部分函数过长
- **错误处理**：★★★★☆ - 使用 anyhow，但部分错误信息可优化
- **测试覆盖**：★★★★☆ - 子模块有测试，但主模块测试较少

### 关键测试

1. **backfill.rs 测试**：
   - `init_removes_legacy_state_db_files`：验证遗留文件清理
   - `backfill_state_persists_progress_and_completion`：验证回填状态
   - `backfill_claim_is_singleton_until_stale_and_blocked_when_complete`：验证回填锁

2. **logs.rs 测试**：
   - `insert_logs_use_dedicated_log_database`：验证双数据库架构
   - `insert_logs_prunes_*`：验证日志修剪逻辑

3. **threads.rs 测试**：
   - `upsert_thread_keeps_creation_memory_mode_for_existing_rows`
   - `apply_rollout_items_restores_memory_mode_from_session_meta`

### 性能考虑

1. **WAL 模式**：适合读多写少的场景
2. **批量操作**：logs.rs 中的批量插入优化
3. **索引策略**：迁移文件中定义的索引覆盖主要查询模式
4. **分区修剪**：日志按 thread_id/process_uuid 分区并自动修剪
