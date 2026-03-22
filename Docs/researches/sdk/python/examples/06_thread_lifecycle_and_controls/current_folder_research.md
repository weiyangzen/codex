# 06_thread_lifecycle_and_controls 研究文档

## 1. 场景与职责

### 1.1 目标示例目录

`sdk/python/examples/06_thread_lifecycle_and_controls/` 是 Codex Python SDK 的第六个示例，专注于展示 **Thread（对话线程）的完整生命周期管理** 和 **相关控制操作**。

### 1.2 核心场景

该示例覆盖了以下业务场景：

| 场景 | 说明 |
|------|------|
| **Thread 创建** | 使用 `thread_start()` 创建新线程，配置模型和参数 |
| **多轮对话** | 在线程中执行多个 turn（用户输入 + AI 响应） |
| **线程恢复** | 使用 `thread_resume()` 重新打开已有线程 |
| **线程列表** | 使用 `thread_list()` 查询活跃/归档线程 |
| **线程读取** | 使用 `read()` 获取线程详情和历史记录 |
| **线程命名** | 使用 `set_name()` 为线程设置名称 |
| **线程归档** | 使用 `thread_archive()` 将线程归档 |
| **线程解档** | 使用 `thread_unarchive()` 恢复归档线程 |
| **线程 Fork** | 使用 `thread_fork()` 从现有线程创建分支 |
| **上下文压缩** | 使用 `compact()` 触发上下文压缩（Context Compaction） |

### 1.3 职责边界

- **同步示例 (`sync.py`)**: 展示阻塞式 API 调用，适用于简单脚本
- **异步示例 (`async.py`)**: 展示基于 `asyncio` 的非阻塞 API 调用，适用于高性能应用
- **两者功能完全一致**，仅调用方式不同

---

## 2. 功能点目的

### 2.1 Thread 生命周期管理

```python
# 创建线程
thread = codex.thread_start(model="gpt-5.4", config={"model_reasoning_effort": "high"})

# 多轮对话
first = thread.turn(TextInput("...")).run()
second = thread.turn(TextInput("...")).run()

# 恢复线程
reopened = codex.thread_resume(thread.id)

# 归档/解档
codex.thread_archive(reopened.id)
unarchived = codex.thread_unarchive(reopened.id)
```

**目的**：展示如何管理线程的完整生命周期，包括创建、使用、暂停、恢复、归档等状态转换。

### 2.2 线程查询与元数据管理

```python
# 列表查询（支持分页和过滤）
listing_active = codex.thread_list(limit=20, archived=False)
listing_archived = codex.thread_list(limit=20, archived=True)

# 读取详情（包含 turns 历史）
reading = reopened.read(include_turns=True)

# 设置名称
reopened.set_name("sdk-lifecycle-demo")
```

**目的**：展示如何查询和管理线程的元数据，支持构建完整的线程管理 UI。

### 2.3 高级操作：Fork 和 Compact

```python
# Fork：从现有线程创建分支，继承历史上下文
forked = codex.thread_fork(unarchived.id, model="gpt-5.4")

# Compact：触发上下文压缩，减少 token 消耗
unarchived.compact()
```

**目的**：
- **Fork**: 支持基于现有对话创建新分支，用于探索不同方向的对话
- **Compact**: 支持手动触发上下文压缩，管理长对话的 token 消耗

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 Thread 创建流程

```
Client (Python SDK)
    ↓
Codex.thread_start() → AppServerClient.thread_start()
    ↓
JSON-RPC: "thread/start" → codex app-server (stdio)
    ↓
AppServerProtocol::ThreadStartParams
    ↓
ThreadStartResponse { thread, model, model_provider, ... }
    ↓
Thread (Python wrapper object)
```

#### 3.1.2 Thread 恢复流程

```
Client
    ↓
Codex.thread_resume(thread_id, model=..., config=...)
    ↓
JSON-RPC: "thread/resume" { threadId, ... }
    ↓
Server loads rollout file from disk
    ↓
ThreadResumeResponse { thread, ... }
```

**关键约束**：
- 线程必须先被 **materialized**（至少有一个用户消息写入磁盘）才能恢复
- 恢复时可以覆盖配置（model, approval_policy, sandbox 等）

#### 3.1.3 Thread Fork 流程

```
Client
    ↓
Codex.thread_fork(thread_id, model=..., ephemeral=...)
    ↓
JSON-RPC: "thread/fork" { threadId, ... }
    ↓
Server copies rollout file to new thread
    ↓
ThreadForkResponse { thread (new id), ... }
```

**关键特性**：
- Fork 创建的是独立的新线程，不影响原线程
- 支持 `ephemeral=True` 创建临时线程（不持久化到磁盘）
- Fork 的线程继承原线程的历史记录

