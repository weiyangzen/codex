# codex-rs/core 深度研究文档

## 概述

`codex-rs/core`（crate 名 `codex-core`）是 Codex 项目的核心业务逻辑库，为各种 Codex UI（如 TUI）提供底层能力。该 crate 实现了完整的 AI 代理会话管理、工具执行、沙箱隔离、认证配置等功能。

---

## 1. 场景与职责

### 1.1 核心场景

| 场景 | 描述 |
|------|------|
| **AI 会话管理** | 管理用户与 AI 模型的多轮对话，维护会话状态和上下文 |
| **工具调用执行** | 路由、执行和管理各类工具（shell、文件操作、MCP 等）|
| **安全沙箱** | 通过 Seatbelt(macOS)、Landlock/seccomp(Linux)、Restricted Token(Windows) 隔离命令执行 |
| **认证管理** | 支持 API Key 和 ChatGPT OAuth 两种认证模式，自动 token 刷新 |
| **配置管理** | 多层配置加载（系统/用户/项目/CLI），支持权限配置和特性开关 |
| **MCP 集成** | 支持 Model Context Protocol 服务器，动态发现和使用外部工具 |
| **技能系统** | 加载和注入技能（skills）到对话上下文中 |

### 1.2 主要职责

1. **会话生命周期管理** - 创建、恢复、归档会话线程
2. **模型通信** - 通过 OpenAI Responses API（HTTP SSE/WebSocket）与模型交互
3. **工具编排** - 工具发现、路由、审批、执行和重试
4. **状态持久化** - SQLite 数据库存储会话状态、历史记录
5. **实时对话** - 支持语音/文本实时对话模式
6. **审查工作流** - Guardian 审查系统用于敏感操作审批

---

## 2. 功能点目的

### 2.1 核心功能模块

