# thread_metadata.rs 研究文档

## 场景与职责

`thread_metadata.rs` 是 Codex 状态管理模块中负责**线程元数据管理**的核心数据模型文件。它定义了对话线程（Thread）的完整元数据结构，支持从 rollout 文件提取、持久化到 SQLite、以及分页查询等功能。

### 核心职责
1. **线程元数据定义**：定义线程的核心属性（ID、路径、时间戳、模型信息等）
2. **构建器模式**：提供 `ThreadMetadataBuilder` 用于安全构建元数据
3. **分页支持**：定义 `Anchor` 和 `ThreadsPage` 支持键集分页
4. **差异检测**：提供 `diff_fields` 方法检测元数据变更
5. **数据库映射**：提供 `ThreadRow` 与领域模型的转换

### 业务背景
Codex 的每个对话会话对应一个线程（Thread），线程元数据用于：
- 会话列表展示（标题、时间、模型等）
- 会话归档/恢复
- 记忆系统关联
- Git 上下文追踪

## 功能点目的

### 1. SortKey - 排序键

```rust
pub enum SortKey {
    CreatedAt,  // 按创建时间排序
    UpdatedAt,  // 按更新时间排序
}
```

用于控制线程列表的排序方式。

### 2. Anchor - 分页锚点

```rust
pub struct Anchor {
    pub ts: DateTime<Utc>,  // 时间戳组件
    pub id: Uuid,           // UUID 组件
}
```

**设计要点**：
- 键集分页（Keyset Pagination）避免深页性能问题
- 复合键（ts + id）确保唯一性和排序稳定性
- 支持 `CreatedAt` 和 `UpdatedAt` 两种排序

### 3. ThreadsPage - 分页结果

```rust
pub struct ThreadsPage {
    pub items: Vec<ThreadMetadata>,      // 当前页数据
    pub next_anchor: Option<Anchor>,     // 下一页锚点
    pub num_scanned_rows: usize,         // 扫描行数（用于调试）
}
```

### 4. ExtractionOutcome - 提取结果

```rust
pub struct ExtractionOutcome {
    pub metadata: ThreadMetadata,        // 提取的元数据
    pub memory_mode: Option<String>,     // 记忆模式（来自 rollout）
    pub parse_errors: usize,             // 解析错误数
}
```

用于从 rollout 文件提取元数据时返回完整结果。

### 5. ThreadMetadata - 线程元数据（核心结构）

```rust
pub struct ThreadMetadata {
    pub id: ThreadId,                    // 线程唯一标识
    pub rollout_path: PathBuf,           // rollout 文件绝对路径
    pub created_at: DateTime<Utc>,       // 创建时间
    pub updated_at: DateTime<Utc>,       // 最后更新时间
    pub source: String,                  // 会话来源（cli, vscode 等）
    pub agent_nickname: Option<String>,  // Agent 昵称（子 Agent）
    pub agent_role: Option<String>,      // Agent 角色
    pub model_provider: String,          // 模型提供商
    pub model: Option<String>,           // 具体模型（如 gpt-5）
    pub reasoning_effort: Option<ReasoningEffort>, // 推理努力程度
    pub cwd: PathBuf,                    // 工作目录
    pub cli_version: String,             // CLI 版本
    pub title: String,                   // 会话标题
    pub sandbox_policy: String,          // 沙箱策略
    pub approval_mode: String,           // 审批模式
    pub tokens_used: i64,                // Token 使用量
    pub first_user_message: Option<String>, // 首条用户消息预览
    pub archived_at: Option<DateTime<Utc>>, // 归档时间（None 表示未归档）
    pub git_sha: Option<String>,         // Git commit SHA
    pub git_branch: Option<String>,     // Git 分支
    pub git_origin_url: Option<String>, // Git 远程地址
}
```

**字段设计要点**：
- `id` 使用 `ThreadId` 类型（来自 `codex_protocol`）
- `source`, `sandbox_policy`, `approval_mode` 使用 String 而非枚举，便于扩展
- `archived_at` 作为归档标记，支持取消归档
- Git 相关字段支持代码上下文追踪

### 6. ThreadMetadataBuilder - 构建器

```rust
pub struct ThreadMetadataBuilder {
    pub id: ThreadId,
    pub rollout_path: PathBuf,
    pub created_at: DateTime<Utc>,
    pub updated_at: Option<DateTime<Utc>>,
    pub source: SessionSource,           // 使用枚举而非 String
    pub agent_nickname: Option<String>,
    pub agent_role: Option<String>,
    pub model_provider: Option<String>,
    pub cwd: PathBuf,
    pub cli_version: Option<String>,
    pub sandbox_policy: SandboxPolicy,   // 使用枚举
    pub approval_mode: AskForApproval,   // 使用枚举
    pub archived_at: Option<DateTime<Utc>>,
    pub git_sha: Option<String>,
    pub git_branch: Option<String>,
    pub git_origin_url: Option<String>,
}
```

