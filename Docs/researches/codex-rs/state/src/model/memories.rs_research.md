# memories.rs 研究文档

## 场景与职责

`memories.rs` 是 Codex 状态管理模块中负责**智能记忆系统**的核心数据模型文件。它定义了 Stage-1 记忆提取和 Phase-2 记忆整合的数据结构，支持 Codex 的上下文学习和长期记忆功能。

### 核心职责
1. **Stage-1 输出定义**：定义从单个 rollout 提取的原始记忆结构
2. **Phase-2 输入选择**：定义记忆整合的输入选择结果
3. **作业认领结果**：定义记忆提取作业的认领状态和参数
4. **数据库行映射**：提供 Stage1OutputRow 与领域模型的转换

### 业务背景
Codex 的记忆系统分为两个阶段：
- **Stage-1**：从单个对话线程（rollout）提取结构化记忆
- **Phase-2**：整合多个线程的记忆，生成全局记忆快照

这种设计允许：
- 增量更新（新线程只触发 Stage-1）
- 按需整合（Phase-2 可批量处理）
- 记忆淘汰（基于使用频率和时效性）

## 功能点目的

### 1. Stage1Output - Stage-1 记忆输出

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Stage1Output {
    pub thread_id: ThreadId,           // 线程 ID
    pub rollout_path: PathBuf,         // rollout 文件路径
    pub source_updated_at: DateTime<Utc>, // 源 rollout 更新时间
    pub raw_memory: String,            // 原始记忆文本
    pub rollout_summary: String,       // rollout 摘要
    pub rollout_slug: Option<String>,  // rollout 标识（用于文件名）
    pub cwd: PathBuf,                  // 工作目录
    pub git_branch: Option<String>,   // Git 分支
    pub generated_at: DateTime<Utc>,   // 生成时间
}
```

**用途**：
- 存储单个线程的记忆提取结果
- 支持记忆使用统计（`usage_count`, `last_usage` 在数据库中）
- 关联到原始 rollout 以便溯源

### 2. Stage1OutputRef - 轻量级引用

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Stage1OutputRef {
    pub thread_id: ThreadId,
    pub source_updated_at: DateTime<Utc>,
    pub rollout_slug: Option<String>,
}
```

**用途**：
- 在 Phase-2 整合时标识被移除的记忆
- 比完整 Stage1Output 更轻量

### 3. Phase2InputSelection - Phase-2 输入选择

```rust
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Phase2InputSelection {
    pub selected: Vec<Stage1Output>,           // 当前选中的记忆
    pub previous_selected: Vec<Stage1Output>,  // 上次整合时的记忆
    pub retained_thread_ids: Vec<ThreadId>,    // 保留的线程 ID（未变更）
    pub removed: Vec<Stage1OutputRef>,         // 被移除的记忆引用
}
```

**用途**：
- 计算 Phase-2 整合的增量变更
- `retained_thread_ids` 允许增量更新，避免重新处理未变更的记忆
- `removed` 列表支持记忆淘汰通知

### 4. Stage1JobClaimOutcome - Stage-1 作业认领结果

```rust
pub enum Stage1JobClaimOutcome {
    Claimed { ownership_token: String },  // 成功认领
    SkippedUpToDate,                      // 已有更新或相等的输出
    SkippedRunning,                       // 其他工作者正在处理
    SkippedRetryBackoff,                  // 处于重试冷却期
    SkippedRetryExhausted,                // 重试次数已耗尽
}
```

**用途**：
- 协调多个工作者对同一 Stage-1 作业的竞争
- 提供详细的跳过原因，便于调试和监控

### 5. Stage1JobClaim - 认领的作业

```rust
pub struct Stage1JobClaim {
    pub thread: ThreadMetadata,      // 线程元数据
    pub ownership_token: String,     // 所有权令牌（用于后续操作验证）
}
```

### 6. Stage1StartupClaimParams - 启动认领参数

```rust
pub struct Stage1StartupClaimParams<'a> {
    pub scan_limit: usize,              // 扫描线程数上限
    pub max_claimed: usize,             // 最大认领数
    pub max_age_days: i64,              // 线程最大年龄（天）
    pub min_rollout_idle_hours: i64,    // rollout 最小空闲时间（小时）
    pub allowed_sources: &'a [String],  // 允许的会话来源
    pub lease_seconds: i64,             // 租约时长（秒）
}
```