```
┌─────────────────────────────────────────────────────────────────┐
│                        codex-core                               │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   Codex     │  │   Session   │  │      TurnContext        │  │
│  │  (主入口)    │  │  (会话状态)  │  │      (回合上下文)        │  │
│  └──────┬──────┘  └──────┬──────┘  └───────────┬─────────────┘  │
│         │                │                     │                │
│         ▼                ▼                     ▼                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    ModelClient                            │  │
│  │              (模型 API 通信客户端)                          │  │
│  └──────────────────────────────────────────────────────────┘  │
│         │                │                     │                │
│         ▼                ▼                     ▼                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ ToolRouter  │  │   Config    │  │      AuthManager        │  │
│  │  (工具路由)  │  │  (配置管理)  │  │      (认证管理)          │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 功能详细说明

#### 2.2.1 会话管理 (codex.rs)

**目的**：提供高层次的 Codex 系统接口，管理会话生命周期

**关键组件**：
- `Codex` - 队列对封装（提交请求/接收事件）
- `Session` - 已初始化模型代理的上下文，同时只能运行一个任务
- `TurnContext` - 单轮对话所需的完整上下文

**工作流程**：
1. 用户通过 `Codex::submit()` 提交 `Submission`
2. `submission_loop` 异步循环处理提交
3. 根据 `Op` 类型分发到不同处理器
4. 通过 `Codex::next_event()` 接收事件流

#### 2.2.2 模型客户端 (client.rs)

**目的**：管理与模型提供商（OpenAI 等）的 API 通信

**关键组件**：
- `ModelClient` - 会话级客户端，保存稳定配置
- `ModelClientSession` - 回合级流式会话，支持 WebSocket 复用
- `ModelClientState` - 会话级共享状态

**通信方式**：
1. **HTTP SSE** - 标准 Server-Sent Events 流
2. **WebSocket** - 优先使用，失败时自动降级到 HTTP
3. **粘性路由** - 通过 `x-codex-turn-state` 头部确保同一会话路由到相同后端

#### 2.2.3 工具系统 (tools/)

**目的**：统一管理和执行各类工具调用

**工具类型**：
| 工具 | 用途 |
|------|------|
| `shell` / `shell_command` | 执行 shell 命令 |
| `exec_command` | PTY 支持的统一执行工具 |
| `apply_patch` | 文件编辑（补丁格式）|
| `read_file` / `list_dir` / `grep_files` | 文件操作 |
| `spawn_agent` / `send_input` / `wait_agent` | 子代理管理 |
| `js_repl` | JavaScript REPL |
| MCP 工具 | 外部 MCP 服务器提供的工具 |

**执行流程**：
```
ToolRouter::build_tool_call() → ToolRegistry::dispatch_any() → 
ToolHandler::handle() → ToolOrchestrator::run() → 
Approval Check → Sandbox Selection → Execution → Retry Logic
```

#### 2.2.4 沙箱系统 (sandboxing/, exec.rs)

**目的**：安全隔离命令执行，防止恶意操作

**平台实现**：
| 平台 | 技术 | 实现 |
|------|------|------|
| macOS | Seatbelt | `/usr/bin/sandbox-exec` |
| Linux | Landlock + seccomp | `codex-linux-sandbox` 可执行文件 |
| Windows | Restricted Token | 进程内通过 `codex-windows-sandbox` |

**权限配置**：
- 文件系统权限：`read` / `write` / `none`
- 网络权限：代理、允许/拒绝域名列表
- 审批策略：`Never` / `OnFailure` / `OnRequest` / `Granular` / `UnlessTrusted`

#### 2.2.5 认证系统 (auth.rs)

**目的**：管理用户认证状态和 token 生命周期

**认证模式**：
1. **API Key** - OpenAI API 密钥认证
2. **ChatGPT OAuth** - ChatGPT 账号 OAuth 认证

**Token 刷新**：
- 自动检测 token 过期（8 天）
- 尝试从磁盘重新加载
- 向授权服务器请求刷新
- 持久化新 token

#### 2.2.6 配置系统 (config/)

**目的**：多层配置加载和合并

**配置层级**（从低到高优先级）：
1. Cloud（云管理要求，仅约束）
2. Admin（macOS 托管设备配置）
3. System（`/etc/codex/config.toml`）
4. User（`~/.codex/config.toml`）
5. CWD（`${PWD}/config.toml`）
6. Tree（向上查找 `.codex/config.toml`）
7. Repo（Git 仓库根目录 `.codex/config.toml`）
8. Runtime（CLI 参数 `--config`）

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 Submission 和 Op (protocol)

```rust
// 用户提交的请求
pub struct Submission {
    pub id: String,                    // 关联 ID
    pub op: Op,                        // 操作类型
    pub trace: Option<W3cTraceContext>, // 分布式追踪
}

// 操作类型枚举
pub enum Op {
    Interrupt,                         // 中断当前任务
    UserTurn { items: Vec<InputItem>, settings: Option<TurnSettings> },
    ExecApproval { call_id: String, decision: ApprovalDecision },
    PatchApproval { call_id: String, decision: ApprovalDecision },
    Compact { skip_if_splittable: bool },
    Shutdown,
    // ... 更多
}
```

#### 3.1.2 Event 和 EventMsg (protocol)

```rust
// 代理返回的事件
pub struct Event {
    pub id: String,                    // 关联的 Submission ID
    pub msg: EventMsg,                 // 事件内容
}

