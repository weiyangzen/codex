# ThreadStartResponse.json 研究文档

## 场景与职责

`ThreadStartResponse` 是 Codex App-Server Protocol v2 中 `thread/start` RPC 方法的响应结构。当客户端成功调用 `thread/start` 创建新线程后，服务器返回此响应，确认线程已创建并返回线程的完整状态信息。

该响应结构的核心职责：
- 确认线程创建成功
- 返回创建的 `Thread` 对象（包含线程 ID、状态、元数据等）
- 返回实际生效的运行时配置（模型、沙箱、审批策略等）
- 支持客户端同步服务器端配置决议结果

## 功能点目的

### 1. 线程对象

| 字段 | 类型 | 用途 |
|------|------|------|
| `thread` | `Thread` | 创建的线程完整信息（**必需**） |

`Thread` 结构包含：
- `id`: 线程唯一标识符
- `created_at`/`updated_at`: 时间戳
- `cwd`: 工作目录
- `status`: 线程状态（notLoaded/idle/active/systemError）
- `turns`: 回合列表（启动时为空）
- `source`: 会话来源（cli/vscode/exec/appServer）
- `ephemeral`: 是否为临时线程
- `git_info`: Git 元数据

### 2. 运行时配置确认

| 字段 | 类型 | 用途 |
|------|------|------|
| `model` | `String` | 实际使用的模型 |
| `model_provider` | `String` | 实际使用的模型提供商 |
| `service_tier` | `Option<ServiceTier>` | 服务层级（fast/flex） |
| `cwd` | `PathBuf` | 实际工作目录 |
| `reasoning_effort` | `Option<ReasoningEffort>` | 推理努力程度 |

### 3. 安全与审批配置

