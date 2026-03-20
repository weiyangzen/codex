# DIR codex-rs/core/src/tasks 研究文档

## 概述

`codex-rs/core/src/tasks` 是 Codex 核心库中负责管理会话任务（Session Task）的模块。该模块实现了多种任务类型，用于驱动 Codex 会话的不同工作流，包括常规对话、代码审查、历史压缩、撤销操作和用户 Shell 命令执行等。

---

## 场景与职责

### 核心职责

1. **任务抽象与调度**：定义 `SessionTask` trait，为所有任务提供统一的接口，包括任务类型标识、执行和取消机制
2. **任务生命周期管理**：管理任务的创建、执行、取消和清理全过程
3. **多种工作流支持**：实现不同类型的任务以支持 Codex 的多样化功能
4. **取消与中断处理**：提供优雅的任务取消机制，支持超时和强制终止

### 使用场景

| 任务类型 | 使用场景 |
|---------|---------|
| `RegularTask` | 常规用户对话回合，处理模型交互和工具调用 |
| `ReviewTask` | 代码审查模式，启动子代理进行代码审查 |
| `CompactTask` | 历史压缩，减少对话历史 token 占用 |
| `UndoTask` | 撤销操作，恢复到之前的 Ghost Snapshot |
| `UserShellCommandTask` | 执行用户 Shell 命令（如 `/shell` 命令） |
| `GhostSnapshotTask` | 创建 Git 仓库的 Ghost Snapshot 用于撤销 |

---

## 功能点目的

### 1. SessionTask Trait - 任务抽象接口

定义在 `mod.rs` 中的核心 trait，所有任务必须实现：

```rust
#[async_trait]
pub(crate) trait SessionTask: Send + Sync + 'static {
    fn kind(&self) -> TaskKind;  // 任务类型标识
    fn span_name(&self) -> &'static str;  // 追踪 span 名称
    
    async fn run(
        self: Arc<Self>,
        session: Arc<SessionTaskContext>,
        ctx: Arc<TurnContext>,
        input: Vec<UserInput>,
        cancellation_token: CancellationToken,
    ) -> Option<String>;  // 返回最后的 agent 消息
    
    async fn abort(&self, session: Arc<SessionTaskContext>, ctx: Arc<TurnContext>);  // 取消清理
}
```

### 2. TaskKind - 任务类型枚举

```rust
pub(crate) enum TaskKind {
    Regular,  // 常规任务
    Review,   // 审查任务
    Compact,  // 压缩任务
}
```

### 3. 任务执行上下文

- **SessionTaskContext**：包装 Session 的轻量级上下文，提供任务执行所需的服务访问
- **TurnContext**：回合级别的上下文，包含模型信息、配置、工作目录等
- **CancellationToken**：用于任务取消的信号机制

---

## 具体技术实现

### 关键流程

#### 1. 任务创建与启动流程 (`Session::spawn_task`)

```rust
pub async fn spawn_task<T: SessionTask>(
    self: &Arc<Self>,
    turn_context: Arc<TurnContext>,
    input: Vec<UserInput>,
    task: T,
) {
    // 1. 中止所有现有任务
    self.abort_all_tasks(TurnAbortReason::Replaced).await;
    
    // 2. 创建取消令牌和完成通知
    let cancellation_token = CancellationToken::new();
    let done = Arc::new(Notify::new());
    
    // 3. 在 Tokio 任务中执行
    let handle = tokio::spawn(async move {
        let last_agent_message = task.run(...).await;
        sess.flush_rollout().await;
        if !cancelled {
            sess.on_task_finished(ctx, last_agent_message).await;
        }
        done.notify_waiters();
    });
    
    // 4. 注册为活动任务
    self.register_new_active_task(running_task, token_usage).await;
}
```

#### 2. 任务取消流程 (`Session::abort_all_tasks`)

```rust
pub async fn abort_all_tasks(self: &Arc<Self>, reason: TurnAbortReason) {
    if let Some(mut active_turn) = self.take_active_turn().await {
        for task in active_turn.drain_tasks() {
            self.handle_task_abort(task, reason.clone()).await;
        }
        // 清理待处理的审批和输入
        active_turn.clear_pending().await;
    }
}
```

#### 3. RegularTask 执行流程

