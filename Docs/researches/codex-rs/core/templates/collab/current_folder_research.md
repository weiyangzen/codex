# Codex-RS Core Templates Collab 深度研究文档

## 目录
1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 目录定位
`codex-rs/core/templates/collab/` 是 Codex CLI 项目中负责**多智能体协作（Multi-Agent Collaboration）**的提示模板目录。该目录包含指导主智能体如何 spawn、管理和与 sub-agents 协作的指令模板。

### 1.2 核心职责

| 职责领域 | 说明 |
|---------|------|
| **Sub-agent 生命周期指导** | 指导主 agent 何时、如何 spawn 新 agent |
| **协作行为规范** | 定义多 agent 环境下的工作边界和通信规则 |
| **资源管理建议** | 提供关于 timeout、上下文继承、递归限制的指导 |
| **风险控制** | 防止无限递归 spawn、资源耗尽等问题 |

### 1.3 与相关目录的关系

```
codex-rs/core/templates/
├── collab/                          # 本目录：多智能体协作指导
│   └── experimental_prompt.md       # 实验性多智能体提示
├── collaboration_mode/              # 协作模式定义（Plan/Execute/Pair Programming）
│   ├── default.md
│   ├── execute.md
│   ├── pair_programming.md
│   └── plan.md
├── agents/                          # Agent 角色定义
│   └── orchestrator.md              # 编排器角色提示
├── personalities/                   # 个性风格模板
│   ├── gpt-5.2-codex_friendly.md
│   └── gpt-5.2-codex_pragmatic.md
└── memories/                        # 记忆系统模板
    └── consolidation.md             # 记忆整合提示
```

---

## 功能点目的

### 2.1 experimental_prompt.md 核心功能

该文件是**多智能体协作的顶层指导文档**，主要功能点：

#### 2.1.1 Spawn Agent 触发场景
- **大型任务分解**：具有多个明确 scope 的复杂任务
- **代码审查**：需要另一个 agent review 工作成果
- **观点碰撞**：需要 fresh context 的辩论和洞察
- **资源优化**：运行测试或配置命令可能产生大量日志，可委托给 sub-agent

#### 2.1.2 关键使用规则
| 规则 | 说明 |
|-----|------|
| 简单任务不 spawn | "For simple or straightforward tasks, you don't need to spawn a new agent" |
| 环境感知 | 必须告知 sub-agents 它们不是环境中唯一的 agent |
| 递归限制 | 必须告知 sub-agents 它们不能自己 spawn agent（防止无限递归） |
| 资源清理 | 使用完毕后必须使用 `close_agent` 关闭 sub-agent |
| Timeout 策略 | `wait_agent` 的 `timeout_ms` 参数需要合理设置 |
| 工具继承 | Sub-agents 继承与父 agent 相同的工具集 |

### 2.2 与 Collaboration Mode 的协同

`collaboration_mode/` 目录定义了不同的协作风格，而 `collab/experimental_prompt.md` 提供了具体的多智能体操作指导：

| 协作模式 | 多智能体应用 |
|---------|------------|
| **Plan Mode** | 使用 sub-agents 并行探索不同方案 |
| **Execute Mode** | 将子任务委托给 sub-agents 执行 |
| **Pair Programming** | 主 agent 与用户协作，sub-agents 处理并行任务 |

### 2.3 Agent 角色系统

`agents/orchestrator.md` 定义了主 agent 的基本行为准则，包括：
- 如何 spawn 和协调多个 sub-agents
- 并行工作策略（"Prefer multiple sub-agents to parallelize your work"）
- 用户交互时的协调规则（"If the user asks a question, answer it first, then continue coordinating sub-agents"）

---

## 具体技术实现

### 3.1 多智能体工具集（Collab Tools）

位于 `codex-rs/core/src/tools/handlers/multi_agents/`，包含 5 个核心工具：

