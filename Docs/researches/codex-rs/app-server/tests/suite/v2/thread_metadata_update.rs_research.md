# thread_metadata_update.rs 研究文档

## 场景与职责

`thread_metadata_update.rs` 是 Codex App Server v2 API 的集成测试文件，专注于测试 `thread/metadata/update` JSON-RPC 方法。该方法用于更新线程的元数据，目前主要用于修改 Git 相关信息（commit SHA、branch、origin URL）。

该测试文件位于 `codex-rs/app-server/tests/suite/v2/` 目录下，属于 app-server 端到端测试套件的一部分。通过启动真实的 app-server 进程并通过 MCP (Model Context Protocol) 与之通信来验证功能正确性。

## 功能点目的

该测试文件覆盖了 `thread/metadata/update` API 的以下核心功能：

1. **Git 元数据更新** - 更新线程的 Git 分支、commit SHA、origin URL
2. **部分更新支持** - 支持只更新部分字段，其他字段保持不变
3. **字段清除** - 支持将字段设置为 null 来清除已有值
4. **空更新拒绝** - 拒绝没有提供任何有效字段的更新请求
5. **SQLite 行修复** - 为存储在文件系统但缺失 SQLite 记录的线程自动创建数据库行
6. **已加载线程更新** - 正确更新已加载线程的元数据而不重置摘要
7. **归档线程支持** - 支持更新已归档线程的元数据

## 具体技术实现

### 协议类型定义

**ThreadMetadataUpdateParams** (`codex-rs/app-server-protocol/src/protocol/v2.rs` 行 2805-2812):
```rust
pub struct ThreadMetadataUpdateParams {
    pub thread_id: String,
    /// Patch the stored Git metadata for this thread.
    /// Omit a field to leave it unchanged, set it to `null` to clear it, or
    /// provide a string to replace the stored value.
    #[ts(optional = nullable)]
    pub git_info: Option<ThreadMetadataGitInfoUpdateParams>,
}
```

**ThreadMetadataGitInfoUpdateParams** (行 2814-2848):
```rust
pub struct ThreadMetadataGitInfoUpdateParams {
    /// Omit to leave the stored commit unchanged, set to `null` to clear it,
    /// or provide a non-empty string to replace it.
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        serialize_with = "super::serde_helpers::serialize_double_option",
        deserialize_with = "super::serde_helpers::deserialize_double_option"
    )]
    #[ts(optional = nullable, type = "string | null")]
    pub sha: Option<Option<String>>,
    
    /// Omit to leave the stored branch unchanged, set to `null` to clear it,
    /// or provide a non-empty string to replace it.
    #[serde(...)]
    #[ts(optional = nullable, type = "string | null")]
    pub branch: Option<Option<String>>,
    
    /// Omit to leave the stored origin URL unchanged, set to `null` to clear it,
    /// or provide a non-empty string to replace it.
    #[serde(...)]
    #[ts(optional = nullable, type = "string | null")]
    pub origin_url: Option<Option<String>>,
}
```

**ThreadMetadataUpdateResponse** (行 2850-2855):
```rust
pub struct ThreadMetadataUpdateResponse {
    pub thread: Thread,
}
```

### 双 Option 模式

Git 信息字段使用 `Option<Option<String>>` 双 Option 模式来区分三种状态：
- `None` - 字段被省略，不修改现有值
- `Some(None)` - 明确设置为 null，清除现有值
- `Some(Some(value))` - 设置为新值

序列化和反序列化使用自定义辅助函数处理。

### 测试用例详解

#### 1. thread_metadata_update_patches_git_branch_and_returns_updated_thread

验证基本的 Git 分支更新功能：

```rust
// 1. 启动新线程
let start_resp = mcp.send_thread_start_request(...).await?;
let ThreadStartResponse { thread, .. } = to_response::<ThreadStartResponse>(start_resp)?;

// 2. 更新 Git 分支
let update_id = mcp.send_thread_metadata_update_request(ThreadMetadataUpdateParams {
    thread_id: thread.id.clone(),
    git_info: Some(ThreadMetadataGitInfoUpdateParams {
        sha: None,                                    // 不修改
        branch: Some(Some("feature/sidebar-pr".to_string())), // 设置新分支
        origin_url: None,                             // 不修改
    }),
}).await?;

// 3. 验证响应
let ThreadMetadataUpdateResponse { thread: updated } = to_response::<ThreadMetadataUpdateResponse>(update_resp)?;
assert_eq!(updated.git_info, Some(GitInfo {
    sha: None,
    branch: Some("feature/sidebar-pr".to_string()),
    origin_url: None,
}));

// 4. 验证通过 thread/read 也能看到更新
let read_resp = mcp.send_thread_read_request(ThreadReadParams {
    thread_id: thread.id,
    include_turns: false,
}).await?;
let ThreadReadResponse { thread: read } = to_response::<ThreadReadResponse>(read_resp)?;
assert_eq!(read.git_info, Some(GitInfo { ... }));
```

