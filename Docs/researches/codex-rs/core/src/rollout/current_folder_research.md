# Research: codex-rs/core/src/rollout

## 场景与职责

`rollout` 模块是 Codex 核心的**会话持久化与发现子系统**，负责以下关键职责：

1. **会话数据持久化**：将用户与 AI 的对话历史（ResponseItem、EventMsg 等）以 JSON Lines 格式写入磁盘，支持会话恢复和审计
2. **会话发现与列表**：提供分页查询能力，支持按创建时间/更新时间排序，支持来源过滤（CLI/VSCode）和模型提供商过滤
3. **会话索引管理**：维护 `session_index.jsonl` 文件，支持通过线程名称查找会话
4. **状态数据库回填**：将历史 rollout 文件迁移到 SQLite 状态数据库（`codex_state` crate）
5. **会话截断**：支持基于用户消息边界的 rollout 截断，用于实现回滚和重建历史

该模块是 Codex 会话生命周期管理的基础设施，直接影响用户体验（会话恢复、历史查看）和数据完整性。

## 功能点目的

### 1. RolloutRecorder（recorder.rs）

**目的**：提供异步、非阻塞的会话记录器，将对话事件持久化到 JSONL 文件。

**核心功能**：
- **延迟写入**：新会话在首次 `persist()` 调用前不创建文件，避免空文件污染
- **异步写入**：通过 Tokio mpsc channel 将 I/O 操作 offload 到独立任务，避免阻塞主线程
- **事件过滤**：根据 `EventPersistenceMode`（Limited/Extended）决定持久化哪些事件类型
- **数据清理**：Extended 模式下截断 ExecCommandEnd 的输出，避免文件过大
- **状态同步**：每次写入后同步更新 SQLite 状态数据库（如果启用）

**关键设计**：
```rust
pub struct RolloutRecorder {
    tx: Sender<RolloutCmd>,           // 命令通道
    rollout_path: PathBuf,            // 目标文件路径
    state_db: Option<StateDbHandle>,  // 可选的状态数据库连接
    event_persistence_mode: EventPersistenceMode,
}
```

### 2. 会话列表与发现（list.rs）

**目的**：高效地列出和查询会话文件，支持复杂的过滤和分页需求。

**核心功能**：
- **分层目录遍历**：按 `YYYY/MM/DD` 结构组织文件，支持高效的时间范围查询
- **双排序模式**：支持按创建时间（文件名解析）或更新时间（文件 mtime）排序
- **分页支持**：基于游标的分页，游标格式为 `"<timestamp>|<uuid>"`
- **多维度过滤**：支持来源过滤（Cli/VSCode/Exec 等）、模型提供商过滤
- **扫描上限**：单次查询最多扫描 10,000 个文件，防止性能退化

**文件命名规范**：
```
rollout-YYYY-MM-DDThh-mm-ss-<uuid>.jsonl
```

**目录结构**：
```
~/.codex/sessions/
├── 2025/
│   ├── 01/
│   │   ├── 03/
│   │   │   ├── rollout-2025-01-03T12-00-00-<uuid>.jsonl
│   │   │   └── ...
```

### 3. 会话索引（session_index.rs）

**目的**：维护线程名称到线程 ID 的映射，支持通过名称查找会话。

**核心设计**：
- **追加写入**：`session_index.jsonl` 采用追加模式，新条目追加到文件末尾
- **反向扫描**：查询时从文件末尾开始扫描，找到最新匹配项
- **批量查询**：支持一次性查询多个线程 ID 的名称

**数据结构**：
```rust
pub struct SessionIndexEntry {
    pub id: ThreadId,
    pub thread_name: String,
    pub updated_at: String,  // RFC3339 格式
}
```

### 4. 元数据提取与回填（metadata.rs）

**目的**：从 rollout 文件中提取会话元数据，并回填到 SQLite 状态数据库。

**核心功能**：
- **元数据提取**：解析 SessionMetaLine，提取线程 ID、创建时间、Git 信息、模型提供商等
- **批量回填**：支持从 `sessions/` 和 `archived_sessions/` 目录批量迁移历史数据
- **断点续传**：通过 watermark 机制支持中断后恢复，避免重复处理
- **租约机制**：使用 15 分钟租约（测试环境 1 秒）防止并发回填冲突

