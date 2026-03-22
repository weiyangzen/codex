# ThreadForkResponse.json 研究文档

## 场景与职责

`ThreadForkResponse.json` 是 Codex App Server Protocol v2 API 的 JSON Schema 定义文件，定义了 `thread/fork` 方法的响应结构。该响应用于在从现有线程（或 rollout 文件）分叉创建新线程时，向客户端返回完整的线程状态、配置信息以及分叉后的新线程详情。

**主要使用场景：**
- 用户希望基于现有会话历史创建一个新的分支会话
- 从持久化的 rollout 文件恢复并创建新的工作线程
- 在 VSCode 或 CLI 客户端中实现"分支会话"功能
- 支持 ephemeral（临时）线程创建，这些线程不持久化到磁盘

## 功能点目的

### 1. 线程分叉响应 (ThreadForkResponse)

`ThreadForkResponse` 是 `thread/fork` 方法的核心响应结构，包含以下关键信息：

| 字段 | 类型 | 说明 |
|------|------|------|
| `thread` | Thread | 新创建的线程对象，包含完整的线程元数据 |
| `model` | string | 当前使用的模型标识 |
| `modelProvider` | string | 模型提供商（如 openai） |
| `serviceTier` | string? | 服务层级（fast/flex） |
| `cwd` | string | 当前工作目录 |
| `approvalPolicy` | AskForApproval | 审批策略配置 |
| `approvalsReviewer` | ApprovalsReviewer | 审批请求路由目标 |
| `sandbox` | SandboxPolicy | 沙箱安全策略配置 |
| `reasoningEffort` | string? | 推理努力程度 |

### 2. 内嵌的 Thread 结构

响应中包含的 `Thread` 对象提供了新线程的完整视图：

- **基础元数据**: `id`, `createdAt`, `updatedAt`, `cliVersion`
- **工作上下文**: `cwd`, `gitInfo`, `modelProvider`
- **用户界面**: `name`（线程标题）, `preview`（预览文本）
- **状态管理**: `status`（notLoaded/idle/systemError/active）, `ephemeral`
- **历史记录**: `turns` 数组包含分叉复制的历史回合

### 3. 嵌套类型定义

该 Schema 文件还包含大量嵌套类型定义，包括：
- `Turn`, `TurnStatus`, `TurnError` - 回合信息
- `ThreadItem` 及其各种子类型（UserMessage, AgentMessage, CommandExecution 等）
- `SandboxPolicy`, `ReadOnlyAccess` - 安全策略
- `CodexErrorInfo` - 错误信息
- `SessionSource`, `SubAgentSource` - 会话来源追踪

## 具体技术实现

### 关键流程

1. **请求处理流程** (`codex_message_processor.rs:3902`):
```rust
async fn thread_fork(&mut self, request_id: ConnectionRequestId, params: ThreadForkParams) {
    // 1. 解析源线程ID或路径
    // 2. 加载源 rollout 文件
    // 3. 构建配置覆盖（model, sandbox, approval_policy 等）
    // 4. 调用 thread_manager.fork_thread() 创建新线程
    // 5. 构造 ThreadForkResponse 返回
}
```

2. **线程创建流程**:
   - 验证源线程存在性（通过 `find_thread_path_by_id_str`）
   - 读取历史工作目录 (`read_history_cwd_from_state_db`)
   - 合并配置覆盖（CLI 参数 + 请求参数）
   - 调用 `ThreadManager::fork_thread()` 执行实际分叉
   - 发送 `ThreadStartedNotification` 通知

3. **Ephemeral 线程处理**:
   - 当 `ephemeral: true` 时，线程不写入磁盘
   - `path` 字段为 `null`
   - 不出现在 `thread/list` 结果中

### 数据结构

**Rust 结构定义** (`app-server-protocol/src/protocol/v2.rs:2690-2705`):
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

### 协议规范

