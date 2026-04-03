# ReviewTarget 研究文档

## 场景与职责

`ReviewTarget` 是 Codex app-server-protocol v2 协议中的代码审查目标类型，用于指定 AI 代码审查的具体对象。该类型是一个标签联合（tagged union），支持多种审查目标：未提交变更、分支对比、特定提交和自定义指令。

在 Codex 的代码审查功能中，`ReviewTarget` 承担以下职责：
1. **目标多样化**：支持不同类型的代码审查目标
2. **Git 集成**：与 Git 工作流紧密集成
3. **灵活审查**：支持自定义审查指令
4. **上下文传递**：传递审查所需的代码上下文

## 功能点目的

### 核心功能
- **未提交变更**：审查工作区中的 staged/unstaged 变更
- **分支对比**：审查当前分支与基础分支的差异
- **提交审查**：审查特定提交的变更
- **自定义审查**：使用任意指令进行审查

### 设计意图
- **覆盖完整**：覆盖常见的代码审查场景
- **类型安全**：使用标签联合确保类型安全
- **可扩展**：易于添加新的审查目标类型
- **与 Git 集成**：紧密集成 Git 工作流

## 具体技术实现

### 数据结构定义

**TypeScript 定义**（`ReviewTarget.ts`）：
```typescript
export type ReviewTarget = 
  | { "type": "uncommittedChanges" }
  | { "type": "baseBranch", branch: string }
  | { "type": "commit", sha: string, title: string | null }
  | { "type": "custom", instructions: string };
```

**Rust 定义**（`v2.rs` 行 3910-3932）：
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "camelCase")]
#[ts(tag = "type", export_to = "v2/")]
pub enum ReviewTarget {
    /// Review the working tree: staged, unstaged, and untracked files.
    UncommittedChanges,

    /// Review changes between the current branch and the given base branch.
    #[serde(rename_all = "camelCase")]
    #[ts(rename_all = "camelCase")]
    BaseBranch { branch: String },

    /// Review the changes introduced by a specific commit.
    #[serde(rename_all = "camelCase")]
    #[ts(rename_all = "camelCase")]
    Commit {
        sha: String,
        /// Optional human-readable label (e.g., commit subject) for UIs.
        title: Option<String>,
    },

