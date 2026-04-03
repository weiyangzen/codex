# ThreadForkResponse.ts 研究文档

## 场景与职责

`ThreadForkResponse` 是 Codex App-Server Protocol v2 API 中 `thread/fork` 方法的响应类型，返回新创建的分叉线程信息及其配置。

## 功能点目的

### 核心功能

| 字段 | 类型 | 说明 |
|------|------|------|
| `thread` | `Thread` | 新创建的线程对象 |
| `model` | `string` | 实际使用的模型 |
| `modelProvider` | `string` | 实际使用的模型提供商 |
| `serviceTier` | `ServiceTier \| null` | 实际使用的服务层级 |
| `cwd` | `string` | 实际工作目录 |
| `approvalPolicy` | `AskForApproval` | 实际审批策略 |
| `approvalsReviewer` | `ApprovalsReviewer` | 实际审批审核者 |
| `sandbox` | `SandboxPolicy` | 实际沙盒策略 |
| `reasoningEffort` | `ReasoningEffort \| null` | 推理努力程度 |

### 设计特点

1. **完整配置返回**：返回实际生效的所有配置参数
2. **线程对象包含**：包含完整的 Thread 对象，可直接使用
3. **与 ThreadResumeResponse 结构一致**：保持 API 一致性

## 具体技术实现

### TypeScript 类型定义

```typescript
export type ThreadForkResponse = { 
  thread: Thread, 
  model: string, 
  modelProvider: string, 
  serviceTier: ServiceTier | null, 
  cwd: string, 
  approvalPolicy: AskForApproval, 
  approvalsReviewer: ApprovalsReviewer, 
  sandbox: SandboxPolicy, 
  reasoningEffort: ReasoningEffort | null, 
};
```

### Rust 源码对应

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 2690-2705) 中定义：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS, ExperimentalApi)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadForkResponse {
    pub thread: Thread,
    pub model: String,
    pub model_provider: String,
    pub service_tier: Option<ServiceTier>,
    pub cwd: PathBuf,
    #[experimental(nested)]
    pub approval_policy: AskForApproval,
    pub approvals_reviewer: ApprovalsReviewer,
    pub sandbox: SandboxPolicy,
    pub reasoning_effort: Option<ReasoningEffort>,
}
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源码）
- `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 2690-2705): Rust 类型定义

### 下游使用方
- 客户端接收 `thread/fork` RPC 响应

### 相关类型
- `ThreadForkParams.ts`: 分叉请求参数
- `ThreadResumeResponse.ts`: 类似结构

## 依赖与外部交互

### 使用示例

```typescript
import type { ThreadForkResponse } from "./v2";

// 执行分叉
const response: ThreadForkResponse = await client.request("thread/fork", {
  threadId: "thread_abc123",
  model: "gpt-4",
  persistExtendedHistory: false
});

// 使用新线程
console.log(`New thread created: ${response.thread.id}`);
console.log(`Using model: ${response.model}`);
console.log(`Working directory: ${response.cwd}`);

// 继续对话
await client.request("turn/start", {
  threadId: response.thread.id,
  input: [{ type: "text", text: "Continue from here" }]
});
```

## 风险、边界与改进建议

### 改进建议

1. **添加源线程 ID**：明确记录从哪个线程分叉
2. **添加分叉时间**：`forkedAt` 记录分叉时间戳
3. **添加分叉深度**：记录这是第几层分叉

### 注意事项

- 该文件为**自动生成**
- `approvalPolicy` 为实验性嵌套字段
