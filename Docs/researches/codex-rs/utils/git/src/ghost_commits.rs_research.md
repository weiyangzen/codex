# ghost_commits.rs 深度研究文档

## 一、场景与职责

`ghost_commits.rs` 是 `codex-git` crate 的核心模块，实现了**工作目录快照（ghost commit）**机制。这是 Codex 工具链中实现 "Undo" 功能的基础设施，允许在代码修改前后创建可恢复的检查点。

### 核心场景

1. **代码修改前快照**: 在 Codex 执行代码修改前，自动创建当前工作目录的快照
2. **Undo 功能**: 用户可以通过快照恢复到修改前的状态
3. **安全回退**: 保留未跟踪文件（untracked files），避免用户数据丢失
4. **大文件/目录处理**: 智能跳过大型未跟踪文件和目录，避免性能问题

### 核心职责
- 创建幽灵提交（不引用在任何分支上的临时提交）
- 捕获工作目录状态（跟踪文件、未跟踪文件、被忽略文件）
- 生成快照报告（跳过的文件、大型目录等）
- 从幽灵提交恢复工作目录
- 智能清理恢复后产生的新未跟踪文件

---

## 二、功能点目的

### 2.1 主要功能点

| 功能点 | 目的 | 关键接口 |
|--------|------|----------|
| `create_ghost_commit` | 创建幽灵提交 | `pub fn create_ghost_commit(options: &CreateGhostCommitOptions<'_>) -> Result<GhostCommit, GitToolingError>` |
| `create_ghost_commit_with_report` | 创建幽灵提交并返回报告 | `pub fn create_ghost_commit_with_report(options: &CreateGhostCommitOptions<'_>) -> Result<(GhostCommit, GhostSnapshotReport), GitToolingError>` |
| `capture_ghost_snapshot_report` | 仅生成报告（不创建提交） | `pub fn capture_ghost_snapshot_report(options: &CreateGhostCommitOptions<'_>) -> Result<GhostSnapshotReport, GitToolingError>` |
| `restore_ghost_commit` | 从幽灵提交恢复 | `pub fn restore_ghost_commit(repo_path: &Path, commit: &GhostCommit) -> Result<(), GitToolingError>` |
| `restore_ghost_commit_with_options` | 带选项的恢复 | `pub fn restore_ghost_commit_with_options(options: &RestoreGhostCommitOptions<'_>, commit: &GhostCommit) -> Result<(), GitToolingError>` |
| `restore_to_commit` | 恢复到任意提交 | `pub fn restore_to_commit(repo_path: &Path, commit_id: &str) -> Result<(), GitToolingError>` |

### 2.2 配置结构

```rust
/// 创建幽灵提交的选项
pub struct CreateGhostCommitOptions<'a> {
    pub repo_path: &'a Path,
    pub message: Option<&'a str>,           // 自定义提交消息
    pub force_include: Vec<PathBuf>,        // 强制包含的被忽略文件
    pub ghost_snapshot: GhostSnapshotConfig,
}

/// 快照配置
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GhostSnapshotConfig {
    pub ignore_large_untracked_files: Option<i64>,  // 跳过大于此值的文件（字节）
    pub ignore_large_untracked_dirs: Option<i64>,   // 跳过包含文件数超过此值的目录
    pub disable_warnings: bool,                      // 禁用警告
}

/// 恢复选项
pub struct RestoreGhostCommitOptions<'a> {
    pub repo_path: &'a Path,
    pub ghost_snapshot: GhostSnapshotConfig,
}
```

### 2.3 报告结构

```rust
/// 快照报告
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct GhostSnapshotReport {
    pub large_untracked_dirs: Vec<LargeUntrackedDir>,
    pub ignored_untracked_files: Vec<IgnoredUntrackedFile>,
}

pub struct LargeUntrackedDir {
    pub path: PathBuf,
    pub file_count: i64,
}

pub struct IgnoredUntrackedFile {
    pub path: PathBuf,
    pub byte_size: i64,
}
```

---

## 三、具体技术实现

### 3.1 核心流程：创建幽灵提交