```rust
async fn run(...) -> Option<String> {
    // 1. 发送 TurnStarted 事件
    sess.send_event(ctx, EventMsg::TurnStarted(...)).await;
    
    // 2. 消费启动预热会话（如果可用）
    let prewarmed = match sess.consume_startup_prewarm(...).await {
        SessionStartupPrewarmResolution::Ready(session) => Some(session),
        _ => None,
    };
    
    // 3. 执行核心回合逻辑
    run_turn(sess, ctx, input, prewarmed, cancellation_token).await
}
```

#### 4. ReviewTask 执行流程

```rust
async fn run(...) -> Option<String> {
    // 1. 启动审查对话（子代理）
    let receiver = start_review_conversation(session, ctx, input, cancellation).await?;
    
    // 2. 处理审查事件流
    let output = process_review_events(session, ctx, receiver).await;
    
    // 3. 退出审查模式
    if !cancelled {
        exit_review_mode(session, output, ctx).await;
    }
    None
}
```

审查任务的特殊处理：
- 禁用 Web 搜索和协作工具
- 设置审查专用提示词 (`REVIEW_PROMPT`)
- 审批策略设为永不审批
- 使用独立的审查模型

#### 5. CompactTask 执行流程

```rust
async fn run(...) -> Option<String> {
    // 根据 provider 选择本地或远程压缩
    if should_use_remote_compact_task(&ctx.provider) {
        crate::compact_remote::run_remote_compact_task(session, ctx).await
    } else {
        crate::compact::run_compact_task(session, ctx, input).await
    }
}
```

#### 6. UndoTask 执行流程

```rust
async fn run(...) -> Option<String> {
    // 1. 发送 UndoStarted 事件
    sess.send_event(ctx, EventMsg::UndoStarted(...)).await;
    
    // 2. 查找最近的 Ghost Snapshot
    let (idx, ghost_commit) = history.iter().enumerate().rev()
        .find_map(|(i, item)| match item {
            ResponseItem::GhostSnapshot { ghost_commit } => Some((i, ghost_commit)),
            _ => None,
        })?;
    
    // 3. 恢复 Ghost Commit
    let result = tokio::task::spawn_blocking(|| {
        restore_ghost_commit_with_options(&options, &ghost_commit)
    }).await;
    
    // 4. 更新历史记录
    if result.is_ok() {
        items.remove(idx);
        sess.replace_history(items, reference_context).await;
    }
    
    // 5. 发送 UndoCompleted 事件
    sess.send_event(ctx, EventMsg::UndoCompleted(...)).await;
}
```

#### 7. UserShellCommandTask 执行流程

```rust
async fn run(...) -> Option<String> {
    execute_user_shell_command(
        session,
        turn_context,
        self.command.clone(),
        cancellation_token,
        UserShellCommandMode::StandaloneTurn,
    ).await;
    None
}
```

执行过程：
- 支持 StandaloneTurn 和 ActiveTurnAuxiliary 两种模式
- 使用用户默认 Shell 执行命令
- 支持管道、重定向等 Shell 特性
- 1小时超时限制
- 记录执行结果到对话历史

#### 8. GhostSnapshotTask 执行流程

```rust
async fn run(...) -> Option<String> {
    tokio::task::spawn(async move {
        // 1. 启动超时警告任务（240秒后）
        if warnings_enabled {
            tokio::task::spawn(async move {
                tokio::select! {
                    _ = tokio::time::sleep(SNAPSHOT_WARNING_THRESHOLD) => {
                        // 发送警告：快照耗时过长
                    }
                    _ = snapshot_done_rx => {}
                    _ = cancellation_token.cancelled() => {}
                }
            });
        }
        
        // 2. 在阻塞线程池中创建 Ghost Commit
        let result = tokio::task::spawn_blocking(|| {
            create_ghost_commit_with_report(&options)
        }).await;
        
        // 3. 处理结果并记录到历史
        match result {
            Ok(Ok((ghost_commit, report))) => {
                // 记录 GhostSnapshot 到对话历史
                session.record_conversation_items(&[ResponseItem::GhostSnapshot { ghost_commit }]).await;
                
                // 发送大文件警告（如果有）
                for message in format_snapshot_warnings(...) {
                    session.send_event(&ctx, EventMsg::Warning(...)).await;
                }
            }
            // 处理错误...
        }
        
        // 4. 标记工具调用门就绪
        ctx.tool_call_gate.mark_ready(token).await;
    });
    None
}
```