**用途**：
- 控制启动时批量认领 Stage-1 作业的行为
- 避免启动时过载，平滑处理历史积压

### 7. Phase2JobClaimOutcome - Phase-2 作业认领结果

```rust
pub enum Phase2JobClaimOutcome {
    Claimed { 
        ownership_token: String,
        input_watermark: i64,        // 认领时的输入水位
    },
    SkippedNotDirty,                 // 无新工作（已是最新）
    SkippedRunning,                  // 其他工作者正在处理
}
```

## 具体技术实现

### 数据库行转换

```rust
// Stage1OutputRow - 数据库行结构（内部使用）
#[derive(Debug)]
pub(crate) struct Stage1OutputRow {
    thread_id: String,
    rollout_path: String,
    source_updated_at: i64,
    raw_memory: String,
    rollout_summary: String,
    rollout_slug: Option<String>,
    cwd: String,
    git_branch: Option<String>,
    generated_at: i64,
}

impl Stage1OutputRow {
    pub(crate) fn try_from_row(row: &SqliteRow) -> Result<Self> {
        Ok(Self {
            thread_id: row.try_get("thread_id")?,
            rollout_path: row.try_get("rollout_path")?,
            // ...
        })
    }
}

// 转换为领域模型
impl TryFrom<Stage1OutputRow> for Stage1Output {
    type Error = anyhow::Error;
    fn try_from(row: Stage1OutputRow) -> std::result::Result<Self, Self::Error> {
        Ok(Self {
            thread_id: ThreadId::try_from(row.thread_id)?,
            rollout_path: PathBuf::from(row.rollout_path),
            source_updated_at: epoch_seconds_to_datetime(row.source_updated_at)?,
            // ...
        })
    }
}
```

### 辅助函数

```rust
pub(crate) fn stage1_output_ref_from_parts(
    thread_id: String,
    source_updated_at: i64,
    rollout_slug: Option<String>,
) -> Result<Stage1OutputRef> {
    Ok(Stage1OutputRef {
        thread_id: ThreadId::try_from(thread_id)?,
        source_updated_at: epoch_seconds_to_datetime(source_updated_at)?,
        rollout_slug,
    })
}
```

## 关键代码路径与文件引用

### 模型定义位置
- **文件**：`codex-rs/state/src/model/memories.rs`（本文件）
- **导出**：`codex-rs/state/src/model/mod.rs` 通过 `pub use memories::*` 导出

### 数据库操作实现
- **文件**：`codex-rs/state/src/runtime/memories.rs`（约 1000+ 行）
- **核心方法**：
  - `clear_memory_data()` / `reset_memory_data_for_fresh_start()` - 清理记忆数据
  - `record_stage1_output_usage()` - 记录记忆使用
  - `claim_stage1_jobs_for_startup()` - 启动时认领 Stage-1 作业
  - `list_stage1_outputs_for_global()` - 列出用于全局整合的记忆
  - `prune_stage1_outputs_for_retention()` - 记忆保留修剪
  - `get_phase2_input_selection()` - 获取 Phase-2 输入选择
  - `try_claim_stage1_job()` - 尝试认领 Stage-1 作业
  - `mark_stage1_job_succeeded()` / `mark_stage1_job_failed()` - 标记作业完成
  - `try_claim_global_phase2_job()` - 尝试认领全局 Phase-2 作业

### 数据库 Schema
- **初始迁移**：`codex-rs/state/migrations/0006_memories.sql`

```sql
-- Stage-1 输出表
CREATE TABLE stage1_outputs (
    thread_id TEXT PRIMARY KEY,
    source_updated_at INTEGER NOT NULL,
    raw_memory TEXT NOT NULL,
    rollout_summary TEXT NOT NULL,
    generated_at INTEGER NOT NULL,
    FOREIGN KEY(thread_id) REFERENCES threads(id) ON DELETE CASCADE
);

CREATE INDEX idx_stage1_outputs_source_updated_at
    ON stage1_outputs(source_updated_at DESC, thread_id DESC);

-- 作业表（用于 Stage-1 和 Phase-2 作业调度）
CREATE TABLE jobs (
    kind TEXT NOT NULL,              -- 'memory_stage1' 或 'memory_consolidate_global'
    job_key TEXT NOT NULL,           -- thread_id 或 'global'
    status TEXT NOT NULL,            -- 'pending', 'running', 'done', 'error'
    worker_id TEXT,
    ownership_token TEXT,
    started_at INTEGER,
    finished_at INTEGER,
    lease_until INTEGER,             -- 租约过期时间
    retry_at INTEGER,                -- 下次重试时间
    retry_remaining INTEGER NOT NULL,
    last_error TEXT,
    input_watermark INTEGER,         -- 输入水位（用于增量检测）
    last_success_watermark INTEGER,  -- 最后成功水位
    PRIMARY KEY (kind, job_key)
);

CREATE INDEX idx_jobs_kind_status_retry_lease
    ON jobs(kind, status, retry_at, lease_until);
```

