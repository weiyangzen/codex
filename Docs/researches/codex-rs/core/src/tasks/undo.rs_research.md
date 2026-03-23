# undo.rs 研究文档

## 场景与职责

`undo.rs` 实现了 **UndoTask**（撤销任务），用于回滚 Codex 会话到之前的 Git 仓库状态。该任务通过恢复幽灵提交（ghost commit）实现代码变更的撤销。

### 核心职责
1. **幽灵提交恢复**：从最近的 GhostSnapshot 恢复仓库状态
2. **历史管理**：移除已撤销的快照项目，更新对话历史
3. **状态报告**：发送撤销开始/完成事件，报告成功或失败
4. **取消支持**：响应取消令牌，优雅终止

### 使用场景
- 用户执行 `/undo` 命令
- 需要回滚到之前保存的代码状态
- 撤销意外或不需要的代码变更

## 功能点目的

### 1. 状态回滚
Undo 任务执行以下操作：
1. 在对话历史中查找最近的 `GhostSnapshot`
2. 使用 `restore_ghost_commit_with_options` 恢复仓库状态
3. 从历史中移除已使用的快照
4. 更新对话历史（保留参考上下文）

### 2. 事件通知
发送生命周期事件：
- `UndoStarted`：撤销操作开始
- `UndoCompleted`：撤销操作完成（成功或失败）

### 3. 错误处理
处理多种错误场景：
- **无可用快照**：提示用户没有可撤销的状态
- **Git 操作失败**：报告具体错误信息
- **任务取消**：报告撤销已取消

## 具体技术实现

### 关键数据结构

```rust
pub(crate) struct UndoTask;

impl UndoTask {
    pub(crate) fn new() -> Self {
        Self
    }
}
```

### SessionTask 实现

```rust
#[async_trait]
impl SessionTask for UndoTask {
    fn kind(&self) -> TaskKind {
        TaskKind::Regular  // 注意：使用 Regular 而非专门的 Undo 类型
    }

    fn span_name(&self) -> &'static str {
        "session_task.undo"
    }

    async fn run(...) -> Option<String> {
        // 实现细节...
    }
}
```

**注意**：`UndoTask` 使用 `TaskKind::Regular` 而非专门的 `TaskKind::Undo`，这意味着它在遥测中被归类为常规任务。

### 核心执行流程

```rust
async fn run(
    self: Arc<Self>,
    session: Arc<SessionTaskContext>,
    ctx: Arc<TurnContext>,
    _input: Vec<UserInput>,
    cancellation_token: CancellationToken,
) -> Option<String> {
    // 1. 记录指标
    session.session.services.session_telemetry
        .counter("codex.task.undo", 1, &[]);

    // 2. 发送开始事件
    sess.send_event(ctx.as_ref(), EventMsg::UndoStarted(...)).await;

    // 3. 检查取消
    if cancellation_token.is_cancelled() {
        sess.send_event(..., EventMsg::UndoCompleted { success: false, ... }).await;
        return None;
    }

    // 4. 查找最近的幽灵提交
    let history = sess.clone_history().await;
    let items = history.raw_items().to_vec();
    let Some((idx, ghost_commit)) = items.iter().enumerate().rev()
        .find_map(|(idx, item)| match item {
            ResponseItem::GhostSnapshot { ghost_commit } => Some((idx, ghost_commit.clone())),
            _ => None,
        })
    else {
        // 无可用快照
        completed.message = Some("No ghost snapshot available to undo.".to_string());
        sess.send_event(..., EventMsg::UndoCompleted(completed)).await;
        return None;
    };

    // 5. 恢复幽灵提交
    let restore_result = tokio::task::spawn_blocking(move || {
        let options = RestoreGhostCommitOptions::new(&repo_path)
            .ghost_snapshot(ghost_snapshot);
        restore_ghost_commit_with_options(&options, &ghost_commit)
    }).await;

    // 6. 处理结果
    match restore_result {
        Ok(Ok(())) => {
            // 成功：移除快照，更新历史
            items.remove(idx);
            let reference_context_item = sess.reference_context_item().await;
            sess.replace_history(items, reference_context_item).await;
            completed.success = true;
            completed.message = Some(format!("Undo restored snapshot {short_id}."));
        }
        Ok(Err(err)) => {
            // Git 错误
            completed.message = Some(format!("Failed to restore snapshot {commit_id}: {err}"));
        }
        Err(err) => {
            // 任务 panic
            completed.message = Some(format!("Failed to restore snapshot {commit_id}: {err}"));
        }
    }

    // 7. 发送完成事件
    sess.send_event(ctx.as_ref(), EventMsg::UndoCompleted(completed)).await;
    None
}
```

### 幽灵提交查找

```rust
let Some((idx, ghost_commit)) = items
    .iter()
    .enumerate()
    .rev()  // 从最新开始查找
    .find_map(|(idx, item)| match item {
        ResponseItem::GhostSnapshot { ghost_commit } => {
            Some((idx, ghost_commit.clone()))
        }
        _ => None,
    })
```

**关键点**：
- 使用 `.rev()` 从最新历史项开始查找
- 返回索引和克隆的 `GhostCommit`
- 索引用于后续从历史中移除