### 关键数据结构

#### RunningTask - 运行中任务结构

```rust
pub(crate) struct RunningTask {
    pub(crate) done: Arc<Notify>,                           // 完成通知
    pub(crate) kind: TaskKind,                              // 任务类型
    pub(crate) task: Arc<dyn SessionTask>,                  // 任务实例
    pub(crate) cancellation_token: CancellationToken,       // 取消令牌
    pub(crate) handle: Arc<AbortOnDropHandle<()>>,         // 任务句柄
    pub(crate) turn_context: Arc<TurnContext>,             // 回合上下文
    pub(crate) _timer: Option<codex_otel::Timer>,          // 计时器
}
```

#### ActiveTurn - 活动回合状态

```rust
pub(crate) struct ActiveTurn {
    pub(crate) tasks: IndexMap<String, RunningTask>,        // 任务映射表
    pub(crate) turn_state: Arc<Mutex<TurnState>>,          // 回合状态
}
```

#### TurnState - 回合可变状态

```rust
pub(crate) struct TurnState {
    pending_approvals: HashMap<String, oneshot::Sender<ReviewDecision>>,
    pending_request_permissions: HashMap<String, oneshot::Sender<RequestPermissionsResponse>>,
    pending_user_input: HashMap<String, oneshot::Sender<RequestUserInputResponse>>,
    pending_elicitations: HashMap<(String, RequestId), oneshot::Sender<ElicitationResponse>>,
    pending_dynamic_tools: HashMap<String, oneshot::Sender<DynamicToolResponse>>,
    pending_input: Vec<ResponseInputItem>,
    granted_permissions: Option<PermissionProfile>,
    pub(crate) tool_calls: u64,
    pub(crate) token_usage_at_turn_start: TokenUsage,
}
```

### 协议与事件

任务模块通过事件系统与客户端通信：

- **TurnStarted**：回合开始
- **TurnComplete**：回合完成
- **TurnAborted**：回合中止
- **UndoStarted/UndoCompleted**：撤销开始/完成
- **ExecCommandBegin/ExecCommandEnd**：命令执行开始/结束
- **Warning**：警告信息

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|-----|------|
| `mod.rs` | 任务模块入口，定义 `SessionTask` trait 和 `Session::spawn_task` |
| `regular.rs` | 常规对话任务实现 |
| `review.rs` | 代码审查任务实现 |
| `compact.rs` | 历史压缩任务实现 |
| `undo.rs` | 撤销操作任务实现 |
| `user_shell.rs` | 用户 Shell 命令任务实现 |
| `ghost_snapshot.rs` | Ghost Snapshot 创建任务实现 |

### 测试文件

| 文件 | 职责 |
|-----|------|
| `mod_tests.rs` | 模块单元测试（网络代理指标） |
| `ghost_snapshot_tests.rs` | Ghost Snapshot 功能测试 |

### 依赖文件

| 文件 | 职责 |
|-----|------|
| `../state/turn.rs` | `ActiveTurn`、`RunningTask`、`TaskKind` 定义 |
| `../state/mod.rs` | 状态模块导出 |
| `../codex.rs` | `Session` 实现、`run_turn` 函数 |
| `../codex_delegate.rs` | 子代理线程管理 |
| `../compact.rs` | 本地压缩实现 |
| `../compact_remote.rs` | 远程压缩实现 |
| `../review_format.rs` | 审查结果格式化 |
| `../user_shell_command.rs` | Shell 命令输出格式化 |

---

## 依赖与外部交互

### 内部依赖

