# ghost_snapshot.rs 研究文档

## 场景与职责

`ghost_snapshot.rs` 实现了 **GhostSnapshotTask**（幽灵快照任务），负责在 Codex 会话中创建 Git 仓库的轻量级快照。这些快照用于支持 `/undo` 功能，允许用户回滚到之前的状态。

### 核心职责
1. **仓库状态捕获**：在每次对话轮次开始时捕获 Git 仓库状态
2. **Undo 支持**：为 `/undo` 命令提供可恢复的提交点
3. **大文件处理**：智能处理大未跟踪文件和目录，避免性能问题
4. **用户警告**：当快照操作耗时过长或大文件被跳过时通知用户

### 使用场景
- 用户发送消息触发新对话轮次时
- 在后台异步执行，不阻塞主对话流程
- 通过 `tool_call_gate` 机制确保快照完成前工具调用等待

## 功能点目的

### 1. 幽灵提交（Ghost Commit）
- 创建临时 Git 提交保存当前工作区状态
- 不包含在常规分支历史中（孤儿提交）
- 记录未跟踪文件和目录信息

### 2. 性能优化
- **大文件跳过**：超过阈值（默认 10 MiB）的未跟踪文件被排除
- **大目录跳过**：超过阈值（默认 200 个文件）的未跟踪目录被排除
- **后台执行**：使用 `tokio::task::spawn_blocking` 避免阻塞异步运行时

### 3. 警告机制
- **慢快照警告**：超过 240 秒时提示用户检查 `.gitignore`
- **大文件警告**：列出被跳过的大文件
- **大目录警告**：列出被跳过的大目录

### 4. 就绪信号
- 使用 `ReadinessFlag`（`tool_call_gate`）
- 确保快照完成前，模型不会开始生成响应
- 支持取消令牌，响应用户中断

## 具体技术实现

### 关键数据结构

```rust
pub(crate) struct GhostSnapshotTask {
    token: Token,  // ReadinessFlag 的令牌
}

const SNAPSHOT_WARNING_THRESHOLD: Duration = Duration::from_secs(240);
```

### 核心执行流程

```rust
async fn run(
    self: Arc<Self>,
    session: Arc<SessionTaskContext>,
    ctx: Arc<TurnContext>,
    _input: Vec<UserInput>,
    cancellation_token: CancellationToken,
) -> Option<String>
```

**执行步骤**：

1. **警告计时器启动**（可选）
   ```rust
   let (snapshot_done_tx, snapshot_done_rx) = oneshot::channel::<()>();
   // 如果 warnings_enabled，启动超时警告任务
   ```

2. **阻塞执行快照创建**
   ```rust
   tokio::task::spawn_blocking(move || {
       let options = CreateGhostCommitOptions::new(&repo_path)
           .ghost_snapshot(ghost_snapshot_for_commit);
       create_ghost_commit_with_report(&options)
   })
   ```

3. **结果处理**
   - 成功：记录 `GhostSnapshot` 响应项，发送警告（如有）
   - `NotAGitRepository`：静默跳过
   - 其他错误：记录警告日志
   - Panic：禁用快照并通知用户

4. **标记就绪**
   ```rust
   ctx.tool_call_gate.mark_ready(token).await
   ```

### 警告格式化

```rust
fn format_snapshot_warnings(
    ignore_large_untracked_files: Option<i64>,
    ignore_large_untracked_dirs: Option<i64>,
    report: &GhostSnapshotReport,
) -> Vec<String>
```

- 最多显示 3 个大目录/文件
- 超出部分显示 "N more"
- 包含配置调整建议

### 字节格式化

```rust
fn format_bytes(bytes: i64) -> String
```

- 自动转换为 KiB/MiB
- 简化用户可读的大小显示

## 关键代码路径与文件引用

### 调用路径
```
codex.rs:new_turn_with_sub_id
  → spawn_ghost_snapshot_task
    → tasks/mod.rs:spawn_task
      → ghost_snapshot.rs:39-161 (GhostSnapshotTask::run)
```

