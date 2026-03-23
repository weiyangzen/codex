# 研究文档：experimental_prompt.md

## 文件基本信息

- **目标文件**: `codex-rs/core/templates/collab/experimental_prompt.md`
- **文件类型**: Markdown 提示模板（Prompt Template）
- **所属模块**: Codex Core Multi-Agent Collaboration（多智能体协作）
- **关联目录**: `codex-rs/core/templates/collab/`

---

## 1. 场景与职责

### 1.1 核心定位

`experimental_prompt.md` 是 Codex CLI 项目中**多智能体协作（Multi-Agent Collaboration）**功能的**实验性提示模板**。该文件为主智能体（Parent Agent）提供关于如何 spawn、管理和与 sub-agents（子智能体）协作的详细指导。

### 1.2 使用场景

| 场景 | 描述 |
|------|------|
| **大规模任务分解** | 当用户请求涉及多个明确定义的范围时，主智能体可以 spawn 多个 sub-agents 并行处理 |
| **代码审查** | 主智能体可以 spawn 审查者 agent 来 review 自己或其他 agent 的工作 |
| **辩论与洞察** | 需要与另一个 agent 交互以辩论想法，获得新鲜上下文的洞察 |
| **测试执行** | 在专用 agent 中运行和修复测试，以优化主智能体的资源使用 |
| **长时间运行任务** | 将长时间运行的命令（如测试、监控）委托给专门的 awaiter agent |

### 1.3 与相关模板的关系

```
templates/
├── agents/
│   └── orchestrator.md          # 主智能体角色定义（包含 Sub-agents 章节）
├── collab/
│   └── experimental_prompt.md   # 本文件：多智能体协作实验性指导
├── collaboration_mode/
│   ├── default.md               # 默认协作模式
│   ├── plan.md                  # Plan 协作模式
│   ├── execute.md               # Execute 协作模式
│   └── pair_programming.md      # 结对编程模式
└── ...
```

- `orchestrator.md` 是主智能体的**核心角色定义**，其中第 87-106 行的 "Sub-agents" 章节引用了本文件的概念
- `experimental_prompt.md` 提供更**详细和实验性**的多智能体操作指导
- `collaboration_mode/` 目录定义不同的**协作风格**，而本文件提供**具体操作指导**

---

## 2. 功能点目的

### 2.1 功能目标

该模板旨在实现以下目标：

1. **指导智能体何时使用 sub-agents**
   - 强调对于简单或直接的任务，不需要 spawn 新 agent
   - 明确列出适合使用多智能体的场景

2. **规范 sub-agent 的生命周期管理**
   - spawn：创建新 agent
   - send_input：向现有 agent 发送消息
   - wait_agent：等待 agent 完成
   - close_agent：关闭 agent

3. **防止资源滥用和无限递归**
   - 明确告知 sub-agents 不能自己 spawn sub-agents（防止无限递归）
   - 强调合理设置 `timeout_ms` 参数

4. **协调多 agent 工作环境**
   - 提醒 sub-agents 它们不是环境中唯一的 agent
   - 强调不应影响或撤销其他 agent 的工作

### 2.2 关键指导原则

根据文件内容，核心指导原则包括：

| 原则 | 说明 |
|------|------|
| **明智使用** | 对于简单或直接的任务，不需要 spawn 新 agent |
| **环境感知** | 当 spawn 多个 agents 时，必须告知它们环境中还有其他 agents |
| **防止递归** | 明确告知 agent 它不能自己 spawn sub-agents |
| **资源管理** | 使用 `close_agent` 关闭不再需要的 sub-agents |
| **超时设置** | 谨慎选择 `wait_agent` 的 `timeout_ms` 参数 |

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 Agent 状态（AgentStatus）

```rust
// codex-rs/core/src/agent/status.rs
codex_protocol::protocol::AgentStatus
```

