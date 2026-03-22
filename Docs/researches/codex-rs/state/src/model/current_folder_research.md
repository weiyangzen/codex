# codex-rs/state/src/model 目录深度研究文档

## 1. 场景与职责

### 1.1 模块定位

`codex-rs/state/src/model` 模块是 **Codex State Crate** 的核心数据模型层，负责定义 SQLite 状态数据库中所有表结构对应的 Rust 领域模型。该模块作为数据持久层与业务逻辑层之间的桥梁，承担着以下关键职责：

- **领域模型定义**：定义线程元数据、Agent 作业、内存提取、日志等核心数据结构
- **数据库行映射**：提供从 SQL 查询结果（`sqlx::Row`）到 Rust 结构体的转换逻辑
- **状态枚举管理**：定义作业状态、回填状态等生命周期状态机
- **跨层数据传输**：作为 `StateRuntime` 与数据库之间的数据载体

### 1.2 架构位置

```
codex-rs/
├── state/src/
│   ├── model/           # ← 本模块：数据模型定义
│   │   ├── mod.rs       # 模块聚合与公共导出
│   │   ├── thread_metadata.rs  # 线程元数据模型
│   │   ├── agent_job.rs        # Agent 批处理作业模型
│   │   ├── memories.rs         # 内存提取（Stage1/Phase2）模型
│   │   ├── backfill_state.rs   # 元数据回填状态模型
│   │   └── log.rs              # 日志条目模型
│   ├── runtime/         # 运行时：数据库操作实现
│   ├── extract.rs       # Rollout 数据提取逻辑
│   ├── log_db.rs        # 日志数据库追踪层
│   └── lib.rs           # Crate 根模块
├── core/src/            # 核心逻辑：调用方
└── protocol/src/        # 协议定义：ThreadId 等
```

### 1.3 使用场景

| 场景 | 描述 |
|------|------|
| **线程列表展示** | TUI/GUI 展示历史会话列表时，通过 `ThreadMetadata` 获取标题、模型、时间等 |
| **Agent 批处理** | `AgentJob` 和 `AgentJobItem` 支持 CSV 批量处理工作流 |
| **智能内存** | `Stage1Output` 和 `Phase2InputSelection` 支持基于 LLM 的会话记忆提取与整合 |
| **元数据回填** | `BackfillState` 管理从 rollout 文件到 SQLite 的初始数据迁移 |
| **日志查询** | `LogEntry` 和 `LogQuery` 支持结构化日志存储与检索 |

---

## 2. 功能点目的

### 2.1 线程元数据管理 (`thread_metadata.rs`)

**目的**：为每个 Codex 会话维护完整的元数据快照，支持线程列表、搜索、归档等功能。

**核心功能点**：
- **线程身份**：`ThreadId` (UUID v7) 作为主键
- **会话属性**：来源（CLI/TUI）、模型提供商、沙箱策略、审批模式
- **Git 上下文**：提交 SHA、分支、远程仓库 URL
- **Agent 标识**：昵称、角色（用于 AgentControl 子代理）
- **时间线**：创建时间、更新时间、归档时间
- **内容摘要**：首条用户消息、自动生成标题、Token 使用量

### 2.2 Agent 作业系统 (`agent_job.rs`)

**目的**：支持批量 CSV 处理工作流，允许用户提交大规模文件处理任务。

**核心功能点**：
- **作业生命周期**：Pending → Running → Completed/Failed/Cancelled
- **作业项追踪**：每行 CSV 对应一个 `AgentJobItem`，独立追踪状态
- **结果收集**：支持 JSON Schema 定义的输出格式
- **超时控制**：`max_runtime_seconds` 防止作业无限运行
- **自动导出**：`auto_export` 控制是否自动写入输出 CSV

### 2.3 智能内存系统 (`memories.rs`)

**目的**：实现基于 LLM 的会话记忆提取与整合，支持长期上下文保持。

