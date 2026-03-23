# 0010_logs_process_id.sql 研究文档

## 场景与职责

本迁移为 `logs` 表添加 `process_uuid` 字段，用于标识日志所属的进程。这支持按进程聚合日志，特别是在多进程或分布式场景下追踪日志来源。

## 功能点目的

### 1. 添加 process_uuid 字段
- **字段**: `process_uuid TEXT`
- **约束**: 可为空（NULL）
- **用途**: 标识日志所属的进程 UUID

### 2. 创建索引
- **索引名**: `idx_logs_process_uuid`
- **字段**: `process_uuid`
- **用途**: 加速按进程查询日志

## 具体技术实现

### 关键流程
1. **UUID 生成**: 进程启动时生成唯一 UUID
2. **日志关联**: 所有该进程的日志都带有相同的 `process_uuid`
3. **查询聚合**: 可按进程查询所有相关日志

### 代码映射
在 `codex-rs/state/src/log_db.rs` 中：
```rust
pub struct LogDbLayer {
    sender: mpsc::Sender<LogDbCommand>,
    process_uuid: String,  // 进程 UUID
}

pub fn start(state_db: std::sync::Arc<StateRuntime>) -> LogDbLayer {
    let process_uuid = current_process_log_uuid().to_string();  // 生成 UUID
    // ...
}

fn current_process_log_uuid() -> &'static str {
    static PROCESS_LOG_UUID: OnceLock<String> = OnceLock::new();
    PROCESS_LOG_UUID.get_or_init(|| {
        let pid = std::process::id();
        let process_uuid = Uuid::new_v4();
        format!("pid:{pid}:{process_uuid}")  // 格式: pid:<pid>:<uuid>
    })
}
```

在 `codex-rs/state/src/model/log.rs` 中：
```rust
pub struct LogEntry {
    // ...
    pub process_uuid: Option<String>,  // 新增字段
    // ...
}

pub struct LogRow {
    // ...
    pub process_uuid: Option<String>,  // 新增字段
    // ...
}
```

## 关键代码路径与文件引用

### 日志收集
- `codex-rs/state/src/log_db.rs`:
  - `current_process_log_uuid()`: 生成进程 UUID
  - `LogDbLayer`: 包含进程 UUID

### 日志查询
- `codex-rs/state/src/runtime/logs.rs`:
  - `query_feedback_logs()`: 使用 `process_uuid` 聚合日志
  - `prune_logs_after_insert()`: 按进程裁剪日志

### 模型定义
- `codex-rs/state/src/model/log.rs`:
  - `LogEntry`: 包含 `process_uuid`
  - `LogQuery`: 支持按进程筛选

## 依赖与外部交互

### 上游依赖
- `0002_logs.sql`: 基础 logs 表结构
- `0003_logs_thread_id.sql`: 添加 `thread_id` 字段

### 下游依赖
- `0011_logs_partition_prune_indexes.sql`: 添加复合索引包含 `process_uuid`

### 应用层交互
- 反馈收集时使用 `process_uuid` 关联无线程的日志

## 风险、边界与改进建议

### 风险
1. **UUID 格式**: 无格式验证，依赖应用层生成有效 UUID
2. **索引膨胀**: 新增索引可能增加存储和写入开销

### 边界情况
1. **进程重启**: 重启后 UUID 变化，日志分散在不同 UUID 下
2. **线程级日志**: 有 `thread_id` 的日志通常不需要 `process_uuid`
3. **空值处理**: 历史日志或某些场景下可能为空

### 改进建议
1. 已实施：`0011` 迁移优化了索引设计
2. 考虑将 `process_uuid` 和 `thread_id` 的查询逻辑合并优化
3. 可为长时间运行的进程添加会话标识