pub enum EventMsg {
    Error { message: String },
    TurnStarted { turn_id: String },
    TurnComplete { turn_id: String },
    AgentMessage { content: String },
    AgentMessageDelta { content: String },
    ExecCommandBegin { call_id: String, command: Vec<String> },
    ExecCommandOutputDelta { call_id: String, output: String },
    ExecCommandEnd { call_id: String, exit_code: i32 },
    ExecApprovalRequest { call_id: String, command: Vec<String> },
    TokenCount { count: TokenCountInfo },
    // ... 更多
}
```

#### 3.1.3 Config 结构 (config/mod.rs)

```rust
pub struct Config {
    pub model: Option<String>,                    // 模型选择
    pub model_provider_id: String,                // 模型提供商 ID
    pub model_provider: ModelProviderInfo,        // 提供商信息
    pub permissions: Permissions,                 // 权限配置
    pub features: ManagedFeatures,                // 特性开关
    pub mcp_servers: Constrained<HashMap<String, McpServerConfig>>, // MCP 配置
    pub agent_roles: BTreeMap<String, AgentRoleConfig>, // 代理角色
    pub memories: MemoriesConfig,                 // 记忆配置
    pub codex_home: PathBuf,                      // Codex 主目录
    pub cwd: PathBuf,                             // 工作目录
    // ... 更多字段
}
```

#### 3.1.4 ToolCall 和 ToolPayload (tools/router.rs)

```rust
pub struct ToolCall {
    pub tool_name: String,
    pub tool_namespace: Option<String>,
    pub call_id: String,
    pub payload: ToolPayload,
}

pub enum ToolPayload {
    Function { arguments: String },
    ToolSearch { arguments: SearchToolCallParams },
    Custom { input: String },
    LocalShell { params: ShellToolCallParams },
    Mcp { server: String, tool: String, raw_arguments: String },
}
```

### 3.2 关键流程

#### 3.2.1 主事件循环 (codex.rs:4173-4384)

```rust
async fn submission_loop(sess: Arc<Session>, config: Arc<Config>, rx_sub: Receiver<Submission>) {
    while let Ok(sub) = rx_sub.recv().await {
        let should_exit = async {
            match sub.op.clone() {
                Op::Interrupt => { handlers::interrupt(&sess).await; false }
                Op::UserInput { .. } | Op::UserTurn { .. } => {
                    handlers::user_input_or_turn(&sess, sub.id.clone(), sub.op).await;
                    false
                }
                Op::ExecApproval { .. } => { handlers::exec_approval(&sess, ...).await; false }
                Op::Shutdown => handlers::shutdown(&sess, sub.id.clone()).await,
                // ... 更多处理器
            }
        }.await;
        if should_exit { break; }
    }
}
```

#### 3.2.2 模型流式响应处理 (client.rs:1289-1337)

```rust
pub async fn stream(
    &mut self,
    prompt: &Prompt,
    model_info: &ModelInfo,
    // ... 其他参数
) -> Result<ResponseStream> {
    match wire_api {
        WireApi::Responses => {
            // 优先尝试 WebSocket
            if self.client.responses_websocket_enabled() {
                match self.stream_responses_websocket(...).await? {
                    WebsocketStreamOutcome::Stream(stream) => return Ok(stream),
                    WebsocketStreamOutcome::FallbackToHttp => {
                        self.try_switch_fallback_transport(...);
                    }
                }
            }
            // 降级到 HTTP SSE
            self.stream_responses_api(...).await
        }
    }
}
```

#### 3.2.3 工具执行流程 (tools/orchestrator.rs)

```
1. 审批检查 (Approvable::start_approval_async)
   └─> 如果需要审批，发送 ExecApprovalRequest 事件等待用户响应

2. 沙箱选择 (SandboxManager::select_initial)
   └─> 根据权限配置选择初始沙箱类型

3. 首次执行 (ToolRuntime::run)
   └─> 使用选定沙箱执行命令

4. 重试逻辑（如果沙箱拒绝且允许升级）
   └─> 请求无沙箱审批
   └─> 使用 SandboxType::None 重试

5. 网络审批（如果需要）
   └─> 检查网络策略
   └─> 请求网络访问审批
