# resume_agent.rs 研究文档

## 场景与职责

`resume_agent.rs` 实现了 `resume_agent` 工具的处理器，用于恢复一个已关闭（closed/shutdown）的子代理。这是多代理协作系统中的重要功能，允许父代理重新激活之前关闭的子代理，继续之前的对话上下文。

在多代理协作场景中，子代理可能因为完成任务而被关闭，但后续可能需要再次与其交互。`resume_agent` 工具允许从之前的 rollout 文件中恢复代理状态，使其能够继续处理新的输入。

## 功能点目的

1. **恢复已关闭代理**：从 rollout 文件中恢复之前关闭的子代理，重建其执行环境
2. **深度限制检查**：防止代理层级过深，避免无限递归创建子代理
3. **状态追踪**：返回恢复后代理的当前状态
4. **事件通知**：通过 `CollabResumeBeginEvent` 和 `CollabResumeEndEvent` 通知恢复操作的开始和结束
5. **无操作优化**：如果代理已经处于活动状态，直接返回当前状态而不进行恢复操作

## 具体技术实现

### 关键数据结构

```rust
// 恢复代理的参数
#[derive(Debug, Deserialize)]
struct ResumeAgentArgs {
    id: String,  // 目标代理的线程 ID
}

// 恢复操作的结果
#[derive(Debug, Deserialize, Serialize, PartialEq, Eq)]
pub(crate) struct ResumeAgentResult {
    pub(crate) status: AgentStatus,  // 恢复后的状态
}
```

### 关键流程

1. **参数解析与验证**：
   - 解析 `ResumeAgentArgs` 并验证代理 ID 格式
   - 获取目标代理的昵称和角色信息

2. **深度限制检查**：
   - 计算子代理的深度（`next_thread_spawn_depth`）
   - 检查是否超过配置的 `agent_max_depth` 限制
   - 如果超过限制，返回错误提示模型自行解决问题

3. **发送开始事件**：
   - 发送 `CollabResumeBeginEvent`，包含发送方和接收方信息

4. **状态检查与恢复**：
   - 查询代理当前状态
   - 如果状态为 `NotFound`（已关闭），调用 `try_resume_closed_agent` 进行恢复
   - 如果代理已存在，直接返回当前状态

5. **发送结束事件**：
   - 发送 `CollabResumeEndEvent`，包含恢复后的状态信息

6. **记录指标**：
   - 通过 `session_telemetry.counter` 记录恢复操作指标

### 恢复逻辑详解

```rust
async fn try_resume_closed_agent(
    session: &Arc<Session>,
    turn: &Arc<TurnContext>,
    receiver_thread_id: ThreadId,
    child_depth: i32,
) -> Result<AgentStatus, FunctionCallError> {
    // 1. 构建恢复配置
    let config = build_agent_resume_config(turn.as_ref(), child_depth)?;
    
    // 2. 调用 AgentControl 恢复代理
    let resumed_thread_id = session
        .services
        .agent_control
        .resume_agent_from_rollout(config, receiver_thread_id, session_source)
        .await
        .map_err(|err| collab_agent_error(receiver_thread_id, err))?;
    
    // 3. 返回恢复后的状态
    Ok(session.services.agent_control.get_status(resumed_thread_id).await)
}
```

### 配置构建

`build_agent_resume_config` 函数（定义在 `multi_agents.rs`）：
- 基于当前 turn 的配置创建基础配置
- 应用 spawn 代理的覆盖设置（深度限制相关的特性禁用）
- **注意**：恢复时 `base_instructions` 设置为 `None`，因为指令从 rollout/session 元数据中恢复

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/tools/handlers/multi_agents/resume_agent.rs` - 本文件

### 依赖文件
- `/home/sansha/Github/codex/codex-rs/core/src/tools/handlers/multi_agents.rs` - 父模块，提供配置构建函数和错误处理
- `/home/sansha/Github/codex/codex-rs/core/src/tools/registry.rs` - 工具注册表
- `/home/sansha/Github/codex/codex-rs/core/src/agent/control.rs` - `AgentControl`，提供 `resume_agent_from_rollout`
- `/home/sansha/Github/codex/codex-rs/core/src/agent/guards.rs` - 提供 `next_thread_spawn_depth` 和 `exceeds_thread_spawn_depth_limit`
- `/home/sansha/Github/codex/codex-rs/protocol/src/protocol.rs` - 协议事件定义

### 调用链
```
ToolRegistry::dispatch_any()
  -> ResumeAgentHandler::handle()
    -> next_thread_spawn_depth()  // 计算深度
    -> exceeds_thread_spawn_depth_limit()  // 检查深度限制
    -> AgentControl::get_status()  // 查询当前状态
    -> try_resume_closed_agent()
      -> build_agent_resume_config()  // 构建配置
      -> AgentControl::resume_agent_from_rollout()  // 恢复代理
    -> AgentControl::get_status()  // 获取恢复后状态
```

## 依赖与外部交互

### 服务依赖
- `session.services.agent_control`：用于恢复代理和查询状态
- `turn.session_telemetry`：用于记录指标

### 配置依赖
- `turn.config.agent_max_depth`：最大代理深度限制
- `turn.session_source`：当前会话来源，用于计算子代理深度

### 事件类型
- `CollabResumeBeginEvent`：恢复操作开始
- `CollabResumeEndEvent`：恢复操作结束

### 深度计算
深度计算基于 `SessionSource`：
```rust
pub(crate) fn next_thread_spawn_depth(session_source: &SessionSource) -> i32 {
    session_depth(session_source).saturating_add(1)
}
```

对于 `SubAgentSource::ThreadSpawn`，深度从父代理继承并递增。

## 风险、边界与改进建议

### 边界情况

1. **代理已存在**：如果代理已经处于活动状态（非 `NotFound`），处理器会直接返回当前状态，不进行任何操作
2. **恢复失败**：如果 rollout 文件损坏或丢失，恢复操作会失败，返回错误
3. **深度限制**：当达到 `agent_max_depth` 时，恢复操作会被拒绝，防止无限递归

### 风险点

1. **配置一致性**：恢复时代理的配置可能与关闭时不同，特别是模型和推理设置
2. **状态丢失**：虽然对话历史从 rollout 恢复，但某些运行时状态（如内存中的变量）可能丢失
3. **并发恢复**：如果多个父代理同时尝试恢复同一个子代理，可能导致竞态条件
4. **昵称冲突**：恢复时代理昵称的重新分配可能与之前不同

### 改进建议

1. **恢复验证**：恢复后验证代理状态是否与预期一致，如检查 rollout 完整性
2. **部分恢复**：支持从部分损坏的 rollout 恢复，保留可用的对话历史
3. **恢复回调**：添加恢复完成后的回调机制，允许执行额外的初始化逻辑
4. **恢复超时**：为恢复操作添加超时机制，避免长时间等待
5. **恢复重试**：在恢复失败时支持自动重试，特别是网络或存储相关的错误
6. **深度豁免**：为特定场景（如系统代理）提供深度限制豁免机制

### 测试覆盖

测试文件：`/home/sansha/Github/codex/codex-rs/core/src/tools/handlers/multi_agents_tests.rs`

相关测试：
- `resume_agent_rejects_invalid_id`：验证无效 ID 被拒绝
- `resume_agent_reports_missing_agent`：验证缺失代理的报告
- `resume_agent_noops_for_active_agent`：验证对已存在代理的无操作处理
- `resume_agent_restores_closed_agent_and_accepts_send_input`：验证恢复后代理可以接受输入
- `resume_agent_rejects_when_depth_limit_exceeded`：验证深度限制检查
