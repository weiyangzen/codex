# hook_runtime.rs 研究文档

## 场景与职责

`hook_runtime.rs` 是 Codex 核心库中的 **Hook 系统运行时协调层**，负责在会话生命周期关键节点执行用户配置的 Hook 脚本，并处理 Hook 的输出结果（包括上下文注入、流程控制等）。该模块架起了 `codex_hooks` crate 与核心会话管理之间的桥梁。

**核心职责：**
1. **Session Start Hook 执行**：在会话启动/恢复时执行 Hook
2. **User Prompt Submit Hook 执行**：在用户提交提示时执行 Hook
3. **Hook 结果处理**：解析 Hook 输出，决定是否阻止操作、注入上下文
4. **事件发射**：向客户端报告 Hook 执行状态（开始/完成）
5. **上下文管理**：将 Hook 产生的附加上下文转换为开发者消息

**在架构中的位置：**
```
┌─────────────────┐
│   codex_hooks   │  ← Hook 引擎实现（registry/engine/dispatcher）
└────────┬────────┘
         │
┌────────▼────────┐
│  hook_runtime   │  ← 本文件：协调层，转换结果格式
└────────┬────────┘
         │
┌────────▼────────┐
│  codex::Session │  ← 核心会话管理
└─────────────────┘
```

## 功能点目的

### 1. Session Start Hook 运行时 (`run_pending_session_start_hooks`)

**目的**：在会话启动时执行配置好的 Session Start Hook，允许在对话开始前执行初始化逻辑或阻止会话启动。

**执行流程：**
1. 从 Session 获取待处理的 `session_start_source`（Startup 或 Resume）
2. 构建 `SessionStartRequest`，包含会话 ID、工作目录、模型、权限模式等
3. 调用 Hook 引擎的 `preview_session_start` 获取即将执行的 Hook 列表
4. 调用 `run_context_injecting_hook` 执行 Hook 并处理结果
5. 将附加上下文记录到会话中

**关键代码：**
```rust
pub(crate) async fn run_pending_session_start_hooks(
    sess: &Arc<Session>,
    turn_context: &Arc<TurnContext>,
) -> bool {
    let Some(session_start_source) = sess.take_pending_session_start_source().await else {
        return false;
    };
    let request = codex_hooks::SessionStartRequest { ... };
    let preview_runs = sess.hooks().preview_session_start(&request);
    run_context_injecting_hook(...).await.record_additional_contexts(sess, turn_context).await
}
```

### 2. User Prompt Submit Hook 运行时 (`run_user_prompt_submit_hooks`)

**目的**：在用户提交提示时执行 Hook，支持内容审查、添加上下文、阻止不当输入等。

**执行流程：**
1. 构建 `UserPromptSubmitRequest`，包含 prompt 内容
2. 获取预览列表并执行 Hook
3. 返回 `HookRuntimeOutcome`，包含是否阻止及附加上下文

**与 Session Start Hook 的区别：**
- 每个用户输入都会触发（而非仅会话开始）
- 支持阻止特定输入（Block 状态）
- 返回结果被用于决定是否接受用户输入

### 3. 待处理输入检查 (`inspect_pending_input`)

**目的**：检查待处理的用户输入，决定接受或阻止。

**决策逻辑：**
```rust
pub(crate) enum PendingInputHookDisposition {
    Accepted(Box<PendingInputRecord>),  // 接受，可能附带额外上下文
    Blocked { additional_contexts: Vec<String> },  // 阻止，返回原因
}
```

**流程：**
1. 将 `ResponseInputItem` 转换为 `ResponseItem`
2. 如果是用户消息，执行 `run_user_prompt_submit_hooks`
3. 根据 `should_stop` 决定接受或阻止
4. 阻止时返回 `Blocked`，接受时返回 `Accepted` 并记录附加上下文

### 4. 上下文注入与记录

**目的**：将 Hook 产生的附加上下文转换为模型可见的开发者消息。

**转换流程：**
```rust
fn additional_context_messages(additional_contexts: Vec<String>) -> Vec<ResponseItem> {
    additional_contexts
        .into_iter()
        .map(|ctx| DeveloperInstructions::new(ctx).into())
        .collect()
}
```

每个附加上下文字符串被包装为 `DeveloperInstructions`，然后转换为 `ResponseItem::Message`，角色为 `developer`。

### 5. 事件发射

**目的**：向客户端报告 Hook 执行的生命周期事件。

**事件类型：**
- `HookStarted`：Hook 开始执行时发射，包含 `HookRunSummary`
- `HookCompleted`：Hook 执行完成时发射，包含执行结果、状态、输出条目

## 具体技术实现

### 核心数据结构

