# 0002_logs_feedback_log_body.sql 研究文档

## 场景与职责

`0002_logs_feedback_log_body.sql` 是 Codex 项目日志数据库的第二次迁移，负责将 `logs` 表的 `message` 字段重命名为 `feedback_log_body`。这是架构演进中的重要一步，反映了日志存储从简单的消息文本向结构化反馈日志内容的转变。

该迁移采用"重建表"策略（rename → create → migrate → drop），确保数据零丢失的同时完成 schema 变更。这种设计支持 Codex 的反馈日志功能，该功能将 tracing span 层级结构和格式化字段整合到单个字段中，供 LLM 反馈上下文使用。

## 功能点目的

### 1. 字段语义澄清
将 `message` 重命名为 `feedback_log_body`，更准确地反映该字段的用途：
- **旧语义 (`message`)**: 简单的日志消息文本
- **新语义 (`feedback_log_body`)**: 包含 span 层级、格式化字段和事件消息的完整反馈日志内容

### 2. 支持反馈日志格式化
配合 `codex-rs/state/src/log_db.rs` 中的 `format_feedback_log_body()` 函数，生成结构化的日志内容：

```
span_name{field1=value1,field2=value2}:child_span{}: actual message
```

这种格式保留了调用链上下文，对 LLM 理解执行流程至关重要。

### 3. 索引优化调整
迁移重新创建了 4 个索引，并移除了 1 个索引：

**保留/重建的索引**:
- `idx_logs_ts`: 时间戳降序索引
- `idx_logs_thread_id`: 线程 ID 索引
- `idx_logs_thread_id_ts`: 线程+时间复合索引
- `idx_logs_process_uuid_threadless_ts`: 无线程日志的部分索引

**移除的索引**:
- `idx_logs_process_uuid`: 通用进程 UUID 索引（被部分索引替代）

## 具体技术实现

### 迁移策略：重建表（Table Rebuild）

SQLite 的 `ALTER TABLE` 限制较多（不支持直接重命名列），因此采用完整的表重建流程：

```sql
-- 1. 重命名旧表
ALTER TABLE logs RENAME TO logs_old;

-- 2. 创建新表结构（使用 feedback_log_body 替代 message）
CREATE TABLE logs (...);

-- 3. 迁移数据（message → feedback_log_body）
INSERT INTO logs (...) SELECT ..., message, ... FROM logs_old;

-- 4. 删除旧表
DROP TABLE logs_old;

-- 5. 重建索引
CREATE INDEX ...;
```

### 数据迁移映射

```sql
INSERT INTO logs (
    id, ts, ts_nanos, level, target,
    feedback_log_body,  -- ← 接收旧表的 message
    module_path, file, line, thread_id, process_uuid, estimated_bytes
)
SELECT
    id, ts, ts_nanos, level, target,
    message,  -- ← 从旧表读取
    module_path, file, line, thread_id, process_uuid, estimated_bytes
FROM logs_old;
```

### 关键代码路径

#### 1. 迁移执行路径
```
codex-rs/state/src/runtime.rs:StateRuntime::init()
  └── open_sqlite(&logs_path, &LOGS_MIGRATOR)
        └── LOGS_MIGRATOR.run(&pool)
              └── 按顺序执行 logs_migrations/*.sql
                    ├── 0001_logs.sql（已执行过则跳过）
                    └── 0002_logs_feedback_log_body.sql
```

#### 2. 反馈日志体生成
`codex-rs/state/src/log_db.rs:format_feedback_log_body()`:

```rust
fn format_feedback_log_body<S>(event: &Event<'_>, ctx: &Context<'_, S>) -> String {
    let mut feedback_log_body = String::new();
    // 遍历 span 层级，构建前缀
    if let Some(scope) = ctx.event_scope(event) {
        for span in scope.from_root() {
            feedback_log_body.push_str(&log_context.name);
            if !log_context.formatted_fields.is_empty() {
                feedback_log_body.push('{');
                feedback_log_body.push_str(&log_context.formatted_fields);
                feedback_log_body.push('}');
            }
            feedback_log_body.push(':');
        }
    }
    // 追加事件消息
    feedback_log_body.push_str(&format_fields(event));
    feedback_log_body
}
```

#### 3. 插入操作适配
`codex-rs/state/src/runtime/logs.rs:insert_logs()`:

```rust
let feedback_log_body = entry.feedback_log_body.as_ref().or(entry.message.as_ref());
let estimated_bytes = feedback_log_body.map_or(0, String::len) as i64
    + entry.level.len() as i64
    + entry.target.len() as i64
    + ...;
row.push_bind(feedback_log_body)
```

注意：插入时优先使用 `feedback_log_body`，若不存在则回退到 `message`，保持向后兼容。

#### 4. 查询操作适配
`codex-rs/state/src/runtime/logs.rs:query_logs()`:

```sql
SELECT ..., feedback_log_body AS message, ... FROM logs
```

查询时将 `feedback_log_body` 别名为 `message`，保持 `LogRow` 结构体的兼容性。

### 数据模型演进

**Rust 结构体（`codex-rs/state/src/model/log.rs`）**:

