# thread_read.rs 研究文档

## 场景与职责

`thread_read.rs` 是 Codex App Server v2 API 的集成测试文件，专注于测试 `thread/read` JSON-RPC 方法。该方法用于读取单个线程的详细信息，包括元数据、状态和可选的回合（turns）历史。

该测试文件位于 `codex-rs/app-server/tests/suite/v2/` 目录下，属于 app-server 端到端测试套件的一部分。通过启动真实的 app-server 进程并通过 MCP (Model Context Protocol) 与之通信来验证功能正确性。

## 功能点目的

该测试文件覆盖了 `thread/read` API 的以下核心功能：

1. **基本线程信息读取** - 验证返回线程的元数据（id, preview, model_provider, ephemeral, path, cwd, cli_version, source, git_info, status）
2. **回合历史读取** - 可选地包含线程的回合（turns）和项目（items）历史
3. **已加载线程读取** - 验证对内存中已加载线程的读取
4. **线程名称传播** - 验证通过 `thread/name/set` 设置的名称在 `thread/read`、`thread/list`、`thread/resume` 中正确显示
5. **未物化线程处理** - 验证对刚创建但尚未写入磁盘的线程的读取行为
6. **系统错误状态检测** - 验证失败回合后线程状态正确报告为 SystemError

## 具体技术实现

### 协议类型定义

**ThreadReadParams** (`codex-rs/app-server-protocol/src/protocol/v2.rs` 行 3045-3054):
```rust
pub struct ThreadReadParams {
    pub thread_id: String,
    /// When true, include turns and their items from rollout history.
    #[serde(default)]
    pub include_turns: bool,
}
```

**ThreadReadResponse** (行 3055-3060):
```rust
pub struct ThreadReadResponse {
    pub thread: Thread,
}
```

**Thread** (行 3472-3512):
```rust
pub struct Thread {
    pub id: String,
    pub preview: String,
    pub ephemeral: bool,
    pub model_provider: String,
    #[ts(type = "number")]
    pub created_at: i64,
    #[ts(type = "number")]
    pub updated_at: i64,
    pub status: ThreadStatus,
    pub path: Option<PathBuf>,
    pub cwd: PathBuf,
    pub cli_version: String,
    pub source: SessionSource,
    pub agent_nickname: Option<String>,
    pub agent_role: Option<String>,
    pub git_info: Option<GitInfo>,
    pub name: Option<String>,  // 用户设置的线程名称
    pub turns: Vec<Turn>,      // 回合历史（仅当 include_turns=true 时填充）
}
```

**Turn** (行 3580-3592):
```rust
pub struct Turn {
    pub id: String,
    pub items: Vec<ThreadItem>,
    pub status: TurnStatus,
    pub error: Option<TurnError>,
}
```

**TurnStatus** (行 3812-3820):
```rust
pub enum TurnStatus {
    Completed,
    Interrupted,
    Failed,
    InProgress,
}
```

**ThreadStatus** (行 3022-3035):
```rust
pub enum ThreadStatus {
    NotLoaded,
    Idle,
    SystemError,
    Active { active_flags: Vec<ThreadActiveFlag> },
}
```

### 测试用例详解

#### 1. thread_read_returns_summary_without_turns

验证基本读取功能（不包含回合历史）：

```rust
// 1. 创建带 text_elements 的 rollout
let preview = "Saved user message";
let text_elements = [TextElement::new(ByteRange { start: 0, end: 5 }, Some("<note>".into()))];
let conversation_id = create_fake_rollout_with_text_elements(
    codex_home.path(),
    "2025-01-05T12-00-00",
    "2025-01-05T12:00:00Z",
    preview,
    text_elements.iter().map(|elem| serde_json::to_value(elem).expect("serialize")).collect(),
    Some("mock_provider"),
    None,
)?;

// 2. 读取线程（include_turns=false）
let read_id = mcp.send_thread_read_request(ThreadReadParams {
    thread_id: conversation_id.clone(),
    include_turns: false,
}).await?;

// 3. 验证响应
let ThreadReadResponse { thread } = to_response::<ThreadReadResponse>(read_resp)?;
assert_eq!(thread.id, conversation_id);
assert_eq!(thread.preview, preview);
assert_eq!(thread.model_provider, "mock_provider");
assert!(!thread.ephemeral);
assert!(thread.path.as_ref().expect("thread path").is_absolute());
assert_eq!(thread.cwd, PathBuf::from("/"));
assert_eq!(thread.cli_version, "0.0.0");
assert_eq!(thread.source, SessionSource::Cli);
assert_eq!(thread.git_info, None);
assert_eq!(thread.turns.len(), 0);  // 不包含回合
assert_eq!(thread.status, ThreadStatus::NotLoaded);
```

