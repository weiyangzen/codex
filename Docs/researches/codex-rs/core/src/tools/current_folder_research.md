# DIR codex-rs/core/src/tools 研究文档

## 目录概述

`codex-rs/core/src/tools` 是 Codex CLI 核心工具系统的实现目录，负责管理、路由和执行所有 AI 可调用的工具（Tools）。该模块是 Codex 与外部世界交互的核心桥梁，实现了从工具注册、权限审批、沙箱执行到结果返回的完整生命周期管理。

---

## 一、场景与职责

### 1.1 核心职责

| 职责领域 | 说明 |
|---------|------|
| **工具注册与管理** | 维护工具注册表（ToolRegistry），支持动态工具、MCP工具、可发现工具的统一管理 |
| **工具路由** | 将模型调用的工具请求路由到正确的处理器（Handler） |
| **权限审批** | 实现多级审批流程：自动审批、用户确认、Guardian 审批、网络策略审批 |
| **沙箱执行** | 协调沙箱管理器执行命令，支持失败后的权限升级重试 |
| **并行执行** | 支持工具的并行调用，同时保证非并行工具的顺序执行 |
| **事件发射** | 向客户端发送工具执行事件（开始、结束、失败等） |
| **Code Mode** | 实现 exec/wait 工具，支持在 JavaScript 环境中嵌套调用其他工具 |

### 1.2 使用场景

1. **AI 代码助手场景**：模型调用 `shell`、`apply_patch`、`read_file` 等工具完成编程任务
2. **多代理协作场景**：通过 `spawn_agent`、`send_input`、`wait_agent` 等工具实现子代理管理
3. **安全受限环境**：通过沙箱和审批系统在安全环境中执行不可信代码
4. **MCP 集成场景**：通过 MCP 协议连接外部工具服务器
5. **JavaScript REPL 场景**：通过 `js_repl` 工具在 Node 环境中执行代码

---

## 二、功能点目的

### 2.1 核心模块功能

#### 2.1.1 `mod.rs` - 模块入口
- 定义遥测预览限制（2KB/64行）
- 提供执行输出格式化函数（结构化/自由格式）
- 导出主要类型：`ToolRouter`

#### 2.1.2 `router.rs` - 工具路由
- **`ToolRouter`**：工具路由器的核心实现
  - 从配置构建工具规格（ToolSpec）
  - 支持 MCP 工具、动态工具、可发现工具的集成
  - 实现 `build_tool_call`：将模型响应项转换为工具调用
  - 实现 `dispatch_tool_call_with_code_mode_result`：分发工具调用并返回 Code Mode 结果
- **`ToolCall`**：表示一个工具调用的结构，包含工具名、命名空间、调用ID和载荷
- **Code Mode 过滤**：支持 `code_mode_only_enabled` 配置，过滤嵌套工具

#### 2.1.3 `registry.rs` - 工具注册表
- **`ToolRegistry`**：工具处理器的注册表
  - 存储工具名称到处理器的映射
  - 实现 `dispatch_any`：异步分发工具调用
  - 集成 OpenTelemetry 遥测和指标收集
  - 支持钩子（Hooks）系统：`after_tool_use` 钩子
- **`ToolHandler` trait**：定义工具处理器的接口
  - `kind()`：返回工具类型（Function/Mcp）
  - `matches_kind()`：检查处理器是否匹配载荷类型
  - `is_mutating()`：判断工具是否会修改环境
  - `handle()`：执行工具调用
- **`AnyToolResult`**：统一的工具结果类型，支持转换为响应项或 Code Mode 结果

#### 2.1.4 `context.rs` - 工具上下文
- **`ToolInvocation`**：工具调用的完整上下文
  - 包含 session、turn、tracker、call_id、tool_name、payload
- **`ToolPayload`**：工具调用的载荷类型
  - `Function`：标准函数调用
  - `ToolSearch`：工具搜索调用
  - `Custom`：自定义工具调用
  - `LocalShell`：本地 shell 调用
  - `Mcp`：MCP 工具调用
- **`ToolOutput` trait**：定义工具输出的接口
  - `log_preview()`：用于遥测的预览文本
  - `success_for_logging()`：用于日志记录的成功状态
  - `to_response_item()`：转换为响应项
  - `code_mode_result()`：转换为 Code Mode 结果
