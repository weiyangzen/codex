# thread_resume.rs 研究文档

## 场景与职责

`thread_resume.rs` 是 Codex App Server v2 API 的集成测试文件，专门测试**线程恢复（Thread Resume）**功能。该功能允许客户端重新连接到一个已存在的会话（thread），获取其历史记录并继续交互。这是实现多客户端协作、断线重连、会话持久化的核心能力。

### 核心测试场景

1. **基础恢复流程** - 验证可以从持久化的 rollout 文件恢复线程历史
2. **运行中线程恢复** - 测试当线程正在执行时，新客户端可以"加入"观察
3. **未物化线程处理** - 验证对尚未创建 rollout 文件的新线程的正确错误处理
4. **Git 元数据恢复** - 测试持久化的 Git 信息（分支、SHA）优先于实时检测
5. **未完成 Turn 的中断处理** - 验证对异常终止的 Turn 的正确状态标记
6. **时间戳和文件修改时间** - 确保恢复操作不意外修改 updated_at 和 mtime
7. **待处理请求重放** - 测试恢复时会重放等待用户批准的命令/文件变更请求
8. **配置覆盖** - 验证恢复时可以覆盖模型、人格等配置
9. **路径优先解析** - 测试 path 参数优先于 thread_id 的解析逻辑
10. **MCP 服务器初始化失败** - 验证必需的 MCP 服务器失败时的错误传播
11. **云配置加载错误** - 测试云端配置加载失败时的认证错误处理

## 功能点目的

### Thread Resume 的核心价值

- **会话持久化**: 用户可以在不同时间、不同客户端继续同一会话
- **多客户端协作**: 多个客户端可以同时观察和操作同一线程
- **断线恢复**: 网络中断后可以无缝恢复会话状态
- **状态同步**: 新连接的客户端可以获取完整的会话历史

### 关键测试功能点

| 测试函数 | 目的 |
|---------|------|
| `thread_resume_rejects_unmaterialized_thread` | 确保新线程（无 rollout 文件）不能被恢复 |
| `thread_resume_returns_rollout_history` | 验证历史记录正确从 rollout 文件解析 |
| `thread_resume_prefers_persisted_git_metadata_for_local_threads` | 确保持久化的 Git 元数据优先于实时检测 |
| `thread_resume_and_read_interrupt_incomplete_rollout_turn_when_thread_is_idle` | 处理未完成 Turn 的状态标记为 Interrupted |
| `thread_resume_without_overrides_does_not_change_updated_at_or_mtime` | 验证恢复操作不修改时间戳 |
| `thread_resume_keeps_in_flight_turn_streaming` | 测试运行中 Turn 的流式输出可被新客户端观察 |
| `thread_resume_rejects_history_when_thread_is_running` | 禁止在运行中线程上使用 history 覆盖 |
| `thread_resume_rejects_mismatched_path_when_thread_is_running` | 禁止在运行中线程上使用 path 覆盖 |
| `thread_resume_rejoins_running_thread_even_with_override_mismatch` | 验证即使有覆盖参数，也会加入运行中的线程 |
| `thread_resume_replays_pending_command_execution_request_approval` | 测试待处理命令执行请求的重放 |
| `thread_resume_replays_pending_file_change_request_approval` | 测试待处理文件变更请求的重放 |
| `thread_resume_with_overrides_defers_updated_at_until_turn_start` | 验证配置覆盖时 updated_at 的延迟更新 |
| `thread_resume_fails_when_required_mcp_server_fails_to_initialize` | 测试 MCP 初始化失败的错误处理 |
| `thread_resume_surfaces_cloud_requirements_load_errors` | 测试云配置加载错误的处理 |
| `thread_resume_prefers_path_over_thread_id` | 验证 path 参数优先于 thread_id |
| `thread_resume_supports_history_and_overrides` | 测试 history 参数和配置覆盖 |
| `thread_resume_accepts_personality_override` | 验证 personality 配置的覆盖 |

## 具体技术实现

### 关键数据结构

