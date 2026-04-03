# fuzzy_file_search.rs 研究文档

## 场景与职责

`fuzzy_file_search.rs` 是 Codex App Server 的集成测试模块，专注于验证**模糊文件搜索**功能的端到端行为。该测试文件位于 `codex-rs/app-server/tests/suite/fuzzy_file_search.rs`，通过 MCP 进程与 App Server 交互，测试文件模糊匹配、搜索会话管理、实时搜索更新等核心功能。

### 核心职责
1. **模糊搜索功能测试**: 验证基于模糊匹配算法的文件搜索
2. **搜索会话管理测试**: 验证会话生命周期（启动、更新、停止）
3. **实时通知测试**: 验证搜索结果的实时流式推送
4. **并发与隔离测试**: 验证多会话独立性和取消机制

---

## 功能点目的

### 1. 辅助类型与常量

| 常量/类型 | 值/定义 | 说明 |
|-----------|---------|------|
| `DEFAULT_READ_TIMEOUT` | 10 秒 | 默认读取超时 |
| `SHORT_READ_TIMEOUT` | 500 毫秒 | 短超时，用于验证无更新 |
| `STOP_GRACE_PERIOD` | 250 毫秒 | 停止后的宽限期 |
| `FileExpectation` | `Any/Empty/NonEmpty` | 文件结果期望枚举 |

### 2. 测试用例矩阵

| 测试函数 | 测试目的 | 关键验证点 |
|----------|----------|-----------|
| `test_fuzzy_file_search_sorts_and_includes_indices` | 验证搜索结果排序和匹配索引 | 分数排序、indices 字段 |
| `test_fuzzy_file_search_accepts_cancellation_token` | 验证请求取消机制 | cancellationToken 工作正常 |
| `test_fuzzy_file_search_session_streams_updates` | 验证会话实时更新流 | sessionUpdated 通知 |
| `test_fuzzy_file_search_session_no_updates_after_complete_until_query_edited` | 验证完成后的静默期 | 无查询变更时不推送 |
| `test_fuzzy_file_search_session_update_before_start_errors` | 验证状态机约束 | 未启动时更新报错 |
| `test_fuzzy_file_search_session_update_works_without_waiting_for_start_response` | 验证异步启动 | 无需等待 start 响应即可 update |
| `test_fuzzy_file_search_session_multiple_query_updates_work` | 验证多次查询更新 | 多次 update 正常工作 |
| `test_fuzzy_file_search_session_update_after_stop_fails` | 验证停止后状态 | stop 后 update 报错 |
| `test_fuzzy_file_search_session_stops_sending_updates_after_stop` | 验证停止后静默 | stop 后无通知推送 |
| `test_fuzzy_file_search_two_sessions_are_independent` | 验证会话隔离 | 多会话互不干扰 |
| `test_fuzzy_file_search_query_cleared_sends_blank_snapshot` | 验证清空查询 | 空查询返回空结果 |

---

## 具体技术实现

### 关键流程

#### 1. 单次搜索流程

```rust
// 1. 创建测试文件
std::fs::write(root.path().join("alpha.txt"), "contents")?;

// 2. 发送搜索请求
let request_id = mcp
    .send_fuzzy_file_search_request("alp", vec![root_path.clone()], None)
    .await?;

// 3. 等待响应
let resp: JSONRPCResponse = timeout(
    DEFAULT_READ_TIMEOUT,
    mcp.read_stream_until_response_message(RequestId::Integer(request_id)),
).await??;

// 4. 验证结果
let files = resp.result.get("files").unwrap().as_array().unwrap();
assert_eq!(files.len(), 1);
assert_eq!(files[0]["path"], "alpha.txt");
```

#### 2. 搜索会话生命周期

