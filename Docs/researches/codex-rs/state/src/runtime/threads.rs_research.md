# threads.rs 研究文档

## 场景与职责

`threads.rs` 是 `codex-state` crate 中 `StateRuntime` 结构体的线程管理模块，负责**线程元数据的持久化存储、查询和更新**。该模块实现了基于 SQLite 的线程状态管理，是 Codex 会话历史功能的核心数据层。

### 核心职责
1. **线程 CRUD 操作**：创建、读取、更新、删除线程元数据
2. **线程列表查询**：支持分页、过滤、排序的线程列表获取
3. **Rollout 数据应用**：将 JSONL rollout 文件中的增量数据应用到线程元数据
4. **动态工具管理**：存储和检索线程级别的动态工具规范
5. **归档管理**：线程的归档/取消归档操作
6. **Git 信息追踪**：记录线程关联的 Git 提交、分支和远程信息

---

## 功能点目的

### 1. 线程查询操作

#### `get_thread()` - 单线程查询
```rust
pub async fn get_thread(&self, id: ThreadId) -> anyhow::Result<Option<ThreadMetadata>>
```
**目的**：通过线程 ID 获取完整的线程元数据

#### `get_thread_memory_mode()` - 内存模式查询
```rust
pub async fn get_thread_memory_mode(&self, id: ThreadId) -> anyhow::Result<Option<String>>
```
**目的**：快速查询线程的记忆模式（enabled/disabled/polluted）

#### `get_dynamic_tools()` - 动态工具查询
```rust
pub async fn get_dynamic_tools(&self, thread_id: ThreadId) -> anyhow::Result<Option<Vec<DynamicToolSpec>>>
```
**目的**：获取线程关联的动态工具规范列表，按位置排序

#### `find_rollout_path_by_id()` - Rollout 路径查询
```rust
pub async fn find_rollout_path_by_id(
    &self,
    id: ThreadId,
    archived_only: Option<bool>,
) -> anyhow::Result<Option<PathBuf>>
```
**目的**：根据线程 ID 查找关联的 rollout 文件路径，支持归档状态过滤

### 2. 线程列表查询

#### `list_threads()` - 分页线程列表
```rust
pub async fn list_threads(
    &self,
    page_size: usize,
    anchor: Option<&crate::Anchor>,
    sort_key: crate::SortKey,
    allowed_sources: &[String],
    model_providers: Option<&[String]>,
    archived_only: bool,
    search_term: Option<&str>,
) -> anyhow::Result<ThreadsPage>
```
**目的**：支持复杂过滤条件的分页查询

**过滤条件**：
- `archived_only`: 仅返回已归档/未归档线程
- `allowed_sources`: 来源白名单过滤（如 `["cli", "vscode"]`）
- `model_providers`: 模型提供商过滤
- `search_term`: 标题模糊搜索
- `anchor`: 基于游标的时间戳+ID 分页

#### `list_thread_ids()` - 轻量 ID 列表
```rust
pub async fn list_thread_ids(
    &self,
    limit: usize,
    anchor: Option<&crate::Anchor>,
    sort_key: crate::SortKey,
    allowed_sources: &[String],
    model_providers: Option<&[String]>,
    archived_only: bool,
) -> anyhow::Result<Vec<ThreadId>>
```
**目的**：仅返回线程 ID 列表，用于批量操作场景

### 3. 线程写入操作

#### `upsert_thread()` - 插入或更新
```rust
pub async fn upsert_thread(&self, metadata: &crate::ThreadMetadata) -> anyhow::Result<()>
```
**目的**：将线程元数据持久化到数据库，存在则更新

**关键行为**：
- 使用 SQLite 的 `ON CONFLICT(id) DO UPDATE` 实现 UPSERT
- 不覆盖 `memory_mode` 字段（保留创建时的值）

#### `insert_thread_if_absent()` - 条件插入
```rust
pub async fn insert_thread_if_absent(
    &self,
    metadata: &crate::ThreadMetadata,
) -> anyhow::Result<bool>
```
**目的**：仅在线程不存在时插入，返回是否实际插入