#### ThreadResumeParams (v2 协议)
```rust
pub struct ThreadResumeParams {
    pub thread_id: String,
    pub path: Option<PathBuf>,           // 可选：直接指定 rollout 文件路径
    pub history: Option<Vec<ResponseItem>>, // 可选：覆盖历史记录
    pub model: Option<String>,           // 可选：覆盖模型
    pub model_provider: Option<String>,  // 可选：覆盖模型提供者
    pub personality: Option<Personality>, // 可选：覆盖人格设置
    // ... 其他覆盖参数
}
```

#### ThreadResumeResponse
```rust
pub struct ThreadResumeResponse {
    pub thread: Thread,        // 恢复的线程信息
    pub model: String,         // 实际使用的模型
    pub model_provider: String, // 实际使用的模型提供者
    pub turns: Vec<Turn>,      // 恢复的历史 Turn
}
```

### 关键流程

#### 1. 恢复流程（正常情况）

```
Client -> thread/resume (thread_id)
    |
    v
Server 查找 rollout 文件
    |
    v
解析 rollout JSONL -> Vec<RolloutItem>
    |
    v
ThreadHistoryBuilder::build_turns_from_rollout_items()
    |
    v
返回 ThreadResumeResponse (包含完整历史)
```

#### 2. 运行中线程的恢复（Rejoin）

```
Client A -> turn/start -> 正在运行
    |
Client B -> thread/resume (相同 thread_id)
    |
    v
Server 检测到线程已在运行
    |
    v
返回当前状态 + 订阅后续更新
    |
    v
Client B 可以观察 Client A 的 Turn 进度
```

#### 3. 待处理请求重放流程

```
Client A -> turn/start -> Agent 请求命令执行批准
    |
    v
Server 发送 CommandExecutionRequestApproval 给 Client A
    |
Client B -> thread/resume
    |
    v
Server 重放待处理的 CommandExecutionRequestApproval 给 Client B
    |
    v
任一客户端响应后，请求被处理
```

### 核心代码路径

#### Rollout 文件解析
- **文件**: `codex-rs/app-server-protocol/src/protocol/thread_history.rs`
- **函数**: `build_turns_from_rollout_items()`
- **职责**: 将持久化的 JSONL rollout 文件转换为 Turn 结构

#### Thread 状态管理
- **文件**: `codex-rs/app-server/src/thread_state.rs`
- **结构**: `ThreadStateManager`
- **职责**: 
  - 管理线程到连接的订阅关系
  - 处理 ThreadListenerCommand 队列
  - 协调多客户端的并发访问

#### 消息处理
- **文件**: `codex-rs/app-server/src/codex_message_processor.rs`
- **函数**: `handle_thread_resume()`
- **职责**: 处理 thread/resume RPC 请求

### 测试辅助结构

#### RestartedThreadFixture
```rust
struct RestartedThreadFixture {
    mcp: McpProcess,
    thread_id: String,
    rollout_file_path: PathBuf,
}
```
用于测试场景：创建线程 -> 物化 rollout -> 重启 MCP 连接 -> 恢复线程

#### RolloutFixture
```rust
struct RolloutFixture {
    conversation_id: String,
    rollout_file_path: PathBuf,
    before_modified: SystemTime,
    expected_updated_at: i64,
}
```
用于测试时间戳和文件修改时间的验证

## 关键代码路径与文件引用

### 主要测试文件
- `codex-rs/app-server/tests/suite/v2/thread_resume.rs` - 本文件，包含 18 个测试用例