#### 3.1.1 spawn_agent
```rust
// codex-rs/core/src/tools/handlers/multi_agents/spawn.rs
pub(crate) struct SpawnAgentArgs {
    message: Option<String>,           // 初始文本任务
    items: Option<Vec<UserInput>>,     // 结构化输入（支持 mention/skill 等）
    agent_type: Option<String>,        // 角色类型（default/explorer/worker）
    model: Option<String>,             // 可选模型覆盖
    reasoning_effort: Option<ReasoningEffort>, // 推理强度
    fork_context: bool,                // 是否 fork 父线程历史
}
```

**关键实现细节**：
- 深度限制检查：`exceeds_thread_spawn_depth_limit(child_depth, max_depth)`
- 配置继承：`build_agent_spawn_config()` 从父 turn 继承运行时配置
- 角色应用：`apply_role_to_config()` 应用角色特定的配置层
- 昵称分配：从 `agent_names.txt` 随机分配科学家/哲学家名字

#### 3.1.2 send_input
```rust
// codex-rs/core/src/tools/handlers/multi_agents/send_input.rs
pub(crate) struct SendInputArgs {
    id: String,                        // 目标 agent ID
    message: Option<String>,           // 文本消息
    items: Option<Vec<UserInput>>,     // 结构化输入
    interrupt: bool,                   // 是否中断当前任务
}
```

#### 3.1.3 wait_agent
```rust
// codex-rs/core/src/tools/handlers/multi_agents/wait.rs
pub(crate) const MIN_WAIT_TIMEOUT_MS: i64 = 10_000;      // 最小 10 秒
pub(crate) const DEFAULT_WAIT_TIMEOUT_MS: i64 = 30_000; // 默认 30 秒
pub(crate) const MAX_WAIT_TIMEOUT_MS: i64 = 3600 * 1000; // 最大 1 小时

pub(crate) struct WaitArgs {
    ids: Vec<String>,                  // 等待的 agent IDs
    timeout_ms: Option<i64>,           // 超时时间
}
```

**等待机制**：
- 使用 `FuturesUnordered` 并行等待多个 agents
- 任一 agent 完成即返回（不等待全部）
- 通过 `watch::Receiver<AgentStatus>` 订阅状态变更

#### 3.1.4 close_agent
```rust
// codex-rs/core/src/tools/handlers/multi_agents/close_agent.rs
pub(crate) struct CloseAgentArgs {
    id: String,                        // 要关闭的 agent ID
}

pub(crate) struct CloseAgentResult {
    pub(crate) previous_status: AgentStatus, // 关闭前的状态
}
```

#### 3.1.5 resume_agent
```rust
// codex-rs/core/src/tools/handlers/multi_agents/resume_agent.rs
pub(crate) struct ResumeAgentArgs {
    id: String,                        // 要恢复的 agent ID
}
```

用于从已关闭的 rollout 文件恢复 agent 状态。

### 3.2 Agent 控制平面（AgentControl）

```rust
// codex-rs/core/src/agent/control.rs
pub(crate) struct AgentControl {
    manager: Weak<ThreadManagerState>, // 弱引用避免循环
    state: Arc<Guards>,                // 限流和配额管理
}
```

**核心方法**：
| 方法 | 功能 |
|-----|------|
| `spawn_agent_with_options()` | 创建新 agent 线程 |
| `resume_agent_from_rollout()` | 从 rollout 恢复 agent |
| `send_input()` | 向 agent 发送输入 |
| `interrupt_agent()` | 中断 agent 当前任务 |
| `shutdown_agent()` | 关闭 agent |
| `subscribe_status()` | 订阅状态变更 |

### 3.3 防护机制（Guards）

```rust
// codex-rs/core/src/agent/guards.rs
pub(crate) struct Guards {
    active_agents: Mutex<ActiveAgents>,
    total_count: AtomicUsize,          // 全局计数器
}

pub(crate) struct ActiveAgents {
    threads_set: HashSet<ThreadId>,
    thread_agent_nicknames: HashMap<ThreadId, String>,
    used_agent_nicknames: HashSet<String>,
    nickname_reset_count: usize,       // 昵称池重置计数
}
```

**限流策略**：
- 最大线程数限制：`agent_max_threads` 配置
- 最大深度限制：`agent_max_depth` 配置（默认 5）
- 昵称池耗尽后自动重置并添加序号后缀（"Euclid the 2nd"）