- **方法名**: `thread/fork`
- **请求类型**: `ThreadForkParams`
- **响应类型**: `ThreadForkResponse`
- **实验性标记**: 包含 `#[experimental("thread/fork")]` 标记

## 关键代码路径与文件引用

### 核心实现

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:2690-2705` | ThreadForkResponse 结构定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs:2657-2688` | ThreadForkParams 结构定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs:224-228` | ClientRequest 枚举中注册 thread/fork 方法 |
| `codex-rs/app-server/src/codex_message_processor.rs:3902-4100` | thread_fork 方法实现 |

### 测试代码

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/thread_fork.rs` | 完整的功能测试套件 |
| `codex-rs/app-server/tests/suite/v2/thread_fork.rs:43-178` | 基础分叉创建测试 |
| `codex-rs/app-server/tests/suite/v2/thread_fork.rs:180-223` | 未物化线程拒绝测试 |
| `codex-rs/app-server/tests/suite/v2/thread_fork.rs:321-482` | Ephemeral 线程测试 |

### 生成的 Schema 和类型

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ThreadForkResponse.json` | JSON Schema 定义（本文件） |
| `codex-rs/app-server-protocol/schema/typescript/v2/ThreadForkResponse.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json` | 合并的 v2 schemas |

## 依赖与外部交互

### 上游依赖

1. **ThreadManager** (`codex_core::ThreadManager`):
   - `fork_thread()` 方法执行实际的分叉逻辑
   - 负责创建新线程、复制历史记录

2. **Config 系统**:
   - `derive_config_for_cwd()` - 基于工作目录派生配置
   - 合并 CLI 覆盖、请求参数覆盖

3. **State DB**:
   - `read_history_cwd_from_state_db()` - 读取历史 CWD
   - 用于修复/恢复线程元数据

4. **Cloud Requirements**:
   - 加载云端配置要求
   - 可能影响分叉后的配置

### 下游消费

1. **VSCode 扩展**: 通过 JSON-RPC 调用接收响应
2. **TUI 客户端**: `tui_app_server/src/app_server_session.rs`
3. **CLI 客户端**: 通过 `debug-client` 或 `codex-cli`

### 相关通知

- `ThreadStartedNotification` - 新线程创建后发送
- `ThreadStatusChangedNotification` - 状态变更通知（但分叉时直接发送 started，不发送 status/changed）

## 风险、边界与改进建议

### 已知风险

1. **配置加载失败**:
   - 云端 requirements 加载失败会导致分叉失败
   - 返回特定的错误数据和重试操作指引

2. **未物化线程限制**:
   - 只能分叉已持久化到磁盘的线程（有 rollout 文件）
   - 临时线程（未物化）不能直接分叉

3. **路径解析问题**:
   - 依赖 `find_thread_path_by_id_str` 查找源线程
   - 如果 SQLite 和文件系统状态不一致可能失败

### 边界情况

1. **Ephemeral 线程**:
   - 设置 `ephemeral: true` 创建临时线程
   - 无 `path`，不出现在列表中
   - 但可以通过 `turn/start` 正常交互

2. **历史记录复制**:
   - 默认复制源线程的完整 turns 历史
   - `persist_extended_history` 实验性选项控制是否保存更多事件变体

3. **并发分叉**:
   - 同一源线程可被多次分叉
   - 每次分叉创建独立的新线程

### 改进建议

1. **错误处理优化**:
   - 当前错误信息较为通用，可增加更具体的错误码
   - 建议区分 "源线程不存在" 和 "源线程未物化" 错误

2. **性能优化**:
   - 大型 rollout 文件的分叉可能较慢
   - 可考虑延迟加载历史记录

3. **功能扩展**:
   - 支持选择性复制部分历史回合
   - 支持分叉时重命名/设置标题

4. **Schema 优化**:
   - 当前 Schema 文件较大（约 52KB），包含大量嵌套定义
   - 可考虑拆分为多个独立的 schema 文件
