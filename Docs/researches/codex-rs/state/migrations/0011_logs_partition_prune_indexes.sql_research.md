# 0011_logs_partition_prune_indexes.sql 研究文档

## 场景与职责

本迁移优化 `logs` 表的索引设计，添加复合索引支持高效的分区裁剪（partition pruning）。这是日志存储优化的关键步骤，支持按线程或进程分区存储和裁剪日志。

## 功能点目的

### 1. 复合索引 idx_logs_thread_id_ts
- **索引名**: `idx_logs_thread_id_ts`
- **字段**: `(thread_id, ts DESC, ts_nanos DESC, id DESC)`
- **用途**: 优化按线程查询最新日志

### 2. 部分索引 idx_logs_process_uuid_threadless_ts
- **索引名**: `idx_logs_process_uuid_threadless_ts`
- **字段**: `(process_uuid, ts DESC, ts_nanos DESC, id DESC)`
- **条件**: `WHERE thread_id IS NULL`
- **用途**: 优化查询无线程关联的进程日志

## 具体技术实现

### 索引设计原理

#### 复合索引 idx_logs_thread_id_ts
```sql
CREATE INDEX idx_logs_thread_id_ts 
ON logs(thread_id, ts DESC, ts_nanos DESC, id DESC);
```
- **最左前缀**: `thread_id` 支持等值查询
- **排序优化**: `ts DESC` 支持按时间倒序
- **唯一性**: `ts_nanos` 和 `id` 确保排序稳定性

#### 部分索引 idx_logs_process_uuid_threadless_ts
```sql
CREATE INDEX idx_logs_process_uuid_threadless_ts 
ON logs(process_uuid, ts DESC, ts_nanos DESC, id DESC)
WHERE thread_id IS NULL;
```
- **条件过滤**: 只索引 `thread_id IS NULL` 的行
- **节省空间**: 有线程的日志不进入此索引
- **进程聚合**: 支持按进程查询系统级日志

### 代码映射
在 `codex-rs/state/src/runtime/logs.rs` 中：
```rust
async fn prune_logs_after_insert(
    &self,
    entries: &[LogEntry],
    tx: &mut SqliteConnection,
) -> anyhow::Result<()> {
    // 按 thread_id 分区裁剪
    let thread_ids: BTreeSet<&str> = entries
        .iter()
        .filter_map(|entry| entry.thread_id.as_deref())
        .collect();
    
    // 按 process_uuid 分区裁剪（threadless 日志）
    let threadless_process_uuids: BTreeSet<&str> = entries
        .iter()
        .filter(|entry| entry.thread_id.is_none())
        .filter_map(|entry| entry.process_uuid.as_deref())
        .collect();
    
    // 使用窗口函数和索引进行裁剪
}
```

## 关键代码路径与文件引用

### 日志裁剪
- `codex-rs/state/src/runtime/logs.rs`:
  - `prune_logs_after_insert()`: 分区裁剪逻辑
  - 使用 `SUM(estimated_bytes) OVER (PARTITION BY thread_id)` 计算累积大小

### 日志查询
- `codex-rs/state/src/runtime/logs.rs`:
  - `query_feedback_logs()`: 使用索引优化查询
  - `query_logs()`: 支持按线程和进程筛选

### 常量定义
- `codex-rs/state/src/runtime.rs`:
```rust
const LOG_PARTITION_SIZE_LIMIT_BYTES: i64 = 10 * 1024 * 1024;  // 10 MiB
const LOG_PARTITION_ROW_LIMIT: i64 = 1_000;
```

## 依赖与外部交互

### 上游依赖
- `0002_logs.sql`: 基础 logs 表
- `0003_logs_thread_id.sql`: `thread_id` 字段
- `0010_logs_process_id.sql`: `process_uuid` 字段

### 下游依赖
- `0012_logs_estimated_bytes.sql`: 添加 `estimated_bytes` 字段支持裁剪

### 应用层交互
- 日志裁剪在每次插入后自动执行
- 反馈收集使用这些索引优化查询

## 风险、边界与改进建议

### 风险
1. **索引维护开销**: 复合索引增加写入开销
2. **存储空间**: 多个索引占用额外磁盘空间
3. **查询计划**: 依赖 SQLite 优化器选择正确索引

### 边界情况
1. **NULL 值处理**: `thread_id IS NULL` 的日志走不同索引
2. **分区边界**: 恰好达到限制时的裁剪行为
3. **并发写入**: 批量插入时的索引更新

### 改进建议
1. 已实施：`0012` 迁移添加了 `estimated_bytes` 支持精确裁剪
2. 考虑监控索引使用效率
3. 可为高频查询添加覆盖索引
4. 定期 ANALYZE 优化查询计划
