# thread_loaded_list.rs 研究文档

## 场景与职责

`thread_loaded_list.rs` 是 Codex App Server v2 API 的集成测试文件，专注于测试 `thread/loaded/list` JSON-RPC 方法。该方法用于查询当前已加载到内存中的线程（threads）ID 列表，与 `thread/list` 不同，它只返回活跃会话的标识符，而非所有历史会话。

该测试文件位于 `codex-rs/app-server/tests/suite/v2/` 目录下，属于 app-server 端到端测试套件的一部分。通过启动真实的 app-server 进程并通过 MCP (Model Context Protocol) 与之通信来验证功能正确性。

## 功能点目的

该测试文件覆盖了 `thread/loaded/list` API 的以下核心功能：

1. **已加载线程列表查询** - 验证返回当前内存中加载的线程 ID 列表
2. **分页机制** - 验证 cursor 分页在已加载线程列表中的工作方式
3. **线程生命周期跟踪** - 验证线程创建后正确出现在已加载列表中

### 与 thread/list 的区别

| 特性 | `thread/loaded/list` | `thread/list` |
|------|---------------------|---------------|
| 数据来源 | 内存中的活跃会话 | 磁盘上的所有会话 |
| 返回内容 | 仅线程 ID | 完整的 Thread 对象 |
| 使用场景 | 检查当前活跃会话 | 浏览历史会话 |
| 持久性 | 进程重启后清空 | 持久化存储 |

## 具体技术实现

### 测试基础设施

#### McpProcess 封装
测试复用 `app_test_support::McpProcess` 与 app-server 进行 JSON-RPC 通信：

```rust
let mut mcp = McpProcess::new(codex_home.path()).await?;
timeout(DEFAULT_READ_TIMEOUT, mcp.initialize()).await??;
```

#### Mock Responses Server
使用 `create_mock_responses_server_repeating_assistant("Done")` 创建模拟模型服务器，返回固定的 "Done" 响应：

```rust
let server = create_mock_responses_server_repeating_assistant("Done").await;
```

### 协议类型定义

**ThreadLoadedListParams** (`codex-rs/app-server-protocol/src/protocol/v2.rs` 行 3000-3009):
```rust
pub struct ThreadLoadedListParams {
    /// Opaque pagination cursor returned by a previous call.
    #[ts(optional = nullable)]
    pub cursor: Option<String>,
    /// Optional page size; defaults to no limit.
    #[ts(optional = nullable)]
    pub limit: Option<u32>,
}
```

**ThreadLoadedListResponse** (行 3011-3020):
```rust
pub struct ThreadLoadedListResponse {
    /// Thread ids for sessions currently loaded in memory.
    pub data: Vec<String>,
    /// Opaque cursor to pass to the next call to continue after the last item.
    /// if None, there are no more items to return.
    pub next_cursor: Option<String>,
}
```

### 测试流程

#### 测试 1: thread_loaded_list_returns_loaded_thread_ids

验证基本功能：创建线程后，该线程 ID 应出现在已加载列表中。

```rust
// 1. 启动线程
let thread_id = start_thread(&mut mcp).await?;

// 2. 查询已加载列表
let list_id = mcp.send_thread_loaded_list_request(ThreadLoadedListParams::default()).await?;
let resp: JSONRPCResponse = timeout(DEFAULT_READ_TIMEOUT, 
    mcp.read_stream_until_response_message(RequestId::Integer(list_id))).await??;

// 3. 验证结果包含创建的线程 ID
let ThreadLoadedListResponse { mut data, next_cursor } = to_response::<ThreadLoadedListResponse>(resp)?;
data.sort();
assert_eq!(data, vec![thread_id]);
assert_eq!(next_cursor, None);
```

#### 测试 2: thread_loaded_list_paginates

验证分页机制：

```rust
// 1. 创建两个线程
let first = start_thread(&mut mcp).await?;
let second = start_thread(&mut mcp).await?;

// 2. 第一页（limit=1）
let list_id = mcp.send_thread_loaded_list_request(ThreadLoadedListParams {
    cursor: None,
    limit: Some(1),
}).await?;
let resp = ...;
let ThreadLoadedListResponse { data: first_page, next_cursor } = to_response::<ThreadLoadedListResponse>(resp)?;
assert_eq!(first_page, vec![expected[0].clone()]);
assert_eq!(next_cursor, Some(expected[0].clone())); // 注意：cursor 是线程 ID

// 3. 第二页（使用 cursor）
let list_id = mcp.send_thread_loaded_list_request(ThreadLoadedListParams {
    cursor: next_cursor,
    limit: Some(1),
}).await?;
let resp = ...;
let ThreadLoadedListResponse { data: second_page, next_cursor } = to_response::<ThreadLoadedListResponse>(resp)?;
assert_eq!(second_page, vec![expected[1].clone()]);
assert_eq!(next_cursor, None);
```

