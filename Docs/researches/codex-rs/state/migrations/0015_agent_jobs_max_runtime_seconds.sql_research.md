# 0015_agent_jobs_max_runtime_seconds.sql 研究文档

## 场景与职责

本迁移为 `agent_jobs` 表添加 `max_runtime_seconds` 字段，支持设置批处理作业的最大运行时间。这是作业超时控制的基础，防止单个作业运行过久影响系统资源。

## 功能点目的

### 1. 添加 max_runtime_seconds 字段
- **字段**: `max_runtime_seconds INTEGER`
- **约束**: 可为空（NULL）
- **用途**: 设置作业的最大运行时间（秒）

### 使用场景
- **超时控制**: 防止作业无限期运行
- **资源管理**: 限制长时间运行的作业
- **SLA 保障**: 确保作业在合理时间内完成

## 具体技术实现

### 关键流程
1. **作业创建**: 可选设置最大运行时间
2. **超时检查**: 执行过程中检查是否超时
3. **超时处理**: 超时后取消作业或标记失败

### 代码映射
在 `codex-rs/state/src/model/agent_job.rs` 中：
```rust
pub struct AgentJob {
    pub id: String,
    pub name: String,
    pub status: AgentJobStatus,
    pub instruction: String,
    pub auto_export: bool,
    pub max_runtime_seconds: Option<u64>,  // 新增字段
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

pub struct AgentJobCreateParams {
    // ...
    pub max_runtime_seconds: Option<u64>,  // 新增参数
    // ...
}
```

在 `codex-rs/state/src/runtime/agent_jobs.rs` 中：
```rust
pub async fn create_agent_job(
    &self,
    params: &AgentJobCreateParams,
    items: &[AgentJobItemCreateParams],
) -> anyhow::Result<AgentJob> {
    let max_runtime_seconds = params
        .max_runtime_seconds
        .map(i64::try_from)
        .transpose()
        .map_err(|_| anyhow::anyhow!("invalid max_runtime_seconds value"))?;
    
    sqlx::query(
        r#"
INSERT INTO agent_jobs (
    // ...
    max_runtime_seconds,
    // ...
) VALUES (..., ?, ...)
        "#,
    )
    .bind(max_runtime_seconds)
    // ...
}
```

数据转换：
```rust
impl TryFrom<AgentJobRow> for AgentJob {
    type Error = anyhow::Error;

    fn try_from(value: AgentJobRow) -> Result<Self, Self::Error> {
        let max_runtime_seconds = value
            .max_runtime_seconds
            .map(u64::try_from)
            .transpose()
            .map_err(|_| anyhow::anyhow!("invalid max_runtime_seconds value"))?;
        Ok(Self {
            // ...
            max_runtime_seconds,
            // ...
        })
    }
}
```

## 关键代码路径与文件引用

### 模型定义
- `codex-rs/state/src/model/agent_job.rs`:
  - `AgentJob`: 包含 `max_runtime_seconds` 字段
  - `AgentJobCreateParams`: 创建参数
  - `AgentJobRow`: 数据库行映射

### 作业管理
- `codex-rs/state/src/runtime/agent_jobs.rs`:
  - `create_agent_job()`: 创建时设置超时
  - 超时检查逻辑（在 core 层实现）

### 超时处理
- `codex-rs/core/src/agent_jobs/executor.rs`: 超时检查和处理

## 依赖与外部交互

### 上游依赖
- `0014_agent_jobs.sql`: 基础 agent_jobs 表结构

### 下游依赖
- 无直接下游依赖

### 应用层交互
- 作业执行器定期检查运行时间
- 超时后触发取消或失败处理

## 风险、边界与改进建议

### 风险
1. **精度问题**: 秒级精度可能不够精细
2. **检查时延**: 检查间隔可能导致实际运行时间略超限制
3. **强制终止**: 超时后的清理操作可能不完整

### 边界情况
1. **NULL 值**: 表示无超时限制
2. **0 值**: 可能表示立即超时（需应用层处理）
3. **大数值**: u64 转 i64 可能溢出

### 改进建议
1. 考虑使用毫秒精度（如果需要更精细控制）
2. 添加超时策略配置（取消/失败/告警）
3. 可为作业项也添加超时控制
4. 考虑添加超时前的预警机制
