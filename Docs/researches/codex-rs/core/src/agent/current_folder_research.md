# DIR codex-rs/core/src/agent 研究文档

## 概述

`codex-rs/core/src/agent` 目录是 Codex 多智能体系统的核心实现，负责子智能体的生命周期管理、角色配置、资源限制和状态跟踪。该模块实现了父智能体创建子智能体（sub-agent）的完整流程，支持并行执行、角色定制和资源隔离。

---

## 场景与职责

### 核心职责

1. **子智能体生命周期管理**
   - 创建（spawn）、恢复（resume）、关闭（shutdown）子智能体
   - 管理子智能体的输入发送和状态监控
   - 支持从父智能体历史记录 fork 创建子智能体

2. **角色（Role）系统**
   - 内置角色：default、explorer、worker（awaiter 暂时移除）
   - 用户自定义角色加载与配置合并
   - 角色配置层叠在现有配置之上，支持模型、推理强度等覆盖

3. **资源限制与保护（Guards）**
   - 限制每个用户会话的子智能体总数（`agent_max_threads`）
   - 限制子智能体嵌套深度（`agent_max_depth`）
   - 智能体昵称分配与管理（避免冲突，支持序号后缀）

4. **状态跟踪与通知**
   - 从事件流派生智能体状态（Running/Completed/Errored/Shutdown等）
   - 子智能体完成时通知父智能体
   - 支持状态订阅（watch channel）

### 使用场景

- **并行探索**：父智能体同时 spawn 多个 explorer 角色子智能体，分别调查代码库不同部分
- **任务分解**：worker 角色子智能体执行独立的代码修改任务
- **长时间等待**：awaiter 角色（当前禁用）用于监控长时间运行的命令
- **协作模式**：支持父子智能体之间的状态通知和上下文共享

---

## 功能点目的

### 1. AgentControl - 控制平面

**文件**: `control.rs` (538 lines)

`AgentControl` 是每个会话共享的控制句柄，提供多智能体操作能力：

| 方法 | 用途 |
|------|------|
| `spawn_agent` / `spawn_agent_with_options` | 创建新子智能体，支持 fork 历史 |
| `resume_agent_from_rollout` | 从 rollout 文件恢复已关闭的智能体 |
| `send_input` | 向子智能体发送用户输入 |
| `interrupt_agent` | 中断子智能体当前任务 |
| `shutdown_agent` | 关闭子智能体并释放资源 |
| `get_status` / `subscribe_status` | 获取/订阅子智能体状态 |
| `format_environment_context_subagents` | 格式化子智能体上下文信息 |

**关键特性**：
- 使用 `Weak<ThreadManagerState>` 避免循环引用
- 子智能体完成时自动通知父智能体（`maybe_start_completion_watcher`）
- 继承父智能体的 shell 快照和执行策略

### 2. Guards - 资源限制

**文件**: `guards.rs` (230 lines)