### 3.4 Agent 角色系统（Role System）

```rust
// codex-rs/core/src/agent/role.rs
pub const DEFAULT_ROLE_NAME: &str = "default";

pub(crate) async fn apply_role_to_config(
    config: &mut Config,
    role_name: Option<&str>,
) -> Result<(), String>
```

**内置角色**：
| 角色 | 配置 | 用途 |
|-----|------|------|
| `default` | 无特殊配置 | 通用任务 |
| `explorer` | `explorer.toml`（空文件） | 代码库探索 |
| `worker` | 无 | 执行和生产工作 |
| `awaiter` | `awaiter.toml` | 长时间等待任务 |

### 3.5 协作模式预设（Collaboration Mode Presets）

```rust
// codex-rs/core/src/models_manager/collaboration_mode_presets.rs
pub(crate) fn builtin_collaboration_mode_presets(
    collaboration_modes_config: CollaborationModesConfig,
) -> Vec<CollaborationModeMask>
```

**预设模式**：
- **Plan**：包含详细的计划模式指令（`COLLABORATION_MODE_PLAN`）
- **Default**：包含动态生成的默认模式指令，支持 `request_user_input` 可用性配置

### 3.6 工具规范定义

```rust
// codex-rs/core/src/tools/spec.rs
fn create_spawn_agent_tool(config: &ToolsConfig) -> ToolSpec {
    // 包含详细的 spawn_agent 工具描述
    // 指导模型何时、如何 spawn sub-agents
}
```

工具描述中嵌入的关键指导：
- "Only use `spawn_agent` if and only if the user explicitly asks for sub-agents"
- 任务分解策略：区分阻塞任务和并行任务
- 子任务设计原则：具体、自包含、不重复工作

---

## 关键代码路径与文件引用

### 4.1 核心文件结构

```
codex-rs/core/
├── templates/
│   ├── collab/
│   │   └── experimental_prompt.md           # 多智能体协作指导
│   ├── collaboration_mode/
│   │   ├── default.md                       # 默认协作模式
│   │   ├── execute.md                       # 执行模式
│   │   ├── pair_programming.md              # 结对编程模式
│   │   └── plan.md                          # 计划模式
│   └── agents/
│       └── orchestrator.md                  # 编排器角色
├── src/
│   ├── agent/
│   │   ├── mod.rs                           # Agent 模块导出
│   │   ├── control.rs                       # AgentControl 实现
│   │   ├── control_tests.rs                 # 控制平面测试
│   │   ├── guards.rs                        # 限流防护
│   │   ├── guards_tests.rs                  # 防护测试
│   │   ├── role.rs                          # 角色系统
│   │   ├── role_tests.rs                    # 角色测试
│   │   ├── status.rs                        # 状态管理
│   │   ├── agent_names.txt                  # 昵称池（101 个名字）
│   │   └── builtins/
│   │       ├── explorer.toml                # Explorer 角色配置
│   │       └── awaiter.toml                 # Awaiter 角色配置
│   ├── tools/
│   │   ├── spec.rs                          # 工具规范定义
│   │   └── handlers/
│   │       ├── multi_agents.rs              # 多智能体工具入口
│   │       ├── multi_agents_tests.rs        # 多智能体测试
│   │       └── multi_agents/
│   │           ├── spawn.rs                 # spawn_agent 实现
│   │           ├── send_input.rs            # send_input 实现
│   │           ├── wait.rs                  # wait_agent 实现
│   │           ├── close_agent.rs           # close_agent 实现
│   │           └── resume_agent.rs          # resume_agent 实现
│   ├── models_manager/
│   │   └── collaboration_mode_presets.rs    # 协作模式预设
│   └── features.rs                          # 功能开关（Feature::Collab）
└── tests/suite/
    └── collaboration_instructions.rs        # 协作指令集成测试
```

### 4.2 关键代码路径

