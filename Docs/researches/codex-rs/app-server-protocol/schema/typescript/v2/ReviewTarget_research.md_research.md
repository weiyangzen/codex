# ReviewTarget 研究文档

## 场景与职责

`ReviewTarget` 是 Codex App Server Protocol v2 中用于定义代码审查目标的枚举类型。它支持多种审查场景，包括审查未提交更改、比较基分支、审查特定提交以及执行自定义审查指令。

该类型是代码审查功能的核心组件，决定了审查的内容范围和上下文。

## 功能点目的

1. **多场景支持**：支持常见的代码审查场景
2. **Git 集成**：深度集成 Git 工作流
3. **灵活指令**：支持自定义审查指令
4. **类型安全**：使用 Rust 枚举确保目标类型的正确性

## 具体技术实现

### 数据结构

```rust
// Rust 定义 (codex-rs/app-server-protocol/src/protocol/v2.rs)
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

```typescript
// TypeScript 生成类型 (schema/typescript/v2/ReviewTarget.ts)
export type ReviewTarget = 
    | { "type": "uncommittedChanges" }
    | { "type": "baseBranch", branch: string }
    | { "type": "commit", sha: string, title: string | null }
    | { "type": "custom", instructions: string };
```

### 变体说明

| 变体 | 类型值 | 字段 | 说明 |
|------|--------|------|------|
| `UncommittedChanges` | `"uncommittedChanges"` | 无 | 审查工作区：暂存、未暂存和未跟踪的文件 |
| `BaseBranch` | `"baseBranch"` | `branch: String` | 比较当前分支与指定基分支的更改 |
| `Commit` | `"commit"` | `sha: String`, `title: Option<String>` | 审查特定提交引入的更改 |
| `Custom` | `"custom"` | `instructions: String` | 执行自定义审查指令 |

### 使用场景示例

#### 1. 未提交更改审查
```rust
ReviewTarget::UncommittedChanges
```
适用于：
- 提交前快速检查
- 查看当前工作区状态
- 暂存前代码审查

#### 2. 基分支比较
```rust
ReviewTarget::BaseBranch { 
    branch: "main".to_string() 
}
```
适用于：
- PR 审查
- 特性分支审查
- 合并前检查

#### 3. 特定提交审查
```rust
ReviewTarget::Commit { 
    sha: "abc123".to_string(),
    title: Some("Fix security vulnerability".to_string())
}
```
适用于：
- 历史提交分析
- 特定变更审查
- 回归分析

#### 4. 自定义指令
```rust
ReviewTarget::Custom { 
    instructions: "Review this code for performance bottlenecks".to_string() 
}
```
适用于：
- 安全审计
- 性能分析
- 特定关注点审查

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 3907-3932)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/ReviewTarget.ts`

### 相关类型
- `ReviewStartParams`: 包含 `target` 字段
- `ReviewStartResponse`: 审查启动响应

### 使用场景
- `review/start` API 的参数
- 测试用例中验证各种目标类型

## 依赖与外部交互

### 内部依赖
- `serde`: 序列化/反序列化
- `schemars`: JSON Schema 生成
- `ts_rs`: TypeScript 类型生成

### 协议交互

**未提交更改**:
```json
{
    "type": "uncommittedChanges"
}
```

**基分支比较**:
```json
{
    "type": "baseBranch",
    "branch": "main"
}
```

**特定提交**:
```json
{
    "type": "commit",
    "sha": "1234567deadbeef",
    "title": "Tidy UI colors"
}
```

**自定义指令**:
```json
{
    "type": "custom",
    "instructions": "Review for security issues"
}
```

## 风险、边界与改进建议

### 当前限制
1. **单目标限制**：一次只能审查一个目标
2. **无范围限制**：无法指定具体的文件或目录范围
3. **无历史范围**：无法指定提交范围（如 `commitA..commitB`）

### 边界情况
1. **空分支名**：`BaseBranch` 的 `branch` 字段为空或空白字符
2. **无效 SHA**：`Commit` 的 `sha` 字段格式无效或不存在
3. **空指令**：`Custom` 的 `instructions` 字段为空或仅包含空白字符
4. **非 Git 仓库**：在非 Git 仓库中使用 Git 相关的目标类型

### 验证逻辑

从测试代码可以看到验证要求：

```rust
// 空分支名验证
async fn review_start_rejects_empty_base_branch() -> Result<()> {
    let request_id = mcp
        .send_review_start_request(ReviewStartParams {
            target: ReviewTarget::BaseBranch {
                branch: "   ".to_string(),
            },
            // ...
        })
        .await?;
    // 期望返回错误：branch must not be empty
}

// 空 SHA 验证
async fn review_start_rejects_empty_commit_sha() -> Result<()> {
    let request_id = mcp
        .send_review_start_request(ReviewStartParams {
            target: ReviewTarget::Commit {
                sha: "\t".to_string(),
                title: None,
            },
            // ...
        })
        .await?;
    // 期望返回错误：sha must not be empty
}

// 空指令验证
async fn review_start_rejects_empty_custom_instructions() -> Result<()> {
    let request_id = mcp
        .send_review_start_request(ReviewStartParams {
            target: ReviewTarget::Custom {
                instructions: "\n\n".to_string(),
            },
            // ...
        })
        .await?;
    // 期望返回错误：instructions must not be empty
}
```

### 改进建议

1. **添加文件范围限制**：
   ```rust
   pub enum ReviewTarget {
       UncommittedChanges,
       UncommittedChangesWithPaths { paths: Vec<PathBuf> },  // 新增
       BaseBranch { branch: String },
       BaseBranchWithPaths { branch: String, paths: Vec<PathBuf> },  // 新增
       // ...
   }
   ```

2. **添加提交范围**：
   ```rust
   pub enum ReviewTarget {
       // ...
       CommitRange { 
           from_sha: String, 
           to_sha: String 
       },  // 新增
   }
   ```

3. **添加 PR 目标**：
   ```rust
   pub enum ReviewTarget {
       // ...
       PullRequest { 
           number: u32,
           remote: Option<String>,
       },  // 新增
   }
   ```

4. **添加标签目标**：
   ```rust
   pub enum ReviewTarget {
       // ...
       Tag { 
           name: String 
       },  // 新增
   }
   ```

### 兼容性注意
- 使用 tagged union 模式（`type` 字段）确保可扩展性
- 使用 `camelCase` 命名确保与 TypeScript 惯例一致
- 新增变体时，旧客户端应能安全忽略不识别的变体

### 使用建议

| 场景 | 推荐目标类型 | 示例 |
|------|-------------|------|
| 提交前检查 | `UncommittedChanges` | 审查暂存和未暂存的更改 |
| PR 准备 | `BaseBranch` | 比较特性分支与 main |
| 历史分析 | `Commit` | 审查特定提交的更改 |
| 安全审计 | `Custom` | "检查 SQL 注入漏洞" |
| 性能优化 | `Custom` | "分析性能瓶颈" |
