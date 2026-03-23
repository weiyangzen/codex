# 0003_logs_thread_id.sql 研究文档

## 场景与职责

本迁移为 `logs` 表添加 `thread_id` 字段，建立日志与会话（thread）之间的关联关系。这使得可以按会话查询相关日志，支持会话级别的日志追踪和反馈收集。

## 功能点目的

### 1. 添加 thread_id 字段
- **字段**: `thread_id TEXT`
- **用途**: 标识日志所属的会话ID
- **可为空**: 是（系统级日志可能没有关联会话）

### 2. 创建索引
- **索引名**: `idx_logs_thread_id`
- **字段**: `thread_id`
- **用途**: 加速按会话查询日志

## 具体技术实现

### 关键流程
1. **日志关联**: 写入日志时，从 tracing span 的 `thread_id` 字段提取并存储
2. **查询优化**: 通过索引快速定位特定会话的所有日志
3. **反馈收集**: `query_feedback_logs()` 使用此字段聚合会话相关日志

### 代码映射
在 `codex-rs/state/src/log_db.rs` 中：
```rust
struct SpanLogContext {
    name: String,
    formatted_fields: String,
    thread_id: Option<String>,  // 从 span 属性提取
}
```

写入时绑定：
```rust
.bind(&entry.thread_id)
```

## 关键代码路径与文件引用

### 日志写入
- `codex-rs/state/src/log_db.rs`:
  - `SpanFieldVisitor`: 从 span 属性提取 `thread_id`
  - `event_thread_id()`: 从事件上下文获取线程ID

### 日志查询
- `codex-rs/state/src/runtime/logs.rs`:
  - `query_feedback_logs()`: 使用 `thread_id` 查询会话日志
  - `push_log_filters()`: 支持按 `thread_ids` 筛选

### 反馈功能
- `codex-rs/tui/src/components/feedback.rs`: 收集反馈时查询相关日志

## 依赖与外部交互

### 上游依赖
- `0002_logs.sql`: 基础日志表结构

### 下游依赖
- `0010_logs_process_id.sql`: 进一步添加 `process_uuid` 字段
- `0011_logs_partition_prune_indexes.sql`: 添加复合索引 `(thread_id, ts, ts_nanos, id)`

### 关联表
- `threads.id`: 外键关系（逻辑上，非数据库约束）

## 风险、边界与改进建议

### 风险
1. **索引膨胀**: 大量日志可能导致索引过大
2. **NULL 值处理**: `thread_id IS NULL` 的日志需要特殊处理

### 边界情况
1. **线程切换**: 异步任务可能在不同线程执行，需要正确传递上下文
2. **长会话**: 活跃会话可能积累大量日志，查询时需要限制

### 改进建议
1. 已实施：`0011_logs_partition_prune_indexes.sql` 添加了复合索引优化查询
2. 考虑添加外键约束（如果需要严格的数据完整性）
3. 可为高频查询添加覆盖索引
