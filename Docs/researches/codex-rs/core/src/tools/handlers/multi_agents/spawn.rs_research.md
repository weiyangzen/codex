# spawn.rs 研究文档

## 场景与职责

`spawn.rs` 实现了 `spawn_agent` 工具的处理器，用于创建新的子代理（sub-agent）。这是多代理协作系统的核心功能，允许父代理动态创建专门的子代理来处理特定任务，实现任务的并行化和专业化分工。

在多代理协作场景中，父代理可以根据任务需求创建具有特定角色（如 "explorer"、"coder" 等）的子代理，并可以指定不同的模型和推理级别。子代理继承父代理的配置和运行时状态，同时可以应用角色特定的覆盖设置。

## 功能点目的

1. **创建子代理**：根据配置和输入创建新的子代理线程
2. **角色应用**：支持应用预定义的角色配置（如 "explorer"）
3. **模型覆盖**：允许指定不同的模型和推理级别
4. **深度限制**：防止代理层级过深，避免无限递归
5. **上下文分叉**：支持从父代理分叉对话历史（fork_context）
6. **事件通知**：通过 `CollabAgentSpawnBeginEvent` 和 `CollabAgentSpawnEndEvent` 通知创建过程
7. **配置继承**：子代理继承父代理的运行时配置（审批策略、沙盒策略、工作目录等）

## 具体技术实现

### 关键数据结构

```rust
// 创建代理的参数
#[derive(Debug, Deserialize)]
struct SpawnAgentArgs {
    message: Option<String>,                    // 初始消息（与 items 互斥）
    items: Option<Vec<UserInput>>,             // 结构化输入项（与 message 互斥）
    agent_type: Option<String>,                // 角色名称（如 "explorer"）
    model: Option<String>,                     // 模型名称覆盖
    reasoning_effort: Option<ReasoningEffort>, // 推理级别覆盖
    #[serde(default)]
    fork_context: bool,                        // 是否分叉父代理上下文
}

// 创建操作的结果
#[derive(Debug, Serialize)]
pub(crate) struct SpawnAgentResult {
    agent_id: String,       // 新代理的 ID
    nickname: Option<String>, // 代理的昵称
}
```

### 关键流程

1. **参数解析与验证**：
   - 解析 `SpawnAgentArgs`
   - 处理角色名称（去除空白，过滤空值）
   - 解析输入（message 或 items）

2. **深度限制检查**：
   - 计算子代理深度（`next_thread_spawn_depth`）
   - 检查是否超过 `agent_max_depth` 限制

3. **发送开始事件**：
   - 发送 `CollabAgentSpawnBeginEvent`，包含模型和推理级别信息

4. **配置构建**：
   - `build_agent_spawn_config`：基于父代理配置创建基础配置
   - `apply_requested_spawn_agent_model_overrides`：应用请求的模型覆盖
   - `apply_role_to_config`：应用角色配置
   - `apply_spawn_agent_runtime_overrides`：应用运行时覆盖（审批策略、沙盒等）
   - `apply_spawn_agent_overrides`：应用深度相关的特性禁用

5. **创建代理**：
   - 调用 `AgentControl::spawn_agent_with_options`
   - 传递 `SpawnAgentOptions`，包含可选的 fork 上下文标志

6. **获取代理信息**：
   - 获取新代理的配置快照
   - 提取昵称、角色、实际使用的模型和推理级别

7. **发送结束事件**：
   - 发送 `CollabAgentSpawnEndEvent`，包含新代理的详细信息

8. **记录指标**：
   - 记录 `codex.multi_agent.spawn` 指标，附带角色标签

### 配置构建详解

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
    // 继承运行时模型设置
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

### 运行时覆盖

`apply_spawn_agent_runtime_overrides` 确保子代理继承父代理的运行时状态：
- `approval_policy`：审批策略
- `shell_environment_policy`：Shell 环境策略
- `codex_linux_sandbox_exe`：Linux 沙盒可执行文件路径
- `cwd`：当前工作目录
- `sandbox_policy`：沙盒策略
- `file_system_sandbox_policy`：文件系统沙盒策略
- `network_sandbox_policy`：网络沙盒策略

### 模型覆盖逻辑

```rust
async fn apply_requested_spawn_agent_model_overrides(
    session: &Session,
    turn: &TurnContext,
    config: &mut Config,
    requested_model: Option<&str>,
    requested_reasoning_effort: Option<ReasoningEffort>,
) -> Result<(), FunctionCallError> {
    if let Some(requested_model) = requested_model {
        // 验证模型可用性
        let available_models = session.services.models_manager.list_models(...).await;
        let selected_model_name = find_spawn_agent_model_name(&available_models, requested_model)?;
        config.model = Some(selected_model_name.clone());
        
        // 应用推理级别
        if let Some(reasoning_effort) = requested_reasoning_effort {
            validate_spawn_agent_reasoning_effort(...)?;
            config.model_reasoning_effort = Some(reasoning_effort);
        }
    }
    ...
}
```

### 深度限制与特性禁用