**实现**：使用 `ON CONFLICT(id) DO NOTHING`

#### `set_thread_memory_mode()` - 内存模式更新
```rust
pub async fn set_thread_memory_mode(
    &self,
    thread_id: ThreadId,
    memory_mode: &str,
) -> anyhow::Result<bool>
```
**目的**：更新线程的记忆模式状态

#### `touch_thread_updated_at()` - 时间戳刷新
```rust
pub async fn touch_thread_updated_at(
    &self,
    thread_id: ThreadId,
    updated_at: DateTime<Utc>,
) -> anyhow::Result<bool>
```
**目的**：仅更新 `updated_at` 字段，不影响其他数据

#### `update_thread_git_info()` - Git 信息更新
```rust
pub async fn update_thread_git_info(
    &self,
    thread_id: ThreadId,
    git_sha: Option<Option<&str>>,
    git_branch: Option<Option<&str>>,
    git_origin_url: Option<Option<&str>>,
) -> anyhow::Result<bool>
```
**目的**：条件更新 Git 相关信息

**参数设计**：
- `Some(Some(value))`: 设置为新值
- `Some(None)`: 清除字段
- `None`: 保持原值不变

### 4. Rollout 数据应用

#### `apply_rollout_items()` - 增量数据应用
```rust
pub async fn apply_rollout_items(
    &self,
    builder: &ThreadMetadataBuilder,
    items: &[RolloutItem],
    new_thread_memory_mode: Option<&str>,
    updated_at_override: Option<DateTime<Utc>>,
) -> anyhow::Result<()>
```
**目的**：将 rollout JSONL 文件解析出的增量数据应用到线程元数据

**处理流程**：
1. 获取现有元数据（如存在）
2. 遍历 `items`，调用 `apply_rollout_item()` 应用每个变更
3. 保留现有 Git 信息（调用 `prefer_existing_git_info()`）
4. 确定 `updated_at`（优先使用 override，其次文件修改时间）
5. 执行 UPSERT
6. 提取并更新 `memory_mode`（如果 rollout 中有）
7. 持久化动态工具（如果 rollout 中有）

#### `persist_dynamic_tools()` - 动态工具持久化
```rust
pub async fn persist_dynamic_tools(
    &self,
    thread_id: ThreadId,
    tools: Option<&[DynamicToolSpec]>,
) -> anyhow::Result<()>
```
**目的**：首次存储线程的动态工具规范（幂等，仅首次写入）

**设计决策**：
- 使用 `ON CONFLICT(thread_id, position) DO NOTHING` 确保不覆盖
- 动态工具在会话开始时定义，不应后续变更

### 5. 归档操作

#### `mark_archived()` / `mark_unarchived()`
```rust
pub async fn mark_archived(&self, thread_id: ThreadId, rollout_path: &Path, archived_at: DateTime<Utc>) -> anyhow::Result<()>
pub async fn mark_unarchived(&self, thread_id: ThreadId, rollout_path: &Path) -> anyhow::Result<()>
```
**目的**：管理线程的归档状态

**行为**：
- 更新 `archived_at` 字段
- 同步更新 `rollout_path` 和 `updated_at`
- 包含 ID 一致性校验（警告日志）

### 6. 删除操作

#### `delete_thread()`
```rust
pub async fn delete_thread(&self, thread_id: ThreadId) -> anyhow::Result<u64>
```
**目的**：从数据库中删除线程元数据
**返回**：受影响的行数

---

## 具体技术实现

### 数据库 Schema

#### threads 表
```sql
CREATE TABLE threads (
    id TEXT PRIMARY KEY,
    rollout_path TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    source TEXT NOT NULL,
    agent_nickname TEXT,
    agent_role TEXT,
    model_provider TEXT NOT NULL,
    model TEXT,
    reasoning_effort TEXT,
    cwd TEXT NOT NULL,
    cli_version TEXT NOT NULL,
    title TEXT NOT NULL,
    sandbox_policy TEXT NOT NULL,
    approval_mode TEXT NOT NULL,
    tokens_used INTEGER NOT NULL,
    first_user_message TEXT NOT NULL,
    archived INTEGER NOT NULL DEFAULT 0,
    archived_at INTEGER,
    git_sha TEXT,
    git_branch TEXT,
    git_origin_url TEXT,
    memory_mode TEXT NOT NULL DEFAULT 'enabled'
);
```

