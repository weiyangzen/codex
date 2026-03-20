# codex-rs/core/src/rollout 模块研究文档

## 目录
- [场景与职责](#场景与职责)
- [功能点目的](#功能点目的)
- [具体技术实现](#具体技术实现)
- [关键代码路径与文件引用](#关键代码路径与文件引用)
- [依赖与外部交互](#依赖与外部交互)
- [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

`rollout` 模块是 Codex 核心库中负责**会话持久化与发现**的关键组件。其主要职责包括：

1. **会话记录持久化**：将 AI 会话的所有事件、消息、工具调用等记录到 JSONL 格式的 rollout 文件中，支持会话的完整回放与恢复
2. **会话发现与列表**：提供高效的会话列表查询能力，支持分页、排序（按创建时间/更新时间）、过滤（按来源/模型提供商）
3. **会话恢复**：支持从 rollout 文件恢复会话历史，包括 fork/branch 场景
4. **元数据提取**：从 rollout 文件中提取会话元数据，用于 SQLite 状态数据库的同步
5. **会话索引管理**：维护 `session_index.jsonl` 文件，支持通过会话名称查找会话

### 典型使用场景

- **TUI/CLI 会话恢复**：用户可以通过 `~/.codex/sessions/` 目录下的 rollout 文件恢复历史会话
- **多代理协作**：子代理（sub-agent） spawned by AgentControl 的会话记录与追踪
- **会话归档**：将不活跃的会话移动到 `archived_sessions` 目录
- **状态数据库回填**：将历史 rollout 文件迁移到 SQLite 数据库进行统一查询

---

## 功能点目的

### 1. RolloutRecorder - 会话记录器

**目的**：提供异步、线程安全的会话事件记录能力。

**核心特性**：
- **延迟写入**：新会话在第一次 `persist()` 调用前不会创建文件，避免空会话文件
- **事件过滤**：根据 `EventPersistenceMode`（Limited/Extended）决定哪些事件需要持久化
- **自动截断**：Extended 模式下对 `ExecCommandEnd` 的输出进行截断（10KB 限制），避免 rollout 文件过大
- **双写同步**：写入 rollout 文件的同时同步更新 SQLite 状态数据库

### 2. 会话列表与发现 (list.rs)

**目的**：高效查询和发现历史会话。

**核心特性**：
- **分层目录结构**：`~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<uuid>.jsonl`
- **双排序策略**：
  - `CreatedAt`：基于文件名中的时间戳（高效，无需文件系统 stat）
  - `UpdatedAt`：基于文件 mtime（需要扫描所有文件）
- **游标分页**：支持稳定的分页查询，格式为 `"<timestamp>|<uuid>"`
- **扫描上限**：单次查询最多扫描 10,000 个文件，防止性能退化
- **DB 回退**：优先使用 SQLite 查询，失败时回退到文件系统扫描

### 3. 会话索引 (session_index.rs)

**目的**：支持通过会话名称（而非 UUID）查找会话。

**核心特性**：
- **追加写入**：`session_index.jsonl` 采用追加模式，最新条目优先
- **反向扫描**：从文件末尾开始扫描，提高最新条目的查找效率
- **批量查询**：支持一次性查询多个会话 ID 的名称

### 4. 元数据提取与回填 (metadata.rs)

**目的**：从 rollout 文件提取元数据并同步到 SQLite 数据库。

**核心特性**：
- **Backfill（回填）机制**：启动时检查并迁移历史 rollout 文件到 SQLite
- **租约机制**：防止多个进程同时进行回填（15 分钟租约，测试环境 1 秒）
- **断点续传**：通过 watermark 机制支持中断后恢复
- **批次处理**：每批处理 200 个 rollout 文件

### 5. 事件持久化策略 (policy.rs)

**目的**：定义哪些事件应该被持久化到 rollout 文件。

**核心策略**：
- **Limited 模式**：只持久化核心事件（用户消息、代理消息、Token 计数、上下文压缩等）
- **Extended 模式**：额外持久化错误、Guardian 评估、工具调用结果等诊断信息
- **Memories 专用过滤**：为记忆系统提供独立的事件过滤逻辑

### 6. 会话截断 (truncation.rs)

**目的**：支持基于"用户回合"边界的会话截断，用于 fork/rollback 场景。

**核心特性**：
- **用户消息边界检测**：识别 `ResponseItem::Message` 中的用户消息
- **Rollback 标记处理**：正确处理 `ThreadRolledBack` 事件，调整有效历史范围

---

## 具体技术实现

### 关键数据结构

#### RolloutRecorder
```rust
pub struct RolloutRecorder {
    tx: Sender<RolloutCmd>,           // 命令通道
    pub(crate) rollout_path: PathBuf, // rollout 文件路径
    state_db: Option<StateDbHandle>,  // SQLite 状态数据库句柄
    event_persistence_mode: EventPersistenceMode,
}
```

#### RolloutItem (协议层定义)
```rust
pub enum RolloutItem {
    SessionMeta(SessionMetaLine),    // 会话元数据
    ResponseItem(ResponseItem),      // API 响应项
    Compacted(CompactedItem),        // 压缩标记
    TurnContext(TurnContextItem),    // 回合上下文
    EventMsg(EventMsg),              // 事件消息
}
```

#### SessionMetaLine
```rust
pub struct SessionMetaLine {
    #[serde(flatten)]
    pub meta: SessionMeta,            // 会话元数据
    #[serde(skip_serializing_if = "Option::is_none")]
    pub git: Option<GitInfo>,         // Git 信息
}
```

#### SessionMeta
```rust
pub struct SessionMeta {
    pub id: ThreadId,
    pub forked_from_id: Option<ThreadId>,
    pub timestamp: String,
    pub cwd: PathBuf,
    pub originator: String,
    pub cli_version: String,
    pub agent_nickname: Option<String>,
    pub agent_role: Option<String>,
    pub source: SessionSource,
    pub model_provider: Option<String>,
    pub base_instructions: Option<BaseInstructions>,
    pub dynamic_tools: Option<Vec<DynamicToolSpec>>,
    pub memory_mode: Option<String>,
}
```

### 关键流程

#### 1. Rollout 文件创建流程

```
RolloutRecorder::new()
  ├── Create 模式（新会话）
  │     ├── precompute_log_file_info() - 计算文件路径
  │     │     └── ~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<uuid>.jsonl
  │     ├── 构建 SessionMeta（延迟写入）
  │     └── spawn rollout_writer() 任务
  └── Resume 模式（恢复会话）
        ├── 立即打开现有文件（append 模式）
        └── spawn rollout_writer() 任务
```

#### 2. 事件写入流程

```
RolloutRecorder::record_items(items)
  ├── 根据 EventPersistenceMode 过滤事件
  ├── sanitize_rollout_item_for_persistence() - 截断大输出
  ├── tx.send(RolloutCmd::AddItems(filtered))
  └── rollout_writer 任务异步写入
        ├── 如果 writer 未初始化，缓冲到内存
        └── 否则直接写入 JSONL 文件
```

#### 3. 持久化触发流程

```
RolloutRecorder::persist()
  ├── tx.send(RolloutCmd::Persist { ack })
  └── rollout_writer 处理
        ├── 如果文件未创建
        │     ├── open_log_file() - 创建目录和文件
        │     ├── write_session_meta() - 写入会话元数据
        │     └── 刷新缓冲的事件
        └── ack.send(()) - 确认完成
```

#### 4. 会话列表查询流程

```
RolloutRecorder::list_threads()
  ├── get_threads() / get_threads_in_root() - 文件系统扫描
  │     ├── traverse_directories_for_paths() - 嵌套目录布局
  │     │     └── walk_rollout_files() - 按 YYYY/MM/DD 遍历
  │     └── 或 traverse_flat_paths() - 扁平目录布局（归档）
  ├── 如果 SQLite 可用
  │     ├── read_repair_rollout_path() - 修复 stale 路径
  │     └── list_threads_db() - DB 查询
  └── 否则返回文件系统结果
```

#### 5. 元数据回填流程

```
metadata::backfill_sessions()
  ├── 获取 backfill 状态
  ├── try_claim_backfill() - 获取租约
  ├── collect_rollout_paths() - 收集所有 rollout 路径
  ├── 按 watermark 排序并过滤已处理
  ├── 分批处理
  │     ├── extract_metadata_from_rollout() - 提取元数据
  │     ├── runtime.upsert_thread() - 写入 SQLite
  │     └── checkpoint_backfill() - 更新 watermark
  └── mark_backfill_complete() - 标记完成
```

### 文件格式

#### Rollout 文件 (JSONL)

```jsonl
{"timestamp":"2025-01-27T12:34:56.789Z","type":"session_meta","payload":{"id":"...","timestamp":"2025-01-27T12-34-56",...}}
{"timestamp":"2025-01-27T12:34:57.012Z","type":"event_msg","payload":{"type":"user_message","message":"Hello",...}}
{"timestamp":"2025-01-27T12:34:58.345Z","type":"response_item","payload":{"role":"assistant",...}}
```

#### Session Index 文件 (JSONL)

```jsonl
{"id":"<uuid>","thread_name":"My Session","updated_at":"2025-01-27T12:34:56Z"}
```

---

## 关键代码路径与文件引用

### 模块结构

```
codex-rs/core/src/rollout/
├── mod.rs              # 模块入口，公共导出
├── error.rs            # 会话初始化错误映射
├── list.rs             # 会话列表查询（~1270 行）
├── metadata.rs         # 元数据提取与回填（~440 行）
├── metadata_tests.rs   # 元数据测试
├── policy.rs           # 事件持久化策略（~185 行）
├── recorder.rs         # RolloutRecorder 实现（~1100 行）
├── recorder_tests.rs   # 记录器测试
├── session_index.rs    # 会话索引管理（~233 行）
├── session_index_tests.rs
├── truncation.rs       # 会话截断工具（~73 行）
├── truncation_tests.rs
└── tests.rs            # 集成测试（~1000+ 行）
```

### 关键函数与方法

| 函数/方法 | 文件 | 用途 |
|-----------|------|------|
| `RolloutRecorder::new()` | recorder.rs:370 | 创建或恢复 rollout 记录器 |
| `RolloutRecorder::record_items()` | recorder.rs:484 | 记录事件到 rollout |
| `RolloutRecorder::persist()` | recorder.rs:509 | 触发文件持久化 |
| `RolloutRecorder::list_threads()` | recorder.rs:165 | 查询会话列表 |
| `get_threads()` | list.rs:303 | 文件系统扫描实现 |
| `walk_rollout_files()` | list.rs:935 | 递归遍历 rollout 目录 |
| `parse_timestamp_uuid_from_filename()` | list.rs:856 | 解析文件名中的时间戳和 UUID |
| `backfill_sessions()` | metadata.rs:133 | 回填历史会话到 SQLite |
| `extract_metadata_from_rollout()` | metadata.rs:95 | 从 rollout 提取元数据 |
| `apply_rollout_item()` | state/src/extract.rs:15 | 应用 rollout 项到元数据 |
| `append_thread_name()` | session_index.rs:28 | 追加会话名称到索引 |
| `user_message_positions_in_rollout()` | truncation.rs:20 | 检测用户消息边界 |

### 协议定义（codex-protocol）

| 类型 | 文件 | 用途 |
|------|------|------|
| `RolloutItem` | protocol/src/protocol.rs:2418 | rollout 项枚举 |
| `RolloutLine` | protocol/src/protocol.rs:2500 | JSONL 行结构 |
| `SessionMeta` | protocol/src/protocol.rs:2361 | 会话元数据 |
| `SessionMetaLine` | protocol/src/protocol.rs:2409 | 带 Git 信息的元数据行 |
| `InitialHistory` | protocol/src/protocol.rs:2150 | 初始历史（新/恢复） |

---

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `codex_protocol` | RolloutItem、SessionMeta 等协议类型定义 |
| `codex_state` | SQLite 状态数据库交互（ThreadMetadata、StateRuntime） |
| `codex_file_search` | 文件搜索（用于 find_thread_path_by_id_str） |
| `crate::state_db` | 状态数据库的 core 层封装 |
| `crate::git_info` | Git 信息收集 |
| `crate::config::Config` | 配置访问 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `tokio` | 异步文件 I/O、通道、任务调度 |
| `serde_json` | JSON 序列化/反序列化 |
| `time` / `chrono` | 时间戳处理 |
| `uuid` | UUID 生成与解析 |
| `tempfile` | 测试临时目录 |
| `pretty_assertions` | 测试断言 |

### 交互流程图

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   TUI/CLI/App   │────▶│  RolloutRecorder │────▶│  rollout.jsonl  │
│                 │     │                 │     │  (文件系统)      │
└─────────────────┘     └────────┬────────┘     └─────────────────┘
                                 │
                                 ▼
                        ┌─────────────────┐
                        │   state_db.rs   │
                        │  (SQLite 同步)   │
                        └────────┬────────┘
                                 │
                                 ▼
                        ┌─────────────────┐
                        │  codex_state    │
                        │ (StateRuntime)  │
                        └─────────────────┘
```

---

## 风险、边界与改进建议

### 已知风险

1. **文件系统扫描性能**
   - 当会话数量巨大时（>10,000），`UpdatedAt` 排序需要扫描所有文件
   - 缓解：已实现扫描上限（MAX_SCAN_FILES = 10,000）和 DB 回退

2. **SQLite 与文件系统不一致**
   - DB 中的 rollout_path 可能与实际文件位置不一致（如用户手动移动文件）
   - 缓解：`read_repair_rollout_path()` 机制在查询时自动修复

3. **并发回填冲突**
   - 多个进程同时启动可能触发并发回填
   - 缓解：基于租约的互斥机制（15 分钟租约）

4. **大 rollout 文件**
   - 长期运行的会话可能产生巨大的 rollout 文件
   - 缓解：Extended 模式下对命令输出进行截断（10KB）

### 边界情况

1. **空 rollout 文件**：`load_rollout_items()` 会返回错误
2. **损坏的 JSON 行**：跳过并记录警告，继续解析后续行
3. **时区处理**：所有时间戳统一转换为 UTC
4. **文件名兼容性**：使用 `-` 代替 `:` 以兼容 Windows 文件系统

### 改进建议

1. **性能优化**
   - 为 `UpdatedAt` 排序引入文件系统事件监听或缓存机制
   - 考虑使用更高效的文件格式（如二进制或压缩）减少 I/O

2. **可靠性增强**
   - 添加 rollout 文件完整性校验（如每 N 行写入校验和）
   - 实现自动归档策略（基于文件大小或年龄）

3. **功能扩展**
   - 支持增量压缩（将历史数据压缩为 CompactedItem）
   - 添加 rollout 文件加密支持（敏感会话数据保护）

4. **可观测性**
   - 添加更多指标（rollout 文件大小分布、写入延迟等）
   - 改进错误上下文（记录具体哪一行 JSON 解析失败）

5. **代码质量**
   - `list.rs` 已超过 1200 行，建议拆分为子模块（如 `traversal.rs`、`cursor.rs`）
   - 统一错误处理（目前混合使用 `anyhow` 和 `std::io::Error`）

---

## 附录：常量与配置

| 常量 | 值 | 说明 |
|------|-----|------|
| `SESSIONS_SUBDIR` | `"sessions"` | 活跃会话子目录 |
| `ARCHIVED_SESSIONS_SUBDIR` | `"archived_sessions"` | 归档会话子目录 |
| `MAX_SCAN_FILES` | `10,000` | 单次查询最大扫描文件数 |
| `HEAD_RECORD_LIMIT` | `10` | 读取文件头用于摘要的最大行数 |
| `USER_EVENT_SCAN_LIMIT` | `200` | 扫描用户事件的最大额外行数 |
| `BACKFILL_BATCH_SIZE` | `200` | 回填批次大小 |
| `BACKFILL_LEASE_SECONDS` | `900` (15分钟) | 回填租约时长 |
| `PERSISTED_EXEC_AGGREGATED_OUTPUT_MAX_BYTES` | `10,000` | 命令输出截断限制 |

---

*文档生成时间：2026-03-21*
*研究范围：codex-rs/core/src/rollout 目录及其直接依赖*