#### 4.2.1 Spawn Agent 完整流程
```
1. ToolHandler::handle() in spawn.rs
   └─> parse_arguments() 解析参数
   └─> exceeds_thread_spawn_depth_limit() 深度检查
   └─> build_agent_spawn_config() 构建配置
       └─> apply_spawn_agent_runtime_overrides() 应用运行时覆盖
   └─> apply_role_to_config() 应用角色配置
   └─> apply_requested_spawn_agent_model_overrides() 模型覆盖
   └─> session.services.agent_control.spawn_agent_with_options()
       └─> Guards::reserve_spawn_slot() 预留槽位
       └─> ThreadManagerState::spawn_new_thread_with_source()
       └─> SpawnReservation::commit() 提交注册
```

#### 4.2.2 Wait Agent 状态监听
```
1. ToolHandler::handle() in wait.rs
   └─> agent_control.subscribe_status() 订阅状态
   └─> wait_for_final_status() 异步等待
       └─> status_rx.changed().await 等待状态变更
   └─> is_final() 检查是否为终态
       └─> Completed | Errored | Shutdown | NotFound
```

#### 4.2.3 协作模式指令注入
```
1. collaboration_mode_presets.rs
   └─> plan_preset() / default_preset()
       └─> include_str!("../../templates/collaboration_mode/plan.md")
       └─> default_mode_instructions() 动态生成
           └─> replace KNOWN_MODE_NAMES_PLACEHOLDER
           └─> replace REQUEST_USER_INPUT_AVAILABILITY_PLACEHOLDER
           └─> replace ASKING_QUESTIONS_GUIDANCE_PLACEHOLDER
```

### 4.3 配置相关

| 配置项 | 默认值 | 说明 |
|-------|-------|------|
| `agent_max_threads` | None | 最大并发 agent 数 |
| `agent_max_depth` | 5 | Agent spawn 深度限制 |
| `features.multi_agent` | true | 多智能体功能开关 |
| `features.enable_fanout` | false | CSV 批量 agent 任务 |

---

## 依赖与外部交互

### 5.1 内部模块依赖

```
collab templates
    ↓
collaboration_mode templates (default.md, plan.md, etc.)
    ↓
agents/orchestrator.md
    ↓
multi_agents tool handlers
    ↓
AgentControl → ThreadManagerState
    ↓
Guards (quota management)
```

### 5.2 协议层交互

```rust
// codex_protocol::protocol
pub enum SubAgentSource {
    ThreadSpawn {
        parent_thread_id: ThreadId,
        depth: i32,
        agent_nickname: Option<String>,
        agent_role: Option<String>,
    },
    Other(String),
}

pub enum AgentStatus {
    PendingInit,
    Running,
    Completed(Option<String>),  // 最终消息
    Errored(String),            // 错误信息
    Interrupted,
    Shutdown,
    NotFound,
}
```

### 5.3 事件系统

多智能体相关事件（用于 UI 通知和日志）：

```rust
// CollabAgentSpawnBeginEvent / CollabAgentSpawnEndEvent
// CollabAgentInteractionBeginEvent / CollabAgentInteractionEndEvent
// CollabWaitingBeginEvent / CollabWaitingEndEvent
// CollabCloseBeginEvent / CollabCloseEndEvent
// CollabResumeBeginEvent / CollabResumeEndEvent
```

### 5.4 外部系统交互

| 系统 | 交互方式 | 用途 |
|-----|---------|------|
| **SQLite State DB** | `state_db::get_state_db()` | 恢复 agent 元数据（nickname/role） |
| **Rollout Recorder** | `RolloutRecorder::get_rollout_history()` | Fork 父线程历史 |
| **Thread Manager** | `ThreadManagerState` | 线程生命周期管理 |
| **MCP Server** | `agent_control.spawn_agent()` | Sub-agent 实际执行 |

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 无限递归风险
- **风险**：Sub-agent 可能继续 spawn 自己的 sub-agents
- **缓解**：
  - 深度限制（`agent_max_depth`，默认 5）
  - 父 agent 需明确告知 sub-agents 不能 spawn
  - 达到深度时自动禁用 `SpawnCsv` 和 `Collab` 特性

#### 6.1.2 资源耗尽风险
- **风险**：大量并发 agents 耗尽系统资源
- **缓解**：
  - `agent_max_threads` 配置限制并发数
  - `Guards` 原子计数器跟踪活跃 agents
  - 昵称池耗尽后自动重置

