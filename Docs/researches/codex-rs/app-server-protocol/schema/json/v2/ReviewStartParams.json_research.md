# ReviewStartParams.json 研究文档

## 场景与职责

`ReviewStartParams` 是 Codex App-Server Protocol v2 API 中 `review/start` 方法的请求参数结构，用于启动代码审查流程。支持多种审查目标（未提交变更、分支对比、特定提交、自定义指令），并允许选择审查的交付方式（内联或分离）。

## 功能点目的

1. **代码审查启动**: 发起对代码变更的 AI 辅助审查
2. **多目标支持**: 支持审查工作目录变更、分支差异、特定提交或自定义范围
3. **交付模式选择**: 支持内联审查（当前线程）或分离审查（新建线程）
4. **集成 Git 工作流**: 与 Git 操作紧密集成，支持多种 Git 场景

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ReviewStartParams {
    pub thread_id: String,
    pub target: ReviewTarget,
    #[serde(default)]
    pub delivery: Option<ReviewDelivery>,
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `threadId` | string | 是 | 当前线程 ID |
| `target` | ReviewTarget | 是 | 审查目标（Tagged Union） |
| `delivery` | ReviewDelivery \| null | 否 | 交付方式，默认 null（表示 inline） |

### ReviewTarget 联合类型

**UncommittedChangesReviewTarget**:
- `type`: "uncommittedChanges"
- 审查工作目录中的已暂存、未暂存和未跟踪文件

**BaseBranchReviewTarget**:
- `type`: "baseBranch"
- `branch`: string - 要对比的基础分支名称
- 审查当前分支与指定基础分支之间的差异

**CommitReviewTarget**:
- `type`: "commit"
- `sha`: string - 提交的 SHA
- `title`: string \| null - 可选的人类可读标签（如提交主题）
- 审查特定提交引入的变更

**CustomReviewTarget**:
- `type`: "custom"
- `instructions`: string - 任意审查指令
- 相当于旧的自由格式提示词

### ReviewDelivery 枚举

- `inline`: 在当前线程上运行审查（默认）
- `detached`: 在新线程上运行审查，返回的 `reviewThreadId` 指向新线程

### JSON Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "ReviewDelivery": {
      "enum": ["inline", "detached"],
      "type": "string"
    },
    "ReviewTarget": {
      "oneOf": [
        {
          "description": "Review the working tree: staged, unstaged, and untracked files.",
          "properties": {
            "type": { "enum": ["uncommittedChanges"], "type": "string" }
          },
          "required": ["type"],
          "title": "UncommittedChangesReviewTarget",
          "type": "object"
        },
        {
          "description": "Review changes between the current branch and the given base branch.",
          "properties": {
            "branch": { "type": "string" },
            "type": { "enum": ["baseBranch"], "type": "string" }
          },
          "required": ["branch", "type"],
          "title": "BaseBranchReviewTarget",
          "type": "object"
        },
        {
          "description": "Review the changes introduced by a specific commit.",
          "properties": {
            "sha": { "type": "string" },
            "title": { "description": "Optional human-readable label", "type": ["string", "null"] },
            "type": { "enum": ["commit"], "type": "string" }
          },
          "required": ["sha", "type"],
          "title": "CommitReviewTarget",
          "type": "object"
        },
        {
          "description": "Arbitrary instructions, equivalent to the old free-form prompt.",
          "properties": {
            "instructions": { "type": "string" },
            "type": { "enum": ["custom"], "type": "string" }
          },
          "required": ["instructions", "type"],
          "title": "CustomReviewTarget",
          "type": "object"
        }
      ]
    }
  },
  "properties": {
    "delivery": {
      "anyOf": [{ "$ref": "#/definitions/ReviewDelivery" }, { "type": "null" }],
      "default": null,
      "description": "Where to run the review: inline (default) on the current thread or detached on a new thread"
    },
    "target": { "$ref": "#/definitions/ReviewTarget" },
    "threadId": { "type": "string" }
  },
  "required": ["target", "threadId"],
  "title": "ReviewStartParams",
  "type": "object"
}
```

## 关键代码路径与文件引用

### 源文件位置
- **Rust 结构定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `ReviewStartParams`: 第 3884 行附近
  - `ReviewTarget`: 第 3860 行附近（Tagged Union）
  - `ReviewDelivery`: 通过宏 `v2_enum_from_core!` 定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ReviewStartParams {
    pub thread_id: String,
    pub target: ReviewTarget,
    #[serde(default)]
    pub delivery: Option<ReviewDelivery>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "camelCase")]
#[ts(tag = "type")]
#[ts(export_to = "v2/")]
pub enum ReviewTarget {
    UncommittedChanges,
    BaseBranch { branch: String },
    Commit { sha: String, title: Option<String> },
    Custom { instructions: String },
}
```