```rust
fn apply_spawn_agent_overrides(config: &mut Config, child_depth: i32) {
    if child_depth >= config.agent_max_depth {
        let _ = config.features.disable(Feature::SpawnCsv);
        let _ = config.features.disable(Feature::Collab);
    }
}
```

当达到最大深度时，禁用 `SpawnCsv` 和 `Collab` 特性，防止进一步创建子代理。

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/tools/handlers/multi_agents/spawn.rs` - 本文件

### 依赖文件
- `/home/sansha/Github/codex/codex-rs/core/src/tools/handlers/multi_agents.rs` - 父模块，提供配置构建函数
- `/home/sansha/Github/codex/codex-rs/core/src/tools/registry.rs` - 工具注册表
- `/home/sansha/Github/codex/codex-rs/core/src/agent/control.rs` - `AgentControl`，提供 `spawn_agent_with_options`
- `/home/sansha/Github/codex/codex-rs/core/src/agent/guards.rs` - 深度计算和限制检查
- `/home/sansha/Github/codex/codex-rs/core/src/agent/role.rs` - 角色配置应用
- `/home/sansha/Github/codex/codex-rs/protocol/src/protocol.rs` - 协议事件定义

### 调用链
```
ToolRegistry::dispatch_any()
  -> SpawnAgentHandler::handle()
    -> next_thread_spawn_depth()  // 计算深度
    -> exceeds_thread_spawn_depth_limit()  // 检查深度限制
    -> build_agent_spawn_config()  // 构建基础配置
    -> apply_requested_spawn_agent_model_overrides()  // 应用模型覆盖
    -> apply_role_to_config()  // 应用角色配置
    -> apply_spawn_agent_runtime_overrides()  // 应用运行时覆盖
    -> apply_spawn_agent_overrides()  // 应用深度覆盖
    -> AgentControl::spawn_agent_with_options()  // 创建代理
    -> AgentControl::get_agent_config_snapshot()  // 获取配置快照
```

## 依赖与外部交互

### 服务依赖
- `session.services.agent_control`：用于创建代理
- `session.services.models_manager`：用于验证和获取模型信息
- `session.get_base_instructions`：获取基础指令

### 配置依赖
- `turn.config`：基础配置
- `turn.model_info`：当前模型信息
- `turn.provider`：模型提供者
- `turn.approval_policy`：审批策略
- `turn.sandbox_policy`：沙盒策略
- `turn.cwd`：工作目录

### 角色系统
角色通过 `apply_role_to_config` 应用，支持：
- 自定义指令
- 工具集限制
- 昵称候选列表
- 沙盒策略覆盖

### 事件类型
- `CollabAgentSpawnBeginEvent`：创建开始
- `CollabAgentSpawnEndEvent`：创建结束，包含代理 ID、昵称、模型、状态等

## 风险、边界与改进建议

### 边界情况

1. **深度限制**：达到 `agent_max_depth` 时创建会被拒绝
2. **无效模型**：请求的模型不在可用列表中会返回错误
3. **无效推理级别**：模型不支持的推理级别会被拒绝
4. **角色不存在**：未知的角色名称会被忽略（使用默认配置）
5. **空输入**：空消息或空 items 会被拒绝

### 风险点

1. **资源耗尽**：大量创建子代理可能耗尽系统资源（内存、线程）
2. **配置漂移**：子代理配置可能与父代理逐渐不一致
3. **角色冲突**：多个角色可能定义冲突的配置覆盖
4. **fork 成本**：分叉上下文需要复制 rollout 历史，可能开销较大
5. **昵称耗尽**：如果代理数量超过昵称候选列表，需要重置昵称池

### 改进建议

1. **资源配额**：为每个父代理设置子代理数量配额
2. **配置同步**：定期同步父子代理的配置，确保一致性
3. **角色继承**：支持角色组合和继承，减少重复配置
4. **延迟 fork**：延迟加载 fork 的上下文，减少初始开销
5. **代理池**：实现代理池机制，复用已关闭的代理资源
6. **创建超时**：为创建操作添加超时，避免无限期等待
7. **预热机制**：预创建代理实例，减少创建延迟
8. **代理模板**：支持保存和复用代理配置模板

### 测试覆盖

测试文件：`/home/sansha/Github/codex/codex-rs/core/src/tools/handlers/multi_agents_tests.rs`

相关测试：
- `handler_rejects_non_function_payloads`：验证 payload 类型检查
- `spawn_agent_rejects_empty_message`：验证空消息拒绝
- `spawn_agent_rejects_when_message_and_items_are_both_set`：验证互斥参数
- `spawn_agent_uses_explorer_role_and_preserves_approval_policy`：验证角色应用和配置继承
- `spawn_agent_errors_when_manager_dropped`：验证 manager 不可用时的错误
- `spawn_agent_reapplies_runtime_sandbox_after_role_config`：验证运行时覆盖
- `spawn_agent_rejects_when_depth_limit_exceeded`：验证深度限制
- `spawn_agent_allows_depth_up_to_configured_max_depth`：验证允许的最大深度
