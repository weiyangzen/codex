# git_info.rs 研究文档

## 场景与职责

本文件提供了全面的 Git 仓库信息收集和操作功能，是 Codex 与 Git 集成的核心模块。主要职责包括：

1. **仓库检测**：检测当前目录是否在 Git 仓库中
2. **基本信息收集**：获取 commit hash、分支名、远程 URL 等
3. **分支管理**：获取本地分支列表、当前分支、默认分支
4. **变更检测**：检测工作区是否有未提交变更
5. **差异计算**：计算与远程分支的差异、生成 diff
6. **提交历史**：获取最近的提交日志
7. **信任检查路径解析**：处理 worktree 等特殊场景的路径解析

## 功能点目的

### 1. 仓库检测与根目录查找

```rust
/// 轻量级检测（不依赖 git 二进制）
pub fn get_git_repo_root(base_dir: &Path) -> Option<PathBuf>

/// 信任检查专用路径解析（支持 worktree）
pub fn resolve_root_git_project_for_trust(cwd: &Path) -> Option<PathBuf>
```

**用途**：
- `get_git_repo_root`：快速检测仓库，用于轻量级场景
- `resolve_root_git_project_for_trust`：处理 worktree，找到主仓库根目录

### 2. 基本信息收集

```rust
pub async fn collect_git_info(cwd: &Path) -> Option<GitInfo>
```

收集：
- `commit_hash`：当前 HEAD 的完整 hash
- `branch`：当前分支名（排除 detached HEAD 状态）
- `repository_url`：origin 远程 URL

**实现特点**：
- 5 秒超时防止大仓库卡顿
- 并行执行三个 git 命令

### 3. 远程 URL 获取

```rust
pub async fn get_git_remote_urls(cwd: &Path) -> Option<BTreeMap<String, String>>
pub async fn get_git_remote_urls_assume_git_repo(cwd: &Path) -> Option<BTreeMap<String, String>>
```

返回格式：`{"origin": "https://github.com/user/repo.git", "upstream": "..."}`

### 4. 分支管理

```rust
pub async fn local_git_branches(cwd: &Path) -> Vec<String>
pub async fn current_branch_name(cwd: &Path) -> Option<String>
pub async fn default_branch_name(cwd: &Path) -> Option<String>
```

**默认分支检测优先级**：
1. `refs/remotes/<remote>/HEAD` 符号引用
2. `git remote show <remote>` 解析 "HEAD branch"
3. 本地分支回退：`main` 或 `master`

### 5. 变更检测

```rust
pub async fn get_has_changes(cwd: &Path) -> Option<bool>
```

使用 `git status --porcelain` 检测是否有未提交变更。

### 6. 提交历史

```rust
pub async fn recent_commits(cwd: &Path, limit: usize) -> Vec<CommitLogEntry>

pub struct CommitLogEntry {
    pub sha: String,
    pub timestamp: i64,    // Unix 时间戳（秒）
    pub subject: String,   // 提交消息主题
}
```

### 7. 差异计算

```rust
pub async fn git_diff_to_remote(cwd: &Path) -> Option<GitDiffToRemote>

pub struct GitDiffToRemote {
    pub sha: GitSha,       // 最近的远程 SHA
    pub diff: String,      // 差异内容
}
```

**算法**：
1. 构建分支祖先链（当前分支 → 默认分支 → 包含 HEAD 的远程分支）
2. 找到最近的远程 SHA（距离 HEAD 最近的）
3. 生成 diff（包括未跟踪文件）

## 具体技术实现

### 超时控制

```rust
const GIT_COMMAND_TIMEOUT: TokioDuration = TokioDuration::from_secs(5);

async fn run_git_command_with_timeout(args: &[&str], cwd: &Path) -> Option<std::process::Output> {
    let mut command = Command::new("git");
    command
        .env("GIT_OPTIONAL_LOCKS", "0")  // 避免锁等待
        .args(args)
        .current_dir(cwd)
        .kill_on_drop(true);
    
    match timeout(GIT_COMMAND_TIMEOUT, command.output()).await {
        Ok(Ok(output)) => Some(output),
        _ => None,  // 超时或错误
    }
}
```

### 并行命令执行

```rust
pub async fn collect_git_info(cwd: &Path) -> Option<GitInfo> {
    // 先检查是否在仓库中
    let is_git_repo = run_git_command_with_timeout(&["rev-parse", "--git-dir"], cwd)
        .await?
        .status
        .success();
    if !is_git_repo {
        return None;
    }

    // 并行执行三个命令
    let (commit_result, branch_result, url_result) = tokio::join!(
        run_git_command_with_timeout(&["rev-parse", "HEAD"], cwd),
        run_git_command_with_timeout(&["rev-parse", "--abbrev-ref", "HEAD"], cwd),
        run_git_command_with_timeout(&["remote", "get-url", "origin"], cwd)
    );

    // 处理结果...
}
```

### 分支祖先链构建

