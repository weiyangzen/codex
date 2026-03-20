# codex-rs/core/src/tasks 目录研究文档

## 概述

`codex-rs/core/src/tasks` 目录是 Codex Core 的任务执行子系统，负责管理会话（Session）中各类异步任务的定义、调度和生命周期管理。该模块实现了多种任务类型，包括常规对话、代码审查、历史压缩、撤销操作、用户 Shell 命令执行以及 Git 快照等。

---

## 场景与职责

### 核心职责

1. **任务抽象与统一接口**：通过 `SessionTask` trait 为所有任务类型提供统一的异步执行接口
2. **任务生命周期管理**：处理任务的创建、执行、取消、完成和资源清理
3. **任务调度协调**：确保同一时间只有一个活跃任务（互斥执行），支持任务中断和替换
4. **事件流驱动**：通过事件机制将任务执行状态反馈给客户端

### 业务场景

| 场景 | 任务类型 | 说明 |
|------|----------|------|
| 常规 AI 对话 | `RegularTask` | 处理用户与 AI 的常规对话交互 |
| 代码审查 | `ReviewTask` | 启动子代理对代码进行审查分析 |
| 历史压缩 | `CompactTask` | 压缩对话历史，减少 Token 消耗 |
| 撤销操作 | `UndoTask` | 恢复到之前的 Git 快照状态 |
| 用户 Shell 命令 | `UserShellCommandTask` | 执行用户输入的 Shell 命令 |
| Git 快照 | `GhostSnapshotTask` | 在后台创建 Git 快照用于撤销 |

---

## 功能点目的

### 1. SessionTask Trait（任务抽象）

**目的**：为所有任务提供统一的接口契约，使 Session 可以以统一方式调度不同类型的任务。

**核心方法**：
- `kind()`：返回任务类型（Regular/Review/Compact）
- `span_name()`：返回 tracing span 名称用于可观测性
- `run()`：执行任务的核心逻辑
- `abort()`：任务取消时的清理逻辑

### 2. RegularTask（常规对话任务）

**目的**：处理标准的用户-AI 对话流程。

**关键行为**：
- 发射 `TurnStarted` 事件通知客户端对话开始
- 消费启动预热的模型客户端会话（如果有）
- 调用 `run_turn()` 执行实际的模型交互循环
- 支持优雅的任务取消

### 3. ReviewTask（代码审查任务）

**目的**：启动独立的子代理对代码进行审查，提供结构化的审查结果。

**关键行为**：
- 创建子代理配置，禁用某些功能（Web 搜索、CSV 生成、协作工具）
- 设置专门的审查提示词（`REVIEW_PROMPT`）
- 通过 `run_codex_thread_one_shot` 启动一次性子代理
- 处理子代理事件流，解析审查输出
- 发射 `ExitedReviewMode` 事件并记录审查结果到对话历史

### 4. CompactTask（历史压缩任务）

**目的**：压缩对话历史，将多轮对话总结为摘要，减少 Token 消耗。

**关键行为**：
- 根据提供商类型选择本地或远程压缩（OpenAI 使用远程压缩）
- 调用 `compact::run_compact_task` 或 `compact_remote::run_remote_compact_task`
- 记录压缩类型指标（local/remote）

### 5. UndoTask（撤销任务）

**目的**：将代码库恢复到之前的 Ghost Snapshot 状态。

**关键行为**：
- 在对话历史中查找最近的 `GhostSnapshot` 项
- 使用 `codex_git::restore_ghost_commit_with_options` 恢复 Git 状态
- 成功后从历史中移除已恢复的快照项
- 发射 `UndoStarted` 和 `UndoCompleted` 事件

### 6. UserShellCommandTask（用户 Shell 命令任务）

**目的**：执行用户输入的 Shell 命令，支持独立执行或作为活跃回合的辅助执行。

**关键行为**：
- 支持两种模式：`StandaloneTurn`（独立生命周期）和 `ActiveTurnAuxiliary`（辅助模式）
- 解析命令并在用户默认 Shell 中执行
- 支持沙箱策略配置（默认 `DangerFullAccess`）
- 发射 `ExecCommandBegin` 和 `ExecCommandEnd` 事件
- 将命令输出持久化到对话历史

### 7. GhostSnapshotTask（Git 快照任务）

**目的**：在后台创建 Git 快照，为撤销功能提供恢复点。

**关键行为**：
- 使用 `ReadinessFlag` 协调与工具调用的时序
- 在阻塞线程池中执行 Git 操作（`create_ghost_commit_with_report`）
- 240 秒超时警告，提示用户可能存在大文件
- 生成大未跟踪文件/目录的警告信息
- 将快照记录到对话历史

---

## 具体技术实现

### 关键流程

#### 任务创建与调度流程（`spawn_task`）