```

#### 3.2.4 配置加载流程 (config/mod.rs)

```rust
// ConfigBuilder 构建流程
pub async fn build(self) -> Result<Config> {
    // 1. 确定 codex_home
    let codex_home = self.codex_home.unwrap_or_else(default_codex_home);
    
    // 2. 加载配置层栈
    let layer_stack = ConfigLayerStack::load(...).await?;
    
    // 3. 合并配置层
    let mut toml = layer_stack.merge();
    
    // 4. 应用 CLI 覆盖
    if let Some(overrides) = self.cli_overrides {
        apply_cli_overrides(&mut toml, overrides)?;
    }
    
    // 5. 应用 harness 覆盖（测试用）
    if let Some(overrides) = self.harness_overrides {
        apply_harness_overrides(&mut toml, overrides)?;
    }
    
    // 6. 构建最终 Config
    Config::from_toml(toml, ...).await
}
```

### 3.3 协议与接口

#### 3.3.1 OpenAI Responses API

**请求格式**：
```json
{
  "model": "gpt-5",
  "input": [...],
  "tools": [...],
  "reasoning": { "effort": "high" },
  "previous_response_id": "resp_xxx"
}
```

**响应流事件**：
- `response.created` - 响应创建
- `output_item.added` - 输出项添加
- `content_part.added` - 内容部分添加
- `content_part.done` - 内容部分完成
- `output_item.done` - 输出项完成（包含工具调用）
- `response.completed` - 响应完成

#### 3.3.2 MCP (Model Context Protocol)

**服务器配置** (config/types.rs):
```rust
pub struct McpServerConfig {
    #[serde(flatten)]
    pub transport: McpServerTransportConfig,  // Stdio 或 StreamableHttp
    pub enabled: bool,
    pub required: bool,                       // 启动失败时是否报错
    pub enabled_tools: Option<Vec<String>>,   // 工具白名单
    pub disabled_tools: Option<Vec<String>>, // 工具黑名单
    pub scopes: Option<Vec<String>>,          // OAuth 范围
}
```

#### 3.3.3 工具输出格式

**结构化格式** (JSON):
```json
{
  "output": "命令输出内容...",
  "metadata": {
    "exit_code": 0,
    "duration_seconds": 1.5
  }
}
```

**自由格式** (文本):
```
Exit code: 0
Wall time: 1.5 seconds
Total output lines: 100
Output:
[截断后的内容]
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心模块文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `src/codex.rs` | ~284KB | 核心业务逻辑、会话管理、事件循环 |
| `src/client.rs` | ~70KB | 模型 API 客户端、流式处理 |
| `src/auth.rs` | ~51KB | 认证管理、token 刷新 |
| `src/exec.rs` | ~32KB | 命令执行、沙箱调用 |
| `src/config/mod.rs` | ~32KB | 配置加载、合并、验证 |
| `src/features.rs` | ~29KB | 特性开关管理 |

### 4.2 工具系统文件

| 文件 | 职责 |
|------|------|
| `src/tools/mod.rs` | 工具模块入口、输出格式化 |
| `src/tools/router.rs` | 工具路由、ToolCall 构建 |
| `src/tools/registry.rs` | 工具注册表、处理器分发 |
| `src/tools/spec.rs` | 工具规范定义 |
| `src/tools/orchestrator.rs` | 工具编排、审批、重试 |
| `src/tools/handlers/` | 各工具处理器实现 |

### 4.3 沙箱系统文件

| 文件 | 职责 |
|------|------|
| `src/sandboxing/mod.rs` | 沙箱管理器、权限合并 |
| `src/seatbelt.rs` | macOS Seatbelt 实现 |
| `src/landlock.rs` | Linux Landlock 实现 |
| `src/windows_sandbox.rs` | Windows 沙箱实现 |
| `src/exec_policy.rs` | 执行策略检查 |

### 4.4 配置系统文件

| 文件 | 职责 |
|------|------|
| `src/config/mod.rs` | Config 结构、加载逻辑 |
| `src/config/types.rs` | 配置类型定义 |
| `src/config/permissions.rs` | 权限配置 |
| `src/config_loader/mod.rs` | 配置层加载 |

