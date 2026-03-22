# RolloutRecorder 深度研究文档

## 1. 场景与职责

`RolloutRecorder` 是 Codex 核心模块中负责**会话持久化**的核心组件，位于 `codex-rs/core/src/rollout/recorder.rs`。其主要职责包括：

- **记录会话事件**：将所有 `ResponseItem` 和 `EventMsg` 事件持久化到 JSONL 格式的 rollout 文件中
- **支持会话恢复**：允许从已保存的 rollout 文件恢复会话历史
- **会话发现与列表**：提供线程列表、搜索、分页功能
- **状态同步**：将 rollout 数据同步到 SQLite 状态数据库 (`state_db`)
- **延迟写入优化**：通过异步通道实现非阻塞写入，提升性能

### 核心使用场景

1. **新会话创建**：用户开始新对话时，创建 rollout 文件并记录元数据
2. **会话恢复**：用户恢复之前的会话时，加载历史 rollout 数据
3. **会话列表展示**：UI 展示历史会话列表，支持分页和筛选
4. **状态数据库回填**：将历史 rollout 文件同步到 SQLite 数据库

---

## 2. 功能点目的

### 2.1 事件持久化模式 (`EventPersistenceMode`)

```rust
pub enum EventPersistenceMode {
    Limited,   // 默认：仅持久化核心事件
    Extended,  // 扩展：包含更多诊断事件
}
```

- **Limited 模式**：仅保存用户消息、助手消息、工具调用等核心事件
- **Extended 模式**：额外保存命令执行输出、Web 搜索、MCP 工具调用等诊断信息

### 2.2 延迟文件创建 (Deferred File Creation)

新会话采用**延迟写入策略**：
- 初始化时仅预计算文件路径，不实际创建文件
- 首次调用 `persist()` 时才真正创建文件并写入缓冲的事件
- 避免空会话产生无意义的 rollout 文件

### 2.3 双存储架构 (Filesystem + SQLite)

```
┌─────────────────┐     ┌─────────────────┐
│  Rollout JSONL  │     │   SQLite DB     │
│  (Source of     │◄────┤   (Indexed      │
│   Truth)        │     │    Metadata)    │
└─────────────────┘     └─────────────────┘
```

- **JSONL 文件**：唯一真相源，包含完整会话历史
- **SQLite 数据库**：索引化的元数据缓存，加速列表查询

### 2.4 会话恢复路径查找

支持按当前工作目录 (CWD) 筛选最新会话：
- 优先匹配缓存的 CWD
- 回退到扫描 rollout 文件中的 `TurnContext`
- 最终回退到会话元数据中的 CWD

---

## 3. 具体技术实现

### 3.1 核心数据结构

#### RolloutRecorder

```rust
#[derive(Clone)]
pub struct RolloutRecorder {
    tx: Sender<RolloutCmd>,           // 命令通道
    pub(crate) rollout_path: PathBuf, // rollout 文件路径
    state_db: Option<StateDbHandle>,  // SQLite 状态数据库句柄
    event_persistence_mode: EventPersistenceMode,
}
```

#### RolloutCmd (内部命令枚举)

```rust
enum RolloutCmd {
    AddItems(Vec<RolloutItem>),           // 添加事件
    Persist { ack: oneshot::Sender<()> }, // 强制持久化
    Flush { ack: oneshot::Sender<()> },   // 刷新到磁盘
    Shutdown { ack: oneshot::Sender<()> },// 关闭写入器
}
```

#### RolloutRecorderParams (创建参数)

```rust
pub enum RolloutRecorderParams {
    Create {
        conversation_id: ThreadId,
        forked_from_id: Option<ThreadId>,
        source: SessionSource,
        base_instructions: BaseInstructions,
        dynamic_tools: Vec<DynamicToolSpec>,
        event_persistence_mode: EventPersistenceMode,
    },
    Resume {
        path: PathBuf,
        event_persistence_mode: EventPersistenceMode,
    },
}
```

### 3.2 关键流程

#### 3.2.1 创建新会话流程

```rust
pub async fn new(
    config: &Config,
    params: RolloutRecorderParams,
    state_db_ctx: Option<StateDbHandle>,
    state_builder: Option<ThreadMetadataBuilder>,
) -> std::io::Result<Self> {
    // 1. 预计算文件路径 (YYYY/MM/DD 分层目录)
    let log_file_info = precompute_log_file_info(config, conversation_id)?;
    
    // 2. 构建 SessionMeta
    let session_meta = SessionMeta { ... };
    
    // 3. 创建异步通道 (容量 256)
    let (tx, rx) = mpsc::channel::<RolloutCmd>(256);
    
    // 4. 启动后台写入任务
    tokio::task::spawn(rollout_writer(
        file: None,  // 延迟创建
        deferred_log_file_info: Some(log_file_info),
        rx,
        meta: Some(session_meta),
        ...
    ));
    
    // 5. 返回 recorder 实例
    Ok(Self { tx, rollout_path, state_db, event_persistence_mode })
}
```

