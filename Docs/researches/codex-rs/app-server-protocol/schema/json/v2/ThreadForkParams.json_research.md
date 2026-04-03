# ThreadForkParams.json 研究文档

## 场景与职责

`ThreadForkParams` 是 App-Server Protocol v2 中用于从现有线程创建分支（fork）的请求参数结构。客户端通过此参数指定源线程 ID 和分支配置，创建一个新的线程副本。

线程分支允许用户从对话的某个点创建新的探索路径，而不影响原始线程。

## 功能点目的

1. **线程分支**: 从现有线程创建独立副本
2. **探索分支**: 支持从特定点探索不同的对话路径
3. **配置继承**: 允许继承或覆盖原始线程的配置

## 具体技术实现

### 数据结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "ApprovalsReviewer": {
      "description": "Configures who approval requests are routed to for review...",
      "enum": ["user", "guardian_subagent"],
      "type": "string"
    },
    "AskForApproval": {
      "oneOf": [
        { "enum": ["untrusted", "on-failure", "on-request", "never"], "type": "string" },
        { /* GranularAskForApproval */ }
      ]
    },
    "SandboxMode": {
      "enum": ["read-only", "workspace-write", "danger-full-access"],
      "type": "string"
    },
    "ServiceTier": {
      "enum": ["fast", "flex"],
      "type": "string"
    }
  },
  "description": "There are two ways to fork a thread: 1. By thread_id: load the thread from disk by thread_id and fork it into a new thread. 2. By path: load the thread from disk by path and fork it into a new thread.\n\nIf using path, the thread_id param will be ignored.\n\nPrefer using thread_id whenever possible.",
  "properties": {
    "approvalPolicy": { "anyOf": [{ "$ref": "#/definitions/AskForApproval" }, { "type": "null" }] },
    "approvalsReviewer": { "description": "Override where approval requests are routed for review on this thread and subsequent turns.", /* ... */ },
    "baseInstructions": { "type": ["string", "null"] },
    "config": { "additionalProperties": true, "type": ["object", "null"] },
    "cwd": { "type": ["string", "null"] },
    "developerInstructions": { "type": ["string", "null"] },
    "ephemeral": { "type": "boolean" },
    "model": { "description": "Configuration overrides for the forked thread, if any.", "type": ["string", "null"] },
    "modelProvider": { "type": ["string", "null"] },
    "sandbox": { "anyOf": [{ "$ref": "#/definitions/SandboxMode" }, { "type": "null" }] },
    "serviceTier": { /* ... */ },
    "threadId": { "type": "string" }
  },
  "required": ["threadId"],
  "title": "ThreadForkParams",
  "type": "object"
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `threadId` | string | 是 | 源线程 ID |
| `model` | string \| null | 否 | 覆盖模型配置 |
| `modelProvider` | string \| null | 否 | 覆盖模型提供商 |
| `approvalPolicy` | AskForApproval \| null | 否 | 覆盖审批策略 |
| `approvalsReviewer` | ApprovalsReviewer \| null | 否 | 覆盖审批审核者 |
| `sandbox` | SandboxMode \| null | 否 | 覆盖沙盒模式 |
| `serviceTier` | ServiceTier \| null | 否 | 覆盖服务层级 |
| `baseInstructions` | string \| null | 否 | 覆盖基础指令 |
| `developerInstructions` | string \| null | 否 | 覆盖开发者指令 |
| `cwd` | string \| null | 否 | 覆盖工作目录 |
| `ephemeral` | boolean | 否 | 是否创建临时线程 |
| `config` | object \| null | 否 | 额外的配置覆盖 |

### Fork 方式

根据描述，有两种方式 fork 线程：
1. **By thread_id**: 使用 `threadId` 参数加载线程并 fork
2. **By path**: 使用 `path` 参数加载线程并 fork（如果提供，`threadId` 将被忽略）

### 关联的 RPC 方法

- **方法**: `thread/fork`
- **响应**: `ThreadForkResponse`

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs
ThreadFork => "thread/fork" {
    params: v2::ThreadForkParams,
    inspect_params: true,
    response: v2::ThreadForkResponse,
}
```

## 关键代码路径与文件引用

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS, ExperimentalApi)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
#[experimental("thread/fork")]
pub struct ThreadForkParams {
    pub thread_id: String,
    pub model: Option<String>,
    pub model_provider: Option<String>,
    pub approval_policy: Option<AskForApproval>,
    pub approvals_reviewer: Option<ApprovalsReviewer>,
    pub sandbox: Option<SandboxMode>,
    pub service_tier: Option<ServiceTier>,
    pub base_instructions: Option<String>,
    pub developer_instructions: Option<String>,
    pub cwd: Option<String>,
    pub ephemeral: bool,
    pub config: Option<JsonValue>,
}
```

### 处理代码

```rust
// codex-rs/app-server/src/codex_message_processor.rs
async fn thread_fork(&self, request_id: ConnectionRequestId, params: ThreadForkParams) {
    let source_thread_id = ThreadId::from_string(&params.thread_id)?;
    
    let fork_options = ForkOptions {
        model: params.model,
        model_provider: params.model_provider,
        approval_policy: params.approval_policy.map(|p| p.to_core()),
        approvals_reviewer: params.approvals_reviewer.map(|r| r.to_core()),
        sandbox: params.sandbox.map(|s| s.to_core()),
        service_tier: params.service_tier,
        base_instructions: params.base_instructions,
        developer_instructions: params.developer_instructions,
        cwd: params.cwd.map(PathBuf::from),
        ephemeral: params.ephemeral,
        config: params.config,
    };
    
    match self.thread_manager.fork_thread(source_thread_id, fork_options).await {
        Ok(new_thread) => {
            let response = ThreadForkResponse {
                thread: new_thread.into(),
            };
            self.outgoing.send_response(request_id, response).await;
        }
        Err(e) => { /* 错误处理 */ }
    }
}
```

### 相关文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ClientRequest 枚举定义 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 请求处理实现 |
| `codex-rs/app-server/tests/suite/v2/thread_fork.rs` | Fork 测试 |
| `codex-rs/tui_app_server/src/app_server_session.rs` | TUI 应用中的使用 |

## 依赖与外部交互

### 上游依赖

1. **线程管理器**: `codex_core::ThreadManager`
2. **源线程**: 必须存在的源线程

### 下游交互

1. **新线程**: 创建新的线程副本
2. **线程列表**: 新线程出现在线程列表中

### 协议版本

- **版本**: v2
- **稳定性**: **实验性 API** (`#[experimental("thread/fork")]`)

## 风险、边界与改进建议

### 风险点

1. **实验性 API**: 可能在未来版本中变更
2. **数据一致性**: Fork 过程中源线程数据可能变化
3. **存储开销**: 每个 fork 创建完整副本，可能占用大量存储

### 边界情况

1. **源线程不存在**: Fork 不存在的线程
2. **源线程活跃**: Fork 正在执行中的线程
3. **循环 Fork**: 从已 Fork 的线程再次 Fork

### 改进建议

1. **添加 fork 点**: 建议添加 `fork_at_turn: Option<String>` 字段支持从特定回合 fork
2. **添加命名**: 建议添加 `name: Option<String>` 字段为 fork 的线程命名
3. **添加引用**: 建议添加 `parent_thread_id` 到响应中跟踪 fork 关系

### 测试覆盖

相关测试文件：`codex-rs/app-server/tests/suite/v2/thread_fork.rs`

建议测试场景：
- 正常线程 fork
- 带配置覆盖的 fork
- Fork 不存在的线程
