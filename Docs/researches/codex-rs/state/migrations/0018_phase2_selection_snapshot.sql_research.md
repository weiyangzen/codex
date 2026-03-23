# 0018_phase2_selection_snapshot.sql 研究文档

## 场景与职责

本迁移添加 `selected_for_phase2_source_updated_at` 字段和 `threads.memory_mode` 字段，用于精确追踪 Phase 2 选择的状态和支持记忆模式控制。

## 功能点目的

### 1. 添加 selected_for_phase2_source_updated_at 字段
- **字段**: `selected_for_phase2_source_updated_at INTEGER`
- **约束**: 可为空（NULL）
- **用途**: 记录被选中时的源更新时间戳

### 2. 添加 threads.memory_mode 字段
- **字段**: `memory_mode TEXT`
- **约束**: `NOT NULL DEFAULT 'enabled'`
- **用途**: 控制会话的记忆功能模式

### 使用场景

#### 选择快照
- **精确匹配**: 判断记忆内容是否在选中后发生变化
- **增量更新**: 只处理源有变化的记忆
- **一致性检查**: 验证 Phase 2 整合的输入一致性

#### 记忆模式
- **enabled**: 正常生成和使用记忆
- **disabled**: 不生成新记忆，不使用现有记忆
- **polluted**: 记忆被污染，需要重新整合

## 具体技术实现

### 关键流程

#### 选择差异检测
```rust
pub async fn get_phase2_input_selection(
    &self,
    n: usize,
    max_unused_days: i64,
) -> anyhow::Result<Phase2InputSelection> {
    // ...
    for row in current_rows {
        let thread_id = row.try_get::<String, _>("thread_id")?;
        let source_updated_at = row.try_get::<i64, _>("source_updated_at")?;
        
        // 检查是否完全匹配（内容未变化）
        if row.try_get::<i64, _>("selected_for_phase2")? != 0
            && row.try_get::<Option<i64>, _>("selected_for_phase2_source_updated_at")?
                == Some(source_updated_at)
        {
            retained_thread_ids.push(ThreadId::try_from(thread_id.clone())?);
        }
        // ...
    }
    // ...
}
```

#### 记忆模式控制
```rust
pub async fn set_thread_memory_mode(
    &self,
    thread_id: ThreadId,
    memory_mode: &str,
) -> anyhow::Result<bool> {
    sqlx::query("UPDATE threads SET memory_mode = ? WHERE id = ?")
        .bind(memory_mode)
        .bind(thread_id.to_string())
        .execute(self.pool.as_ref())
        .await?;
}

pub async fn get_thread_memory_mode(&self, id: ThreadId) -> anyhow::Result<Option<String>> {
    sqlx::query_scalar("SELECT memory_mode FROM threads WHERE id = ?")
        .bind(id.to_string())
        .fetch_optional(self.pool.as_ref())
        .await
}
```

#### 污染标记
```rust
pub async fn mark_thread_memory_mode_polluted(
    &self,
    thread_id: ThreadId,
) -> anyhow::Result<bool> {
    let mut tx = self.pool.begin().await?;
    
    // 标记为污染
    let rows_affected = sqlx::query(
        "UPDATE threads SET memory_mode = 'polluted' WHERE id = ? AND memory_mode != 'polluted'"
    )
    .bind(thread_id.to_string())
    .execute(&mut *tx)
    .await?
    .rows_affected();
    
    // 如果之前被选中，触发 Phase 2 重新整合
    let selected_for_phase2 = sqlx::query_scalar::<_, i64>(
        "SELECT selected_for_phase2 FROM stage1_outputs WHERE thread_id = ?"
    )
    .bind(thread_id.to_string())
    .fetch_optional(&mut *tx)
    .await?
    .unwrap_or(0);
    
    if selected_for_phase2 != 0 {
        enqueue_global_consolidation_with_executor(&mut *tx, now).await?;
    }
    
    tx.commit().await?;
}
```

## 关键代码路径与文件引用

### 记忆管理
- `codex-rs/state/src/runtime/memories.rs`:
  - `get_phase2_input_selection()`: 使用快照检测变化
  - `mark_thread_memory_mode_polluted()`: 污染处理

### 线程管理
- `codex-rs/state/src/runtime/threads.rs`:
  - `set_thread_memory_mode()`: 设置记忆模式
  - `get_thread_memory_mode()`: 查询记忆模式
  - `insert_thread_if_absent()`: 默认设置为 'enabled'

## 依赖与外部交互

### 上游依赖
- `0001_threads.sql`: 基础 threads 表
- `0017_phase2_selection_flag.sql`: Phase 2 选择标记

### 下游依赖
- 无直接下游依赖

### 应用层交互
- 用户可通过命令切换记忆模式
- 检测到记忆不一致时自动标记为 polluted

## 风险、边界与改进建议

### 风险
1. **模式值错误**: 无约束检查，可能写入无效值
2. **快照不一致**: 如果 Phase 2 失败，快照可能不准确

### 边界情况
1. **NULL 快照**: 从未被选中的记忆快照为 NULL
2. **模式切换**: 频繁切换模式可能导致不一致
3. **污染传播**: 污染会话的记忆可能影响全局整合

### 改进建议
1. 考虑为 memory_mode 添加 CHECK 约束
2. 可添加模式切换历史记录
3. 考虑支持更多模式（如只读模式）
4. 添加记忆健康检查工具