#### 2. thread_read_can_include_turns

验证包含回合历史的读取：

```rust
// 1. 使用相同的 rollout 创建方式

// 2. 读取线程（include_turns=true）
let read_id = mcp.send_thread_read_request(ThreadReadParams {
    thread_id: conversation_id.clone(),
    include_turns: true,
}).await?;

// 3. 验证包含回合
assert_eq!(thread.turns.len(), 1);
let turn = &thread.turns[0];
assert_eq!(turn.status, TurnStatus::Completed);
assert_eq!(turn.items.len(), 1);

// 验证回合项目内容
match &turn.items[0] {
    ThreadItem::UserMessage { content, .. } => {
        assert_eq!(content, &vec![UserInput::Text {
            text: preview.to_string(),
            text_elements: text_elements.clone().into_iter().map(Into::into).collect(),
        }]);
    }
    other => panic!("expected user message item, got {other:?}"),
}
```

#### 3. thread_read_loaded_thread_returns_precomputed_path_before_materialization

验证对已加载但未物化线程的读取：

```rust
// 1. 启动新线程（尚未写入磁盘）
let start_resp = mcp.send_thread_start_request(ThreadStartParams {
    model: Some("mock-model".to_string()),
    ..Default::default()
}).await?;
let ThreadStartResponse { thread, .. } = to_response::<ThreadStartResponse>(start_resp)?;
let thread_path = thread.path.clone().expect("thread path");
assert!(!thread_path.exists(), "fresh thread rollout should not be materialized yet");

// 2. 读取线程
let read_resp = mcp.send_thread_read_request(ThreadReadParams {
    thread_id: thread.id.clone(),
    include_turns: false,
}).await?;
let ThreadReadResponse { thread: read } = to_response::<ThreadReadResponse>(read_resp)?;

// 3. 验证返回预计算的路径
assert_eq!(read.id, thread.id);
assert_eq!(read.path, Some(thread_path));
assert!(read.preview.is_empty());
assert_eq!(read.turns.len(), 0);
assert_eq!(read.status, ThreadStatus::Idle);  // 已加载线程状态为 Idle
```

#### 4. thread_name_set_is_reflected_in_read_list_and_resume

验证线程名称在多个 API 中的一致性：

```rust
// 1. 创建 rollout
let conversation_id = create_fake_rollout_with_text_elements(...)?;

// 2. 设置线程名称
let new_name = "My renamed thread";
let set_id = mcp.send_thread_set_name_request(ThreadSetNameParams {
    thread_id: conversation_id.clone(),
    name: new_name.to_string(),
}).await?;

// 3. 验证 thread/read 返回名称
let read_resp = mcp.send_thread_read_request(ThreadReadParams {
    thread_id: conversation_id.clone(),
    include_turns: false,
}).await?;
let ThreadReadResponse { thread } = to_response::<ThreadReadResponse>(read_resp)?;
assert_eq!(thread.name.as_deref(), Some(new_name));

// 4. 验证 wire 上序列化了 name 字段
let thread_json = read_resp.result.get("thread").and_then(Value::as_object).unwrap();
assert_eq!(thread_json.get("name").and_then(Value::as_str), Some(new_name));
assert_eq!(thread_json.get("ephemeral").and_then(Value::as_bool), Some(false));

// 5. 验证 thread/list 也返回名称
let list_resp = mcp.send_thread_list_request(ThreadListParams { ... }).await?;
let ThreadListResponse { data, .. } = to_response::<ThreadListResponse>(list_resp)?;
let listed = data.iter().find(|t| t.id == conversation_id).unwrap();
assert_eq!(listed.name.as_deref(), Some(new_name));

// 6. 验证 thread/resume 也返回名称
let resume_resp = mcp.send_thread_resume_request(ThreadResumeParams {
    thread_id: conversation_id.clone(),
    ..Default::default()
}).await?;
let ThreadResumeResponse { thread: resumed, .. } = to_response::<ThreadResumeResponse>(resume_resp)?;
assert_eq!(resumed.name.as_deref(), Some(new_name));
```