#### 3.1.4 上下文压缩 (Compact) 流程

```
Client
    ↓
Thread.compact() / Codex.thread_compact(thread_id)
    ↓
JSON-RPC: "thread/compact/start" { threadId }
    ↓
Server triggers compaction (local or remote)
    ↓
Notifications: item/started, item/completed (ContextCompaction)
    ↓
ThreadCompactStartResponse {}
```

### 3.2 数据结构

#### 3.2.1 Thread 对象结构 (Rust)

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
pub struct Thread {
    pub id: String,
    pub name: Option<String>,
    pub preview: String,           // 消息预览
    pub path: Option<PathBuf>,     // rollout 文件路径
    pub cwd: PathBuf,              // 工作目录
    pub status: ThreadStatus,      // 线程状态
    pub turns: Vec<Turn>,          // 对话轮次
    pub created_at: i64,
    pub updated_at: i64,
    pub model_provider: String,
    pub ephemeral: bool,           // 是否为临时线程
    pub archived: bool,            // 是否已归档
    pub source: SessionSource,     // 来源 (Cli, VsCode, etc.)
    pub git_info: Option<GitInfo>, // Git 元数据
}
```

#### 3.2.2 Thread 状态机

```rust
pub enum ThreadStatus {
    Idle,           // 空闲，等待用户输入
    Active {       // 正在处理中
        active_flags: Vec<ActiveFlag>,
    },
    NotLoaded,      // 未加载（仅存在于磁盘）
}
```

#### 3.2.3 Turn 结构

```rust
pub struct Turn {
    pub id: String,
    pub status: TurnStatus,        // Completed, Failed, Interrupted, etc.
    pub items: Vec<ThreadItem>,    // 消息、工具调用等
    pub created_at: i64,
    pub updated_at: i64,
}
```

### 3.3 协议/命令

#### 3.3.1 JSON-RPC 方法列表

| 方法 | 方向 | 参数 | 响应 | 说明 |
|------|------|------|------|------|
| `thread/start` | C→S | `ThreadStartParams` | `ThreadStartResponse` | 创建新线程 |
| `thread/resume` | C→S | `ThreadResumeParams` | `ThreadResumeResponse` | 恢复已有线程 |
| `thread/fork` | C→S | `ThreadForkParams` | `ThreadForkResponse` | Fork 线程 |
| `thread/archive` | C→S | `ThreadArchiveParams` | `ThreadArchiveResponse` | 归档线程 |
| `thread/unarchive` | C→S | `ThreadUnarchiveParams` | `ThreadUnarchiveResponse` | 解档线程 |
| `thread/list` | C→S | `ThreadListParams` | `ThreadListResponse` | 列表查询 |
| `thread/read` | C→S | `ThreadReadParams` | `ThreadReadResponse` | 读取详情 |
| `thread/name/set` | C→S | `ThreadSetNameParams` | `ThreadSetNameResponse` | 设置名称 |
| `thread/compact/start` | C→S | `ThreadCompactStartParams` | `ThreadCompactStartResponse` | 触发压缩 |

#### 3.3.2 Server Notification (服务端推送)

| 通知 | 触发时机 |
|------|----------|
| `thread/started` | 新线程创建完成 |
| `thread/status/changed` | 线程状态变化 |
| `thread/archived` | 线程已归档 |
| `thread/unarchived` | 线程已解档 |
| `thread/name/updated` | 线程名称更新 |
| `turn/started` | 新 turn 开始 |
| `turn/completed` | turn 完成 |
| `item/started` | 新项目开始（如 ContextCompaction） |
| `item/completed` | 项目完成 |

### 3.4 Python SDK 实现细节

#### 3.4.1 同步客户端 (`Codex` 类)

```python
# sdk/python/src/codex_app_server/api.py
class Codex:
    def __init__(self, config: AppServerConfig | None = None):
        self._client = AppServerClient(config=config)
        self._client.start()
        self._init = self._validate_initialize(self._client.initialize())
    
    def thread_start(self, *, model: str | None = None, ...) -> Thread:
        params = ThreadStartParams(...)
        started = self._client.thread_start(params)
        return Thread(self._client, started.thread.id)
    
    def thread_resume(self, thread_id: str, *, model: str | None = None, ...) -> Thread:
        params = ThreadResumeParams(...)
        resumed = self._client.thread_resume(thread_id, params)
        return Thread(self._client, resumed.thread.id)