### Schema 生成
- **生成工具**: `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs`
- **生成函数**: `export_client_param_schemas()` 在 `common.rs` 中定义

### 使用位置
- **ClientRequest 定义**: `codex-rs/app-server-protocol/src/protocol/common.rs` 第 384-387 行
```rust
ReviewStart => "review/start" {
    params: v2::ReviewStartParams,
    response: v2::ReviewStartResponse,
}
```

### 核心枚举映射
```rust
v2_enum_from_core! {
    pub enum ReviewDelivery from codex_protocol::protocol::ReviewDelivery {
        Inline, Detached
    }
}
```

## 依赖与外部交互

### 内部依赖
1. **codex_protocol**: 核心协议类型（ReviewDelivery）
2. **schemars**: JSON Schema 生成
3. **ts_rs**: TypeScript 类型生成
4. **serde**: 序列化/反序列化

### 外部交互
1. **Git 系统**: 执行 Git 命令获取差异信息
2. **AI 模型**: 将代码变更发送给模型进行审查
3. **文件系统**: 读取工作目录和 Git 仓库状态

### 关联响应类型
- `ReviewStartResponse`: 包含 `reviewThreadId` 和 `turn`

## 风险、边界与改进建议

### 风险点
1. **Git 依赖**: 需要有效的 Git 仓库，非 Git 项目无法使用
2. **大差异处理**: 大量变更可能导致审查时间过长或超出模型上下文限制
3. **并发审查**: 同一目标的多次审查可能产生冲突
4. **敏感信息**: 代码审查可能暴露敏感信息（密钥、密码等）

### 边界情况
1. **空仓库**: 新仓库没有提交历史时的处理
2. **干净工作目录**: 没有未提交变更时的处理
3. **无效分支/提交**: 指定的分支或提交不存在
4. **合并冲突**: 审查时存在未解决的合并冲突
5. **二进制文件**: 二进制文件的审查处理

### 改进建议
1. **添加范围限制**: 限制审查的文件数量或变更大小：
   ```rust
   pub struct ReviewStartParams {
       // ... existing fields
       pub max_files: Option<u32>,      // 最大文件数
       pub max_lines: Option<u32>,      // 最大行数
       pub exclude_patterns: Vec<String>, // 排除模式
   }
   ```

2. **添加审查模板**: 支持预定义的审查模板：
   ```rust
   pub enum ReviewTarget {
       // ... existing variants
       Template { name: String },  // 使用预定义模板
   }
   ```

3. **增量审查**: 支持只审查自上次审查后的新变更：
   ```rust
   pub struct ReviewStartParams {
       // ... existing fields
       pub since_review_id: Option<String>,  // 基于上次审查的增量
   }
   ```

4. **审查焦点**: 允许指定审查重点：
   ```rust
   pub struct ReviewStartParams {
       // ... existing fields
       pub focus: Vec<ReviewFocus>,  // security, performance, style, etc.
   }
   ```

5. **异步状态查询**: 对长时间运行的审查支持状态查询
