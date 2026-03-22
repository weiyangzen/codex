# review_prompts.rs 研究文档

## 场景与职责

本文件负责**代码审查提示（Prompt）的生成和解析**，将用户的审查请求转换为适合 LLM 处理的提示文本。它是 Codex 代码审查功能的**输入层**，处理不同审查场景（未提交更改、分支比较、特定提交等）。

**核心职责**：
- 解析 `ReviewRequest` 中的审查目标
- 生成针对不同审查场景的 LLM 提示
- 提供用户友好的提示描述（hint）
- 处理 Git 分支和提交相关的提示逻辑

## 功能点目的

### 1. 审查目标解析 (`resolve_review_request`)
将 `ReviewRequest` 解析为完整的审查配置：
- 确定审查目标类型
- 生成对应的 LLM 提示
- 提供用户友好的描述

### 2. 提示生成 (`review_prompt`)
支持四种审查场景：

| 场景 | 描述 |
|-----|------|
| `UncommittedChanges` | 审查工作目录中的更改（staged/unstaged/untracked） |
| `BaseBranch { branch }` | 比较当前分支与基础分支的差异 |
| `Commit { sha, title }` | 审查特定提交的更改 |
| `Custom { instructions }` | 自定义审查指令 |

### 3. 用户提示 (`user_facing_hint`)
生成简短的审查描述，用于 UI 显示：
- `"current changes"` - 未提交更改
- `"changes against 'main'"` - 分支比较
- `"commit abc1234: fix bug"` - 特定提交

## 具体技术实现

### 数据结构

```rust
#[derive(Clone, Debug, PartialEq)]
pub struct ResolvedReviewRequest {
    pub target: ReviewTarget,
    pub prompt: String,           // 发送给 LLM 的完整提示
    pub user_facing_hint: String, // 给用户看的简短描述
}

// 来自 protocol.rs
pub enum ReviewTarget {
    UncommittedChanges,
    BaseBranch { branch: String },
    Commit { sha: String, title: Option<String> },
    Custom { instructions: String },
}
```

### 提示模板

#### 未提交更改
```rust
const UNCOMMITTED_PROMPT: &str = 
    "Review the current code changes (staged, unstaged, and untracked files) \
     and provide prioritized findings.";
```

#### 分支比较（主要）
```rust
const BASE_BRANCH_PROMPT: &str = 
    "Review the code changes against the base branch '{baseBranch}'. \
     The merge base commit for this comparison is {mergeBaseSha}. \
     Run `git diff {mergeBaseSha}` to inspect the changes relative to {baseBranch}. \
     Provide prioritized, actionable findings.";
```

#### 分支比较（回退）
```rust
const BASE_BRANCH_PROMPT_BACKUP: &str = 
    "Review the code changes against the base branch '{branch}'. \
     Start by finding the merge diff between the current branch and {branch}'s \
     upstream e.g. (`git merge-base HEAD ...`), then run `git diff` against \
     that SHA to see what changes we would merge into the {branch} branch. \
     Provide prioritized, actionable findings.";
```

#### 特定提交
```rust
const COMMIT_PROMPT_WITH_TITLE: &str = 
    "Review the code changes introduced by commit {sha} (\"{title}\"). \
     Provide prioritized, actionable findings.";
```

### 关键函数流程

#### `review_prompt` 逻辑
```rust
pub fn review_prompt(target: &ReviewTarget, cwd: &Path) -> anyhow::Result<String> {
    match target {
        UncommittedChanges => Ok(UNCOMMITTED_PROMPT.to_string()),
        
        BaseBranch { branch } => {
            // 尝试获取 merge base commit
            if let Some(commit) = merge_base_with_head(cwd, branch)? {
                Ok(BASE_BRANCH_PROMPT.replace("{baseBranch}", branch)
                                     .replace("{mergeBaseSha}", &commit))
            } else {
                // 回退到备份提示
                Ok(BASE_BRANCH_PROMPT_BACKUP.replace("{branch}", branch))
            }
        }
        
        Commit { sha, title } => {
            match title {
                Some(title) => Ok(COMMIT_PROMPT_WITH_TITLE.replace("{sha}", sha)
                                                          .replace("{title}", title)),
                None => Ok(COMMIT_PROMPT.replace("{sha}", sha)),
            }
        }
        
        Custom { instructions } => {
            let prompt = instructions.trim();
            if prompt.is_empty() {
                anyhow::bail!("Review prompt cannot be empty");
            }
            Ok(prompt.to_string())
        }
    }
}
```