```rust
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

**功能**：
- `reserve_spawn_slot`: 原子性地预留创建槽位（支持最大线程数限制）
- `SpawnReservation`: RAII 风格的预留句柄，drop 时自动释放
- `reserve_agent_nickname`: 从候选列表分配唯一昵称，支持序号后缀（如 "Plato the 2nd"）
- 昵称池耗尽时自动重置并增加序号

### 3. Role - 角色配置

**文件**: `role.rs` (423 lines)

**内置角色**（`built_in` 模块）：
- `default`: 默认智能体，无特殊配置
- `explorer`: 用于代码库探索，配置在 `builtins/explorer.toml`（当前为空）
- `worker`: 用于执行和生产工作，无特殊配置
- `awaiter`: 已移除，原用于长时间等待任务

**角色配置合并流程**：
1. 解析角色配置文件（TOML）
2. 确定保留策略（preserve_current_profile/provider）
3. 构建配置层叠栈（ConfigLayerStack）
4. 重新加载合并后的配置

**关键函数**：
- `apply_role_to_config`: 将角色配置应用到现有配置
- `resolve_role_config`: 解析角色配置（优先用户定义， fallback 内置）
- `spawn_tool_spec::build`: 构建 spawn_agent 工具的描述文本

### 4. Status - 状态派生

**文件**: `status.rs` (27 lines)

从事件流派生智能体状态：

```rust
pub(crate) fn agent_status_from_event(msg: &EventMsg) -> Option<AgentStatus> {
    match msg {
        EventMsg::TurnStarted(_) => Some(AgentStatus::Running),
        EventMsg::TurnComplete(ev) => Some(AgentStatus::Completed(...)),
        EventMsg::TurnAborted(ev) => ...
        EventMsg::Error(ev) => Some(AgentStatus::Errored(...)),
        EventMsg::ShutdownComplete => Some(AgentStatus::Shutdown),
        _ => None,
    }
}
```

**AgentStatus 枚举**（定义在 `codex_protocol::protocol`）：
- `PendingInit`: 等待初始化
- `Running`: 运行中
- `Interrupted`: 被中断
- `Completed(Option<String>)`: 完成，包含最后消息
- `Errored(String)`: 错误
- `Shutdown`: 已关闭
- `NotFound`: 未找到

---

## 具体技术实现

### 关键流程

#### 1. 子智能体创建流程（spawn_agent）

```
spawn_agent_with_options
├── 升级 Weak<ThreadManagerState>（失败返回错误）
├── reserve_spawn_slot（预留槽位，检查 max_threads）
├── 继承父智能体 shell 快照和执行策略
├── 确定 agent_nickname（从角色候选列表或默认列表）
├── 构建 SessionSource::SubAgent(SubAgentSource::ThreadSpawn {...})
├── 选择创建路径：
│   ├── fork_parent_spawn_call_id 存在 → fork_thread_with_source
│   │   ├── 确保父 rollout 已物化
│   │   ├── 加载父历史记录
│   │   ├── 注入 FORKED_SPAWN_AGENT_OUTPUT_MESSAGE
│   │   └── 创建子线程
│   └── 否则 → spawn_new_thread_with_source
├── reservation.commit（提交槽位预留）
├── notify_thread_created（通知线程创建）
├── send_input（发送初始输入）
└── maybe_start_completion_watcher（启动完成监控）
```

#### 2. 角色配置应用流程

```
apply_role_to_config
├── resolve_role_config（解析角色配置）
├── load_role_layer_toml（加载角色 TOML）
│   ├── 内置角色 → include_str! 嵌入内容
│   └── 用户角色 → 读取文件并解析
├── preservation_policy（确定保留策略）
│   ├── 角色是否显式设置 model_provider？
│   ├── 角色是否显式设置 profile？
│   └── 角色是否更新当前 profile 的 provider？
└── reload::build_next_config（重建配置）
    ├── build_config_layer_stack（构建层叠栈）
    ├── deserialize_effective_config（反序列化有效配置）
    └── Config::load_config_with_layer_stack（加载配置）
```

#### 3. 完成通知流程

```
maybe_start_completion_watcher
├── 仅对 ThreadSpawn 类型的子智能体启用
├── tokio::spawn 后台任务
│   ├── subscribe_status 或轮询获取状态
│   ├── 等待状态变为 final（Completed/Errored/Shutdown）
│   ├── 获取父智能体线程
│   └── inject_user_message_without_turn（注入完成通知）
```

### 关键数据结构

#### SpawnAgentOptions
```rust
#[derive(Clone, Debug, Default)]
pub(crate) struct SpawnAgentOptions {
    pub(crate) fork_parent_spawn_call_id: Option<String>,
}
```

#### SubAgentSource（协议定义）
```rust
pub enum SubAgentSource {
    ThreadSpawn {
        parent_thread_id: ThreadId,
        depth: i32,
        agent_nickname: Option<String>,
        agent_role: Option<String>,
    },
    Review,
}
```

#### AgentRoleConfig
```rust
pub struct AgentRoleConfig {
    pub description: Option<String>,
    pub config_file: Option<PathBuf>,
    pub nickname_candidates: Option<Vec<String>>,
}
```

### 协议与命令

**AgentControl 与 ThreadManagerState 的交互**：
- `AgentControl` 持有 `Weak<ThreadManagerState>`，避免循环引用
- 所有操作通过 `upgrade()` 获取 `Arc<ThreadManagerState>`
- `ThreadManagerState` 管理线程哈希表和创建通知通道

**与 multi_agents 工具处理器的交互**：
- `tools/handlers/multi_agents/spawn.rs` 调用 `AgentControl::spawn_agent_with_options`
- 构建配置时调用 `apply_role_to_config` 应用角色
- 深度限制检查通过 `exceeds_thread_spawn_depth_limit`

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `control.rs` | 538 | AgentControl 实现，生命周期管理 |
| `guards.rs` | 230 | 资源限制和昵称管理 |
| `role.rs` | 423 | 角色配置解析和应用 |
| `status.rs` | 27 | 状态派生逻辑 |
| `mod.rs` | 10 | 模块导出 |

### 测试文件

| 文件 | 行数 | 覆盖内容 |
|------|------|----------|
| `control_tests.rs` | 1095 | AgentControl 完整测试 |
| `guards_tests.rs` | 243 | Guards 和昵称逻辑测试 |
| `role_tests.rs` | 741 | 角色配置应用测试 |

### 内置角色配置

| 文件 | 内容 |
|------|------|
| `builtins/explorer.toml` | 空文件（当前配置） |
| `builtins/awaiter.toml` | awaiter 角色配置（已禁用） |
| `agent_names.txt` | 101 个科学家/哲学家名字列表 |

### 调用方文件

| 文件 | 用途 |
|------|------|
| `tools/handlers/multi_agents.rs` | 协作工具处理器，调用 spawn/close/wait/resume |
| `tools/handlers/multi_agents/spawn.rs` | spawn_agent 工具实现 |
| `thread_manager.rs` | ThreadManagerState 定义，被 AgentControl 引用 |
| `codex.rs` | Codex 主结构，使用 AgentControl |

### 被调用方/依赖

| 模块 | 用途 |
|------|------|
| `codex_protocol::protocol::AgentStatus` | 状态枚举定义 |
| `codex_protocol::protocol::SessionSource` | 会话来源类型 |
| `config::agent_roles` | 角色配置加载 |
| `config_loader::ConfigLayerStack` | 配置层叠管理 |
| `state_db` | 智能体元数据持久化 |

---

## 依赖与外部交互

### 内部依赖

```rust
// 核心依赖
use crate::thread_manager::ThreadManagerState;
use crate::config::{Config, AgentRoleConfig};
use crate::error::{CodexErr, Result};
use crate::codex_thread::CodexThread;
use crate::state_db;
use crate::rollout::RolloutRecorder;