### 相关文件
- `codex-rs/core/src/tasks/ghost_snapshot.rs`：主实现（254行）
- `codex-rs/core/src/tasks/ghost_snapshot_tests.rs`：单元测试
- `codex-rs/utils/git/src/ghost_commits.rs`：Git 操作实现
- `codex-rs/utils/git/src/lib.rs`：`GhostCommit` 结构定义

### 配置相关
- `codex-rs/core/src/config/mod.rs`：`GhostSnapshotConfig` 导入
- `codex-rs/utils/git/src/ghost_commits.rs:65-79`：配置结构定义

## 依赖与外部交互

### 外部 crate 依赖
| Crate | 用途 |
|-------|------|
| `async_trait` | 异步 trait 支持 |
| `tokio::sync::oneshot` | 快照完成信号通道 |
| `tokio_util::sync::CancellationToken` | 取消机制 |
| `tracing` | 日志记录 |
| `codex_git` | Git 操作（幽灵提交） |
| `codex_protocol` | 协议类型（`ResponseItem`, `EventMsg`） |
| `codex_utils_readiness` | 就绪标志（`Readiness`, `Token`） |

### 内部模块交互
```
ghost_snapshot.rs
  ├── uses crate::codex::TurnContext
  ├── uses crate::protocol::{EventMsg, WarningEvent}
  ├── uses crate::state::TaskKind
  ├── uses crate::tasks::{SessionTask, SessionTaskContext}
  ├── uses codex_git::{CreateGhostCommitOptions, GhostSnapshotReport, ...}
  └── uses codex_utils_readiness::{Readiness, Token}
```

### Git 操作依赖
```
codex_git::create_ghost_commit_with_report
  → CreateGhostCommitOptions
    → repo_path: &Path
    → ghost_snapshot: GhostSnapshotConfig
      → ignore_large_untracked_files: Option<i64> (default: 10 MiB)
      → ignore_large_untracked_dirs: Option<i64> (default: 200 files)
      → disable_warnings: bool
```

## 风险、边界与改进建议

### 已知风险

1. **性能问题**
   - 大型仓库的快照可能耗时数分钟
   - 当前实现会在 240 秒后发出警告，但不会自动取消
   - 建议：添加可配置的超时限制

2. **磁盘空间**
   - 每个幽灵提交都会占用 Git 对象存储空间
   - 长期运行可能积累大量孤儿对象
   - 建议：实现自动清理机制

3. **并发安全**
   - 快照操作在阻塞线程中执行，但 Git 操作本身可能与其他进程冲突
   - 建议：添加文件锁或重试机制

### 边界条件

| 边界条件 | 处理策略 |
|---------|---------|
| 非 Git 仓库 | 静默跳过，记录 info 日志 |
| 快照 panic | 捕获并禁用快照功能 |
| 取消令牌触发 | 优雅退出，不记录快照 |
| 大文件/目录 | 根据配置跳过，发送警告 |
| 警告禁用 | `ctx.ghost_snapshot.disable_warnings` 控制 |

### 改进建议

1. **可配置超时**
   ```rust
   // 建议添加
   pub snapshot_timeout: Option<Duration>,
   ```

2. **自动清理策略**
   - 保留最近 N 个快照
   - 按时间过期（如 7 天）
   - 在会话结束时清理

3. **增量快照**
   - 仅捕获自上次快照以来的变更
   - 减少 I/O 和存储开销

4. **快照验证**
   - 创建后验证快照可恢复
   - 定期测试 undo 功能

5. **用户控制**
   - 允许用户手动触发快照
   - 提供快照列表和选择性回滚

### 测试覆盖

当前测试（`ghost_snapshot_tests.rs`）：
- `large_untracked_warning_includes_threshold`：验证警告包含阈值信息
- `large_untracked_warning_disabled_when_threshold_disabled`：验证阈值禁用时无警告

建议添加：
- 非 Git 仓库场景
- 取消令牌处理
- 大文件格式化
- 并发快照场景