- **具体输出类型**：
  - `FunctionToolOutput`：函数工具输出
  - `ApplyPatchToolOutput`：补丁应用输出
  - `ExecCommandToolOutput`：统一执行命令输出
  - `AbortedToolOutput`：中止的工具输出

#### 2.1.5 `orchestrator.rs` - 执行编排器
- **`ToolOrchestrator`**：工具执行的中央协调器
  - 实现审批 → 沙箱选择 → 执行 → 重试的完整流程
  - 支持网络审批的延迟和立即两种模式
  - 处理沙箱拒绝后的权限升级重试
- **执行流程**：
  1. 检查审批要求（`ExecApprovalRequirement`）
  2. 获取用户审批（如需要）
  3. 选择初始沙箱
  4. 执行工具
  5. 如沙箱拒绝且允许升级，请求重新审批后无沙箱重试

#### 2.1.6 `sandboxing.rs` - 沙箱与审批抽象
- **`ApprovalStore`**：审批决策的缓存存储
- **`with_cached_approval`**：带缓存的审批辅助函数
- **`Approvable` trait**：定义可审批工具的接口
  - `approval_keys()`：返回审批键列表
  - `start_approval_async()`：启动异步审批
  - `exec_approval_requirement()`：返回执行审批要求
- **`Sandboxable` trait**：定义可沙箱化工具的接口
  - `sandbox_preference()`：沙箱偏好
  - `escalate_on_failure()`：失败时是否升级
- **`ToolRuntime` trait**：定义工具运行时的接口
  - `network_approval_spec()`：网络审批规格
  - `run()`：执行工具
- **`SandboxAttempt`**：沙箱尝试的上下文，包含沙箱类型、策略、网络策略等

#### 2.1.7 `network_approval.rs` - 网络审批
- **`NetworkApprovalService`**：网络访问审批服务
  - 管理待审批的主机请求
  - 支持会话级的主机允许/拒绝缓存
  - 实现内联策略请求处理
- **`HostApprovalKey`**：主机审批的键（主机+协议+端口）
- **`PendingHostApproval`**：待审批的主机请求
- **审批模式**：
  - `Immediate`：立即模式，执行前等待审批
  - `Deferred`：延迟模式，执行后处理审批结果

#### 2.1.8 `parallel.rs` - 并行执行
- **`ToolCallRuntime`**：工具调用运行时
  - 管理并行执行锁（读写锁）
  - 支持取消令牌（CancellationToken）
  - 处理工具调用超时和中止
- **并行策略**：
  - 支持并行的工具使用读锁（允许多个并发）
  - 不支持并行的工具使用写锁（顺序执行）

#### 2.1.9 `events.rs` - 工具事件
- **`ToolEmitter`**：工具事件的统一发射器
  - `Shell`：Shell 命令事件
  - `ApplyPatch`：补丁应用事件
  - `UnifiedExec`：统一执行事件
- **`ToolEventCtx`**：工具事件的上下文
- **事件阶段**：`Begin`、`Success`、`Failure`
- **事件类型**：
  - `ExecCommandBegin`/`ExecCommandEnd`：命令执行开始/结束
  - `PatchApplyBegin`/`PatchApplyEnd`：补丁应用开始/结束

#### 2.1.10 `spec.rs` - 工具规格定义
- **`ToolsConfig`**：工具配置
  - 包含 shell 类型、apply_patch 类型、Web 搜索配置等
  - 支持特性标志（Features）控制工具启用
- **`JsonSchema`**：简化的 JSON Schema 子集
  - 支持 Boolean、String、Number、Array、Object 类型
- **工具创建函数**：
  - `create_shell_tool()`：创建 shell 工具
  - `create_apply_patch_tool()`：创建补丁应用工具
  - `create_read_file_tool()`：创建文件读取工具
  - `create_list_dir_tool()`：创建目录列表工具
  - `create_grep_files_tool()`：创建文件搜索工具
  - `create_spawn_agent_tool()`：创建代理生成工具
  - `create_js_repl_tool()`：创建 JS REPL 工具
  - 等等...

#### 2.1.11 `discoverable.rs` - 可发现工具
- **`DiscoverableTool`**：可发现工具的枚举
  - `Connector`：应用连接器
  - `Plugin`：插件
