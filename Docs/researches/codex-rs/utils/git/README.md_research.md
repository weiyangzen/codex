# codex-rs/utils/git/README.md 研究文档

## 场景与职责

`README.md` 是 `codex-git` crate 的用户文档入口，面向 Rust 开发者提供：

1. **功能概述**：简要说明 crate 的核心能力（补丁应用、工作树快照）
2. **快速入门**：通过代码示例展示典型使用模式
3. **API 导航**：引导用户查看主要类型和函数

该文档位于 crate 根目录，被 `Cargo.toml` 的 `readme` 字段引用，会显示在 crates.io 和 docs.rs 上。

## 功能点目的

### 功能定位
README 明确该 crate 是 "Helpers for interacting with git"，强调两个核心价值：

1. **Patch Application**：通过 `git apply` 命令安全地应用统一差异格式（unified diff）
2. **Worktree Snapshot**：创建轻量级、无引用的提交（ghost commits）保存工作树状态

### 目标用户
- Codex 项目内部开发者（core、chatgpt 等模块）
- 可能的外部使用者（该 crate 设计为可独立使用）

### 文档策略
- 采用 `rust,no_run` 代码块，确保文档测试通过但不实际执行
- 展示 Builder 模式 API（`CreateGhostCommitOptions::new(...).message(...)`）
- 强调 `force_include` 功能（处理 `.gitignore` 文件）

## 具体技术实现

### 文档结构分析

```markdown
# codex-git                    # 标题：crate 名称

功能描述段落                  # 一句话价值主张

```rust,no_run                 # 可编译但不可运行的示例
use codex_git::{...};         # 展示主要导入项

// 示例 1: 应用补丁
let request = ApplyGitRequest { ... };
let result = apply_git_patch(&request)?;

// 示例 2: 创建和恢复快照
let ghost = create_ghost_commit(&options)?;
restore_ghost_commit(repo, &ghost)?;
```

补充说明段落                  # force_include 提示
```

### 代码示例详解

#### 示例 1：应用补丁

```rust
let request = ApplyGitRequest {
    cwd: repo.to_path_buf(),      // 工作目录（必须包含 .git）
    diff: String::from("..."),    // 统一差异格式文本
    revert: false,                // 正向应用（true 为反向/撤销）
    preflight: false,             // false=实际应用，true=仅检查
};
let result = apply_git_patch(&request)?;
```

**关键参数说明**：
- `preflight: true` → 执行 `git apply --check`，不修改工作树
- `revert: true` → 添加 `-R` 标志，用于撤销已应用的补丁

#### 示例 2：Ghost Commit 快照

```rust
// 创建快照（Builder 模式）
let ghost = create_ghost_commit(&CreateGhostCommitOptions::new(repo))?;

// 后续恢复到快照状态
restore_ghost_commit(repo, &ghost)?;
```

**Ghost Commit 特性**：
- 使用 git plumbing 命令（`commit-tree`）创建无引用提交
- 不污染分支历史（detached commit）
- 保存工作树状态（包括未跟踪文件元数据）

### 未展示但重要的 API

README 未提及但实现中存在的功能：

1. **详细报告获取**
   ```rust
   let (commit, report) = create_ghost_commit_with_report(&options)?;
   // report: GhostSnapshotReport { large_untracked_dirs, ignored_untracked_files }
   ```

2. **带选项的恢复**
   ```rust
   restore_ghost_commit_with_options(
       &RestoreGhostCommitOptions::new(repo).ignore_large_untracked_files(1024),
       &ghost
   )?;
   ```

3. **补丁路径提取**
   ```rust
   let paths = extract_paths_from_patch(&diff_text);
   ```

4. **分支合并基础**
   ```rust
   let base = merge_base_with_head(repo_path, "main")?;
   ```

## 关键代码路径与文件引用

### 文档相关
- `codex-rs/utils/git/README.md` - 本文档
- `codex-rs/utils/git/Cargo.toml` - 引用 README 作为包元数据

### 示例涉及源码
- `codex-rs/utils/git/src/lib.rs` - 导出 `GhostCommit`, `ApplyGitRequest` 等
- `codex-rs/utils/git/src/apply.rs` - `apply_git_patch` 实现
- `codex-rs/utils/git/src/ghost_commits.rs` - `create_ghost_commit` 实现

### 示例代码的完整上下文

#### ApplyGitRequest 定义（apply.rs:17-23）
```rust
#[derive(Debug, Clone)]
pub struct ApplyGitRequest {
    pub cwd: PathBuf,
    pub diff: String,
    pub revert: bool,
    pub preflight: bool,
}
```