```rust
/// Hook 执行结果
pub(crate) struct HookRuntimeOutcome {
    pub should_stop: bool,              // 是否阻止后续操作
    pub additional_contexts: Vec<String>, // 要注入模型的附加上下文
}

/// 待处理输入的处理结果
pub(crate) enum PendingInputHookDisposition {
    Accepted(Box<PendingInputRecord>),
    Blocked { additional_contexts: Vec<String> },
}

/// 被接受的输入记录
pub(crate) enum PendingInputRecord {
    UserMessage {
        content: Vec<UserInput>,
        response_item: ResponseItem,
        additional_contexts: Vec<String>,
    },
    ConversationItem {
        response_item: ResponseItem,
    },
}

/// 内部使用的 Hook 结果包装（用于类型转换）
struct ContextInjectingHookOutcome {
    hook_events: Vec<HookCompletedEvent>,
    outcome: HookRuntimeOutcome,
}
```

### 类型转换实现

```rust
// 从 codex_hooks::SessionStartOutcome 转换
impl From<SessionStartOutcome> for ContextInjectingHookOutcome {
    fn from(value: SessionStartOutcome) -> Self {
        Self {
            hook_events: value.hook_events,
            outcome: HookRuntimeOutcome {
                should_stop: value.should_stop,
                additional_contexts: value.additional_contexts,
            },
        }
    }
}

// 从 codex_hooks::UserPromptSubmitOutcome 转换
impl From<UserPromptSubmitOutcome> for ContextInjectingHookOutcome {
    fn from(value: UserPromptSubmitOutcome) -> Self {
        // 类似结构...
    }
}
```

### 通用 Hook 执行框架

```rust
async fn run_context_injecting_hook<Fut, Outcome>(
    sess: &Arc<Session>,
    turn_context: &Arc<TurnContext>,
    preview_runs: Vec<HookRunSummary>,      // 预览信息（用于 started 事件）
    outcome_future: Fut,                     // Hook 执行 Future
) -> HookRuntimeOutcome
where
    Fut: Future<Output = Outcome>,
    Outcome: Into<ContextInjectingHookOutcome>,
{
    // 1. 发射 started 事件
    emit_hook_started_events(sess, turn_context, preview_runs).await;
    
    // 2. 执行 Hook
    let outcome = outcome_future.await.into();
    
    // 3. 发射 completed 事件
    emit_hook_completed_events(sess, turn_context, outcome.hook_events).await;
    
    outcome.outcome
}
```

### 权限模式映射

```rust
fn hook_permission_mode(turn_context: &TurnContext) -> String {
    match turn_context.approval_policy.value() {
        AskForApproval::Never => "bypassPermissions",
        AskForApproval::UnlessTrusted
        | AskForApproval::OnFailure
        | AskForApproval::OnRequest
        | AskForApproval::Granular(_) => "default",
    }
    .to_string()
}
```

将内部权限策略映射为 Hook 可理解的字符串模式。

## 关键代码路径与文件引用

### 本文件内部调用图

```
hook_runtime.rs
├── run_pending_session_start_hooks
│   ├── sess.take_pending_session_start_source()
│   ├── sess.hooks().preview_session_start()
│   └── run_context_injecting_hook
│       ├── emit_hook_started_events
│       ├── outcome_future.await (调用 codex_hooks)
│       └── emit_hook_completed_events
├── run_user_prompt_submit_hooks
│   ├── sess.hooks().preview_user_prompt_submit()
│   └── run_context_injecting_hook
├── inspect_pending_input
│   ├── parse_turn_item
│   └── run_user_prompt_submit_hooks
├── record_pending_input
│   └── sess.record_user_prompt_and_emit_turn_item / record_conversation_items
└── record_additional_contexts
    └── additional_context_messages → DeveloperInstructions
```

### 跨文件依赖

**上游调用方（谁调用了 hook_runtime）：**
| 调用方 | 调用函数 | 场景 |
|--------|----------|------|
| `codex.rs` | `run_pending_session_start_hooks` | 会话启动/恢复时 |
| `tasks/mod.rs` | `inspect_pending_input` | 处理用户输入时 |
| `tasks/mod.rs` | `record_pending_input` | 接受用户输入后 |

**下游依赖（hook_runtime 调用了谁）：**
| 被调用方 | 用途 |
|----------|------|
| `codex_hooks::Hooks` | 执行实际 Hook 逻辑 |
| `codex_hooks::SessionStartRequest` | 构建请求参数 |
| `codex_hooks::UserPromptSubmitRequest` | 构建请求参数 |
| `Session::record_user_prompt_and_emit_turn_item` | 记录用户输入 |
| `Session::record_conversation_items` | 记录对话项 |
| `Session::send_event` | 发射事件 |

### 相关文件