#### thread_dynamic_tools 表
```sql
CREATE TABLE thread_dynamic_tools (
    thread_id TEXT NOT NULL,
    position INTEGER NOT NULL,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    input_schema TEXT NOT NULL,
    defer_loading INTEGER NOT NULL,
    PRIMARY KEY (thread_id, position),
    FOREIGN KEY (thread_id) REFERENCES threads(id)
);
```

### 查询构建辅助函数

#### `push_thread_filters()` - 过滤器构建
```rust
pub(super) fn push_thread_filters<'a>(
    builder: &mut QueryBuilder<'a, Sqlite>,
    archived_only: bool,
    allowed_sources: &'a [String],
    model_providers: Option<&'a [String]>,
    anchor: Option<&crate::Anchor>,
    sort_key: SortKey,
    search_term: Option<&'a str>,
)
```

**构建的 WHERE 条件**：
1. `WHERE 1 = 1` - 基础条件
2. `AND archived = 0/1` - 归档状态
3. `AND first_user_message <> ''` - 排除空消息线程
4. `AND source IN (...)` - 来源过滤
5. `AND model_provider IN (...)` - 提供商过滤
6. `AND instr(title, ?) > 0` - 标题搜索
7. 游标分页条件（复合索引）：
   ```sql
   AND (created_at/updated_at < ? OR (created_at/updated_at = ? AND id < ?))
   ```

#### `push_thread_order_and_limit()` - 排序和限制
```rust
pub(super) fn push_thread_order_and_limit(
    builder: &mut QueryBuilder<'_, Sqlite>,
    sort_key: SortKey,
    limit: usize,
)
```

**排序规则**：
- `SortKey::CreatedAt`: `ORDER BY created_at DESC, id DESC`
- `SortKey::UpdatedAt`: `ORDER BY updated_at DESC, id DESC`

### 数据提取辅助函数

#### `extract_dynamic_tools()`
```rust
pub(super) fn extract_dynamic_tools(items: &[RolloutItem]) -> Option<Option<Vec<DynamicToolSpec>>>
```
从 rollout items 中提取动态工具规范，返回 `Some(Some(tools))` 表示有工具定义。

#### `extract_memory_mode()`
```rust
pub(super) fn extract_memory_mode(items: &[RolloutItem]) -> Option<String>
```
从 rollout items 中提取记忆模式（倒序查找，取最新值）。

---

## 关键代码路径与文件引用

### 类型定义
| 类型 | 定义位置 | 说明 |
|------|----------|------|
| `ThreadMetadata` | `model/thread_metadata.rs` | 线程元数据结构体 |
| `ThreadMetadataBuilder` | `model/thread_metadata.rs` | 元数据构建器 |
| `ThreadRow` | `model/thread_metadata.rs` | 数据库行映射 |
| `SortKey` | `model/thread_metadata.rs` | 排序键枚举 |
| `Anchor` | `model/thread_metadata.rs` | 分页游标 |
| `DynamicToolSpec` | `codex-protocol` | 动态工具规范 |
| `RolloutItem` | `codex-protocol` | Rollout 数据项 |

### 依赖函数
| 函数 | 来源 | 用途 |
|------|------|------|
| `apply_rollout_item()` | `extract.rs` | 应用单个 rollout item |
| `datetime_to_epoch_seconds()` | `model/thread_metadata.rs` | 时间戳转换 |
| `file_modified_time_utc()` | `paths.rs` | 获取文件修改时间 |

### 调用方
| 调用方 | 用途 |
|--------|------|
| `codex-core` | 线程列表展示、归档管理 |
| `runtime/memories.rs` | 记忆系统需要线程元数据 |
| `runtime/backfill.rs` | 历史数据回填 |

---

## 依赖与外部交互