**两阶段架构**：
- **Stage 1（提取）**：从单个 rollout 提取原始记忆和摘要
  - `Stage1Output`：存储提取的记忆内容
  - `Stage1JobClaimOutcome`：作业认领结果（支持分布式竞争）
  - 重试机制：默认 3 次重试，带指数退避

- **Phase 2（整合）**：聚合多个 Stage 1 输出为全局记忆
  - `Phase2InputSelection`：输入选择快照，支持增量更新
  - `Phase2JobClaimOutcome`：全局锁竞争结果

### 2.4 回填状态管理 (`backfill_state.rs`)

**目的**：管理从 rollout JSONL 文件到 SQLite 的元数据迁移过程。

**状态流转**：
```
Pending → Running → Complete
```

**功能**：
- 水印追踪：`last_watermark` 记录最后处理的 rollout 路径
- 租约机制：防止多实例并发回填
- 断点续传：支持从上次位置恢复

### 2.5 日志模型 (`log.rs`)

**目的**：支持结构化日志存储，用于调试和反馈收集。

**功能点**：
- **分级存储**：支持 TRACE/DEBUG/INFO/WARN/ERROR 级别
- **线程关联**：通过 `thread_id` 关联到特定会话
- **进程追踪**：`process_uuid` 区分不同进程实例
- **查询过滤**：`LogQuery` 支持多维度过滤（时间、级别、模块、文件）

---

## 3. 具体技术实现

### 3.1 数据结构设计

#### 3.1.1 ThreadMetadata（线程元数据）

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ThreadMetadata {
    pub id: ThreadId,                    // UUID v7 主键
    pub rollout_path: PathBuf,           // Rollout 文件绝对路径
    pub created_at: DateTime<Utc>,       // 创建时间戳
    pub updated_at: DateTime<Utc>,       // 最后更新时间
    pub source: String,                  // 来源："cli" | "tui" | ...
    pub agent_nickname: Option<String>,  // Agent 子代理昵称
    pub agent_role: Option<String>,      // Agent 角色
    pub model_provider: String,          // 模型提供商
    pub model: Option<String>,           // 具体模型名称
    pub reasoning_effort: Option<ReasoningEffort>, // 推理努力程度
    pub cwd: PathBuf,                    // 工作目录
    pub cli_version: String,             // CLI 版本
    pub title: String,                   // 会话标题
    pub sandbox_policy: String,          // 沙箱策略
    pub approval_mode: String,           // 审批模式
    pub tokens_used: i64,                // Token 使用量
    pub first_user_message: Option<String>, // 首条用户消息预览
    pub archived_at: Option<DateTime<Utc>>, // 归档时间
    pub git_sha: Option<String>,         // Git 提交 SHA
    pub git_branch: Option<String>,      // Git 分支
    pub git_origin_url: Option<String>,  // Git 远程地址
}
```

**设计决策**：
- 使用 `String` 而非枚举存储策略字段，保持数据库兼容性
- `ThreadId` 包装 UUID v7，支持时间排序
- 时间戳使用 `DateTime<Utc>`，数据库层转换为 Unix 秒

#### 3.1.2 AgentJob（Agent 批处理作业）

```rust
#[derive(Debug, Clone, PartialEq)]
pub struct AgentJob {
    pub id: String,                      // 作业 ID
    pub name: String,                    // 作业名称
    pub status: AgentJobStatus,          // 状态枚举
    pub instruction: String,             // 系统指令
    pub auto_export: bool,               // 自动导出结果
    pub max_runtime_seconds: Option<u64>, // 超时限制
    pub output_schema_json: Option<Value>, // 输出 JSON Schema
    pub input_headers: Vec<String>,      // CSV 表头
    pub input_csv_path: String,          // 输入文件路径
    pub output_csv_path: String,         // 输出文件路径
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub started_at: Option<DateTime<Utc>>,
    pub completed_at: Option<DateTime<Utc>>,
    pub last_error: Option<String>,
}
```

#### 3.1.3 Stage1Output（内存提取输出）

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Stage1Output {
    pub thread_id: ThreadId,
    pub rollout_path: PathBuf,
    pub source_updated_at: DateTime<Utc>, // rollout 修改时间
    pub raw_memory: String,               // 原始记忆文本
    pub rollout_summary: String,          // Rollout 摘要
    pub rollout_slug: Option<String>,     // 用于文件命名
    pub cwd: PathBuf,                     // 工作目录（当时）
    pub git_branch: Option<String>,       // Git 分支（当时）
    pub generated_at: DateTime<Utc>,      // 生成时间
}
```