| 文件路径 | 关系 |
|----------|------|
| `/home/sansha/Github/codex/codex-rs/core/src/codex.rs` | 调用 Session Start Hook |
| `/home/sansha/Github/codex/codex-rs/core/src/tasks/mod.rs` | 调用 Prompt Submit Hook |
| `/home/sansha/Github/codex/codex-rs/hooks/src/lib.rs` | Hook 系统公共接口 |
| `/home/sansha/Github/codex/codex-rs/hooks/src/registry.rs` | Hooks 注册表实现 |
| `/home/sansha/Github/codex/codex-rs/hooks/src/events/session_start.rs` | Session Start 事件处理 |
| `/home/sansha/Github/codex/codex-rs/hooks/src/events/user_prompt_submit.rs` | User Prompt 事件处理 |

## 依赖与外部交互

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_hooks` | Hook 引擎核心实现 |
| `codex_protocol` | 协议类型（TurnItem, ResponseItem, EventMsg 等） |
| `tokio` | 异步运行时 |
| `std::sync::Arc` | 共享所有权 |

### 协议类型依赖

```rust
use codex_protocol::items::TurnItem;
use codex_protocol::models::DeveloperInstructions;
use codex_protocol::models::ResponseInputItem;
use codex_protocol::models::ResponseItem;
use codex_protocol::protocol::AskForApproval;
use codex_protocol::protocol::EventMsg;
use codex_protocol::protocol::HookCompletedEvent;
use codex_protocol::protocol::HookRunSummary;
use codex_protocol::user_input::UserInput;
```

### 核心模块依赖

```rust
use crate::codex::Session;
use crate::codex::TurnContext;
use crate::event_mapping::parse_turn_item;
```

## 风险、边界与改进建议

### 已知风险

1. **Hook 执行阻塞**
   - Hook 执行是同步等待的（`.await`）
   - **风险**：长时间运行的 Hook 会阻塞用户输入处理
   - **缓解**：Hook 引擎内部有超时机制（timeout_sec）

2. **上下文注入顺序**
   - 当前实现中，多个 Hook 的附加上下文按顺序注入
   - **风险**：如果 Hook A 阻止但 Hook B 产生上下文，B 的上下文仍会被注入
   - **现状**：代码中 `should_stop` 是聚合结果（`any`），但上下文是全部收集

3. **内存泄漏风险**
   - `PendingInputRecord` 使用 `Box` 包装
   - 在接受路径中需要确保正确释放

4. **错误处理简化**
   - Hook 执行错误主要记录到事件流，不阻止主流程
   - **风险**：Hook 持续失败可能无感知

### 边界情况

| 边界情况 | 处理 | 说明 |
|----------|------|------|
| 无 Hook 配置 | ✅ | 快速返回，不执行 |
| Hook 返回空上下文 | ✅ | 跳过记录 |
| 多个 Hook 产生上下文 | ✅ | 按顺序全部注入 |
| Hook 阻止 + 上下文 | ✅ | 阻止操作，但上下文仍记录 |
| 序列化失败 | ✅ | 返回失败状态的事件 |

### 改进建议

1. **Hook 并行执行**
   ```rust
   // 当前：顺序执行
   // 建议：独立 Hook 可并行执行，减少延迟
   let results = futures::future::join_all(handlers.iter().map(|h| async {
       // 执行单个 Hook
   })).await;
   ```

2. **上下文去重**
   ```rust
   // 建议：相同内容的上下文避免重复注入
   let unique_contexts: HashSet<String> = additional_contexts.into_iter().collect();
   ```

3. **Hook 执行指标**
   ```rust
   // 建议：添加 Hook 执行时间指标，便于监控
   tracing::info!(hook_name = %name, duration_ms = %elapsed, "hook executed");
   ```

4. **更细粒度的阻止控制**
   ```rust
   // 当前：should_stop 是 bool
   // 建议：支持部分阻止（如仅阻止特定工具调用）
   pub enum StopAction {
       Continue,
       BlockInput,
       BlockTools(Vec<String>),
   }
   ```

5. **Hook 结果缓存**
   - 对于重复的输入，考虑缓存 Hook 结果
   - 需要设计缓存失效策略（如基于文件修改时间）

### 测试覆盖

当前测试主要验证：
- `additional_context_messages` 正确转换消息格式
- 多个上下文保持独立和顺序

**建议增加的测试：**
1. Hook 阻止逻辑测试
2. 并发 Hook 执行测试
3. 错误恢复测试
4. 大上下文负载测试

### 维护注意事项

1. **与 codex_hooks 的耦合**：本模块紧密依赖 `codex_hooks` crate 的接口，升级时需注意兼容性
2. **事件格式稳定性**：`HookStarted`/`HookCompleted` 事件格式影响客户端，修改需谨慎
3. **权限模式映射**：新增权限策略时需同步更新 `hook_permission_mode` 函数
