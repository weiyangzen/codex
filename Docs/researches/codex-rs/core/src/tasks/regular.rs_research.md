# regular.rs 研究文档

## 场景与职责

`regular.rs` 实现了 **RegularTask**（常规对话任务），是 Codex 中最核心的任务类型。它处理用户输入的标准对话轮次，协调模型调用、事件流处理和对话历史管理。

### 核心职责
1. **对话轮次执行**：处理用户输入并生成模型响应
2. **生命周期事件**：发送 `TurnStarted` 和 `TurnComplete` 事件
3. **预热优化**：利用会话启动预热的客户端连接
4. **取消支持**：响应取消令牌，优雅终止执行

### 使用场景
- 用户发送普通消息（`Op::UserInput`）
- 带有设置更新的用户输入（`Op::UserInputWithSettingsUpdate`）
- 需要完整对话生命周期的标准交互

## 功能点目的

### 1. 标准对话轮次
RegularTask 实现了 Codex 的标准对话流程：
1. 发送 `TurnStarted` 事件
2. 消费预热的客户端会话（如有）
3. 调用 `run_turn` 执行实际对话
4. 返回最终代理消息（由框架统一发送 `TurnComplete`）

### 2. 预热优化
利用 `SessionStartupPrewarmResolution` 机制：
- **Cancelled**：任务被取消，直接返回
- **Unavailable**：无预热连接，创建新连接
- **Ready**：使用预热的客户端会话，减少延迟

### 3. 追踪集成
使用 `tracing::Instrument` 为任务执行附加追踪跨度：
```rust
.run_turn(...)
.instrument(run_turn_span)
.await
```

## 具体技术实现

### 关键数据结构

```rust
#[derive(Default)]
pub(crate) struct RegularTask;

impl RegularTask {
    pub(crate) fn new() -> Self {
        Self
    }
}
```

- 零大小类型（ZST），无内部状态
- 使用 `Default` derive 简化创建

### SessionTask 实现

```rust
#[async_trait]
impl SessionTask for RegularTask {
    fn kind(&self) -> TaskKind {
        TaskKind::Regular
    }

    fn span_name(&self) -> &'static str {
        "session_task.turn"
    }

    async fn run(
        self: Arc<Self>,
        session: Arc<SessionTaskContext>,
        ctx: Arc<TurnContext>,
        input: Vec<UserInput>,
        cancellation_token: CancellationToken,
    ) -> Option<String> {
        // 实现细节...
    }
}
```

### 核心执行流程

```rust
async fn run(...) -> Option<String> {
    let sess = session.clone_session();
    let run_turn_span = trace_span!("run_turn");
    
    // 1. 发送 TurnStarted 事件
    let event = EventMsg::TurnStarted(TurnStartedEvent {
        turn_id: ctx.sub_id.clone(),
        model_context_window: ctx.model_context_window(),
        collaboration_mode_kind: ctx.collaboration_mode.mode,
    });
    sess.send_event(ctx.as_ref(), event).await;
    
    // 2. 重置服务端 reasoning 标志
    sess.set_server_reasoning_included(/*included*/ false).await;
    
    // 3. 消费预热连接
    let prewarmed_client_session = match sess
        .consume_startup_prewarm_for_regular_turn(&cancellation_token)
        .await
    {
        SessionStartupPrewarmResolution::Cancelled => return None,
        SessionStartupPrewarmResolution::Unavailable { .. } => None,
        SessionStartupPrewarmResolution::Ready(prewarmed) => Some(*prewarmed),
    };
    
    // 4. 执行对话轮次
    run_turn(
        sess,
        ctx,
        input,
        prewarmed_client_session,
        cancellation_token,
    )
    .instrument(run_turn_span)
    .await
}
```

### 预热解析结果处理

