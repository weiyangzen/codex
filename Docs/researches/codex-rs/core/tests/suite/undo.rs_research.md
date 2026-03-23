# undo.rs 深入研究文档

## 场景与职责

`undo.rs` 是 Codex 核心测试套件中的关键测试文件，负责验证**撤销（Undo）**功能的正确性。该功能基于 Git 的 "Ghost Commit"（幽灵提交）机制，允许用户撤销 AI 助手在一次回合（Turn）中对工作区所做的更改，恢复到操作前的状态。

### 核心场景
1. **文件创建撤销**：撤销 AI 创建的新文件
2. **文件修改撤销**：撤销 AI 对已有文件的修改
3. **文件移动/重命名撤销**：撤销 AI 的文件移动操作
4. **多回合顺序撤销**：支持连续撤销多个回合的更改
5. **边界保护**：确保撤销不影响用户手动修改的文件

---

## 功能点目的

### 1. Ghost Commit 机制

Ghost Commit 是一种特殊的 Git 提交，用于捕获工作区的完整状态：

- **不可见**：不加入任何分支，不污染用户提交历史
- **完整**：捕获 tracked、untracked 和 ignored 文件
- **可恢复**：可以通过 Git 操作完整恢复到该状态
- **临时**：生命周期与 Codex 会话绑定

### 2. 撤销生命周期

```
用户提交 Turn
    │
    ▼
AI 执行操作（apply_patch、shell 等）
    │
    ▼
创建 Ghost Commit ──► 存储到 ResponseItem::GhostSnapshot
    │
    ▼
用户请求 Undo
    │
    ▼
恢复 Ghost Commit ──► 工作区回到操作前状态
    │
    ▼
从历史中移除 GhostSnapshot 项
```

### 3. 保护边界

- **用户手动修改**：撤销不影响用户在回合后手动修改的文件
- **Staged 更改**：保留用户的 staged 更改
- **Ignored 文件**：正确处理 .gitignore 中的文件
- **大型文件**：可配置忽略超过阈值的大型未跟踪文件

---

## 具体技术实现

### 关键流程

#### 1. Ghost Commit 创建（`codex-rs/utils/git/src/ghost_commits.rs`）

```rust
pub fn create_ghost_commit(
    options: &CreateGhostCommitOptions<'_>
) -> Result<GhostCommit, GitToolingError> {
    // 1. 确保是 Git 仓库
    ensure_git_repository(options.repo_path)?;
    
    // 2. 解析仓库根目录
    let repo_root = resolve_repository_root(options.repo_path)?;
    let repo_prefix = repo_subdir(repo_root.as_path(), options.repo_path);
    
    // 3. 获取当前 HEAD 作为父提交
    let parent = resolve_head(repo_root.as_path())?;
    
    // 4. 捕获工作区状态
    let status_snapshot = capture_status_snapshot(
        repo_root.as_path(),
        repo_prefix.as_deref(),
        options.ghost_snapshot.ignore_large_untracked_files,
        options.ghost_snapshot.ignore_large_untracked_dirs,
        &force_include,
    )?;
    
    // 5. 使用临时索引（不污染用户索引）
    let index_tempdir = Builder::new().prefix("codex-git-index-").tempdir()?;
    let index_path = index_tempdir.path().join("index");
    
    // 6. 预填充 HEAD 到临时索引
    if let Some(parent_sha) = parent.as_deref() {
        run_git_for_status(
            repo_root.as_path(),
            vec![OsString::from("read-tree"), OsString::from(parent_sha)],
            Some(base_env.as_slice()),
        )?;
    }
    
    // 7. 添加 tracked 和新的 untracked 文件到索引
    add_paths_to_index(repo_root.as_path(), base_env.as_slice(), &index_paths)?;
    
    // 8. 写入树对象
    let tree_id = run_git_for_stdout(
        repo_root.as_path(),
        vec![OsString::from("write-tree")],
        Some(base_env.as_slice()),
    )?;
    
    // 9. 创建提交（不更新任何引用）
    let commit_id = run_git_for_stdout(
        repo_root.as_path(),
        vec![
            OsString::from("commit-tree"),
            OsString::from(&tree_id),
            OsString::from("-p"), OsString::from(parent),  // 父提交
            OsString::from("-m"), OsString::from("codex snapshot"),
        ],
        Some(commit_env.as_slice()),
    )?;
    
    // 10. 创建 GhostCommit 对象
    Ok(GhostCommit::new(
        commit_id,
        parent,
        preexisting_untracked_files,
        preexisting_untracked_dirs,
    ))
}
```