### 3.2 数据库行映射模式

Model 模块采用 **Row → Domain Model** 的双层映射模式：

```rust
// 1. 数据库原始行（sqlx::FromRow）
#[derive(Debug, sqlx::FromRow)]
pub(crate) struct ThreadRow {
    pub(crate) id: String,
    pub(crate) created_at: i64,  // Unix 秒
    // ... 其他字段
}

// 2. 领域模型（业务逻辑使用）
pub struct ThreadMetadata {
    pub id: ThreadId,
    pub created_at: DateTime<Utc>,
    // ...
}

// 3. TryFrom 实现转换逻辑
impl TryFrom<ThreadRow> for ThreadMetadata {
    type Error = anyhow::Error;
    fn try_from(row: ThreadRow) -> Result<Self, Self::Error> {
        Ok(Self {
            id: ThreadId::try_from(row.id)?,
            created_at: epoch_seconds_to_datetime(row.created_at)?,
            // ...
        })
    }
}
```

**转换工具函数**：
```rust
pub(crate) fn epoch_seconds_to_datetime(secs: i64) -> Result<DateTime<Utc>> {
    DateTime::<Utc>::from_timestamp(secs, 0)
        .ok_or_else(|| anyhow::anyhow!("invalid unix timestamp: {secs}"))
}

pub(crate) fn datetime_to_epoch_seconds(dt: DateTime<Utc>) -> i64 {
    dt.timestamp()
}
```

### 3.3 状态机实现

#### 3.3.1 AgentJobStatus

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AgentJobStatus {
    Pending,    // 等待执行
    Running,    // 执行中
    Completed,  // 成功完成
    Failed,     // 执行失败
    Cancelled,  // 被取消
}

impl AgentJobStatus {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Running => "running",
            Self::Completed => "completed",
            Self::Failed => "failed",
            Self::Cancelled => "cancelled",
        }
    }

    pub fn parse(value: &str) -> Result<Self> {
        match value {
            "pending" => Ok(Self::Pending),
            "running" => Ok(Self::Running),
            "completed" => Ok(Self::Completed),
            "failed" => Ok(Self::Failed),
            "cancelled" => Ok(Self::Cancelled),
            _ => Err(anyhow::anyhow!("invalid agent job status: {value}")),
        }
    }

    pub fn is_final(self) -> bool {
        matches!(self, Self::Completed | Self::Failed | Self::Cancelled)
    }
}
```

### 3.4 Builder 模式

`ThreadMetadataBuilder` 提供类型安全的构造方式：

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ThreadMetadataBuilder {
    pub id: ThreadId,
    pub rollout_path: PathBuf,
    pub created_at: DateTime<Utc>,
    pub updated_at: Option<DateTime<Utc>>,
    pub source: SessionSource,
    pub agent_nickname: Option<String>,
    pub agent_role: Option<String>,
    pub model_provider: Option<String>,
    pub cwd: PathBuf,
    pub cli_version: Option<String>,
    pub sandbox_policy: SandboxPolicy,
    pub approval_mode: AskForApproval,
    pub archived_at: Option<DateTime<Utc>>,
    pub git_sha: Option<String>,
    pub git_branch: Option<String>,
    pub git_origin_url: Option<String>,
}

impl ThreadMetadataBuilder {
    pub fn new(id: ThreadId, rollout_path: PathBuf, created_at: DateTime<Utc>, source: SessionSource) -> Self {
        Self { /* 默认值 */ }
    }

    pub fn build(&self, default_provider: &str) -> ThreadMetadata {
        // 填充默认值，转换枚举为字符串
    }
}
```