### Git 集成

使用 `codex_utils_git::merge_base_with_head` 获取合并基准：
- 首先尝试获取分支的上游（upstream）
- 如果上游领先，使用上游作为比较基准
- 否则使用本地分支

```rust
// utils/git/src/branch.rs
pub fn merge_base_with_head(
    repo_path: &Path,
    branch: &str,
) -> Result<Option<String>, GitToolingError>
```

## 关键代码路径与文件引用

### 调用关系
```
tasks/review.rs
  └── resolve_review_request()  [启动审查时调用]

// 反向依赖（消费者）
protocol/src/protocol.rs
  └── impl From<ResolvedReviewRequest> for ReviewRequest
```

### 依赖关系
```
review_prompts.rs
  ├── codex_git::merge_base_with_head  [Git 操作]
  ├── codex_protocol::protocol::ReviewRequest  [输入]
  └── codex_protocol::protocol::ReviewTarget   [枚举定义]
```

### 相关文件
- `utils/git/src/branch.rs` - Git 分支操作，提供 `merge_base_with_head`
- `protocol/src/protocol.rs` - 协议定义
- `tasks/review.rs` - 审查任务主逻辑

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|-----|------|
| `codex_git` | Git 仓库操作，获取 merge base |
| `codex_protocol` | 协议类型定义 |
| `std::path::Path` | 路径处理 |

### IO 操作
- **文件系统**: 通过 `merge_base_with_head` 访问 Git 仓库
- **Git 命令**: 内部执行 `git merge-base`、`git rev-parse` 等

### 错误处理
- 使用 `anyhow::Result` 进行错误传播
- 自定义审查指令为空时返回错误
- Git 操作失败时传播错误

## 风险、边界与改进建议

### 潜在风险

1. **Git 依赖风险**
   - 依赖外部 Git 可执行文件
   - 大型仓库的 `merge-base` 操作可能较慢
   - 非 Git 仓库场景下无法使用分支比较功能

2. **提示注入风险**
   - `Custom` 指令直接传递给 LLM，无过滤
   - 恶意用户可能通过自定义指令进行提示注入

3. **模板硬编码**
   - 提示模板为英文硬编码
   - 无法根据模型或场景动态调整

### 边界限制

1. **Git 特定**
   - 仅支持 Git 版本控制
   - 不支持 Mercurial、SVN 等其他 VCS

2. **单分支模型**
   - 分支比较仅支持单一基础分支
   - 不支持多分支比较或复杂合并场景

3. **无缓存**
   - 每次调用都重新计算 merge base
   - 频繁审查时可能重复执行 Git 命令

### 改进建议

1. **性能优化**
   - 缓存 `merge_base_with_head` 结果
   - 添加异步支持避免阻塞
   - 支持 shallow clone 优化

2. **功能扩展**
   - 支持多分支比较（`base1...base2`）
   - 支持文件范围限制（仅审查特定路径）
   - 支持忽略模式（.gitignore 扩展）

3. **安全性**
   - 对 `Custom` 指令进行过滤/验证
   - 限制提示长度防止 DoS
   - 添加审计日志

4. **国际化**
   - 支持多语言提示模板
   - 根据用户配置选择语言

5. **可配置性**
   - 允许用户自定义提示模板
   - 支持提示模板继承和覆盖
   - 添加提示版本管理

6. **错误处理增强**
   - 更详细的 Git 错误信息
   - 网络问题时的重试机制
   - 优雅降级（如无法获取 merge base 时）