```rust
// 1. 启动会话
mcp.start_fuzzy_file_search_session(session_id, vec![root_path.clone()]).await?;

// 2. 更新查询（触发搜索）
mcp.update_fuzzy_file_search_session(session_id, "alp").await?;

// 3. 等待实时更新通知
let payload = wait_for_session_updated(&mut mcp, session_id, "alp", FileExpectation::NonEmpty).await?;
assert_eq!(payload.files.len(), 1);

// 4. 等待完成通知
let completed = wait_for_session_completed(&mut mcp, session_id).await?;
assert_eq!(completed.session_id, session_id);

// 5. 停止会话
mcp.stop_fuzzy_file_search_session(session_id).await?;
```

#### 3. 等待通知辅助函数

```rust
async fn wait_for_session_updated(
    mcp: &mut McpProcess,
    session_id: &str,
    query: &str,
    file_expectation: FileExpectation,
) -> Result<FuzzyFileSearchSessionUpdatedNotification> {
    let description = format!("session update for sessionId={session_id}, query={query}");
    let notification = timeout(
        DEFAULT_READ_TIMEOUT,
        mcp.read_stream_until_matching_notification(&description, |notification| {
            // 验证方法名
            if notification.method != SESSION_UPDATED_METHOD {
                return false;
            }
            // 解析并验证 payload
            let payload: FuzzyFileSearchSessionUpdatedNotification = 
                serde_json::from_value(params.clone()).ok()?;
            // 验证 session_id, query, files 条件
            payload.session_id == session_id 
                && payload.query == query 
                && files_match
        }),
    ).await?;
}
```

### 数据结构

#### FuzzyFileSearchParams (单次搜索请求)
```rust
pub struct FuzzyFileSearchParams {
    pub query: String,
    pub roots: Vec<String>,           // 搜索根目录列表
    pub cancellation_token: Option<String>, // 可选的取消令牌
}
```

#### FuzzyFileSearchResult (搜索结果)
```rust
pub struct FuzzyFileSearchResult {
    pub root: String,                 // 根目录路径
    pub path: String,                 // 相对路径
    pub match_type: FuzzyFileSearchMatchType, // File 或 Directory
    pub file_name: String,            // 文件名
    pub score: u32,                   // 匹配分数（越高越匹配）
    pub indices: Option<Vec<u32>>,    // 匹配的字符索引
}
```

#### FuzzyFileSearchSessionStartParams (会话启动)
```rust
pub struct FuzzyFileSearchSessionStartParams {
    pub session_id: String,           // 客户端指定的会话 ID
    pub roots: Vec<String>,           // 搜索根目录
}
```

#### FuzzyFileSearchSessionUpdatedNotification (实时更新)
```rust
pub struct FuzzyFileSearchSessionUpdatedNotification {
    pub session_id: String,
    pub query: String,
    pub files: Vec<FuzzyFileSearchResult>,
}
```

#### FuzzyFileSearchSessionCompletedNotification (搜索完成)
```rust
pub struct FuzzyFileSearchSessionCompletedNotification {
    pub session_id: String,
}
```

### 搜索算法验证

测试用例 `test_fuzzy_file_search_sorts_and_includes_indices` 验证了模糊搜索的排序逻辑：

```rust
// 创建测试文件
abc          // 匹配 "abe": 分数较低
abcde        // 匹配 "abe": 分数中等
abexy        // 匹配 "abe": 分数最高 (84)
sub/abce     // 子目录匹配

// 期望结果顺序（按分数降序）:
// 1. abexy    (score: 84, indices: [0,1,2])
// 2. sub/abce (score: 72, indices: [4,5,7])
// 3. abcde    (score: 71, indices: [0,1,4])
```

**注意**: `zzz.txt` 不匹配查询 "abe"，因此不出现在结果中。

---

## 关键代码路径与文件引用

### 测试文件
| 文件 | 路径 | 说明 |
|------|------|------|
| fuzzy_file_search.rs | `codex-rs/app-server/tests/suite/fuzzy_file_search.rs` | 本测试文件（574 行） |
| mod.rs | `codex-rs/app-server/tests/suite/mod.rs` | 测试套件模块声明 |
| all.rs | `codex-rs/app-server/tests/all.rs` | 集成测试入口 |