**回填流程**：
1. 检查 backfill 状态，如果已完成则跳过
2. 尝试获取租约，失败则退出
3. 收集所有 rollout 文件路径，按 watermark 排序
4. 批量处理（每批 200 个），提取元数据并写入 SQLite
5. 更新 checkpoint，标记完成

### 5. 持久化策略（policy.rs）

**目的**：定义哪些事件应该被持久化到 rollout 文件，控制文件大小和隐私。

**两种模式**：
- **Limited**：仅持久化核心对话事件（用户消息、助手消息、工具调用等）
- **Extended**：额外持久化执行命令输出、Web 搜索结果等详细事件

**过滤规则示例**：
```rust
fn should_persist_response_item(item: &ResponseItem) -> bool {
    match item {
        ResponseItem::Message { .. }
        | ResponseItem::FunctionCall { .. }
        | ResponseItem::FunctionCallOutput { .. } => true,
        ResponseItem::Other => false,
    }
}
```

### 6. 会话截断（truncation.rs）

**目的**：支持基于用户消息边界的 rollout 截断，用于实现回滚功能。

**核心功能**：
- **用户消息边界检测**：扫描 ResponseItem，识别用户消息位置
- **回滚感知**：处理 `ThreadRolledBack` 事件，调整有效历史范围
- **前缀截断**：支持截断到第 N 个用户消息之前的所有内容

**使用场景**：
- 用户执行 `/undo` 命令时，截断 rollout 到指定位置
- 重建会话历史时，忽略已回滚的内容

### 7. 错误处理（error.rs）

**目的**：将 IO 错误转换为用户友好的错误消息。

**错误映射**：
- `PermissionDenied`：提示用户检查文件所有权
- `NotFound`：提示创建目录或选择不同的 Codex home
- `AlreadyExists`：提示删除或重命名冲突文件
- `InvalidData`：提示数据可能损坏，建议清除 sessions 目录

## 具体技术实现

### 关键数据结构

#### RolloutItem（来自 codex_protocol）
```rust
pub enum RolloutItem {
    SessionMeta(SessionMetaLine),    // 会话元数据（首行）
    ResponseItem(ResponseItem),      // OpenAI API 响应项
    Compacted(CompactedItem),        // 压缩标记
    TurnContext(TurnContextItem),    // 回合上下文
    EventMsg(EventMsg),              // 内部事件消息
}
```

#### SessionMetaLine
```rust
pub struct SessionMetaLine {
    pub meta: SessionMeta,  // 会话基本信息
    pub git: Option<GitInfo>, // Git 仓库信息
}
```

#### SessionMeta
```rust
pub struct SessionMeta {
    pub id: ThreadId,                    // 会话唯一 ID
    pub forked_from_id: Option<ThreadId>, // 分叉来源（如适用）
    pub timestamp: String,               // 创建时间戳
    pub cwd: PathBuf,                    // 工作目录
    pub originator: String,              // 发起者标识
    pub cli_version: String,             // CLI 版本
    pub source: SessionSource,           // 来源（Cli/VSCode/Exec 等）
    pub model_provider: Option<String>,  // 模型提供商
    pub base_instructions: Option<BaseInstructions>, // 基础指令
    pub dynamic_tools: Option<Vec<DynamicToolSpec>>, // 动态工具
    pub memory_mode: Option<String>,     // 记忆模式
}
```

### 关键流程

#### 1. 创建新会话并记录
```rust
// 1. 创建 RolloutRecorder
let recorder = RolloutRecorder::new(
    &config,
    RolloutRecorderParams::Create {
        conversation_id: thread_id,
        forked_from_id: None,
        source: SessionSource::Cli,
        base_instructions,
        dynamic_tools: vec![],
        event_persistence_mode: EventPersistenceMode::Limited,
    },
    state_db_ctx,
    None,
).await?;

// 2. 记录事件（此时文件尚未创建）
recorder.record_items(&items).await?;

// 3. 显式持久化（创建文件并写入）
recorder.persist().await?;
```

#### 2. 恢复会话
```rust
// 1. 加载 rollout 文件
let (items, thread_id, parse_errors) = RolloutRecorder::load_rollout_items(path).await?;

// 2. 重建历史
let history = InitialHistory::Resumed(ResumedHistory {
    conversation_id: thread_id.unwrap(),
    history: items,
    rollout_path: path.to_path_buf(),
});
```