    /// Arbitrary instructions, equivalent to the old free-form prompt.
    #[serde(rename_all = "camelCase")]
    #[ts(rename_all = "camelCase")]
    Custom { instructions: String },
}
```

### 变体说明

| 变体 | 字段 | 说明 | 使用场景 |
|------|------|------|----------|
| `UncommittedChanges` | 无 | 审查工作区中所有未提交的变更 | 提交前自检 |
| `BaseBranch` | `branch: string` | 审查当前分支与指定分支的差异 | PR 前审查 |
| `Commit` | `sha: string`, `title: string \| null` | 审查特定提交的变更 | 历史提交审查 |
| `Custom` | `instructions: string` | 使用自定义指令审查 | 特殊场景 |

### 与核心类型的映射

在 `codex_message_processor.rs` 行 597-600：
```rust
impl From<ApiReviewTarget> for CoreReviewTarget {
    fn from(value: ApiReviewTarget) -> Self {
        match value {
            ApiReviewTarget::UncommittedChanges => CoreReviewTarget::UncommittedChanges,
            ApiReviewTarget::BaseBranch { branch } => CoreReviewTarget::BaseBranch { branch },
            ApiReviewTarget::Commit { sha, title } => CoreReviewTarget::Commit { sha, title },
            ApiReviewTarget::Custom { instructions } => CoreReviewTarget::Custom { instructions },
        }
    }
}
```

### Prompt 生成

在 `core/src/review_prompts.rs` 行 39-68：
```rust
pub fn review_prompt(target: &ReviewTarget, cwd: &Path) -> anyhow::Result<String> {
    match target {
        ReviewTarget::UncommittedChanges => Ok(UNCOMMITTED_PROMPT.to_string()),
        ReviewTarget::BaseBranch { branch } => {
            // 生成对比分支的 prompt
        }
        ReviewTarget::Commit { sha, title } => {
            // 生成审查提交的 prompt
        }
        ReviewTarget::Custom { instructions } => {
            // 使用自定义指令
        }
    }
}
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 行 3910-3932
- **TypeScript 生成**：`codex-rs/app-server-protocol/schema/typescript/v2/ReviewTarget.ts`
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/ReviewStartParams.json`

### 使用位置
- **ReviewStartParams**：`v2.rs` 行 3886 - 审查启动参数
- **消息处理器**：`codex_message_processor.rs` 行 554-600 - 目标验证和转换
- **Prompt 生成**：`core/src/review_prompts.rs` 行 39 - 生成审查 prompt

### 相关类型
- `ReviewStartParams`：包含 `target: ReviewTarget`（行 3884-3893）
- `CoreReviewTarget`：核心协议中的对应类型（`protocol/src/protocol.rs` 行 2529-2551）
- `ReviewRequest`：核心层的审查请求（`protocol/src/protocol.rs` 行 2553-2560）

### 目标验证逻辑

在 `codex_message_processor.rs` 行 565-590：
```rust
fn normalize_review_target(target: ApiReviewTarget, cwd: &Path) -> anyhow::Result<ApiReviewTarget> {
    match target {
        ApiReviewTarget::Commit { sha, title } => {
            // 验证 SHA 格式（7-40 位十六进制）
            if !is_valid_sha(&sha) {
                return Err(anyhow!("Invalid commit SHA: {}", sha));
            }
            // 验证提交存在
            if !commit_exists(&sha, cwd) {
                return Err(anyhow!("Commit not found: {}", sha));
            }
            Ok(ApiReviewTarget::Commit { sha, title })
        }
        ApiReviewTarget::BaseBranch { branch } => {
            // 验证分支存在
            if !branch_exists(&branch, cwd) {
                return Err(anyhow!("Branch not found: {}", branch));
            }
            Ok(ApiReviewTarget::BaseBranch { branch })
        }
        // ... 其他变体
    }
}
```

## 依赖与外部交互

### 依赖项
- `serde`：序列化/反序列化支持
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成

### 上游依赖
- `CoreReviewTarget`（核心协议）：`protocol/src/protocol.rs`
- Git 命令：用于验证和获取代码变更

### 下游使用
- `ReviewStartParams`：审查启动参数
- `ReviewPrompt`：生成审查 prompt
- `user_facing_hint`：生成用户可见的提示文本

### 协议集成
- 通过 `review/start` RPC 方法的 `target` 参数传递
- 转换为 `CoreReviewTarget` 后传递给核心层

## 风险、边界与改进建议

### 潜在风险
1. **Git 依赖**：所有目标类型都依赖 Git，非 Git 项目无法使用
2. **路径遍历**：分支名称可能包含恶意路径
3. **SHA 碰撞**：短 SHA 可能存在碰撞风险
4. **性能问题**：大型仓库的 diff 计算可能很慢

### 边界情况
1. **空工作区**：`UncommittedChanges` 时没有变更
2. **无效 SHA**：`Commit` 变体的 SHA 不存在
3. **远程分支**：`BaseBranch` 指向远程分支
4. **合并提交**：审查合并提交的复杂情况
5. **超大 diff**：变更文件过多或过大

### 改进建议
1. **扩展目标类型**：
   ```rust
   pub enum ReviewTarget {
       // 现有变体...
       
       /// 审查特定文件或目录
       Path { path: PathBuf },
       /// 审查 PR/MR
       PullRequest { provider: String, id: String },
       /// 审查特定时间范围内的提交
       CommitRange { from: String, to: String },
       /// 审查 stash
       Stash { index: u32 },
   }
   ```

2. **验证增强**：
   - 添加 SHA 完整验证（40 位）
   - 验证分支名称合法性
   - 检查文件路径安全性
   - 限制 diff 大小

3. **性能优化**：
   - 实现 diff 缓存
   - 支持增量审查
   - 添加超时机制
   - 实现异步 diff 计算

4. **非 Git 支持**：
   - 支持 SVN、Mercurial 等版本控制
   - 支持普通目录对比
   - 支持文件上传审查

5. **用户体验**：
   - 提供目标预览
   - 支持目标历史记录
   - 添加目标模板
   - 实现目标自动补全

6. **安全增强**：
   - 审查敏感文件检测
   - 密钥泄露检测
   - 添加审查审计日志
