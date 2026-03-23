# mod.rs 研究文档

## 场景与职责

`mod.rs` 是 `codex-rs/core/src/tasks` 模块的核心文件，定义了 **SessionTask** trait 和任务管理框架。它是 Codex 会话中所有异步任务的统一抽象层，负责任务的生命周期管理、取消机制和指标收集。

### 核心职责
1. **任务抽象**：定义 `SessionTask` trait，统一所有任务类型接口
2. **生命周期管理**：`spawn_task`、`abort_all_tasks`、`on_task_finished`
3. **取消机制**：优雅和强制任务取消支持
4. **指标收集**：token 使用、工具调用、网络代理等指标
5. **任务协调**：管理活跃任务状态，处理任务替换和中断

### 任务类型
模块包含以下子任务实现：
- `compact.rs`：对话压缩任务
- `ghost_snapshot.rs`：Git 快照任务
- `regular.rs`：常规对话轮次任务
- `review.rs`：代码审查任务
- `undo.rs`：撤销/回滚任务
- `user_shell.rs`：用户 shell 命令任务

## 功能点目的

### 1. SessionTask Trait

```rust
#[async_trait]
pub(crate) trait SessionTask: Send + Sync + 'static {
    fn kind(&self) -> TaskKind;
    fn span_name(&self) -> &'static str;
    async fn run(... ) -> Option<String>;
    async fn abort(&self, ...);  // 默认空实现
}
```

**设计意图**：
- `kind()`：任务分类（Regular/Review/Compact），用于遥测和 UI
- `span_name()`：OpenTelemetry 追踪跨度名称
- `run()`：核心执行逻辑，返回可选的最终代理消息
- `abort()`：取消后的清理逻辑

### 2. 任务生命周期

```
spawn_task
  ├── abort_all_tasks (取消现有任务)
  ├── clear_connector_selection
  ├── sync_mcp_request_headers_for_turn
  ├── 创建 RunningTask
  ├── tokio::spawn (在独立任务中执行)
  └── register_new_active_task

任务执行
  ├── task.run() (用户代码)
  ├── flush_rollout
  ├── on_task_finished (如果未取消)
  └── notify_waiters

任务完成
  ├── 取消 git 富化任务
  ├── 处理 pending_input
  ├── 记录指标 (token, tool_calls, network_proxy)
  └── 发送 TurnComplete 事件
```

### 3. 取消机制

**优雅取消**：
```rust
async fn handle_task_abort(...) {
    task.cancellation_token.cancel();  // 发送取消信号
    select! {
        _ = task.done.notified() => {},  // 等待优雅完成
        _ = sleep(GRACEFULL_INTERRUPTION_TIMEOUT_MS) => {
            warn!("task didn't complete gracefully");
        }
    }
    task.handle.abort();  // 强制中止
    task.task.abort(...).await;  // 执行清理
}
```

**超时**：`GRACEFULL_INTERRUPTION_TIMEOUT_MS = 100ms`

### 4. 指标收集

| 指标 | 类型 | 说明 |
|------|------|------|
| `turn.e2e.duration` | Timer | 端到端轮次耗时 |
| `turn.network_proxy` | Counter | 网络代理使用情况 |
| `turn.token_usage` | Histogram | Token 使用量（按类型） |
| `turn.tool_call` | Histogram | 工具调用次数 |

## 具体技术实现

### 关键数据结构

```rust
/// 任务执行上下文
#[derive(Clone)]
pub(crate) struct SessionTaskContext {
    session: Arc<Session>,
}

/// 运行中的任务
pub(crate) struct RunningTask {
    pub(crate) done: Arc<Notify>,
    pub(crate) kind: TaskKind,
    pub(crate) task: Arc<dyn SessionTask>,
    pub(crate) cancellation_token: CancellationToken,
    pub(crate) handle: Arc<AbortOnDropHandle<()>>,
    pub(crate) turn_context: Arc<TurnContext>,
    pub(crate) _timer: Option<codex_otel::Timer>,
}

/// 任务类型枚举
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum TaskKind {
    Regular,
    Review,
    Compact,
}
```

### spawn_task 实现细节

```rust
pub async fn spawn_task<T: SessionTask>(
    self: &Arc<Self>,
    turn_context: Arc<TurnContext>,
    input: Vec<UserInput>,
    task: T,
)
```

**关键步骤**：

1. **前置清理**
   ```rust
   self.abort_all_tasks(TurnAbortReason::Replaced).await;
   self.clear_connector_selection().await;
   self.sync_mcp_request_headers_for_turn(turn_context.as_ref()).await;
   ```

2. **创建取消令牌和通知**
   ```rust
   let cancellation_token = CancellationToken::new();
   let done = Arc::new(Notify::new());
   ```

3. **启动计时器**
   ```rust
   let timer = turn_context
       .session_telemetry
       .start_timer(TURN_E2E_DURATION_METRIC, &[])
       .ok();
   ```

