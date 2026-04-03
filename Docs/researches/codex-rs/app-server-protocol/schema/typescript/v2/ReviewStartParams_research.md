# ReviewStartParams 研究文档

## 场景与职责

`ReviewStartParams` 是 Codex app-server-protocol v2 协议中 `review/start` 方法的请求参数类型，用于发起 AI 代码审查请求。该类型封装了启动代码审查所需的全部参数，包括目标线程、审查目标和交付模式。

在 Codex 的代码审查功能中，`ReviewStartParams` 承担以下职责：
1. **审查发起**：指定要审查的目标（代码变更、提交等）
2. **线程关联**：将审查与特定线程关联
3. **模式控制**：控制审查结果的交付方式
4. **上下文传递**：传递审查所需的上下文信息

## 功能点目的

### 核心功能
- **目标指定**：通过 `target` 字段指定审查的具体目标
- **线程绑定**：通过 `threadId` 指定审查所属的线程
- **交付控制**：通过 `delivery` 控制审查结果的展示方式
- **类型安全**：使用强类型确保参数正确性

### 设计意图
- **明确职责**：每个字段职责单一明确
- **灵活目标**：支持多种审查目标（未提交变更、分支、提交、自定义）
- **可选模式**：交付模式为可选，默认为内联模式

## 具体技术实现

### 数据结构定义

**TypeScript 定义**（`ReviewStartParams.ts`）：
```typescript
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

**Rust 定义**（`v2.rs` 行 3884-3893）：
```rust
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

### 关键字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `threadId` | `string` | 是 | 目标线程的唯一标识符 |
| `target` | `ReviewTarget` | 是 | 审查目标（未提交变更、分支、提交、自定义） |
| `delivery` | `ReviewDelivery \| null` | 否 | 审查结果交付模式，默认为 `inline` |

### ReviewTarget 变体

**TypeScript 定义**：
```typescript
export type ReviewTarget = 
  | { "type": "uncommittedChanges" }
  | { "type": "baseBranch", branch: string }
  | { "type": "commit", sha: string, title: string | null }
  | { "type": "custom", instructions: string };
```

| 变体 | 说明 |
|------|------|
| `uncommittedChanges` | 审查工作区中未提交的变更 |
| `baseBranch` | 审查当前分支与指定基础分支的差异 |
| `commit` | 审查特定提交的变更 |
| `custom` | 使用自定义指令进行审查 |

### 处理流程

```
ClientRequest::ReviewStart { params: ReviewStartParams }
  ↓
codex_message_processor.rs::review_start() 行 6488
  ↓
解析 ReviewStartParams
  ↓
验证 target 和 thread_id
  ↓
根据 delivery 模式确定 review_thread_id
  ↓
启动审查流程
  ↓
返回 ReviewStartResponse { turn, reviewThreadId }
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 行 3884-3893
- **TypeScript 生成**：`codex-rs/app-server-protocol/schema/typescript/v2/ReviewStartParams.ts`
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/ReviewStartParams.json`

### 使用位置
- **ClientRequest 定义**：`common.rs` 行 385 - 注册为 RPC 方法参数
- **消息处理器**：`codex_message_processor.rs` 行 6488-6530 - 处理审查请求
- **测试用例**：`tests/suite/v2/review.rs` - 测试审查功能

### 相关类型
- `ReviewTarget`：审查目标类型（行 3910-3932）
- `ReviewDelivery`：交付模式类型（行 328）
- `ReviewStartResponse`：对应的响应类型（行 3898-3905）
- `Turn`：审查创建的回合

### 转换逻辑

在 `codex_message_processor.rs` 行 565-600：
```rust
fn normalize_review_target(target: ApiReviewTarget, cwd: &Path) -> ApiReviewTarget {
    match target {
        ApiReviewTarget::Commit { sha, title } => {
            // 验证提交 SHA 格式
            // ...
            ApiReviewTarget::Commit { sha, title }
        }
        ApiReviewTarget::BaseBranch { branch } => {
            // 处理分支名称
            // ...
            ApiReviewTarget::BaseBranch { branch }
        }
        // ... 其他变体
    }
}
```

## 依赖与外部交互

### 依赖项
- `ReviewTarget`：审查目标类型
- `ReviewDelivery`：交付模式类型
- `serde`：序列化/反序列化支持
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成

### 上游依赖
- `CoreReviewTarget`（核心协议）：`protocol/src/protocol.rs`
- `ReviewPrompt`（核心层）：`core/src/review_prompts.rs`

### 下游使用
- `ClientRequest::ReviewStart`：RPC 请求
- `ReviewStartResponse`：形成请求-响应配对

### 协议集成
- RPC 方法名：`review/start`（`common.rs` 行 385-386）
- 请求方向：Client → Server
- 响应类型：`ReviewStartResponse`

## 风险、边界与改进建议

### 潜在风险
1. **无效目标**：`target` 指向不存在的提交或分支
2. **权限问题**：用户可能没有权限审查某些代码
3. **资源消耗**：大型代码库的审查可能消耗大量资源
4. **并发冲突**：同一目标的并发审查可能产生冲突

### 边界情况
1. **空目标**：`target` 为空或无效
2. **不存在的线程**：`threadId` 指向不存在的线程
3. **超大变更**：审查包含大量文件的变更
4. **二进制文件**：审查包含二进制文件的变更

### 改进建议
1. **验证增强**：
   - 添加 `target` 存在性验证
   - 验证用户是否有权限审查目标
   - 检查目标大小，对超大变更发出警告

2. **功能扩展**：
   ```rust
   pub struct ReviewStartParams {
       // 现有字段...
       /// 审查范围（文件路径列表），null 表示全部
       pub scope: Option<Vec<PathBuf>>,
       /// 审查焦点（如 "security", "performance", "style"）
       pub focus: Option<String>,
       /// 审查严格程度
       pub thoroughness: Option<ReviewThoroughness>,
       /// 是否包含测试文件
       pub include_tests: Option<bool>,
   }
   ```

3. **性能优化**：
   - 支持增量审查（只审查变更的部分）
   - 实现审查缓存避免重复分析
   - 添加审查进度通知

4. **用户体验**：
   - 提供审查模板选择
   - 支持保存常用审查配置
   - 添加审查预览功能

5. **协作功能**：
   - 支持多人协作审查
   - 实现审查评论和讨论
   - 添加审查状态追踪

6. **集成增强**：
   - 与 GitHub/GitLab PR 集成
   - 支持 CI/CD 流水线触发审查
   - 提供审查报告导出