#### 3.2.2 事件写入流程

```rust
pub(crate) async fn record_items(&self, items: &[RolloutItem]) -> std::io::Result<()> {
    // 1. 根据持久化模式过滤事件
    let mut filtered = Vec::new();
    for item in items {
        if is_persisted_response_item(item, self.event_persistence_mode) {
            filtered.push(sanitize_rollout_item_for_persistence(item.clone(), self.event_persistence_mode));
        }
    }
    
    // 2. 通过通道发送给后台写入器
    self.tx.send(RolloutCmd::AddItems(filtered)).await
}
```

#### 3.2.3 后台写入器 (`rollout_writer`)

```rust
async fn rollout_writer(
    mut file: Option<tokio::fs::File>,
    mut deferred_log_file_info: Option<LogFileInfo>,
    mut rx: mpsc::Receiver<RolloutCmd>,
    ...
) -> std::io::Result<()> {
    let mut writer = file.map(|file| JsonlWriter { file });
    let mut buffered_items = Vec::<RolloutItem>::new();
    
    while let Some(cmd) = rx.recv().await {
        match cmd {
            RolloutCmd::AddItems(items) => {
                if writer.is_none() {
                    // 延迟模式：缓冲到内存
                    buffered_items.extend(items);
                } else {
                    // 直接写入
                    write_and_reconcile_items(...).await?;
                }
            }
            RolloutCmd::Persist { ack } => {
                if writer.is_none() {
                    // 首次持久化：创建文件并写入缓冲内容
                    let file = open_log_file(log_file_info.path.as_path())?;
                    writer = Some(JsonlWriter { file });
                    // 写入 session_meta
                    write_session_meta(...).await?;
                    // 写入缓冲的事件
                    write_and_reconcile_items(..., buffered_items.as_slice(), ...).await?;
                }
                let _ = ack.send(());
            }
            // ... Flush, Shutdown 处理
        }
    }
}
```

#### 3.2.4 线程列表查询流程

```rust
pub async fn list_threads(
    config: &Config,
    page_size: usize,
    cursor: Option<&Cursor>,
    sort_key: ThreadSortKey,
    allowed_sources: &[SessionSource],
    model_providers: Option<&[String]>,
    default_provider: &str,
    search_term: Option<&str>,
) -> std::io::Result<ThreadsPage> {
    // 1. 尝试从 SQLite 查询 (如果可用且回填完成)
    if let Some(db_page) = state_db::list_threads_db(...).await {
        return Ok(db_page.into());
    }
    
    // 2. 回退到文件系统扫描
    let fs_page = get_threads(codex_home, page_size, cursor, sort_key, ...).await?;
    
    // 3. 返回结果
    Ok(fs_page)
}
```

### 3.3 数据清理与截断

```rust
fn sanitize_rollout_item_for_persistence(
    item: RolloutItem,
    mode: EventPersistenceMode,
) -> RolloutItem {
    if mode != EventPersistenceMode::Extended {
        return item;
    }
    
    match item {
        RolloutItem::EventMsg(EventMsg::ExecCommandEnd(mut event)) => {
            // 截断聚合输出到 10KB
            event.aggregated_output = truncate_text(
                &event.aggregated_output,
                TruncationPolicy::Bytes(PERSISTED_EXEC_AGGREGATED_OUTPUT_MAX_BYTES),
            );
            // 清空详细输出字段
            event.stdout.clear();
            event.stderr.clear();
            event.formatted_output.clear();
            RolloutItem::EventMsg(EventMsg::ExecCommandEnd(event))
        }
        _ => item,
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件结构

```
codex-rs/core/src/rollout/
├── mod.rs              # 模块导出
├── recorder.rs         # 核心实现 (本文件)
├── recorder_tests.rs   # 单元测试
├── list.rs             # 线程列表查询
├── metadata.rs         # 元数据提取与回填
├── policy.rs           # 持久化策略
├── session_index.rs    # 会话名称索引
├── truncation.rs       # 历史截断工具
└── error.rs            # 错误类型
```

### 4.2 关键依赖

| 依赖模块 | 用途 |
|---------|------|
| `codex_protocol::protocol` | `RolloutItem`, `RolloutLine`, `SessionMeta`, `EventMsg` |
| `codex_state` | `StateRuntime`, `ThreadMetadataBuilder`, `ThreadsPage` |
| `crate::state_db` | SQLite 数据库操作封装 |
| `crate::truncate` | 文本截断工具 |
| `crate::git_info` | Git 信息收集 |

### 4.3 重要函数索引

| 函数名 | 行号 | 用途 |
|-------|------|------|
| `RolloutRecorder::new` | 370 | 创建 recorder 实例 |
| `RolloutRecorder::record_items` | 484 | 记录事件 |
| `RolloutRecorder::persist` | 509 | 强制持久化 |
| `RolloutRecorder::list_threads` | 165 | 列表查询 |
| `rollout_writer` | 708 | 后台写入任务 |
| `write_session_meta` | 838 | 写入会话元数据 |
| `sync_thread_state_after_write` | 898 | 同步到 SQLite |
| `precompute_log_file_info` | 661 | 预计算文件路径 |

---

## 5. 依赖与外部交互

### 5.1 上游调用方

```
codex-rs/core/src/codex_thread.rs
  └── CodexThread::new()
      └── RolloutRecorder::new()