#### 2. Ghost Commit 恢复（`codex-rs/utils/git/src/ghost_commits.rs`）

```rust
pub fn restore_ghost_commit_with_options(
    options: &RestoreGhostCommitOptions<'_>,
    commit: &GhostCommit,
) -> Result<(), GitToolingError> {
    // 1. 捕获当前未跟踪文件（用于清理新创建的文件）
    let current_untracked = capture_existing_untracked(...)?;
    
    // 2. 恢复工作区到 Ghost Commit 状态
    restore_to_commit_inner(repo_root.as_path(), repo_prefix.as_deref(), commit.id())?;
    
    // 3. 清理新创建的未跟踪文件
    remove_new_untracked(
        repo_root.as_path(),
        commit.preexisting_untracked_files(),
        commit.preexisting_untracked_dirs(),
        current_untracked,
    )
}

fn restore_to_commit_inner(
    repo_root: &Path,
    repo_prefix: Option<&Path>,
    commit_id: &str,
) -> Result<(), GitToolingError> {
    // 使用 git restore 恢复工作区（不碰索引）
    // git restore --source <commit> --worktree -- <prefix>
    let mut restore_args = vec![
        OsString::from("restore"),
        OsString::from("--source"),
        OsString::from(commit_id),
        OsString::from("--worktree"),  // 只恢复工作区，保留索引
        OsString::from("--"),
    ];
    // ...
}
```

#### 3. Ghost Snapshot 任务（`codex-rs/core/src/tasks/ghost_snapshot.rs`）

```rust
#[async_trait]
impl SessionTask for GhostSnapshotTask {
    async fn run(
        self: Arc<Self>,
        session: Arc<SessionTaskContext>,
        ctx: Arc<TurnContext>,
        _input: Vec<UserInput>,
        cancellation_token: CancellationToken,
    ) -> Option<String> {
        // 1. 超时警告任务（240秒阈值）
        let (snapshot_done_tx, snapshot_done_rx) = oneshot::channel::<()>();
        tokio::task::spawn(async move {
            tokio::select! {
                _ = tokio::time::sleep(SNAPSHOT_WARNING_THRESHOLD) => {
                    // 发送警告：快照耗时过长
                }
                _ = snapshot_done_rx => {}
                _ = cancellation_token_for_warning.cancelled() => {}
            }
        });
        
        // 2. 在阻塞线程池中执行 Git 操作
        let result = tokio::task::spawn_blocking(move || {
            create_ghost_commit_with_report(&options)
        }).await;
        
        // 3. 处理结果
        match result {
            Ok(Ok((ghost_commit, report))) => {
                // 发送警告（如大文件被忽略）
                for message in format_snapshot_warnings(...) {
                    session.send_event(...).await;
                }
                
                // 记录 GhostSnapshot 到历史
                session.record_conversation_items(&ctx, &[ResponseItem::GhostSnapshot {
                    ghost_commit: ghost_commit.clone(),
                }]).await;
            }
            // 错误处理...
        }
    }
}
```

#### 4. Undo 任务（`codex-rs/core/src/tasks/undo.rs`）