### 被测实现文件
- `codex-rs/app-server/src/codex_message_processor.rs` - 处理 thread/resume 请求
- `codex-rs/app-server/src/thread_state.rs` - 线程状态管理
- `codex-rs/app-server-protocol/src/protocol/thread_history.rs` - 历史记录构建

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs` - ThreadResumeParams/Response 定义

### 测试基础设施
- `codex-rs/app-server/tests/common/mcp_process.rs` - MCP 进程管理
- `codex-rs/app-server/tests/common/rollout.rs` - Rollout 文件创建辅助
- `codex-rs/app-server/tests/common/mock_model_server.rs` - Mock 模型服务器

### 核心协议依赖
- `codex-protocol` crate - 核心协议类型（EventMsg, RolloutItem 等）
- `codex-core` crate - ThreadManager, CodexThread 等

## 依赖与外部交互

### 外部依赖

1. **Wiremock** - 模拟 OpenAI Responses API
   - 提供 SSE 流响应
   - 验证请求计数

2. **TempDir** - 临时文件系统
   - 创建隔离的 CODEX_HOME
   - 存储 rollout 文件

3. **Tokio** - 异步运行时
   - 超时控制 (`DEFAULT_READ_TIMEOUT = 10s`)
   - 并发测试执行

### 内部依赖

```
thread_resume.rs
    |
    +-> app_test_support (测试辅助库)
    |       +-> McpProcess (MCP 进程管理)
    |       +-> create_fake_rollout* (创建测试 rollout)
    |       +-> create_mock_responses_server* (Mock 服务器)
    |
    +-> codex_app_server_protocol (协议层)
    |       +-> ThreadResumeParams/Response
    |       +-> ThreadHistoryBuilder
    |
    +-> codex_protocol (核心协议)
    |       +-> EventMsg, RolloutItem
    |       +-> SessionMeta
    |
    +-> codex_core (核心业务)
            +-> ThreadManager
            +-> CodexThread
```

### 文件系统交互

测试使用真实的文件系统操作：
- 创建 `CODEX_HOME/sessions/YYYY/MM/DD/rollout-{ts}-{id}.jsonl`
- 修改文件修改时间 (`set_rollout_mtime`)
- 验证 mtime 不被意外修改

### 进程交互

测试启动真实的 `codex-app-server` 进程：
- 通过 stdin/stdout 进行 JSON-RPC 通信
- 环境变量控制（`CODEX_HOME`, `RUST_LOG`）
- 进程生命周期管理（`kill_on_drop`）

## 风险、边界与改进建议

### 已知风险

1. **竞态条件**
   - `thread_resume_keeps_in_flight_turn_streaming` 测试中存在固有的竞态
   - 恢复响应和 Turn 完成通知的到达顺序不确定
   - 代码注释说明：`"If the in-flight turn completes before that queued command runs..."`

2. **时间依赖**
   - 多个测试使用 `tokio::time::timeout`
   - 在慢速 CI 环境可能不稳定
   - `DEFAULT_READ_TIMEOUT = 10s` 可能不足

3. **Git 依赖**
   - `thread_resume_prefers_persisted_git_metadata_for_local_threads` 需要 `git` 命令
   - 在最小化环境中可能失败

### 边界情况

1. **空 Rollout 文件**
   - 测试 `thread_resume_rejects_unmaterialized_thread` 验证新线程无法恢复
   - 但空 rollout 文件的处理未明确测试

2. **并发恢复**
   - 多个客户端同时恢复同一线程的行为
   - 当前测试覆盖有限

3. **大型历史记录**
   - 测试使用小型历史记录（1-2 个 Turn）
   - 大规模历史记录的性能未测试

### 改进建议

1. **测试稳定性**
   ```rust
   // 建议：增加重试机制或更宽松的超时
   const DEFAULT_READ_TIMEOUT: Duration = Duration::from_secs(30);
   ```

2. **并发测试覆盖**
   - 添加测试：3+ 客户端同时恢复同一线程
   - 验证消息广播的正确性

3. **错误场景覆盖**
   - 损坏的 rollout 文件处理
   - 权限不足的 rollout 文件
   - 网络存储（NFS/SMB）上的 rollout 文件

4. **性能测试**
   - 大型历史记录（100+ Turn）的恢复性能
   - 内存使用监控

5. **测试代码重构**
   - `create_config_toml` 在多个文件中重复定义
   - 建议提取到 `app_test_support` 公共库

### 维护注意事项

1. **协议变更同步**
   - `ThreadResumeParams` 新增字段时，需同步更新测试
   - 特别是 `#[experimental]` 字段的测试

2. **Mock 服务器更新**
   - OpenAI API 变更时，`create_shell_command_sse_response` 等辅助函数可能需要更新

3. **平台兼容性**
   - Windows 路径处理（`PathBuf` 与字符串转换）
   - Git 测试在 Windows 上的行为差异