**构建器模式优势**：
- 强制设置必需字段（`new()` 方法）
- 可选字段使用 `Option` 表示
- `build()` 方法提供合理的默认值填充

### 7. BackfillStats - 回填统计

```rust
pub struct BackfillStats {
    pub scanned: usize,    // 扫描的 rollout 文件数
    pub upserted: usize,   // 成功插入/更新的记录数
    pub failed: usize,     // 失败的记录数
}
```

## 具体技术实现

### 时间戳规范化

```rust
fn canonicalize_datetime(dt: DateTime<Utc>) -> DateTime<Utc> {
    dt.with_nanosecond(0).unwrap_or(dt)
}
```

- SQLite 只存储秒级时间戳
- 规范化确保内存和数据库的一致性

### Git 信息保留策略

```rust
impl ThreadMetadata {
    /// 保留现有非空 Git 字段
    pub fn prefer_existing_git_info(&mut self, existing: &Self) {
        if existing.git_sha.is_some() {
            self.git_sha = existing.git_sha.clone();
        }
        if existing.git_branch.is_some() {
            self.git_branch = existing.git_branch.clone();
        }
        if existing.git_origin_url.is_some() {
            self.git_origin_url = existing.git_origin_url.clone();
        }
    }
}
```

**场景**：rollout 文件中的 Git 信息可能较旧，数据库中的信息可能来自更近期的更新。

### 字段差异检测

```rust
pub fn diff_fields(&self, other: &Self) -> Vec<&'static str> {
    let mut diffs = Vec::new();
    if self.id != other.id { diffs.push("id"); }
    if self.rollout_path != other.rollout_path { diffs.push("rollout_path"); }
    // ... 检查所有字段
    diffs
}
```

**用途**：
- 检测元数据变更，决定是否需要更新数据库
- 调试和日志记录

### 数据库行转换

```rust
#[derive(Debug)]
pub(crate) struct ThreadRow {
    id: String,
    rollout_path: String,
    created_at: i64,
    updated_at: i64,
    source: String,
    agent_nickname: Option<String>,
    agent_role: Option<String>,
    model_provider: String,
    model: Option<String>,
    reasoning_effort: Option<String>,
    cwd: String,
    cli_version: String,
    title: String,
    sandbox_policy: String,
    approval_mode: String,
    tokens_used: i64,
    first_user_message: String,
    archived_at: Option<i64>,
    git_sha: Option<String>,
    git_branch: Option<String>,
    git_origin_url: Option<String>,
}
```

**转换要点**：
- `first_user_message` 数据库中存储空字符串表示 None
- `reasoning_effort` 需要字符串解析为枚举
- 时间戳需要秒级转换

### 锚点生成

```rust
pub(crate) fn anchor_from_item(item: &ThreadMetadata, sort_key: SortKey) -> Option<Anchor> {
    let id = Uuid::parse_str(&item.id.to_string()).ok()?;
    let ts = match sort_key {
        SortKey::CreatedAt => item.created_at,
        SortKey::UpdatedAt => item.updated_at,
    };
    Some(Anchor { ts, id })
}
```

## 关键代码路径与文件引用

### 模型定义位置
- **文件**：`codex-rs/state/src/model/thread_metadata.rs`（本文件，512 行）
- **导出**：`codex-rs/state/src/model/mod.rs` 通过 `pub use thread_metadata::*` 导出

### 数据库操作实现
- **文件**：`codex-rs/state/src/runtime/threads.rs`（约 1000+ 行）
- **核心方法**：
  - `get_thread()` - 获取单个线程
  - `list_threads()` - 分页列表
  - `list_thread_ids()` - ID 列表
  - `upsert_thread()` - 插入或更新
  - `insert_thread_if_absent()` - 不存在时插入
  - `mark_archived()` / `mark_unarchived()` - 归档操作
  - `delete_thread()` - 删除
  - `apply_rollout_items()` - 应用 rollout 增量更新

### 元数据提取
- **文件**：`codex-rs/state/src/extract.rs`
- **核心函数**：
  - `apply_rollout_item()` - 将 rollout 项应用到元数据
  - `rollout_item_affects_thread_metadata()` - 判断项是否影响元数据

### 数据库 Schema
- **初始迁移**：`codex-rs/state/migrations/0001_threads.sql`

