# Thread.ts 研究文档

## 场景与职责

`Thread` 是 Codex App-Server Protocol v2 API 的核心数据类型，代表一个对话会话（线程）。它是整个协议中最基础、最重要的实体之一，承载着：

1. **会话管理**：标识和管理用户与 AI 的对话会话
2. **状态追踪**：记录线程的创建、更新、运行状态
3. **历史持久化**：存储对话历史，支持恢复、分叉、回滚等操作
4. **多源集成**：支持 CLI、VSCode、App Server、子代理等多种来源

## 功能点目的

### 核心字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `string` | 线程唯一标识符 |
| `preview` | `string` | 线程预览（通常是第一条用户消息） |
| `ephemeral` | `boolean` | 是否为临时线程（不持久化到磁盘） |
| `modelProvider` | `string` | 模型提供商（如 'openai'） |
| `createdAt` | `number` | Unix 时间戳（秒），创建时间 |
| `updatedAt` | `number` | Unix 时间戳（秒），最后更新时间 |
| `status` | `ThreadStatus` | 当前运行时状态 |
| `path` | `string \| null` | [UNSTABLE] 线程磁盘路径 |
| `cwd` | `string` | 工作目录 |
| `cliVersion` | `string` | 创建线程的 CLI 版本 |
| `source` | `SessionSource` | 线程来源（CLI、VSCode 等） |
| `agentNickname` | `string \| null` | 子代理昵称（AgentControl 生成） |
| `agentRole` | `string \| null` | 子代理角色 |
| `gitInfo` | `GitInfo \| null` | Git 元数据 |
| `name` | `string \| null` | 用户可见的线程标题 |
| `turns` | `Array<Turn>` | 对话轮次列表（条件填充） |

### 设计特点

1. **条件填充策略**：`turns` 字段仅在特定响应中填充，避免不必要的数据传输
2. **多源支持**：通过 `source` 字段支持多种客户端类型
3. **Git 集成**：捕获 Git 上下文，便于代码相关对话的追溯
4. **子代理支持**：`agentNickname` 和 `agentRole` 支持多代理协作场景

## 具体技术实现

### TypeScript 类型定义

```typescript
export type Thread = { 
  id: string, 
  preview: string, 
  ephemeral: boolean, 
  modelProvider: string, 
  createdAt: number, 
  updatedAt: number, 
  status: ThreadStatus, 
  path: string | null, 
  cwd: string, 
  cliVersion: string, 
  source: SessionSource, 
  agentNickname: string | null, 
  agentRole: string | null, 
  gitInfo: GitInfo | null, 
  name: string | null, 
  turns: Array<Turn>, 
};
```

### Rust 源码对应

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 3472-3512) 中定义：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct Thread {
    pub id: String,
    pub preview: String,
    pub ephemeral: bool,
    pub model_provider: String,
    #[ts(type = "number")]
    pub created_at: i64,
    #[ts(type = "number")]
    pub updated_at: i64,
    pub status: ThreadStatus,
    pub path: Option<PathBuf>,
    pub cwd: PathBuf,
    pub cli_version: String,
    pub source: SessionSource,
    pub agent_nickname: Option<String>,
    pub agent_role: Option<String>,
    pub git_info: Option<GitInfo>,
    pub name: Option<String>,
    pub turns: Vec<Turn>,
}
```

### turns 字段填充规则

根据注释说明，`turns` 仅在以下响应中填充：
- `thread/resume`
- `thread/rollback`
- `thread/fork`
- `thread/read`（当 `includeTurns` 为 true 时）

其他情况下 `turns` 为空列表，这是为了优化网络传输性能。

## 关键代码路径与文件引用

### 上游依赖（Rust 源码）
- `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 3472-3512): Rust 类型定义

### 下游使用方

| 文件 | 使用场景 |
|------|----------|
| `ThreadStartResponse.ts` | 线程启动响应 |
| `ThreadResumeResponse.ts` | 线程恢复响应 |
| `ThreadForkResponse.ts` | 线程分叉响应 |
| `ThreadReadResponse.ts` | 线程读取响应 |
| `ThreadRollbackResponse.ts` | 线程回滚响应 |
| `ThreadUnarchiveResponse.ts` | 线程取消归档响应 |
| `ThreadMetadataUpdateResponse.ts` | 元数据更新响应 |
| `ThreadStartedNotification.ts` | 线程启动通知 |
| `ThreadListResponse.ts` | 线程列表响应 |
| `TurnStartedNotification.ts` | 轮次启动通知 |
| `TurnCompletedNotification.ts` | 轮次完成通知 |

### 相关类型
- `ThreadStatus.ts`: 线程状态枚举
- `SessionSource.ts`: 会话来源枚举
- `GitInfo.ts`: Git 元数据类型
- `Turn.ts`: 对话轮次类型

## 依赖与外部交互

### 导入依赖
```typescript
import type { GitInfo } from "./GitInfo";
import type { SessionSource } from "./SessionSource";
import type { ThreadStatus } from "./ThreadStatus";
import type { Turn } from "./Turn";
```

### 使用示例

```typescript
import type { Thread } from "./v2";

// 线程创建响应
const thread: Thread = {
  id: "thread_abc123",
  preview: "Help me refactor this code",
  ephemeral: false,
  modelProvider: "openai",
  createdAt: 1704067200,
  updatedAt: 1704067200,
  status: { type: "idle" },
  path: "/home/user/.codex/threads/thread_abc123",
  cwd: "/home/user/project",
  cliVersion: "1.0.0",
  source: "cli",
  agentNickname: null,
  agentRole: null,
  gitInfo: {
    sha: "abc123",
    branch: "main",
    originUrl: "https://github.com/user/repo.git"
  },
  name: "Code Refactoring Session",
  turns: []
};
```

## 风险、边界与改进建议

### 边界情况

1. **path 字段不稳定**：标记为 [UNSTABLE]，未来可能变更或移除
2. **turns 数据量**：长对话的 turns 可能非常大，需要注意内存和传输性能
3. **时间戳精度**：Unix 秒级时间戳，不包含毫秒

### 改进建议

1. **分页加载**：对于长对话，考虑对 turns 进行分页
2. **增量更新**：支持只获取新增或修改的 turns
3. **压缩传输**：对大型线程考虑启用压缩
4. **类型细化**：`modelProvider` 可考虑使用联合类型而非 string

### 注意事项

- 该文件为**自动生成**
- `turns` 字段的填充是条件性的，客户端不应假设其始终包含完整数据
- `path` 字段为不稳定 API，避免依赖