// 协议类型
use codex_protocol::ThreadId;
use codex_protocol::protocol::{SessionSource, SubAgentSource, Op, AgentStatus};
use codex_protocol::user_input::UserInput;
```

### 外部 crate 依赖

- `tokio`: 异步运行时，spawn 后台 watcher 任务
- `rand`: 随机选择 agent 昵称
- `serde` / `toml`: 角色配置解析

### 配置项

| 配置键 | 用途 |
|--------|------|
| `agents.max_threads` | 每个会话的最大子智能体数 |
| `agents.max_depth` | 子智能体嵌套深度限制 |
| `agents.<role>` | 自定义角色定义 |

---

## 风险、边界与改进建议

### 当前风险与边界

1. **昵称池耗尽**
   - 当所有昵称被使用后，会自动重置并添加序号后缀
   - 风险：序号可能无限增长（虽然实际不太可能达到）
   - 边界：昵称重置计数器 `nickname_reset_count` 是 usize，理论上可能溢出

2. **资源限制绕过**
   - `max_threads` 为 `None` 时不限制数量
   - `Drop` 实现确保预留槽位在失败时释放，但 panic 时可能泄漏

3. **Fork 历史一致性**
   - Fork 时需要先物化父 rollout，如果父智能体在物化过程中崩溃，fork 可能获得不完整历史
   - 边界：fork 只复制到 spawn 调用时的历史，后续父智能体的操作对子智能体不可见

4. **角色配置冲突**
   - 用户角色和内置角色同名时，用户角色优先
   - 风险：用户可能意外覆盖内置角色行为

5. **状态通知可靠性**
   - `maybe_start_completion_watcher` 使用 detached tokio task
   - 如果父智能体在子智能体完成前关闭，通知可能丢失

### 改进建议

1. **增强可观测性**
   - 添加更多指标：子智能体创建/关闭计数、平均生命周期、角色使用分布
   - 当前只有 `codex.multi_agent.nickname_pool_reset` 一个指标

2. **优化昵称管理**
   - 考虑使用 LRU 策略重用已关闭智能体的昵称
   - 添加配置允许用户自定义昵称列表

3. **强化错误处理**
   - `apply_role_to_config` 的错误信息可以更丰富，指出具体哪个配置项失败
   - 角色配置验证可以提前到加载时，而非应用时

4. **支持动态角色更新**
   - 当前角色配置在启动时加载，不支持运行时热更新
   - 可以考虑添加信号或 API 触发角色重载

5. **改进完成通知机制**
   - 考虑使用持久化队列确保通知不丢失
   - 支持批量通知（多个子智能体同时完成时合并通知）

6. **代码结构优化**
   - `control.rs` 538 行接近 AGENTS.md 建议的 500 行上限，可以考虑将 `resume_agent_from_rollout` 等逻辑提取到子模块
   - `role.rs` 中的 `reload` 子模块逻辑复杂，可以进一步拆分

---

## 附录：Agent 昵称列表

`agent_names.txt` 包含 101 个科学家和哲学家名字，用于子智能体昵称分配：

- 古希腊/罗马：Euclid, Archimedes, Ptolemy, Hypatia, Socrates, Plato, Aristotle...
- 文艺复兴/启蒙：Copernicus, Galileo, Bacon, Descartes, Pascal, Newton...
- 现代科学：Darwin, Maxwell, Curie, Einstein, Turing, Feynman...
- 哲学：Locke, Hume, Kant, Nietzsche, Russell...

昵称格式：
- 首次使用：`Plato`
- 第二次：`Plato the 2nd`
- 第三次：`Plato the 3rd`
- 第十一次：`Plato the 11th`

---

*文档生成时间: 2026-03-21*
*研究范围: codex-rs/core/src/agent 目录及其直接依赖*
