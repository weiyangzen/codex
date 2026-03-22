# thread_list.rs 研究文档

## 场景与职责

`thread_list.rs` 是 Codex App Server v2 API 的集成测试文件，专注于测试 `thread/list` JSON-RPC 方法。该方法用于分页查询用户的历史会话（threads）列表，支持多种过滤条件和排序方式。

该测试文件位于 `codex-rs/app-server/tests/suite/v2/` 目录下，属于 app-server 的端到端测试套件的一部分，通过启动真实的 app-server 进程并通过 MCP (Model Context Protocol) 与之通信来验证功能正确性。

## 功能点目的

该测试文件覆盖了 `thread/list` API 的以下核心功能：

1. **基础列表查询** - 验证空列表返回、基本线程属性（preview, model_provider, created_at, updated_at, cwd, cli_version, source, git_info, status）
2. **分页机制** - 验证 cursor 分页、next_cursor 在最后一页返回 None
3. **provider 过滤** - 按模型提供商筛选线程
4. **cwd 过滤** - 按工作目录筛选线程
5. **搜索词过滤** - 通过 SQLite 全文搜索线程标题（需要启用 sqlite 特性）
6. **source_kinds 过滤** - 按会话来源类型筛选（CLI、VSCode、Exec、AppServer、SubAgent 等）
7. **排序** - 支持按 created_at（默认）和 updated_at 排序
8. **archived 过滤** - 区分活跃线程和已归档线程
9. **系统错误状态检测** - 验证失败回合后线程状态正确报告为 SystemError
10. **分页限制** - 验证最大分页限制（100条）
11. **无效 cursor 处理** - 验证对无效 cursor 返回适当错误

## 具体技术实现

### 测试基础设施

#### McpProcess 封装
```rust
pub struct McpProcess {
    next_request_id: AtomicI64,
    process: Child,
    stdin: Option<ChildStdin>,
    stdout: BufReader<ChildStdout>,
    pending_messages: VecDeque<JSONRPCMessage>,
}
```

测试通过 `McpProcess::new(codex_home)` 启动 app-server 子进程，建立 stdin/stdout 管道进行 JSON-RPC 通信。

#### 测试辅助函数

**`list_threads`** - 基础列表查询包装：
```rust
async fn list_threads(
    mcp: &mut McpProcess,
    cursor: Option<String>,
    limit: Option<u32>,
    providers: Option<Vec<String>>,
    source_kinds: Option<Vec<ThreadSourceKind>>,
    archived: Option<bool>,
) -> Result<ThreadListResponse>
```

**`list_threads_with_sort`** - 支持排序键的完整版本：
```rust
async fn list_threads_with_sort(
    mcp: &mut McpProcess,
    cursor: Option<String>,
    limit: Option<u32>,
    providers: Option<Vec<String>>,
    source_kinds: Option<Vec<ThreadSourceKind>>,
    sort_key: Option<ThreadSortKey>,
    archived: Option<bool>,
) -> Result<ThreadListResponse>
```

**`create_fake_rollouts`** - 批量创建测试 rollout 文件：
```rust
fn create_fake_rollouts<F, G>(
    codex_home: &Path,
    count: usize,
    provider_for_index: F,
    timestamp_for_index: G,
    preview: &str,
) -> Result<Vec<String>>
```

**`set_rollout_cwd`** - 修改 rollout 文件中的工作目录：
```rust
fn set_rollout_cwd(path: &Path, cwd: &Path) -> Result<()>
```

**`set_rollout_mtime`** - 修改 rollout 文件修改时间（用于 updated_at 排序测试）：
```rust
fn set_rollout_mtime(path: &Path, updated_at_rfc3339: &str) -> Result<()>
```

### 协议类型定义

**ThreadListParams** (`codex-rs/app-server-protocol/src/protocol/v2.rs`):
```rust
pub struct ThreadListParams {
    pub cursor: Option<String>,
    pub limit: Option<u32>,
    pub sort_key: Option<ThreadSortKey>,
    pub model_providers: Option<Vec<String>>,
    pub source_kinds: Option<Vec<ThreadSourceKind>>,
    pub archived: Option<bool>,
    pub cwd: Option<String>,
    pub search_term: Option<String>,
}
```

