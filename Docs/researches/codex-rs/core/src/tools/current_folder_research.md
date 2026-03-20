# 研究文档: codex-rs/core/src/tools

## 目录
- [场景与职责](#场景与职责)
- [功能点目的](#功能点目的)
- [具体技术实现](#具体技术实现)
- [关键代码路径与文件引用](#关键代码路径与文件引用)
- [依赖与外部交互](#依赖与外部交互)
- [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

`codex-rs/core/src/tools` 是 Codex 核心工具系统的实现目录，负责管理、调度和执行 AI 助手可调用的各类工具。该模块是整个 Codex 系统的"手脚"，将模型的意图转化为实际的系统操作。

### 核心职责

1. **工具注册与发现**: 维护可用工具的注册表，支持动态工具、MCP 工具、可发现工具等多种来源
2. **工具路由与调度**: 将模型输出的工具调用请求路由到对应的处理器
3. **执行编排**: 管理工具执行的生命周期，包括权限审批、沙箱选择、重试机制
4. **并行执行**: 支持工具的并行调用，同时管理并发安全
5. **网络审批**: 处理受管网络环境下的访问审批流程
6. **Code Mode**: 支持在 JavaScript 环境中嵌套调用其他工具

### 架构定位

```
┌─────────────────────────────────────────────────────────────┐
│                      Model (LLM)                            │
└──────────────────────┬──────────────────────────────────────┘
                       │ Tool Call Request
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  ToolRouter (router.rs) - 解析请求，构建 ToolCall           │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  ToolRegistry (registry.rs) - 查找并分派到对应 Handler      │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  ToolHandler (handlers/*.rs) - 具体工具实现                 │
│  ├─ ShellHandler / ShellCommandHandler                      │
│  ├─ UnifiedExecHandler                                      │
│  ├─ ApplyPatchHandler                                       │
│  ├─ ReadFileHandler / ListDirHandler / GrepFilesHandler     │
│  ├─ McpHandler / McpResourceHandler                         │
│  ├─ JsReplHandler / JsReplResetHandler                      │
│  ├─ Multi-agents (spawn, wait, send_input, etc.)            │
│  └─ ...                                                     │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  ToolOrchestrator (orchestrator.rs) - 审批+沙箱+重试        │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  ToolRuntime (runtimes/*.rs) - 实际执行层                   │
└─────────────────────────────────────────────────────────────┘
```

---

## 功能点目的

### 1. 工具注册表 (Registry)

**目的**: 集中管理所有可用工具，提供统一的查找和调用接口。

**关键特性**:
- 支持命名空间（如 MCP 工具的 `server:tool` 格式）
- 区分 Function 和 MCP 两种工具类型
- 支持并行工具调用标记
- 集成 Hook 系统（before/after tool use）

### 2. 工具路由 (Router)

**目的**: 将模型输出的各种调用格式转换为内部统一的 `ToolCall` 结构。

**支持的调用类型**:
- `FunctionCall`: 标准函数调用
- `ToolSearchCall`: 工具搜索调用
- `CustomToolCall`: 自定义工具调用
- `LocalShellCall`: 本地 Shell 调用

### 3. 执行编排 (Orchestrator)

**目的**: 为工具执行提供统一的审批、沙箱选择和重试机制。

**核心流程**:
```
1. 检查执行审批要求 (ExecApprovalRequirement)
   ├─ Skip: 直接执行
   ├─ NeedsApproval: 请求用户审批
   └─ Forbidden: 拒绝执行

2. 选择沙箱策略进行首次尝试
   ├─ 使用 SandboxManager 选择初始沙箱
   └─ 支持绕过沙箱的特殊请求

3. 如果首次尝试被沙箱拒绝且工具支持升级
   └─ 请求用户批准后，在无沙箱环境下重试
```

### 4. 并行执行 (Parallel)

**目的**: 支持多个工具的并发执行，同时确保线程安全。

**机制**:
- 使用 `RwLock` 区分并行和非并行工具
- 支持并行标记的工具使用读锁（允许多个并发）
- 非并行工具使用写锁（独占执行）
- 支持取消令牌（CancellationToken）中断执行

### 5. 网络审批 (Network Approval)

**目的**: 在受管网络环境下，对出站网络请求进行审批控制。

**两种模式**:
- **Immediate**: 同步等待审批结果
- **Deferred**: 异步审批，适用于长时间运行的工具

### 6. Code Mode

**目的**: 允许在 JavaScript 环境中嵌套调用其他工具，提供更灵活的自动化能力。

**组件**:
- `CodeModeExecuteHandler`: 执行 JavaScript 代码
- `CodeModeWaitHandler`: 等待异步操作完成
- `CodeModeService`: 管理 Node.js 进程和通信

---

## 具体技术实现

### 3.1 核心数据结构

#### ToolInvocation (context.rs)
```rust
pub struct ToolInvocation {
    pub session: Arc<Session>,           // 会话上下文
    pub turn: Arc<TurnContext>,          // 当前轮次上下文
    pub tracker: SharedTurnDiffTracker,  // 文件变更追踪
    pub call_id: String,                 // 调用唯一标识
    pub tool_name: String,               // 工具名称
    pub tool_namespace: Option<String>,  // 命名空间（MCP）
    pub payload: ToolPayload,            // 调用负载
}
```

#### ToolPayload 枚举 (context.rs)
```rust
pub enum ToolPayload {
    Function { arguments: String },                    // 标准函数调用
    ToolSearch { arguments: SearchToolCallParams },   // 工具搜索
    Custom { input: String },                          // 自定义输入（freeform）
    LocalShell { params: ShellToolCallParams },       // 本地 Shell
    Mcp { server, tool, raw_arguments },              // MCP 工具调用
}
```

#### ToolOutput Trait (context.rs)
```rust
pub trait ToolOutput: Send {
    fn log_preview(&self) -> String;                              // 日志预览
    fn success_for_logging(&self) -> bool;                        // 执行是否成功
    fn to_response_item(&self, call_id: &str, payload: &ToolPayload) -> ResponseInputItem;
    fn code_mode_result(&self, payload: &ToolPayload) -> JsonValue; // Code Mode 结果
}
```

### 3.2 工具处理器 Trait

```rust
#[async_trait]
pub trait ToolHandler: Send + Sync {
    type Output: ToolOutput + 'static;

    fn kind(&self) -> ToolKind;  // Function 或 Mcp
    
    fn matches_kind(&self, payload: &ToolPayload) -> bool;
    
    // 判断工具调用是否可能修改环境（用于权限控制）
    async fn is_mutating(&self, _invocation: &ToolInvocation) -> bool;
    
    // 执行工具调用
    async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError>;
}
```

### 3.3 沙箱与审批系统

#### ExecApprovalRequirement (sandboxing.rs)
```rust
pub(crate) enum ExecApprovalRequirement {
    Skip { bypass_sandbox: bool, proposed_execpolicy_amendment: Option<ExecPolicyAmendment> },
    NeedsApproval { reason: Option<String>, proposed_execpolicy_amendment: Option<ExecPolicyAmendment> },
    Forbidden { reason: String },
}
```

#### ToolRuntime Trait
```rust
pub(crate) trait ToolRuntime<Req, Out>: Approvable<Req> + Sandboxable {
    fn network_approval_spec(&self, _req: &Req, _ctx: &ToolCtx) -> Option<NetworkApprovalSpec>;
    
    async fn run(&mut self, req: &Req, attempt: &SandboxAttempt<'_>, ctx: &ToolCtx) 
        -> Result<Out, ToolError>;
}
```

### 3.4 关键流程详解

#### 工具调用完整流程

1. **模型输出解析** (`router.rs:build_tool_call`)
   - 解析 `ResponseItem` 转换为 `ToolCall`
   - 识别 MCP 工具名称格式 (`server__tool`)

2. **路由分发** (`router.rs:dispatch_tool_call_with_code_mode_result`)
   - 检查 Code Mode 限制（js_repl_tools_only）
   - 构建 `ToolInvocation` 上下文
   - 调用 `ToolRegistry::dispatch_any`

3. **注册表查找** (`registry.rs:dispatch_any`)
   - 根据工具名称和命名空间查找 Handler
   - 检查 payload 类型匹配
   - 判断是否为 mutating 操作

4. **执行前准备**
   - 等待 tool_call_gate（用于 mutating 操作的串行化）
   - 记录 telemetry
   - 触发 before_tool_use hooks

5. **Handler 执行**
   - 解析参数
   - 应用权限（granted session/turn permissions）
   - 调用 `ToolOrchestrator::run`

6. **编排执行** (`orchestrator.rs`)
   - 检查/请求审批
   - 选择沙箱策略
   - 首次尝试执行
   - 如被拒绝且允许升级，请求批准后重试

7. **结果处理**
   - 触发 after_tool_use hooks
   - 记录执行结果到 telemetry
   - 转换为 `ResponseInputItem` 返回给模型

#### Shell 工具执行示例

```rust
// handlers/shell.rs
async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError> {
    // 1. 解析参数
    let params: ShellToolCallParams = parse_arguments_with_base_path(&arguments, cwd.as_path())?;
    
    // 2. 转换为 ExecParams
    let exec_params = Self::to_exec_params(&params, turn.as_ref(), session.conversation_id);
    
    // 3. 应用已授予的权限
    let effective_additional_permissions = apply_granted_turn_permissions(...).await;
    
    // 4. 检查 apply_patch 拦截（shell 命令实际是 apply_patch）
    if let Some(output) = intercept_apply_patch(...).await? {
        return Ok(output);
    }
    
    // 5. 创建执行请求
    let req = ShellRequest { ... };
    
    // 6. 通过 Orchestrator 执行
    let mut orchestrator = ToolOrchestrator::new();
    let mut runtime = ShellRuntime::new();
    let out = orchestrator.run(&mut runtime, &req, &tool_ctx, &turn, approval_policy).await?;
    
    // 7. 返回结果
    Ok(FunctionToolOutput::from_text(content, Some(true)))
}
```

### 3.5 Code Mode 实现

Code Mode 允许 JavaScript 代码通过 `codex.tool()` API 调用其他工具。

**架构**:
```
┌─────────────────────────────────────────┐
│  Node.js Process (runner.cjs + bridge.js)│
│  ├─ 加载并执行用户脚本                   │
│  ├─ 拦截 codex.tool() 调用               │
│  └─ 通过 stdio 与宿主通信                │
└──────────────────┬──────────────────────┘
                   │ JSON-RPC-like protocol
                   ▼
┌─────────────────────────────────────────┐
│  CodeModeService (service.rs)           │
│  ├─ 管理 Node.js 进程生命周期            │
│  ├─ 处理工具调用请求                     │
│  └─ 维护存储值状态                       │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│  call_nested_tool (mod.rs)              │
│  ├─ 构建嵌套 ToolCall                   │
│  ├─ 通过 ToolCallRuntime 执行           │
│  └─ 返回结果给 Node.js                   │
└─────────────────────────────────────────┘
```

---

## 关键代码路径与文件引用

### 核心模块文件

| 文件 | 职责 | 关键类型/函数 |
|------|------|---------------|
| `mod.rs` | 模块入口，输出格式化 | `format_exec_output_for_model_structured`, `format_exec_output_for_model_freeform` |
| `registry.rs` | 工具注册与分派 | `ToolRegistry`, `ToolHandler`, `ToolRegistryBuilder`, `dispatch_any` |
| `router.rs` | 请求路由 | `ToolRouter`, `ToolCall`, `build_tool_call`, `dispatch_tool_call_with_code_mode_result` |
| `orchestrator.rs` | 执行编排 | `ToolOrchestrator`, `run`, `run_attempt` |
| `context.rs` | 执行上下文 | `ToolInvocation`, `ToolPayload`, `ToolOutput`, `ExecCommandToolOutput` |
| `sandboxing.rs` | 审批与沙箱 trait | `Approvable`, `Sandboxable`, `ToolRuntime`, `ApprovalStore` |
| `parallel.rs` | 并行执行 | `ToolCallRuntime`, `handle_tool_call`, `handle_tool_call_with_source` |
| `events.rs` | 事件发射 | `ToolEmitter`, `ToolEventCtx`, `emit_exec_command_begin`, `emit_patch_end` |
| `network_approval.rs` | 网络审批 | `NetworkApprovalService`, `handle_inline_policy_request`, `ActiveNetworkApproval` |
| `spec.rs` | 工具规格定义 | `ToolsConfig`, `build_specs_with_discoverable_tools`, 各种 `create_*_tool` |
| `discoverable.rs` | 可发现工具 | `DiscoverableTool`, `DiscoverableToolType`, `DiscoverableToolAction` |

### 工具处理器 (handlers/)

| 文件 | 工具 | 说明 |
|------|------|------|
| `shell.rs` | `shell`, `shell_command` | 传统 Shell 执行 |
| `unified_exec.rs` | `exec_command`, `write_stdin` | 统一执行（PTY 支持） |
| `apply_patch.rs` | `apply_patch` | 文件编辑补丁 |
| `read_file.rs` | `read_file` | 文件读取 |
| `list_dir.rs` | `list_dir` | 目录列表 |
| `grep_files.rs` | `grep_files` | 文件搜索 |
| `mcp.rs` | MCP 工具 | MCP 客户端调用 |
| `mcp_resource.rs` | MCP 资源 | MCP 资源读取 |
| `js_repl.rs` | `js_repl`, `js_repl_reset` | JavaScript REPL |
| `multi_agents.rs` | `spawn_agent`, `wait`, `send_input`, `close_agent`, `resume_agent` | 多 Agent 管理 |
| `agent_jobs.rs` | `agent_jobs` | 批量作业 |
| `artifacts.rs` | `artifacts` | 制品管理 |
| `plan.rs` | `plan` | 计划工具 |
| `tool_search.rs` | `tool_search` | 工具搜索 |
| `tool_suggest.rs` | `tool_suggest` | 工具建议 |
| `request_permissions.rs` | `request_permissions` | 权限请求 |
| `request_user_input.rs` | `request_user_input` | 用户输入请求 |
| `view_image.rs` | `view_image` | 图片查看 |
| `dynamic.rs` | 动态工具 | 动态加载工具 |

### 运行时 (runtimes/)

| 文件 | 职责 |
|------|------|
| `mod.rs` | 运行时基础，CommandSpec 构建 |
| `shell.rs` | Shell 运行时实现 |
| `apply_patch.rs` | ApplyPatch 运行时 |
| `unified_exec.rs` | 统一执行运行时 |
| `shell/unix_escalation.rs` | Unix 权限提升 |
| `shell/zsh_fork_backend.rs` | Zsh Fork 后端 |

### Code Mode (code_mode/)

| 文件 | 职责 |
|------|------|
| `mod.rs` | 模块入口，工具描述，嵌套工具调用 |
| `execute_handler.rs` | `exec` 工具处理器 |
| `wait_handler.rs` | `wait` 工具处理器 |
| `service.rs` | Node.js 进程管理 |
| `worker.rs` | 工作进程管理 |
| `process.rs` | 子进程管理 |
| `protocol.rs` | 与 Node.js 的通信协议 |

---

## 依赖与外部交互

### 内部依赖

```
tools/
├── 依赖 codex::Session, codex::TurnContext (会话管理)
├── 依赖 sandboxing::SandboxManager (沙箱管理)
├── 依赖 exec::ExecToolCallOutput (执行输出)
├── 依赖 protocol::EventMsg (事件协议)
├── 依赖 mcp_connection_manager (MCP 连接)
├── 依赖 unified_exec (统一执行)
├── 依赖 apply_patch (补丁应用)
├── 依赖 codex_hooks (Hook 系统)
└── 依赖 codex_otel (Telemetry)
```

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `async-trait` | 异步 trait 支持 |
| `serde`, `serde_json` | 序列化/反序列化 |
| `tokio` | 异步运行时 |
| `tokio-util` | 取消令牌、Either 类型 |
| `tracing` | 日志追踪 |
| `uuid` | 唯一标识生成 |
| `indexmap` | 有序哈希表 |
| `codex_protocol` | 协议定义 |
| `codex_network_proxy` | 网络代理 |
| `codex_apply_patch` | 补丁应用库 |
| `codex_hooks` | Hook 系统 |
| `codex_otel` | Telemetry |

### 与模型交互

- **输入**: `ResponseItem`（模型的工具调用请求）
- **输出**: `ResponseInputItem`（工具执行结果）

### 与沙箱系统交互

通过 `SandboxManager` 进行沙箱转换：
```rust
attempt.env_for(spec, network) -> Result<ExecRequest, SandboxTransformError>
```

### 与审批系统交互

通过 `Session::request_command_approval` 请求用户审批，支持：
- 命令行审批
- Guardian 审批（企业环境）
- 网络访问审批

---

## 风险、边界与改进建议

### 已知风险

1. **权限提升风险**
   - 沙箱拒绝后的重试机制可能绕过安全限制
   - `should_bypass_approval` 逻辑需要仔细审查
   - **缓解**: 所有无沙箱执行都需要用户明确批准

2. **并发安全问题**
   - `tool_call_gate` 用于串行化 mutating 操作
   - 并行工具执行使用读写锁，但非并行工具可能阻塞整个系统
   - **缓解**: 仔细标记工具是否支持并行执行

3. **网络审批竞态条件**
   - `NetworkApprovalService` 中的 pending approvals 需要正确处理并发
   - **缓解**: 使用 `Mutex` 和 `Notify` 进行同步

4. **Code Mode 安全风险**
   - JavaScript 代码可以调用任意工具
   - **缓解**: 通过 `js_repl_tools_only` 模式限制可用工具

### 边界情况

1. **MCP 工具名称解析**
   - 使用 `__` 作为分隔符（如 `server__tool`）
   - 可能与合法工具名冲突

2. **沙箱策略回退**
   - Windows 下 ConPTY 不支持时回退到 ShellCommand
   - 需要确保功能降级时行为一致

3. **Hook 系统失败处理**
   - `FailedContinue` vs `FailedAbort` 的决策可能影响用户体验

4. **Telemetry 截断**
   - 大输出会被截断（2KiB/64行），可能影响调试

### 改进建议

1. **代码组织**
   - `handlers/mod.rs` 已经较大（344行），可考虑进一步拆分
   - `spec.rs` 超过1000行，工具定义可拆分到单独文件

2. **错误处理**
   - 统一 `ToolError` 和 `FunctionCallError` 的转换逻辑
   - 提供更多上下文信息用于调试

3. **测试覆盖**
   - 增加集成测试覆盖沙箱拒绝和重试流程
   - 测试网络审批的竞态条件处理

4. **性能优化**
   - 考虑缓存工具规格（ToolSpec）避免重复构建
   - 优化 MCP 工具列表的获取（当前每次都要读锁）

5. **文档**
   - 增加架构图和流程图
   - 为复杂的权限计算逻辑添加更多注释

6. **可观测性**
   - 增加工具执行链路追踪
   - 提供更详细的沙箱决策日志

---

## 附录：工具类型速查

| 类别 | 工具 | 是否 Mutating | 支持并行 | 需要审批 |
|------|------|---------------|----------|----------|
| 文件操作 | `read_file` | No | Yes | No |
| 文件操作 | `list_dir` | No | Yes | No |
| 文件操作 | `grep_files` | No | Yes | No |
| 文件操作 | `apply_patch` | Yes | No | Yes |
| 执行 | `shell` | 视命令 | No | 视配置 |
| 执行 | `shell_command` | 视命令 | No | 视配置 |
| 执行 | `exec_command` | 视命令 | No | 视配置 |
| 代码 | `js_repl` | Yes | No | Yes |
| Agent | `spawn_agent` | Yes | No | Yes |
| MCP | MCP 工具 | 视工具 | 视配置 | 视配置 |