#### 5. thread_read_include_turns_rejects_unmaterialized_loaded_thread

验证对未物化的已加载线程拒绝读取回合：

```rust
// 1. 启动新线程（未物化）
let start_resp = mcp.send_thread_start_request(...).await?;
let ThreadStartResponse { thread, .. } = to_response::<ThreadStartResponse>(start_resp)?;
assert!(!thread.path.clone().unwrap().exists());

// 2. 尝试读取回合（应失败）
let read_id = mcp.send_thread_read_request(ThreadReadParams {
    thread_id: thread.id.clone(),
    include_turns: true,  // 请求回合
}).await?;

// 3. 验证返回错误
let read_err: JSONRPCError = mcp.read_stream_until_error_message(RequestId::Integer(read_id)).await?;
assert!(read_err.error.message.contains("includeTurns is unavailable before first user message"));
```

#### 6. thread_read_reports_system_error_idle_flag_after_failed_turn

验证系统错误状态检测：

```rust
// 1. 设置模拟服务器返回失败响应
let server = responses::start_mock_server().await;
let _response_mock = responses::mount_sse_once(
    &server,
    responses::sse_failed("resp-1", "server_error", "simulated failure"),
).await;

// 2. 启动线程并开始回合
let start_resp = mcp.send_thread_start_request(...).await?;
let ThreadStartResponse { thread, .. } = to_response::<ThreadStartResponse>(start_resp)?;

let turn_start_response = mcp.send_turn_start_request(TurnStartParams {
    thread_id: thread.id.clone(),
    input: vec![UserInput::Text { text: "fail this turn".to_string(), text_elements: Vec::new() }],
    ..Default::default()
}).await?;

// 3. 等待错误通知
let error_notification = mcp.read_stream_until_notification_message("error").await?;

// 4. 读取线程，验证状态为 SystemError
let read_resp = mcp.send_thread_read_request(ThreadReadParams {
    thread_id: thread.id,
    include_turns: false,
}).await?;
let ThreadReadResponse { thread } = to_response::<ThreadReadResponse>(read_resp)?;
assert_eq!(thread.status, ThreadStatus::SystemError);
```

### 辅助函数

**`create_config_toml`** - 创建测试配置：
```rust
fn create_config_toml(codex_home: &Path, server_uri: &str) -> std::io::Result<()>
```

**`create_fake_rollout_with_text_elements`** - 创建带文本元素的 rollout：
```rust
pub fn create_fake_rollout_with_text_elements(
    codex_home: &Path,
    filename_ts: &str,
    meta_rfc3339: &str,
    preview: &str,
    text_elements: Vec<serde_json::Value>,
    model_provider: Option<&str>,
    git_info: Option<GitInfo>,
) -> Result<String>
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/app-server/tests/suite/v2/thread_read.rs` - 本测试文件（499 行）