```rust
async fn branch_ancestry(cwd: &Path) -> Option<Vec<String>> {
    // 1. 当前分支
    let current_branch = run_git_command_with_timeout(&["rev-parse", "--abbrev-ref", "HEAD"], cwd)
        .await
        .and_then(|o| /* 解析 */)
        .filter(|s| s != "HEAD");  // 排除 detached HEAD

    // 2. 默认分支
    let default_branch = get_default_branch(cwd).await;

    // 3. 包含 HEAD 的远程分支
    let remotes = get_git_remotes(cwd).await.unwrap_or_default();
    for remote in remotes {
        // git for-each-ref --format=%(refname:short) --contains=HEAD refs/remotes/{remote}
        // 解析格式：origin/feature → feature
    }
}
```

### 最近的远程 SHA 查找

```rust
async fn find_closest_sha(cwd: &Path, branches: &[String], remotes: &[String]) -> Option<GitSha> {
    let mut closest_sha: Option<(GitSha, usize)> = None;  // (SHA, 距离)
    
    for branch in branches {
        let (maybe_remote_sha, distance) = branch_remote_and_distance(cwd, branch, remotes).await?;
        let remote_sha = maybe_remote_sha?;  // 跳过无远程的分支
        
        // 选择距离最近的
        match &closest_sha {
            None => closest_sha = Some((remote_sha, distance)),
            Some((_, best_distance)) if distance < *best_distance => {
                closest_sha = Some((remote_sha, distance));
            }
            _ => {}
        }
    }
    
    closest_sha.map(|(sha, _)| sha)
}
```

### 差异生成（含未跟踪文件）

```rust
async fn diff_against_sha(cwd: &Path, sha: &GitSha) -> Option<String> {
    // 1. 常规 diff
    let mut diff = run_git_command_with_timeout(
        &["diff", "--no-textconv", "--no-ext-diff", &sha.0],
        cwd
    ).await?;
    
    // 2. 获取未跟踪文件列表
    let untracked = run_git_command_with_timeout(
        &["ls-files", "--others", "--exclude-standard"],
        cwd
    ).await?;
    
    // 3. 为每个未跟踪文件生成 diff（与 /dev/null 比较）
    for file in untracked_files {
        let extra = run_git_command_with_timeout(
            &["diff", "--no-textconv", "--no-ext-diff", "--binary", 
              "--no-index", "--", null_device, &file],
            cwd
        ).await?;
        diff.push_str(&extra.stdout);
    }
    
    Some(diff)
}
```

### Worktree 支持

```rust
pub fn resolve_root_git_project_for_trust(cwd: &Path) -> Option<PathBuf> {
    let (repo_root, dot_git) = find_ancestor_git_entry(base)?;
    
    if dot_git.is_dir() {
        return Some(canonicalize_or_raw(repo_root));
    }
    
    // .git 是文件，解析 gitdir 指向
    let git_dir_s = std::fs::read_to_string(&dot_git).ok()?;
    let git_dir_rel = git_dir_s.trim().strip_prefix("gitdir:")?.trim();
    let git_dir_path = canonicalize_or_raw(resolve_path(&repo_root, &PathBuf::from(git_dir_rel)));
    
    // 验证路径结构：.../worktrees/<name>/
    let worktrees_dir = git_dir_path.parent()?;
    if worktrees_dir.file_name() != Some(OsStr::new("worktrees")) {
        return None;
    }
    
    // 返回主仓库根目录
    let common_dir = worktrees_dir.parent()?;
    let main_repo_root = common_dir.parent()?;
    Some(canonicalize_or_raw(main_repo_root.to_path_buf()))
}
```

## 关键代码路径与文件引用

### 核心数据结构

| 结构体 | 用途 |
|-------|------|
| `GitInfo` | 基本信息（commit、branch、URL） |
| `GitDiffToRemote` | 远程差异（SHA + diff） |
| `CommitLogEntry` | 提交日志条目 |

### 公开 API

| 函数 | 可见性 | 用途 |
|-----|-------|------|
| `get_git_repo_root` | `pub` | 仓库根目录检测 |
| `collect_git_info` | `pub` | 收集完整信息 |
| `get_git_remote_urls` | `pub` | 获取所有远程 URL |
| `get_head_commit_hash` | `pub` | 获取 HEAD hash |
| `get_has_changes` | `pub` | 检测未提交变更 |
| `recent_commits` | `pub` | 最近提交历史 |
| `git_diff_to_remote` | `pub` | 远程差异计算 |
| `default_branch_name` | `pub` | 默认分支名 |
| `local_git_branches` | `pub` | 本地分支列表 |
| `current_branch_name` | `pub` | 当前分支名 |
| `resolve_root_git_project_for_trust` | `pub` | 信任检查路径 |

### 内部辅助函数

