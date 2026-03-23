# migrations.rs 深度研究文档

## 场景与职责

`migrations.rs` 是 `codex-state` crate 中负责数据库迁移的最小化模块。它使用 `sqlx` 的迁移系统来管理 SQLite 数据库的模式演进。该模块定义了两个独立的迁移器（Migrator），分别用于状态数据库和日志数据库。

### 核心职责

1. **迁移器定义**：为状态数据库和日志数据库定义静态迁移器
2. **迁移文件引用**：引用嵌入在 crate 中的 SQL 迁移文件
3. **模式版本控制**：通过文件系统约定管理数据库模式版本

## 功能点目的

### 1. 状态数据库迁移器

```rust
pub(crate) static STATE_MIGRATOR: Migrator = sqlx::migrate!("./migrations");
```

**作用**：
- 管理 `state_{version}.sqlite` 数据库的模式
- 从 `./migrations` 目录加载迁移文件
- 当前版本：`STATE_DB_VERSION = 5`

### 2. 日志数据库迁移器

```rust
pub(crate) static LOGS_MIGRATOR: Migrator = sqlx::migrate!("./logs_migrations");
```

**作用**：
- 管理 `logs_{version}.sqlite` 数据库的模式
- 从 `./logs_migrations` 目录加载迁移文件
- 当前版本：`LOGS_DB_VERSION = 1`

## 具体技术实现

### sqlx 迁移系统

`sqlx::migrate!` 是一个编译时宏，它会：
1. 扫描指定目录下的 `.sql` 文件
2. 按文件名排序（通常使用 `0001_`, `0002_` 前缀）
3. 将 SQL 内容嵌入到二进制中
4. 创建 `Migrator` 结构，包含所有迁移

### 迁移文件命名约定

```
migrations/
├── 0001_threads.sql
├── 0002_logs.sql
├── 0003_logs_thread_id.sql
├── 0004_thread_dynamic_tools.sql
├── 0005_threads_cli_version.sql
├── 0006_memories.sql
├── 0007_threads_first_user_message.sql
├── 0008_backfill_state.sql
├── 0009_stage1_outputs_rollout_slug.sql
├── 0010_logs_process_id.sql
├── 0011_logs_partition_prune_indexes.sql
├── 0012_logs_estimated_bytes.sql
├── 0013_threads_agent_nickname.sql
├── 0014_agent_jobs.sql
├── 0015_agent_jobs_max_runtime_seconds.sql
├── 0016_memory_usage.sql
├── 0017_phase2_selection_flag.sql
├── 0018_phase2_selection_snapshot.sql
├── 0019_thread_dynamic_tools_defer_loading.sql
└── 0020_threads_model_reasoning_effort.sql

logs_migrations/
├── 0001_logs.sql
└── 0002_logs_feedback_log_body.sql
```

### 迁移执行流程

```
StateRuntime::init()
    │
    ├──► open_sqlite(state_path, &STATE_MIGRATOR)
    │       │
    │       ├──► SqlitePool::connect_with(options)
    │       │
    │       └──► STATE_MIGRATOR.run(&pool)
    │               │
    │               ├──► 创建 __migrations 表（如不存在）
    │               ├──► 检查已应用迁移
    │               ├──► 执行未应用的迁移
    │               └──► 记录迁移版本
    │
    └──► open_sqlite(logs_path, &LOGS_MIGRATOR)
            └──► （同上流程）
```

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `runtime.rs` | 使用 `STATE_MIGRATOR` 和 `LOGS_MIGRATOR` |
| `../migrations/*.sql` | 状态数据库迁移文件 |
| `../logs_migrations/*.sql` | 日志数据库迁移文件 |

### 外部依赖

| Crate | 模块/类型 | 用途 |
|-------|----------|------|
| `sqlx` | `migrate::Migrator` | 迁移基础设施 |

### 迁移文件位置

