# ThreadForkParams.ts 研究文档

## 场景与职责

`ThreadForkParams` 是 Codex App-Server Protocol v2 API 中 `thread/fork` 方法的请求参数类型，用于从现有线程创建一个新的分支线程。这是实现对话分支、实验不同方案的关键功能。

## 功能点目的

### 核心功能

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 源线程 ID |
| `path` | `string \| null` | [UNSTABLE] 指定 rollout 路径进行分叉 |
| `model` | `string \| null` | 覆盖模型 |
| `modelProvider` | `string \| null` | 覆盖模型提供商 |
| `serviceTier` | `ServiceTier \| null \| null` | 覆盖服务层级 |
| `cwd` | `string \| null` | 覆盖工作目录 |
| `approvalPolicy` | `AskForApproval \| null` | 覆盖审批策略 |
| `approvalsReviewer` | `ApprovalsReviewer \| null` | 覆盖审批审核者 |
| `sandbox` | `SandboxMode \| null` | 覆盖沙盒模式 |
| `config` | `{ [key: string]?: JsonValue } \| null` | 额外配置 |
| `baseInstructions` | `string \| null` | 覆盖基础指令 |
| `developerInstructions` | `string \| null` | 覆盖开发者指令 |
| `ephemeral` | `boolean` | 是否为临时线程 |
| `persistExtendedHistory` | `boolean` | 是否持久化扩展历史 |

### 设计特点

1. **两种分叉方式**：
   - 通过 `threadId` 从磁盘加载并分叉
   - 通过 `path` 从指定 rollout 路径分叉（`path` 优先）

2. **完全可配置**：支持覆盖源线程的所有配置参数
3. **历史继承**：新线程继承源线程的对话历史

## 具体技术实现

### TypeScript 类型定义

```typescript
export type ThreadForkParams = {
  threadId: string,
  path?: string | null,
  model?: string | null,
  modelProvider?: string | null,
  serviceTier?: ServiceTier | null | null,
  cwd?: string | null,
  approvalPolicy?: AskForApproval | null,
  approvalsReviewer?: ApprovalsReviewer | null,
  sandbox?: SandboxMode | null,
  config?: { [key in string]?: JsonValue } | null,
  baseInstructions?: string | null,
  developerInstructions?: string | null,
  ephemeral?: boolean,
  persistExtendedHistory: boolean
};
```

### Rust 源码对应

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 2630-2688) 中定义：

```rust
#[derive(Serialize, Deserialize, Debug, Default, Clone, PartialEq, JsonSchema, TS, ExperimentalApi)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadForkParams {
    pub thread_id: String,
    #[experimental("thread/fork.path")]
    #[ts(optional = nullable)]
    pub path: Option<PathBuf>,
    #[ts(optional = nullable)]
    pub model: Option<String>,
    // ... 其他字段
    #[experimental("thread/fork.persistFullHistory")]
    #[serde(default)]
    pub persist_extended_history: bool,
}
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源码）
- `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 2630-2688): Rust 类型定义

### 下游使用方
- 客户端调用 `thread/fork` RPC 方法

### 相关类型
- `ThreadForkResponse.ts`: 分叉响应
- `ThreadResumeParams.ts`: 类似结构，用于恢复线程

## 依赖与外部交互

### 使用示例

```typescript
import type { ThreadForkParams } from "./v2";

// 基本分叉
const params: ThreadForkParams = {
  threadId: "thread_abc123",
  persistExtendedHistory: false
};

// 使用不同模型分叉
const paramsWithModel: ThreadForkParams = {
  threadId: "thread_abc123",
  model: "gpt-4",
  modelProvider: "openai",
  ephemeral: true,
  persistExtendedHistory: true
};

const response = await client.request("thread/fork", params);
```

## 风险、边界与改进建议

### 边界情况

1. **path 与 threadId**：`path` 指定时 `threadId` 被忽略
2. **循环分叉**：从已分叉线程再次分叉的处理
3. **历史一致性**：分叉后源线程历史变更不影响新线程

### 改进建议

1. **添加分叉名称**：`forkName` 用于标识分叉目的
2. **添加标签**：支持添加标签便于管理
3. **批量分叉**：支持一次创建多个分叉进行 A/B 测试

### 注意事项

- 该文件为**自动生成**
- `path` 字段为实验性 API，不稳定
- `persistExtendedHistory` 为实验性功能
