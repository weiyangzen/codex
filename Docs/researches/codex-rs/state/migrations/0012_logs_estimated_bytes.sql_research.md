# 0012_logs_estimated_bytes.sql 研究文档

## 场景与职责

本迁移为 `logs` 表添加 `estimated_bytes` 字段，用于估计每行日志的字节大小。这是实现精确日志分区裁剪的关键，确保每个分区（线程或进程）的日志存储在可控范围内。

## 功能点目的

### 1. 添加 estimated_bytes 字段
- **字段**: `estimated_bytes INTEGER`
- **约束**: `NOT NULL DEFAULT 0`
- **用途**: 估计日志行的字节大小

### 2. 数据回填
迁移包含 UPDATE 语句计算现有日志的大小：
```sql
UPDATE logs
SET estimated_bytes =
    LENGTH(CAST(COALESCE(message, '') AS BLOB))
    + LENGTH(CAST(level AS BLOB))
    + LENGTH(CAST(target AS BLOB))
    + LENGTH(CAST(COALESCE(module_path, '') AS BLOB))
    + LENGTH(CAST(COALESCE(file, '') AS BLOB));
```

**计算逻辑**:
- `message`: 日志消息内容长度
- `level`: 日志级别长度
- `target`: 目标模块长度
- `module_path`: 模块路径长度
- `file`: 源文件名长度

## 具体技术实现

### 关键流程

#### 大小计算
写入日志时实时计算：
```rust
let estimated_bytes = feedback_log_body.map_or(0, String::len) as i64
    + entry.level.len() as i64
    + entry.target.len() as i64
    + entry.module_path.as_ref().map_or(0, String::len) as i64
    + entry.file.as_ref().map_or(0, String::len) as i64;
```

#### 分区裁剪
使用窗口函数按累积大小裁剪：
```sql
DELETE FROM logs
WHERE id IN (
    SELECT id
    FROM (
        SELECT
            id,
            SUM(estimated_bytes) OVER (
                PARTITION BY thread_id
                ORDER BY ts DESC, ts_nanos DESC, id DESC
            ) AS cumulative_bytes,
            ROW_NUMBER() OVER (
                PARTITION BY thread_id
                ORDER BY ts DESC, ts_nanos DESC, id DESC
            ) AS row_number
        FROM logs
        WHERE thread_id IN (...)
    )
    WHERE cumulative_bytes > ? OR row_number > ?
);
```

### 代码映射
在 `codex-rs/state/src/runtime/logs.rs` 中：
```rust
async fn prune_logs_after_insert(
    &self,
    entries: &[LogEntry],
    tx: &mut SqliteConnection,
) -> anyhow::Result<()> {
    // 检查超出限制的线程
    let over_limit_threads_query = QueryBuilder::<Sqlite>::new(
        "SELECT thread_id FROM logs WHERE thread_id IN (...) 
         GROUP BY thread_id 
         HAVING SUM(estimated_bytes) > ? OR COUNT(*) > ?"
    );
    
    // 删除超出限制的旧日志
    // 使用窗口函数计算累积大小
}
```

## 关键代码路径与文件引用

### 日志写入
- `codex-rs/state/src/runtime/logs.rs`:
  - `insert_logs()`: 计算并写入 `estimated_bytes`

### 日志裁剪
- `codex-rs/state/src/runtime/logs.rs`:
  - `prune_logs_after_insert()`: 分区裁剪实现

### 常量定义
- `codex-rs/state/src/runtime.rs`:
```rust
const LOG_PARTITION_SIZE_LIMIT_BYTES: i64 = 10 * 1024 * 1024;  // 10 MiB
const LOG_PARTITION_ROW_LIMIT: i64 = 1_000;
```

## 依赖与外部交互

### 上游依赖
- `0002_logs.sql`: 基础 logs 表
- `0011_logs_partition_prune_indexes.sql`: 分区索引

### 下游依赖
- 无直接下游依赖

### 应用层交互
- 日志裁剪在每次批量插入后自动触发
- 确保每个线程/进程的日志不超过 10 MiB 或 1000 行

## 风险、边界与改进建议

### 风险
1. **大小估计不准确**: 未包含所有字段，实际大小可能不同
2. **性能开销**: 窗口函数计算可能影响插入性能
3. **并发裁剪**: 高并发时可能出现竞态条件

### 边界情况
1. **单条超大日志**: 超过 10 MiB 的单条日志会被直接删除
2. **分区为空**: 裁剪后分区可能为空
3. **大小为 0**: 空消息日志大小为 0

### 改进建议
1. 考虑使用实际存储大小而非估计值
2. 可为裁剪操作添加异步处理
3. 考虑添加裁剪事件日志
4. 监控裁剪频率和数量，优化限制参数