```rust
#[async_trait]
impl SessionTask for UndoTask {
    async fn run(
        self: Arc<Self>,
        session: Arc<SessionTaskContext>,
        ctx: Arc<TurnContext>,
        _input: Vec<UserInput>,
        cancellation_token: CancellationToken,
    ) -> Option<String> {
        // 1. 发送 UndoStarted 事件
        sess.send_event(
            ctx.as_ref(),
            EventMsg::UndoStarted(UndoStartedEvent {
                message: Some("Undo in progress...".to_string()),
            }),
        ).await;
        
        // 2. 查找最近的 GhostSnapshot
        let Some((idx, ghost_commit)) = items
            .iter()
            .enumerate()
            .rev()
            .find_map(|(idx, item)| match item {
                ResponseItem::GhostSnapshot { ghost_commit } => Some((idx, ghost_commit.clone())),
                _ => None,
            })
        else {
            // 无可用快照，返回失败
            completed.message = Some("No ghost snapshot available to undo.".to_string());
            sess.send_event(ctx.as_ref(), EventMsg::UndoCompleted(completed)).await;
            return None;
        };
        
        // 3. 恢复 Ghost Commit
        let restore_result = tokio::task::spawn_blocking(move || {
            let options = RestoreGhostCommitOptions::new(&repo_path)
                .ghost_snapshot(ghost_snapshot);
            restore_ghost_commit_with_options(&options, &ghost_commit)
        }).await;
        
        // 4. 处理结果
        match restore_result {
            Ok(Ok(())) => {
                // 从历史中移除 GhostSnapshot 项
                items.remove(idx);
                sess.replace_history(items, reference_context_item).await;
                completed.success = true;
            }
            Ok(Err(err)) => { /* 记录警告 */ }
            Err(err) => { /* 记录错误 */ }
        }
        
        // 5. 发送 UndoCompleted 事件
        sess.send_event(ctx.as_ref(), EventMsg::UndoCompleted(completed)).await;
    }
}
```

### 数据结构

#### 1. `GhostCommit`（`codex-rs/utils/git/src/lib.rs`）

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GhostCommit {
    id: String,                    // 提交 SHA
    parent: Option<String>,        // 父提交 SHA
    preexisting_untracked_files: Vec<PathBuf>,  // 快照前已存在的未跟踪文件
    preexisting_untracked_dirs: Vec<PathBuf>,   // 快照前已存在的未跟踪目录
}

impl GhostCommit {
    pub fn new(
        id: String,
        parent: Option<String>,
        preexisting_untracked_files: Vec<PathBuf>,
        preexisting_untracked_dirs: Vec<PathBuf>,
    ) -> Self {
        Self { id, parent, preexisting_untracked_files, preexisting_untracked_dirs }
    }
    
    pub fn id(&self) -> &str { &self.id }
    pub fn parent(&self) -> Option<&str> { self.parent.as_deref() }
    pub fn preexisting_untracked_files(&self) -> &[PathBuf] { &self.preexisting_untracked_files }
    pub fn preexisting_untracked_dirs(&self) -> &[PathBuf] { &self.preexisting_untracked_dirs }
}
```

#### 2. `GhostSnapshotConfig`（配置）

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GhostSnapshotConfig {
    pub ignore_large_untracked_files: Option<i64>,  // 忽略大于此值的文件（字节）
    pub ignore_large_untracked_dirs: Option<i64>,   // 忽略包含超过此数量文件的目录
    pub disable_warnings: bool,                      // 是否禁用警告
}

impl Default for GhostSnapshotConfig {
    fn default() -> Self {
        Self {
            ignore_large_untracked_files: Some(10 * 1024 * 1024),  // 10MB
            ignore_large_untracked_dirs: Some(200),
            disable_warnings: false,
        }
    }
}
```

#### 3. `ResponseItem::GhostSnapshot`（协议层）

```rust
pub enum ResponseItem {
    // ...
    GhostSnapshot {
        ghost_commit: GhostCommit,
    },
    // ...
}
```

#### 4. Undo 事件（`codex-rs/protocol/src/protocol.rs`）

```rust
#[derive(Debug, Clone, Deserialize, Serialize, JsonSchema, TS)]
pub struct UndoStartedEvent {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize, JsonSchema, TS)]
pub struct UndoCompletedEvent {
    pub success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}
```

---

## 关键代码路径与文件引用

### 核心实现文件

