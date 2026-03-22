# Multi-Agent Collaboration System Research

## 目录
- [场景与职责](#场景与职责)
- [功能点目的](#功能点目的)
- [具体技术实现](#具体技术实现)
- [关键代码路径与文件引用](#关键代码路径与文件引用)
- [依赖与外部交互](#依赖与外部交互)
- [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 系统定位

`multi_agents` 模块是 Codex 核心中的**多智能体协作子系统**，负责实现主 Agent 与子 Agent 之间的完整生命周期管理。该系统允许主 Agent 根据任务需要动态创建、管理、通信和销毁子 Agent，实现并行任务处理和工作负载分发。

### 1.2 核心职责

| 职责领域 | 具体描述 |
|---------|---------|
| **Agent 生命周期管理** | 创建(spawn)、恢复(resume)、关闭(close)子 Agent |
| **跨 Agent 通信** | 向子 Agent 发送输入(send_input)、等待子 Agent 完成(wait) |
| **资源管控** | 线程深度限制、并发数限制、昵称分配 |
| **配置继承** | 子 Agent 继承父 Agent 的运行时配置（模型、沙盒策略、审批策略等） |
| **事件通知** | 通过协议事件通知 UI 层 Agent 状态变化 |

### 1.3 使用场景

1. **并行代码分析**：主 Agent 创建多个 explorer 子 Agent 并行分析不同代码模块
2. **分布式任务处理**：使用 CSV 批处理(spawn_agents_on_csv)对大量数据行并行处理
3. **长时间任务分离**：将长时间运行的任务（如测试、编译）委托给专门的子 Agent
4. **角色专业化**：根据任务类型选择不同角色（explorer/worker/default）的子 Agent

---

## 功能点目的

### 2.1 五大核心工具

| 工具名称 | 功能目的 | 关键参数 |
|---------|---------|---------|
| `spawn_agent` | 创建新的子 Agent 线程 | `message`/`items`, `agent_type`, `model`, `fork_context` |
| `send_input` | 向已存在的 Agent 发送消息 | `id`, `message`/`items`, `interrupt` |
| `wait_agent` | 等待一个或多个 Agent 达到最终状态 | `ids`, `timeout_ms` |
| `close_agent` | 关闭不再需要的 Agent | `id` |
| `resume_agent` | 恢复之前关闭的 Agent | `id` |

### 2.2 批处理工具

| 工具名称 | 功能目的 | 关键参数 |
|---------|---------|---------|
| `spawn_agents_on_csv` | 基于 CSV 文件批量创建 Agent 处理任务 | `csv_path`, `instruction`, `max_concurrency` |
| `report_agent_job_result` | 子 Agent 报告任务结果 | `job_id`, `item_id`, `result` |

### 2.3 设计原则

1. **显式授权**：仅在用户明确要求时才启用子 Agent（`Only use spawn_agent if and only if the user explicitly asks for sub-agents`）
2. **并行优先**：鼓励并行创建多个独立子 Agent 而非顺序等待
3. **资源隔离**：每个子 Agent 拥有独立的线程和配置，但继承父 Agent 的安全策略
4. **深度限制**：通过 `agent_max_depth` 防止无限递归创建子 Agent

---

## 具体技术实现

### 3.1 模块结构

```
codex-rs/core/src/tools/handlers/multi_agents/
├── spawn.rs          # spawn_agent 工具实现
├── send_input.rs     # send_input 工具实现
├── wait.rs           # wait_agent 工具实现
├── close_agent.rs    # close_agent 工具实现
├── resume_agent.rs   # resume_agent 工具实现
└── (parent mod)      # multi_agents.rs 公共逻辑
```

### 3.2 关键数据结构

#### 3.2.1 超时常量

```rust
pub(crate) const MIN_WAIT_TIMEOUT_MS: i64 = 10_000;      // 最小等待 10 秒
pub(crate) const DEFAULT_WAIT_TIMEOUT_MS: i64 = 30_000;  // 默认 30 秒
pub(crate) const MAX_WAIT_TIMEOUT_MS: i64 = 3600 * 1000; // 最大 1 小时
```

#### 3.2.2 Agent 状态定义

```rust
// codex_protocol::protocol::AgentStatus
pub enum AgentStatus {
    PendingInit,           // 初始化中
    Running,               // 运行中
    Completed(Option<String>), // 完成（可能携带最后消息）
    Errored(String),       // 错误
    Interrupted,           // 被中断
    Shutdown,              // 已关闭
    NotFound,              // 未找到
}
```

#### 3.2.3 Spawn 参数

```rust
#[derive(Debug, Deserialize)]
struct SpawnAgentArgs {
    message: Option<String>,              // 纯文本消息
    items: Option<Vec<UserInput>>,        // 结构化输入项
    agent_type: Option<String>,           // 角色类型 (explorer/worker/default)
    model: Option<String>,                // 可选模型覆盖
    reasoning_effort: Option<ReasoningEffort>, // 推理努力度
    #[serde(default)]
    fork_context: bool,                   // 是否 fork 父线程历史
}
```

### 3.3 核心流程

#### 3.3.1 Agent 创建流程 (spawn.rs)

```
1. 解析参数 → SpawnAgentArgs
2. 深度检查 → exceeds_thread_spawn_depth_limit()
3. 发送 CollabAgentSpawnBeginEvent
4. 构建配置 → build_agent_spawn_config()
   ├── 继承父 Agent 的 model、provider、reasoning_effort
   ├── 应用运行时覆盖（approval_policy、sandbox_policy、cwd）
   └── 应用角色配置 → apply_role_to_config()
5. 可选：应用模型覆盖 → apply_requested_spawn_agent_model_overrides()
6. 调用 AgentControl::spawn_agent_with_options()
7. 发送 CollabAgentSpawnEndEvent
8. 返回 SpawnAgentResult { agent_id, nickname }
```

#### 3.3.2 配置构建 (multi_agents.rs)

```rust
pub(crate) fn build_agent_spawn_config(
    base_instructions: &BaseInstructions,
    turn: &TurnContext,
) -> Result<Config, FunctionCallError> {
    let mut config = build_agent_shared_config(turn)?;
    config.base_instructions = Some(base_instructions.text.clone());
    Ok(config)
}

fn build_agent_shared_config(turn: &TurnContext) -> Result<Config, FunctionCallError> {
    let base_config = turn.config.clone();
    let mut config = (*base_config).clone();
    // 继承运行时关键字段
    config.model = Some(turn.model_info.slug.clone());
    config.model_provider = turn.provider.clone();
    config.model_reasoning_effort = turn.reasoning_effort;
    config.model_reasoning_summary = Some(turn.reasoning_summary);
    config.developer_instructions = turn.developer_instructions.clone();
    config.compact_prompt = turn.compact_prompt.clone();
    apply_spawn_agent_runtime_overrides(&mut config, turn)?;
    Ok(config)
}
```

#### 3.3.3 等待流程 (wait.rs)

```rust
pub async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError> {
    // 1. 解析参数和超时
    let timeout_ms = args.timeout_ms.unwrap_or(DEFAULT_WAIT_TIMEOUT_MS);
    let timeout_ms = timeout_ms.clamp(MIN_WAIT_TIMEOUT_MS, MAX_WAIT_TIMEOUT_MS);
    
    // 2. 发送 CollabWaitingBeginEvent
    session.send_event(&turn, CollabWaitingBeginEvent { ... }).await;
    
    // 3. 订阅所有目标 Agent 的状态
    let mut status_rxs = Vec::new();
    for id in &receiver_thread_ids {
        match session.services.agent_control.subscribe_status(*id).await {
            Ok(rx) => status_rxs.push((*id, rx)),
            Err(CodexErr::ThreadNotFound(_)) => initial_final_statuses.push((*id, AgentStatus::NotFound)),
            Err(err) => return Err(collab_agent_error(*id, err)),
        }
    }
    
    // 4. 等待任一 Agent 达到最终状态
    let statuses = if !initial_final_statuses.is_empty() {
        initial_final_statuses
    } else {
        // 使用 FuturesUnordered 并发等待
        let mut futures = FuturesUnordered::new();
        for (id, rx) in status_rxs {
            futures.push(wait_for_final_status(session.clone(), id, rx));
        }
        // 带超时的等待
        let deadline = Instant::now() + Duration::from_millis(timeout_ms as u64);
        loop {
            match timeout_at(deadline, futures.next()).await {
                Ok(Some(Some(result))) => { results.push(result); break; }
                Ok(Some(None)) => continue,
                Ok(None) | Err(_) => break, // 超时或全部完成
            }
        }
        results
    };
    
    // 5. 发送 CollabWaitingEndEvent
    session.send_event(&turn, CollabWaitingEndEvent { ... }).await;
    
    Ok(WaitAgentResult { status: statuses_map, timed_out: statuses.is_empty() })
}
```

#### 3.3.4 Agent 控制层 (agent/control.rs)

```rust
#[derive(Clone, Default)]
pub(crate) struct AgentControl {
    manager: Weak<ThreadManagerState>,  // 弱引用避免循环
    state: Arc<Guards>,                  // 资源管控
}

impl AgentControl {
    pub(crate) async fn spawn_agent_with_options(
        &self,
        config: Config,
        items: Vec<UserInput>,
        session_source: Option<SessionSource>,
        options: SpawnAgentOptions,
    ) -> CodexResult<ThreadId> {
        // 1. 预留资源槽位
        let mut reservation = self.state.reserve_spawn_slot(config.agent_max_threads)?;
        
        // 2. 获取继承的 shell 快照和执行策略
        let inherited_shell_snapshot = ...;
        let inherited_exec_policy = ...;
        
        // 3. 分配昵称
        let agent_nickname = reservation.reserve_agent_nickname(&candidate_name_refs)?;
        
        // 4. 创建线程（支持 fork 或新建）
        let new_thread = if options.fork_parent_spawn_call_id.is_some() {
            state.fork_thread_with_source(...).await?
        } else {
            state.spawn_new_thread_with_source(...).await?
        };
        
        // 5. 提交初始输入
        self.send_input(new_thread.thread_id, items).await?;
        
        // 6. 启动完成监视器
        self.maybe_start_completion_watcher(new_thread.thread_id, notification_source);
        
        Ok(new_thread.thread_id)
    }
}
```

### 3.4 角色系统 (agent/role.rs)

内置三种角色：

| 角色 | 描述 | 配置 |
|-----|------|------|
| `default` | 默认 Agent | 无特殊配置 |
| `explorer` | 代码库探索专家 | 使用 explorer.toml 配置 |
| `worker` | 执行和生产工作 | 无特殊配置 |

角色配置通过 `apply_role_to_config()` 函数应用到子 Agent 配置中，支持用户自定义角色。

### 3.5 资源管控 (agent/guards.rs)

```rust
#[derive(Default)]
pub(crate) struct Guards {
    active_agents: Mutex<ActiveAgents>,
    total_count: AtomicUsize,
}

struct ActiveAgents {
    threads_set: HashSet<ThreadId>,
    thread_agent_nicknames: HashMap<ThreadId, String>,
    used_agent_nicknames: HashSet<String>,
    nickname_reset_count: usize,
}
```

管控功能：
- **线程数限制**：通过 `agent_max_threads` 限制并发 Agent 数量
- **深度限制**：通过 `agent_max_depth` 限制子 Agent 嵌套层级
- **昵称分配**：自动分配不重复的 Agent 昵称（从预定义列表中选择）

### 3.6 批处理实现 (agent_jobs.rs)

```rust
pub struct BatchJobHandler;

const DEFAULT_AGENT_JOB_CONCURRENCY: usize = 16;
const MAX_AGENT_JOB_CONCURRENCY: usize = 64;
const STATUS_POLL_INTERVAL: Duration = Duration::from_millis(250);
const PROGRESS_EMIT_INTERVAL: Duration = Duration::from_secs(1);
const DEFAULT_AGENT_JOB_ITEM_TIMEOUT: Duration = Duration::from_secs(60 * 30);
```

批处理流程：
1. 解析 CSV 文件，每行创建一个 job item
2. 维护工作队列，按 `max_concurrency` 控制并发
3. 每个 item 创建一个子 Agent 处理
4. 子 Agent 通过 `report_agent_job_result` 报告结果
5. 自动导出结果到 CSV

---

## 关键代码路径与文件引用

### 4.1 核心实现文件

| 文件路径 | 职责 | 关键函数/结构体 |
|---------|------|----------------|
| `codex-rs/core/src/tools/handlers/multi_agents.rs` | 公共逻辑和配置构建 | `build_agent_spawn_config`, `build_agent_resume_config`, `parse_collab_input` |
| `codex-rs/core/src/tools/handlers/multi_agents/spawn.rs` | spawn_agent 实现 | `SpawnAgentHandler`, `SpawnAgentArgs`, `SpawnAgentResult` |
| `codex-rs/core/src/tools/handlers/multi_agents/send_input.rs` | send_input 实现 | `SendInputHandler`, `SendInputArgs`, `SendInputResult` |
| `codex-rs/core/src/tools/handlers/multi_agents/wait.rs` | wait_agent 实现 | `WaitAgentHandler`, `WaitArgs`, `WaitAgentResult`, `wait_for_final_status` |
| `codex-rs/core/src/tools/handlers/multi_agents/close_agent.rs` | close_agent 实现 | `CloseAgentHandler`, `CloseAgentArgs`, `CloseAgentResult` |
| `codex-rs/core/src/tools/handlers/multi_agents/resume_agent.rs` | resume_agent 实现 | `ResumeAgentHandler`, `ResumeAgentArgs`, `ResumeAgentResult` |
| `codex-rs/core/src/tools/handlers/agent_jobs.rs` | 批处理实现 | `BatchJobHandler`, `spawn_agents_on_csv`, `report_agent_job_result` |

### 4.2 Agent 控制层

| 文件路径 | 职责 | 关键函数/结构体 |
|---------|------|----------------|
| `codex-rs/core/src/agent/control.rs` | Agent 控制接口 | `AgentControl`, `spawn_agent`, `send_input`, `shutdown_agent`, `subscribe_status` |
| `codex-rs/core/src/agent/guards.rs` | 资源管控 | `Guards`, `SpawnReservation`, `exceeds_thread_spawn_depth_limit` |
| `codex-rs/core/src/agent/role.rs` | 角色系统 | `apply_role_to_config`, `DEFAULT_ROLE_NAME`, `built_in` |
| `codex-rs/core/src/agent/status.rs` | 状态管理 | `is_final`, `agent_status_from_event` |

### 4.3 工具注册和协议

| 文件路径 | 职责 | 关键函数/结构体 |
|---------|------|----------------|
| `codex-rs/core/src/tools/spec.rs` | 工具规范定义 | `create_spawn_agent_tool`, `create_send_input_tool`, `create_wait_agent_tool`, `create_close_agent_tool`, `create_resume_agent_tool` |
| `codex-rs/core/src/tools/registry.rs` | 工具注册 | `ToolRegistry`, `ToolHandler` trait |
| `codex-rs/protocol/src/protocol.rs` | 协议事件定义 | `CollabAgentSpawnBeginEvent`, `CollabAgentSpawnEndEvent`, `CollabWaitingBeginEvent`, `CollabWaitingEndEvent`, etc. |

### 4.4 TUI 集成

| 文件路径 | 职责 | 关键函数/结构体 |
|---------|------|----------------|
| `codex-rs/tui/src/app/agent_navigation.rs` | Agent 导航状态 | `AgentNavigationState`, `AgentNavigationDirection` |
| `codex-rs/tui/src/multi_agents.rs` | TUI 多 Agent 支持 | `AgentPickerThreadEntry`, `format_agent_picker_item_name` |

### 4.5 测试文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/src/tools/handlers/multi_agents_tests.rs` | multi_agents 模块单元测试 |
| `codex-rs/core/src/agent/control_tests.rs` | AgentControl 测试 |
| `codex-rs/core/src/agent/guards_tests.rs` | Guards 测试 |

---

## 依赖与外部交互

### 5.1 内部依赖关系

```
multi_agents/
├── agent/control.rs      (AgentControl 接口)
├── agent/guards.rs       (资源管控)
├── agent/role.rs         (角色系统)
├── tools/context.rs      (ToolInvocation, ToolOutput)
├── tools/registry.rs     (ToolHandler trait)
├── codex.rs              (Session, TurnContext)
├── config/               (Config, AgentRoleConfig)
└── thread_manager.rs     (ThreadManagerState)
```

### 5.2 外部协议依赖

```rust
// codex_protocol 协议事件
codex_protocol::protocol::CollabAgentSpawnBeginEvent
codex_protocol::protocol::CollabAgentSpawnEndEvent
codex_protocol::protocol::CollabAgentInteractionBeginEvent
codex_protocol::protocol::CollabAgentInteractionEndEvent
codex_protocol::protocol::CollabWaitingBeginEvent
codex_protocol::protocol::CollabWaitingEndEvent
codex_protocol::protocol::CollabCloseBeginEvent
codex_protocol::protocol::CollabCloseEndEvent
codex_protocol::protocol::CollabResumeBeginEvent
codex_protocol::protocol::CollabResumeEndEvent

// 状态相关
codex_protocol::protocol::AgentStatus
codex_protocol::protocol::SessionSource
codex_protocol::protocol::SubAgentSource
codex_protocol::ThreadId
codex_protocol::user_input::UserInput
```

### 5.3 与 TUI 的交互

通过协议事件通知 UI 层：

```rust
// 发送事件到 UI
session.send_event(&turn, CollabAgentSpawnBeginEvent { ... }).await;
session.send_event(&turn, CollabAgentSpawnEndEvent { ... }).await;
```

TUI 层通过 `AgentNavigationState` 维护 Agent 列表和导航状态。

### 5.4 与 ThreadManager 的交互

```rust
// 通过 AgentControl 调用 ThreadManagerState
state.spawn_new_thread_with_source(config, self.clone(), session_source, ...).await?;
state.fork_thread_with_source(config, initial_history, self.clone(), ...).await?;
state.send_op(agent_id, Op::UserInput { items, ... }).await?;
state.get_thread(agent_id).await?;
```

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 资源泄漏风险

```rust
// 问题：如果 Agent 异常退出，Guards 中的计数可能不一致
pub(crate) fn release_spawned_thread(&self, thread_id: ThreadId) {
    let removed = { ... };
    if removed {
        self.total_count.fetch_sub(1, Ordering::AcqRel);
    }
}
```

**缓解措施**：`SpawnReservation` 实现了 `Drop` trait，确保异常时释放计数。

#### 6.1.2 死锁风险

`Guards` 使用 `Mutex<ActiveAgents>`，在持有锁时进行异步操作可能导致问题。当前实现已避免在锁内进行异步操作。

#### 6.1.3 超时处理

`wait_agent` 的最小超时为 10 秒，过短可能导致频繁轮询，过长可能延迟响应。

### 6.2 边界条件

| 边界条件 | 处理策略 |
|---------|---------|
| 深度限制超限 | 返回错误 `"Agent depth limit reached. Solve the task yourself."` |
| 线程数限制超限 | 返回 `CodexErr::AgentLimitReached` |
| 无效 Agent ID | 返回 `CodexErr::ThreadNotFound` |
| Agent 已关闭 | 返回 `CodexErr::InternalAgentDied` |
| 空消息 | 返回错误 `"Empty message can't be sent to an agent"` |
| message 和 items 同时提供 | 返回错误 `"Provide either message or items, but not both"` |

### 6.3 改进建议

#### 6.3.1 可观测性增强

```rust
// 建议：添加更详细的指标
- codex.multi_agent.spawn_latency (创建耗时)
- codex.multi_agent.wait_duration (等待耗时)
- codex.multi_agent.message_size (消息大小分布)
```

#### 6.3.2 错误处理细化

当前错误类型较为笼统，建议：
- 区分 "Agent 不存在" 和 "Agent 已关闭"
- 提供更详细的错误上下文（如创建时的配置验证错误）

#### 6.3.3 配置继承优化

当前配置继承逻辑分散在多个函数中，建议：
- 统一配置继承策略到单独模块
- 支持更细粒度的配置覆盖控制

#### 6.3.4 批处理增强

```rust
// 建议：支持更灵活的批处理模式
- 动态并发调整（基于系统负载）
- 失败重试机制
- 进度检查点（支持断点续传）
```

#### 6.3.5 测试覆盖

当前测试主要覆盖正常路径，建议增加：
- 并发场景测试（多个 Agent 同时完成）
- 资源耗尽场景测试
- 网络中断恢复测试

### 6.4 代码质量建议

1. **文档完善**：部分复杂逻辑（如 `build_agent_shared_config`）缺少详细注释
2. **错误信息国际化**：当前错误信息均为英文硬编码
3. **配置验证**：spawn 时的模型名称验证可以前置到参数解析阶段
4. **日志增强**：关键路径（如 Agent 状态转换）可以添加更多诊断日志

---

## 附录：关键代码片段

### A.1 Agent 创建完整流程

```rust
// spawn.rs 核心逻辑
async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError> {
    // 1. 解析参数
    let args: SpawnAgentArgs = parse_arguments(&arguments)?;
    
    // 2. 深度检查
    let child_depth = next_thread_spawn_depth(&session_source);
    if exceeds_thread_spawn_depth_limit(child_depth, max_depth) {
        return Err(FunctionCallError::RespondToModel(
            "Agent depth limit reached. Solve the task yourself.".to_string(),
        ));
    }
    
    // 3. 发送开始事件
    session.send_event(&turn, CollabAgentSpawnBeginEvent { ... }).await;
    
    // 4. 构建配置
    let mut config = build_agent_spawn_config(&session.get_base_instructions().await, turn.as_ref())?;
    apply_requested_spawn_agent_model_overrides(...).await?;
    apply_role_to_config(&mut config, role_name).await?;
    apply_spawn_agent_runtime_overrides(&mut config, turn.as_ref())?;
    apply_spawn_agent_overrides(&mut config, child_depth);
    
    // 5. 创建 Agent
    let result = session.services.agent_control.spawn_agent_with_options(...).await;
    
    // 6. 发送结束事件
    session.send_event(&turn, CollabAgentSpawnEndEvent { ... }).await;
    
    // 7. 返回结果
    Ok(SpawnAgentResult { agent_id: new_thread_id.to_string(), nickname })
}
```

### A.2 等待状态机

```rust
// wait.rs 状态检查
pub(crate) fn is_final(status: &AgentStatus) -> bool {
    !matches!(
        status,
        AgentStatus::PendingInit | AgentStatus::Running | AgentStatus::Interrupted
    )
}

// 异步等待循环
async fn wait_for_final_status(
    session: Arc<Session>,
    thread_id: ThreadId,
    mut status_rx: Receiver<AgentStatus>,
) -> Option<(ThreadId, AgentStatus)> {
    loop {
        if status_rx.changed().await.is_err() {
            // 接收器断开，直接查询状态
            let latest = session.services.agent_control.get_status(thread_id).await;
            return is_final(&latest).then_some((thread_id, latest));
        }
        let status = status_rx.borrow().clone();
        if is_final(&status) {
            return Some((thread_id, status));
        }
    }
}
```

---

*文档生成时间：2026-03-22*
*基于代码版本：codex-rs/main*