```sql
CREATE TABLE threads (
    id TEXT PRIMARY KEY,
    rollout_path TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    source TEXT NOT NULL,
    model_provider TEXT NOT NULL,
    cwd TEXT NOT NULL,
    title TEXT NOT NULL,
    sandbox_policy TEXT NOT NULL,
    approval_mode TEXT NOT NULL,
    tokens_used INTEGER NOT NULL DEFAULT 0,
    has_user_event INTEGER NOT NULL DEFAULT 0,
    archived INTEGER NOT NULL DEFAULT 0,
    archived_at INTEGER,
    git_sha TEXT,
    git_branch TEXT,
    git_origin_url TEXT
);
```

- **升级迁移**：
  - `0005_threads_cli_version.sql` - 添加 cli_version
  - `0007_threads_first_user_message.sql` - 添加 first_user_message
  - `0013_threads_agent_nickname.sql` - 添加 agent_nickname, agent_role
  - `0020_threads_model_reasoning_effort.sql` - 添加 model, reasoning_effort

### 调用方
- **Rollout 元数据**：`codex-rs/core/src/rollout/metadata.rs`
- **状态数据库**：`codex-rs/core/src/state_db.rs`
- **记忆系统**：`codex-rs/core/src/memories/*.rs`
- **App Server**：`codex-rs/app-server-protocol/src/protocol/v2.rs`（API 协议）
- **TUI**：`codex-rs/tui/src/lib.rs`

### 测试
- **单元测试**：本文件底部包含测试模块（约 80 行）
  - `thread_row_parses_reasoning_effort` - 解析推理努力程度
  - `thread_row_ignores_unknown_reasoning_effort_values` - 容错处理

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `anyhow` | 错误处理 |
| `chrono` | 时间戳处理（DateTime, Timelike, Utc） |
| `codex_protocol::ThreadId` | 线程 ID 类型 |
| `codex_protocol::openai_models::ReasoningEffort` | 推理努力程度枚举 |
| `codex_protocol::protocol::*` | SessionSource, AskForApproval, SandboxPolicy |
| `sqlx::Row` / `SqliteRow` | 数据库行访问 |
| `uuid::Uuid` | UUID 生成和解析 |

### 内部模块交互
```
thread_metadata.rs (模型定义)
    ↓
mod.rs (统一导出)
    ↓
runtime/threads.rs (数据库操作)
    ↓
extract.rs (rollout 提取)
    ↓
lib.rs (公开 API)
```

## 风险、边界与改进建议

### 风险点

1. **时间戳精度丢失**
   - 数据库只存储秒级时间戳
   - **风险**：同一秒内创建的线程排序可能不稳定
   - **缓解**：使用复合键（ts + id）确保排序稳定

2. **字符串枚举**
   - `source`, `sandbox_policy`, `approval_mode` 使用 String 而非数据库枚举
   - **风险**：数据不一致（如 "cli" vs "CLI"）
   - **缓解**：在应用层统一转换（`extract::enum_to_string`）

3. **Git 信息过时**
   - Git 信息只在创建时捕获，后续分支切换不会更新
   - **风险**：归档线程的 Git 信息可能误导

### 边界情况

1. **空标题处理**
   - `first_user_message` 用于生成标题
   - 如果用户只发送图片，使用 `"[Image]"` 占位符

2. **模型信息缺失**
   - `model` 和 `reasoning_effort` 是可选的
   - 旧 rollout 可能没有这些信息

3. **归档状态变更**
   - 归档和取消归档都会更新 `updated_at`
   - 这会影响按 UpdatedAt 排序的结果

### 改进建议

1. **数据库枚举**
   - 当前字符串枚举可能不一致
   - 建议：使用 SQLite CHECK 约束验证枚举值

2. **索引优化**
   - 当前索引：`(created_at DESC, id DESC)`, `(updated_at DESC, id DESC)`
   - 建议：如果频繁按 source 或 model_provider 过滤，增加复合索引

3. **软删除**
   - 当前 `delete_thread()` 是物理删除
   - 建议：考虑软删除支持数据恢复

4. **元数据版本控制**
   - 当前更新会覆盖旧值
   - 建议：保留历史版本用于审计

5. **批量操作**
   - 当前 API 主要是单线程操作
   - 建议：增加批量插入/更新接口

### 代码质量

1. **diff_fields 维护**
   - 新增字段时需要同步更新 `diff_fields`
   - 建议：使用宏自动生成或编译时检查

2. **测试覆盖**
   - 当前只有 2 个测试用例
   - 建议：增加 Builder 和转换逻辑的测试

3. **文档完善**
   - 部分字段缺少文档注释
   - 建议：为所有公共字段添加文档