| 字段 | 类型 | 用途 |
|------|------|------|
| `approval_policy` | `AskForApproval` | 实际生效的审批策略（实验性） |
| `approvals_reviewer` | `ApprovalsReviewer` | 审批请求路由目标 |
| `sandbox` | `SandboxPolicy` | 实际生效的沙箱策略 |

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS, ExperimentalApi)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadStartResponse {
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

### 关键特性

1. **配置决议回显**：响应中的配置字段反映了服务器端配置层（Config Layer）的决议结果，可能与请求参数不同

2. **实验性嵌套标记**：`#[experimental(nested)]` 表示该字段内部包含实验性子字段

3. **路径类型**：`cwd` 使用 `PathBuf` 而非字符串，保持类型安全

### Thread 结构详解

```rust
pub struct Thread {
    pub id: String,
    pub created_at: i64,
    pub updated_at: i64,
    pub cwd: String,
    pub status: ThreadStatus,
    pub turns: Vec<Turn>,
    pub source: SessionSource,
    pub ephemeral: bool,
    pub model_provider: String,
    pub cli_version: String,
    pub preview: String,
    pub name: Option<String>,
    pub path: Option<String>,
    pub git_info: Option<GitInfo>,
    pub agent_nickname: Option<String>,
    pub agent_role: Option<String>,
}
```

### ThreadStatus 枚举

```rust
pub enum ThreadStatus {
    NotLoaded,
    Idle,
    SystemError,
    Active { active_flags: Vec<ThreadActiveFlag> },
}

pub enum ThreadActiveFlag {
    WaitingOnApproval,
    WaitingOnUserInput,
}
```

### SandboxPolicy 类型

支持四种沙箱策略：
- `DangerFullAccess`: 完全访问（无限制）
- `ReadOnly { access, network_access }`: 只读模式
- `ExternalSandbox { network_access }`: 外部沙箱
- `WorkspaceWrite { writable_roots, read_only_access, network_access, ... }`: 工作区写入

## 关键代码路径与文件引用

### 定义位置
- **主定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs:2527-2542`
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/ThreadStartResponse.json`

### 相关类型定义

| 类型 | 位置 | 说明 |
|------|------|------|
| `Thread` | `v2.rs:3000+` | 线程核心结构 |
| `ThreadStatus` | `v2.rs:1429-1502` | 线程状态枚举 |
| `Turn` | `v2.rs:1504-1536` | 回合结构 |
| `SessionSource` | `v2.rs:1464-1501` | 会话来源 |
| `SandboxPolicy` | `v2.rs:1271-1381` | 沙箱策略 |
| `AskForApproval` | `v2.rs:201-265` | 审批策略 |
| `ApprovalsReviewer` | `v2.rs:267-296` | 审批审查者 |

### RPC 方法注册
- **位置**：`codex-rs/app-server-protocol/src/protocol/common.rs:214-218`
```rust
ThreadStart => "thread/start" {
    params: v2::ThreadStartParams,
    inspect_params: true,
    response: v2::ThreadStartResponse,
}
```

### Schema 生成
- **位置**：`codex-rs/app-server-protocol/src/export.rs`
- `write_json_schema::<ThreadStartResponse>()` 生成 JSON Schema
- 包含在 `export_client_response_schemas()` 中

### 测试验证
- **位置**：`codex-rs/app-server-protocol/src/export.rs:2540-2542`
```rust
assert_eq!(definitions.contains_key("ThreadStartParams"), true);
assert_eq!(definitions.contains_key("ThreadStartResponse"), true);
assert_eq!(definitions.contains_key("ThreadStartedNotification"), true);
```

## 依赖与外部交互

### 内部依赖

| 依赖 | 用途 |
|------|------|
| `Thread` | 线程核心数据结构 |
| `SandboxPolicy` | 沙箱策略类型 |
| `AskForApproval` | 审批策略类型 |
| `ApprovalsReviewer` | 审批审查者类型 |
| `ServiceTier` | 服务层级枚举 |
| `ReasoningEffort` | 推理努力程度 |

### 与 ThreadStartedNotification 的关系

`ThreadStartResponse` 和 `ThreadStartedNotification` 都包含 `Thread` 对象：
- `ThreadStartResponse`：RPC 响应，直接回复给调用者
- `ThreadStartedNotification`：服务器通知，广播给所有订阅者

```rust
// ThreadStartedNotification 定义
pub struct ThreadStartedNotification {
    pub thread: Thread,
}
```

### 协议交互流程

```
Client                                    Server
  |                                         |
  |---- thread/start (ThreadStartParams) --->|
  |                                         |
  |<--- ThreadStartResponse -----------------|
  |    { thread: Thread, ... }              |
  |                                         |
  |<--- notification:thread/started --------|
  |    { thread: Thread }                   |
```

## 风险、边界与改进建议

### 已知风险

1. **配置漂移**
   - 响应中的配置可能与请求不同（服务器端配置层覆盖）
   - 客户端需要正确处理配置决议结果

2. **实验性字段稳定性**
   - `approval_policy` 标记为实验性，未来可能变更
   - 细粒度审批策略的序列化格式可能调整

3. **路径序列化**
   - `cwd` 使用 `PathBuf`，在 Windows/Unix 间可能存在序列化差异
   - 需要确保跨平台兼容性

### 边界情况

1. **Thread.turns 为空**
   - 新创建的线程 `turns` 字段为空列表
   - 只有 `thread/resume`、`thread/rollback`、`thread/fork` 和 `thread/read` 会填充 turns

2. **ThreadStatus 初始值**
   - 新线程通常为 `Idle` 状态
   - 如果创建时出错可能为 `SystemError`

3. **ephemeral 线程**
   - `ephemeral: true` 的线程不会持久化到磁盘
   - `path` 字段为 null

### 改进建议

1. **配置差异说明**
   - 在响应中添加 `config_resolved_from` 字段，说明配置来源
   - 帮助客户端理解为何请求配置与实际配置不同

2. **错误处理增强**
   - 当前响应结构无错误字段，错误通过 JSON-RPC error 返回
   - 考虑添加 `warnings` 字段用于非致命问题提示

3. **字段扩展**
   - 添加 `created_by` 字段标识创建者
   - 添加 `estimated_tokens` 字段预估上下文窗口使用

4. **文档完善**
   - 明确 `preview` 字段的生成逻辑（通常为第一条用户消息）
   - 文档化 `git_info` 的捕获时机和失败处理

5. **测试覆盖**
   - 增加跨平台路径序列化测试
   - 增加配置层决议结果的验证测试
