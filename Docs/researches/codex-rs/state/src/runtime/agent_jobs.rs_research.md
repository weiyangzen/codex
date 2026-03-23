# Agent Jobs Runtime 研究文档

## 文件信息
- **源文件**: `codex-rs/state/src/runtime/agent_jobs.rs`
- **文件大小**: 19,429 bytes (684 行)
- **所属模块**: `codex-state` crate 的 runtime 子模块

---

## 一、场景与职责

### 1.1 核心定位
`agent_jobs.rs` 是 Codex 状态管理系统的**批处理任务执行引擎**，负责管理基于 CSV 的批量 Agent 任务生命周期。它是 `spawn_agents_on_csv` 工具的后端存储实现，支持将 CSV 文件的每一行作为一个独立的 Agent 任务项进行并行处理。

### 1.2 主要使用场景
1. **批量代码分析**: 对大量文件/模块执行相同的 AI 分析指令
2. **数据批处理**: 基于结构化输入（CSV）生成结构化输出
3. **并行任务调度**: 管理数百至数千个并发 Agent 子任务
4. **结果汇总导出**: 自动将处理结果导出为 CSV 格式

### 1.3 架构位置
```
┌─────────────────────────────────────────────────────────────┐
│                    codex-core                               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  tools/handlers/agent_jobs.rs                         │  │
│  │  - BatchJobHandler (spawn_agents_on_csv)              │  │
│  │  - 任务编排、Worker 管理、结果收集                      │  │
│  └────────────────────┬──────────────────────────────────┘  │
│                       │ 调用 StateRuntime API                │
│                       ▼                                      │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  codex-state                                          │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │ runtime/agent_jobs.rs ◄── 本文件                │  │  │
│  │  │ - Agent Job CRUD 操作                           │  │  │
│  │  │ - Agent Job Item 状态管理                        │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │ model/agent_job.rs                              │  │  │
│  │  │ - 数据结构定义 (AgentJob, AgentJobItem 等)       │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 二、功能点目的

### 2.1 功能概览

| 功能类别 | 方法名 | 目的 |
|---------|--------|------|
| **Job 管理** | `create_agent_job` | 创建新的 Agent Job 及其所有 Items |
| | `get_agent_job` | 查询单个 Job 详情 |
| **Item 管理** | `list_agent_job_items` | 分页查询 Job 的 Items |
| | `get_agent_job_item` | 查询单个 Item 详情 |
| **状态流转** | `mark_agent_job_running` | 标记 Job 为运行中 |
| | `mark_agent_job_completed` | 标记 Job 为已完成 |
| | `mark_agent_job_failed` | 标记 Job 为失败 |
| | `mark_agent_job_cancelled` | 取消 Job（条件性）|
| **Item 状态** | `mark_agent_job_item_running` | 标记 Item 为运行中 |
| | `mark_agent_job_item_running_with_thread` | 标记 Item 运行并关联 Thread |
| | `mark_agent_job_item_pending` | 重置 Item 为待处理（重试）|
| | `mark_agent_job_item_completed` | 标记 Item 为已完成 |
| | `mark_agent_job_item_failed` | 标记 Item 为失败 |
| **结果报告** | `report_agent_job_item_result` | Worker 报告处理结果 |
| **进度查询** | `get_agent_job_progress` | 获取 Job 进度统计 |
| **取消检查** | `is_agent_job_cancelled` | 检查 Job 是否被取消 |

### 2.2 状态机设计

#### Job 状态机
```
                    ┌─────────────┐
                    │   Pending   │
                    └──────┬──────┘
                           │ mark_agent_job_running
                           ▼
                    ┌─────────────┐
           ┌───────│   Running   │──────┐
           │       └──────┬──────┘      │
           │              │             │
           ▼              ▼             ▼
    ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
    │  Completed  │ │   Failed    │ │  Cancelled  │
    └─────────────┘ └─────────────┘ └─────────────┘