### 测试支持库
| 文件 | 路径 | 说明 |
|------|------|------|
| mcp_process.rs | `codex-rs/app-server/tests/common/mcp_process.rs` | MCP 进程管理，包含 fuzzy file search 相关方法 |
| lib.rs | `codex-rs/app-server/tests/common/lib.rs` | 测试公共库 |

### MCP Process 中的相关方法

```rust
// mcp_process.rs 中的 fuzzy file search 方法

pub async fn send_fuzzy_file_search_request(
    &mut self,
    query: &str,
    roots: Vec<String>,
    cancellation_token: Option<String>,
) -> anyhow::Result<i64>

pub async fn start_fuzzy_file_search_session(
    &mut self,
    session_id: &str,
    roots: Vec<String>,
) -> anyhow::Result<JSONRPCResponse>

pub async fn update_fuzzy_file_search_session(
    &mut self,
    session_id: &str,
    query: &str,
) -> anyhow::Result<JSONRPCResponse>

pub async fn stop_fuzzy_file_search_session(
    &mut self,
    session_id: &str,
) -> anyhow::Result<JSONRPCResponse>
```

### 协议定义
| 文件 | 路径 | 说明 |
|------|------|------|
| common.rs | `codex-rs/app-server-protocol/src/protocol/common.rs` | FuzzyFileSearch 相关类型定义（行 795-872） |
| lib.rs | `codex-rs/app-server-protocol/src/lib.rs` | 协议库导出 |

### 协议中的 RPC 方法

| 方法 | 方向 | 参数 | 响应 |
|------|------|------|------|
| `fuzzyFileSearch` | Client → Server | `FuzzyFileSearchParams` | `FuzzyFileSearchResponse` |
| `fuzzyFileSearch/sessionStart` | Client → Server | `FuzzyFileSearchSessionStartParams` | `FuzzyFileSearchSessionStartResponse` |
| `fuzzyFileSearch/sessionUpdate` | Client → Server | `FuzzyFileSearchSessionUpdateParams` | `FuzzyFileSearchSessionUpdateResponse` |
| `fuzzyFileSearch/sessionStop` | Client → Server | `FuzzyFileSearchSessionStopParams` | `FuzzyFileSearchSessionStopResponse` |
| `fuzzyFileSearch/sessionUpdated` | Server → Client | `FuzzyFileSearchSessionUpdatedNotification` | - |
| `fuzzyFileSearch/sessionCompleted` | Server → Client | `FuzzyFileSearchSessionCompletedNotification` | - |

---

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `anyhow` | 错误处理 |
| `app_test_support::McpProcess` | MCP 进程管理 |
| `codex_app_server_protocol` | 协议类型定义 |
| `pretty_assertions` | 测试断言美化 |
| `serde_json` | JSON 序列化/反序列化 |
| `tempfile::TempDir` | 临时目录创建 |
| `tokio::time::timeout` | 异步超时处理 |

### 进程间交互

```
测试进程 (fuzzy_file_search.rs)
    │
    ├─► 创建临时目录和测试文件
    │
    ├─► 启动 codex-app-server 子进程
    │       CODEX_HOME={临时目录}
    │
    ├─► 发送 JSON-RPC 请求
    │       ├─ fuzzyFileSearch (单次搜索)
    │       ├─ fuzzyFileSearch/sessionStart
    │       ├─ fuzzyFileSearch/sessionUpdate
    │       └─ fuzzyFileSearch/sessionStop
    │
    ├─◄ 接收 JSON-RPC 响应
    │       └─ 请求响应 (request_id 匹配)
    │
    └─◄ 接收 Server Notification
            ├─ fuzzyFileSearch/sessionUpdated
            └─ fuzzyFileSearch/sessionCompleted
```

### 通知方法常量

```rust
const SESSION_UPDATED_METHOD: &str = "fuzzyFileSearch/sessionUpdated";
const SESSION_COMPLETED_METHOD: &str = "fuzzyFileSearch/sessionCompleted";
```

---

## 风险、边界与改进建议

### 已知风险

1. **文件系统依赖**: 测试依赖本地文件系统操作，在沙箱环境可能受限
2. **时序敏感**: 实时通知测试对时序敏感，可能 flaky
3. **平台差异**: 路径处理在不同平台（Windows/Unix）可能有差异
4. **性能依赖**: 大目录搜索可能超时

