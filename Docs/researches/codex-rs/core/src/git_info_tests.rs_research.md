# git_info_tests.rs 研究文档

## 场景与职责

`git_info_tests.rs` 是 `codex-rs/core/src/git_info.rs` 的配套测试文件，负责验证 Git 信息收集模块的核心功能。该测试文件在 Codex 核心库中扮演质量保证角色，确保 Git 仓库信息（提交历史、分支、远程 URL、工作区状态等）能够被正确提取和解析。

**核心测试场景：**
1. 验证 `recent_commits()` 函数在非 Git 目录和正常仓库中的行为
2. 验证 `collect_git_info()` 函数对仓库元数据的收集能力
3. 验证 `get_has_changes()` 函数检测工作区变更的能力
4. 验证 `git_diff_to_remote()` 函数计算与远程差异的能力
5. 验证 `resolve_root_git_project_for_trust()` 函数解析 Git 项目根目录的能力（包括 worktree 支持）

## 功能点目的

### 1. 提交历史测试 (`test_recent_commits_*`)
- **目的**：验证 `recent_commits()` 函数能够按时间倒序返回指定数量的提交记录
- **关键验证点**：
  - 非 Git 目录返回空列表
  - 提交按时间戳正确排序
  - SHA 格式验证（至少7位十六进制字符）

### 2. Git 信息收集测试 (`test_collect_git_info_*`)
- **目的**：验证 `collect_git_info()` 函数收集仓库元数据
- **关键验证点**：
  - 非 Git 目录返回 `None`
  - 正确提取 commit hash（40位 SHA-1）
  - 正确识别分支名称（main/master）
  - 正确处理 detached HEAD 状态（branch 为 None）
  - 正确提取远程 URL

### 3. 工作区状态测试 (`test_get_has_changes_*`)
- **目的**：验证 `get_has_changes()` 检测工作区是否有未提交变更
- **关键验证点**：
  - 非 Git 目录返回 `None`
  - 干净仓库返回 `Some(false)`
  - 跟踪文件修改返回 `Some(true)`
  - 未跟踪文件返回 `Some(true)`

### 4. 远程差异测试 (`test_get_git_working_tree_state_*`)
- **目的**：验证 `git_diff_to_remote()` 计算与远程分支的差异
- **关键验证点**：
  - 干净仓库返回空 diff
  - 修改后的跟踪文件和未跟踪文件都包含在 diff 中
  - 分支回退逻辑（当前分支无远程时尝试其他分支）
  - 未推送的提交包含在 diff 中

### 5. 信任根目录解析测试 (`resolve_root_git_project_for_trust_*`)
- **目的**：验证 `resolve_root_git_project_for_trust()` 解析项目根目录
- **关键验证点**：
  - 非仓库目录返回 `None`
  - 普通仓库返回仓库根目录
  - Git worktree 返回主仓库根目录（而非 worktree 目录）
  - 支持 `.git` 文件指向 gitdir 的情况
  - 嵌套子目录正确向上查找

### 6. 序列化测试 (`test_git_info_serialization*`)
- **目的**：验证 `GitInfo` 结构的 JSON 序列化行为
- **关键验证点**：
  - 字段正确映射为 snake_case
  - `None` 值字段被跳过（`skip_serializing_if`）

## 具体技术实现

### 测试辅助函数

```rust
// 创建测试 Git 仓库
async fn create_test_git_repo(temp_dir: &TempDir) -> PathBuf
```
- 使用 `GIT_CONFIG_GLOBAL=/dev/null` 和 `GIT_CONFIG_NOSYSTEM=1` 隔离全局配置
- 配置测试用户（user.name, user.email）
- 创建初始提交

```rust
// 创建带远程的测试仓库
async fn create_test_git_repo_with_remote(temp_dir: &TempDir) -> (PathBuf, String)
```
- 创建 bare 远程仓库
- 添加 origin remote
- 推送当前分支并建立追踪关系

### 关键测试技术

1. **时间控制**：使用 `sleep(Duration::from_millis(1100))` 确保提交时间戳有差异
2. **环境隔离**：通过环境变量禁用全局 Git 配置，确保测试可重复
3. **并行命令执行**：`tokio::join!` 用于并行执行多个 Git 命令
4. **超时保护**：`GIT_COMMAND_TIMEOUT = 5s` 防止大仓库阻塞

### 数据结构

```rust
// GitInfo 序列化测试用的结构
GitInfo {
    commit_hash: Option<String>,  // 40位 SHA-1
    branch: Option<String>,       // 分支名或 None（detached HEAD）
    repository_url: Option<String>, // 远程 URL
}

// GitDiffToRemote 结构
GitDiffToRemote {
    sha: GitSha,    // 远程基准提交
    diff: String,   // 差异内容
}

// CommitLogEntry 结构
CommitLogEntry {
    sha: String,
    timestamp: i64,  // Unix 时间戳（秒）
    subject: String, // 提交主题
}
```

## 关键代码路径与文件引用

### 被测试的源文件
- **`/home/sansha/Github/codex/codex-rs/core/src/git_info.rs`** - 主实现文件

### 关键函数路径

