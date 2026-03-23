# 0008_backfill_state.sql 研究文档

## 场景与职责

本迁移创建 `backfill_state` 表，用于管理 rollout 元数据回填（backfill）任务的状态。回填任务负责将历史 rollout 文件的元数据同步到 SQLite 数据库，确保所有会话都能被正确索引和查询。

## 功能点目的

### 1. backfill_state 表结构
创建包含以下字段的单例状态表：

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | INTEGER PRIMARY KEY | 固定为 1 的单例记录 |
| `status` | TEXT NOT NULL | 回填状态（pending/running/complete） |
| `last_watermark` | TEXT | 最后处理的 rollout 路径标记 |
| `last_success_at` | INTEGER | 最后成功完成时间 |
| `updated_at` | INTEGER NOT NULL | 状态更新时间 |

### 2. 单例约束
- **CHECK 约束**: `id = 1` 确保只有一条记录
- **初始化**: 插入默认状态为 `pending` 的记录

### 3. 数据初始化
```sql
INSERT INTO backfill_state (id, status, last_watermark, last_success_at, updated_at)
VALUES (1, 'pending', NULL, NULL, CAST(strftime('%s', 'now') AS INTEGER))
ON CONFLICT(id) DO NOTHING;
```

## 具体技术实现

### 关键流程

#### 回填生命周期
1. **Pending**: 初始状态，等待开始回填
2. **Running**: 正在扫描和处理 rollout 文件
3. **Complete**: 回填完成，所有历史数据已同步

#### 状态转换
```
Pending -> Running: try_claim_backfill() 成功
Running -> Running: checkpoint_backfill() 进度检查点
Running -> Complete: mark_backfill_complete() 完成
```

### 代码映射
在 `codex-rs/state/src/runtime/backfill.rs` 中：
```rust
pub async fn try_claim_backfill(&self, lease_seconds: i64) -> anyhow::Result<bool> {
    let now = Utc::now().timestamp();
    let lease_cutoff = now.saturating_sub(lease_seconds.max(0));
    let result = sqlx::query(
        r#"
UPDATE backfill_state
SET status = ?, updated_at = ?
WHERE id = 1
  AND status != ?
  AND (status != ? OR updated_at <= ?)
        "#,
    )
    .bind(BackfillStatus::Running.as_str())
    .bind(now)
    .bind(BackfillStatus::Complete.as_str())
    .bind(BackfillStatus::Running.as_str())
    .bind(lease_cutoff)
    .execute(self.pool.as_ref())
    .await?;
    Ok(result.rows_affected() == 1)
}
```

## 关键代码路径与文件引用

### 回填管理
- `codex-rs/state/src/runtime/backfill.rs`:
  - `try_claim_backfill()`: 尝试获取回填执行权
  - `mark_backfill_running()`: 标记回填运行中
  - `checkpoint_backfill()`: 记录进度检查点
  - `mark_backfill_complete()`: 标记回填完成
  - `get_backfill_state()`: 获取当前状态

### 模型定义
- `codex-rs/state/src/model/backfill_state.rs`:
  - `BackfillState`: 状态结构体
  - `BackfillStatus`: 状态枚举（Pending/Running/Complete）

### 触发点
- `codex-rs/core/src/rollout.rs`: 启动时检查并触发回填
- `codex-rs/tui/src/app.rs`: TUI 应用启动逻辑

## 依赖与外部交互

### 上游依赖
- `0001_threads.sql`: 回填任务最终写入 threads 表

### 下游依赖
- 无直接下游依赖

### 应用层交互
- 回填任务扫描 `codex_home/sessions/` 目录下的 rollout 文件
- 解析 JSONL 文件并提取元数据写入 `threads` 表

## 风险、边界与改进建议

### 风险
1. **单点故障**: 回填任务只能由一个实例执行
2. **长时间运行**: 大量历史数据可能导致回填耗时很长
3. **租约过期**: 实例崩溃可能导致回填状态卡在 Running

### 边界情况
1. **重复执行**: 租约过期后其他实例可以接管
2. **部分完成**: 通过 `last_watermark` 支持断点续传
3. **并发修改**: 使用数据库锁确保状态一致性

### 改进建议
1. 考虑添加回填进度百分比字段
2. 可记录已扫描文件数量和成功/失败统计
3. 考虑支持增量回填（只处理新文件）
4. 添加回填超时处理机制