### 3.5 分页支持

```rust
/// 分页锚点，用于 keyset 分页
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Anchor {
    pub ts: DateTime<Utc>,  // 时间戳分量
    pub id: Uuid,           // UUID 分量
}

/// 线程列表分页结果
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ThreadsPage {
    pub items: Vec<ThreadMetadata>,
    pub next_anchor: Option<Anchor>,  // 下一页锚点
    pub num_scanned_rows: usize,      // 扫描行数（用于诊断）
}

/// 排序键
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SortKey {
    CreatedAt,
    UpdatedAt,
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 模块结构

```
codex-rs/state/src/model/
├── mod.rs                 # 模块聚合，pub use 所有公开类型
├── thread_metadata.rs     # ThreadMetadata, ThreadMetadataBuilder, ThreadsPage
├── agent_job.rs           # AgentJob, AgentJobItem, AgentJobStatus, AgentJobProgress
├── memories.rs            # Stage1Output, Phase2InputSelection, Stage1JobClaimOutcome
├── backfill_state.rs      # BackfillState, BackfillStatus
└── log.rs                 # LogEntry, LogQuery, LogRow
```

### 4.2 关键代码路径

#### 路径 1：线程元数据查询

```
调用方: codex-core/src/realtime_context.rs
    ↓
StateRuntime::list_threads()  [runtime/threads.rs:107]
    ↓
ThreadRow::try_from_row()     [thread_metadata.rs:320]
    ↓
ThreadMetadata::try_from()    [thread_metadata.rs:347]
```

#### 路径 2：Rollout 数据提取

```
调用方: codex-core/src/rollout/metadata.rs
    ↓
apply_rollout_item()          [extract.rs:15]
    ↓
更新 ThreadMetadata 字段
    ↓
StateRuntime::upsert_thread() [runtime/threads.rs:210]
```

#### 路径 3：Agent 作业创建

```
调用方: app-server 或 CLI
    ↓
StateRuntime::create_agent_job() [runtime/agent_jobs.rs:5]
    ↓
AgentJobRow → AgentJob 转换  [agent_job.rs:161]
```

#### 路径 4：内存 Stage 1 作业认领

```
调用方: codex-core/src/memories/storage.rs
    ↓
StateRuntime::claim_stage1_jobs_for_startup() [runtime/memories.rs:139]
    ↓
Stage1JobClaimOutcome 枚举    [memories.rs:105]
```

### 4.3 数据库 Schema 对应

| 模型文件 | 对应 SQL 迁移 | 表名 |
|---------|--------------|------|
| thread_metadata.rs | `migrations/0001_threads.sql` | `threads` |
| agent_job.rs | `migrations/0014_agent_jobs.sql` | `agent_jobs`, `agent_job_items` |
| memories.rs | `migrations/0006_memories.sql` | `stage1_outputs`, `jobs` |
| backfill_state.rs | `migrations/0008_backfill_state.sql` | `backfill_state` |
| log.rs | `logs_migrations/0001_logs.sql` | `logs` |

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```
model/
    ↑
    ├── codex_protocol::ThreadId          [protocol/src/thread_id.rs]
    ├── codex_protocol::ReasoningEffort   [protocol/src/openai_models.rs]
    ├── codex_protocol::protocol::*       [protocol/src/protocol/]
    │   - SessionSource
    │   - SandboxPolicy
    │   - AskForApproval
    │   - RolloutItem
    │   - SessionMetaLine
    │   - TurnContextItem
    │   - EventMsg
    │   - UserMessageEvent
    └── extract::enum_to_string           [extract.rs:128]