### 内部依赖
```rust
use super::*;  // 从 runtime.rs 导入 StateRuntime 和基础类型
use crate::model::ThreadRow;
use crate::model::datetime_to_epoch_seconds;
use crate::paths::file_modified_time_utc;
```

### 外部 Crate
| Crate | 用途 |
|-------|------|
| `sqlx` | SQLite 异步操作 |
| `chrono` | 时间戳处理 |
| `codex_protocol` | `ThreadId`, `DynamicToolSpec`, `RolloutItem` |
| `serde_json` | JSON 解析（动态工具 schema） |
| `tracing` | 日志记录 |

### 数据库交互
- **连接池**：通过 `self.pool`（`Arc<SqlitePool>`）访问
- **事务**：`persist_dynamic_tools()` 使用显式事务
- **查询构建**：使用 `sqlx::QueryBuilder` 动态构建复杂查询

---

## 风险、边界与改进建议

### 当前风险

1. **SQL 注入风险**
   - 使用 `QueryBuilder::push_bind()` 正确参数化，无直接字符串拼接
   - 但 `search_term` 使用 `instr()` 函数，需确保输入不过长

2. **并发冲突**
   - `apply_rollout_items()` 非原子操作，多个进程同时写入同一线程可能产生竞态
   - 缓解：SQLite WAL 模式 + 应用层协调

3. **分页游标稳定性**
   - 游标基于 `created_at/updated_at + id`，如果线程被更新导致时间戳变化，可能产生重复或遗漏
   - 缓解：使用 `SortKey::CreatedAt` 更稳定（创建时间不变）

4. **Git 信息覆盖**
   - `prefer_existing_git_info()` 逻辑在 `apply_rollout_items()` 中调用，但如果 rollout 中的 Git 信息更新，不会覆盖
   - 这可能是设计意图，但需要文档化

### 边界条件

1. **空 rollout items**
   ```rust
   if items.is_empty() {
       return Ok(());
   }
   ```
   早期返回，避免不必要的数据库查询

2. **动态工具空列表**
   ```rust
   if tools.is_empty() {
       return Ok(());
   }
   ```
   空列表不写入数据库

3. **时间戳精度**
   - 数据库使用秒级 Unix 时间戳（`i64`）
   - 纳秒级精度丢失，但对业务无影响

### 改进建议

1. **添加批量操作**
   ```rust
   pub async fn upsert_threads_batch(&self, metadatas: &[ThreadMetadata]) -> anyhow::Result<()>
   ```
   减少多次往返数据库的开销

2. **添加缓存层**
   对于 `get_thread()` 等高频读取，考虑添加 LRU 缓存

3. **优化分页查询**
   ```rust
   // 当前：查询 page_size + 1 行来判断是否有下一页
   // 建议：使用 COUNT 估算或使用单独的计数查询
   ```

4. **添加索引建议**
   ```sql
   -- 当前可能缺少的索引
   CREATE INDEX idx_threads_memory_mode ON threads(memory_mode);
   CREATE INDEX idx_threads_source ON threads(source);
   ```

5. **错误处理细化**
   当前大量使用 `anyhow::Result`，建议关键操作返回结构化错误：
   ```rust
   pub enum ThreadError {
       NotFound,
       ConcurrentModification,
       Database(sqlx::Error),
   }
   ```

6. **测试覆盖增强**
   - 当前测试覆盖主要功能，但缺少：
     - 并发写入测试
     - 大数据量分页性能测试
     - 动态工具冲突场景测试

### 性能考虑

1. **列表查询优化**
   - `list_threads()` 查询 `page_size + 1` 行来判断是否有下一页
   - 对于大 `page_size`（如 1000），这是合理的
   - 对于小 `page_size`（如 10），额外的 1 行开销可忽略

2. **动态工具查询**
   - 每次调用 `get_dynamic_tools()` 都会执行一次查询
   - 建议调用方在应用层缓存结果

3. **文件系统访问**
   - `apply_rollout_items()` 调用 `file_modified_time_utc()` 读取文件元数据
   - 这是异步操作，不会阻塞线程