- **`DiscoverableToolType`**：工具类型（Connector/Plugin）
- **`DiscoverableToolAction`**：工具动作（Install/Enable）
- **`DiscoverablePluginInfo`**：插件信息

### 2.2 Handlers 子模块

#### 2.2.1 `handlers/shell.rs`
- **`ShellHandler`**：处理 `shell` 工具调用
- **`ShellCommandHandler`**：处理 `shell_command` 工具调用
- 支持两种后端：Classic 和 ZshFork
- 实现命令拦截（如 `apply_patch` 命令的拦截）

#### 2.2.2 `handlers/apply_patch.rs`
- **`ApplyPatchHandler`**：处理 `apply_patch` 工具调用
- 支持自由格式（Freeform）和 JSON 格式
- 实现补丁验证和权限计算
- 通过 `intercept_apply_patch` 拦截 shell 命令中的补丁

#### 2.2.3 `handlers/read_file.rs`
- **`ReadFileHandler`**：处理 `read_file` 工具调用
- 支持两种模式：
  - `Slice`：简单的行范围读取
  - `Indentation`：缩进感知的代码块读取
- 实现智能缩进分析，支持上下文展开

#### 2.2.4 `handlers/list_dir.rs`
- **`ListDirHandler`**：处理 `list_dir` 工具调用
- 支持分页（offset/limit）和深度限制
- 递归收集目录条目，按名称排序

#### 2.2.5 `handlers/grep_files.rs`
- **`GrepFilesHandler`**：处理 `grep_files` 工具调用
- 使用 `ripgrep`（rg）进行文件搜索
- 支持模式匹配和文件类型过滤

#### 2.2.6 `handlers/multi_agents.rs`
- 实现多代理协作工具：
  - `spawn_agent`：生成子代理
  - `send_input`：向代理发送输入
  - `wait_agent`：等待代理完成
  - `resume_agent`：恢复已关闭的代理
  - `close_agent`：关闭代理
- 支持代理配置继承和角色覆盖

#### 2.2.7 `handlers/mcp.rs` 和 `mcp_resource.rs`
- **`McpHandler`**：处理 MCP 工具调用
- **`McpResourceHandler`**：处理 MCP 资源列表

#### 2.2.8 `handlers/js_repl.rs`
- **`JsReplHandler`**：处理 `js_repl` 工具调用
- **`JsReplResetHandler`**：处理 `js_repl_reset` 工具调用

#### 2.2.9 `handlers/unified_exec.rs`
- **`UnifiedExecHandler`**：处理 `exec_command`/`write_stdin` 工具
- 支持 PTY 分配和交互式会话

### 2.3 Runtimes 子模块

#### 2.3.1 `runtimes/shell.rs`
- **`ShellRuntime`**：Shell 工具的运行时实现
- 实现 `ToolRuntime` trait
- 支持 ZshFork 后端优化

#### 2.3.2 `runtimes/apply_patch.rs`
- **`ApplyPatchRuntime`**：补丁应用运行时
- 构建自调用命令（`codex --codex-run-as-apply-patch`）

#### 2.3.3 `runtimes/unified_exec.rs`
- 统一执行运行时

### 2.4 Code Mode 子模块

#### 2.4.1 `code_mode/mod.rs`
- 定义 Code Mode 的核心常量（`PUBLIC_TOOL_NAME = "exec"`）
- 提供工具描述生成
- 实现嵌套工具调用

#### 2.4.2 `code_mode/execute_handler.rs`
- **`CodeModeExecuteHandler`**：处理 `exec` 工具调用

#### 2.4.3 `code_mode/wait_handler.rs`
- **`CodeModeWaitHandler`**：处理 `wait` 工具调用

#### 2.4.4 `code_mode/service.rs`
- **`CodeModeService`**：管理 Code Mode 会话状态

### 2.5 JS REPL 子模块

#### 2.5.1 `js_repl/mod.rs`
- **`JsReplManager`**：JS REPL 的管理器
- 管理 Node.js 内核进程
- 处理工具调用的嵌套执行
- 实现执行状态跟踪和错误诊断

---

## 三、具体技术实现

### 3.1 工具调用流程