### 4.5 关键代码路径

**会话启动路径**：
```
Codex::spawn() → Config::load_with_cli_overrides() → AuthManager::new() → 
ModelClient::new() → submission_loop() 启动
```

**用户输入处理路径**：
```
Codex::submit(Op::UserTurn) → submission_loop → handlers::user_input_or_turn() → 
Session::new_turn_with_sub_id() → spawn_task() → RegularTask::run()
```

**模型调用路径**：
```
RegularTask::run() → ModelClientSession::stream() → 
stream_responses_websocket() / stream_responses_api() → 
map_response_stream() → 返回 ResponseStream
```

**工具调用路径**：
```
ResponseStream 解析出 FunctionCall → ToolRouter::build_tool_call() → 
ToolRegistry::dispatch_any() → ToolHandler::handle() → 
ToolOrchestrator::run() → exec::process_exec_tool_call()
```

**沙箱执行路径**：
```
process_exec_tool_call() → build_exec_request() → 
SandboxManager::transform() → sandboxing::execute_env() → 
execute_exec_request() → exec() → 平台特定实现
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖（Workspace Crates）

| Crate | 用途 |
|-------|------|
| `codex-api` | OpenAI API 客户端 |
| `codex-protocol` | 协议类型定义（Submission, Op, Event 等）|
| `codex-auth` | 认证类型和存储 |
| `codex-config` | 配置类型定义 |
| `codex-sandbox` | 沙箱类型定义 |
| `codex-state` | SQLite 状态管理 |
| `codex-rmcp-client` | MCP 客户端 |
| `codex-skills` | 技能系统 |
| `codex-apply-patch` | 补丁应用 |
| `codex-shell-command` | Shell 命令解析 |

### 5.2 外部依赖（第三方 Crate）

| Crate | 用途 |
|-------|------|
| `tokio` | 异步运行时 |
| `reqwest` | HTTP 客户端 |
| `serde`/`serde_json` | 序列化/反序列化 |
| `futures` | 异步工具 |
| `tracing` | 日志和遥测 |
| `async-channel` | 异步通道 |
| `tokio-tungstenite` | WebSocket 客户端 |
| `landlock` (Linux) | 文件系统沙箱 |
| `seccompiler` (Linux) | Seccomp 过滤器 |
| `keyring` | 系统密钥环访问 |

### 5.3 外部系统交互

| 系统 | 交互方式 | 用途 |
|------|----------|------|
| OpenAI API | HTTP/WebSocket | 模型推理 |
| MCP 服务器 | Stdio/HTTP | 外部工具 |
| SQLite | 本地文件 | 状态持久化 |
| 系统密钥环 | OS API | 凭证存储 |
| Seatbelt | 子进程 | macOS 沙箱 |
| Landlock/seccomp | 系统调用 | Linux 沙箱 |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 安全风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 沙箱逃逸 | 恶意命令可能突破沙箱限制 | 多层沙箱（Seatbelt/Landlock/seccomp）、审批流程 |
| Token 泄露 | API Key 或 OAuth token 被窃取 | 密钥环存储、定期刷新、最小权限 |
| 命令注入 | 用户输入被注入到 shell 命令 | 参数数组传递、避免 shell 解析 |
| 网络滥用 | 恶意代码访问外部网络 | 网络沙箱、域名黑白名单 |

#### 6.1.2 稳定性风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 模型 API 不可用 | OpenAI 服务中断 | 重试机制、优雅降级 |
| Token 过期 | OAuth token 过期导致认证失败 | 自动刷新、用户提示 |
| 内存泄漏 | 长会话导致内存增长 | 定期 compact、历史截断 |
| 死锁 | 并发操作导致死锁 | 锁顺序规范、超时机制 |

### 6.2 边界情况

#### 6.2.1 配置边界

- **配置层冲突**：高层配置覆盖低层，但 `Constrained` 类型有特殊合并逻辑
- **无效配置**：部分无效配置会导致启动警告而非失败
- **权限降级**：某些权限组合可能无法同时满足，系统会选择最严格的

#### 6.2.2 执行边界

- **输出截断**：单流 8MB、聚合 1/3-2/3 分配、token 限制
- **执行超时**：可配置超时，超时后强制终止
- **沙箱拒绝**：首次沙箱拒绝后可申请无沙箱执行（需审批）

#### 6.2.3 模型交互边界

- **上下文窗口**：超出后自动 compact 或拒绝
- **工具调用循环**：防止无限工具调用循环
- **流中断**：网络中断后支持恢复或重试

### 6.3 改进建议

#### 6.3.1 架构改进

1. **模块化拆分**
   - `codex.rs` 284KB 过大，建议按功能拆分为多个子模块
   - 将 handlers、task 管理、状态管理分离到独立文件

2. **配置系统简化**
   - 当前配置层级复杂（8 层），可考虑简化
   - 提供更清晰的配置覆盖规则文档

3. **错误处理增强**
   - 统一错误类型，减少 `anyhow` 的动态错误
   - 提供更多可恢复错误的上下文

#### 6.3.2 性能优化

1. **WebSocket 连接池**
   - 当前每回合创建新 WebSocket 会话
   - 可考虑跨回合复用连接

2. **配置缓存**
   - 配置加载涉及多次文件 IO
   - 可考虑文件监视 + 缓存机制

3. **工具执行并行化**
   - 支持并行执行独立工具调用
   - 减少模型等待时间

#### 6.3.3 可观测性

1. **指标暴露**
   - 添加更多 Prometheus 指标
   - 工具调用延迟、沙箱拒绝率、token 使用量

2. **分布式追踪**
   - 完善 W3C Trace Context 传播
   - 跨 API 边界的追踪关联

3. **调试工具**
   - 提供配置验证 CLI 工具
   - 沙箱策略预览功能

#### 6.3.4 安全增强

1. **审计日志**
   - 记录所有工具调用和审批决策
   - 支持 SIEM 集成

2. **策略即代码**
   - 支持更复杂的权限策略定义
   - 基于 OPA/Rego 的策略引擎

3. **供应链安全**
   - MCP 服务器签名验证
   - 技能代码静态分析

---

## 7. 测试覆盖

### 7.1 单元测试

每个主要模块都有对应的 `*_tests.rs` 文件：
- `codex_tests.rs` - 核心逻辑测试
- `client_tests.rs` - 模型客户端测试
- `auth_tests.rs` - 认证测试
- `exec_tests.rs` - 执行测试
- `config_tests.rs` - 配置测试

### 7.2 集成测试

`tests/suite/` 目录包含 80+ 集成测试：
- `tools.rs` - 工具系统测试
- `exec.rs` - 执行流程测试
- `seatbelt.rs` - macOS 沙箱测试
- `client.rs` - 客户端集成测试
- `auth_refresh.rs` - Token 刷新测试
- `skills.rs` - 技能系统测试
- `rmcp_client.rs` - MCP 集成测试

### 7.3 测试工具

- `core_test_support` crate - 测试支持库
- `wiremock` - HTTP mock
- `insta` - 快照测试
- `tempfile` - 临时文件/目录

---

## 8. 总结

`codex-rs/core` 是一个功能丰富、架构复杂的 AI 代理核心库。其主要特点：

1. **队列驱动的架构** - 通过 Submission/Event 队列解耦 UI 和核心逻辑
2. **多层安全模型** - 平台原生沙箱 + 审批流程 + 权限配置
3. **灵活的工具系统** - 内置工具 + MCP 扩展 + 技能注入
4. **健壮的配置管理** - 8 层配置叠加，支持复杂部署场景
5. **生产级可靠性** - 自动重试、降级、token 刷新、状态恢复

该 crate 是 Codex 项目的核心，理解其架构对于贡献代码或二次开发至关重要。