#### 2. thread_metadata_update_rejects_empty_git_info_patch

验证空更新被拒绝：

```rust
let update_id = mcp.send_thread_metadata_update_request(ThreadMetadataUpdateParams {
    thread_id: thread.id,
    git_info: Some(ThreadMetadataGitInfoUpdateParams {
        sha: None,
        branch: None,
        origin_url: None,
    }),
}).await?;

// 期望返回错误
let update_err: JSONRPCError = mcp.read_stream_until_error_message(...).await?;
assert_eq!(update_err.error.message, "gitInfo must include at least one field");
```

#### 3. thread_metadata_update_repairs_missing_sqlite_row_for_stored_thread

验证自动修复缺失的 SQLite 行：

```rust
// 1. 初始化 SQLite 数据库
let _state_db = init_state_db(codex_home.path()).await?;

// 2. 手动创建 rollout 文件（不通过正常流程）
let thread_id = create_fake_rollout(codex_home.path(), ..., preview, Some("mock_provider"), None)?;

// 3. 更新元数据（此时 SQLite 中没有对应行）
let update_resp = mcp.send_thread_metadata_update_request(...).await?;

// 4. 验证成功，且保留了 rollout 中的原始数据（preview, created_at）
let ThreadMetadataUpdateResponse { thread: updated } = to_response::<ThreadMetadataUpdateResponse>(update_resp)?;
assert_eq!(updated.id, thread_id);
assert_eq!(updated.preview, preview);
assert_eq!(updated.created_at, 1736078400);
```

#### 4. thread_metadata_update_repairs_loaded_thread_without_resetting_summary

验证对已加载线程的更新不重置摘要：

```rust
// 1. 创建 rollout 并手动同步到 SQLite
let thread_id = create_fake_rollout(...)?;
reconcile_rollout(Some(&state_db), rollout_path.as_path(), "mock_provider", None, &[], None, None).await;

// 2. 恢复线程（加载到内存）
let resume_resp = mcp.send_thread_resume_request(ThreadResumeParams {
    thread_id: thread_id.clone(),
    ..Default::default()
}).await?;

// 3. 从 SQLite 删除行（模拟数据不一致）
assert_eq!(state_db.delete_thread(thread_uuid).await?, 1);

// 4. 更新元数据应成功且不重置 preview
let update_resp = mcp.send_thread_metadata_update_request(...).await?;
assert_eq!(updated.preview, preview); // preview 保持不变
```

#### 5. thread_metadata_update_repairs_missing_sqlite_row_for_archived_thread

验证对归档线程的支持：

```rust
// 1. 创建 rollout
let thread_id = create_fake_rollout(...)?;

// 2. 将 rollout 移动到归档目录
let archived_dir = codex_home.path().join(ARCHIVED_SESSIONS_SUBDIR);
fs::create_dir_all(&archived_dir)?;
fs::rename(&archived_source, &archived_dest)?;

// 3. 更新应成功
let update_resp = mcp.send_thread_metadata_update_request(...).await?;
```

#### 6. thread_metadata_update_can_clear_stored_git_fields

验证清除字段功能：

```rust
// 1. 创建带 Git 信息的 rollout
let thread_id = create_fake_rollout(..., Some(RolloutGitInfo {
    commit_hash: Some("abc123".to_string()),
    branch: Some("feature/sidebar-pr".to_string()),
    repository_url: Some("git@example.com:openai/codex.git".to_string()),
}))?;

// 2. 清除所有 Git 字段
let update_resp = mcp.send_thread_metadata_update_request(ThreadMetadataUpdateParams {
    thread_id: thread_id.clone(),
    git_info: Some(ThreadMetadataGitInfoUpdateParams {
        sha: Some(None),        // 清除
        branch: Some(None),     // 清除
        origin_url: Some(None), // 清除
    }),
}).await?;

// 3. 验证 git_info 为 None
assert_eq!(updated.git_info, None);
```

### 辅助函数

**`init_state_db`** - 初始化 SQLite 状态数据库：
```rust
async fn init_state_db(codex_home: &Path) -> Result<Arc<StateRuntime>> {
    let state_db = StateRuntime::init(codex_home.to_path_buf(), "mock_provider".into()).await?;
    state_db.mark_backfill_complete(None).await?;
    Ok(state_db)
}
```