```
模型响应 → ToolRouter::build_tool_call → ToolCall
                ↓
ToolCallRuntime::handle_tool_call → 获取并行锁
                ↓
ToolRegistry::dispatch_any → 查找处理器
                ↓
ToolHandler::handle → 具体处理器
                ↓
ToolOrchestrator::run → 审批 + 沙箱执行
                ↓
ToolOutput → 转换为 ResponseInputItem
```

### 3.2 审批流程

```
1. 检查 ExecApprovalRequirement
   - Skip：跳过审批
   - Forbidden：拒绝执行
   - NeedsApproval：需要审批

2. 获取审批决策
   - 检查缓存（ApprovalStore）
   - 如未缓存，请求用户审批
   - 支持 Guardian 审批路由

3. 缓存审批结果（如 ApprovedForSession）
```

### 3.3 沙箱执行流程

```
1. 选择初始沙箱（SandboxManager::select_initial）
   - 根据策略和偏好选择沙箱类型

2. 首次尝试执行
   - 构建 CommandSpec
   - 转换环境（SandboxAttempt::env_for）
   - 执行（execute_env）

3. 如沙箱拒绝且允许升级
   - 请求重新审批
   - 使用无沙箱环境重试

4. 完成网络审批（如延迟模式）
```

### 3.4 关键数据结构

#### 3.4.1 工具调用
```rust
pub struct ToolCall {
    pub tool_name: String,
    pub tool_namespace: Option<String>,
    pub call_id: String,
    pub payload: ToolPayload,
}
```

#### 3.4.2 工具载荷
```rust
pub enum ToolPayload {
    Function { arguments: String },
    ToolSearch { arguments: SearchToolCallParams },
    Custom { input: String },
    LocalShell { params: ShellToolCallParams },
    Mcp { server: String, tool: String, raw_arguments: String },
}
```

#### 3.4.3 审批要求
```rust
pub enum ExecApprovalRequirement {
    Skip { bypass_sandbox: bool, proposed_execpolicy_amendment: Option<ExecPolicyAmendment> },
    NeedsApproval { reason: Option<String>, proposed_execpolicy_amendment: Option<ExecPolicyAmendment> },
    Forbidden { reason: String },
}
```

#### 3.4.4 沙箱尝试
```rust
pub struct SandboxAttempt<'a> {
    pub sandbox: crate::exec::SandboxType,
    pub policy: &'a crate::protocol::SandboxPolicy,
    pub file_system_policy: &'a FileSystemSandboxPolicy,
    pub network_policy: NetworkSandboxPolicy,
    pub enforce_managed_network: bool,
    pub(crate) manager: &'a SandboxManager,
    pub(crate) sandbox_cwd: &'a Path,
    pub codex_linux_sandbox_exe: Option<&'a std::path::PathBuf>,
    pub use_legacy_landlock: bool,
    pub windows_sandbox_level: WindowsSandboxLevel,
    pub windows_sandbox_private_desktop: bool,
}
```

### 3.5 协议与接口

#### 3.5.1 ToolHandler Trait
```rust
#[async_trait]
pub trait ToolHandler: Send + Sync {
    type Output: ToolOutput + 'static;
    fn kind(&self) -> ToolKind;
    fn matches_kind(&self, payload: &ToolPayload) -> bool;
    async fn is_mutating(&self, _invocation: &ToolInvocation) -> bool;
    async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError>;
}
```

#### 3.5.2 ToolRuntime Trait
```rust
pub trait ToolRuntime<Req, Out>: Approvable<Req> + Sandboxable {
    fn network_approval_spec(&self, _req: &Req, _ctx: &ToolCtx) -> Option<NetworkApprovalSpec>;
    async fn run(&mut self, req: &Req, attempt: &SandboxAttempt<'_>, ctx: &ToolCtx) -> Result<Out, ToolError>;
}
```

---

## 四、关键代码路径与文件引用

### 4.1 核心文件