```

### 5.2 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `sqlx` | 数据库行映射 (`FromRow`)、查询构建 |
| `chrono` | 时间戳处理 (`DateTime<Utc>`) |
| `serde`/`serde_json` | JSON 序列化（`output_schema_json`, `row_json`） |
| `uuid` | UUID v7 生成与解析 |
| `anyhow` | 错误处理 |

### 5.3 调用方 Crate

| Crate | 使用方式 |
|-------|---------|
| `codex-core` | 主要调用方，使用所有模型类型 |
| `codex-tui` | 通过 `log_db` 使用日志功能 |
| `codex-cli` | 间接通过 `codex-core` 使用 |
| `app-server` | Agent 作业管理 |

### 5.4 数据流图

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Rollout JSONL │────→│  extract.rs     │────→│ ThreadMetadata  │
│   Files         │     │  (解析逻辑)      │     │ (领域模型)       │
└─────────────────┘     └─────────────────┘     └────────┬────────┘
                                                         │
┌─────────────────┐     ┌─────────────────┐              │
│   Agent CSV     │────→│ StateRuntime    │←─────────────┘
│   Input         │     │ (运行时)         │
└─────────────────┘     └────────┬────────┘
                                 │
                    ┌────────────┼────────────┐
                    ↓            ↓            ↓
              ┌─────────┐  ┌─────────┐  ┌─────────┐
              │ threads │  │ stage1_ │  │ agent_  │
              │         │  │ outputs │  │ jobs    │
              └─────────┘  └─────────┘  └─────────┘
                    ↑            ↑            ↑
              ┌─────────┐  ┌─────────┐  ┌─────────┐
              │ Thread  │  │ Stage1  │  │ Agent   │
              │Metadata │  │ Output  │  │ Job     │
              │ (model) │  │ (model) │  │ (model) │
              └─────────┘  └─────────┘  └─────────┘
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 风险 1：时间戳精度丢失

**问题**：数据库使用 Unix 秒（`i64`），丢弃了亚秒精度。

```rust
// thread_metadata.rs:291
fn canonicalize_datetime(dt: DateTime<Utc>) -> DateTime<Utc> {
    dt.with_nanosecond(0).unwrap_or(dt)  // ← 纳秒归零
}
```

**影响**：同一秒内创建的线程排序可能不稳定。

**缓解**：使用 `id`（UUID v7）作为次级排序键。

#### 风险 2：枚举字符串兼容性

**问题**：策略字段（`sandbox_policy`, `approval_mode`）使用 `String` 而非枚举，可能存储无效值。

```rust
// 数据库可能包含无效值，但转换不会失败
pub sandbox_policy: String,  // 应为 "read-only" | "danger-full-access" | ...
```

**缓解**：在业务逻辑层验证，而非模型层。

#### 风险 3：JSON 字段类型安全

**问题**：`output_schema_json` 和 `row_json` 使用 `serde_json::Value`，无编译时类型检查。

```rust
pub output_schema_json: Option<Value>,  // 应为 JSON Schema
pub row_json: Value,                    // 应为 CSV 行数据
```

**缓解**：运行时验证，TODO 注释表明计划迁移到 JSON Schema。

### 6.2 边界情况

#### 边界 1：线程 ID 解析失败

```rust
impl TryFrom<String> for ThreadId {
    type Error = uuid::Error;
    fn try_from(value: String) -> Result<Self, Self::Error> {
        Self::from_string(value.as_str())  // ← UUID 解析可能失败
    }
}
```

**场景**：手动修改数据库 `threads.id` 为无效 UUID。

**处理**：`TryFrom` 返回 `Err`，调用方需处理。

#### 边界 2：时间戳越界

```rust
fn epoch_seconds_to_datetime(secs: i64) -> Result<DateTime<Utc>> {
    DateTime::<Utc>::from_timestamp(secs, 0)
        .ok_or_else(|| anyhow::anyhow!("invalid unix timestamp: {secs}"))
}
```

**场景**：数据库包含超出 `DateTime` 范围的 Unix 秒值。

**处理**：返回错误，可能导致查询失败。

#### 边界 3：Agent 作业项并发更新

```rust
// agent_jobs.rs:425
pub async fn report_agent_job_item_result(...) -> anyhow::Result<bool> {
    // 使用 assigned_thread_id 作为乐观锁
    // 如果状态已被其他线程修改，返回 false
}
```

**场景**：多个线程同时报告同一作业项结果。

**处理**：SQL `WHERE` 条件确保原子性，返回 `bool` 指示是否成功。

### 6.3 改进建议

#### 建议 1：类型安全增强

**现状**：
```rust
pub source: String,  // 应为 "cli" | "tui" | "agent"
```

**建议**：
```rust
pub source: SessionSource,  // 使用 protocol 中的枚举

