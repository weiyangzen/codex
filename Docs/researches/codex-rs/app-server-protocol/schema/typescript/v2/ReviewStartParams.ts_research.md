# ReviewStartParams.ts 研究文档

## 场景与职责

`ReviewStartParams.ts` 定义了启动代码审查请求的参数数据结构，用于客户端向服务器发起代码审查请求。这是 Codex 代码审查功能的入口点，支持多种审查目标（未提交更改、分支、提交等）。

## 功能点目的

该类型用于：
1. **审查启动**：定义启动代码审查所需的全部参数
2. **目标指定**：支持多种审查目标类型（更改、分支、提交、自定义指令）
3. **交付控制**：选择审查在当前线程还是新线程执行
4. **工作流集成**：与 Git 工作流深度集成

## 具体技术实现

### 数据结构定义

```typescript
import type { ReviewDelivery } from "./ReviewDelivery";
import type { ReviewTarget } from "./ReviewTarget";

export type ReviewStartParams = { 
  threadId: string,           // 发起审查的线程ID
  target: ReviewTarget,       // 审查目标
  /**
   * Where to run the review: inline (default) on the current thread or
   * detached on a new thread (returned in `reviewThreadId`).
   */
  delivery?: ReviewDelivery | null,  // 交付方式，可选
};
```

### 字段详解

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| threadId | string | 是 | 发起审查的线程标识符 |
| target | ReviewTarget | 是 | 指定要审查的内容 |
| delivery | ReviewDelivery \| null | 否 | 审查执行位置，默认为 "inline" |

### ReviewTarget 联合类型

```typescript
type ReviewTarget = 
  | { type: "uncommittedChanges" }                    // 审查未提交更改
  | { type: "baseBranch"; branch: string }           // 审查与基础分支的差异
  | { type: "commit"; sha: string; title: string | null }  // 审查特定提交
  | { type: "custom"; instructions: string };        // 自定义审查指令
```

### Rust 协议定义

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ReviewStartParams {
    pub thread_id: String,
    pub target: ReviewTarget,
    #[ts(optional = nullable)]
    pub delivery: Option<ReviewDelivery>,
}
```

### 使用示例

#### 审查未提交更改

```typescript
const params: ReviewStartParams = {
  threadId: "thread-abc123",
  target: { type: "uncommittedChanges" },
  delivery: "inline"
};
```

#### 审查与基础分支的差异

```typescript
const params: ReviewStartParams = {
  threadId: "thread-abc123",
  target: { 
    type: "baseBranch", 
    branch: "main" 
  },
  delivery: "detached"
};
```

#### 审查特定提交

```typescript
const params: ReviewStartParams = {
  threadId: "thread-abc123",
  target: { 
    type: "commit", 
    sha: "a1b2c3d4",
    title: "Fix authentication bug"
  }
};
```

#### 自定义审查指令

```typescript
const params: ReviewStartParams = {
  threadId: "thread-abc123",
  target: { 
    type: "custom", 
    instructions: "Review the API design for RESTful principles"
  }
};
```

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/ReviewStartParams.ts`

### Rust 协议定义
- V2 协议：`codex-rs/app-server-protocol/src/protocol/v2.rs`
- 通用协议：`codex-rs/app-server-protocol/src/protocol/common.rs`

### 服务端实现
- 消息处理：`codex-rs/app-server/src/codex_message_processor.rs`

### 客户端使用
- Exec 模块：`codex-rs/exec/src/lib.rs`
- TUI 应用服务器：`codex-rs/tui_app_server/src/app_server_session.rs`

### 测试覆盖
- 审查测试：`codex-rs/app-server/tests/suite/v2/review.rs`
- TUI 测试：`codex-rs/tui_app_server/src/chatwidget/tests.rs`

### 相关类型
- ReviewDelivery：`codex-rs/app-server-protocol/schema/typescript/v2/ReviewDelivery.ts`
- ReviewTarget：`codex-rs/app-server-protocol/schema/typescript/v2/ReviewTarget.ts`
- ReviewStartResponse：`codex-rs/app-server-protocol/schema/typescript/v2/ReviewStartResponse.ts`

## 依赖与外部交互

### 上游依赖
- 用户输入：通过 TUI 或命令行收集审查参数
- Git 状态：获取当前仓库的未提交更改、分支等信息

### 下游消费
- 审查处理器：解析参数并启动相应的审查流程
- Git 集成：根据 target 类型执行不同的 Git 操作

### RPC 方法

```
review/start
```

请求：ReviewStartParams
响应：ReviewStartResponse

## 风险、边界与改进建议

### 边界情况
1. **空线程ID**：threadId 为空字符串可能导致错误
2. **无效目标**：target 指定的提交或分支可能不存在
3. **权限问题**：可能没有权限访问指定的审查目标

### 潜在风险
1. **大差异**：审查大量更改可能导致性能问题
2. **循环引用**：detached 审查中再次启动审查可能导致循环
3. **状态同步**：inline 和 detached 之间的状态同步复杂

### 改进建议
1. **验证增强**：在服务端增加 target 的有效性验证
2. **进度反馈**：对于大审查提供进度指示
3. **范围限制**：添加选项限制审查的文件数量或行数
4. **模板支持**：支持保存和复用常用审查配置
5. **批量审查**：支持一次指定多个审查目标
6. **审查预设**：提供常见审查场景的预设配置
