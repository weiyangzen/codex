# multi_agents.rs 研究文档

## 场景与职责

`multi_agents.rs` 是 Codex 多智能体协作系统的核心协调模块，实现了子智能体的生命周期管理和协作工具集。该模块使 AI 模型能够：

1. **创建子智能体** (`spawn_agent`) - 派生独立的子任务执行者
2. **发送输入** (`send_input`) - 向运行中的子智能体发送消息
3. **等待完成** (`wait_agent`) - 等待子智能体达到终态
4. **恢复智能体** (`resume_agent`) - 从持久化状态恢复已关闭的智能体
5. **关闭智能体** (`close_agent`) - 终止子智能体

**架构定位：**
该模块作为工具处理器层的一部分，将模型工具调用转换为 `AgentControl` 操作，维护父-子智能体关系，并确保配置和状态的一致性。

## 功能点目的

### 1. 智能体生命周期管理

**创建 (spawn_agent):**
- 基于父智能体的当前配置创建子智能体
- 继承运行时状态（模型、审批策略、沙箱、工作目录）
- 支持角色特定的配置覆盖
- 支持上下文分叉（fork_context）

**输入 (send_input):**
- 向指定子智能体发送文本消息或结构化输入项
- 支持中断当前操作
- 异步发送，立即返回

**等待 (wait_agent):**
- 等待一个或多个子智能体达到终态
- 支持超时配置（默认 30 秒，范围 10 秒-1 小时）
- 返回所有目标智能体的最终状态

**恢复 (resume_agent):**
- 从 rollout 记录恢复已关闭的智能体
- 重建会话状态和历史
- 支持深度限制检查

**关闭 (close_agent):**
- 优雅地关闭子智能体
- 返回关闭前的状态

### 2. 配置继承与覆盖

**配置构建流程：**
```
父智能体配置
  ├── 运行时覆盖（来自 TurnContext）
  │     ├── model
  │     ├── provider
  │     ├── reasoning_effort
  │     ├── approval_policy
  │     ├── sandbox_policy
  │     └── cwd
  ├── 角色配置覆盖（可选）
  └── 深度限制检查
```

### 3. 深度限制与防循环

- 每个子智能体有深度值（从父继承 +1）
- 可配置 `agent_max_depth` 限制最大深度
- 达到限制时禁用 `SpawnCsv` 和 `Collab` 功能

## 具体技术实现

### 模块结构

```rust
pub mod close_agent;    // close_agent.rs
mod resume_agent;       // resume_agent.rs
mod send_input;         // send_input.rs
mod spawn;              // spawn.rs
pub(crate) mod wait;    // wait.rs

// 公开导出
pub(crate) use close_agent::Handler as CloseAgentHandler;
pub(crate) use resume_agent::Handler as ResumeAgentHandler;
pub(crate) use send_input::Handler as SendInputHandler;
pub(crate) use spawn::Handler as SpawnAgentHandler;
pub(crate) use wait::Handler as WaitAgentHandler;
```

### 关键常量

```rust
pub(crate) const MIN_WAIT_TIMEOUT_MS: i64 = 10_000;       // 最小 10 秒
pub(crate) const DEFAULT_WAIT_TIMEOUT_MS: i64 = 30_000;   // 默认 30 秒
pub(crate) const MAX_WAIT_TIMEOUT_MS: i64 = 3600 * 1000;  // 最大 1 小时
```

### 配置构建详解

**1. 基础配置构建：**
```rust
pub(crate) fn build_agent_spawn_config(
    base_instructions: &BaseInstructions,
    turn: &TurnContext,
) -> Result<Config, FunctionCallError> {
    let mut config = build_agent_shared_config(turn)?;
    config.base_instructions = Some(base_instructions.text.clone());
    Ok(config)
}
```

**2. 共享配置构建：**
```rust
fn build_agent_shared_config(turn: &TurnContext) -> Result<Config, FunctionCallError> {
    let base_config = turn.config.clone();
    let mut config = (*base_config).clone();
    
    // 运行时状态覆盖
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

**3. 运行时覆盖：**
```rust
fn apply_spawn_agent_runtime_overrides(
    config: &mut Config,
    turn: &TurnContext,
) -> Result<(), FunctionCallError> {
    config.permissions.approval_policy.set(turn.approval_policy.value())?;
    config.permissions.shell_environment_policy = turn.shell_environment_policy.clone();
    config.codex_linux_sandbox_exe = turn.codex_linux_sandbox_exe.clone();
    config.cwd = turn.cwd.clone();
    config.permissions.sandbox_policy.set(turn.sandbox_policy.get().clone())?;
    config.permissions.file_system_sandbox_policy = turn.file_system_sandbox_policy.clone();
    config.permissions.network_sandbox_policy = turn.network_sandbox_policy;
    Ok(())
}
```

### 模型选择逻辑

```rust
async fn apply_requested_spawn_agent_model_overrides(
    session: &Session,
    turn: &TurnContext,
    config: &mut Config,
    requested_model: Option<&str>,
    requested_reasoning_effort: Option<ReasoningEffort>,
) -> Result<(), FunctionCallError>
```

**流程：**
1. 如果指定了模型，验证模型可用性
2. 如果指定了推理强度，验证模型支持该强度
3. 否则继承父智能体的模型和推理设置

### 错误处理

```rust
fn collab_spawn_error(err: CodexErr) -> FunctionCallError {
    match err {
        CodexErr::UnsupportedOperation(_) => 
            FunctionCallError::RespondToModel("collab manager unavailable".to_string()),
        err => FunctionCallError::RespondToModel(format!("collab spawn failed: {err}")),
    }
}