**`create_config_toml`** - 创建启用 SQLite 特性的配置：
```rust
fn create_config_toml(codex_home: &Path, server_uri: &str) -> std::io::Result<()>
```
配置包含：
```toml
[features]
sqlite = true
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/app-server/tests/suite/v2/thread_metadata_update.rs` - 本测试文件（461 行）

### 依赖的测试基础设施
- `codex-rs/app-server/tests/common/mcp_process.rs` - McpProcess 实现
- `codex-rs/app-server/tests/common/rollout.rs` - create_fake_rollout 等辅助函数
- `codex-rs/app-server/tests/common/lib.rs` - 测试公共库

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs` - v2 API 协议类型定义
  - `ThreadMetadataUpdateParams` (行 2805-2812)
  - `ThreadMetadataGitInfoUpdateParams` (行 2814-2848)
  - `ThreadMetadataUpdateResponse` (行 2850-2855)
  - `GitInfo` (行 1503-1510)

### 被测实现（app-server 内部）
- `codex-rs/app-server/src/mcp/methods/thread_metadata_update.rs` - thread/metadata/update 方法实现
- `codex-rs/app-server/src/session_store.rs` - 会话存储管理
- `codex-rs/state/src/lib.rs` - SQLite 状态数据库操作

### 核心依赖
- `codex_core::state_db::reconcile_rollout` - 同步 rollout 文件到 SQLite
- `codex_core::ARCHIVED_SESSIONS_SUBDIR` - 归档目录常量

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
| `codex_protocol` | 核心协议类型（ThreadId, GitInfo 等） |
| `codex_core` | 核心功能（ARCHIVED_SESSIONS_SUBDIR, reconcile_rollout） |
| `codex_state` | SQLite 状态数据库（StateRuntime） |
| `app_test_support` | 测试辅助函数 |

### 进程间交互

```
测试进程 --(stdin/stdout JSON-RPC)--> app-server 子进程
                |
                |--(HTTP/SSE)--> mock responses server
                |
                |--(文件系统)--> CODEX_HOME/sessions/
                |                CODEX_HOME/archived/
                |
                |--(SQLite)--> CODEX_HOME/state.db
```

## 风险、边界与改进建议

### 当前风险与边界

1. **SQLite 强依赖** - 所有测试都需要启用 sqlite 特性并初始化 StateRuntime，增加了测试复杂度和执行时间。

2. **数据一致性场景复杂** - 测试涉及 rollout 文件、SQLite 数据库、内存中会话三者之间的同步，理解成本较高。

3. **错误处理覆盖不足** - 缺少以下错误场景的测试：
   - 不存在的 thread_id
   - 损坏的 rollout 文件
   - SQLite 数据库锁定/损坏
   - 并发更新冲突

4. **字段验证缺失** - 未测试无效字段值的处理：
   - 过长的分支名
   - 无效的 URL 格式
   - 特殊字符处理

5. **权限测试缺失** - 未测试：
   - 只读 rollout 的更新行为
   - 跨用户/跨会话的访问控制

### 改进建议

1. **增加错误场景测试**：
   ```rust
   async fn thread_metadata_update_returns_error_for_nonexistent_thread() -> Result<()>
   async fn thread_metadata_update_handles_corrupted_rollout() -> Result<()>
   ```

2. **增加并发测试**：
   ```rust
   async fn thread_metadata_update_handles_concurrent_updates() -> Result<()>
   ```

3. **增加字段验证测试**：
   ```rust
   async fn thread_metadata_update_validates_branch_name_length() -> Result<()>
   async fn thread_metadata_update_validates_origin_url_format() -> Result<()>
   ```

4. **扩展元数据类型** - 当前仅支持 Git 信息，未来可能需要支持：
   - 自定义标签/分类
   - 用户备注
   - 会话优先级

5. **批量更新支持** - 考虑添加批量更新多个线程的 API：
   ```rust
   pub struct ThreadMetadataBatchUpdateParams {
       pub thread_ids: Vec<String>,
       pub git_info: Option<ThreadMetadataGitInfoUpdateParams>,
   }
   ```

6. **审计日志** - 记录元数据变更历史，支持：
   - 查看变更时间线
   - 回滚到之前的状态

7. **测试优化** - 考虑：
   - 提取公共的测试数据构造逻辑
   - 使用测试宏减少样板代码
   - 添加测试数据库的自动清理
