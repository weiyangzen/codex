# ThreadReadResponse.json 研究文档

## 场景与职责

`ThreadReadResponse` 是 Codex App-Server Protocol v2 API 中 `thread/read` 方法的响应结构，用于返回请求的线程完整信息。该响应是客户端获取线程状态、元数据和历史记录的主要途径。

**核心场景：**
1. **线程详情展示** - 客户端（VSCode/TUI）显示线程的完整信息面板
2. **历史记录浏览** - 当 `includeTurns=true` 时，展示完整的对话历史
3. **状态同步** - 操作后验证线程当前状态（如错误状态、活跃标志）
4. **离线浏览** - 访问已归档或未加载线程的信息

**典型使用流程：**
```rust
// 请求
ThreadReadParams { thread_id, include_turns: true }

// 响应
ThreadReadResponse {
    thread: Thread {
        id,
        preview,
        status,
        turns: [...], // 当 includeTurns=true 时填充
        ...
    }
}
```

## 功能点目的

### 1. 响应结构设计

```json
{
  "thread": {
    "id": "thread-uuid",
    "preview": "First user message...",
    "ephemeral": false,
    "model_provider": "openai",
    "created_at": 1736078400,
    "updated_at": 1736078500,
    "status": { "type": "idle" },
    "path": "/home/user/.codex/threads/...",
    "cwd": "/home/user/project",
    "cli_version": "1.0.0",
    "source": "cli",
    "agent_nickname": null,
    "agent_role": null,
    "git_info": { "sha": "abc123", "branch": "main", "origin_url": "..." },
    "name": "My Thread",
    "turns": [] // 或 Turn 数组
  }
}
```

**设计意图：**
- **封装性**：通过嵌套 `Thread` 对象，保持响应结构的一致性和可扩展性
- **完整性**：返回线程的所有元数据，无需额外查询
- **灵活性**：`turns` 字段根据请求参数动态填充

### 2. Thread 结构体详解

**核心字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | 线程唯一标识符（UUID） |
| `preview` | `String` | 预览文本（通常是第一条用户消息） |
| `ephemeral` | `bool` | 是否为临时线程（不持久化到磁盘） |
| `model_provider` | `String` | 模型提供商（如 'openai'） |
| `created_at` | `i64` | 创建时间戳（Unix 秒） |
| `updated_at` | `i64` | 最后更新时间戳（Unix 秒） |
| `status` | `ThreadStatus` | 当前运行状态 |
| `path` | `Option<PathBuf>` | 磁盘上的 rollout 文件路径 |
| `cwd` | `PathBuf` | 工作目录 |
| `cli_version` | `String` | 创建时 CLI 版本 |
| `source` | `SessionSource` | 来源（CLI/VSCode/Exec/AppServer） |
| `git_info` | `Option<GitInfo>` | Git 元数据 |
| `name` | `Option<String>` | 用户自定义名称 |
| `turns` | `Vec<Turn>` | 回合历史（条件填充） |

### 3. 状态机（ThreadStatus）

```rust
pub enum ThreadStatus {
    NotLoaded,           // 仅元数据加载，线程未激活
    Idle,                // 已加载，等待输入
    SystemError,         // 发生系统错误
    Active { active_flags: Vec<ThreadActiveFlag> }, // 正在处理中
}

pub enum ThreadActiveFlag {
    WaitingOnApproval,   // 等待用户批准
    WaitingOnUserInput,  // 等待用户输入
}
```

## 具体技术实现

### 1. Rust 源码定义

**文件路径：** `codex-rs/app-server-protocol/src/protocol/v2.rs:3055-3060`

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadReadResponse {
    pub thread: Thread,
}
```

**Thread 结构体定义（v2.rs:3475-3512）：**

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

### 2. JSON Schema 结构

**Schema 特点：**
- 内联定义所有依赖类型（`Thread`, `ThreadStatus`, `Turn`, `ThreadItem` 等）
- 使用 `definitions` 区块组织可复用类型
- 标记 `required` 字段，确保数据完整性
- 支持多种 `ThreadItem` 类型的 tagged union（通过 `type` 字段区分）

**主要定义区块：**
1. `Thread` - 主线程对象
2. `ThreadStatus` - 状态枚举（notLoaded, idle, systemError, active）
3. `Turn` - 回合对象
4. `ThreadItem` - 线程项目联合类型（userMessage, agentMessage, commandExecution 等）
5. `UserInput` - 用户输入联合类型（text, image, localImage, skill, mention）

### 3. 服务器端构建逻辑

**文件路径：** `codex-rs/app-server/src/codex_message_processor.rs`

```rust
async fn build_thread_response(
    &self,
    thread: &CodexThread,
    include_turns: bool,
) -> Thread {
    Thread {
        id: thread.id().to_string(),
        preview: thread.preview().to_string(),
        ephemeral: thread.is_ephemeral(),
        model_provider: thread.model_provider().to_string(),
        created_at: thread.created_at(),
        updated_at: thread.updated_at(),
        status: self.resolve_thread_status(thread).into(),
        path: Some(thread.path().to_path_buf()),
        cwd: thread.cwd().to_path_buf(),
        cli_version: thread.cli_version().to_string(),
        source: thread.source().into(),
        agent_nickname: thread.agent_nickname().map(String::from),
        agent_role: thread.agent_role().map(String::from),
        git_info: thread.git_info().map(Into::into),
        name: thread.name().map(String::from),
        turns: if include_turns {
            self.build_turns(thread).await
        } else {
            vec![]
        },
    }
}
```

### 4. TypeScript 类型定义

**文件路径：** `codex-rs/app-server-protocol/schema/typescript/v2/ThreadReadResponse.ts`

```typescript
import type { Thread } from "./Thread";