| 文件 | 职责 |
|------|------|
| `codex-rs/utils/git/src/ghost_commits.rs` | Ghost Commit 创建和恢复的核心逻辑 |
| `codex-rs/utils/git/src/lib.rs` | `GhostCommit` 结构体定义 |
| `codex-rs/core/src/tasks/ghost_snapshot.rs` | Ghost Snapshot 异步任务 |
| `codex-rs/core/src/tasks/undo.rs` | Undo 异步任务 |
| `codex-rs/core/src/features.rs` | `GhostCommit` 功能开关 |

### 协议层文件

| 文件 | 职责 |
|------|------|
| `codex-rs/protocol/src/protocol.rs` | `UndoStartedEvent`、`UndoCompletedEvent` 定义 |
| `codex-rs/protocol/src/models.rs` | `ResponseItem::GhostSnapshot` 定义 |

### 测试文件

| 文件 | 职责 |
|------|------|
| `codex-rs/core/tests/suite/undo.rs` | Undo 功能集成测试 |
| `codex-rs/utils/git/src/ghost_commits.rs`（tests 模块）| Ghost Commit 单元测试 |

### 关键代码路径

```
1. 回合完成触发快照
   codex-rs/core/src/codex.rs
   └── 回合处理完成
       └── 触发 GhostSnapshotTask
           └── codex-rs/core/src/tasks/ghost_snapshot.rs
               └── create_ghost_commit_with_report
                   └── codex-rs/utils/git/src/ghost_commits.rs

2. 用户请求 Undo
   codex-rs/core/src/codex.rs
   └── 处理 Op::Undo
       └── 触发 UndoTask
           └── codex-rs/core/src/tasks/undo.rs
               └── restore_ghost_commit_with_options
                   └── codex-rs/utils/git/src/ghost_commits.rs

3. 功能开关
   codex-rs/core/src/features.rs
   └── Feature::GhostCommit
       └── 控制 Ghost Snapshot 和 Undo 功能的启用/禁用
```

---

## 依赖与外部交互

### 内部依赖

```rust
// Git 工具库
use codex_git::{
    CreateGhostCommitOptions,
    RestoreGhostCommitOptions,
    create_ghost_commit_with_report,
    restore_ghost_commit_with_options,
};

// 协议类型
use codex_protocol::protocol::{
    EventMsg, Op, UndoCompletedEvent, UndoStartedEvent,
};
use codex_protocol::models::ResponseItem;

// 核心类型
use codex_core::{
    CodexThread,
    features::Feature,
};

// 测试支持
use core_test_support::{
    responses,
    test_codex::TestCodexHarness,
    wait_for_event_match,
};
```

### 外部系统交互

1. **Git 命令行**
   - `git status --porcelain=2 -z --untracked-files=all`：捕获工作区状态
   - `git read-tree HEAD`：预填充临时索引
   - `git add --all`：添加文件到索引
   - `git write-tree`：写入树对象
   - `git commit-tree`：创建提交（不更新引用）
   - `git restore --source <commit> --worktree`：恢复工作区

2. **文件系统**
   - 创建临时目录存储 Git 索引
   - 文件创建、修改、删除操作

### 测试基础设施

```rust
// Git 操作辅助函数
fn git(path: &Path, args: &[&str]) -> Result<()> {
    let status = Command::new("git")
        .args(args)
        .current_dir(path)
        .status()?;
    // ...
}

fn init_git_repo(path: &Path) -> Result<()> {
    git(path, &["init", "--initial-branch=main"])?;
    git(path, &["config", "core.autocrlf", "false"])?;
    git(path, &["config", "user.name", "Codex Tests"])?;
    git(path, &["config", "user.email", "codex-tests@example.com"])?;
    // 创建初始提交...
}

// 测试 harness
async fn undo_harness() -> Result<TestCodexHarness> {
    let builder = test_codex()
        .with_model("gpt-5.1")
        .with_config(|config| {
            config.include_apply_patch_tool = true;
            config.features.enable(Feature::GhostCommit).expect(...);
        });
    TestCodexHarness::with_builder(builder).await
}
```

---

## 风险、边界与改进建议

### 已知风险