```
tasks/
├── mod.rs
│   ├── crate::codex::Session
│   ├── crate::codex::TurnContext
│   ├── crate::state::{ActiveTurn, RunningTask, TaskKind}
│   ├── crate::protocol::EventMsg
│   └── codex_protocol::user_input::UserInput
├── regular.rs
│   ├── crate::codex::run_turn
│   └── crate::session_startup_prewarm::SessionStartupPrewarmResolution
├── review.rs
│   ├── crate::codex_delegate::run_codex_thread_one_shot
│   ├── crate::review_format::format_review_findings_block
│   └── crate::client_common::REVIEW_PROMPT
├── compact.rs
│   ├── crate::compact::should_use_remote_compact_task
│   ├── crate::compact::run_compact_task
│   └── crate::compact_remote::run_remote_compact_task
├── undo.rs
│   └── codex_git::restore_ghost_commit_with_options
├── user_shell.rs
│   ├── crate::exec::execute_exec_request
│   ├── crate::user_shell_command::user_shell_command_record_item
│   └── codex_protocol::models::ResponseItem
└── ghost_snapshot.rs
    ├── codex_git::create_ghost_commit_with_report
    └── codex_utils_readiness::Token
```

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `async-trait` | 异步 trait 支持 |
| `tokio` | 异步运行时、任务管理 |
| `tokio-util` | `CancellationToken`、`AbortOnDropHandle` |
| `tracing` | 日志和追踪 |
| `uuid` | UUID 生成 |
| `codex_protocol` | 协议类型（UserInput、ResponseItem、Event 等） |
| `codex_git` | Git 操作（Ghost Commit 创建/恢复） |
| `codex_otel` | 遥测和指标 |
| `codex_utils_readiness` | 就绪状态管理 |

---

## 风险、边界与改进建议

### 已知风险

1. **任务取消竞争条件**
   - 在 `handle_task_abort` 中，任务可能在取消信号和完成通知之间完成
   - 使用 `select!` 处理优雅取消超时（100ms），但可能不够某些长时间运行的任务

2. **Ghost Snapshot 性能问题**
   - 大型未跟踪文件会导致快照耗时过长（> 240秒）
   - 已实现警告机制，但用户可能忽略

3. **Undo 操作的原子性**
   - 撤销操作涉及 Git 操作和历史记录修改，不是原子操作
   - 如果在中途失败，可能处于不一致状态

4. **Shell 命令执行安全**
   - `UserShellCommandTask` 使用 `SandboxPolicy::DangerFullAccess`
   - 用户命令在没有任何沙箱限制下执行

### 边界条件

1. **并发任务限制**
   - 同一时刻只能有一个活动回合（ActiveTurn）
   - 新任务启动会自动取消现有任务

2. **取消超时**
   - 优雅取消超时为 100ms (`GRACEFULL_INTERRUPTION_TIMEOUT_MS`)
   - 超时后强制中止任务句柄

3. **Shell 命令超时**
   - 用户 Shell 命令硬编码 1 小时超时 (`USER_SHELL_TIMEOUT_MS`)

4. **历史记录大小**
   - 压缩任务在上下文窗口超限时可能多次重试
   - 每次重试移除最旧的历史项

### 改进建议

1. **任务取消改进**
   - 考虑为不同类型任务配置不同的取消超时
   - 实现更细粒度的取消检查点

2. **错误处理增强**
   - 为 Ghost Snapshot 失败提供更详细的错误分类
   - 添加自动重试机制

3. **性能优化**
   - 考虑对 Ghost Snapshot 使用增量快照
   - 压缩任务支持流式处理大历史记录

4. **可观测性**
   - 为每个任务类型添加更详细的指标
   - 实现任务执行时间的直方图统计

5. **代码结构**
   - `mod.rs` 文件较长（465行），可考虑将 `Session` 的任务相关方法提取到单独模块
   - 任务取消逻辑可以进一步抽象，减少重复代码

---

## 附录：关键常量和配置

```rust
// 优雅取消超时（毫秒）
const GRACEFULL_INTERRUPTION_TIMEOUT_MS: u64 = 100;

// 用户 Shell 命令超时（毫秒）- 1小时
const USER_SHELL_TIMEOUT_MS: u64 = 60 * 60 * 1000;

// Ghost Snapshot 警告阈值（秒）- 4分钟
const SNAPSHOT_WARNING_THRESHOLD: Duration = Duration::from_secs(240);

// 用户中断后的指导消息
const TURN_ABORTED_INTERRUPTED_GUIDANCE: &str = "The user interrupted the previous turn on purpose...";
```

---

*文档生成时间：2026-03-21*
*研究范围：codex-rs/core/src/tasks/*