// 数据库层使用自定义类型或检查约束
```

#### 建议 2：JSON Schema 验证

**现状**：
```rust
// TODO(jif-oai): Convert to JSON Schema and enforce structured outputs.
pub output_schema_json: Option<Value>,
```

**建议**：
- 引入 `schemars` 或 `jsonschema` crate
- 定义 `OutputSchema` 类型，带编译时验证

#### 建议 3：时间戳精度提升

**建议**：
- 迁移到毫秒或微秒级时间戳（`i64` 毫秒）
- 或添加 `ts_nanos` 列保持纳秒精度

#### 建议 4：模型文档化

**建议**：
- 为每个模型类型添加 `#[doc = "..."]` 文档注释
- 说明字段含义、约束条件、使用场景

#### 建议 5：测试覆盖率

**现状**：测试主要集中在 `runtime/` 子模块。

**建议**：
- 为 `TryFrom` 转换添加单元测试
- 测试边界情况（无效 UUID、越界时间戳）
- 测试枚举 `parse` 的容错性

### 6.4 技术债务

| 位置 | 问题 | 优先级 |
|------|------|--------|
| `agent_job.rs:83` | `output_schema_json` 未使用 JSON Schema 验证 | 中 |
| `thread_metadata.rs:291` | 时间戳精度丢失 | 低 |
| `memories.rs` | `Stage1Output` 的 `raw_memory` 可能很大，无大小限制 | 中 |
| `log.rs` | `LogEntry` 和 `LogRow` 字段重复，可考虑合并 | 低 |

---

## 7. 附录

### 7.1 相关文件索引

| 文件路径 | 描述 |
|---------|------|
| `codex-rs/state/src/model/mod.rs` | 模块聚合与导出 |
| `codex-rs/state/src/model/thread_metadata.rs` | 线程元数据模型（512 行） |
| `codex-rs/state/src/model/agent_job.rs` | Agent 作业模型（256 行） |
| `codex-rs/state/src/model/memories.rs` | 内存提取模型（149 行） |
| `codex-rs/state/src/model/backfill_state.rs` | 回填状态模型（73 行） |
| `codex-rs/state/src/model/log.rs` | 日志模型（46 行） |
| `codex-rs/state/src/runtime/threads.rs` | 线程数据库操作（1000+ 行） |
| `codex-rs/state/src/runtime/agent_jobs.rs` | Agent 作业数据库操作（684 行） |
| `codex-rs/state/src/runtime/memories.rs` | 内存数据库操作（1000+ 行） |
| `codex-rs/state/src/extract.rs` | Rollout 数据提取逻辑（435 行） |
| `codex-rs/protocol/src/thread_id.rs` | ThreadId 定义（103 行） |

### 7.2 数据库迁移索引

| 迁移文件 | 描述 |
|---------|------|
| `0001_threads.sql` | 初始线程表 |
| `0006_memories.sql` | Stage1 输出和作业表 |
| `0008_backfill_state.sql` | 回填状态表 |
| `0014_agent_jobs.sql` | Agent 作业表 |
| `0017_phase2_selection_flag.sql` | Phase2 选择标记 |
| `0018_phase2_selection_snapshot.sql` | Phase2 选择快照 |
| `0020_threads_model_reasoning_effort.sql` | 模型和推理努力字段 |

---

*文档生成时间：2026-03-22*
*基于代码版本：codex-rs/state/src/model 目录*