| 函数 | 用途 |
|-----|------|
| `run_git_command_with_timeout` | 带超时的 git 命令执行 |
| `parse_git_remote_urls` | 解析 `git remote -v` 输出 |
| `get_git_remotes` | 获取远程列表（origin 优先） |
| `get_default_branch` | 默认分支检测算法 |
| `get_default_branch_local` | 本地默认分支回退 |
| `branch_ancestry` | 分支祖先链构建 |
| `branch_remote_and_distance` | 分支远程存在性和距离计算 |
| `find_closest_sha` | 最近的远程 SHA 查找 |
| `diff_against_sha` | 差异生成 |
| `find_ancestor_git_entry` | 向上查找 .git 入口 |
| `canonicalize_or_raw` | 路径规范化（容错） |

### 调用方

| 调用方 | 用途 |
|-------|------|
| `environment_context.rs` | 收集环境上下文 |
| `codex.rs` | 会话初始化 |
| `commit_attribution.rs` | 提交归属 |
| `turn_diff_tracker.rs` | Turn 间差异跟踪 |
| `trust.rs` | 仓库信任检查 |

## 依赖与外部交互

### 外部 crate

| crate | 用途 |
|-------|------|
| `tokio::process::Command` | 异步进程执行 |
| `tokio::time::timeout` | 超时控制 |
| `serde` | 序列化支持 |
| `futures::future::join_all` | 批量并发执行 |
| `codex_app_server_protocol::GitSha` | Git SHA 类型 |
| `codex_protocol::protocol::GitInfo` | GitInfo 类型 |

### 内部模块

| 模块 | 用途 |
|-----|------|
| `util::resolve_path` | 路径解析 |

### 外部命令

| 命令 | 用途 |
|-----|------|
| `git rev-parse` | 解析引用、获取路径 |
| `git remote` | 远程操作 |
| `git status` | 状态检测 |
| `git log` | 提交历史 |
| `git diff` | 差异计算 |
| `git for-each-ref` | 引用遍历 |
| `git symbolic-ref` | 符号引用 |
| `git ls-files` | 文件列表 |
| `git branch` | 分支操作 |

## 风险、边界与改进建议

### 当前风险点

1. **git 二进制依赖**：所有功能依赖系统安装的 git
2. **超时硬编码**：5 秒超时对大仓库可能不足
3. **UTF-8 假设**：命令输出假设为 UTF-8
4. **并发限制**：大量未跟踪文件时，`diff_against_sha` 可能创建过多并发任务

### 边界情况处理

| 边界情况 | 处理方式 |
|---------|---------|
| 非 Git 目录 | 返回 `None` 或空列表 |
| Detached HEAD | `current_branch_name` 返回 `None` |
| 无远程仓库 | `repository_url` 为 `None` |
| 命令超时 | 返回 `None`，静默失败 |
| 命令失败 | 返回 `None`，静默失败 |
| 非 UTF-8 输出 | 跳过该字段 |
| Worktree | `resolve_root_git_project_for_trust` 特殊处理 |
| 空提交历史 | `recent_commits` 返回空列表 |

### 性能考量

1. **超时机制**：防止大仓库卡顿，但可能丢失信息
2. **并行执行**：`collect_git_info` 并行执行 3 个命令
3. **批量处理**：`diff_against_sha` 对未跟踪文件使用 `join_all`
4. **引用计数**：`branch_ancestry` 使用 `HashSet` 去重

### 改进建议

1. **可配置超时**：
   ```rust
   pub struct GitConfig {
       pub command_timeout: Duration,
       pub max_concurrent_diffs: usize,
   }
   ```

2. **libgit2 备选**：
   对于无 git 二进制或需要更高性能的场景，支持 libgit2：
   ```rust
   pub enum GitBackend {
       CommandLine,
       Libgit2,
   }
   ```

3. **缓存机制**：
   对不频繁变化的信息（如远程 URL）增加缓存：
   ```rust
   pub struct CachedGitInfo {
       info: GitInfo,
       fetched_at: Instant,
   }
   ```

4. **流式 diff**：
   大 diff 场景下使用流式处理：
   ```rust
   pub async fn git_diff_to_remote_stream(cwd: &Path) -> impl Stream<Item = String>
   ```

5. **错误类型细化**：
   当前使用 `Option` 简化错误处理，可考虑：
   ```rust
   pub enum GitError {
       NotARepository,
       CommandFailed(String),
       Timeout,
       ParseError(String),
   }
   ```

6. **遥测集成**：
   增加 git 命令执行指标：
   - 命令执行时间
   - 超时次数
   - 失败次数

### 测试覆盖

测试文件 `git_info_tests.rs` 应覆盖：
- 仓库检测（正常、非仓库、worktree）
- 信息收集（正常、超时、失败）
- 分支检测（正常、detached、无远程）
- 差异计算（正常、大量文件、二进制文件）
- 路径解析（正常、worktree、符号链接）

建议增加：
- 大仓库性能测试
- 并发安全测试
- 跨平台路径测试
- 错误恢复测试