```

#### 3.4.2 Thread 包装类

```python
@dataclass(slots=True)
class Thread:
    _client: AppServerClient
    id: str
    
    def turn(self, input: Input, *, ...) -> TurnHandle:
        # 创建新 turn
        turn = self._client.turn_start(self.id, wire_input, params=params)
        return TurnHandle(self._client, self.id, turn.turn.id)
    
    def read(self, *, include_turns: bool = False) -> ThreadReadResponse:
        return self._client.thread_read(self.id, include_turns=include_turns)
    
    def set_name(self, name: str) -> ThreadSetNameResponse:
        return self._client.thread_set_name(self.id, name)
    
    def compact(self) -> ThreadCompactStartResponse:
        return self._client.thread_compact(self.id)
```

#### 3.4.3 异步客户端 (`AsyncCodex` 类)

```python
class AsyncCodex:
    def __init__(self, config: AppServerConfig | None = None):
        self._client = AsyncAppServerClient(config=config)
        # 延迟初始化，使用 _ensure_initialized()
```

异步实现通过 `asyncio.to_thread()` 将同步调用包装为异步操作，使用 `_transport_lock` 保证单线程安全。

---

## 4. 关键代码路径与文件引用

### 4.1 Python SDK 层

| 文件 | 职责 |
|------|------|
| `sdk/python/examples/06_thread_lifecycle_and_controls/sync.py` | 同步示例代码 |
| `sdk/python/examples/06_thread_lifecycle_and_controls/async.py` | 异步示例代码 |
| `sdk/python/src/codex_app_server/api.py` | `Codex`, `AsyncCodex`, `Thread`, `AsyncThread` 类 |
| `sdk/python/src/codex_app_server/client.py` | `AppServerClient` 同步 JSON-RPC 客户端 |
| `sdk/python/src/codex_app_server/async_client.py` | `AsyncAppServerClient` 异步包装器 |
| `sdk/python/src/codex_app_server/generated/v2_all.py` | 自动生成的 Pydantic 模型（ThreadStartResponse, ThreadResumeResponse 等） |
| `sdk/python/src/codex_app_server/models.py` | 基础类型定义（Notification, InitializeResponse 等） |

### 4.2 Rust App-Server 层

| 文件 | 职责 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | v2 API 协议定义（ThreadStartParams, ThreadResumeResponse 等） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | `ClientRequest` 枚举（定义所有 JSON-RPC 方法） |
| `codex-rs/app-server/src/codex_message_processor.rs` | 处理 thread/start, thread/resume 等请求 |
| `codex-rs/app-server/src/thread_state.rs` | Thread 状态管理 |
| `codex-rs/app-server/tests/suite/v2/thread_archive.rs` | 归档/解档测试 |
| `codex-rs/app-server/tests/suite/v2/thread_fork.rs` | Fork 功能测试 |
| `codex-rs/app-server/tests/suite/v2/thread_resume.rs` | 恢复功能测试 |
| `codex-rs/app-server/tests/suite/v2/compaction.rs` | 上下文压缩测试 |

### 4.3 关键代码片段

#### 4.3.1 Thread Resume 参数定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs:2544-2611
#[derive(Serialize, Deserialize, Debug, Default, Clone, PartialEq, JsonSchema, TS, ExperimentalApi)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadResumeParams {
    pub thread_id: String,
    
    #[experimental("thread/resume.history")]
    #[ts(optional = nullable)]
    pub history: Option<Vec<ResponseItem>>,
    
    #[experimental("thread/resume.path")]
    #[ts(optional = nullable)]
    pub path: Option<PathBuf>,
    
    // 配置覆盖项
    #[ts(optional = nullable)]
    pub model: Option<String>,
    #[ts(optional = nullable)]
    pub model_provider: Option<String>,
    // ...
}
```

#### 4.3.2 ClientRequest 枚举定义

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs:205-280
client_request_definitions! {
    ThreadStart => "thread/start" {
        params: v2::ThreadStartParams,
        inspect_params: true,
        response: v2::ThreadStartResponse,
    },
    ThreadResume => "thread/resume" {
        params: v2::ThreadResumeParams,
        inspect_params: true,
        response: v2::ThreadResumeResponse,
    },
    ThreadFork => "thread/fork" {
        params: v2::ThreadForkParams,
        inspect_params: true,
        response: v2::ThreadForkResponse,
    },
    ThreadArchive => "thread/archive" { ... },
    ThreadUnarchive => "thread/unarchive" { ... },
    ThreadCompactStart => "thread/compact/start" { ... },
    // ...
}
```

---

## 5. 依赖与外部交互

### 5.1 依赖关系图

```
06_thread_lifecycle_and_controls/
    ├── sync.py / async.py
    │       ↓
    ├── codex_app_server.Codex / AsyncCodex
    │       ↓
    ├── AppServerClient / AsyncAppServerClient
    │       ↓
    ├── subprocess.Popen("codex app-server --listen stdio://")
    │       ↓
    ├── codex-cli-bin (Rust binary)
    │       ↓
    ├── JSON-RPC over stdio
    │       ↓
    ├── app-server-protocol (Rust crate)
    │       ↓
    ├── codex-core / codex-state (Thread persistence)
