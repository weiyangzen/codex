# thread_unarchive.rs 研究文档

## 场景与职责

`thread_unarchive.rs` 是 Codex App Server V2 API 的集成测试文件，专注于测试 **Thread Unarchive（线程解归档）** 功能。该功能允许将已归档的线程从归档目录移回活跃会话目录，使其重新可访问。

### 核心测试场景

1. **线程生命周期完整流程测试**：创建线程 → 执行对话回合 → 归档线程 → 解归档线程 → 验证状态恢复
2. **文件系统操作验证**：验证归档/解归档过程中文件在磁盘上的实际移动
3. **时间戳更新验证**：验证解归档操作会更新线程的 `updated_at` 字段
4. **Wire 协议契约验证**：验证 API 响应中字段序列化行为（如 `name: null`）

---

## 功能点目的

### Thread Unarchive 功能

Thread Unarchive 是 Codex 线程管理的重要组成部分：

- **归档（Archive）**：将不活跃的线程从 `sessions/` 目录移动到 `archived_sessions/` 目录，减少主目录 clutter
- **解归档（Unarchive）**：将已归档的线程恢复到 `sessions/` 目录，使其重新可加载和编辑

### 关键业务规则

1. 解归档操作会将线程文件从归档目录移回会话目录
2. 解归档会更新线程的 `updated_at` 时间戳
3. 解归档后的线程状态为 `NotLoaded`
4. 线程标题字段 `name` 在未设置时必须序列化为 `null`（而非省略）

---

## 具体技术实现

### 关键流程

```
thread_unarchive_moves_rollout_back_into_sessions_directory
├── 1. 创建 Mock Responses Server
│   └── create_mock_responses_server_repeating_assistant("Done")
├── 2. 创建临时 CODEX_HOME 目录
│   └── TempDir::new()
├── 3. 写入 config.toml 配置
│   └── model_provider = "mock_provider"
├── 4. 启动 MCP 进程
│   └── McpProcess::new(codex_home)
├── 5. 初始化连接
│   └── mcp.initialize()
├── 6. 创建线程 (thread/start)
│   └── ThreadStartParams { model: Some("mock-model") }
├── 7. 启动对话回合 (turn/start)
│   └── TurnStartParams { thread_id, input: [UserInput::Text] }
├── 8. 验证线程文件存在于 sessions 目录
│   └── find_thread_path_by_id_str(codex_home, &thread.id)
├── 9. 归档线程 (thread/archive)
│   └── ThreadArchiveParams { thread_id }
├── 10. 验证线程文件移动到 archived_sessions 目录
│    └── find_archived_thread_path_by_id_str(codex_home, &thread.id)
├── 11. 修改归档文件时间戳（用于验证更新）
│    └── file.set_times(FileTimes::new().set_modified(old_time))
├── 12. 解归档线程 (thread/unarchive)
│    └── ThreadUnarchiveParams { thread_id }
├── 13. 验证响应和通知
│    ├── ThreadUnarchiveResponse { thread }
│    └── ThreadUnarchivedNotification
├── 14. 验证文件系统状态
│    ├── 验证线程文件存在于 sessions 目录
│    └── 验证归档文件不存在于 archived_sessions 目录
└── 15. 验证 updated_at 已更新
     └── assert!(unarchived_thread.updated_at > old_timestamp)
```

### 数据结构

#### ThreadUnarchiveParams
```rust
pub struct ThreadUnarchiveParams {
    pub thread_id: String,
}
```

#### ThreadUnarchiveResponse
```rust
pub struct ThreadUnarchiveResponse {
    pub thread: Thread,  // 解归档后的线程信息
}
```

#### ThreadUnarchivedNotification
```rust
pub struct ThreadUnarchivedNotification {
    pub thread_id: String,
}
```

### 核心依赖函数

| 函数 | 来源 | 用途 |
|------|------|------|
| `find_thread_path_by_id_str` | `codex_core::rollout::list` | 查找活跃会话目录中的线程文件 |
| `find_archived_thread_path_by_id_str` | `codex_core::rollout::list` | 查找归档目录中的线程文件 |
| `McpProcess::send_thread_unarchive_request` | `app_test_support::mcp_process` | 发送解归档请求 |

---

## 关键代码路径与文件引用