```
create_ghost_commit_with_report(options)
├── ensure_git_repository(repo_path)
├── resolve_repository_root(repo_path)         # 获取仓库根目录
├── repo_subdir(repo_root, repo_path)          # 计算子目录前缀
├── resolve_head(repo_root)                    # 获取父提交（HEAD）
├── prepare_force_include()                    # 处理强制包含路径
├── capture_status_snapshot()                  # 捕获工作目录状态
│   ├── git status --porcelain=2 -z --untracked-files=all
│   ├── 解析 porcelain v2 格式
│   ├── 检测大型未跟踪目录
│   └── 过滤默认忽略目录
├── 创建临时索引
│   ├── tempfile::Builder::new().prefix("codex-git-index-")
│   ├── GIT_INDEX_FILE=<temp> git read-tree HEAD  # 预填充 HEAD
│   └── GIT_INDEX_FILE=<temp> git add --all -- <paths>
├── GIT_INDEX_FILE=<temp> git write-tree       # 写入树对象
├── GIT_INDEX_FILE=<temp> git commit-tree      # 创建提交对象
│   ├── 使用默认身份: Codex Snapshot <snapshot@codex.local>
│   └── 默认消息: "codex snapshot"
└── 构建 GhostCommit
    ├── commit_id: 新提交的 SHA
    ├── parent: HEAD SHA（如果有）
    ├── preexisting_untracked_files: 已存在的未跟踪文件
    └── preexisting_untracked_dirs: 已存在的未跟踪目录
```

### 3.2 核心流程：恢复幽灵提交

```
restore_ghost_commit_with_options(options, commit)
├── ensure_git_repository(repo_path)
├── resolve_repository_root(repo_path)
├── repo_subdir(repo_root, repo_path)
├── capture_existing_untracked()               # 捕获当前未跟踪文件
├── restore_to_commit_inner()                  # 恢复工作目录
│   └── git restore --source <commit_id> --worktree -- <prefix>
└── remove_new_untracked()                     # 清理新增未跟踪文件
    ├── 对比 commit.preexisting_untracked_files/dirs
    ├── 保留已存在的未跟踪文件
    └── 删除恢复后产生的新未跟踪文件
```

### 3.3 状态捕获详解

**Porcelain v2 格式解析**:
```
# 普通条目
1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>

# 重命名条目
2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <Xscore> <path> <sep> <origPath>

# 未合并条目
u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>

# 未跟踪/忽略条目
? <path>
! <path>
```

**处理逻辑**:
```rust
for entry in output.split('\0') {
    match record_type {
        b'?' | b'!' => {  // 未跟踪/忽略
            // 检查是否默认忽略目录
            if should_ignore_for_snapshot(&normalized) { continue; }
            
            // 检查文件大小阈值
            if let Some(threshold) = ignore_large_untracked_files
                && byte_size > threshold
                && !is_force_included(&normalized, force_include)
            {
                snapshot.untracked.ignored_untracked_files.push(...);
            } else {
                snapshot.untracked.files.push(normalized.clone());
                snapshot.untracked.untracked_files_for_index.push(normalized);
            }
        }
        b'1' => {  // 普通跟踪文件
            snapshot.tracked_paths.push(normalized);
        }
        b'2' => {  // 重命名
            snapshot.tracked_paths.push(normalized);
            expect_rename_source = true;
        }
        b'u' => {  // 未合并
            snapshot.tracked_paths.push(normalized);
        }
    }
}
```

### 3.4 大型未跟踪目录检测

```rust
fn detect_large_untracked_dirs(
    files: &[PathBuf],
    dirs: &[PathBuf],
    threshold: Option<i64>,
) -> Vec<LargeUntrackedDir> {
    // 1. 按深度降序排序目录（先处理深层目录）
    sorted_dirs.sort_by(|a, b| {
        b_components.cmp(&a_components)
    });
    
    // 2. 统计每个目录下的文件数
    for file in files {
        // 找到文件所属的最深层目录
        for dir in &sorted_dirs {
            if file.starts_with(dir.as_path()) {
                counts[dir] += 1;
                break;
            }
        }
    }
    
    // 3. 过滤超过阈值的目录
    result.filter(|(_, count)| *count >= threshold)
          .sorted_by(|a, b| b.file_count.cmp(&a.file_count))
}
```

### 3.5 临时索引机制

幽灵提交使用临时索引文件，避免干扰用户的工作索引：

```rust
let index_tempdir = Builder::new().prefix("codex-git-index-").tempdir()?;
let index_path = index_tempdir.path().join("index");
let base_env = vec![
    (OsString::from("GIT_INDEX_FILE"), OsString::from(index_path.as_os_str())),
];

// 预填充 HEAD（使未变更的跟踪文件包含在快照中）
if let Some(parent_sha) = parent.as_deref() {
    run_git_for_status(repo_root, vec!["read-tree", parent_sha], Some(base_env.as_slice()))?;
}

// 添加变更的文件
add_paths_to_index(repo_root, base_env.as_slice(), &index_paths)?;

// 写入树对象并创建提交
let tree_id = run_git_for_stdout(repo_root, vec!["write-tree"], Some(base_env.as_slice()))?;
let commit_id = run_git_for_stdout(repo_root, vec!["commit-tree", &tree_id, ...], ...)?;
```