### 仓库恢复

```rust
let restore_result = tokio::task::spawn_blocking(move || {
    let options = RestoreGhostCommitOptions::new(&repo_path)
        .ghost_snapshot(ghost_snapshot);
    restore_ghost_commit_with_options(&options, &ghost_commit)
}).await;
```

**设计考虑**：
- 使用 `spawn_blocking` 避免阻塞异步运行时
- Git 操作可能涉及大量文件 I/O
- `RestoreGhostCommitOptions` 包含大文件/目录忽略配置

### 历史更新

```rust
// 成功恢复后
items.remove(idx);  // 移除已使用的快照
let reference_context_item = sess.reference_context_item().await;
sess.replace_history(items, reference_context_item).await;
```

**注意**：
- 移除已使用的快照防止重复撤销
- 保留 `reference_context_item` 维持上下文引用

## 关键代码路径与文件引用

### 调用路径
```
codex.rs:4847-4850 (undo)
  → spawn_task(Arc<UndoTask>)
    → tasks/mod.rs:spawn_task
      → undo.rs:38-131 (UndoTask::run)
```

### 相关文件
- `codex-rs/core/src/tasks/undo.rs`：本文件（131行）
- `codex-rs/core/src/tasks/mod.rs`：`SessionTask` trait
- `codex-rs/core/src/codex.rs`：`Session::undo`
- `codex-rs/utils/git/src/ghost_commits.rs`：`restore_ghost_commit_with_options`
- `codex-rs/utils/git/src/lib.rs`：`GhostCommit` 定义

### 依赖类型
- `codex_git::RestoreGhostCommitOptions`：恢复选项
- `codex_git::restore_ghost_commit_with_options`：恢复函数
- `codex_protocol::models::ResponseItem::GhostSnapshot`：快照项目
- `codex_protocol::protocol::{UndoStartedEvent, UndoCompletedEvent}`：事件

## 依赖与外部交互

### 外部 crate
| Crate | 用途 |
|-------|------|
| `async_trait` | 异步 trait |
| `tokio_util::sync::CancellationToken` | 取消机制 |
| `tokio::task::spawn_blocking` | 阻塞 Git 操作 |
| `tracing` | 日志记录 |
| `codex_git` | Git 幽灵提交操作 |
| `codex_protocol` | 协议类型 |

### 内部模块
```
undo.rs
  ├── uses crate::codex::TurnContext
  ├── uses crate::protocol::{EventMsg, UndoCompletedEvent, UndoStartedEvent}
  ├── uses crate::state::TaskKind
  ├── uses crate::tasks::{SessionTask, SessionTaskContext}
  ├── uses codex_git::{RestoreGhostCommitOptions, restore_ghost_commit_with_options}
  └── uses codex_protocol::models::ResponseItem
```

### Git 操作依赖
```
restore_ghost_commit_with_options
  → RestoreGhostCommitOptions
    → repo_path: &Path
    → ghost_snapshot: GhostSnapshotConfig
      → ignore_large_untracked_files: Option<i64>
      → ignore_large_untracked_dirs: Option<i64>
```

## 风险、边界与改进建议

### 已知风险

1. **单级撤销**
   - 当前实现仅支持撤销到最近快照
   - 多级撤销需要多次执行 `/undo`
   - 每次撤销后快照被移除，无法再次撤销到同一状态

2. **并发修改**
   - 撤销操作在后台执行
   - 如果用户同时修改文件，可能导致冲突
   - Git 恢复操作可能失败或产生意外结果

3. **历史丢失**
   - 撤销后，被撤销轮次的对话历史保留
   - 但幽灵提交本身从历史中移除
   - 无法"重做"（redo）撤销操作

4. **大仓库性能**
   - 大型仓库的恢复操作可能耗时较长
   - 当前无进度指示
   - 取消令牌检查仅在操作开始前

### 边界条件

| 场景 | 处理 |
|------|------|
| 无可用快照 | 发送失败事件，提示用户 |
| 取消令牌触发 | 发送取消事件，不执行恢复 |
| Git 操作失败 | 记录警告，发送失败事件 |
| 任务 panic | 记录错误，发送失败事件 |
| 非 Git 仓库 | 幽灵快照任务会跳过，undo 找不到快照 |

### 改进建议

1. **多级撤销/重做**
   ```rust
   // 保留快照历史，支持多级撤销
   struct UndoStack {
       snapshots: Vec<GhostCommit>,
       current_index: usize,
   }
   ```

2. **撤销预览**
   - 执行前显示将要恢复的文件变更
   - 让用户确认后再执行

3. **进度指示**
   ```rust
   // 对于大仓库，发送进度事件
   EventMsg::UndoProgress { processed_files, total_files }
   ```

4. **选择性撤销**
   - 允许用户选择撤销特定文件
   - 而非整个仓库状态

5. **冲突处理**
   ```rust
   // 恢复前检查工作区状态
   if has_uncommitted_changes() {
       // 提示用户提交或暂存
   }
   ```

6. **测试覆盖**
   - 当前无专门测试文件
   - 建议添加：
     - 成功撤销场景
     - 无快照场景
     - Git 错误处理
     - 取消处理