4. **生成任务**
   ```rust
   let handle = tokio::spawn(
       async move {
           let last_agent_message = task_for_run.run(...).await;
           sess.flush_rollout().await;
           if !task_cancellation_token.is_cancelled() {
               sess.on_task_finished(...).await;
           }
           done_clone.notify_waiters();
       }
       .instrument(task_span),
   );
   ```

5. **注册任务**
   ```rust
   let running_task = RunningTask { ... };
   self.register_new_active_task(running_task, token_usage_at_turn_start).await;
   ```

### abort_all_tasks 实现

```rust
pub async fn abort_all_tasks(self: &Arc<Self>, reason: TurnAbortReason)
```

**处理流程**：
1. 取出 `ActiveTurn`
2. 遍历并取消所有任务 (`handle_task_abort`)
3. 清除 pending 状态（审批、输入等）
4. 清除 MCP 请求头

### on_task_finished 实现

```rust
pub async fn on_task_finished(
    self: &Arc<Self>,
    turn_context: Arc<TurnContext>,
    last_agent_message: Option<String>,
)
```

**职责**：
1. 取消 git 富化任务
2. 从 `ActiveTurn` 移除任务
3. 处理 `pending_input`（通过 hook 运行时）
4. 计算并记录指标
5. 发送 `TurnComplete` 事件

## 关键代码路径与文件引用

### 调用路径示例

**常规对话**：
```
codex.rs:4564 (submit_user_input)
  → spawn_task(Arc<RegularTask>)
    → mod.rs:148-227
```

**用户 Shell**：
```
codex.rs:4592 (run_user_shell_command)
  → spawn_task(Arc<UserShellCommandTask>)
```

**压缩**：
```
codex.rs:4856 (compact)
  → spawn_task(Arc<CompactTask>)
```

**撤销**：
```
codex.rs:4849 (undo)
  → spawn_task(Arc<UndoTask>)
```

**审查**：
```
codex.rs:5321 (review)
  → spawn_task(Arc<ReviewTask>)
```

### 相关文件

| 文件 | 用途 |
|------|------|
| `codex-rs/core/src/tasks/mod.rs` | 本文件，任务框架（465行） |
| `codex-rs/core/src/tasks/mod_tests.rs` | 单元测试（114行） |
| `codex-rs/core/src/state/turn.rs` | `ActiveTurn`、`TaskKind`、`RunningTask` |
| `codex-rs/core/src/codex.rs` | `Session` 实现，任务调用方 |

## 依赖与外部交互

### 外部 crate
| Crate | 用途 |
|-------|------|
| `async_trait` | 异步 trait |
| `tokio::sync::Notify` | 任务完成通知 |
| `tokio_util::sync::CancellationToken` | 取消机制 |
| `tokio_util::task::AbortOnDropHandle` | 自动中止句柄 |
| `tracing::Instrument` | 追踪跨度 |
| `codex_otel` | 遥测指标 |
| `codex_protocol` | 协议类型 |

### 内部模块
```
mod.rs
  ├── mod compact/ghost_snapshot/regular/review/undo/user_shell
  ├── uses crate::codex::{Session, TurnContext}
  ├── uses crate::state::{ActiveTurn, RunningTask, TaskKind}
  ├── uses crate::hook_runtime (pending input 处理)
  └── uses crate::protocol (EventMsg, TurnCompleteEvent, ...)
```

## 风险、边界与改进建议

### 已知风险

1. **任务竞争**
   - `abort_all_tasks` 和 `spawn_task` 之间可能存在竞态条件
   - 当前通过 `active_turn` 锁保护，但需要仔细验证

2. **取消粒度**
   - 100ms 的优雅取消超时可能过短
   - 某些任务（如大文件操作）可能需要更长时间清理

3. **指标准确性**
   - token 使用计算依赖 `total_token_usage().await`
   - 如果并发修改可能产生不准确结果

### 边界条件

| 场景 | 处理 |
|------|------|
| 任务 panic | `AbortOnDropHandle` 确保清理 |
| 双重取消 | `is_cancelled()` 检查防止重复处理 |
| 空 pending_input | 直接跳过处理 |
| 任务替换 | 先取消旧任务，再创建新任务 |

### 改进建议

1. **可配置超时**
   ```rust
   // 按任务类型配置不同的优雅取消超时
   fn abort_timeout(&self) -> Duration {
       match self.kind() {
           TaskKind::Regular => Duration::from_millis(100),
           TaskKind::Compact => Duration::from_secs(5),
           TaskKind::Review => Duration::from_millis(100),
       }
   }
   ```

2. **任务队列**
   - 当前直接替换活跃任务
   - 考虑添加队列机制支持顺序执行

3. **更细粒度的指标**
   - 按任务类型区分指标
   - 添加任务取消率指标

4. **健康检查**
   - 监控任务执行时间异常
   - 自动报告卡死任务

5. **测试覆盖**
   - 当前 `mod_tests.rs` 仅测试 `emit_turn_network_proxy_metric`
   - 建议添加：
     - 任务生命周期测试
     - 取消机制测试
     - 并发任务测试