```rust
pub struct LogEntry {
    pub ts: i64,
    pub ts_nanos: i64,
    pub level: String,
    pub target: String,
    pub message: Option<String>,           // 保留用于向后兼容
    pub feedback_log_body: Option<String>, // 新的主字段
    pub thread_id: Option<String>,
    pub process_uuid: Option<String>,
    pub module_path: Option<String>,
    pub file: Option<String>,
    pub line: Option<i64>,
}

pub struct LogRow {
    pub id: i64,
    pub ts: i64,
    pub ts_nanos: i64,
    pub level: String,
    pub target: String,
    pub message: Option<String>,  // 查询时映射 feedback_log_body
    pub thread_id: Option<String>,
    pub process_uuid: Option<String>,
    pub file: Option<String>,
    pub line: Option<i64>,
}
```

## 依赖与外部交互

### 上游依赖

| 组件 | 路径 | 关系 |
|------|------|------|
| 0001_logs.sql | 同目录 | 前置迁移，提供基础表结构 |
| sqlx | Cargo.toml | 迁移框架 |
| StateRuntime | src/runtime.rs | 触发迁移执行 |

### 下游消费者

| 组件 | 路径 | 用途 |
|------|------|------|
| log_db.rs | src/log_db.rs | 生成 feedback_log_body 内容 |
| runtime/logs.rs | src/runtime/logs.rs | 插入/查询日志 |
| logs_client.rs | src/bin/logs_client.rs | 读取并显示日志 |

### API 兼容性

- **查询兼容性**: `LogRow.message` 继续存在，消费者无需修改
- **插入兼容性**: `LogEntry` 同时保留 `message` 和 `feedback_log_body`，支持渐进迁移

## 风险、边界与改进建议

### 已知风险

1. **迁移耗时**: 重建表操作在大型数据库上可能耗时较长，会阻塞应用启动。虽然日志数据库通常有 10 天保留期限制，但在极端情况下仍需注意。

2. **事务安全**: 整个迁移在单个事务中执行，若中途失败可能导致数据库处于中间状态（但 sqlx 迁移框架会处理失败回滚）。

3. **索引重建开销**: 4 个索引的重建会增加迁移时间，特别是在已有大量日志的情况下。

### 边界条件

- **NULL 处理**: `feedback_log_body` 保持可为空，与 `message` 一致
- **数据类型不变**: 所有字段的数据类型保持不变，仅列名变更
- **约束继承**: 主键、非空约束完全继承自旧表

### 测试覆盖

`codex-rs/state/src/runtime/logs.rs` 包含专门的迁移测试：

```rust
#[tokio::test]
async fn init_migrates_message_only_logs_db_to_feedback_log_body_schema() {
    // 1. 仅应用 0001 迁移（旧 schema）
    let old_logs_migrator = Migrator {
        migrations: Cow::Owned(vec![LOGS_MIGRATOR.migrations[0].clone()]),
        ...
    };
    
    // 2. 插入旧格式数据
    sqlx::query("INSERT INTO logs ... message ...")
    
    // 3. 初始化 StateRuntime（触发完整迁移）
    let runtime = StateRuntime::init(...).await?;
    
    // 4. 验证数据完整性和新 schema
    assert_eq!(rows[0].message.as_deref(), Some("legacy-body"));
    assert!(columns.contains(&"feedback_log_body".to_string()));
    assert!(!columns.contains(&"message".to_string()));
}
```

### 改进建议

1. **添加迁移进度日志**: 大型数据库迁移时可添加进度指示，改善用户体验。

2. **考虑在线迁移**: 对于未来的 schema 变更，可考虑使用 "添加新列 → 双写 → 迁移数据 → 删除旧列" 的在线策略，减少停机时间。

3. **索引优化**: `idx_logs_process_uuid` 的移除是正确的，但应在注释中说明原因（被部分索引替代）。

4. **反馈日志体大小限制**: 当前 `estimated_bytes` 计算包含 `feedback_log_body`，但应考虑对单个日志条目的大小设置上限，防止异常大的日志内容。

5. **schema 版本文档**: 建议在代码中添加 schema 版本常量，与迁移文件对应：
   ```rust
   // src/lib.rs
   pub const LOGS_DB_SCHEMA_VERSION: u32 = 2; // 对应 0002 迁移
   ```

### 相关文件引用

```
codex-rs/state/
├── logs_migrations/
│   ├── 0001_logs.sql                     # 前置迁移
│   └── 0002_logs_feedback_log_body.sql   # 本文件
├── src/
│   ├── migrations.rs                     # LOGS_MIGRATOR 定义
│   ├── runtime.rs                        # 数据库初始化和迁移触发
│   ├── runtime/logs.rs                   # 日志插入/查询/修剪
│   ├── log_db.rs                         # tracing 层和 feedback_log_body 生成
│   ├── model/log.rs                      # LogEntry/LogRow 数据模型
│   └── bin/logs_client.rs                # CLI 日志查看工具
└── Cargo.toml
```

---

**文件路径**: `codex-rs/state/logs_migrations/0002_logs_feedback_log_body.sql`  
**前置依赖**: `0001_logs.sql`  
**关联功能**: 反馈日志（Feedback Logs）、Tracing 集成、LLM 上下文构建