#### 6.1.3 状态不一致风险
- **风险**：Sub-agent 失败或超时后父 agent 不知情
- **缓解**：
  - `wait_agent` 提供超时机制
  - 完成通知自动注入父线程（`maybe_start_completion_watcher`）
  - 状态订阅机制（`subscribe_status`）

#### 6.1.4 配置继承风险
- **风险**：Sub-agent 可能继承错误的 sandbox/approval 策略
- **缓解**：
  - `apply_spawn_agent_runtime_overrides()` 确保运行时策略继承
  - 角色配置分层应用，保留父级 provider/profile

### 6.2 边界条件

| 边界 | 处理策略 |
|-----|---------|
| **空消息** | `parse_collab_input()` 拒绝空消息和空 items |
| **无效 ID** | `agent_id()` 解析失败返回 `RespondToModel` 错误 |
| **Agent 不存在** | 返回 `AgentStatus::NotFound` 或错误消息 |
| **Timeout 超限** | `clamp(MIN_WAIT_TIMEOUT_MS, MAX_WAIT_TIMEOUT_MS)` |
| **深度超限** | 返回 "Agent depth limit reached" 错误 |
| **昵称池耗尽** | 自动重置并添加序号后缀 |

### 6.3 改进建议

#### 6.3.1 功能增强
1. **动态负载均衡**
   - 当前：固定 `agent_max_threads` 限制
   - 建议：基于系统资源（CPU/内存）动态调整并发数

2. **Agent 健康检查**
   - 当前：依赖状态订阅和超时
   - 建议：增加心跳机制，检测僵尸 agents

3. **跨会话 Agent 恢复**
   - 当前：`resume_agent` 需要 rollout 文件
   - 建议：支持从 SQLite 状态直接恢复，无需文件

#### 6.3.2 可观测性
1. **Metrics 增强**
   - 当前：仅计数器 `codex.multi_agent.spawn`
   - 建议：增加 latency histogram、失败率、平均存活时间

2. **Tracing 上下文传递**
   - 当前：Sub-agents 独立 trace
   - 建议：通过 `session_source` 传递 parent trace ID

#### 6.3.3 用户体验
1. **Agent 树可视化**
   - 当前：仅通过 nickname 和 parent_thread_id 关联
   - 建议：TUI 中显示 agent 调用树

2. **批量操作**
   - 当前：`wait_agent` 支持多 IDs 但返回任一结果
   - 建议：支持 `close_all_agents()`、`broadcast_input()` 等批量操作

#### 6.3.4 代码质量
1. **错误分类**
   - 当前：多为 `RespondToModel` 统一错误
   - 建议：细化错误类型，支持程序化重试决策

2. **测试覆盖**
   - 当前：单元测试覆盖基础场景
   - 建议：增加混沌测试（随机 kill agents、网络分区）

### 6.4 模板内容建议

`experimental_prompt.md` 当前内容较为简略，建议增加：

1. **具体使用示例**：展示典型的 spawn/wait/close 序列
2. **错误处理指导**：当 sub-agent 失败时如何处理
3. **成本意识提醒**：sub-agents 消耗额外 token，需权衡收益
4. **调试技巧**：如何诊断 sub-agent 问题

---

## 附录：关键常量与默认值

| 常量 | 值 | 位置 |
|-----|---|------|
| `MIN_WAIT_TIMEOUT_MS` | 10,000 (10s) | `multi_agents/mod.rs` |
| `DEFAULT_WAIT_TIMEOUT_MS` | 30,000 (30s) | `multi_agents/mod.rs` |
| `MAX_WAIT_TIMEOUT_MS` | 3,600,000 (1h) | `multi_agents/mod.rs` |
| `DEFAULT_AGENT_MAX_DEPTH` | 5 | `config/mod.rs` |
| `FORKED_SPAWN_AGENT_OUTPUT_MESSAGE` | "You are the newly spawned agent..." | `agent/control.rs` |

---

*文档生成时间：2026-03-22*
*基于代码版本：codex-rs/main*