### 依赖的测试基础设施
- `codex-rs/app-server/tests/common/mcp_process.rs` - McpProcess 实现
- `codex-rs/app-server/tests/common/rollout.rs` - create_fake_rollout_with_text_elements
- `codex-rs/app-server/tests/common/lib.rs` - 测试公共库
- `codex-rs/app-server/tests/common/mock_model_server.rs` - Mock 模型服务器

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs` - v2 API 协议类型定义
  - `ThreadReadParams` (行 3045-3054)
  - `ThreadReadResponse` (行 3055-3060)
  - `Thread` (行 3472-3512)
  - `Turn` (行 3580-3592)
  - `TurnStatus` (行 3812-3820)
  - `ThreadStatus` (行 3022-3035)
  - `ThreadItem` - 回合项目类型
  - `UserInput` - 用户输入类型

### 被测实现（app-server 内部）
- `codex-rs/app-server/src/mcp/methods/thread_read.rs` - thread/read 方法实现
- `codex-rs/app-server/src/session_store.rs` - 会话存储管理
- `codex-rs/app-server/src/rollout/` - Rollout 文件读写

## 依赖与外部交互

### 外部依赖

| Crate | 用途 |
|-------|------|
| `anyhow` | 错误处理 |
| `tokio` | 异步运行时 |
| `tempfile` | 临时目录创建（CODEX_HOME） |
| `serde_json` | JSON 序列化/反序列化 |
| `pretty_assertions` | 测试断言美化 |

### 内部依赖

| Crate | 用途 |
|-------|------|
| `codex_app_server_protocol` | 协议类型定义 |
| `codex_protocol` | 核心协议类型（ThreadId, ByteRange, TextElement, UserInput 等） |
| `app_test_support` | 测试辅助函数 |
| `core_test_support` | 核心测试辅助（responses mock） |

### 进程间交互

```
测试进程 --(stdin/stdout JSON-RPC)--> app-server 子进程
                |
                |--(HTTP/SSE)--> mock responses server
                |
                |--(文件系统)--> CODEX_HOME/sessions/
                |                (rollout JSONL 文件)
```

## 风险、边界与改进建议

### 当前风险与边界

1. **回合历史完整性** - `include_turns=true` 时返回的回合历史是"有损"的（lossy），不包含所有代理交互（如命令执行详情），测试仅验证了基本结构。

2. **并发读取未测试** - 未测试多客户端同时读取同一线程的场景。

3. **大历史测试缺失** - 未测试回合历史很长时的性能和行为（分页、截断等）。

4. **错误场景覆盖不足** - 缺少以下测试：
   - 读取不存在的 thread_id
   - 读取损坏的 rollout 文件
   - 读取权限不足的文件

5. **状态转换测试有限** - 仅测试了 SystemError 状态，未测试：
   - Active 状态（进行中回合）
   - 从 SystemError 恢复后的状态变化

6. **TextElement 测试简单** - 仅测试了基本的 ByteRange，未测试复杂的文本元素嵌套。

### 改进建议

1. **增加错误场景测试**：
   ```rust
   async fn thread_read_returns_error_for_nonexistent_thread() -> Result<()>
   async fn thread_read_handles_corrupted_rollout() -> Result<()>
   async fn thread_read_handles_permission_denied() -> Result<()>
   ```

2. **增加并发测试**：
   ```rust
   async fn thread_read_is_consistent_under_concurrent_access() -> Result<()>
   ```

3. **增加大历史测试**：
   ```rust
   async fn thread_read_handles_large_turn_history() -> Result<()>
   async fn thread_read_performance_with_many_turns() -> Result<()>
   ```

4. **增加状态转换测试**：
   ```rust
   async fn thread_read_reports_active_status_during_turn() -> Result<()>
   async fn thread_read_transitions_from_system_error_after_success() -> Result<()>
   ```

5. **扩展文本元素测试**：
   ```rust
   async fn thread_read_preserves_complex_text_elements() -> Result<()>
   async fn thread_read_handles_empty_text_elements() -> Result<()>
   ```

6. **验证序列化完整性** - 添加测试验证 Thread 对象的所有字段都在 wire 上正确序列化：
   ```rust
   async fn thread_read_serializes_all_thread_fields() -> Result<()>
   ```

7. **与 thread/list 的一致性** - 添加测试验证同一线程在 `thread/read` 和 `thread/list` 中返回一致的数据。

8. **归档线程测试** - 添加对归档线程的读取测试：
   ```rust
   async fn thread_read_works_for_archived_threads() -> Result<()>
   ```
