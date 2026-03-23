# 0009_stage1_outputs_rollout_slug.sql 研究文档

## 场景与职责

本迁移为 `stage1_outputs` 表添加 `rollout_slug` 字段，用于存储 rollout 摘要的标识 slug。这支持为每个会话的记忆输出生成唯一的、可读的标识符，便于调试和追踪。

## 功能点目的

### 1. 添加 rollout_slug 字段
- **字段**: `rollout_slug TEXT`
- **约束**: 可为空（NULL）
- **用途**: 存储 rollout 摘要的标识 slug

### 使用场景
- **调试追踪**: 通过 slug 快速定位特定会话的记忆输出
- **文件命名**: 用于生成记忆摘要文件的文件名
- **日志关联**: 在日志中标识记忆生成任务

## 具体技术实现

### 关键流程
1. **Slug 生成**: 在 Stage 1 记忆提取时生成唯一 slug
2. **结果存储**: `mark_stage1_job_succeeded()` 时写入 slug
3. **查询使用**: 列出记忆输出时包含 slug 信息

### 代码映射
在 `codex-rs/state/src/runtime/memories.rs` 中：
```rust
pub async fn mark_stage1_job_succeeded(
    &self,
    thread_id: ThreadId,
    ownership_token: &str,
    source_updated_at: i64,
    raw_memory: &str,
    rollout_summary: &str,
    rollout_slug: Option<&str>,  // 新增参数
) -> anyhow::Result<bool> {
    // ...
    sqlx::query(
        r#"
INSERT INTO stage1_outputs (
    thread_id,
    source_updated_at,
    raw_memory,
    rollout_summary,
    rollout_slug,  -- 新增字段
    generated_at
) VALUES (?, ?, ?, ?, ?, ?)
ON CONFLICT(thread_id) DO UPDATE SET
    source_updated_at = excluded.source_updated_at,
    raw_memory = excluded.raw_memory,
    rollout_summary = excluded.rollout_summary,
    rollout_slug = excluded.rollout_slug,
    generated_at = excluded.generated_at
WHERE excluded.source_updated_at >= stage1_outputs.source_updated_at
        "#,
    )
    .bind(rollout_slug)  // 绑定 slug
    // ...
}
```

在 `codex-rs/state/src/model/memories.rs` 中：
```rust
pub struct Stage1Output {
    pub thread_id: ThreadId,
    pub rollout_path: PathBuf,
    pub source_updated_at: DateTime<Utc>,
    pub raw_memory: String,
    pub rollout_summary: String,
    pub rollout_slug: Option<String>,  // 新增字段
    pub cwd: PathBuf,
    pub git_branch: Option<String>,
    pub generated_at: DateTime<Utc>,
}
```

## 关键代码路径与文件引用

### 记忆管理
- `codex-rs/state/src/runtime/memories.rs`:
  - `mark_stage1_job_succeeded()`: 写入记忆输出时包含 slug

### 模型定义
- `codex-rs/state/src/model/memories.rs`:
  - `Stage1Output`: 包含 `rollout_slug` 字段
  - `Stage1OutputRow`: 数据库行映射

### Slug 生成
- `codex-rs/core/src/memory/stage1.rs`: 生成唯一 slug

## 依赖与外部交互

### 上游依赖
- `0006_memories.sql`: 基础 stage1_outputs 表结构

### 下游依赖
- 无直接下游依赖

### 应用层交互
- 记忆摘要文件可能使用 slug 作为文件名的一部分

## 风险、边界与改进建议

### 风险
1. **Slug 冲突**: 如果生成逻辑有问题，可能导致 slug 重复
2. **空值处理**: 历史数据可能没有这个字段

### 边界情况
1. **Slug 格式**: 无格式验证，依赖应用层生成有效值
2. **字符集**: 未限制字符集，可能包含特殊字符

### 改进建议
1. 考虑添加唯一约束（如果 slug 应该全局唯一）
2. 可为 slug 添加索引（如果频繁按 slug 查询）
3. 考虑添加 slug 生成规范文档
