# 0006_memories.sql 研究文档

## 场景与职责

本迁移创建记忆系统（Memory System）的核心表结构，包括 `stage1_outputs` 表和 `jobs` 表。这是 Codex 长期记忆功能的基础，支持从会话 rollout 中提取记忆、存储处理结果，以及管理记忆生成任务。

## 功能点目的

### 1. stage1_outputs 表
存储 Stage 1 记忆提取的输出结果：

| 字段 | 类型 | 说明 |
|------|------|------|
| `thread_id` | TEXT PRIMARY KEY | 关联的会话ID |
| `source_updated_at` | INTEGER NOT NULL | 源 rollout 更新时间 |
| `raw_memory` | TEXT NOT NULL | 提取的原始记忆内容 |
| `rollout_summary` | TEXT NOT NULL | rollout 摘要 |
| `generated_at` | INTEGER NOT NULL | 生成时间戳 |

**索引**: `idx_stage1_outputs_source_updated_at` - 按源更新时间倒序查询

### 2. jobs 表
通用的任务队列表，用于管理记忆提取任务：

| 字段 | 类型 | 说明 |
|------|------|------|
| `kind` | TEXT NOT NULL | 任务类型（如 "memory_stage1"） |
| `job_key` | TEXT NOT NULL | 任务唯一标识 |
| `status` | TEXT NOT NULL | 状态（pending/running/done/error） |
| `worker_id` | TEXT | 执行工作者ID |
| `ownership_token` | TEXT | 所有权令牌（租约） |
| `started_at` | INTEGER | 开始时间 |
| `finished_at` | INTEGER | 完成时间 |
| `lease_until` | INTEGER | 租约过期时间 |
| `retry_at` | INTEGER | 下次重试时间 |
| `retry_remaining` | INTEGER NOT NULL | 剩余重试次数 |
| `last_error` | TEXT | 最后错误信息 |
| `input_watermark` | INTEGER | 输入水位标记 |
| `last_success_watermark` | INTEGER | 最后成功水位 |

**主键**: `(kind, job_key)` - 复合主键
**索引**: `idx_jobs_kind_status_retry_lease` - 任务调度查询优化

## 具体技术实现

### 关键流程

#### Stage 1 记忆提取
1. **任务认领**: `try_claim_stage1_job()` 竞争获取任务执行权
2. **记忆生成**: 从 rollout 文件提取记忆内容
3. **结果存储**: `mark_stage1_job_succeeded()` 写入 `stage1_outputs`
4. **任务完成**: 更新 `jobs` 表状态

#### 任务调度
1. **任务创建**: 检测到需要更新的 rollout 时创建任务
2. **租约机制**: `lease_until` 防止任务被重复执行
3. **重试机制**: `retry_remaining` 和 `retry_at` 控制失败重试
4. **水位标记**: `input_watermark` 和 `last_success_watermark` 跟踪进度

### 代码映射
在 `codex-rs/state/src/runtime/memories.rs` 中：
```rust
const JOB_KIND_MEMORY_STAGE1: &str = "memory_stage1";
const JOB_KIND_MEMORY_CONSOLIDATE_GLOBAL: &str = "memory_consolidate_global";

pub async fn try_claim_stage1_job(
    &self,
    thread_id: ThreadId,
    worker_id: ThreadId,
    source_updated_at: i64,
    lease_seconds: i64,
    max_running_jobs: usize,
) -> anyhow::Result<Stage1JobClaimOutcome> {
    // 复杂的竞争条件处理
}
```

## 关键代码路径与文件引用

### 记忆管理
- `codex-rs/state/src/runtime/memories.rs`:
  - `try_claim_stage1_job()`: 认领 Stage 1 任务
  - `mark_stage1_job_succeeded()`: 标记任务成功
  - `list_stage1_outputs_for_global()`: 查询记忆输出

### 模型定义
- `codex-rs/state/src/model/memories.rs`:
  - `Stage1Output`: 记忆输出结构体
  - `Stage1JobClaimOutcome`: 任务认领结果枚举

### 任务调度
- `codex-rs/state/src/runtime/memories.rs`:
  - `claim_stage1_jobs_for_startup()`: 启动时批量认领任务
  - `try_claim_global_phase2_job()`: Phase 2 全局任务认领

## 依赖与外部交互

### 上游依赖
- `0001_threads.sql`: `stage1_outputs` 外键依赖 `threads.id`

### 下游依赖
- `0009_stage1_outputs_rollout_slug.sql`: 添加 `rollout_slug` 字段
- `0016_memory_usage.sql`: 添加使用统计字段
- `0017_phase2_selection_flag.sql`: 添加 Phase 2 选择标记
- `0018_phase2_selection_snapshot.sql`: 添加选择快照字段

### 应用层交互
- `codex-rs/core/src/memory/`: 记忆生成和整合逻辑
- `codex-rs/tui/src/app.rs`: 记忆功能开关控制

## 风险、边界与改进建议

### 风险
1. **任务竞争**: 多实例并发时可能出现任务重复执行
2. **存储膨胀**: `raw_memory` 和 `rollout_summary` 可能很大
3. **死锁**: 长时间运行的任务可能持有租约过久

### 边界情况
1. **空记忆**: `raw_memory` 和 `rollout_summary` 可能为空字符串
2. **任务过期**: 租约过期后任务可被其他实例认领
3. **重试耗尽**: `retry_remaining` 为 0 后任务不再自动重试

### 改进建议
1. 已实施：后续迁移添加了使用统计、Phase 2 选择等功能
2. 考虑添加 `stage1_outputs` 表的数据保留策略
3. 可为 `jobs` 表添加优先级字段
4. 考虑将 `raw_memory` 和 `rollout_summary` 存储在单独的文件中（如果很大）