#### 3. 列出会话（文件系统优先）
```rust
let page = get_threads(
    codex_home,
    page_size: 10,
    cursor: None,
    sort_key: ThreadSortKey::CreatedAt,
    allowed_sources: &[SessionSource::Cli, SessionSource::VSCode],
    model_providers: Some(&["openai".to_string()]),
    default_provider: "openai",
).await?;
```

#### 4. 状态数据库回填
```rust
// 在后台任务中执行
pub(crate) async fn backfill_sessions(runtime: &StateRuntime, config: &Config) {
    // 1. 获取租约
    if !runtime.try_claim_backfill(BACKFILL_LEASE_SECONDS).await? {
        return; // 其他进程正在回填
    }
    
    // 2. 收集 rollout 文件
    let mut paths = collect_rollout_paths(&sessions_root).await?;
    paths.sort_by(|a, b| a.watermark.cmp(&b.watermark));
    
    // 3. 批量处理
    for batch in paths.chunks(BACKFILL_BATCH_SIZE) {
        for rollout in batch {
            let outcome = extract_metadata_from_rollout(&rollout.path, default_provider).await?;
            runtime.upsert_thread(&outcome.metadata).await?;
        }
        // 4. 更新 checkpoint
        runtime.checkpoint_backfill(last_watermark).await?;
    }
    
    // 5. 标记完成
    runtime.mark_backfill_complete(last_watermark).await?;
}
```

### 协议与格式

#### Rollout 文件格式（JSON Lines）
每行是一个 JSON 对象，包含 `timestamp` 和 `type`/`payload`：
```jsonl
{"timestamp":"2025-01-27T12:34:56.789Z","type":"session_meta","payload":{"id":"...",...}}
{"timestamp":"2025-01-27T12:34:57.012Z","type":"event_msg","payload":{"type":"user_message",...}}
{"timestamp":"2025-01-27T12:34:58.345Z","type":"response","role":"assistant",...}
```

#### 游标格式
用于分页的游标格式：
```
<ISO8601-timestamp>|<UUID>
```
示例：`"2025-03-04T09:00:00|550e8400-e29b-41d4-a716-446655440000"`

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 | 关键导出 |
|------|------|----------|
| `mod.rs` | 模块入口，定义常量 | `SESSIONS_SUBDIR`, `ARCHIVED_SESSIONS_SUBDIR`, `SessionMeta` |
| `recorder.rs` | 记录器实现 | `RolloutRecorder`, `RolloutRecorderParams` |
| `list.rs` | 会话列表与发现 | `get_threads`, `find_thread_path_by_id_str`, `Cursor`, `ThreadsPage` |
| `metadata.rs` | 元数据提取与回填 | `extract_metadata_from_rollout`, `backfill_sessions` |
| `session_index.rs` | 会话名称索引 | `append_thread_name`, `find_thread_name_by_id`, `find_thread_path_by_name_str` |
| `policy.rs` | 持久化策略 | `EventPersistenceMode`, `is_persisted_response_item` |
| `truncation.rs` | 会话截断 | `user_message_positions_in_rollout`, `truncate_rollout_before_nth_user_message_from_start` |
| `error.rs` | 错误映射 | `map_session_init_error` |

### 测试文件

| 文件 | 测试覆盖 |
|------|----------|
| `tests.rs` | 集成测试：列表分页、排序、过滤、游标、文件系统回退 |
| `recorder_tests.rs` | 记录器单元测试：延迟写入、状态同步、DB 回退 |
| `metadata_tests.rs` | 元数据提取测试、回填测试 |
| `session_index_tests.rs` | 索引扫描测试 |
| `truncation_tests.rs` | 截断逻辑测试 |

### 调用方引用

| 调用方 | 使用方式 |
|--------|----------|
| `codex.rs` | 创建 `RolloutRecorder`，调用 `reconstruct_history_from_rollout` |
| `codex/rollout_reconstruction.rs` | 从 rollout 重建历史，处理 compaction 和 rollback |
| `thread_manager.rs` | 创建线程时初始化 `RolloutRecorder`，恢复会话时加载 rollout |
| `state_db.rs` | 调用 `metadata::backfill_sessions` 进行回填 |
| `codex_thread.rs` | 获取 `rollout_path` 用于展示 |

## 依赖与外部交互

### 内部依赖