### 3.6 默认忽略目录

```rust
const DEFAULT_IGNORED_DIR_NAMES: &[&str] = &[
    "node_modules",
    ".venv", "venv", "env", ".env",
    "dist", "build",
    ".pytest_cache", ".mypy_cache", ".cache", ".tox",
    "__pycache__",
];
```

---

## 四、关键代码路径与文件引用

### 4.1 内部调用关系

```
ghost_commits.rs
├── lib.rs (导出接口)
│   ├── GhostCommit (结构体定义)
│   ├── CreateGhostCommitOptions, RestoreGhostCommitOptions
│   ├── GhostSnapshotConfig, GhostSnapshotReport
│   ├── LargeUntrackedDir, IgnoredUntrackedFile
│   └── create_ghost_commit, restore_ghost_commit, ...
├── operations.rs (依赖)
│   ├── ensure_git_repository
│   ├── resolve_repository_root
│   ├── resolve_head
│   ├── repo_subdir
│   ├── normalize_relative_path
│   ├── apply_repo_prefix_to_force_include
│   ├── run_git_for_status
│   ├── run_git_for_stdout
│   └── run_git_for_stdout_all
└── errors.rs
    └── GitToolingError
```

### 4.2 关键代码段

**幽灵提交结构**（定义在 `lib.rs`）:
```rust
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema, TS)]
pub struct GhostCommit {
    id: CommitID,                              // 提交 SHA
    parent: Option<CommitID>,                  // 父提交（HEAD）
    preexisting_untracked_files: Vec<PathBuf>, // 快照前已存在的未跟踪文件
    preexisting_untracked_dirs: Vec<PathBuf>,  // 快照前已存在的未跟踪目录
}
```

**路径去重**:
```rust
fn dedupe_paths(paths: Vec<PathBuf>) -> Vec<PathBuf> {
    let mut seen = HashSet::new();
    let mut result = Vec::new();
    for path in paths {
        if seen.insert(path.clone()) {
            result.push(path);
        }
    }
    result
}
```

**批量添加路径**（避免命令行过长）:
```rust
fn add_paths_to_index(repo_root: &Path, env: &[(OsString, OsString)], paths: &[PathBuf]) -> Result<(), GitToolingError> {
    let chunk_size = usize::try_from(64_i64).unwrap_or(1);
    for chunk in paths.chunks(chunk_size) {
        let mut args = vec![OsString::from("add"), OsString::from("--all"), OsString::from("--")];
        args.extend(chunk.iter().map(|path| path.as_os_str().to_os_string()));
        run_git_for_status(repo_root, args, Some(env))?;
    }
    Ok(())
}
```

---

## 五、依赖与外部交互

### 5.1 外部依赖

| crate | 用途 |
|-------|------|
| `tempfile` | 创建临时索引目录 |
| `walkdir` | 目录遍历（测试中使用） |

### 5.2 系统依赖

- **git 二进制**: 执行以下命令：
  - `git status --porcelain=2 -z --untracked-files=all [-- <prefix>]`
  - `git read-tree <parent>`
  - `git add --all -- <paths>`
  - `git add --force -- <paths>`（强制包含）
  - `git write-tree`
  - `git commit-tree <tree> [-p <parent>] -m <message>`
  - `git restore --source <commit> --worktree -- <prefix>`

### 5.3 调用序列示例

**创建快照**:
```bash
# 1. 获取状态
git -C <repo> status --porcelain=2 -z --untracked-files=all

# 2. 创建临时索引
tempdir = /tmp/codex-git-index-xxx
export GIT_INDEX_FILE=$tempdir/index

# 3. 预填充 HEAD
git -C <repo> read-tree <head_sha>

# 4. 添加文件
git -C <repo> add --all -- <path1> <path2> ...

# 5. 写入树
git -C <repo> write-tree

# 6. 创建提交
GIT_AUTHOR_NAME="Codex Snapshot" \
GIT_AUTHOR_EMAIL="snapshot@codex.local" \
GIT_COMMITTER_NAME="Codex Snapshot" \
GIT_COMMITTER_EMAIL="snapshot@codex.local" \
git -C <repo> commit-tree <tree_sha> -p <head_sha> -m "codex snapshot"
```