```
codex-rs/state/
├── src/
│   └── migrations.rs      # 本文件
├── migrations/            # 状态数据库迁移
│   ├── 0001_threads.sql
│   ├── ...
│   └── 0020_threads_model_reasoning_effort.sql
└── logs_migrations/       # 日志数据库迁移
    ├── 0001_logs.sql
    └── 0002_logs_feedback_log_body.sql
```

## 依赖与外部交互

### 上游调用方

1. **runtime.rs**：`open_sqlite` 函数调用 `migrator.run(&pool)`

### 下游依赖

无直接下游依赖，迁移器由 sqlx 管理。

### 迁移文件内容示例

#### 0001_threads.sql（初始表结构）

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
    has_user_event INTEGER NOT NULL DEFAULT 0,
    archived INTEGER NOT NULL DEFAULT 0,
    archived_at INTEGER,
    git_sha TEXT,
    git_branch TEXT,
    git_origin_url TEXT
);

CREATE INDEX idx_threads_created_at ON threads(created_at DESC, id DESC);
CREATE INDEX idx_threads_updated_at ON threads(updated_at DESC, id DESC);
CREATE INDEX idx_threads_archived ON threads(archived);
CREATE INDEX idx_threads_source ON threads(source);
CREATE INDEX idx_threads_provider ON threads(model_provider);
```

#### 0002_logs_feedback_log_body.sql（列重命名迁移）

```sql
ALTER TABLE logs RENAME TO logs_old;

CREATE TABLE logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts INTEGER NOT NULL,
    ts_nanos INTEGER NOT NULL,
    level TEXT NOT NULL,
    target TEXT NOT NULL,
    feedback_log_body TEXT,  -- 从 message 重命名
    module_path TEXT,
    file TEXT,
    line INTEGER,
    thread_id TEXT,
    process_uuid TEXT,
    estimated_bytes INTEGER NOT NULL DEFAULT 0
);

-- 数据迁移
INSERT INTO logs (...)
SELECT ... FROM logs_old;

DROP TABLE logs_old;

-- 重建索引
CREATE INDEX ...
```

## 风险、边界与改进建议

### 潜在风险

1. **迁移文件缺失**：如果迁移文件在编译后删除，已编译的二进制仍能工作（内容已嵌入），但重新编译会失败
2. **版本号不匹配**：`STATE_DB_VERSION` 常量与迁移文件数量可能不同步
3. **破坏性迁移**：某些迁移（如列重命名）需要重建表，大数据量时可能很慢

### 边界情况

1. **并发迁移**：多个进程同时启动时，SQLite 的 WAL 模式可以防止冲突
2. **中断恢复**：迁移过程中断后，下次启动会检测到部分应用状态
3. **降级不支持**：sqlx 迁移不支持自动降级

### 改进建议

1. **版本同步检查**：
   - 添加编译时断言验证迁移文件数量与版本常量匹配
   - 或在运行时检查并警告

2. **迁移文档**：
   - 为每个迁移文件添加头部注释说明变更原因
   - 维护 CHANGELOG

3. **测试策略**：
   - 添加迁移测试：从空数据库到最新版本
   - 添加数据完整性测试

4. **性能优化**：
   - 对于大数据量迁移，考虑分批处理
   - 添加进度日志

5. **监控**：
   - 记录迁移执行时间
   - 导出迁移状态指标

### 代码质量评估

- **简洁性**：★★★★★ - 极简设计，职责单一
- **可维护性**：★★★★☆ - 依赖文件系统约定，需要文档说明
- **可靠性**：★★★★☆ - 依赖 sqlx 的成熟迁移系统

### 相关常量（来自 lib.rs）

```rust
pub const STATE_DB_VERSION: u32 = 5;
pub const LOGS_DB_VERSION: u32 = 1;
```

注意：当前有 20 个状态迁移文件，但版本号是 5，这是因为版本号用于数据库文件命名（`state_5.sqlite`），而非迁移计数。