状态包括：
- `PendingInit` - 等待初始化
- `Running` - 运行中
- `Completed(Option<String>)` - 完成（可能包含最后消息）
- `Interrupted` - 被中断
- `Errored(String)` - 出错
- `Shutdown` - 已关闭
- `NotFound` - 未找到

#### 3.1.2 SubAgentSource

```rust
// codex_protocol::protocol::SubAgentSource::ThreadSpawn
codex_protocol::protocol::SubAgentSource::ThreadSpawn {
    parent_thread_id: ThreadId,
    depth: i32,
    agent_nickname: Option<String>,
    agent_role: Option<String>,
}
```

#### 3.1.3 SpawnAgentOptions

```rust
// codex-rs/core/src/agent/control.rs
pub(crate) struct SpawnAgentOptions {
    pub(crate) fork_parent_spawn_call_id: Option<String>,
}
```

### 3.2 核心工具（Tools）

多智能体协作通过以下工具实现，定义于 `codex-rs/core/src/tools/spec.rs`：

| 工具名称 | 功能 | 处理器位置 |
|----------|------|------------|
| `spawn_agent` | 创建新的 sub-agent | `multi_agents/spawn.rs` |
| `send_input` | 向现有 agent 发送消息 | `multi_agents/send_input.rs` |
| `wait_agent` | 等待 agents 达到最终状态 | `multi_agents/wait.rs` |
| `close_agent` | 关闭 agent | `multi_agents/close_agent.rs` |
| `resume_agent` | 恢复之前关闭的 agent | `multi_agents/resume_agent.rs` |

### 3.3 关键流程

#### 3.3.1 Spawn Agent 流程

```
┌─────────────────┐
│  Model 调用     │
│ spawn_agent     │
└────────┬────────┘
         ▼
┌─────────────────┐
│ 解析参数         │
│ - message/items │
│ - agent_type    │
│ - model         │
│ - fork_context  │
└────────┬────────┘
         ▼
┌─────────────────┐
│ 检查深度限制     │
│ exceeds_thread_ │
│ spawn_depth_limit│
└────────┬────────┘
         ▼
┌─────────────────┐
│ 构建配置         │
│ build_agent_    │
│ spawn_config()  │
└────────┬────────┘
         ▼
┌─────────────────┐
│ 应用角色配置     │
│ apply_role_to_  │
│ config()        │
└────────┬────────┘
         ▼
┌─────────────────┐
│ AgentControl    │
│ spawn_agent_    │
│ with_options()  │
└────────┬────────┘
         ▼
┌─────────────────┐
│ 创建 Thread     │
│ 发送初始输入     │
│ 启动状态监视器   │
└─────────────────┘
```

#### 3.3.2 Wait Agent 流程

```rust
// codex-rs/core/src/tools/handlers/multi_agents/wait.rs
pub(crate) const MIN_WAIT_TIMEOUT_MS: i64 = 10_000;
pub(crate) const DEFAULT_WAIT_TIMEOUT_MS: i64 = 30_000;
pub(crate) const MAX_WAIT_TIMEOUT_MS: i64 = 3600 * 1000;
```

流程：
1. 验证 `ids` 非空
2. 解析 agent IDs
3. 获取 timeout_ms（默认 30s，范围 10s-1h）
4. 订阅所有 agent 的状态更新
5. 使用 `FuturesUnordered` 等待任一 agent 达到最终状态
6. 返回最终状态或超时

#### 3.3.3 状态监视与通知

```rust
// codex-rs/core/src/agent/control.rs
fn maybe_start_completion_watcher(
    &self,
    child_thread_id: ThreadId,
    session_source: Option<SessionSource>,
)
```

当 sub-agent 达到最终状态时，自动向 parent thread 注入通知消息：

```rust
format_subagent_notification_message(&child_thread_id.to_string(), &status)
```

### 3.4 Agent 角色系统

#### 3.4.1 内置角色

定义于 `codex-rs/core/src/agent/role.rs`：