- **升级迁移**：
  - `0009_stage1_outputs_rollout_slug.sql` - 添加 rollout_slug 字段
  - `0016_memory_usage.sql` - 添加 usage_count 和 last_usage 字段
  - `0017_phase2_selection_flag.sql` - 添加 selected_for_phase2 字段
  - `0018_phase2_selection_snapshot.sql` - 添加 selected_for_phase2_source_updated_at 字段

### 业务逻辑调用方
- **Phase-1 提取**：`codex-rs/core/src/memories/phase1.rs`
- **Phase-2 整合**：`codex-rs/core/src/memories/phase2.rs`
- **存储管理**：`codex-rs/core/src/memories/storage.rs`
- **提示词生成**：`codex-rs/core/src/memories/prompts.rs`

### 测试
- **单元测试**：`codex-rs/core/src/memories/storage_tests.rs`
- **集成测试**：`codex-rs/core/tests/suite/memories.rs`
- **核心测试**：`codex-rs/core/src/memories/tests.rs`

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `anyhow` | 错误处理 |
| `chrono` | 时间戳处理 |
| `codex_protocol::ThreadId` | 线程 ID 类型 |
| `sqlx::Row` / `SqliteRow` | 数据库行访问 |
| `std::path::PathBuf` | 路径处理 |

### 内部模块交互
```
memories.rs (模型定义)
    ↓
mod.rs (统一导出)
    ↓
runtime/memories.rs (数据库操作)
    ↓
lib.rs (公开 API)
    ↓
codex-core/memories/* (业务逻辑)
```

## 风险、边界与改进建议

### 风险点

1. **作业竞争**
   - 多个实例可能同时尝试认领同一 Stage-1 作业
   - **缓解**：使用 `BEGIN IMMEDIATE` 事务和原子 UPDATE 语句

2. **记忆爆炸**
   - 长期使用后 stage1_outputs 表可能变得庞大
   - **缓解**：`prune_stage1_outputs_for_retention()` 基于使用频率和时效性修剪

3. **Phase-2 一致性**
   - Phase-2 整合是全局操作，可能与其他线程的 Stage-1 完成冲突
   - **缓解**：使用 `selected_for_phase2` 标记和快照机制

### 边界情况

1. **空记忆**
   - Stage-1 提取可能产生空记忆
   - **处理**：`mark_stage1_job_succeeded_no_output()` 删除现有输出

2. **线程删除**
   - 外键约束 `ON DELETE CASCADE` 会自动清理关联的 stage1_outputs

3. **重试耗尽**
   - 默认重试次数为 3 次（`DEFAULT_RETRY_REMAINING = 3`）
   - 耗尽后需要手动重置或等待 rollout 更新

### 改进建议

1. **记忆优先级**
   - 当前 Phase-2 选择基于使用频率和时效性
   - 建议：增加显式优先级字段，允许用户标记重要记忆

2. **增量 Phase-2**
   - 当前 Phase-2 需要处理全部选中记忆
   - 建议：利用 `retained_thread_ids` 实现真正的增量整合

3. **记忆版本控制**
   - 当前记忆更新会覆盖旧版本
   - 建议：保留历史版本，支持记忆回溯

4. **跨设备同步**
   - 记忆目前只存储在本地 SQLite
   - 建议：考虑加密云同步机制

5. **记忆搜索**
   - 当前没有直接搜索记忆内容的功能
   - 建议：增加 FTS 索引支持记忆内容搜索

### 代码质量

1. **时间戳转换重复**
   - `epoch_seconds_to_datetime` 在多个文件重复定义
   - 建议：提取到公共工具模块

2. **SQL 复杂度**
   - `runtime/memories.rs` 中的 SQL 查询非常复杂
   - 建议：考虑使用查询构建器或预定义视图

3. **测试覆盖**
   - 模型转换逻辑测试覆盖不足
   - 建议：增加针对 `TryFrom` 实现的单元测试