fn collab_agent_error(agent_id: ThreadId, err: CodexErr) -> FunctionCallError {
    match err {
        CodexErr::ThreadNotFound(id) => 
            FunctionCallError::RespondToModel(format!("agent with id {id} not found")),
        CodexErr::InternalAgentDied => 
            FunctionCallError::RespondToModel(format!("agent with id {agent_id} is closed")),
        CodexErr::UnsupportedOperation(_) => 
            FunctionCallError::RespondToModel("collab manager unavailable".to_string()),
        err => FunctionCallError::RespondToModel(format!("collab tool failed: {err}")),
    }
}
```

### 输入解析

```rust
fn parse_collab_input(
    message: Option<String>,
    items: Option<Vec<UserInput>>,
) -> Result<Vec<UserInput>, FunctionCallError>
```

**规则：**
- 必须提供 `message` 或 `items` 之一，不能同时提供
- `message` 不能为空字符串
- `items` 不能为空列表

### 状态构建

```rust
fn build_wait_agent_statuses(
    statuses: &HashMap<ThreadId, AgentStatus>,
    receiver_agents: &[CollabAgentRef],
) -> Vec<CollabAgentStatusEntry>
```

**逻辑：**
1. 首先按 `receiver_agents` 顺序添加已知智能体
2. 然后添加不在列表中的额外智能体（按 ID 排序）

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::agent::{AgentStatus, AgentControl, ...}` | 智能体控制接口 |
| `crate::codex::{Session, TurnContext}` | 会话和回合上下文 |
| `crate::config::Config` | 配置管理 |
| `crate::features::Feature` | 功能开关 |
| `crate::tools::registry::{ToolHandler, ToolKind}` | 工具处理器 trait |
| `crate::tools::context::{ToolInvocation, ToolPayload, FunctionToolOutput}` | 工具调用上下文 |
| `crate::models_manager::manager::RefreshStrategy` | 模型列表刷新 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `codex_protocol::ThreadId` | 线程/智能体标识 |
| `codex_protocol::models::BaseInstructions` | 基础指令 |
| `codex_protocol::protocol::*` | 协议事件类型 |
| `codex_protocol::user_input::UserInput` | 用户输入类型 |
| `serde::{Deserialize, Serialize}` | 序列化 |
| `async_trait` | 异步 trait |

### 子模块关系

```
multi_agents.rs (协调层)
  ├── close_agent.rs → CloseAgentHandler
  ├── resume_agent.rs → ResumeAgentHandler
  ├── send_input.rs → SendInputHandler
  ├── spawn.rs → SpawnAgentHandler
  └── wait.rs → WaitAgentHandler
```

每个子模块实现 `ToolHandler` trait，处理特定的工具调用。

## 风险、边界与改进建议

### 已知风险

1. **深度限制绕过**
   - 当前深度检查在配置构建后应用
   - 角色配置可能覆盖深度限制
   - **建议：** 在配置应用后再次验证深度

2. **配置不一致**
   - 运行时状态可能与会话持久化状态不一致
   - 恢复的智能体可能缺少某些运行时覆盖
   - **建议：** 明确区分持久化和非持久化配置

3. **超时处理**
   - `wait_agent` 的超时是整个等待的超时，不是每个智能体的超时
   - 大量智能体可能导致超时计算不准确

### 边界情况

| 场景 | 当前行为 |
|------|----------|
| 深度达到限制 | 返回错误 "Agent depth limit reached" |
| 等待空 ID 列表 | 返回错误 "ids must be non-empty" |
| 超时 <= 0 | 返回错误 "timeout_ms must be greater than zero" |
| 同时提供 message 和 items | 返回错误 "Provide either message or items, but not both" |
| 恢复不存在的智能体 | 返回错误 "agent with id X not found" |

### 测试覆盖

测试模块 `multi_agents_tests.rs` 覆盖：
- 配置构建逻辑
- 深度限制计算
- 输入解析

**测试盲点：**
- 实际的智能体创建/关闭流程（需要 mock）
- 等待超时逻辑
- 模型选择验证
- 角色配置应用

### 改进建议

1. **添加配置验证**
```rust
fn validate_agent_config(config: &Config, parent_depth: i32) -> Result<(), FunctionCallError> {
    if exceeds_thread_spawn_depth_limit(parent_depth + 1, config.agent_max_depth) {
        return Err(FunctionCallError::RespondToModel(
            "Agent depth limit reached".to_string()
        ));
    }
    // 其他验证...
    Ok(())
}
```

2. **优化等待性能**
```rust
// 使用 tokio::time::timeout 替代手动 deadline 计算
let result = tokio::time::timeout(
    Duration::from_millis(timeout_ms as u64),
    wait_for_agents(...)
).await;
```

3. **添加更多事件通知**
- 当前只有 begin/end 事件
- 建议添加进度事件，特别是对于长时间等待

4. **改进错误消息**
```rust
// 当前
"agent with id X not found"

// 建议
"Agent X not found. It may have been closed or never existed. \
 Use spawn_agent to create a new agent."
```

5. **支持批量操作**
```rust
// 当前：一次只能发送给一个智能体
send_input(id: String, ...)

// 建议：支持批量发送
send_input(ids: Vec<String>, ...)
```

### 代码统计

| 指标 | 数值 |
|------|------|
| 代码行数 | ~417 行 |
| 子模块 | 5 个 |
| 公开导出 | 5 个 Handler 类型 |
| 辅助函数 | 15+ 个 |

这是一个复杂的多智能体协调模块，涉及配置管理、生命周期控制和错误处理等多个方面，是整个 Codex 协作能力的核心。