```

#### Item 状态机
```
                    ┌─────────────┐
                    │   Pending   │◄──────┐
                    └──────┬──────┘       │
                           │              │ mark_agent_job_item_pending
                           ▼              │ (重试时)
                    ┌─────────────┐       │
           ┌───────│   Running   │───────┘
           │       └──────┬──────┘
           │              │
           ▼              ▼
    ┌─────────────┐ ┌─────────────┐
    │  Completed  │ │   Failed    │
    └─────────────┘ └─────────────┘
```

---

## 三、具体技术实现

### 3.1 数据库 Schema

#### agent_jobs 表
```sql
CREATE TABLE agent_jobs (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    status TEXT NOT NULL,           -- pending/running/completed/failed/cancelled
    instruction TEXT NOT NULL,      -- 任务指令模板
    output_schema_json TEXT,        -- 期望输出 JSON Schema
    input_headers_json TEXT NOT NULL,
    input_csv_path TEXT NOT NULL,
    output_csv_path TEXT NOT NULL,
    auto_export INTEGER NOT NULL DEFAULT 1,
    max_runtime_seconds INTEGER,    -- 单个 Item 超时时间
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    started_at INTEGER,
    completed_at INTEGER,
    last_error TEXT
);
```

#### agent_job_items 表
```sql
CREATE TABLE agent_job_items (
    job_id TEXT NOT NULL,
    item_id TEXT NOT NULL,
    row_index INTEGER NOT NULL,     -- CSV 行号
    source_id TEXT,                 -- 用户指定的 ID 列值
    row_json TEXT NOT NULL,         -- 整行数据 JSON
    status TEXT NOT NULL,           -- pending/running/completed/failed
    assigned_thread_id TEXT,        -- 关联的 Thread ID
    attempt_count INTEGER NOT NULL DEFAULT 0,
    result_json TEXT,               -- Worker 返回结果
    last_error TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    completed_at INTEGER,
    reported_at INTEGER,            -- 结果报告时间
    PRIMARY KEY (job_id, item_id),
    FOREIGN KEY(job_id) REFERENCES agent_jobs(id) ON DELETE CASCADE
);
```

### 3.2 关键数据结构

#### AgentJob (领域模型)
```rust
pub struct AgentJob {
    pub id: String,
    pub name: String,
    pub status: AgentJobStatus,      // Pending/Running/Completed/Failed/Cancelled
    pub instruction: String,         // 指令模板，支持 {column} 占位符
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

#### AgentJobItem (任务项)
```rust
pub struct AgentJobItem {
    pub job_id: String,
    pub item_id: String,
    pub row_index: i64,
    pub source_id: Option<String>,
    pub row_json: Value,             // 行数据对象
    pub status: AgentJobItemStatus,
    pub assigned_thread_id: Option<String>,
    pub attempt_count: i64,          // 重试次数
    pub result_json: Option<Value>,
    pub last_error: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub completed_at: Option<DateTime<Utc>>,
    pub reported_at: Option<DateTime<Utc>>,
}
```

#### AgentJobProgress (进度统计)
```rust
pub struct AgentJobProgress {
    pub total_items: usize,
    pub pending_items: usize,
    pub running_items: usize,
    pub completed_items: usize,
    pub failed_items: usize,
}
```

### 3.3 核心流程实现

#### 3.3.1 创建 Job 流程
```rust
pub async fn create_agent_job(
    &self,
    params: &AgentJobCreateParams,
    items: &[AgentJobItemCreateParams],
) -> anyhow::Result<AgentJob> {
    // 1. 序列化复杂字段
    let input_headers_json = serde_json::to_string(&params.input_headers)?;
    let output_schema_json = params.output_schema_json.as_ref()
        .map(serde_json::to_string).transpose()?;
    
    // 2. 开启事务
    let mut tx = self.pool.begin().await?;
    
    // 3. 插入 agent_jobs 记录
    sqlx::query(...).bind(...).execute(&mut *tx).await?;
    
    // 4. 批量插入 agent_job_items
    for item in items {
        let row_json = serde_json::to_string(&item.row_json)?;
        sqlx::query(...).bind(...).execute(&mut *tx).await?;
    }
    
    // 5. 提交事务
    tx.commit().await?;
    
    // 6. 返回创建的 Job
    self.get_agent_job(job_id).await?
}
```

#### 3.3.2 结果报告流程（关键安全机制）
```rust
pub async fn report_agent_job_item_result(
    &self,
    job_id: &str,
    item_id: &str,
    reporting_thread_id: &str,  // 关键：验证报告来源
    result_json: &Value,
) -> anyhow::Result<bool> {
    // 原子性更新，验证条件：
    // 1. status = Running
    // 2. assigned_thread_id = reporting_thread_id (防止伪造)
    let result = sqlx::query(
        "UPDATE agent_job_items SET 
            status = 'completed',
            result_json = ?,
            reported_at = ?,
            completed_at = ?,
            updated_at = ?,
            last_error = NULL,
            assigned_thread_id = NULL
         WHERE job_id = ? AND item_id = ? 
           AND status = 'running'
           AND assigned_thread_id = ?"  // 关键安全校验
    )
    .bind(serialized)
    .bind(now)
    .bind(job_id)
    .bind(item_id)
    .bind(reporting_thread_id)  // 必须匹配
    .execute(self.pool.as_ref()).await?;
    
    Ok(result.rows_affected() > 0)
}
```

#### 3.3.3 进度统计实现
使用 SQL 聚合查询实时计算进度：
```rust
let row = sqlx::query(
    "SELECT
        COUNT(*) AS total_items,
        SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) AS pending_items,
        SUM(CASE WHEN status = 'running' THEN 1 ELSE 0 END) AS running_items,
        SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed_items,
        SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed_items
     FROM agent_job_items
     WHERE job_id = ?"
)
.bind(job_id)
.fetch_one(self.pool.as_ref()).await?;
```

### 3.4 并发控制机制

1. **乐观锁**: 通过 `rows_affected() > 0` 验证更新是否成功
2. **Thread 绑定**: `assigned_thread_id` 确保只有特定的 Worker 可以报告结果
3. **状态校验**: 所有状态转换都通过 SQL WHERE 条件进行校验
4. **事务隔离**: Job 创建使用事务保证原子性

---

## 四、关键代码路径与文件引用

### 4.1 内部依赖

| 文件路径 | 用途 |
|---------|------|
| `model/agent_job.rs` | 数据结构定义 (AgentJob, AgentJobItem, 状态枚举) |
| `model/mod.rs` | 模块导出 |
| `runtime.rs` | StateRuntime 结构体定义和常量 (LOG_PARTITION_*) |
| `migrations/0014_agent_jobs.sql` | 初始表结构 |
| `migrations/0015_agent_jobs_max_runtime_seconds.sql` | 超时字段迁移 |

### 4.2 外部调用方

| 文件路径 | 调用方式 | 用途 |
|---------|---------|------|
| `core/src/tools/handlers/agent_jobs.rs` | `db.create_agent_job()` | 创建批量任务 |
| | `db.mark_agent_job_running()` | 启动任务 |
| | `db.list_agent_job_items()` | 获取待处理项 |
| | `db.mark_agent_job_item_running_with_thread()` | 分配 Worker |
| | `db.report_agent_job_item_result()` | 收集结果 |
| | `db.mark_agent_job_completed/failed()` | 完成任务 |
| | `db.get_agent_job_progress()` | 进度监控 |
| `core/tests/suite/agent_jobs.rs` | 直接调用 | 集成测试 |

### 4.3 关键代码片段

#### 4.3.1 安全的结果报告（行 425-464）
```rust
pub async fn report_agent_job_item_result(
    &self,
    job_id: &str,
    item_id: &str,
    reporting_thread_id: &str,  // 必须匹配 assigned_thread_id
    result_json: &Value,
) -> anyhow::Result<bool> {
    let now = Utc::now().timestamp();
    let serialized = serde_json::to_string(result_json)?;
    let result = sqlx::query(
        r#"
UPDATE agent_job_items
SET
    status = ?,
    result_json = ?,
    reported_at = ?,
    completed_at = ?,
    updated_at = ?,
    last_error = NULL,
    assigned_thread_id = NULL
WHERE
    job_id = ?
    AND item_id = ?
    AND status = ?
    AND assigned_thread_id = ?  -- 关键安全校验
        "#,
    )
    .bind(AgentJobItemStatus::Completed.as_str())
    .bind(serialized)
    .bind(now)
    .bind(now)
    .bind(now)
    .bind(job_id)
    .bind(item_id)
    .bind(AgentJobItemStatus::Running.as_str())
    .bind(reporting_thread_id)
    .execute(self.pool.as_ref())
    .await?;
    Ok(result.rows_affected() > 0)
}
```

#### 4.3.2 取消操作的条件更新（行 271-294）
```rust
pub async fn mark_agent_job_cancelled(
    &self,
    job_id: &str,
    reason: &str,
) -> anyhow::Result<bool> {
    let now = Utc::now().timestamp();
    let result = sqlx::query(
        r#"
UPDATE agent_jobs
SET status = ?, updated_at = ?, completed_at = ?, last_error = ?
WHERE id = ? AND status IN (?, ?)  -- 只允许取消 Pending/Running
        "#,
    )
    .bind(AgentJobStatus::Cancelled.as_str())
    .bind(now)
    .bind(now)
    .bind(reason)
    .bind(job_id)
    .bind(AgentJobStatus::Pending.as_str())
    .bind(AgentJobStatus::Running.as_str())
    .execute(self.pool.as_ref())
    .await?;
    Ok(result.rows_affected() > 0)
}
```

---

## 五、依赖与外部交互

### 5.1 直接依赖

| 依赖 | 用途 |
|-----|------|
| `sqlx` | SQLite 异步操作 |
| `chrono` | 时间戳处理 |
| `serde_json` | JSON 序列化/反序列化 |
| `anyhow` | 错误处理 |

### 5.2 数据库交互

```
┌─────────────────────────────────────────────────────────────┐
│                      SQLite DB (state.db)                   │
│  ┌─────────────────────┐    ┌─────────────────────────────┐ │
│  │    agent_jobs       │    │      agent_job_items        │ │
│  ├─────────────────────┤    ├─────────────────────────────┤ │
│  │ PK: id              │◄───│ PK: (job_id, item_id)       │ │
│  │ status              │    │ FK: job_id → agent_jobs.id  │ │
│  │ instruction         │    │ status                      │ │
│  │ input_csv_path      │    │ assigned_thread_id          │ │
│  │ output_csv_path     │    │ result_json                 │ │
│  │ max_runtime_seconds │    │ attempt_count               │ │
│  │ created_at          │    │ created_at, completed_at    │ │
│  └─────────────────────┘    └─────────────────────────────┘ │
│                                                             │
│  Index: idx_agent_jobs_status (status, updated_at DESC)     │
│  Index: idx_agent_job_items_status (job_id, status, row_index ASC)│
└─────────────────────────────────────────────────────────────┘
```

### 5.3 与 core 模块的交互

```
codex-core (tools/handlers/agent_jobs.rs)
    │
    ├──► StateRuntime::create_agent_job() ──► SQLite INSERT
    │
    ├──► StateRuntime::mark_agent_job_item_running_with_thread()
    │    └── 分配 Worker Thread
    │
    ├──► Worker (SubAgent) 执行
    │    └── 调用 report_agent_job_result 工具
    │
    ├──► StateRuntime::report_agent_job_item_result()
    │    └── 验证 reporting_thread_id == assigned_thread_id
    │
    └──► StateRuntime::mark_agent_job_completed()
         └── 导出结果 CSV
```

---

## 六、风险、边界与改进建议

### 6.1 已知风险

| 风险类别 | 描述 | 严重程度 |
|---------|------|---------|
| **并发竞争** | 多个 Worker 同时报告同一 Item 时，SQL 条件竞争可能产生不确定性 | 低 |
| **状态不一致** | 如果 core 层崩溃，Running 状态的 Item 可能永远挂起 | 中 |
| **Thread ID 伪造** | 虽然校验了 assigned_thread_id，但依赖 Thread ID 的保密性 | 低 |
| **CSV 注入** | 未对 row_json 内容进行严格校验，可能存在注入风险 | 低 |

### 6.2 边界条件

1. **最大并发**: 由 core 层的 `MAX_AGENT_JOB_CONCURRENCY` (64) 控制
2. **超时处理**: `max_runtime_seconds` 默认 30 分钟，由 core 层强制执行
3. **重试机制**: `attempt_count` 记录重试次数，但无自动重试逻辑
4. **取消语义**: 取消后已运行的 Item 继续执行，仅阻止新 Item 启动

### 6.3 改进建议

#### 6.3.1 短期改进
1. **添加乐观锁版本号**
   ```rust
   // 建议添加 version 字段防止并发更新冲突
   pub async fn mark_agent_job_item_completed_with_version(
       &self,
       job_id: &str,
       item_id: &str,
       expected_version: i64,
   ) -> anyhow::Result<bool>
   ```

2. **增加死 Item 清理机制**
   ```rust
   // 建议添加定期清理长时间 Running 的 Item
   pub async fn cleanup_stale_items(
       &self,
       stale_threshold_seconds: i64,
   ) -> anyhow::Result<u64>
   ```

3. **批量状态更新优化**
   ```rust
   // 当前是逐个更新，建议支持批量完成
   pub async fn mark_agent_job_items_completed_batch(
       &self,
       updates: &[(String, String)], // (job_id, item_id) 列表
   ) -> anyhow::Result<u64>
   ```

#### 6.3.2 长期改进
1. **支持 Job 优先级队列**: 允许高优先级 Job 抢占资源
2. **添加 Job 依赖关系**: 支持 DAG 形式的任务依赖
3. **结果缓存**: 对相同输入的 Item 支持结果复用
4. **分布式执行**: 支持跨进程/跨机器的 Job 分发

### 6.4 测试覆盖

当前测试（行 569-684）覆盖：
- ✅ 结果报告的原子性
- ✅ 延迟报告拒绝（状态已变）
- ✅ 错误 Thread ID 拒绝

建议补充：
- ⬜ 并发报告竞争测试
- ⬜ 大规模 Item (10k+) 性能测试
- ⬜ 取消操作的条件边界测试
- ⬜ 数据库连接断开恢复测试

---

## 七、附录

### 7.1 相关配置项

在 `core/src/config/mod.rs` 中：
```rust
pub struct Config {
    pub agent_job_max_runtime_seconds: Option<u64>,  // 默认超时
    pub agent_max_threads: Option<usize>,            // 最大并发
    pub agent_max_depth: usize,                      // 嵌套深度限制
}
```

### 7.2 监控指标

| 指标名 | 类型 | 说明 |
|-------|------|------|
| `codex.db.error` | Counter | 数据库操作错误 |
| `codex.db.backfill` | Counter | Backfill 统计 |
| `codex.db.backfill.duration_ms` | Timer | Backfill 耗时 |

### 7.3 版本历史

| 版本 | 变更 |
|-----|------|
| 0014_agent_jobs.sql | 初始表结构 |
| 0015_agent_jobs_max_runtime_seconds.sql | 添加超时字段 |