```

### 5.2 外部交互

#### 5.2.1 与 Codex CLI 的交互

- Python SDK 通过 `subprocess.Popen` 启动 `codex app-server --listen stdio://`
- 使用 **JSON-RPC 2.0** 协议通过 stdin/stdout 进行通信
- 所有 thread 操作最终由 Rust app-server 处理

#### 5.2.2 与文件系统的交互

- Thread 数据以 **rollout** 格式持久化到磁盘
- 默认位置：`~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<thread_id>.jsonl`
- 归档位置：`~/.codex/archived/`

#### 5.2.3 与模型服务的交互

- Thread 的 turn 执行时，app-server 会调用配置的模型服务（OpenAI API 或其他 provider）
- 模型响应通过 SSE (Server-Sent Events) 流式返回

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 Materialization 约束

**风险**：Thread 必须先 materialize（至少有一个用户消息写入磁盘）才能进行 archive/fork/resume 操作。

```python
# 错误示例：新创建的线程直接归档会失败
thread = codex.thread_start(model="gpt-5.4")
codex.thread_archive(thread.id)  # ❌ 失败：no rollout found for thread id

# 正确做法：先执行至少一个 turn
thread.turn(TextInput("Hello")).run()
codex.thread_archive(thread.id)  # ✅ 成功
```

#### 6.1.2 并发限制

**风险**：SDK 目前不支持并发 turn 消费。

```python
# sdk/python/src/codex_app_server/client.py:288-296
def acquire_turn_consumer(self, turn_id: str) -> None:
    with self._turn_consumer_lock:
        if self._active_turn_consumer is not None:
            raise RuntimeError(
                "Concurrent turn consumers are not yet supported..."
            )
```

#### 6.1.3 实验性 API

**风险**：部分参数被标记为实验性（`#[experimental(...)]`），可能在未来版本中变更：
- `thread/resume.history` - 内存恢复
- `thread/resume.path` - 指定路径恢复
- `thread/fork.ephemeral` - 临时线程

### 6.2 边界条件

| 边界 | 说明 |
|------|------|
| **Thread ID 格式** | UUID v4 格式字符串 |
| **List 分页** | 默认 limit 由服务器决定，使用 cursor 进行分页 |
| **Archive 限制** | 只能归档已 materialized 的线程 |
| **Fork 继承** | Fork 的线程继承原线程的历史，但创建新的 thread ID |
| **Compact 触发** | 可以手动触发，也可配置自动压缩阈值 |

### 6.3 改进建议

#### 6.3.1 SDK 层改进

1. **更好的错误提示**：当操作未 materialized 线程时，提供更清晰的错误信息和解决建议

2. **批量操作支持**：当前 `thread_list` 返回完整 Thread 对象，对于大量线程可能性能不佳，建议支持轻量级列表查询

3. **事件监听机制**：当前需要轮询 `next_notification()`，建议提供基于回调的事件监听 API

#### 6.3.2 协议层改进

1. **原子操作**：当前 archive/unarchive 是独立操作，建议支持条件原子操作（如 "仅当处于 X 状态时归档"）

2. **批量归档**：支持一次归档多个线程

3. **搜索增强**：当前 `search_term` 仅支持简单子串匹配，建议支持正则或全文搜索

#### 6.3.3 测试建议

参考现有测试用例：
- `codex-rs/app-server/tests/suite/v2/thread_archive.rs` - 归档需要 materialized rollout
- `codex-rs/app-server/tests/suite/v2/thread_fork.rs` - Fork 不修改原线程
- `codex-rs/app-server/tests/suite/v2/thread_resume.rs` - 恢复时覆盖配置的行为

建议添加：
- 并发 resume 同一线程的冲突处理测试
- 归档线程在 list 中的可见性测试
- Fork ephemeral 线程的生命周期测试

---

## 7. 附录

### 7.1 相关文档

- `sdk/python/examples/_bootstrap.py` - 示例运行环境初始化
- `codex-rs/app-server-protocol/README.md` - 协议文档
- `AGENTS.md` - 项目级开发规范

### 7.2 生成代码说明

`sdk/python/src/codex_app_server/generated/v2_all.py` 是通过 `datamodel-codegen` 从 JSON Schema 自动生成的，来源：
- `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`

当 Rust 协议定义变更时，需要重新生成 Python 模型。

### 7.3 版本信息

- Python SDK 版本：`0.2.0`（见 `AppServerConfig.client_version`）
- 协议版本：v2（App-Server Protocol v2）
- 示例最后更新：基于当前仓库 HEAD