#### CreateGhostCommitOptions 定义（ghost_commits.rs:51-56）
```rust
pub struct CreateGhostCommitOptions<'a> {
    pub repo_path: &'a Path,
    pub message: Option<&'a str>,
    pub force_include: Vec<PathBuf>,
    pub ghost_snapshot: GhostSnapshotConfig,
}
```

#### GhostCommit 结构（lib.rs:40-46）
```rust
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema, TS)]
pub struct GhostCommit {
    id: CommitID,
    parent: Option<CommitID>,
    preexisting_untracked_files: Vec<PathBuf>,
    preexisting_untracked_dirs: Vec<PathBuf>,
}
```

## 依赖与外部交互

### 文档系统依赖
- **docs.rs**：自动从 README 和源码注释生成文档
- **crates.io**：显示 README 作为包主页

### 代码示例的隐式依赖
示例代码假设：
1. 系统已安装 `git` 可执行文件
2. 目标路径是有效的 git 仓库
3. 补丁格式符合统一差异标准

### 实际使用场景

#### 场景 1：Codex Core 的 Undo 功能
```rust
// core/src/tasks/undo.rs
let ghost_commit = // 从历史记录获取
restore_ghost_commit_with_options(&options, &ghost_commit)?;
```

#### 场景 2：ChatGPT CLI 的 apply 命令
```rust
// chatgpt/src/apply_command.rs
let req = codex_git::ApplyGitRequest {
    cwd,
    diff: diff.to_string(),
    revert: false,
    preflight: false,
};
let res = codex_git::apply_git_patch(&req)?;
```

## 风险、边界与改进建议

### 当前文档的不足

1. **错误处理缺失**
   - 示例使用 `?` 操作符但未说明可能的错误类型
   - 未提及 `GitToolingError` 变体

2. **性能特征未说明**
   - Ghost commit 在大仓库可能很慢（README 未提及）
   - 无超时处理指导

3. **平台限制未声明**
   - `platform.rs` 仅支持 Unix/Windows
   - 符号链接功能在其他平台编译失败

4. **并发安全未说明**
   - Git 操作会修改工作树，未说明并发限制

### 改进建议

#### 1. 添加错误处理示例
```markdown
## 错误处理

```rust
use codex_git::{apply_git_patch, GitToolingError};

match apply_git_patch(&request) {
    Ok(result) if result.exit_code == 0 => println!("Success"),
    Ok(result) => println!("Applied with issues: {:?}", result.conflicted_paths),
    Err(GitToolingError::NotAGitRepository { path }) => eprintln!("Not a git repo: {}", path.display()),
    Err(e) => eprintln!("Git error: {}", e),
}
```
```

#### 2. 添加性能提示
```markdown
## 性能注意事项

- Ghost commits 在包含大量未跟踪文件的仓库中可能较慢
- 考虑使用 `ignore_large_untracked_files` 和 `ignore_large_untracked_dirs` 选项
- 默认忽略 `node_modules`, `.venv` 等目录
```

#### 3. 添加平台支持表格
```markdown
## 平台支持

| 功能 | Linux | macOS | Windows | 其他 |
|------|-------|-------|---------|------|
| Patch apply | ✅ | ✅ | ✅ | ✅ |
| Ghost commits | ✅ | ✅ | ✅ | ✅ |
| Symlinks | ✅ | ✅ | ✅* | ❌ |

*Windows 需要开发者模式或管理员权限
```

#### 4. 添加架构说明
```markdown
## 实现细节

Ghost commits 使用 git plumbing 命令实现：
1. `git read-tree HEAD` - 加载基础索引
2. `git add --all` - 暂存工作树变更
3. `git write-tree` - 写入树对象
4. `git commit-tree` - 创建无引用提交
```

#### 5. 添加安全警告
```markdown
## 安全注意事项

- `force_include` 可以绕过 `.gitignore`，谨慎使用
- 路径参数经过规范化处理，阻止 `../` 逃逸
- 临时补丁文件创建在系统临时目录，具有受限权限
```

### 与代码同步的维护建议

1. **添加文档测试（doctests）**
   ```rust
   /// ```
   /// # use codex_git::create_ghost_commit;
   /// # use std::path::Path;
   /// # fn test() -> Result<(), Box<dyn std::error::Error>> {
   /// let ghost = create_ghost_commit(&CreateGhostCommitOptions::new(Path::new(".")))?;
   /// # Ok(()) }
   /// ```
   ```

2. **使用 cargo-readme 自动生成**
   从源码注释提取文档，确保 README 与代码同步

3. **添加 CHANGELOG 链接**
   在 README 底部添加版本历史链接，帮助用户了解 breaking changes
