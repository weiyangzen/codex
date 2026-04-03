# thread_archive.rs 研究文档

## 场景与职责

本文件是 Codex App Server v2 API 的集成测试套件的一部分，专门测试**线程归档功能** (`thread/archive` 和 `thread/unarchive`)。归档允许用户将暂时不用的对话线程从活跃列表中移除，但保留数据以便将来恢复。

测试场景覆盖：
1. **归档前置条件验证** - 只有已实体化（materialized）的线程才能归档
2. **归档文件操作** - 验证线程文件从活跃目录移动到归档目录
3. **订阅清理** - 验证归档/解归档操作正确清理过期的订阅
4. **多客户端场景** - 验证归档后其他客户端可以正常恢复线程

## 功能点目的

### 1. 线程生命周期管理
线程归档是线程生命周期的重要阶段：
- **活跃**: 线程在 `sessions/` 目录下，可被列出和恢复
- **归档**: 线程移动到 `archived/` 子目录，从常规列表中隐藏
- **解归档**: 线程恢复到活跃状态

### 2. 实体化要求
线程必须"实体化"（有实际的 rollout 文件）才能归档：
- 仅创建但未执行任何回合的线程无法归档
- 需要至少完成一个用户回合才会创建 rollout 文件

### 3. 订阅管理
归档操作会清理订阅状态：
- 归档时清理活跃订阅
- 解归档后其他客户端可以正常订阅和恢复
- 防止归档线程的通知发送到旧订阅者

### 4. 文件系统操作
```
sessions/2025/01/05/rollout-xxx-thread_id.jsonl
  ↓ 归档
archived/rollout-xxx-thread_id.jsonl
  ↓ 解归档
sessions/2025/01/05/rollout-xxx-thread_id.jsonl
```

## 具体技术实现

### 关键流程

```
测试用例: thread_archive_requires_materialized_rollout
1. 创建临时 CODEX_HOME
2. 启动 mock 服务器和 MCP 连接
3. 启动线程 (thread/start)
4. 验证 rollout 路径不存在（未实体化）
5. 尝试归档，验证返回错误 "no rollout found for thread id"
6. 执行一个用户回合 (turn/start)
7. 验证 rollout 文件已创建
8. 再次尝试归档，验证成功
9. 验证收到 thread/archived 通知
10. 验证文件已移动到 archived/ 目录

测试用例: thread_archive_clears_stale_subscriptions_before_resume
1. 创建临时 CODEX_HOME
2. 启动 mock 服务器
3. 客户端 A: 启动 MCP，创建线程，执行回合
4. 客户端 B: 启动 MCP，初始化
5. 客户端 A: 归档线程
6. 客户端 A: 解归档线程
7. 客户端 B: 恢复线程 (thread/resume)
8. 客户端 B: 开始新回合
9. 验证客户端 A 不会收到客户端 B 的回合通知
```

### 核心数据结构

```rust
// 归档请求
ThreadArchiveParams {
    thread_id: String,
}

ThreadArchiveResponse {}

// 解归档请求
ThreadUnarchiveParams {
    thread_id: String,
}

ThreadUnarchiveResponse {}

// 归档通知
ThreadArchivedNotification {
    thread_id: String,
}

// 解归档通知
ThreadUnarchivedNotification {
    thread_id: String,
}

// 线程状态
ThreadStatus {
    Idle,
    InProgress,
    // ...
}
```

### 文件系统验证

```rust
// 归档前
assert!(!rollout_path.exists());
assert!(find_thread_path_by_id_str(codex_home.path(), &thread.id).await?.is_none());

// 回合执行后
assert!(rollout_path.exists());
let discovered_path = find_thread_path_by_id_str(codex_home.path(), &thread.id).await?;
assert_paths_match_on_disk(&discovered_path, &rollout_path)?;

// 归档后
let archived_directory = codex_home.path().join(ARCHIVED_SESSIONS_SUBDIR);
let archived_rollout_path = archived_directory.join(rollout_path.file_name()?);
assert!(!rollout_path.exists());
assert!(archived_rollout_path.exists());
```

### 订阅清理验证