```rust
// 1. 终止所有现有任务
self.abort_all_tasks(TurnAbortReason::Replaced).await;

// 2. 创建取消令牌和完成通知
let cancellation_token = CancellationToken::new();
let done = Arc::new(Notify::new());

// 3. 在 Tokio 任务中执行
let handle = tokio::spawn(async move {
    let last_agent_message = task_for_run.run(...).await;
    sess.flush_rollout().await;
    if !task_cancellation_token.is_cancelled() {
        sess.on_task_finished(...).await;
    }
    done_clone.notify_waiters();
});

// 4. 注册为活跃任务
let running_task = RunningTask { ... };
self.register_new_active_task(running_task, token_usage_at_turn_start).await;
```

#### 任务取消流程（`abort_all_tasks`）

```rust
// 1. 获取活跃回合
if let Some(mut active_turn) = self.take_active_turn().await {
    // 2. 遍历并取消所有任务
    for task in active_turn.drain_tasks() {
        self.handle_task_abort(task, reason.clone()).await;
    }
    // 3. 清理待处理状态
    active_turn.clear_pending().await;
}
```

#### 任务取消处理（`handle_task_abort`）

```rust
// 1. 触发取消令牌
task.cancellation_token.cancel();

// 2. 等待任务优雅完成（100ms 超时）
select! {
    _ = task.done.notified() => {},
    _ = tokio::time::sleep(Duration::from_millis(100)) => {
        warn!("task didn't complete gracefully");
    }
}

// 3. 强制中止任务句柄
task.handle.abort();

// 4. 调用任务特定的清理逻辑
session_task.abort(session_ctx, turn_context).await;

// 5. 如果是中断，记录中断标记到历史
if reason == TurnAbortReason::Interrupted {
    // 记录 turn_aborted 标记...
}

// 6. 发射 TurnAborted 事件
```

### 关键数据结构

#### SessionTaskContext

```rust
#[derive(Clone)]
pub(crate) struct SessionTaskContext {
    session: Arc<Session>,
}
```

任务执行上下文，封装 Session 的部分能力，提供对认证管理器、模型管理器的访问。

#### RunningTask

```rust
pub(crate) struct RunningTask {
    pub(crate) done: Arc<Notify>,                    // 完成通知
    pub(crate) kind: TaskKind,                       // 任务类型
    pub(crate) task: Arc<dyn SessionTask>,          // 任务实例
    pub(crate) cancellation_token: CancellationToken, // 取消令牌
    pub(crate) handle: Arc<AbortOnDropHandle<()>>,  // 任务句柄
    pub(crate) turn_context: Arc<TurnContext>,      // 回合上下文
    pub(crate) _timer: Option<codex_otel::Timer>,   // 计时器
}
```

#### TaskKind（任务类型枚举）

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum TaskKind {
    Regular,  // 常规对话
    Review,   // 代码审查
    Compact,  // 历史压缩
}
```

#### UserShellCommandMode（Shell 命令模式）

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum UserShellCommandMode {
    StandaloneTurn,       // 独立回合生命周期
    ActiveTurnAuxiliary,  // 活跃回合辅助执行
}
```

### 协议与事件

任务系统涉及的关键事件类型：

| 事件 | 方向 | 说明 |
|------|------|------|
| `TurnStarted` | Server → Client | 回合开始 |
| `TurnComplete` | Server → Client | 回合完成 |
| `TurnAborted` | Server → Client | 回合中止 |
| `ExecCommandBegin` | Server → Client | Shell 命令开始执行 |
| `ExecCommandEnd` | Server → Client | Shell 命令执行结束 |
| `UndoStarted` / `UndoCompleted` | Server → Client | 撤销操作状态 |
| `ExitedReviewMode` | Server → Client | 退出审查模式 |
| `WarningEvent` | Server → Client | 警告信息（如快照超时） |

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `mod.rs` | 465 | 任务模块入口，定义 `SessionTask` trait 和 `spawn_task`/`abort_all_tasks` |
| `regular.rs` | 76 | `RegularTask` 实现，常规对话任务 |
| `review.rs` | 273 | `ReviewTask` 实现，代码审查任务 |
| `compact.rs` | 49 | `CompactTask` 实现，历史压缩任务 |
| `undo.rs` | 131 | `UndoTask` 实现，撤销操作任务 |
| `user_shell.rs` | 357 | `UserShellCommandTask` 实现，Shell 命令执行 |
| `ghost_snapshot.rs` | 254 | `GhostSnapshotTask` 实现，Git 快照任务 |
| `mod_tests.rs` | 114 | 模块单元测试（网络代理指标） |
| `ghost_snapshot_tests.rs` | 31 | Ghost Snapshot 单元测试 |

### 关键代码路径

#### 任务调度路径

```
codex.rs:submit_user_input() 
  → spawn_task() [mod.rs:148]
    → abort_all_tasks() [清理现有任务]
    → tokio::spawn() [启动新任务]
    → register_new_active_task()
```

#### 任务取消路径

```
abort_all_tasks() [mod.rs:229]
  → take_active_turn()
  → handle_task_abort() [每个任务]
    → cancellation_token.cancel()
    → select! { done.notified() / sleep(100ms) }
    → handle.abort()
    → task.abort() [任务特定清理]
    → send_event(TurnAborted)
```

#### 审查任务路径