**ThreadListResponse**:
```rust
pub struct ThreadListResponse {
    pub data: Vec<Thread>,
    pub next_cursor: Option<String>,
}
```

**ThreadSortKey**:
```rust
pub enum ThreadSortKey {
    CreatedAt,
    UpdatedAt,
}
```

**ThreadSourceKind**:
```rust
pub enum ThreadSourceKind {
    Cli,
    VsCode,
    Exec,
    AppServer,
    SubAgent,
    SubAgentReview,
    SubAgentCompact,
    SubAgentThreadSpawn,
    SubAgentOther,
    Unknown,
}
```

**ThreadStatus**:
```rust
pub enum ThreadStatus {
    NotLoaded,
    Idle,
    SystemError,
    Active { active_flags: Vec<ThreadActiveFlag> },
}
```

### 测试数据构造

测试使用 `create_fake_rollout()` 在 `CODEX_HOME/sessions/YYYY/MM/DD/rollout-{timestamp}-{uuid}.jsonl` 路径创建模拟 rollout 文件：

```rust
let id = create_fake_rollout(
    codex_home.path(),
    "2025-01-02T12-00-00",     // 文件名时间戳
    "2025-01-02T12:00:00Z",    // RFC3339 元数据时间
    "Hello",                    // preview 文本
    Some("mock_provider"),      // 模型提供商
    None,                       // git_info
)?;
```

Rollout 文件内容格式（JSON Lines）：
1. `session_meta` 类型行 - 包含会话元数据（id, timestamp, cwd, source, model_provider 等）
2. `response_item` 类型行 - 用户消息内容
3. `event_msg` 类型行 - 事件消息

### 关键测试用例

| 测试函数 | 目的 |
|---------|------|
| `thread_list_basic_empty` | 验证空列表正确返回 |
| `thread_list_pagination_next_cursor_none_on_last_page` | 验证分页 cursor 机制 |
| `thread_list_respects_provider_filter` | 验证 provider 过滤 |
| `thread_list_respects_cwd_filter` | 验证 cwd 过滤 |
| `thread_list_respects_search_term_filter` | 验证搜索词过滤（SQLite 路径） |
| `thread_list_empty_source_kinds_defaults_to_interactive_only` | 验证 source_kinds 默认行为 |
| `thread_list_filters_by_source_kind_subagent_thread_spawn` | 验证 SubAgentThreadSpawn 过滤 |
| `thread_list_filters_by_subagent_variant` | 验证 SubAgent 变体过滤 |
| `thread_list_fetches_until_limit_or_exhausted` | 验证跨页填充逻辑 |
| `thread_list_enforces_max_limit` | 验证最大分页限制（100） |
| `thread_list_stops_when_not_enough_filtered_results_exist` | 验证结果耗尽时停止 |
| `thread_list_includes_git_info` | 验证 git 元数据返回 |
| `thread_list_default_sorts_by_created_at` | 验证默认按 created_at 降序 |
| `thread_list_sort_updated_at_orders_by_mtime` | 验证 updated_at 排序 |
| `thread_list_updated_at_paginates_with_cursor` | 验证 updated_at 排序下的分页 |
| `thread_list_created_at_tie_breaks_by_uuid` | 验证 created_at 相同时使用 UUID 降序打破平局 |
| `thread_list_updated_at_tie_breaks_by_uuid` | 验证 updated_at 相同时使用 UUID 降序打破平局 |
| `thread_list_updated_at_uses_mtime` | 验证 updated_at 使用文件 mtime |
| `thread_list_archived_filter` | 验证 archived 过滤 |
| `thread_list_invalid_cursor_returns_error` | 验证无效 cursor 错误处理 |
| `thread_list_reports_system_error_idle_flag_after_failed_turn` | 验证系统错误状态检测 |

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/app-server/tests/suite/v2/thread_list.rs` - 本测试文件（1430 行）

### 依赖的测试基础设施
- `codex-rs/app-server/tests/common/mcp_process.rs` - McpProcess 实现
- `codex-rs/app-server/tests/common/rollout.rs` - create_fake_rollout 等辅助函数
- `codex-rs/app-server/tests/common/lib.rs` - 测试公共库

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs` - v2 API 协议类型定义
  - `ThreadListParams` (行 2932-2961)
  - `ThreadListResponse` (行 2989-2997)
  - `ThreadSortKey` (行 2981-2987)
  - `ThreadSourceKind` (行 2963-2979)
  - `ThreadStatus` (行 3022-3035)
  - `Thread` (行 3472-3512)