```rust
// 客户端 A 归档并解归档后，清除消息缓冲区
primary.clear_message_buffer();

// 客户端 B 恢复并开始回合
let resume: ThreadResumeResponse = ...;
assert_eq!(resume.thread.status, ThreadStatus::Idle);

// 客户端 B 开始新回合
let resumed_turn_id = secondary.send_turn_start_request(...).await?;

// 验证客户端 A 不会收到回合通知
assert!(
    timeout(
        std::time::Duration::from_millis(250),
        primary.read_stream_until_notification_message("turn/started"),
    )
    .await
    .is_err()
);
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/app-server/tests/suite/v2/thread_archive.rs` - 本测试文件

### 测试支持库
- `codex-rs/app-server/tests/common/mcp_process.rs`
  - `send_thread_archive_request()` (行336)
  - `send_thread_unarchive_request()` (行372)
  - `send_thread_resume_request()` (行318)
  - `clear_message_buffer()` - 清除消息缓冲区

- `codex-rs/core/src/lib.rs`
  - `ARCHIVED_SESSIONS_SUBDIR` - 归档子目录常量
  - `find_thread_path_by_id_str()` - 按 ID 查找线程路径

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/common.rs`
  - `ThreadArchive => "thread/archive"` (行229)
  - `ThreadUnarchive => "thread/unarchive"` (行262)
  - `ThreadArchived => "thread/archived"` (通知)
  - `ThreadUnarchived => "thread/unarchived"` (通知)

- `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `ThreadArchiveParams` (行2710)
  - `ThreadArchiveResponse`
  - `ThreadUnarchiveParams` (行2793)
  - `ThreadUnarchiveResponse`
  - `ThreadStatus` (Idle, InProgress, etc.)

### 核心实现
- `codex-rs/core/src/state/session.rs` - 会话状态管理
- `codex-rs/core/src/storage/thread_storage.rs` - 线程存储
- `codex-rs/app-server/src/thread_manager.rs` - 线程管理

## 依赖与外部交互

### 直接依赖
| 依赖 | 用途 |
|-----|------|
| `tempfile::TempDir` | 隔离测试环境 |
| `tokio::time::timeout` | 异步超时控制 |
| `codex_core::ARCHIVED_SESSIONS_SUBDIR` | 归档目录常量 |
| `codex_core::find_thread_path_by_id_str` | 线程路径查找 |
| `pretty_assertions::assert_eq` | 断言增强 |

### 文件系统常量
```rust
// codex-rs/core/src/lib.rs
pub const ARCHIVED_SESSIONS_SUBDIR: &str = "archived";
```

### 配置要求
```toml
model = "mock-model"
approval_policy = "never"
sandbox_mode = "read-only"
```

## 风险、边界与改进建议

### 当前风险

1. **时序依赖**
   - 订阅清理测试依赖精确的时序控制
   - 在慢速系统上可能不稳定
   - 建议: 增加重试或更宽松的验证

2. **文件系统操作**
   - 测试依赖原子文件移动操作
   - 在部分文件系统上可能有问题
   - 建议: 添加文件系统错误处理测试

3. **并发归档**
   - 未测试多客户端同时归档同一线程
   - 建议: 添加并发归档测试

### 边界情况

1. **已归档线程再次归档**
   - 未测试重复归档的行为
   - 建议: 添加幂等性测试

2. **未归档不存在的线程**
   - 未测试解归档不存在线程的错误处理
   - 建议: 添加错误场景测试

3. **归档线程的列表查询**
   - 未测试 `thread/list` 对归档线程的过滤
   - 建议: 添加列表过滤测试

4. **大线程归档**
   - 未测试大型线程文件的归档性能
   - 建议: 添加性能基准测试

### 改进建议

1. **扩展测试覆盖**
   ```rust
   // 建议添加:
   - async fn thread_archive_already_archived()  // 重复归档
   - async fn thread_unarchive_not_archived()  // 解归档未归档线程
   - async fn thread_list_excludes_archived()  // 列表过滤
   - async fn thread_archive_concurrent()  // 并发归档
   - async fn thread_archive_large_thread()  // 大线程归档
   ```

2. **跨平台测试**
   - 测试 Windows 文件锁定场景
   - 测试网络文件系统上的归档

3. **错误恢复测试**
   - 归档过程中断的恢复
   - 磁盘满错误处理

4. **归档策略测试**
   - 自动归档策略（如 30 天未使用）
   - 归档保留策略

### 相关测试文件
- `codex-rs/app-server/tests/suite/v2/thread_list.rs` - 线程列表测试
- `codex-rs/app-server/tests/suite/v2/thread_resume.rs` - 线程恢复测试
- `codex-rs/app-server/tests/suite/v2/thread_unarchive.rs` - 解归档测试
