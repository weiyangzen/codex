# ReviewTarget.ts 研究文档

## 场景与职责

`ReviewTarget.ts` 定义了代码审查目标的数据结构，用于指定要审查的具体内容。这是一个标记联合类型（tagged union），支持多种审查目标类型，包括未提交更改、分支差异、特定提交和自定义指令。

## 功能点目的

该类型用于：
1. **多样化审查**：支持不同粒度和类型的代码审查
2. **Git 集成**：深度集成 Git 工作流，支持常见审查场景
3. **灵活性**：支持自定义审查指令满足特殊需求
4. **类型安全**：通过标记联合确保类型安全的目标指定

## 具体技术实现

### 数据结构定义

```typescript
export type ReviewTarget = 
  | { "type": "uncommittedChanges" }                                    // 未提交更改
  | { "type": "baseBranch", branch: string }                           // 基础分支差异
  | { "type": "commit", sha: string, title: string | null }            // 特定提交
  | { "type": "custom", instructions: string };                        // 自定义指令
```

### 变体详解

#### UncommittedChanges（未提交更改）

```typescript
{ type: "uncommittedChanges" }
```

审查工作目录中尚未提交的更改，相当于 `git diff`。

#### BaseBranch（基础分支）

```typescript
{ 
  type: "baseBranch", 
  branch: string  // 基础分支名称，如 "main" 或 "develop"
}
```

审查当前分支与指定基础分支之间的差异，相当于 `git diff baseBranch..HEAD`。

#### Commit（特定提交）

```typescript
{ 
  type: "commit", 
  sha: string,           // 提交哈希
  title: string | null   // 可选的人类可读标题（如提交主题）
}
```

审查特定的提交，title 字段用于 UI 展示。

#### Custom（自定义指令）

```typescript
{ 
  type: "custom", 
  instructions: string   // 自定义审查指令
}
```

允许用户指定任意审查指令，用于非标准的审查场景。

### Rust 协议定义

在 `codex-rs/protocol/src/protocol.rs` 中：

```rust
#[derive(
    Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Display, JsonSchema, TS,
)]
#[serde(tag = "type", rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
#[ts(tag = "type")]
pub enum ReviewTarget {
    /// 审查未提交的更改
    UncommittedChanges,
    
    /// 审查与基础分支的差异
    BaseBranch { branch: String },
    
    /// 审查特定提交
    Commit { 
        sha: String, 
        title: Option<String> 
    },
    
    /// 自定义审查指令
    Custom { instructions: String },
}
```

### 服务端处理

在 `codex-rs/app-server/src/codex_message_processor.rs` 中：

```rust
async fn resolve_review_target(
    &self,
    target: &ReviewTarget,
    cwd: &Path,
) -> Result<ResolvedReviewTarget, Error> {
    match target {
        ReviewTarget::UncommittedChanges => {
            let diff = self.git_uncommitted_changes(cwd).await?;
            Ok(ResolvedReviewTarget::Diff(diff))
        }
        ReviewTarget::BaseBranch { branch } => {
            let diff = self.git_diff_branch(cwd, branch).await?;
            Ok(ResolvedReviewTarget::Diff(diff))
        }
        ReviewTarget::Commit { sha, .. } => {
            let commit_info = self.git_show_commit(cwd, sha).await?;
            Ok(ResolvedReviewTarget::Commit(commit_info))
        }
        ReviewTarget::Custom { instructions } => {
            Ok(ResolvedReviewTarget::Custom(instructions.clone()))
        }
    }
}
```

### 审查提示生成

在 `codex-rs/core/src/review_prompts.rs` 中，根据目标类型生成不同的审查提示：

```rust
fn generate_review_prompt(target: &ResolvedReviewTarget) -> String {
    match target {
        ResolvedReviewTarget::Diff(diff) => {
            format!("Please review the following changes:\n\n{}", diff)
        }
        ResolvedReviewTarget::Commit(commit) => {
            format!("Please review this commit:\n\n{}", commit)
        }
        ResolvedReviewTarget::Custom(instructions) => {
            format!("Please review according to these instructions:\n\n{}", instructions)
        }
    }
}
```

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/ReviewTarget.ts`

### Rust 协议定义
- 核心类型：`codex-rs/protocol/src/protocol.rs`
- V2 API 封装：`codex-rs/app-server-protocol/src/protocol/v2.rs`

### 服务端实现
- 消息处理：`codex-rs/app-server/src/codex_message_processor.rs`
- 审查提示：`codex-rs/core/src/review_prompts.rs`

### 客户端使用
- Exec 模块：`codex-rs/exec/src/lib.rs`
- TUI 应用服务器：`codex-rs/tui_app_server/src/app_server_session.rs`
- TUI 聊天组件：`codex-rs/tui/src/chatwidget.rs`

### 测试覆盖
- 审查测试：`codex-rs/app-server/tests/suite/v2/review.rs`
- 核心审查测试：`codex-rs/core/tests/suite/review.rs`

### 相关类型
- ReviewStartParams：`codex-rs/app-server-protocol/schema/typescript/v2/ReviewStartParams.ts`

## 依赖与外部交互

### 上游依赖
- Git 仓库：需要有效的 Git 仓库来解析分支和提交
- 用户输入：通过 UI 或命令行选择审查目标

### 下游消费
- Git 操作：执行相应的 Git 命令获取差异
- 提示工程：根据目标类型生成适当的审查提示

### 目标解析流程

```
ReviewTarget
    ↓
Git 操作（uncommittedChanges/baseBranch/commit）
    ↓
ResolvedReviewTarget（Diff / Commit / Custom）
    ↓
审查提示生成
    ↓
发送给模型审查
```

## 风险、边界与改进建议

### 边界情况
1. **空差异**：目标可能产生空的差异（如无未提交更改）
2. **无效提交**：commit sha 可能不存在或无效
3. **分支不存在**：baseBranch 可能不存在于本地
4. **非 Git 目录**：在非 Git 目录中使用 Git 相关目标会失败

### 潜在风险
1. **大差异**：大型 PR 的差异可能超出模型上下文限制
2. **二进制文件**：差异中可能包含二进制文件内容
3. **敏感信息**：差异可能包含敏感信息（密码、密钥等）
4. **编码问题**：文件编码可能导致差异解析问题

### 改进建议
1. **差异限制**：添加选项限制审查的文件数量或行数
2. **文件过滤**：支持按路径模式过滤要审查的文件
3. **二进制处理**：智能处理二进制文件的差异显示
4. **敏感检测**：检测并警告可能的敏感信息
5. **增量审查**：支持仅审查自上次审查以来的新更改
6. **多目标审查**：支持一次指定多个审查目标
7. **审查范围**：支持行级范围的审查（如特定函数）