```
git_info_tests.rs
├── test_recent_commits_non_git_directory_returns_empty
│   └── calls -> git_info::recent_commits()
├── test_recent_commits_orders_and_limits
│   └── calls -> git_info::recent_commits()
├── test_collect_git_info_non_git_directory
│   └── calls -> git_info::collect_git_info()
├── test_collect_git_info_git_repository
│   └── calls -> git_info::collect_git_info()
├── test_collect_git_info_with_remote
│   └── calls -> git_info::collect_git_info()
├── test_collect_git_info_detached_head
│   └── calls -> git_info::collect_git_info()
├── test_collect_git_info_with_branch
│   └── calls -> git_info::collect_git_info()
├── test_get_has_changes_*
│   └── calls -> git_info::get_has_changes()
├── test_get_git_working_tree_state_*
│   └── calls -> git_info::git_diff_to_remote()
└── resolve_root_git_project_for_trust_*
    └── calls -> git_info::resolve_root_git_project_for_trust()
```

### 依赖的外部类型
- `codex_app_server_protocol::GitSha` - Git SHA 包装类型
- `codex_protocol::protocol::GitInfo` - Git 信息协议类型
- `core_test_support::skip_if_sandbox!` - 沙箱环境跳过宏

## 依赖与外部交互

### 外部命令依赖
| 命令 | 用途 | 超时设置 |
|------|------|----------|
| `git init` | 初始化测试仓库 | 无（测试辅助函数） |
| `git config` | 配置测试用户 | 无 |
| `git add` | 添加文件到暂存区 | 无 |
| `git commit` | 创建提交 | 无 |
| `git remote` | 管理远程仓库 | 5秒超时 |
| `git rev-parse` | 解析引用 | 5秒超时 |
| `git status` | 检查工作区状态 | 5秒超时 |
| `git log` | 获取提交历史 | 5秒超时 |
| `git diff` | 计算差异 | 5秒超时 |
| `git worktree` | 创建工作树 | 无 |
| `git for-each-ref` | 遍历引用 | 5秒超时 |
| `git symbolic-ref` | 读取符号引用 | 5秒超时 |
| `git ls-files` | 列出文件 | 5秒超时 |

### 测试框架依赖
- `tokio::test` - 异步测试运行时
- `tempfile::TempDir` - 临时目录管理
- `pretty_assertions` - 更好的断言输出

### 环境变量
```rust
// 隔离全局 Git 配置
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1
GIT_OPTIONAL_LOCKS=0  // 禁用可选锁，提高性能
```

## 风险、边界与改进建议

### 已知风险

1. **时间敏感测试**
   - `test_recent_commits_orders_and_limits` 依赖 `sleep(1100ms)` 确保时间戳差异
   - **风险**：在慢速 CI 环境可能不稳定
   - **建议**：考虑使用 Git 的 `--date` 参数显式设置提交时间

2. **Git 版本差异**
   - 不同 Git 版本的分支名默认行为可能不同（main vs master）
   - 测试使用 `assert!(branch == "main" || branch == "master")` 兼容处理

3. **沙箱环境限制**
   - 部分测试使用 `skip_if_sandbox!()` 宏跳过
   - **原因**：沙箱中可能无法执行 `git` 命令或创建进程

4. **并发执行风险**
   - 测试创建真实文件系统和 Git 仓库
   - 使用 `TempDir` 确保清理，但并发执行时可能产生资源竞争

### 边界情况覆盖

| 边界情况 | 测试覆盖 | 说明 |
|----------|----------|------|
| 非 Git 目录 | ✅ | 多个测试验证返回 None/空列表 |
| 空仓库 | ❌ | 未测试刚 init 但未 commit 的情况 |
| 大仓库超时 | ❌ | 依赖 5 秒超时，但无大仓库测试 |
| 特殊字符分支名 | ❌ | 未测试含空格、中文等分支名 |
| 子模块 | ❌ | 未测试子模块场景 |
| 浅克隆 | ❌ | 未测试 shallow clone 场景 |

### 改进建议

1. **增加模糊测试**
   ```rust
   // 建议添加：测试特殊字符处理
   #[tokio::test]
   async fn test_branch_name_with_special_chars() {
       // 测试分支名含空格、unicode 等情况
   }
   ```

2. **性能优化**
   - 当前 `test_recent_commits_orders_and_limits` 需要 3.3 秒以上（3 × 1.1s sleep）
   - 可使用 `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE` 环境变量精确控制时间戳

3. **错误处理增强**
   - 当前测试主要验证成功路径
   - 建议增加 Git 命令失败时的错误处理测试

4. **Worktree 测试完善**
   - 当前已覆盖基本 worktree 场景
   - 建议增加 worktree 嵌套、删除后重建等边界情况

5. **并发安全**
   - 考虑使用 `serial_test` crate 确保涉及全局状态的测试串行执行

### 维护注意事项

1. **Git 版本兼容性**：测试使用较基础的 Git 命令，兼容性较好，但需关注新 Git 版本的默认行为变化
2. **平台差异**：测试在 Windows 上可能表现不同（路径分隔符、换行符等）
3. **测试数据清理**：`TempDir` 在 drop 时自动清理，但 panic 时可能残留，建议配合 `tempfile` 的 `into_path()` 调试模式