export type ThreadReadResponse = { thread: Thread };
```

**Thread.ts 类型（生成）：**
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

## 关键代码路径与文件引用

### 协议定义
| 文件 | 位置 | 说明 |
|------|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 3055-3060 | ThreadReadResponse 定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 3475-3512 | Thread 结构体定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 3022-3043 | ThreadStatus 定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 3583-3610 | Turn 结构体定义 |

### 服务器实现
| 文件 | 位置 | 说明 |
|------|------|------|
| `codex-rs/app-server/src/codex_message_processor.rs` | 3175+ | thread_read 处理 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 135 | 类型导入 |

### 生成的 Schema/类型
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ThreadReadResponse.json` | JSON Schema（本文件，约 44KB） |
| `codex-rs/app-server-protocol/schema/typescript/v2/ThreadReadResponse.ts` | TypeScript 响应类型 |
| `codex-rs/app-server-protocol/schema/typescript/v2/Thread.ts` | TypeScript Thread 类型 |

### 测试
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/thread_read.rs` | 核心集成测试（6+ 测试用例） |

## 依赖与外部交互

### 1. 上游依赖

```
ThreadReadResponse
  └── Thread
       ├── ThreadId (codex_protocol)
       ├── ThreadStatus
       ├── SessionSource (v2.rs:1464-1475)
       ├── GitInfo (v2.rs:1506-1510)
       ├── Turn (v2.rs:3583-3610)
       │    └── ThreadItem (v2.rs:822-1427)
       │         ├── UserMessage
       │         ├── AgentMessage
       │         ├── CommandExecution
       │         ├── FileChange
       │         ├── McpToolCall
       │         └── ... (10+ 类型)
       └── UserInput (v2.rs:1575-1693)
```

### 2. 数据转换层

```
Core Types (codex_core/codex_protocol)
  │
  ▼
V2 Types (app-server-protocol)
  │
  ▼
JSON / TypeScript (schema)
```

**转换示例：**
```rust
// Core -> V2
impl From<CoreSessionSource> for SessionSource { ... }
impl From<CoreGitInfo> for GitInfo { ... }
impl From<CoreThreadStatus> for ThreadStatus { ... }
```

### 3. 相关协议方法

| 方法 | 响应类型 | 说明 |
|------|----------|------|
| `thread/read` | `ThreadReadResponse` | 读取线程（本方法） |
| `thread/start` | `ThreadStartResponse` | 创建线程（含 Thread） |
| `thread/resume` | `ThreadResumeResponse` | 恢复线程（含 Thread + turns） |
| `thread/fork` | `ThreadForkResponse` | 分叉线程（含 Thread） |
| `thread/metadata/update` | `ThreadMetadataUpdateResponse` | 更新元数据（含 Thread） |

## 风险、边界与改进建议

### 1. 已知风险

**风险 1：Schema 体积过大**
- **描述**：ThreadReadResponse.json 约 44KB，包含大量嵌套定义
- **影响**：
  - 客户端代码生成耗时
  - 文档加载缓慢
  - 类型检查开销
- **缓解**：使用引用（`$ref`）而非内联，但当前为自包含 Schema

**风险 2：Turns 数据量不可控**
- **描述**：长线程的 `turns` 数组可能包含数千个 Item
- **影响**：
  - 内存峰值
  - JSON 序列化/反序列化开销
  - 网络传输延迟
- **缓解**：`includeTurns` 默认为 false

**风险 3：类型演进的兼容性**
- **描述**：`ThreadItem` 联合类型频繁新增变体
- **影响**：旧客户端可能无法识别新类型
- **缓解**：使用 `#[serde(other)]` 和默认值处理未知变体

### 2. 边界情况

| 场景 | 行为 |
|------|------|
| 新创建线程（未物化） | `turns: []`, `preview: ""`, `status: Idle` |
| 归档线程 | `status: NotLoaded`，路径指向归档目录 |
| 加载中的线程 | `status: Active { active_flags: [...] }` |
| 错误状态 | `status: SystemError` |
| 临时线程 | `ephemeral: true`, `path: null` |

### 3. 改进建议

**建议 1：响应压缩**
```rust
pub struct ThreadReadResponse {
    pub thread: Thread,
    pub compression: Option<CompressionInfo>, // 大响应使用 gzip
}
```

**建议 2：增量更新**
```rust
pub struct ThreadDeltaResponse {
    pub thread_id: String,
    pub changes: Vec<ThreadFieldChange>, // 仅返回变更字段
    pub removed_turns: Vec<String>,      // 删除的 Turn ID
    pub added_turns: Vec<Turn>,          // 新增的 Turn
}
```

**建议 3：字段访问控制**
```rust
pub struct ThreadReadParams {
    pub thread_id: String,
    pub include_turns: bool,
    pub field_mask: Option<Vec<String>>, // 仅返回指定字段
}
```

**建议 4：性能指标**
```rust
pub struct ThreadReadResponse {
    pub thread: Thread,
    pub meta: ResponseMeta, // 包含构建耗时、数据大小等
}
```

### 4. 测试缺口

| 缺口 | 优先级 | 说明 |
|------|--------|------|
| 极限数据量测试 | 高 | 验证超大 turns 数组的处理 |
| 序列化性能基准 | 中 | 测量 JSON 生成耗时 |
| 内存使用分析 | 中 | 验证大响应的内存峰值 |
| 向后兼容性测试 | 中 | 旧客户端解析新 ThreadItem 类型 |