```
rollout/
├── codex_protocol::protocol::*    # RolloutItem, SessionMeta, EventMsg 等
├── codex_protocol::models::*      # ResponseItem, BaseInstructions
├── codex_protocol::ThreadId       # 线程 ID 类型
├── codex_state::*                 # SQLite 状态数据库交互
├── crate::config::Config          # 配置读取
├── crate::state_db::*             # 状态数据库句柄和辅助函数
├── crate::git_info::collect_git_info  # Git 信息收集
└── crate::truncate::truncate_text     # 文本截断
```

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `tokio` | 异步文件 I/O、channel、spawn |
| `serde_json` | JSON 序列化/反序列化 |
| `time` / `chrono` | 时间戳处理 |
| `uuid` | UUID 解析和生成 |
| `tempfile` | 测试中的临时目录 |
| `pretty_assertions` | 测试断言美化 |

### 与状态数据库的交互

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   RolloutRecorder │────▶│   state_db.rs   │────▶│  codex_state    │
│   (文件系统写入)   │     │  (适配层)        │     │  (SQLite DB)    │
└─────────────────┘     └─────────────────┘     └─────────────────┘
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
  sessions/*.jsonl         读取修复/回填           threads 表
```

**关键交互点**：
1. **写入时同步**：`sync_thread_state_after_write` 在每次写入 rollout 后更新 SQLite
2. **读取修复**：`read_repair_rollout_path` 当文件系统路径与 DB 不一致时修复 DB
3. **回填迁移**：`backfill_sessions` 将历史 rollout 文件迁移到 SQLite

## 风险、边界与改进建议

### 已知风险

1. **文件系统与 DB 不一致**
   - **风险**：用户手动删除或移动 rollout 文件后，DB 中仍保留旧路径
   - **缓解**：`find_thread_path_by_id_str` 会检查文件是否存在，不存在时回退到文件系统搜索并修复 DB
   - **代码**：`list.rs:1190-1244`

2. **并发回填冲突**
   - **风险**：多个进程同时启动时可能并发执行回填
   - **缓解**：使用 15 分钟租约机制，`try_claim_backfill` 确保只有一个进程执行回填
   - **代码**：`metadata.rs:151-167`

3. **大文件扫描性能**
   - **风险**：`updated_at` 排序需要读取所有文件的 mtime，目录庞大时性能下降
   - **缓解**：设置 10,000 文件扫描上限，未来可通过缓存优化
   - **代码**：`list.rs:103`, `list.rs:486-543`

4. **游标稳定性**
   - **风险**：同一秒内创建多个会话时，仅靠时间戳无法区分顺序
   - **缓解**：游标包含 UUID，按 `(timestamp desc, uuid desc)` 排序确保稳定
   - **代码**：`list.rs:852`, `list.rs:677-689`

### 边界情况

1. **空 rollout 文件**：`load_rollout_items` 会返回错误，提示空文件
2. **损坏的 JSON**：解析错误被记录，继续处理后续行，返回解析错误计数
3. **缺失 SessionMeta**：`builder_from_items` 会回退到从文件名解析时间戳和 UUID
4. **跨时区**：所有时间戳使用 UTC，文件名使用本地时间但格式化为无时区字符串

### 改进建议

1. **性能优化**
   - 为 `updated_at` 排序维护内存缓存或单独索引文件，避免每次扫描 mtime
   - 使用 `notify` crate 监听文件系统变化，增量更新缓存

2. **数据完整性**
   - 添加 rollout 文件校验和，检测文件损坏
   - 定期后台任务验证 DB 与文件系统一致性

3. **可观测性**
   - 添加更多指标：写入延迟、文件大小分布、回填进度
   - 为关键错误（如 DB 写入失败）添加结构化日志

4. **代码简化**
   - `list.rs` 超过 1200 行，可考虑将 `traverse_directories_for_paths_created` 和 `traverse_directories_for_paths_updated` 提取到子模块
   - 合并 `traverse_flat_paths_*` 和 `traverse_directories_for_paths_*` 的重复逻辑

5. **测试覆盖**
   - 添加压力测试：模拟 10,000+ 文件的目录结构
   - 添加并发测试：验证回填租约机制的正确性
   - 添加故障注入测试：模拟磁盘满、权限错误等场景

### 技术债务

1. **TODO 标记**：`list.rs:1181` 有 SQLite 迁移阶段的 TODO，需要清理
2. **注释掉的测试**：`tests.rs:91-215` 有大量注释掉的测试，需要修复或删除
3. **硬编码常量**：`MAX_SCAN_FILES = 10000` 等常量应考虑移到配置中

---

*Generated: 2026-03-21*
*Researcher: Kimi Code CLI*
