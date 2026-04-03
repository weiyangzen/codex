# ThreadStartResponse Research Document

## 场景与职责 (Usage Scenarios and Responsibilities)

`ThreadStartResponse` 是 `thread/start` RPC 方法的响应类型，用于在客户端成功发起线程创建请求后，向客户端返回新创建线程的完整配置和状态信息。

**核心使用场景：**
1. **新线程初始化确认**：客户端调用 `thread/start` 后，服务器通过此响应确认线程已成功创建
2. **线程配置同步**：向客户端同步线程的运行时配置，包括模型、沙箱策略、审批策略等
3. **客户端状态建立**：为客户端提供必要的线程元数据，以便后续操作（如 `turn/start`）

**职责范围：**
- 返回创建的 `Thread` 对象（包含线程ID、状态、路径等核心元数据）
- 提供线程的运行时配置快照（模型、提供商、服务层级等）
- 传达安全和审批相关的配置（sandbox、approvalPolicy、approvalsReviewer）
- 支持实验性功能的数据传递（reasoningEffort 等）

## 功能点目的 (Purpose of the Functionality)

**主要设计目标：**

1. **线程创建确认与初始化**
   - 确认服务器已成功创建新线程
   - 提供线程的唯一标识符和持久化路径
   - 建立客户端与服务器之间的线程上下文

2. **配置透明化**
   - 向客户端暴露实际生效的模型配置（解决配置继承和默认值问题）
   - 传达安全策略（sandbox、approvalPolicy），让客户端了解操作限制
   - 提供服务层级信息（serviceTier），用于成本和质量预期管理

3. **实验性功能支持**
   - 标记为 `#[experimental("...")]` 的字段支持新功能的渐进式推出
   - `approvalPolicy` 和整个 `ThreadStartResponse` 结构都被标记为实验性

4. **多源配置整合**
   - 整合来自配置文件、环境变量、请求参数的最终生效配置
   - 支持项目级配置（`.codex/config.toml`）的自动加载和应用

## 具体技术实现 (Technical Implementation Details)

### 数据结构定义