| 结果 | 处理 | 返回值 |
|------|------|--------|
| `Cancelled` | 立即返回 | `None` |
| `Unavailable` | 使用 `None` 作为预热会话 | 继续执行 |
| `Ready` | 解包预热会话 | 继续执行 |

## 关键代码路径与文件引用

### 调用路径
```
codex.rs:4558-4569 (submit_user_input)
  → spawn_task(Arc<RegularTask>)
    → tasks/mod.rs:148-227 (spawn_task)
      → regular.rs:38-76 (RegularTask::run)
        → codex.rs:run_turn (实际对话执行)
```

### 相关文件
- `codex-rs/core/src/tasks/regular.rs`：本文件（76行）
- `codex-rs/core/src/tasks/mod.rs`：`SessionTask` trait 定义
- `codex-rs/core/src/codex.rs`：`run_turn` 函数，`Session::submit_user_input`
- `codex-rs/core/src/session_startup_prewarm.rs`：预热机制

### 依赖类型
- `codex_protocol::user_input::UserInput`：用户输入类型
- `codex_protocol::protocol::TurnStartedEvent`：生命周期事件
- `codex_protocol::protocol::EventMsg`：事件消息枚举
- `crate::session_startup_prewarm::SessionStartupPrewarmResolution`：预热解析
- `crate::codex::run_turn`：核心对话执行函数

## 依赖与外部交互

### 外部 crate
| Crate | 用途 |
|-------|------|
| `async_trait` | 异步 trait 支持 |
| `tokio_util::sync::CancellationToken` | 取消机制 |
| `tracing::Instrument` / `trace_span` | 追踪跨度 |
| `codex_protocol::user_input::UserInput` | 用户输入 |

### 内部模块
```
regular.rs
  ├── uses crate::codex::{TurnContext, run_turn}
  ├── uses crate::protocol::{EventMsg, TurnStartedEvent}
  ├── uses crate::session_startup_prewarm::SessionStartupPrewarmResolution
  ├── uses crate::state::TaskKind
  └── uses super::{SessionTask, SessionTaskContext}
```

### 事件发送
```rust
sess.send_event(ctx.as_ref(), EventMsg::TurnStarted(...)).await;
```

事件包含：
- `turn_id`：轮次唯一标识
- `model_context_window`：模型上下文窗口大小
- `collaboration_mode_kind`：协作模式类型

## 风险、边界与改进建议

### 已知风险

1. **预热竞争**
   - 多个快速连续的对话请求可能竞争预热连接
   - 当前实现确保只有一个请求能获得预热连接

2. **取消时机**
   - 如果在 `TurnStarted` 发送后、预热消费前取消，会浪费预热资源
   - 需要确保取消检查覆盖所有关键路径

3. **错误传播**
   - `run_turn` 的错误处理在函数内部完成
   - 返回值 `Option<String>` 仅用于最终代理消息

### 边界条件

| 场景 | 处理 |
|------|------|
| 空输入 | 传递给 `run_turn` 处理 |
| 预热取消 | 立即返回 `None` |
| 取消令牌触发 | `run_turn` 内部处理取消 |
| 模型不可用 | `run_turn` 返回错误事件 |

### 改进建议

1. **预热状态暴露**
   ```rust
   // 添加指标或事件报告预热使用情况
   sess.session_telemetry.counter(
       "codex.prewarm.usage",
       1,
       &[("status", if prewarmed.is_some() { "hit" } else { "miss" })],
   );
   ```

2. **延迟启动优化**
   - 当前 `TurnStarted` 在预热消费前发送
   - 考虑将预热等待纳入 Turn 计时

3. **重试机制**
   - 预热消费失败时考虑重试
   - 区分临时错误和永久错误

4. **测试覆盖**
   - 当前无专门测试文件
   - 建议添加：
     - 预热命中/未命中场景
     - 取消时机测试
     - 事件发送验证

5. **性能监控**
   - 添加预热消费耗时指标
   - 监控 `run_turn` 执行时间分布