**恢复快照**:
```bash
# 1. 恢复工作目录
git -C <repo> restore --source <commit_id> --worktree -- <prefix>

# 2. 清理新未跟踪文件（通过 Rust 代码直接删除）
rm <new_untracked_files>
```

---

## 六、风险、边界与改进建议

### 6.1 已知风险

| 风险点 | 描述 | 严重程度 |
|--------|------|----------|
| 大仓库性能 | 大仓库中 `git status` 可能很慢 | 中 |
| 磁盘空间 | 临时索引和大型文件可能占用磁盘 | 中 |
| 并发修改 | 快照和恢复之间用户修改文件可能导致不一致 | 中 |
| 权限问题 | 无法读取某些文件时可能导致快照不完整 | 低 |
| 子模块 | 当前不处理 git 子模块 | 中 |
| 稀疏检出 | 未测试稀疏检出场景 | 低 |

### 6.2 边界情况

1. **无 HEAD 的新仓库**: 创建无父提交的根提交
2. **空仓库**: 正常处理，返回空快照
3. **子目录工作**: 仅捕获子目录内的变更
4. **符号链接**: 作为普通文件处理
5. **大文件**: 根据阈值跳过，但保留在 `preexisting_untracked_files` 中防止恢复时删除
6. **嵌套忽略目录**: 正确识别嵌套的 `node_modules` 等目录

### 6.3 测试覆盖

模块包含 17 个单元测试：

| 测试名 | 目的 |
|--------|------|
| `create_and_restore_roundtrip` | 端到端创建和恢复 |
| `snapshot_ignores_large_untracked_files` | 大文件跳过 |
| `create_snapshot_reports_large_untracked_dirs` | 大目录报告 |
| `restore_preserves_large_untracked_dirs_when_threshold_disabled` | 禁用阈值时的保留行为 |
| `snapshot_ignores_default_ignored_directories` | 默认忽略目录 |
| `restore_preserves_default_ignored_directories` | 恢复时保留忽略目录 |
| `create_snapshot_reports_nested_large_untracked_dirs_under_tracked_parent` | 嵌套大目录检测 |
| `create_snapshot_without_existing_head` | 无 HEAD 场景 |
| `create_ghost_commit_uses_custom_message` | 自定义消息 |
| `create_ghost_commit_rejects_force_include_parent_path` | 路径越界检查 |
| `restore_requires_git_repository` | 非仓库恢复失败 |
| `restore_from_subdirectory_restores_files_relatively` | 子目录恢复 |
| `restore_from_subdirectory_preserves_parent_vscode` | 父目录忽略文件保留 |
| `restore_preserves_ignored_files` | 被忽略文件保留 |
| `restore_preserves_new_ignored_directory` | 新忽略目录保留 |
| `restore_preserves_new_ignored_file` | 新忽略文件保留 |
| `restore_respects_removed_ignored_file` | 删除的忽略文件保持删除 |
| `restore_preserves_ignored_glob_matches` | glob 匹配忽略保留 |

### 6.4 改进建议

1. **性能优化**:
   - 使用 `git status --porcelain=2` 的 `--no-renames` 选项加速（如果不需要 rename 检测）
   - 考虑使用 `git fast-import` 替代 `commit-tree` 批量创建提交
   - 添加并行处理大目录的选项

2. **功能扩展**:
   - 支持子模块快照和恢复
   - 支持工作目录多个子目录的独立快照
   - 添加快照压缩/归档功能
   - 支持选择性恢复（仅恢复某些文件）

3. **安全性增强**:
   - 添加路径遍历的额外验证
   - 对 force_include 路径进行更严格的检查
   - 添加快照完整性校验（如 SHA 校验）

4. **可观测性**:
   - 添加 tracing 日志记录关键操作
   - 记录快照创建/恢复时间
   - 添加指标收集（快照大小、文件数等）

5. **用户体验**:
   - 添加进度指示器（大仓库）
   - 提供更详细的跳过原因说明
   - 支持交互式选择要恢复的文件

---

## 七、代码统计

- **总行数**: 1785 行
- **代码行**: ~900 行
- **测试行**: ~880 行
- **公共 API**: 7 个
- **常量**: 3 个（默认阈值、默认忽略目录、默认消息）
- **内部结构**: `UntrackedSnapshot`, `StatusSnapshot`
