# ReviewTarget 研究文档

## 1. 场景与职责

`ReviewTarget` 是 Codex app-server-protocol v2 协议中的代码审查目标类型，用于指定 AI 代码审查的具体对象。该类型是一个标签联合（tagged union），支持多种审查目标：未提交变更、分支对比、特定提交和自定义指令。

### 使用场景
- **预提交审查**：审查工作目录中的未提交变更
- **分支对比审查**：比较当前分支与基础分支的差异
- **提交审查**：审查特定提交的变更
- **自定义审查**：基于任意指令进行代码审查

## 2. 功能点目的

该类型的核心目的是：
1. **灵活的审查对象**：支持多种 Git 操作场景下的代码审查
2. **类型安全**：通过标签联合确保每种目标类型的数据完整性
3. **可扩展性**：便于未来添加新的审查目标类型

### 审查目标类型对比
| 类型 | 描述 | 典型使用场景 |
|------|------|--------------|
| `uncommittedChanges` | 工作目录中的变更 | 提交前的快速审查 |
| `baseBranch` | 与基础分支的对比 | PR 前的完整审查 |
| `commit` | 特定提交的变更 | 历史提交审查 |
| `custom` | 自定义审查指令 | 特殊审查需求 |

## 3. 具体技术实现

### TypeScript 类型定义
```typescript
export type ReviewTarget = 
  | { "type": "uncommittedChanges" } 
  | { "type": "baseBranch", branch: string } 
  | { "type": "commit", sha: string, title: string | null } 
  | { "type": "custom", instructions: string };
```

### 字段说明

#### `uncommittedChanges`
| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | `"uncommittedChanges"` | 审查工作目录中的暂存、未暂存和未跟踪文件 |

#### `baseBranch`
| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | `"baseBranch"` | 分支对比模式 |
| `branch` | `string` | 基础分支名称（如 "main", "develop"） |

#### `commit`
| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | `"commit"` | 特定提交审查模式 |
| `sha` | `string` | 提交的 SHA 哈希 |
| `title` | `string \| null` | 可选的人类可读标签（如提交主题） |

#### `custom`
| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | `"custom"` | 自定义审查模式 |
| `instructions` | `string` | 自由形式的审查指令 |

### Rust 源实现
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

## 4. 关键代码路径与文件引用

### 协议定义
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 3907-3932)
- **TypeScript 文件**: `codex-rs/app-server-protocol/schema/typescript/v2/ReviewTarget.ts`

### 使用位置

#### 审查启动参数
- **文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - 作为 `ReviewStartParams` 的 `target` 字段

#### 消息处理器
- **文件**: `codex-rs/app-server/src/codex_message_processor.rs`
  - 解析 `ReviewTarget` 并执行相应的 Git 操作

#### 测试
- **文件**: `codex-rs/app-server/tests/suite/v2/review.rs`
  - 构造各种 `ReviewTarget` 变体进行测试

### JSON Schema
- `codex-rs/app-server-protocol/schema/json/ClientRequest.json`
- `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`
- `codex-rs/app-server-protocol/schema/json/v2/ReviewStartParams.json`

## 5. 依赖与外部交互

### 导入依赖
- 无直接导入的类型

### 被依赖类型
- `ReviewStartParams` - 包含 `target: ReviewTarget` 字段

### 核心协议映射
- 直接定义在 v2 协议中，无核心协议映射

## 6. 风险、边界与改进建议

### 潜在风险
1. **Git 状态依赖**：`uncommittedChanges` 类型依赖当前工作目录状态
2. **分支存在性**：`baseBranch` 类型需要验证分支是否存在
3. **提交有效性**：`commit` 类型需要验证 SHA 是否有效
4. **指令注入**：`custom` 类型的 `instructions` 需要防止提示注入

### 边界情况
- **空仓库**：在空 Git 仓库中使用某些类型可能失败
- **合并冲突**：工作目录有冲突时的审查行为
- **大变更集**：大量变更可能导致审查超时

### 改进建议
1. **添加范围限制**：
   ```typescript
   // uncommittedChanges 变体
   includeUntracked?: boolean;  // 是否包含未跟踪文件
   ```

2. **添加提交范围**：
   ```typescript
   // 新增 commitRange 变体
   | { type: "commitRange", base: string, head: string }
   ```

3. **添加文件过滤**：
   ```typescript
   // 所有变体支持可选的文件过滤
   fileFilter?: {
     include?: string[];  // glob 模式
     exclude?: string[];
   };
   ```

4. **验证增强**：
   - 服务端添加 Git 状态验证
   - 提供预览功能，让客户端确认审查范围

5. **性能优化**：
   - 对于大变更集，支持分块审查
   - 添加变更大小预估

### 使用示例
```typescript
// 审查未提交变更
const target1: ReviewTarget = { type: "uncommittedChanges" };

// 与 main 分支对比
const target2: ReviewTarget = { 
  type: "baseBranch", 
  branch: "main" 
};

// 审查特定提交
const target3: ReviewTarget = { 
  type: "commit", 
  sha: "a1b2c3d", 
  title: "Fix authentication bug" 
};

// 自定义审查
const target4: ReviewTarget = { 
  type: "custom", 
  instructions: "重点检查安全漏洞和性能问题" 
};
```

### 类型守卫函数
```typescript
// 便于 TypeScript 类型收窄的守卫函数
function isUncommittedChanges(target: ReviewTarget): target is { type: "uncommittedChanges" } {
  return target.type === "uncommittedChanges";
}

function isBaseBranch(target: ReviewTarget): target is { type: "baseBranch", branch: string } {
  return target.type === "baseBranch";
}

function isCommit(target: ReviewTarget): target is { type: "commit", sha: string, title: string | null } {
  return target.type === "commit";
}

function isCustom(target: ReviewTarget): target is { type: "custom", instructions: string } {
  return target.type === "custom";
}
```

### 相关类型关系
```
ReviewStartParams
├── threadId: string
├── target: ReviewTarget  <-- 本类型
│   ├── type: "uncommittedChanges"
│   ├── type: "baseBranch", branch: string
│   ├── type: "commit", sha: string, title?: string
│   └── type: "custom", instructions: string
└── delivery?: ReviewDelivery
```
