# agent_job.rs 研究文档

## 场景与职责

`agent_job.rs` 是 Codex 状态管理模块中负责**批量 Agent 作业管理**的核心数据模型文件。它定义了 Agent Job（代理作业）系统的完整数据结构和状态流转模型，用于支持批量处理任务（如批量代码审查、批量文件处理等）。

### 核心职责
1. **作业生命周期管理**：定义 Agent Job 和 Agent Job Item 的状态机（Pending → Running → Completed/Failed/Cancelled）
2. **数据模型定义**：提供内存中的领域模型（AgentJob/AgentJobItem）与数据库行模型（AgentJobRow/AgentJobItemRow）之间的映射
3. **状态转换逻辑**：提供状态解析、字符串转换和状态判断方法

## 功能点目的

### 1. AgentJobStatus - 作业状态枚举

```rust
pub enum AgentJobStatus {
    Pending,    // 等待执行
    Running,    // 执行中
    Completed,  // 已完成
    Failed,     // 失败
    Cancelled,  // 已取消
}
```

- **目的**：跟踪整个作业的宏观状态
- **is_final() 方法**：判断作业是否已到达终态（Completed/Failed/Cancelled），用于流程控制和资源清理

### 2. AgentJobItemStatus - 作业项状态枚举

```rust
pub enum AgentJobItemStatus {
    Pending,    // 等待处理
    Running,    // 处理中
    Completed,  // 已完成
    Failed,     // 失败
}
```

- **目的**：跟踪作业中每个具体项目（CSV 行）的处理状态
- **注意**：没有 Cancelled 状态，因为作业取消是作业级别的操作

### 3. AgentJob - 作业领域模型

```rust
pub struct AgentJob {
    pub id: String,
    pub name: String,
    pub status: AgentJobStatus,
    pub instruction: String,           // Agent 执行指令
    pub auto_export: bool,             // 是否自动导出结果
    pub max_runtime_seconds: Option<u64>,  // 最大运行时间限制
    pub output_schema_json: Option<Value>, // 输出 JSON Schema（TODO: 未来用于结构化输出验证）
    pub input_headers: Vec<String>,    // CSV 输入表头
    pub input_csv_path: String,        // 输入 CSV 路径
    pub output_csv_path: String,       // 输出 CSV 路径
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub started_at: Option<DateTime<Utc>>,
    pub completed_at: Option<DateTime<Utc>>,
    pub last_error: Option<String>,
}
```

### 4. AgentJobItem - 作业项领域模型

```rust
pub struct AgentJobItem {
    pub job_id: String,
    pub item_id: String,
    pub row_index: i64,                // CSV 行索引
    pub source_id: Option<String>,     // 可选的源标识
    pub row_json: Value,               // 行数据（JSON 格式）
    pub status: AgentJobItemStatus,
    pub assigned_thread_id: Option<String>, // 分配的线程 ID
    pub attempt_count: i64,            // 重试次数
    pub result_json: Option<Value>,    // 执行结果
    pub last_error: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub completed_at: Option<DateTime<Utc>>,
    pub reported_at: Option<DateTime<Utc>>, // 结果报告时间
}
```

### 5. AgentJobProgress - 进度统计

```rust
pub struct AgentJobProgress {
    pub total_items: usize,
    pub pending_items: usize,
    pub running_items: usize,
    pub completed_items: usize,
    pub failed_items: usize,
}
```

用于向用户展示作业执行进度。

## 具体技术实现

### 数据库行模型与领域模型转换

文件实现了 `TryFrom` trait 来完成数据库行（AgentJobRow/AgentJobItemRow）与领域模型之间的转换：

```rust
impl TryFrom<AgentJobRow> for AgentJob {
    type Error = anyhow::Error;
    fn try_from(value: AgentJobRow) -> Result<Self, Self::Error> {
        // 1. 解析可选的 JSON Schema
        let output_schema_json = value.output_schema_json
            .as_deref()
            .map(serde_json::from_str)
            .transpose()?;
        
        // 2. 解析输入表头 JSON
        let input_headers = serde_json::from_str(value.input_headers_json.as_str())?;
        
        // 3. 转换时间戳
        let created_at = epoch_seconds_to_datetime(value.created_at)?;
        
        // 4. 解析状态字符串
        let status = AgentJobStatus::parse(value.status.as_str())?;
        
        // ... 构建 AgentJob
    }
}
```

### 时间戳处理

```rust
fn epoch_seconds_to_datetime(secs: i64) -> Result<DateTime<Utc>> {
    DateTime::<Utc>::from_timestamp(secs, 0)
        .ok_or_else(|| anyhow::anyhow!("invalid unix timestamp: {secs}"))
}
```

SQLite 存储 Unix 时间戳（秒），内存中使用 `chrono::DateTime<Utc>`。

## 关键代码路径与文件引用