```
codex.rs:enter_review_mode() [~5315]
  → spawn_task(tc, input, ReviewTask::new())
    → review.rs:start_review_conversation()
      → run_codex_thread_one_shot() [创建子代理]
      → process_review_events() [处理事件流]
        → parse_review_output_event() [解析输出]
    → exit_review_mode() [发送 ExitedReviewMode]
```

#### Ghost Snapshot 路径

```
codex.rs:maybe_start_ghost_snapshot() [~3786]
  → GhostSnapshotTask::new(token)
  → task.run()
    → tokio::task::spawn_blocking()
      → create_ghost_commit_with_report()
    → format_snapshot_warnings() [格式化警告]
    → record_conversation_items() [记录快照]
```

---

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::codex::Session` | 会话管理，历史记录，事件发送 |
| `crate::codex::TurnContext` | 回合上下文，配置，模型信息 |
| `crate::state::{ActiveTurn, RunningTask, TaskKind}` | 任务状态管理 |
| `crate::protocol::EventMsg` | 事件消息定义 |
| `crate::compact` / `crate::compact_remote` | 历史压缩实现 |
| `crate::exec` / `crate::sandboxing` | 命令执行和沙箱 |

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `async_trait` | 异步 trait 支持 |
| `tokio` / `tokio_util` | 异步运行时，取消令牌，任务句柄 |
| `tracing` | 日志和可观测性 |
| `codex_protocol` | 协议类型（UserInput, ResponseItem 等） |
| `codex_git` | Git 操作（Ghost Snapshot, Undo） |
| `codex_otel` | 遥测指标收集 |
| `codex_utils_readiness` | ReadinessFlag 用于任务协调 |

### 与 Session 的交互

```rust
// Session 提供的能力
impl Session {
    pub async fn spawn_task<T: SessionTask>(...)  // 启动任务
    pub async fn abort_all_tasks(reason)          // 取消所有任务
    pub async fn on_task_finished(...)            // 任务完成回调
    pub async fn send_event(...)                  // 发送事件
    pub async fn record_conversation_items(...)   // 记录到历史
}
```

---

## 风险、边界与改进建议

### 已知风险

1. **任务取消竞争条件**
   - 100ms 的优雅取消超时可能不足以完成清理
   - 强制中止可能导致资源泄漏
   - 代码位置：`mod.rs:420`

2. **Ghost Snapshot 阻塞**
   - Git 操作在阻塞线程池执行，但仍可能耗时过长
   - 大仓库可能导致 240+ 秒的延迟警告
   - 代码位置：`ghost_snapshot.rs:87-91`

3. **Review Task 子代理隔离**
   - 子代理配置禁用某些功能，但依赖配置克隆
   - 如果父配置变更，可能存在隔离失效风险
   - 代码位置：`review.rs:94-104`

4. **Shell 命令安全风险**
   - 默认使用 `DangerFullAccess` 沙箱策略
   - 用户 Shell 命令可能执行任意代码
   - 代码位置：`user_shell.rs:156`

### 边界情况

1. **任务替换**：新任务启动时会取消现有任务，可能导致客户端状态不一致
2. **取消传播**：取消令牌通过 `child_token()` 传递，确保层级取消
3. **历史操作**：Undo 操作直接修改对话历史，需要确保原子性
4. **并发限制**：`spawn_task` 确保单任务执行，但 `execute_user_shell_command` 函数可并发调用

### 改进建议

1. **可配置取消超时**
   ```rust
   // 当前硬编码 100ms
   const GRACEFULL_INTERRUPTION_TIMEOUT_MS: u64 = 100;
   // 建议改为配置项
   ```

2. **Review Task 完整生命周期**
   - 当前 Review Task 不发射 `TurnStarted`，与常规任务不一致
   - 建议添加完整生命周期事件（代码中已有 TODO）
   - 代码位置：`codex.rs:5318-5320`

3. **Ghost Snapshot 异步化**
   - 考虑使用 `git2` 的异步 API 或更细粒度的阻塞控制
   - 添加进度报告机制

4. **任务优先级**
   - 当前所有任务平等，可考虑为 Ghost Snapshot 添加低优先级标记
   - 避免快照影响用户交互响应

5. **错误处理增强**
   - `UndoTask` 中 Git 错误分类较粗，可细化错误类型
   - 添加更多可恢复错误场景的处理

6. **指标完善**
   - 当前仅记录任务计数，可添加：
     - 任务执行时长分布
     - 取消原因统计
     - 各任务类型成功率

---

## 总结

`codex-rs/core/src/tasks` 模块是 Codex Core 的任务调度核心，通过 `SessionTask` trait 提供统一的任务抽象，支持多种任务类型的并发安全执行。模块设计遵循以下原则：

1. **单一活跃任务**：通过 `ActiveTurn` 确保同一时间只有一个任务执行
2. **优雅取消**：使用 `CancellationToken` 实现协作式取消
3. **事件驱动**：通过事件机制与客户端通信，保持松耦合
4. **资源清理**：每个任务有机会在取消时执行清理逻辑

该模块的稳定性直接影响用户体验，特别是在任务取消、历史压缩和撤销等关键操作上。