1. **Git 状态不一致**
   - 如果用户在 Codex 操作期间手动修改 Git 状态，可能导致快照不完整
   - **缓解**：Ghost Snapshot 任务尽快执行，减少竞争窗口

2. **大型仓库性能**
   - 大型仓库的快照操作可能耗时较长
   - **缓解**：
     - 可配置的忽略阈值（`ignore_large_untracked_files`、`ignore_large_untracked_dirs`）
     - 超时警告机制（240秒阈值）
     - 异步执行不阻塞主流程

3. **并发修改**
   - 用户手动编辑与 Undo 操作可能冲突
   - **缓解**：Undo 会覆盖手动修改（按设计），但保留 staged 更改

4. **非 Git 仓库**
   - 非 Git 仓库无法使用 Undo 功能
   - **缓解**：优雅降级，记录日志但不报错

### 边界情况

| 场景 | 处理方式 |
|------|----------|
| 非 Git 仓库 | 跳过快照，Undo 返回失败 |
| 空仓库（无提交）| 创建无父提交的 Ghost Commit |
| 大型未跟踪文件 | 可配置忽略，保留文件但内容不快照 |
| 大型未跟踪目录 | 可配置忽略，目录整体排除 |
| 用户 staged 更改 | 保留 staged 状态，仅恢复工作区 |
| 手动修改后 Undo | 覆盖手动修改（预期行为）|
| 连续 Undo | 依次撤销多个回合，每次撤销最后一个快照 |
| 无可用快照 | 返回 "No ghost snapshot available to undo." |

### 改进建议

1. **增量快照**
   - 只捕获与上一个快照的差异，减少存储和时间开销
   - 使用 Git 的增量存储机制

2. **快照压缩**
   - 对大文件使用 Git LFS 或类似机制
   - 定期清理旧的 Ghost Commit

3. **可观测性增强**
   - 记录快照大小和耗时遥测
   - 显示快照创建进度
   - 提供快照历史查看功能

4. **冲突处理**
   - 检测用户手动修改与快照的差异
   - 提供交互式冲突解决
   - 支持选择性撤销（只撤销某些文件的更改）

5. **跨平台改进**
   - 优化 Windows 上的 Git 操作性能
   - 处理换行符差异（`core.autocrlf`）

### 相关配置

```toml
# config.toml 示例
[features]
ghost_commit = true  # 启用 Ghost Commit 功能

[ghost_snapshot]
ignore_large_untracked_files = 10485760  # 10MB，忽略大于此值的文件
ignore_large_untracked_dirs = 200        # 忽略包含超过 200 个文件的目录
disable_warnings = false                 # 不禁用警告
```

---

## 测试用例详解

### 1. `undo_removes_new_file_created_during_turn`

**目的**：验证撤销能删除 AI 创建的新文件

**流程**：
1. 初始化 Git 仓库
2. AI 回合：创建 `new_file.txt`
3. 验证文件存在
4. 执行 Undo
5. 验证文件被删除

### 2. `undo_restores_tracked_file_edit`

**目的**：验证撤销能恢复已跟踪文件的修改

**流程**：
1. 创建并提交 `tracked.txt`
2. AI 回合：修改文件内容
3. 验证修改生效
4. 执行 Undo
5. 验证内容恢复，Git 状态干净

### 3. `undo_restores_untracked_file_edit`

**目的**：验证撤销能恢复未跟踪文件的修改

**流程**：
1. 创建未跟踪文件 `notes.txt`
2. AI 回合：修改文件
3. 执行 Undo
4. 验证内容恢复到原始状态

### 4. `undo_reverts_only_latest_turn`

**目的**：验证只撤销最近一个回合

**流程**：
1. 回合 1：创建文件，内容 "first version"
2. 回合 2：修改内容 "second version"
3. 执行 Undo
4. 验证内容回到 "first version"（而非删除文件）

### 5. `undo_does_not_touch_unrelated_files`

**目的**：验证撤销不影响无关文件

**流程**：
1. 创建多个 tracked、untracked、ignored 文件
2. AI 回合：修改部分文件
3. 执行 Undo
4. 验证无关文件保持不变

### 6. `undo_sequential_turns_consumes_snapshots`