### 模型定义位置
- **文件**：`codex-rs/state/src/model/agent_job.rs`（本文件）
- **导出**：`codex-rs/state/src/model/mod.rs` 通过 `pub use agent_job::*` 统一导出

### 数据库操作实现
- **文件**：`codex-rs/state/src/runtime/agent_jobs.rs`
- **核心方法**：
  - `create_agent_job()` - 创建作业及作业项
  - `get_agent_job()` / `list_agent_job_items()` - 查询
  - `mark_agent_job_running/completed/failed/cancelled()` - 状态变更
  - `mark_agent_job_item_*()` - 作业项状态管理
  - `report_agent_job_item_result()` - 报告执行结果
  - `get_agent_job_progress()` - 获取进度统计

### 数据库 Schema
- **迁移文件**：`codex-rs/state/migrations/0014_agent_jobs.sql`
- **升级迁移**：`codex-rs/state/migrations/0015_agent_jobs_max_runtime_seconds.sql`（添加 max_runtime_seconds 字段）

```sql
-- agent_jobs 表
CREATE TABLE agent_jobs (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    status TEXT NOT NULL,
    instruction TEXT NOT NULL,
    output_schema_json TEXT,
    input_headers_json TEXT NOT NULL,
    input_csv_path TEXT NOT NULL,
    output_csv_path TEXT NOT NULL,
    auto_export INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    started_at INTEGER,
    completed_at INTEGER,
    last_error TEXT
);

-- agent_job_items 表
CREATE TABLE agent_job_items (
    job_id TEXT NOT NULL,
    item_id TEXT NOT NULL,
    row_index INTEGER NOT NULL,
    source_id TEXT,
    row_json TEXT NOT NULL,
    status TEXT NOT NULL,
    assigned_thread_id TEXT,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    result_json TEXT,
    last_error TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    completed_at INTEGER,
    reported_at INTEGER,
    PRIMARY KEY (job_id, item_id),
    FOREIGN KEY(job_id) REFERENCES agent_jobs(id) ON DELETE CASCADE
);
```

### 调用方
- **工具处理器**：`codex-rs/core/src/tools/handlers/agent_jobs.rs` - Agent Job 工具的 CLI 实现
- **事件处理器**：`codex-rs/exec/src/event_processor_with_human_output.rs` - 处理 Agent Job 相关事件
- **配置模块**：`codex-rs/core/src/config/mod.rs` - Agent Job 配置

### 测试
- **集成测试**：`codex-rs/core/tests/suite/agent_jobs.rs`
- **单元测试**：`codex-rs/state/src/runtime/agent_jobs.rs` 底部包含测试模块

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `anyhow` | 错误处理 |
| `chrono` | 时间戳处理（DateTime<Utc>） |
| `serde_json::Value` | 动态 JSON 数据存储（row_json, output_schema_json, result_json） |
| `sqlx::FromRow` | 数据库行映射 |

### 内部模块交互
```
agent_job.rs (模型定义)
    ↓
mod.rs (统一导出)
    ↓
runtime/agent_jobs.rs (数据库操作实现)
    ↓
lib.rs (公开 API)
    ↓
codex-core (业务逻辑调用)
```

## 风险、边界与改进建议

### 风险点

1. **JSON 序列化开销**
   - `row_json`, `output_schema_json`, `result_json` 使用 `serde_json::Value`
   - 大数据量时序列化/反序列化可能成为瓶颈
   - **缓解**：批量处理时控制每批大小

2. **状态竞争**
   - 作业项状态变更（如 `mark_agent_job_item_running`）使用条件更新
   - 需要确保并发安全，目前依赖 SQLite 的行级锁

3. **时间戳精度**
   - 数据库只存储秒级时间戳（nanosecond 被截断）
   - `canonicalize_datetime()` 方法在 `thread_metadata.rs` 中统一处理

### 边界情况

1. **作业取消**
   - 只能取消 Pending 或 Running 状态的作业
   - 已完成的作业项不会被取消

2. **结果报告**
   - `report_agent_job_item_result` 要求作业项处于 Running 状态且 `assigned_thread_id` 匹配
   - 防止过期结果覆盖新结果

3. **最大运行时间**
   - `max_runtime_seconds` 字段存在，但具体超时检查逻辑在调用方实现

### 改进建议

1. **输出 Schema 验证**
   - TODO 注释提到："Convert to JSON Schema and enforce structured outputs"
   - 建议：在 `report_agent_job_item_result` 时验证结果是否符合 schema

2. **批量转换优化**
   - 当前 `TryFrom` 实现逐个字段转换
   - 建议：考虑使用 `sqlx` 的派生宏简化代码

3. **状态历史追踪**
   - 当前只记录最后错误，不记录完整状态历史
   - 建议：如需审计功能，可增加状态变更历史表

4. **作业项分页**
   - `list_agent_job_items` 支持 limit 参数
   - 建议：如需处理超大数据集，考虑支持 cursor-based 分页
