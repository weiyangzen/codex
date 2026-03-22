# codex-rs/state 深度研究文档

## 1. 场景与职责

### 1.1 定位
`codex-state` 是 Codex CLI 的 **SQLite-backed 状态管理 crate**，负责将 rollout 元数据、日志、Agent Job 状态等持久化到本地 SQLite 数据库。它是整个 Codex 系统的"记忆中枢"，为 TUI、CLI、App Server 提供统一的状态访问接口。

### 1.2 核心场景

| 场景 | 说明 |
|------|------|
| **Thread 元数据管理** | 从 JSONL rollout 文件提取并缓存 thread 元数据（标题、模型、token 使用量等） |
| **日志持久化** | 通过 tracing layer 收集日志，写入独立 SQLite 数据库，支持查询和反馈日志生成 |
| **Agent Job 执行** | 管理批量 Agent Job 的创建、状态跟踪、进度查询 |
| **Memory 系统** | Stage-1 记忆提取任务调度、全局 Phase-2 记忆整合任务管理 |
| **Backfill 迁移** | 历史 rollout 文件的元数据回填，支持增量 checkpoint |

### 1.3 架构位置

```
┌─────────────────────────────────────────────────────────────┐
│                     Codex CLI / TUI / App Server            │
├─────────────────────────────────────────────────────────────┤
│  codex-core  │  codex-tui  │  codex-app-server              │
├─────────────────────────────────────────────────────────────┤
│                    codex-state (SQLite)                     │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐   │
│  │  state.sqlite │  │  logs.sqlite │  │  migrations/    │   │
│  │  (threads,    │  │  (log entries)│  │  (20+ migrations)│  │
│  │   jobs,       │  │              │  │                 │   │
│  │   stage1_out) │  │              │  │                 │   │
│  └──────────────┘  └──────────────┘  └─────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 Thread 元数据管理 (`runtime/threads.rs`)

**目的**：避免每次启动时扫描所有 JSONL rollout 文件，通过 SQLite 缓存实现 O(1) 的 thread 查询。

**关键功能**：
- `get_thread()` - 按 ID 查询 thread 元数据
- `list_threads()` - 分页列出 threads，支持排序（CreatedAt/UpdatedAt）、搜索、归档过滤
- `upsert_thread()` - 插入或更新 thread 元数据
- `apply_rollout_items()` - 从 rollout items 增量更新元数据
- `persist_dynamic_tools()` - 存储线程级别的动态工具定义

### 2.2 日志系统 (`runtime/logs.rs`, `log_db.rs`)

**目的**：将 tracing 日志持久化到 SQLite，支持：
- 按 thread_id / process_uuid / 时间范围查询
- 自动日志裁剪（每 partition 10MiB 上限）
- 反馈日志生成（用于 LLM 上下文）

**关键设计**：
- 独立 `logs.sqlite` 数据库，避免与状态数据竞争锁
- 分区裁剪策略：thread 日志按 thread_id 分区，threadless 日志按 process_uuid 分区
- 使用 SQL window function 实现精确的累积字节裁剪

### 2.3 Agent Job 管理 (`runtime/agent_jobs.rs`)

**目的**：支持批量任务执行（如批量代码审查），跟踪每个 job item 的状态。

**状态机**：
```
Job: Pending -> Running -> Completed/Failed/Cancelled
Item: Pending -> Running -> Completed/Failed
```

### 2.4 Memory 系统 (`runtime/memories.rs`)

**目的**：实现两阶段记忆提取 pipeline：

**Stage-1**：从单个 thread 的 rollout 提取原始记忆
- `try_claim_stage1_job()` - 竞争式任务认领（支持 lease 机制、重试退避）
- `mark_stage1_job_succeeded()` - 保存提取的记忆到 `stage1_outputs` 表

**Phase-2**：全局记忆整合
- `try_claim_global_phase2_job()` - 全局任务认领
- `get_phase2_input_selection()` - 获取当前应整合的记忆集合
- `mark_global_phase2_job_succeeded()` - 更新整合基线

### 2.5 Backfill 系统 (`runtime/backfill.rs`)

**目的**：首次启动时将历史 rollout 文件元数据回填到 SQLite。

**状态机**：
```
Pending -> Running (claim) -> Complete (with watermark)
```

---

## 3. 具体技术实现

### 3.1 数据库架构

**State DB (`state_{VERSION}.sqlite`)**：

| 表 | 用途 |
|----|------|
| `threads` | Thread 元数据（20+ 字段） |
| `thread_dynamic_tools` | 每线程动态工具定义（JSON Schema） |
| `stage1_outputs` | Stage-1 记忆提取结果 |
| `jobs` | 通用任务队列（Stage-1 + Phase-2） |
| `agent_jobs` / `agent_job_items` | Agent Job 管理 |
| `backfill_state` | Backfill 进度跟踪 |

**Logs DB (`logs_{VERSION}.sqlite`)**：

| 表 | 用途 |
|----|------|
| `logs` | 日志条目（带 estimated_bytes 用于裁剪） |

### 3.2 关键数据结构

```rust
// Thread 元数据（内存表示）
pub struct ThreadMetadata {
    pub id: ThreadId,
    pub rollout_path: PathBuf,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub source: String,           // "cli" | "vscode" | ...
    pub model_provider: String,
    pub model: Option<String>,
    pub reasoning_effort: Option<ReasoningEffort>,
    pub cwd: PathBuf,
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

// Stage-1 记忆输出
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

// Agent Job
pub struct AgentJob {
    pub id: String,
    pub name: String,
    pub status: AgentJobStatus,  // Pending/Running/Completed/Failed/Cancelled
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

#### 3.3.1 Thread 元数据提取流程 (`extract.rs`)

```rust
// 从 RolloutItem 提取元数据
pub fn apply_rollout_item(
    metadata: &mut ThreadMetadata,
    item: &RolloutItem,
    default_provider: &str,
) {
    match item {
        RolloutItem::SessionMeta(meta) => apply_session_meta(metadata, meta),
        RolloutItem::TurnContext(ctx) => apply_turn_context(metadata, ctx),
        RolloutItem::EventMsg(EventMsg::TokenCount(tc)) => update_tokens(metadata, tc),
        RolloutItem::EventMsg(EventMsg::UserMessage(um)) => update_title(metadata, um),
        // ...
    }
}
```

**关键规则**：
- SessionMeta 提供基础信息（agent_nickname, model_provider, git 信息）
- TurnContext 提供运行时配置（model, reasoning_effort, sandbox_policy）
- UserMessage 事件用于生成 thread 标题（取第一条用户消息）

#### 3.3.2 日志裁剪流程

```rust
// 每 partition 限制：10 MiB 或 1000 行
const LOG_PARTITION_SIZE_LIMIT_BYTES: i64 = 10 * 1024 * 1024;
const LOG_PARTITION_ROW_LIMIT: i64 = 1_000;

// 使用 SQL window function 裁剪
DELETE FROM logs
WHERE id IN (
    SELECT id FROM (
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

#### 3.3.3 Stage-1 Job 认领流程

```rust
pub async fn try_claim_stage1_job(
    &self,
    thread_id: ThreadId,
    worker_id: ThreadId,
    source_updated_at: i64,
    lease_seconds: i64,
    max_running_jobs: usize,
) -> anyhow::Result<Stage1JobClaimOutcome> {
    // 1. 检查是否已是最新（source_updated_at >= existing）
    // 2. 检查全局运行任务数 < max_running_jobs
    // 3. 尝试 INSERT OR UPDATE jobs 表（状态：running）
    // 4. 返回 Claimed / SkippedUpToDate / SkippedRunning / SkippedRetryBackoff
}
```

### 3.4 数据库迁移

**State DB 迁移**（`migrations/` 目录，当前版本 5）：
- `0001_threads.sql` - 初始 threads 表
- `0002_logs.sql` - 初始 logs 表（后迁移到独立 DB）
- `0006_memories.sql` - stage1_outputs + jobs 表
- `0014_agent_jobs.sql` - Agent Job 表
- `0016_memory_usage.sql` - usage_count / last_usage 字段
- `0017_phase2_selection_flag.sql` - selected_for_phase2 标记
- `0020_threads_model_reasoning_effort.sql` - reasoning_effort 字段

**Logs DB 迁移**（`logs_migrations/` 目录，当前版本 1）：
- `0001_logs.sql` - 初始 logs 表
- `0002_logs_feedback_log_body.sql` - feedback_log_body 字段

---

## 4. 关键代码路径与文件引用

### 4.1 入口与初始化

| 文件 | 职责 |
|------|------|
| `src/lib.rs` | 模块导出、常量定义（DB 版本号） |
| `src/runtime.rs` | `StateRuntime` 结构体定义、`init()` 方法 |
| `src/migrations.rs` | sqlx migrate 宏定义 |

### 4.2 功能模块

| 文件 | 职责 |
|------|------|
| `src/runtime/threads.rs` | Thread CRUD、rollout items 应用 |
| `src/runtime/logs.rs` | 日志查询、裁剪、反馈日志生成 |
| `src/runtime/agent_jobs.rs` | Agent Job 生命周期管理 |
| `src/runtime/memories.rs` | Stage-1 / Phase-2 记忆任务调度 |
| `src/runtime/backfill.rs` | Backfill 状态管理 |
| `src/extract.rs` | RolloutItem 到 ThreadMetadata 的提取逻辑 |
| `src/log_db.rs` | tracing Layer 实现（LogDbLayer） |

### 4.3 数据模型

| 文件 | 职责 |
|------|------|
| `src/model/mod.rs` | 模型导出 |
| `src/model/thread_metadata.rs` | ThreadMetadata、ThreadRow、Anchor |
| `src/model/agent_job.rs` | AgentJob、AgentJobItem、状态枚举 |
| `src/model/log.rs` | LogEntry、LogRow、LogQuery |
| `src/model/memories.rs` | Stage1Output、Phase2InputSelection |
| `src/model/backfill_state.rs` | BackfillState、BackfillStatus |

### 4.4 工具

| 文件 | 职责 |
|------|------|
| `src/bin/logs_client.rs` | CLI 工具：查询和 tail 日志 |
| `src/paths.rs` | 文件修改时间获取 |
| `src/runtime/test_support.rs` | 测试辅助函数 |

---

## 5. 依赖与外部交互

### 5.1 外部依赖

| Crate | 用途 |
|-------|------|
| `sqlx` | SQLite 异步访问、迁移管理 |
| `chrono` | 时间处理 |
| `serde` / `serde_json` | JSON 序列化 |
| `tokio` | 异步运行时 |
| `tracing` / `tracing-subscriber` | 日志收集（LogDbLayer） |
| `uuid` | UUID 生成 |
| `codex-protocol` | ThreadId、RolloutItem、EventMsg 等协议类型 |

### 5.2 调用方

| Crate | 使用方式 |
|-------|----------|
| `codex-core` | `state_db.rs` 模块封装，供 rollout、memories 使用 |
| `codex-cli` | 直接初始化 `StateRuntime`，用于 debug 命令 |
| `codex-tui` | 通过 `log_db::start()` 初始化日志层 |
| `codex-app-server` | 初始化日志层，处理 thread 元数据 |
| `codex-tui-app-server` | 初始化日志层 |

### 5.3 配置

- `CODEX_SQLITE_HOME` 环境变量：覆盖 SQLite 数据库目录（默认 `~/.codex`）
- 数据库文件命名：`state_{VERSION}.sqlite`、`logs_{VERSION}.sqlite`
- 版本号常量：`STATE_DB_VERSION = 5`、`LOGS_DB_VERSION = 1`

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 说明 | 缓解措施 |
|------|------|----------|
| **数据库锁定** | SQLite WAL 模式下高并发写入可能导致锁竞争 | 使用 `BEGIN IMMEDIATE`、限制连接池大小（max 5）、短事务 |
| **日志数据膨胀** | 高频日志可能快速填满磁盘 | 每 partition 10MiB 自动裁剪、10 天保留策略 |
| **Backfill 阻塞** | 首次启动时大量历史文件需要回填 | 异步后台任务、支持 checkpoint 恢复 |
| **版本兼容性** | 旧版本 DB 文件可能不兼容 | 版本号命名、启动时清理旧版本文件 |

### 6.2 边界情况

1. **Threadless 日志**：没有 thread_id 的日志（如启动阶段）按 process_uuid 分区，NULL process_uuid 作为独立分区
2. **Memory 模式**：threads.memory_mode 字段控制（enabled/disabled/polluted），disabled 的 thread 不参与 Stage-1 提取
3. **Lease 过期**：Job 认领使用 lease 机制，过期后可被其他 worker 抢占
4. **Retry 耗尽**：Stage-1 Job 默认 3 次重试，耗尽后需手动干预

### 6.3 改进建议

| 优先级 | 建议 | 理由 |
|--------|------|------|
| **高** | 添加 metrics 导出 | 当前仅定义了常量（DB_ERROR_METRIC 等），未实际上报 |
| **中** | 抽象存储接口 | 当前直接依赖 SQLite，未来可能需要支持其他存储（如远程） |
| **中** | 优化日志裁剪性能 | 当前使用 window function，大数据量时可能影响写入延迟 |
| **低** | 支持 DB 压缩/归档 | 长期使用的用户可能积累大量历史数据 |
| **低** | 添加 DB 健康检查 API | 用于诊断工具检测 DB 完整性 |

### 6.4 测试覆盖

- **单元测试**：各 runtime 模块包含完整测试（`#[cfg(test)]`）
- **并发测试**：`stage1_concurrent_claim_for_same_thread_is_conflict_safe` 验证竞争条件
- **迁移测试**：`init_migrates_message_only_logs_db_to_feedback_log_body_schema` 验证 schema 升级
- **集成测试**：`codex-core/tests/suite/memories.rs` 端到端测试

---

## 7. 附录：关键代码片段

### 7.1 StateRuntime 初始化

```rust
pub async fn init(codex_home: PathBuf, default_provider: String) -> anyhow::Result<Arc<Self>> {
    tokio::fs::create_dir_all(&codex_home).await?;
    // 清理旧版本 DB 文件
    remove_legacy_db_files(&codex_home, ...).await;
    
    let state_path = state_db_path(codex_home.as_path());
    let logs_path = logs_db_path(codex_home.as_path());
    
    let pool = open_sqlite(&state_path, &STATE_MIGRATOR).await?;
    let logs_pool = open_sqlite(&logs_path, &LOGS_MIGRATOR).await?;
    
    Ok(Arc::new(Self {
        pool, logs_pool, codex_home, default_provider,
    }))
}
```

### 7.2 LogDbLayer 使用示例

```rust
// 在应用初始化时
let runtime = StateRuntime::init(codex_home, provider).await?;
let log_layer = codex_state::log_db::start(runtime.clone());

tracing_subscriber::registry()
    .with(log_layer)
    .init();
```

### 7.3 Thread 列表查询

```rust
let page = runtime
    .list_threads(
        page_size,
        anchor.as_ref(),      // 分页锚点
        SortKey::UpdatedAt,   // 排序字段
        &["cli".to_string()], // 允许的 sources
        Some(&["openai".to_string()]), // 模型提供商过滤
        false,                // 仅归档
        Some("search term"),  // 标题搜索
    )
    .await?;
```

---

*文档生成时间：2026-03-22*
*基于 codex-rs/state 代码库研究*