codex-rs/core/src/loop.rs
  └── 事件处理循环
      └── RolloutRecorder::record_items()
```

### 5.2 下游依赖

```
RolloutRecorder
  ├── codex_state::StateRuntime          # SQLite 数据库
  ├── tokio::fs                          # 异步文件操作
  ├── serde_json                         # JSON 序列化
  └── time/chrono                        # 时间处理
```

### 5.3 文件系统布局

```
~/.codex/
├── sessions/
│   └── YYYY/
│       └── MM/
│           └── DD/
│               └── rollout-YYYY-MM-DDThh-mm-ss-<uuid>.jsonl
├── archived_sessions/
│   └── ... (同上结构)
└── state.db                             # SQLite 数据库
```

### 5.4 状态数据库交互

```rust
// 写入后同步到 SQLite
state_db::apply_rollout_items(
    state_db_ctx,
    rollout_path,
    default_provider,
    state_builder,
    items,
    "rollout_writer",
    new_thread_memory_mode,
    Some(updated_at),
).await;
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 文件句柄泄漏风险

```rust
// 当前实现中，如果 persist() 未被调用，writer 永远不会创建
// 但 buffered_items 会持续累积在内存中
RolloutCmd::AddItems(items) => {
    if writer.is_none() {
        buffered_items.extend(items);  // 内存累积风险
        continue;
    }
    ...
}
```

**缓解措施**：当前通道容量限制为 256，可缓冲的事件数量有限。

#### 6.1.2 并发写入竞争

多个线程同时写入同一 rollout 文件可能导致数据损坏。当前通过 `RolloutRecorder` 的克隆共享单一写入任务来避免。

#### 6.1.3 磁盘空间耗尽

JSONL 文件会持续增长，特别是 Extended 模式下。当前缺乏自动轮转机制。

### 6.2 边界条件

| 场景 | 行为 |
|-----|------|
| 磁盘已满 | 写入失败，返回 `std::io::Error` |
| 文件被外部删除 | 下次写入会重新创建文件 |
| 会话无事件 | 文件延迟创建，可能永不创建 |
| SQLite 不可用 | 回退到纯文件系统模式 |
| 超大事件 (>10KB) | 在 Extended 模式下会被截断 |

### 6.3 改进建议

#### 6.3.1 添加内存缓冲上限

```rust
const MAX_BUFFERED_ITEMS: usize = 10000;

// 在 AddItems 处理中添加检查
if buffered_items.len() + items.len() > MAX_BUFFERED_ITEMS {
    // 强制触发 persist 或返回错误
}
```

#### 6.3.2 文件轮转支持

```rust
// 建议添加配置项
pub struct RolloutConfig {
    max_file_size: Option<usize>,  // 如 100MB
    max_file_age: Option<Duration>, // 如 24小时
}
```

#### 6.3.3 批量写入优化

当前每个事件都触发一次 `file.flush().await`，可考虑：
- 添加定时 flush 机制
- 批量 flush 减少系统调用

#### 6.3.4 压缩支持

对于历史 rollout 文件，可考虑透明压缩：
```rust
// 读取时自动检测 .jsonl.gz 并解压
// 写入时可配置压缩级别
```

#### 6.3.5 更完善的错误恢复

当前某些错误仅记录警告日志，建议：
- 添加错误事件上报机制
- 实现指数退避重试

### 6.4 测试覆盖

当前测试 (`recorder_tests.rs`) 覆盖：
- ✅ 延迟持久化行为
- ✅ 元数据更新
- ✅ 列表分页
- ✅ 数据库回退
- ⚠️ 建议补充：磁盘满、权限拒绝、并发写入等异常场景