| 文件 | 职责 | 关键类型/函数 |
|-----|------|-------------|
| `mod.rs` | 模块入口 | `format_exec_output_for_model_structured`, `TELEMETRY_PREVIEW_MAX_BYTES` |
| `router.rs` | 工具路由 | `ToolRouter`, `ToolCall`, `build_tool_call` |
| `registry.rs` | 工具注册 | `ToolRegistry`, `ToolHandler`, `dispatch_any` |
| `context.rs` | 工具上下文 | `ToolInvocation`, `ToolPayload`, `ToolOutput` |
| `orchestrator.rs` | 执行编排 | `ToolOrchestrator`, `run` |
| `sandboxing.rs` | 沙箱抽象 | `Approvable`, `Sandboxable`, `ToolRuntime` |
| `network_approval.rs` | 网络审批 | `NetworkApprovalService`, `HostApprovalKey` |
| `parallel.rs` | 并行执行 | `ToolCallRuntime`, `handle_tool_call` |
| `events.rs` | 事件发射 | `ToolEmitter`, `ToolEventCtx` |
| `spec.rs` | 工具规格 | `ToolsConfig`, `JsonSchema`, `create_*_tool` |
| `discoverable.rs` | 可发现工具 | `DiscoverableTool` |

### 4.2 Handlers 目录

| 文件 | 职责 |
|-----|------|
| `handlers/mod.rs` | 处理器模块入口，共享工具函数 |
| `handlers/shell.rs` | Shell 工具实现 |
| `handlers/apply_patch.rs` | 补丁应用工具实现 |
| `handlers/read_file.rs` | 文件读取工具实现 |
| `handlers/list_dir.rs` | 目录列表工具实现 |
| `handlers/grep_files.rs` | 文件搜索工具实现 |
| `handlers/multi_agents.rs` | 多代理协作工具实现 |
| `handlers/mcp.rs` | MCP 工具实现 |
| `handlers/js_repl.rs` | JS REPL 工具实现 |
| `handlers/unified_exec.rs` | 统一执行工具实现 |

### 4.3 Runtimes 目录

| 文件 | 职责 |
|-----|------|
| `runtimes/mod.rs` | 运行时模块入口，共享辅助函数 |
| `runtimes/shell.rs` | Shell 运行时实现 |
| `runtimes/apply_patch.rs` | 补丁应用运行时实现 |
| `runtimes/unified_exec.rs` | 统一执行运行时实现 |

### 4.4 Code Mode 目录

| 文件 | 职责 |
|-----|------|
| `code_mode/mod.rs` | Code Mode 核心定义 |
| `code_mode/execute_handler.rs` | exec 工具处理器 |
| `code_mode/wait_handler.rs` | wait 工具处理器 |
| `code_mode/service.rs` | Code Mode 服务 |
| `code_mode/protocol.rs` | 协议消息定义 |
| `code_mode/worker.rs` | 工作进程管理 |
| `code_mode/process.rs` | 子进程管理 |

### 4.5 JS REPL 目录

| 文件 | 职责 |
|-----|------|
| `js_repl/mod.rs` | JS REPL 管理器实现 |

---

## 五、依赖与外部交互

### 5.1 内部依赖

```
tools/
├── 依赖 codex_protocol: ToolSpec, ResponseItem, ResponseInputItem
├── 依赖 crate::codex: Session, TurnContext
├── 依赖 crate::sandboxing: SandboxManager, CommandSpec, SandboxPermissions
├── 依赖 crate::exec: ExecToolCallOutput, SandboxType, execute_env
├── 依赖 crate::guardian: GuardianApprovalRequest, review_approval_request
├── 依赖 crate::features: Feature
├── 依赖 crate::mcp_connection_manager: ToolInfo
├── 依赖 codex_hooks: HookEvent, HookPayload
├── 依赖 codex_otel: 遥测和指标
└── 依赖 codex_network_proxy: NetworkProxy, NetworkPolicyDecider
```

### 5.2 外部依赖

| Crate | 用途 |
|-------|------|
| `async-trait` | 异步 trait 支持 |
| `serde`/`serde_json` | 序列化/反序列化 |
| `tokio` | 异步运行时 |
| `tokio-util` | 取消令牌、Either 类型 |
| `tracing` | 日志和追踪 |
| `uuid` | UUID 生成 |
| `indexmap` | 有序哈希映射 |
| `futures` | Future 工具 |

### 5.3 外部工具调用

| 工具 | 用途 | 位置 |
|-----|------|------|
| `ripgrep` (rg) | 文件内容搜索 | `handlers/grep_files.rs` |
| `node` | JS REPL 执行 | `js_repl/mod.rs` |
| `codex` (自身) | 补丁应用 | `runtimes/apply_patch.rs` |

