# ReviewStartParams 研究文档

## 场景与职责

`ReviewStartParams` 是 Codex App Server Protocol v2 中用于启动代码审查操作的参数结构体。它定义了客户端请求代码审查时需要提供的参数，包括目标线程、审查目标和交付模式。

该类型是代码审查功能的核心入口，支持多种审查目标（未提交更改、基分支比较、特定提交、自定义指令）和两种交付模式（内联/分离）。

## 功能点目的

1. **审查目标指定**：支持多种代码审查场景
2. **线程关联**：指定审查关联的线程
3. **交付模式控制**：选择内联或分离审查模式
4. **灵活配置**：支持自定义审查指令

## 具体技术实现

### 数据结构

```rust
// Rust 定义 (codex-rs/app-server-protocol/src/protocol/v2.rs)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ReviewStartParams {
    pub thread_id: String,
    pub target: ReviewTarget,
    /// Where to run the review: inline (default) on the current thread or
    /// detached on a new thread (returned in `reviewThreadId`).
    #[serde(default)]
    #[ts(optional = nullable)]
    pub delivery: Option<ReviewDelivery>,
}
```

```typescript
// TypeScript 生成类型 (schema/typescript/v2/ReviewStartParams.ts)
export type ReviewStartParams = { 
    threadId: string, 
    target: ReviewTarget, 
    /**
     * Where to run the review: inline (default) on the current thread or
     * detached on a new thread (returned in `reviewThreadId`).
     */
    delivery?: ReviewDelivery | null, 
};
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `thread_id` | `String` | 是 | 要启动审查的线程 ID |
| `target` | `ReviewTarget` | 是 | 审查目标（未提交更改/基分支/提交/自定义指令） |
| `delivery` | `Option<ReviewDelivery>` | 否 | 交付模式：`inline`（默认）或 `detached` |

### 审查目标类型

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

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 3881-3893)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/ReviewStartParams.ts`

### 相关类型
- `ReviewTarget`: 审查目标枚举
- `ReviewDelivery`: 交付模式枚举
- `ReviewStartResponse`: 审查启动响应

### 使用场景
- 客户端调用 `review/start` 方法时传递此参数
- 服务器根据参数启动相应的审查流程

## 依赖与外部交互

### 内部依赖
- `ReviewTarget`: 审查目标类型
- `ReviewDelivery`: 交付模式类型
- `serde`: 序列化/反序列化
- `schemars`: JSON Schema 生成
- `ts_rs`: TypeScript 类型生成

### 协议交互

**审查未提交更改**:
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "review/start",
    "params": {
        "threadId": "thread-123",
        "target": {
            "type": "uncommittedChanges"
        },
        "delivery": "inline"
    }
}
```

**审查特定提交**:
```json
{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "review/start",
    "params": {
        "threadId": "thread-123",
        "target": {
            "type": "commit",
            "sha": "1234567deadbeef",
            "title": "Tidy UI colors"
        },
        "delivery": "detached"
    }
}
```

**审查基分支**:
```json
{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "review/start",
    "params": {
        "threadId": "thread-123",
        "target": {
            "type": "baseBranch",
            "branch": "main"
        }
    }
}
```

**自定义审查指令**:
```json
{
    "jsonrpc": "2.0",
    "id": 4,
    "method": "review/start",
    "params": {
        "threadId": "thread-123",
        "target": {
            "type": "custom",
            "instructions": "Review this code for security vulnerabilities"
        }
    }
}
```

## 风险、边界与改进建议

### 当前限制
1. **单目标限制**：一次只能审查一个目标
2. **无范围限制**：无法指定审查的文件范围
3. **无深度控制**：无法控制审查的深度或详细程度

### 边界情况
1. **空分支名**：`BaseBranch` 的 `branch` 字段为空时的处理
2. **无效提交 SHA**：`Commit` 的 `sha` 字段无效时的处理
3. **空自定义指令**：`Custom` 的 `instructions` 为空时的处理

### 测试覆盖

从 `review.rs` 测试文件可以看到边界测试：

```rust
// 测试空分支名
#[tokio::test]
async fn review_start_rejects_empty_base_branch() -> Result<()> {
    let request_id = mcp
        .send_review_start_request(ReviewStartParams {
            thread_id,
            delivery: Some(ReviewDelivery::Inline),
            target: ReviewTarget::BaseBranch {
                branch: "   ".to_string(),  // 空分支名
            },
        })
        .await?;
    // 期望返回错误
    assert_eq!(error.error.code, INVALID_REQUEST_ERROR_CODE);
    assert!(error.error.message.contains("branch must not be empty"));
}

// 测试空提交 SHA
#[tokio::test]
async fn review_start_rejects_empty_commit_sha() -> Result<()> {
    let request_id = mcp
        .send_review_start_request(ReviewStartParams {
            thread_id,
            delivery: Some(ReviewDelivery::Inline),
            target: ReviewTarget::Commit {
                sha: "\t".to_string(),  // 空白 SHA
                title: None,
            },
        })
        .await?;
    // 期望返回错误
    assert_eq!(error.error.code, INVALID_REQUEST_ERROR_CODE);
    assert!(error.error.message.contains("sha must not be empty"));
}

// 测试空自定义指令
#[tokio::test]
async fn review_start_rejects_empty_custom_instructions() -> Result<()> {
    let request_id = mcp
        .send_review_start_request(ReviewStartParams {
            thread_id,
            delivery: Some(ReviewDelivery::Inline),
            target: ReviewTarget::Custom {
                instructions: "\n\n".to_string(),  // 空白指令
            },
        })
        .await?;
    // 期望返回错误
    assert_eq!(error.error.code, INVALID_REQUEST_ERROR_CODE);
    assert!(error.error.message.contains("instructions must not be empty"));
}
```

### 改进建议

1. **添加文件范围限制**：
   ```rust
   pub struct ReviewStartParams {
       pub thread_id: String,
       pub target: ReviewTarget,
       pub delivery: Option<ReviewDelivery>,
       pub file_patterns: Option<Vec<String>>,  // 新增：文件匹配模式
   }
   ```

2. **添加审查深度控制**：
   ```rust
   pub struct ReviewStartParams {
       // ...
       pub depth: Option<ReviewDepth>,  // 新增：quick/normal/deep
   }
   
   pub enum ReviewDepth {
       Quick,   // 快速检查
       Normal,  // 标准审查
       Deep,    // 深度分析
   }
   ```

3. **支持多目标审查**：
   ```rust
   pub struct ReviewStartParams {
       pub thread_id: String,
       pub targets: Vec<ReviewTarget>,  // 改为数组
       // ...
   }
   ```

4. **添加上下文信息**：
   ```rust
   pub struct ReviewStartParams {
       // ...
       pub context: Option<ReviewContext>,  // 新增：PR 信息、Issue 关联等
   }
   ```

### 兼容性注意
- 使用 `#[serde(default)]` 确保 `delivery` 字段的向后兼容
- `ReviewTarget` 使用 tagged union 模式确保可扩展性
- 验证错误返回标准的 JSON-RPC 错误格式

### 使用建议

| 场景 | 推荐目标类型 | 推荐交付模式 |
|------|-------------|-------------|
| 检查当前工作区 | `UncommittedChanges` | `Inline` |
| PR 审查 | `BaseBranch` | `Detached` |
| 特定提交分析 | `Commit` | `Inline` |
| 安全审计 | `Custom` | `Detached` |