### 被测实现（app-server 内部）
- `codex-rs/app-server/src/mcp/methods/thread_list.rs` - thread/list 方法实现
- `codex-rs/app-server/src/session_store.rs` - 会话存储管理
- `codex-rs/state/src/lib.rs` - SQLite 状态数据库

## 依赖与外部交互

### 外部依赖

| Crate | 用途 |
|-------|------|
| `anyhow` | 错误处理 |
| `tokio` | 异步运行时 |
| `tempfile` | 临时目录创建（CODEX_HOME） |
| `chrono` | 时间解析和格式化 |
| `uuid` | UUID 解析（用于排序测试） |
| `serde_json` | JSON 序列化/反序列化 |
| `pretty_assertions` | 测试断言美化 |

### 内部依赖

| Crate | 用途 |
|-------|------|
| `codex_app_server_protocol` | 协议类型定义 |
| `codex_protocol` | 核心协议类型（ThreadId, GitInfo, SessionSource 等） |
| `codex_core` | 核心常量（ARCHIVED_SESSIONS_SUBDIR） |
| `codex_state` | SQLite 状态数据库（用于搜索测试） |
| `app_test_support` | 测试辅助函数 |
| `core_test_support` | 核心测试辅助（responses mock） |

### 进程间交互

```
测试进程 --(stdin/stdout JSON-RPC)--> app-server 子进程
                |
                |--(HTTP/SSE)--> mock responses server
                |
                |--(文件系统)--> CODEX_HOME/sessions/
                |
                |--(SQLite)--> CODEX_HOME/state.db (可选)
```

## 风险、边界与改进建议

### 当前风险与边界

1. **SQLite 依赖** - `thread_list_respects_search_term_filter` 测试需要启用 sqlite 特性，且需要手动初始化 StateRuntime 并标记 backfill 完成，测试复杂度较高。

2. **文件系统竞争** - 测试依赖文件系统操作（创建 rollout 文件、修改 mtime），在并行测试运行时可能遇到文件系统竞争问题。

3. **时间精度问题** - `updated_at` 排序依赖文件 mtime，不同文件系统的时间精度可能不同（秒级 vs 毫秒级）。

4. **UUID 排序依赖** - 测试假设 UUID 字符串的字典序与生成时间相关，这在极端情况下可能不成立。

5. **硬编码超时** - `DEFAULT_READ_TIMEOUT = 10s` 在慢速 CI 环境下可能导致 flaky 测试。

### 改进建议

1. **增加并发测试** - 添加多客户端并发调用 `thread/list` 的测试，验证线程安全性。

2. **边界条件测试** - 添加以下边界测试：
   - limit = 0 的行为
   - 非常大的 limit 值（超过 u32 范围）
   - 特殊字符的 search_term
   - 非常长的 cursor 字符串

3. **性能基准** - 添加大规模数据（1000+ threads）下的分页性能测试。

4. **错误场景覆盖** - 增加更多错误场景：
   - 损坏的 rollout 文件
   - 权限不足的目录
   - 磁盘空间不足

5. **测试隔离优化** - 考虑使用内存文件系统或更严格的临时目录隔离，减少文件系统相关的 flaky。

6. **SQLite 测试简化** - 考虑在测试框架中提供自动初始化 StateRuntime 的辅助函数，减少样板代码。

7. **文档补充** - 在协议文档中明确说明：
   - cursor 的具体格式（当前为不透明字符串）
   - 各种过滤条件的组合行为（AND vs OR）
   - 排序的稳定性保证