---

## 六、风险、边界与改进建议

### 6.1 潜在风险

#### 6.1.1 安全风险
1. **命令注入**：虽然使用参数化命令，但仍需警惕 shell 解释器中的注入风险
2. **路径遍历**：文件操作工具需要严格验证路径，防止越权访问
3. **沙箱逃逸**：Linux Landlock 和 macOS Seatbelt 沙箱可能存在绕过漏洞
4. **网络策略绕过**：延迟审批模式下，网络请求可能在审批完成前已发出

#### 6.1.2 稳定性风险
1. **死锁**：并行执行中的读写锁使用不当可能导致死锁
2. **资源泄漏**：JS REPL 和 Code Mode 的子进程可能异常退出导致资源泄漏
3. **内存溢出**：大文件读取和输出截断逻辑需要严格测试
4. **超时处理**：网络请求和命令执行的超时处理需要完善

#### 6.1.3 一致性风险
1. **审批缓存**：会话级审批缓存可能导致意外的权限提升
2. **并发修改**：多代理场景下的文件并发修改可能导致冲突
3. **状态同步**：Code Mode 和 JS REPL 的状态同步复杂，容易出错

### 6.2 边界情况

1. **超大文件**：`read_file` 和 `grep_files` 对超大文件的处理
2. **循环引用**：Code Mode 中工具调用的循环引用检测
3. **深度嵌套**：子代理的递归生成深度限制
4. **特殊字符**：文件名和命令参数中的特殊字符处理
5. **跨平台**：Windows 和 Unix 平台的行为差异

### 6.3 改进建议

#### 6.3.1 架构改进
1. **工具隔离**：考虑使用 WASM 或更严格的沙箱实现工具隔离
2. **事件溯源**：将工具执行事件持久化，支持审计和回放
3. **插件系统**：将更多工具实现为可插拔的插件
4. **缓存优化**：优化审批缓存的过期策略和内存占用

#### 6.3.2 性能优化
1. **并行优化**：优化并行执行的锁粒度，减少竞争
2. **增量更新**：`read_file` 支持增量更新，减少重复读取
3. **连接池**：MCP 工具连接池化，减少连接开销
4. **预编译**：JS REPL 的代码预编译，提高执行速度

#### 6.3.3 可观测性
1. **详细指标**：增加更多细粒度的性能指标
2. **分布式追踪**：支持跨工具的分布式追踪
3. **执行图谱**：可视化工具调用依赖关系
4. **错误分类**：更精细的错误分类和恢复建议

#### 6.3.4 用户体验
1. **审批批处理**：支持批量审批相似请求
2. **预览功能**：执行前提供命令影响的预览
3. **撤销支持**：支持工具执行的撤销操作
4. **智能提示**：基于历史数据的工具参数建议

---

## 七、测试覆盖

### 7.1 单元测试文件

| 测试文件 | 覆盖内容 |
|---------|---------|
| `router_tests.rs` | 工具路由逻辑 |
| `registry_tests.rs` | 工具注册表 |
| `context_tests.rs` | 工具上下文和输出 |
| `sandboxing_tests.rs` | 沙箱和审批逻辑 |
| `network_approval_tests.rs` | 网络审批服务 |
| `spec_tests.rs` | 工具规格定义 |
| `handlers/*_tests.rs` | 各工具处理器 |
| `runtimes/*_tests.rs` | 运行时实现 |

### 7.2 集成测试

- 工具端到端测试在 `core/tests/` 目录
- 使用 `test_sync_tool` 进行并发测试
- 使用 `insta` 进行快照测试（TUI 输出）

---

## 八、总结

`codex-rs/core/src/tools` 是 Codex CLI 的核心模块，实现了完整的工具生命周期管理。其设计亮点包括：

1. **分层架构**：清晰的 Router → Registry → Handler → Runtime 分层
2. **安全优先**：多层审批和沙箱机制保障安全
3. **灵活扩展**：支持 MCP、动态工具、可发现工具等多种扩展方式
4. **并行优化**：细粒度的并行控制，平衡性能和正确性
5. **可观测性**：完善的遥测和事件系统

该模块的复杂性主要来自于安全性和灵活性的平衡，需要在严格的沙箱限制和流畅的用户体验之间找到最佳点。
