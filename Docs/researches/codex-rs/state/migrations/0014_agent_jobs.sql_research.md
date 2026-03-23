# 0014_agent_jobs.sql 研究文档

## 场景与职责

本迁移创建 Agent Jobs 系统，支持批量处理任务。这是 Codex 批处理功能的基础，允许用户提交包含多个输入项的作业，由多个代理并行处理。

## 功能点目的

### 1. agent_jobs 表
存储批处理作业的定义和状态：

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | TEXT PRIMARY KEY | 作业唯一标识 |
| `name` | TEXT NOT NULL | 作业名称 |
| `status` | TEXT NOT NULL | 状态（pending/running/completed/failed/cancelled） |
| `instruction` | TEXT NOT NULL | 处理指令/提示词 |
| `output_schema_json` | TEXT | 输出 JSON Schema |
| `input_headers_json` | TEXT NOT NULL | 输入 CSV 表头（JSON 数组） |
| `input_csv_path` | TEXT NOT NULL | 输入 CSV 文件路径 |
| `output_csv_path` | TEXT NOT NULL | 输出 CSV 文件路径 |
| `auto_export` | INTEGER NOT NULL DEFAULT 1 | 是否自动导出结果 |
| `created_at` | INTEGER NOT NULL | 创建时间 |
| `updated_at` | INTEGER NOT NULL | 更新时间 |
| `started_at` | INTEGER | 开始时间 |
| `completed_at` | INTEGER | 完成时间 |
| `last_error` | TEXT | 最后错误信息 |

### 2. agent_job_items 表
存储作业中的单个输入项：

| 字段 | 类型 | 说明 |
|------|------|------|
| `job_id` | TEXT NOT NULL | 所属作业ID |
| `item_id` | TEXT NOT NULL | 项唯一标识 |
| `row_index` | INTEGER NOT NULL | CSV 行号 |
| `source_id` | TEXT | 源标识（可选） |
| `row_json` | TEXT NOT NULL | 行数据（JSON） |
| `status` | TEXT NOT NULL | 状态（pending/running/completed/failed） |
| `assigned_thread_id` | TEXT | 分配的会话ID |
| `attempt_count` | INTEGER NOT NULL DEFAULT 0 | 尝试次数 |
| `result_json` | TEXT | 结果数据（JSON） |
| `last_error` | TEXT | 最后错误 |
| `created_at` | INTEGER NOT NULL | 创建时间 |
| `updated_at` | INTEGER NOT NULL | 更新时间 |
| `completed_at` | INTEGER | 完成时间 |
| `reported_at` | INTEGER | 结果报告时间 |

**主键**: `(job_id, item_id)` - 复合主键
**外键**: `job_id` 引用 `agent_jobs(id)`，级联删除

### 3. 索引设计
- `idx_agent_jobs_status`: 按状态和更新时间查询
- `idx_agent_job_items_status`: 按作业和状态查询待处理项

## 具体技术实现

### 关键流程

#### 作业创建
1. 解析输入 CSV 文件
2. 创建 `agent_jobs` 记录
3. 为每行 CSV 创建 `agent_job_items` 记录

#### 作业执行
1. 认领待处理项（`mark_agent_job_item_running`）
2. 分配会话处理（`set_agent_job_item_thread`）
3. 报告结果（`report_agent_job_item_result`）
4. 标记完成（`mark_agent_job_item_completed`）

#### 状态管理
```rust
pub enum AgentJobStatus {
    Pending,
    Running,
    Completed,
    Failed,
    Cancelled,
}

pub enum AgentJobItemStatus {
    Pending,
    Running,
    Completed,
    Failed,
}
```

### 代码映射
在 `codex-rs/state/src/runtime/agent_jobs.rs` 中：
```rust
pub async fn create_agent_job(
    &self,
    params: &AgentJobCreateParams,
    items: &[AgentJobItemCreateParams],
) -> anyhow::Result<AgentJob> {
    // 插入 agent_jobs
    // 批量插入 agent_job_items
}

pub async fn report_agent_job_item_result(
    &self,
    job_id: &str,
    item_id: &str,
    reporting_thread_id: &str,
    result_json: &Value,
) -> anyhow::Result<bool> {
    // 验证线程所有权
    // 更新结果和状态
}
```

## 关键代码路径与文件引用

### 作业管理
- `codex-rs/state/src/runtime/agent_jobs.rs`:
  - `create_agent_job()`: 创建作业
  - `get_agent_job()`: 查询作业
  - `mark_agent_job_running()`: 标记运行中
  - `mark_agent_job_completed()`: 标记完成

### 作业项管理
- `codex-rs/state/src/runtime/agent_jobs.rs`:
  - `mark_agent_job_item_running()`: 认领项
  - `report_agent_job_item_result()`: 报告结果
  - `get_agent_job_progress()`: 获取进度统计

### 模型定义
- `codex-rs/state/src/model/agent_job.rs`:
  - `AgentJob`: 作业结构体
  - `AgentJobItem`: 作业项结构体
  - `AgentJobStatus`: 状态枚举
  - `AgentJobProgress`: 进度统计

## 依赖与外部交互

### 上游依赖
- `0001_threads.sql`: `assigned_thread_id` 可能引用 `threads.id`

### 下游依赖
- `0015_agent_jobs_max_runtime_seconds.sql`: 添加最大运行时间字段

### 应用层交互
- `codex-rs/core/src/agent_jobs/`: 批处理作业执行逻辑
- `codex-rs/tui/src/components/agent_jobs.rs`: UI 展示

## 风险、边界与改进建议

### 风险
1. **数据一致性**: 作业和项的状态需要保持一致
2. **并发冲突**: 多个实例可能同时认领同一项
3. **存储膨胀**: 大量作业项可能导致表过大

### 边界情况
1. **空作业**: 没有项的作业处理
2. **全部失败**: 所有项都失败时的作业状态
3. **部分完成**: 取消时部分项已完成

### 改进建议
1. 已实施：`0015` 迁移添加了超时控制
2. 考虑添加作业优先级字段
3. 可为长时间运行的作业添加心跳机制
4. 考虑支持作业项的依赖关系
5. 添加作业历史归档功能