### 边界条件

| 边界场景 | 测试覆盖 | 状态 |
|----------|----------|------|
| 空查询字符串 | `test_fuzzy_file_search_query_cleared_sends_blank_snapshot` | ✅ 已覆盖 |
| 无匹配结果 | `test_fuzzy_file_search_session_multiple_query_updates_work` (zzzz 查询) | ✅ 已覆盖 |
| 大量文件 | `test_fuzzy_file_search_session_stops_sending_updates_after_stop` (512 文件) | ✅ 已覆盖 |
| 多会话并发 | `test_fuzzy_file_search_two_sessions_are_independent` | ✅ 已覆盖 |
| 取消令牌 | `test_fuzzy_file_search_accepts_cancellation_token` | ✅ 已覆盖 |
| 会话未启动就更新 | `test_fuzzy_file_search_session_update_before_start_errors` | ✅ 已覆盖 |
| 停止后更新 | `test_fuzzy_file_search_session_update_after_stop_fails` | ✅ 已覆盖 |
| 特殊字符文件名 | ❌ 未测试 | 建议添加 |
| 深层嵌套目录 | ❌ 未测试 | 建议添加 |
| 符号链接 | ❌ 未测试 | 建议添加 |
| 权限不足文件 | ❌ 未测试 | 建议添加 |

### 改进建议

1. **增加边界测试**:
   ```rust
   #[tokio::test]
   async fn test_fuzzy_file_search_special_characters() -> Result<()> {
       // 测试包含空格、Unicode、特殊符号的文件名
       std::fs::write(root.path().join("file with spaces.txt"), "")?;
       std::fs::write(root.path().join("文件.txt"), "")?;
       std::fs::write(root.path().join("file\"with'quotes.txt"), "")?;
   }
   ```

2. **增加性能基准测试**:
   ```rust
   #[tokio::test]
   async fn test_fuzzy_file_search_large_directory() -> Result<()> {
       // 创建 10000+ 文件，验证响应时间在可接受范围
   }
   ```

3. **增加并发压力测试**:
   ```rust
   #[tokio::test]
   async fn test_fuzzy_file_search_many_concurrent_sessions() -> Result<()> {
       // 同时启动 100 个会话，验证系统稳定性
   }
   ```

4. **路径安全测试**:
   ```rust
   #[tokio::test]
   async fn test_fuzzy_file_search_path_traversal_protection() -> Result<()> {
       // 验证无法通过 ../ 访问根目录外文件
   }
   ```

5. **错误恢复测试**:
   ```rust
   #[tokio::test]
   async fn test_fuzzy_file_search_root_removed_during_search() -> Result<()> {
       // 搜索过程中删除根目录，验证优雅降级
   }
   ```

### 会话状态机

```
                    ┌─────────────┐
                    │   Initial   │
                    └──────┬──────┘
                           │ sessionStart
                           ▼
                    ┌─────────────┐
         ┌─────────│   Active    │◄────────┐
         │         └──────┬──────┘         │
         │                │ sessionUpdate  │
         │                ▼                │
         │    ┌─────────────────────┐      │
         │    │  Searching/Updating │──────┘
         │    └─────────────────────┘
         │                │
         │                ▼
         │    ┌─────────────────────┐
         └───►│      Completed      │
              └─────────────────────┘
                           │
                    sessionStop
                           ▼
                    ┌─────────────┐
                    │   Stopped   │
                    └─────────────┘
```

### 相关实现组件

| 组件 | 可能位置 | 说明 |
|------|----------|------|
| 模糊匹配算法 | `codex-file-search` crate | 提供文件模糊匹配核心算法 |
| 文件系统遍历 | `codex-file-search` 或 app-server | 目录遍历和文件发现 |
| 会话管理 | `codex-app-server/src/` | 会话状态管理和生命周期 |
| 通知推送 | `codex-app-server/src/` | WebSocket/JSON-RPC 通知 |