**目的**：验证连续撤销消耗快照

**流程**：
1. 执行 3 个回合，每回合修改文件
2. 连续执行 3 次 Undo
3. 验证每次撤销一个回合
4. 第 4 次 Undo 失败（无可用快照）

### 7. `undo_without_snapshot_reports_failure`

**目的**：验证无快照时 Undo 返回失败

**流程**：
1. 不执行任何 AI 回合
2. 直接执行 Undo
3. 验证返回失败，消息为 "No ghost snapshot available to undo."

### 8. `undo_restores_moves_and_renames`

**目的**：验证撤销能恢复文件移动/重命名

**流程**：
1. 创建文件 `rename_me.txt`
2. AI 回合：移动并重命名文件
3. 执行 Undo
4. 验证原文件恢复，新位置文件删除

### 9. `undo_does_not_touch_ignored_directory_contents`

**目的**：验证撤销不影响被忽略目录的内容

**流程**：
1. 设置 `.gitignore` 忽略 `logs/` 目录
2. 在 `logs/` 中创建文件
3. AI 回合：在 `logs/` 中创建新文件
4. 执行 Undo
5. 验证 AI 创建的文件保留（因为整个目录被忽略，不在快照中）

### 10. `undo_overwrites_manual_edits_after_turn`

**目的**：验证 Undo 会覆盖回合后的手动修改

**流程**：
1. AI 回合：修改文件
2. 用户手动修改同一文件
3. 执行 Undo
4. 验证文件恢复到 AI 修改前的状态（覆盖手动修改）

### 11. `undo_preserves_unrelated_staged_changes`

**目的**：验证 Undo 保留用户 staged 的更改

**流程**：
1. 创建 `user_file.txt` 并提交
2. AI 回合：修改 `ai_file.txt`
3. 用户修改 `user_file.txt` 并 `git add`
4. 执行 Undo
5. 验证 AI 文件恢复，用户 staged 更改保留在索引中

---

## 架构关系图

```
┌─────────────────────────────────────────────────────────────┐
│                     Codex Session                           │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Conversation History                   │   │
│  │  ┌─────────────────────────────────────────────┐   │   │
│  │  │  ResponseItem::Message { ... }              │   │   │
│  │  │  ResponseItem::FunctionCallOutput { ... }   │   │   │
│  │  │  ResponseItem::GhostSnapshot {              │   │   │
│  │  │      ghost_commit: GhostCommit {            │   │   │
│  │  │          id: "abc123...",                   │   │   │
│  │  │          parent: Some("def456..."),         │   │   │
│  │  │          preexisting_untracked_files: [...] │   │   │
│  │  │      }                                      │   │   │
│  │  │  }                                          │   │   │
│  │  └─────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────┘   │
│                            │                                │
│                            ▼                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              GhostSnapshotTask                      │   │
│  │  - 回合完成后异步执行                                │   │
│  │  - 调用 git 命令创建 Ghost Commit                    │   │
│  │  - 将 GhostCommit 添加到 History                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                            │                                │
│                            ▼                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              UndoTask                               │   │
│  │  - 用户请求 Op::Undo 时触发                          │   │
│  │  - 查找最近的 GhostSnapshot                          │   │
│  │  - 调用 git restore 恢复状态                         │   │
│  │  - 从历史中移除 GhostSnapshot                        │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     Git Repository                          │
│  ┌─────────────────┐    ┌─────────────────────────────┐    │
│  │   HEAD (main)   │    │   Ghost Commit (detached)   │    │
│  │  ┌───────────┐  │    │  ┌─────────────────────┐    │    │
│  │  │  Parent   │◄─┼────┼──┤       Tree          │    │    │
│  │  └───────────┘  │    │  │  ┌───────────────┐  │    │    │
│  └─────────────────┘    │  │  │  All files    │  │    │    │
│                         │  │  │  (tracked +   │  │    │    │
│                         │  │  │   untracked)  │  │    │    │
│                         │  │  └───────────────┘  │    │    │
│                         │  └─────────────────────┘    │    │
│                         └─────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```
