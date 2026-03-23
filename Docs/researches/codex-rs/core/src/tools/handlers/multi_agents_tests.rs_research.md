# multi_agents_tests.rs 研究文档

## 场景与职责

`multi_agents_tests.rs` 是 `codex-rs/core/src/tools/handlers/multi_agents.rs` 的配套测试文件，负责验证多智能体协作工具（spawn_agent、send_input、resume_agent、wait_agent、close_agent）的完整行为。这些测试确保子智能体生命周期管理、配置继承、深度限制和沙箱策略等核心功能的正确性。

## 功能点目的

### 1. 基础 Handler 验证
- **payload 类型校验**: 确保 handler 只接受 Function 类型的 payload，拒绝 Custom 类型
- **空消息校验**: 验证 spawn_agent 和 send_input 拒绝空消息
- **互斥参数校验**: 验证 message 和 items 不能同时提供

### 2. 智能体生命周期测试
- **spawn_agent**: 验证智能体创建、配置继承、角色应用
- **send_input**: 验证向现有智能体发送输入、支持中断标志
- **resume_agent**: 验证恢复已关闭的智能体
- **wait_agent**: 验证等待多个智能体达到最终状态
- **close_agent**: 验证关闭智能体并返回之前状态

### 3. 深度限制测试
- 验证超过 `agent_max_depth` 时拒绝创建子智能体
- 验证在允许深度范围内可以正常创建

### 4. 配置继承验证
- 验证子智能体继承父智能体的运行时配置（approval_policy、sandbox_policy、model_provider 等）
- 验证角色特定配置正确应用

## 具体技术实现

### 测试基础设施

```rust
// 辅助函数：创建 ToolInvocation
fn invocation(
    session: Arc<crate::codex::Session>,
    turn: Arc<TurnContext>,
    tool_name: &str,
    payload: ToolPayload,
) -> ToolInvocation

// 辅助函数：创建 Function payload
fn function_payload(args: serde_json::Value) -> ToolPayload

// 辅助函数：创建 ThreadManager
fn thread_manager() -> ThreadManager

// 辅助函数：提取文本输出
fn expect_text_output<T>(output: T) -> (String, Option<bool>)
```

### 关键测试用例

| 测试用例 | 目的 | 关键断言 |
|---------|------|---------|
| `handler_rejects_non_function_payloads` | 验证 payload 类型检查 | 返回 `FunctionCallError::RespondToModel` |
| `spawn_agent_rejects_empty_message` | 验证空消息拒绝 | 错误消息包含 "Empty message" |
| `spawn_agent_uses_explorer_role_and_preserves_approval_policy` | 验证角色和策略继承 | 子智能体配置与父智能体一致 |
| `spawn_agent_rejects_when_depth_limit_exceeded` | 验证深度限制 | 返回 "Agent depth limit reached" |
| `send_input_interrupts_before_prompt` | 验证中断功能 | 先发送 Interrupt，再发送 UserInput |
| `resume_agent_restores_closed_agent_and_accepts_send_input` | 验证恢复功能 | 关闭后可恢复并能接收输入 |
| `wait_agent_times_out_when_status_is_not_final` | 验证等待超时 | `timed_out: true` |
| `close_agent_submits_shutdown_and_returns_previous_status` | 验证关闭功能 | 发送 Shutdown op，返回之前状态 |

### 配置构建测试

```rust
// 验证 build_agent_spawn_config 使用 turn 上下文值
async fn build_agent_spawn_config_uses_turn_context_values

// 验证 resume 配置清除 base_instructions
async fn build_agent_resume_config_clears_base_instructions
```

## 关键代码路径与文件引用

### 被测试的主要文件
- `codex-rs/core/src/tools/handlers/multi_agents.rs` - 主模块
- `codex-rs/core/src/tools/handlers/multi_agents/spawn.rs` - spawn_agent 实现
- `codex-rs/core/src/tools/handlers/multi_agents/send_input.rs` - send_input 实现
- `codex-rs/core/src/tools/handlers/multi_agents/resume_agent.rs` - resume_agent 实现
- `codex-rs/core/src/tools/handlers/multi_agents/wait.rs` - wait_agent 实现
- `codex-rs/core/src/tools/handlers/multi_agents/close_agent.rs` - close_agent 实现

### 依赖类型
```rust
use crate::agent::AgentStatus;
use crate::protocol::SessionSource;
use crate::protocol::SubAgentSource;
use codex_protocol::ThreadId;
use codex_protocol::protocol::InitialHistory;
use codex_protocol::protocol::RolloutItem;
```

### 测试使用的 Mock/辅助
- `make_session_and_context()` - 创建测试会话和上下文
- `ThreadManager::with_models_provider_for_tests` - 测试用的线程管理器
- `manager.captured_ops()` - 捕获的操作日志验证

## 依赖与外部交互

### 外部依赖
1. **ThreadManager**: 管理智能体线程生命周期
2. **AgentControl**: 控制智能体的 spawn、send_input、shutdown 等操作
3. **Session/TurnContext**: 提供执行上下文
4. **CodexAuth**: 认证管理

### 协议依赖
- `codex_protocol::protocol::Op` - 操作类型（Interrupt、UserInput、Shutdown）
- `codex_protocol::user_input::UserInput` - 输入项类型
- `codex_protocol::models::ContentItem` - 内容项

## 风险、边界与改进建议

### 潜在风险
1. **并发安全**: 测试中使用 `Arc<Mutex<TurnDiffTracker>>`，需要确保多线程安全
2. **超时敏感**: `wait_agent_clamps_short_timeouts_to_minimum` 测试依赖时间，可能有 flaky 风险
3. **资源清理**: 测试创建的智能体需要确保正确关闭，避免资源泄漏

### 边界情况
1. **深度限制边界**: 测试验证了 `depth == max_depth` 时拒绝，但未测试 `depth == max_depth - 1` 时允许
2. **UUID 格式**: 测试验证了无效 UUID 被拒绝，但只测试了 "not-a-uuid" 一种情况
3. **空 items**: `send_input_accepts_structured_items` 测试了正常 items，但未测试空 items 边界

### 改进建议
1. **增加并发测试**: 添加多个智能体同时 spawn/wait 的并发场景测试
2. **增加错误恢复测试**: 测试网络中断、服务不可用等情况下的错误处理
3. **增加性能基准**: 添加大规模智能体创建的性能测试
4. **完善边界覆盖**: 增加更多边界值测试（如最小/最大 timeout、空配置等）
5. **提取公共设置**: 多个测试使用相似的 session/turn 设置，可以提取为 fixtures

### 代码质量观察
- 测试代码使用了 `pretty_assertions::assert_eq` 提供更好的 diff 输出
- 使用了 `tokio::time::timeout` 防止测试挂起
- 测试命名清晰，遵循 `snake_case` 且描述性强