### 辅助函数

**`start_thread`** - 创建新线程并返回线程 ID：
```rust
async fn start_thread(mcp: &mut McpProcess) -> Result<String> {
    let req_id = mcp
        .send_thread_start_request(ThreadStartParams {
            model: Some("gpt-5.1".to_string()),
            ..Default::default()
        })
        .await?;
    let resp: JSONRPCResponse = timeout(
        DEFAULT_READ_TIMEOUT,
        mcp.read_stream_until_response_message(RequestId::Integer(req_id)),
    )
    .await??;
    let ThreadStartResponse { thread, .. } = to_response::<ThreadStartResponse>(resp)?;
    Ok(thread.id)
}
```

**`create_config_toml`** - 创建测试配置：
```rust
fn create_config_toml(codex_home: &Path, server_uri: &str) -> std::io::Result<()>
```

配置内容包括：
- model = "mock-model"
- approval_policy = "never"
- sandbox_mode = "read-only"
- model_provider = "mock_provider"
- 模拟提供商的 base_url 指向 mock server

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/app-server/tests/suite/v2/thread_loaded_list.rs` - 本测试文件（139 行）

### 依赖的测试基础设施
- `codex-rs/app-server/tests/common/mcp_process.rs` - McpProcess 实现
- `codex-rs/app-server/tests/common/mock_model_server.rs` - Mock 模型服务器
- `codex-rs/app-server/tests/common/lib.rs` - 测试公共库

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs` - v2 API 协议类型定义
  - `ThreadLoadedListParams` (行 3000-3009)
  - `ThreadLoadedListResponse` (行 3011-3020)
  - `ThreadStartParams` (行 2449-2508)
  - `ThreadStartResponse` (行 2527-2542)

### 被测实现（app-server 内部）
- `codex-rs/app-server/src/mcp/methods/thread_loaded_list.rs` - thread/loaded/list 方法实现
- `codex-rs/app-server/src/session_store.rs` - 会话存储管理，维护已加载会话的内存索引

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
| `app_test_support` | 测试辅助函数（McpProcess, create_mock_responses_server_repeating_assistant, to_response） |

### 进程间交互

```
测试进程 --(stdin/stdout JSON-RPC)--> app-server 子进程
                |
                |--(HTTP/SSE)--> mock responses server (返回 "Done")
                |
                |--(内存)--> 已加载会话表
```

## 风险、边界与改进建议

### 当前风险与边界

1. **测试覆盖有限** - 当前仅有两个测试用例，覆盖场景较为基础：
   - 仅测试了单线程和双线程场景
   - 未测试线程关闭/卸载后从列表移除的场景
   - 未测试大量线程（性能/分页边界）

2. **Cursor 语义特殊** - 与其他列表 API 不同，`thread/loaded/list` 的 cursor 直接是线程 ID（而非编码的偏移量），这在文档中未明确说明。

3. **排序行为未定义** - 测试中对返回结果进行排序后再断言，说明 API 不保证返回顺序，这可能影响客户端的稳定性。

4. **并发场景未覆盖** - 未测试多客户端同时创建线程时列表的一致性。

### 改进建议

1. **增加生命周期测试** - 添加以下测试场景：
   ```rust
   // 线程关闭后从列表移除
   async fn thread_loaded_list_removes_unloaded_threads() -> Result<()>
   
   // 线程归档后状态
   async fn thread_loaded_list_excludes_archived_threads() -> Result<()>
   ```

2. **边界条件测试** - 添加：
   - limit = 0 的行为
   - 空列表返回（无加载线程时）
   - 无效 cursor 处理

3. **并发测试** - 验证：
   ```rust
   // 多线程并发创建时列表一致性
   async fn thread_loaded_list_is_consistent_under_concurrent_creates() -> Result<()>
   ```

4. **性能测试** - 添加基准测试：
   ```rust
   // 大量已加载线程下的查询性能
   async fn thread_loaded_list_performance_with_many_threads() -> Result<()>
   ```

5. **文档澄清** - 在协议文档中明确：
   - 返回结果的排序保证（或无保证）
   - cursor 的具体格式（当前是线程 ID）
   - 线程从列表移除的时机（显式关闭 vs 超时）

6. **与 thread/list 的关系** - 考虑添加测试验证：
   ```rust
   // 已加载线程应同时出现在 thread/list 中
   async fn thread_loaded_list_is_subset_of_thread_list() -> Result<()>
   ```