**Rust 源码**（`codex-rs/app-server-protocol/src/protocol/v2.rs` lines 2527-2542）：

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
    /// Reviewer currently used for approval requests on this thread.
    pub approvals_reviewer: ApprovalsReviewer,
    pub sandbox: SandboxPolicy,
    pub reasoning_effort: Option<ReasoningEffort>,
}
```

**TypeScript 生成类型**（`ThreadStartResponse.ts`）：

```typescript
export type ThreadStartResponse = { 
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

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| `thread` | `Thread` | 线程核心元数据（ID、状态、时间戳、路径等） |
| `model` | `string` | 实际使用的模型标识符（如 "gpt-5.1"） |
| `modelProvider` | `string` | 模型提供商（如 "openai", "mock_provider"） |
| `serviceTier` | `ServiceTier \| null` | 服务层级（"fast" 或 "flex"），影响成本和延迟 |
| `cwd` | `string` | 线程的工作目录（当前工作目录） |
| `approvalPolicy` | `AskForApproval` | 审批策略（实验性字段） |
| `approvalsReviewer` | `ApprovalsReviewer` | 审批请求的路由目标（"user" 或 "guardian_subagent"） |
| `sandbox` | `SandboxPolicy` | 沙箱安全策略配置 |
| `reasoningEffort` | `ReasoningEffort \| null` | 推理努力程度（OpenAI reasoning 模型参数） |

### 关联类型

**AskForApproval**（审批策略）：
```typescript
type AskForApproval = "untrusted" | "on-failure" | "on-request" | 
    { "granular": { sandbox_approval: boolean, rules: boolean, skill_approval: boolean, 
                    request_permissions: boolean, mcp_elicitations: boolean } } | 
    "never";
```

**SandboxPolicy**（沙箱策略）：
- `"dangerFullAccess"` - 完全访问（危险模式）
- `"readOnly"` - 只读访问
- `"externalSandbox"` - 外部沙箱
- `"workspaceWrite"` - 工作区写入模式

**ServiceTier**（服务层级）：
- `"fast"` - 快速响应，较高成本
- `"flex"` - 灵活调度，较低成本

**ReasoningEffort**（推理努力程度）：
- `"none" | "minimal" | "low" | "medium" | "high" | "xhigh"`
- 参考：https://platform.openai.com/docs/guides/reasoning

## 关键代码路径与文件引用 (Key Code Paths and File References)

### 协议定义
- **`codex-rs/app-server-protocol/src/protocol/v2.rs`** (lines 2527-2542)
  - `ThreadStartResponse` 结构体定义
  - 标记为 `ExperimentalApi`，表示实验性 API

- **`codex-rs/app-server-protocol/src/protocol/common.rs`** (line 214-218)
  - RPC 方法注册：`ThreadStart => "thread/start"`
  - 使用 `inspect_params: true` 支持字段级实验性控制

### TypeScript 生成文件
- **`codex-rs/app-server-protocol/schema/typescript/v2/ThreadStartResponse.ts`**
- **`codex-rs/app-server-protocol/schema/json/v2/ThreadStartResponse.json`**

### 服务器实现
- **`codex-rs/app-server/src/in_process.rs`**
  - 线程创建逻辑的实现
  
- **`codex-rs/app-server/src/codex_message_processor.rs`**
  - 消息处理和响应构造

- **`codex-rs/app-server/src/message_processor/tracing_tests.rs`**
  - 相关测试实现

### 测试文件
- **`codex-rs/app-server/tests/suite/v2/thread_start.rs`**
  - 全面的 `thread/start` 功能测试
  - 包括配置继承、服务层级、临时线程等场景

### 客户端实现
- **`codex-rs/tui_app_server/src/app.rs`**
- **`codex-rs/tui_app_server/src/app/app_server_adapter.rs`**
- **`codex-rs/tui_app_server/src/app_server_session.rs`**
  - TUI 应用服务器适配器实现

## 依赖与外部交互 (Dependencies and External Interactions)

### 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `Thread` | 线程核心数据结构 |
| `AskForApproval` | 审批策略枚举 |
| `ApprovalsReviewer` | 审批审阅者配置 |
| `SandboxPolicy` | 沙箱安全策略 |
| `ServiceTier` | 服务层级枚举 |
| `ReasoningEffort` | 推理努力程度枚举 |

### 外部系统交互

1. **配置系统**
   - 读取 `~/.codex/config.toml` 用户级配置
   - 读取 `./.codex/config.toml` 项目级配置
   - 合并请求参数中的覆盖值

2. **模型提供商**
   - 验证模型可用性
   - 获取模型默认配置

3. **认证系统**
   - 验证用户认证状态
   - 加载云服务要求（cloud requirements）

4. **MCP 服务器**
   - 初始化必需的 MCP 服务器
   - 验证 MCP 服务器健康状态

### 序列化/反序列化

```rust
// serde 配置
#[serde(rename_all = "camelCase")]  // 驼峰命名转换
#[ts(export_to = "v2/")]            // TypeScript 导出路径
```

## 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 已知风险

1. **实验性 API 稳定性**
   - 整个 `ThreadStartResponse` 被标记为实验性，API 可能变更
   - `approvalPolicy` 字段也是实验性的，行为可能调整

2. **配置继承复杂性**
   - 多层级配置（默认、用户、项目、请求）合并逻辑复杂
   - 测试用例 `thread_start_respects_project_config_from_cwd` 验证了这一行为

3. **MCP 服务器依赖**
   - 如果必需的 MCP 服务器初始化失败，线程创建会失败
   - 错误信息需要清晰传达给客户端

### 边界情况

1. **临时线程（Ephemeral Threads）**
   - `ephemeral: true` 时，线程不会持久化到磁盘
   - `path` 字段将为 `null`
   - 测试用例 `thread_start_ephemeral_remains_pathless` 覆盖此场景

2. **云服务认证失败**
   - 当云认证失效时，需要返回特定的错误码和重登录指引
   - 测试用例 `thread_start_surfaces_cloud_requirements_load_errors` 覆盖

3. **路径处理**
   - 新创建的线程路径在首次用户消息前不会实际创建
   - `path.exists()` 在创建时为 `false`

### 改进建议

1. **API 稳定性**
   - 考虑将核心字段（`thread`, `model`, `cwd`）稳定化
   - 保留实验性标记仅用于真正实验性的字段

2. **错误处理增强**
   - 为配置加载失败提供更详细的错误上下文
   - 区分用户配置错误和系统错误

3. **文档完善**
   - 补充各字段的详细语义说明
   - 提供配置继承的完整文档

4. **性能优化**
   - 考虑对大型配置对象进行延迟加载
   - 缓存常用的配置组合

5. **类型安全**
   - 考虑使用更严格的类型替代 `Option<String>`
   - 为 `model` 字段考虑使用模型枚举类型
