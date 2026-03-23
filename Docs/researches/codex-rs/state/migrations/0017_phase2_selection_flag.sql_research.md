# 0017_phase2_selection_flag.sql 研究文档

## 场景与职责

本迁移为 `stage1_outputs` 表添加 `selected_for_phase2` 字段，用于标记哪些 Stage 1 记忆输出被选中参与 Phase 2 全局整合。这是记忆系统多阶段处理的关键标记。

## 功能点目的

### 1. 添加 selected_for_phase2 字段
- **字段**: `selected_for_phase2 INTEGER`
- **约束**: `NOT NULL DEFAULT 0`
- **用途**: 标记是否被选中参与 Phase 2 整合

### 使用场景
- **Phase 2 选择**: 标记当前被选中的记忆集合
- **增量更新**: 识别新增和移除的记忆
- **保留保护**: 被选中的记忆不会被裁剪

## 具体技术实现

### 关键流程

#### Phase 2 选择
```rust
pub async fn get_phase2_input_selection(
    &self,
    n: usize,
    max_unused_days: i64,
) -> anyhow::Result<Phase2InputSelection> {
    // 查询当前选择
    let current_rows = sqlx::query(
        r#"
SELECT
    so.thread_id,
    ...
    so.selected_for_phase2,
FROM stage1_outputs AS so
LEFT JOIN threads AS t ON t.id = so.thread_id
WHERE t.memory_mode = 'enabled'
  AND (length(trim(so.raw_memory)) > 0 OR length(trim(so.rollout_summary)) > 0)
  AND (...)
ORDER BY ...
LIMIT ?
        "#,
    ).fetch_all(self.pool.as_ref()).await?;
    
    // 查询之前的选择
    let previous_rows = sqlx::query(
        r#"
SELECT ...
FROM stage1_outputs AS so
LEFT JOIN threads AS t ON t.id = so.thread_id
WHERE so.selected_for_phase2 = 1
ORDER BY so.source_updated_at DESC, so.thread_id DESC
        "#,
    ).fetch_all(self.pool.as_ref()).await?;
    
    // 计算差异
}
```

#### 标记选择
Phase 2 整合成功后更新标记：
```rust
pub async fn mark_phase2_job_succeeded(
    &self,
    ownership_token: &str,
    selected_thread_ids: &[ThreadId],
) -> anyhow::Result<bool> {
    // 清除之前的选择
    sqlx::query("UPDATE stage1_outputs SET selected_for_phase2 = 0")
        .execute(&mut *tx)
        .await?;
    
    // 标记新的选择
    for thread_id in selected_thread_ids {
        sqlx::query(
            "UPDATE stage1_outputs SET selected_for_phase2 = 1 WHERE thread_id = ?"
        )
        .bind(thread_id.to_string())
        .execute(&mut *tx)
        .await?;
    }
}
```

### 代码映射
在 `codex-rs/state/src/runtime/memories.rs` 中：
```rust
/// Prunes stale stage-1 outputs while preserving the latest phase-2 baseline.
pub async fn prune_stage1_outputs_for_retention(
    &self,
    max_unused_days: i64,
    limit: usize,
) -> anyhow::Result<usize> {
    sqlx::query(
        r#"
DELETE FROM stage1_outputs
WHERE thread_id IN (
    SELECT thread_id
    FROM stage1_outputs
    WHERE selected_for_phase2 = 0  -- 只删除未被选中的
      AND COALESCE(last_usage, source_updated_at) < ?
    ORDER BY ...
    LIMIT ?
)
        "#,
    )
    // ...
}
```

## 关键代码路径与文件引用

### 记忆管理
- `codex-rs/state/src/runtime/memories.rs`:
  - `get_phase2_input_selection()`: 获取选择差异
  - `prune_stage1_outputs_for_retention()`: 保留策略（跳过选中的）

### Phase 2 整合
- `codex-rs/core/src/memory/phase2.rs`: Phase 2 整合逻辑

## 依赖与外部交互

### 上游依赖
- `0006_memories.sql`: 基础 stage1_outputs 表
- `0016_memory_usage.sql`: 使用统计字段

### 下游依赖
- `0018_phase2_selection_snapshot.sql`: 添加选择快照时间戳

### 应用层交互
- Phase 2 整合任务读取和更新此标记
- 保留策略跳过被选中的记忆

## 风险、边界与改进建议

### 风险
1. **标记不一致**: 如果 Phase 2 失败，标记可能不准确
2. **全表更新**: 清除和设置标记需要更新多行

### 边界情况
1. **空选择**: 如果没有记忆被选中，所有标记为 0
2. **全部选中**: 所有记忆都被选中
3. **Phase 2 失败**: 标记保持上次成功的状态

### 改进建议
1. 已实施：`0018` 迁移添加了选择快照时间戳
2. 考虑添加选择原因或优先级字段
3. 可为选择历史添加审计日志
4. 考虑支持多版本选择（A/B 测试）
