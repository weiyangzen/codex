# 0016_memory_usage.sql 研究文档

## 场景与职责

本迁移为 `stage1_outputs` 表添加使用统计字段，支持追踪记忆的使用情况。这为记忆系统的 LRU（Least Recently Used）淘汰策略和 Phase 2 选择提供数据支持。

## 功能点目的

### 1. 添加 usage_count 字段
- **字段**: `usage_count INTEGER`
- **约束**: 可为空（NULL），表示从未使用
- **用途**: 记录记忆被引用的次数

### 2. 添加 last_usage 字段
- **字段**: `last_usage INTEGER`
- **约束**: 可为空（NULL），表示从未使用
- **用途**: 记录最后一次使用时间戳

### 使用场景
- **使用统计**: 了解哪些记忆被频繁使用
- **淘汰策略**: 基于使用频率和时间决定保留哪些记忆
- **Phase 2 选择**: 优先选择使用频率高的记忆进行整合

## 具体技术实现

### 关键流程

#### 使用记录
当记忆被引用时更新统计：
```rust
pub async fn record_stage1_output_usage(
    &self,
    thread_ids: &[ThreadId],
) -> anyhow::Result<usize> {
    let now = Utc::now().timestamp();
    
    for thread_id in thread_ids {
        sqlx::query(
            r#"
UPDATE stage1_outputs
SET
    usage_count = COALESCE(usage_count, 0) + 1,
    last_usage = ?
WHERE thread_id = ?
            "#,
        )
        .bind(now)
        .bind(thread_id.to_string())
        .execute(&mut *tx)
        .await?;
    }
}
```

#### Phase 2 选择
使用统计影响 Phase 2 记忆选择：
```rust
pub async fn get_phase2_input_selection(
    &self,
    n: usize,
    max_unused_days: i64,
) -> anyhow::Result<Phase2InputSelection> {
    let cutoff = (Utc::now() - Duration::days(max_unused_days.max(0))).timestamp();
    
    let current_rows = sqlx::query(
        r#"
SELECT ...
FROM stage1_outputs AS so
LEFT JOIN threads AS t ON t.id = so.thread_id
WHERE t.memory_mode = 'enabled'
  AND (length(trim(so.raw_memory)) > 0 OR length(trim(so.rollout_summary)) > 0)
  AND (
        (so.last_usage IS NOT NULL AND so.last_usage >= ?)
        OR (so.last_usage IS NULL AND so.source_updated_at >= ?)
  )
ORDER BY
    COALESCE(so.usage_count, 0) DESC,
    COALESCE(so.last_usage, so.source_updated_at) DESC,
    so.source_updated_at DESC,
    so.thread_id DESC
LIMIT ?
        "#,
    )
    .bind(cutoff)
    .bind(cutoff)
    .bind(n as i64)
    // ...
}
```

### 代码映射
在 `codex-rs/state/src/runtime/memories.rs` 中：
```rust
/// Record usage for cited stage-1 outputs.
pub async fn record_stage1_output_usage(
    &self,
    thread_ids: &[ThreadId],
) -> anyhow::Result<usize> {
    // 更新 usage_count 和 last_usage
}

/// Prunes stale stage-1 outputs while preserving the latest phase-2 baseline.
pub async fn prune_stage1_outputs_for_retention(
    &self,
    max_unused_days: i64,
    limit: usize,
) -> anyhow::Result<usize> {
    let cutoff = (Utc::now() - Duration::days(max_unused_days.max(0))).timestamp();
    
    sqlx::query(
        r#"
DELETE FROM stage1_outputs
WHERE thread_id IN (
    SELECT thread_id
    FROM stage1_outputs
    WHERE selected_for_phase2 = 0
      AND COALESCE(last_usage, source_updated_at) < ?
    ORDER BY
      COALESCE(last_usage, source_updated_at) ASC,
      source_updated_at ASC,
      thread_id ASC
    LIMIT ?
)
        "#,
    )
    .bind(cutoff)
    .bind(limit as i64)
    .execute(self.pool.as_ref())
    .await?;
}
```

## 关键代码路径与文件引用

### 记忆管理
- `codex-rs/state/src/runtime/memories.rs`:
  - `record_stage1_output_usage()`: 记录使用
  - `get_phase2_input_selection()`: Phase 2 选择
  - `prune_stage1_outputs_for_retention()`: 保留策略裁剪

### 模型定义
- `codex-rs/state/src/model/memories.rs`:
  - `Stage1Output`: 记忆输出结构体

## 依赖与外部交互

### 上游依赖
- `0006_memories.sql`: 基础 stage1_outputs 表
- `0009_stage1_outputs_rollout_slug.sql`: 可选依赖

### 下游依赖
- `0017_phase2_selection_flag.sql`: Phase 2 选择标记

### 应用层交互
- 记忆被引用时（如生成回复时）调用 `record_stage1_output_usage`
- 定期清理任务使用这些字段决定删除哪些记忆

## 风险、边界与改进建议

### 风险
1. **计数溢出**: `usage_count` 理论上可能溢出（实际不太可能）
2. **并发更新**: 高频使用可能导致更新竞争
3. **时间精度**: 秒级精度可能不够精细

### 边界情况
1. **NULL 处理**: `COALESCE(last_usage, source_updated_at)` 处理未使用过的记忆
2. **从未使用**: `usage_count` 和 `last_usage` 都为 NULL
3. **Phase 2 保留**: `selected_for_phase2 = 1` 的记忆不会被裁剪

### 改进建议
1. 考虑添加首次使用时间字段
2. 可为使用统计添加索引（如果频繁按使用排序）
3. 考虑使用加权计数（近期使用权重更高）
4. 添加使用统计的监控和告警