| 角色名称 | 描述 | 用途 |
|----------|------|------|
| `default` | 默认 agent | 通用任务 |
| `explorer` | 代码库探索者 | 快速、权威的代码库问题解答 |
| `worker` | 执行和生产工作 | 实现功能、修复测试或 bug |

#### 3.4.2 角色配置示例（explorer）

```rust
"explorer" => AgentRoleConfig {
    description: Some(r#"Use `explorer` for specific codebase questions.
Explorers are fast and authoritative.
They must be used to ask specific, well-scoped questions on the codebase.
Rules:
- In order to avoid redundant work, you should avoid exploring the same problem that explorers have already covered...
- You are encouraged to spawn up multiple explorers in parallel...
- Reuse existing explorers for related questions."#.to_string()),
    config_file: Some("explorer.toml".to_string().parse().unwrap_or_default()),
    nickname_candidates: None,
}
```

### 3.5 Guards（守卫）机制

```rust
// codex-rs/core/src/agent/guards.rs
pub(crate) struct Guards {
    active_agents: Mutex<ActiveAgents>,
    total_count: AtomicUsize,
}
```

限制：
- 总 sub-agents 数量限制（通过 `agent_max_threads` 配置）
- 嵌套深度限制（通过 `agent_max_depth` 配置）

```rust
pub(crate) fn exceeds_thread_spawn_depth_limit(depth: i32, max_depth: i32) -> bool {
    depth > max_depth
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心实现文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/core/templates/collab/experimental_prompt.md` | **本文件**：多智能体协作实验性提示模板 |
| `codex-rs/core/templates/agents/orchestrator.md` | 主智能体角色定义，包含 Sub-agents 章节 |
| `codex-rs/core/src/agent/mod.rs` | Agent 模块入口，导出关键类型 |
| `codex-rs/core/src/agent/control.rs` | AgentControl：多智能体操作控制平面 |
| `codex-rs/core/src/agent/guards.rs` | Guards：资源限制和守卫机制 |
| `codex-rs/core/src/agent/role.rs` | Agent 角色系统实现 |
| `codex-rs/core/src/agent/status.rs` | Agent 状态定义和转换 |

### 4.2 工具处理器文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/core/src/tools/handlers/multi_agents.rs` | 多智能体工具处理器入口和公共函数 |
| `codex-rs/core/src/tools/handlers/multi_agents/spawn.rs` | `spawn_agent` 工具实现 |
| `codex-rs/core/src/tools/handlers/multi_agents/send_input.rs` | `send_input` 工具实现 |
| `codex-rs/core/src/tools/handlers/multi_agents/wait.rs` | `wait_agent` 工具实现 |
| `codex-rs/core/src/tools/handlers/multi_agents/close_agent.rs` | `close_agent` 工具实现 |
| `codex-rs/core/src/tools/handlers/multi_agents/resume_agent.rs` | `resume_agent` 工具实现 |

### 4.3 工具定义文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/core/src/tools/spec.rs` | 工具规范定义，包括多智能体工具的 JSON Schema |

### 4.4 配置文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/core/src/agent/builtins/explorer.toml` | Explorer 角色配置（当前为空） |
| `codex-rs/core/src/agent/builtins/awaiter.toml` | Awaiter 角色配置 |
| `codex-rs/core/src/config/agent_roles.rs` | Agent 角色配置加载和解析 |

### 4.5 测试文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/core/src/tools/handlers/multi_agents_tests.rs` | 多智能体工具单元测试 |
| `codex-rs/core/tests/suite/subagent_notifications.rs` | Sub-agent 通知集成测试 |
| `codex-rs/core/tests/suite/spawn_agent_description.rs` | Spawn agent 描述测试 |
| `codex-rs/core/tests/suite/hierarchical_agents.rs` | 层级 agents 测试 |

### 4.6 关键代码片段

#### 4.6.1 AgentControl 结构定义