### 测试文件
- **位置**: `codex-rs/app-server/tests/suite/v2/thread_unarchive.rs`
- **行数**: 198 行

### 协议定义
- **位置**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
- **相关结构**: 
  - `ThreadUnarchiveParams` (行 2793-2795)
  - `ThreadUnarchiveResponse` (行 2797-2800)
  - `ThreadUnarchivedNotification` (行 2802-2805)

### 核心实现
- **位置**: `codex-rs/core/src/rollout/list.rs`
- **关键函数**:
  - `find_thread_path_by_id_str` (行 1250-1255)
  - `find_archived_thread_path_by_id_str` (行 1258-1263)
  - `find_thread_path_by_id_str_in_subdir` (行 1170-1245)

### 目录常量
```rust
// codex-rs/core/src/rollout/mod.rs
const SESSIONS_SUBDIR: &str = "sessions";
const ARCHIVED_SESSIONS_SUBDIR: &str = "archived_sessions";
```

### 测试支持库
- **位置**: `codex-rs/app-server/tests/common/mcp_process.rs`
- **方法**: `send_thread_unarchive_request` (行 372-379)

---

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `tempfile::TempDir` | 创建临时测试目录 |
| `tokio::time::timeout` | 测试超时控制 |
| `wiremock::MockServer` | Mock OpenAI Responses API |
| `serde_json` | JSON 序列化/反序列化 |

### 内部模块依赖

```
thread_unarchive.rs
├── app_test_support::McpProcess
├── app_test_support::create_mock_responses_server_repeating_assistant
├── app_test_support::to_response
├── codex_app_server_protocol::* (协议类型)
├── codex_core::find_archived_thread_path_by_id_str
├── codex_core::find_thread_path_by_id_str
├── pretty_assertions::assert_eq
└── tempfile::TempDir
```

### 文件系统交互

测试涉及以下文件系统操作：

1. **创建**: `config.toml` 在临时 CODEX_HOME 中
2. **创建**: 线程 rollout 文件在 `sessions/YYYY/MM/DD/` 目录
3. **移动**: 归档时将文件从 `sessions/` 移到 `archived_sessions/`
4. **移动**: 解归档时将文件从 `archived_sessions/` 移回 `sessions/`
5. **修改**: 使用 `FileTimes::set_modified()` 修改归档文件时间戳

---

## 风险、边界与改进建议

### 潜在风险

1. **时间戳精度问题**
   - 测试依赖于文件修改时间戳的比较
   - 在某些文件系统上，时间戳精度可能不足（如 FAT32 只有 2 秒精度）
   - **缓解**: 测试使用 1 秒的 old_time（UNIX_EPOCH + 1s），留有足够余量

2. **并发测试冲突**
   - 测试使用临时目录，但并发执行时可能遇到资源竞争
   - **缓解**: `TempDir` 确保每个测试有独立目录

3. **Mock Server 状态**
   - 测试依赖 Mock Server 返回固定的 "Done" 响应
   - 如果 Mock Server 行为改变，测试可能失败

### 边界情况

1. **线程不存在**: 测试未覆盖尝试解归档不存在的线程的场景
2. **权限问题**: 测试未覆盖文件系统权限不足的场景
3. **磁盘空间**: 测试未处理磁盘空间不足的情况

### 改进建议

1. **增加错误场景测试**
   ```rust
   // 建议添加：测试解归档不存在的线程
   async fn thread_unarchive_returns_error_for_nonexistent_thread() -> Result<()>
   
   // 建议添加：测试重复解归档同一线程
   async fn thread_unarchive_is_idempotent() -> Result<()>
   ```

2. **增加并发测试**
   - 测试同时归档和解归档同一线程的行为
   - 测试多线程同时解归档不同线程的性能

3. **优化时间戳验证**
   - 考虑使用 mock 时钟来消除对实际文件系统时间戳的依赖
   - 或者增加时间戳容差范围

4. **增加状态转换验证**
   - 验证线程在归档/解归档过程中的状态转换
   - 验证通知消息的顺序和内容

### 相关测试文件

- `thread_archive.rs`: 测试归档功能（与 unarchive 互补）
- `thread_resume.rs`: 测试线程恢复功能
- `thread_read.rs`: 测试线程读取功能