```rust
// codex-rs/core/src/agent/control.rs:69-76
#[derive(Clone, Default)]
pub(crate) struct AgentControl {
    /// Weak handle back to the global thread registry/state.
    manager: Weak<ThreadManagerState>,
    state: Arc<Guards>,
}
```

#### 4.6.2 Spawn Agent 核心逻辑

```rust
// codex-rs/core/src/agent/control.rs:98-225
pub(crate) async fn spawn_agent_with_options(
    &self,
    config: crate::config::Config,
    items: Vec<UserInput>,
    session_source: Option<SessionSource>,
    options: SpawnAgentOptions,
) -> CodexResult<ThreadId> {
    // 1. 获取 ThreadManagerState
    // 2. 预留 spawn slot
    // 3. 继承 shell snapshot 和 exec policy
    // 4. 处理 agent nickname
    // 5. 创建新线程（fork 或新建）
    // 6. 提交 reservation
    // 7. 发送初始输入
    // 8. 启动完成监视器
}
```

#### 4.6.3 Wait Agent 超时处理

```rust
// codex-rs/core/src/tools/handlers/multi_agents/wait.rs:62-70
let timeout_ms = args.timeout_ms.unwrap_or(DEFAULT_WAIT_TIMEOUT_MS);
let timeout_ms = match timeout_ms {
    ms if ms <= 0 => {
        return Err(FunctionCallError::RespondToModel(
            "timeout_ms must be greater than zero".to_owned(),
        ));
    }
    ms => ms.clamp(MIN_WAIT_TIMEOUT_MS, MAX_WAIT_TIMEOUT_MS),
};
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```
experimental_prompt.md
    │
    ├── 被引用 by
    │   └── orchestrator.md (Sub-agents 章节)
    │
    └── 相关实现
        ├── agent/control.rs (AgentControl)
        ├── agent/guards.rs (Guards)
        ├── agent/role.rs (角色系统)
        ├── agent/status.rs (状态管理)
        ├── tools/handlers/multi_agents/*.rs (工具处理器)
        ├── tools/spec.rs (工具定义)
        └── config/agent_roles.rs (角色配置)
```

### 5.2 协议依赖

```rust
// codex_protocol 依赖
codex_protocol::ThreadId
codex_protocol::protocol::AgentStatus
codex_protocol::protocol::SessionSource
codex_protocol::protocol::SubAgentSource
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
codex_protocol::user_input::UserInput
```

### 5.3 Feature Flag

```rust
// codex-rs/core/src/features.rs:716-721
FeatureSpec {
    id: Feature::Collab,
    key: "multi_agent",
    stage: Stage::Stable,
    default_enabled: true,
},
```

多智能体功能默认启用，可通过 `features.multi_agent = false` 禁用。

### 5.4 配置项

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `agent_max_depth` | 最大 agent 嵌套深度 | 3 |
| `agent_max_threads` | 最大线程数（sub-agents） | None（无限制） |
| `features.multi_agent` | 是否启用多智能体功能 | true |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 无限递归风险

**风险描述**：如果 sub-agent 被允许 spawn 新的 sub-agents，可能导致无限递归。

**当前缓解措施**：
- `experimental_prompt.md` 明确告知 sub-agents 不能自己 spawn sub-agents
- 代码层面有深度限制（`agent_max_depth`）

**建议**：在 `apply_spawn_agent_overrides` 中当达到最大深度时禁用 Collab 功能：

```rust
// codex-rs/core/src/tools/handlers/multi_agents.rs:315-320
fn apply_spawn_agent_overrides(config: &mut Config, child_depth: i32) {
    if child_depth >= config.agent_max_depth {
        let _ = config.features.disable(Feature::SpawnCsv);
        let _ = config.features.disable(Feature::Collab);
    }
}
```

#### 6.1.2 资源耗尽风险

**风险描述**：Spawn 过多 sub-agents 可能导致资源耗尽。

**当前缓解措施**：
- `Guards` 机制限制总线程数（`agent_max_threads`）
- `SpawnReservation` 确保资源正确释放

#### 6.1.3 竞态条件风险

**风险描述**：多个 sub-agents 同时修改同一文件可能导致冲突。

**当前缓解措施**：
- `orchestrator.md` 和角色定义中强调明确分配文件所有权
- 告知 workers 它们不是环境中唯一的 agent

### 6.2 边界情况

| 边界情况 | 行为 |
|----------|------|
| **空消息** | `spawn_agent` 和 `send_input` 拒绝空消息 |
| **同时设置 message 和 items** | 被拒绝，只能二选一 |
| **无效 agent ID** | 返回 `RespondToModel` 错误 |
| **Agent 不存在** | `wait_agent` 返回 `NotFound` 状态 |
| **超时** | `wait_agent` 返回 `timed_out: true` 和空状态 |
| **深度限制** | 超过 `agent_max_depth` 时返回错误 "Agent depth limit reached" |
| **线程限制** | 超过 `agent_max_threads` 时返回 `AgentLimitReached` 错误 |

### 6.3 改进建议

#### 6.3.1 文档改进

1. **添加中文版本**：考虑为中文用户提供本地化版本的提示模板
2. **示例丰富**：添加更多具体的使用示例，特别是并行 delegation 模式
3. **故障排除指南**：添加常见错误和解决方案的说明

#### 6.3.2 功能改进

1. **动态深度限制**：根据任务复杂度动态调整深度限制
2. **Agent 间通信**：支持 sub-agents 之间的直接通信（当前只能通过 parent）
3. **结果聚合**：提供内置的结果聚合机制，简化多 agent 结果整合
4. **可视化**：在 TUI 中显示 agent 层级结构和状态

#### 6.3.3 监控与可观测性

1. **Metrics 增强**：
   - 添加 `codex.multi_agent.spawn_duration` 直方图
   - 添加 `codex.multi_agent.wait_duration` 直方图
   - 添加 `codex.multi_agent.depth` 分布

2. **Tracing 增强**：
   - 在关键路径添加 span
   - 关联 parent 和 child agent 的 trace

#### 6.3.4 测试覆盖

1. **边界测试**：
   - 深度限制边界测试
   - 线程限制边界测试
   - 超时边界测试

2. **故障注入**：
   - Agent 崩溃恢复测试
   - 网络中断测试
   - 资源耗尽测试

### 6.4 相关 Issue/PR 参考

- 该文件目前未直接引用具体的 Issue 或 PR
- 相关变更历史可在 `codex-rs/core/src/tools/handlers/multi_agents*.rs` 的 git 历史中找到

---

## 7. 附录

### 7.1 术语表

| 术语 | 说明 |
|------|------|
| **Agent** | 智能体，指 Codex 的 AI 助手实例 |
| **Sub-agent** | 由主 agent spawn 的子智能体 |
| **Parent agent** | 创建 sub-agent 的主智能体 |
| **Thread** | 对话线程，每个 agent 对应一个 thread |
| **ThreadId** | 线程唯一标识符 |
| **Spawn** | 创建新的 sub-agent |
| **Fork** | 从 parent agent 复制上下文创建新 agent |
| **Role** | Agent 的角色定义（如 explorer、worker） |
| **Nickname** | Agent 的用户友好名称 |

### 7.2 相关文档链接

- `codex-rs/core/templates/agents/orchestrator.md` - 主智能体角色定义
- `codex-rs/core/templates/collaboration_mode/*.md` - 协作模式模板
- `codex-rs/app-server/README.md` - App Server API 文档
- `AGENTS.md`（项目根目录）- 项目级代理指导

---

*文档生成时间：2026-03-23*
*研究范围：codex-rs/core/templates/collab/experimental_prompt.md 及其直接依赖*
