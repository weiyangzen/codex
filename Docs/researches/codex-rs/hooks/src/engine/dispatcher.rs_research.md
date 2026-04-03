# dispatcher.rs 深度研究文档

## 场景与职责

`dispatcher.rs` 是 Codex Hooks 系统的**调度与执行协调器**，负责 Handler 的选择过滤、并发执行协调、执行状态管理和结果聚合。它是 Hooks 执行流程的"指挥中心"，承担着以下关键职责：

1. **Handler 选择**：根据事件类型和匹配条件筛选适用的 Handler
2. **并发执行**：使用 `futures::future::join_all` 并行执行多个 Handler
3. **状态管理**：构建运行中（Running）和已完成（Completed）的执行摘要
4. **结果聚合**：收集多个 Handler 的执行结果并返回给上层

该模块是连接"配置发现"与"命令执行"的关键枢纽，实现了 Hook 的**声明式调度**（配置决定执行顺序和条件）。

## 功能点目的

### 1. 执行结果封装 (`ParsedHandler<T>`)

```rust
#[derive(Debug)]
pub(crate) struct ParsedHandler<T> {
    pub completed: HookCompletedEvent,  // 协议层完成事件
    pub data: T,                         // 业务层解析数据
}
```

**设计意图**：
- 分离协议层（`HookCompletedEvent`）与业务层（`T`）数据
- 支持不同事件类型的自定义解析结果（`SessionStartHandlerData`, `UserPromptSubmitHandlerData`, `StopHandlerData`）
- 泛型设计确保类型安全

### 2. Handler 选择 (`select_handlers`)

**选择逻辑**：
```rust
pub(crate) fn select_handlers(
    handlers: &[ConfiguredHandler],
    event_name: HookEventName,
    matcher_input: Option<&str>,
) -> Vec<ConfiguredHandler> {
    handlers
        .iter()
        .filter(|handler| handler.event_name == event_name)
        .filter(|handler| match event_name {
            HookEventName::SessionStart => match (&handler.matcher, matcher_input) {
                (Some(matcher), Some(input)) => regex::Regex::new(matcher)
                    .map(|regex| regex.is_match(input))
                    .unwrap_or(false),
                (None, _) => true,
                _ => false,
            },
            HookEventName::UserPromptSubmit | HookEventName::Stop => true,
        })
        .cloned()
        .collect()
}
```

**设计决策**：
- **SessionStart 支持条件匹配**：通过正则匹配 `startup`/`resume` 等来源
- **其他事件无条件执行**：简化逻辑，确保每次事件都触发
- **防御性编程**：正则编译失败时返回 `false`（已在 discovery 阶段验证）

### 3. 运行中状态构建 (`running_summary`)

```rust
pub(crate) fn running_summary(handler: &ConfiguredHandler) -> HookRunSummary {
    HookRunSummary {
        id: handler.run_id(),
        event_name: handler.event_name,
        handler_type: HookHandlerType::Command,
        execution_mode: HookExecutionMode::Sync,  // 当前仅支持同步
        scope: scope_for_event(handler.event_name),
        source_path: handler.source_path.clone(),
        display_order: handler.display_order,
        status: HookRunStatus::Running,
        status_message: handler.status_message.clone(),
        started_at: chrono::Utc::now().timestamp(),
        completed_at: None,
        duration_ms: None,
        entries: Vec::new(),
    }
}
```

**状态机设计**：
```
Running → Completed/Failed/Blocked/Stopped
```

**作用域映射**：
| 事件类型 | 作用域 | 说明 |
|---------|-------|------|
| SessionStart | Thread | 会话级，影响整个对话 |
| UserPromptSubmit | Turn | 回合级，仅影响当前输入 |
| Stop | Turn | 回合级，仅影响当前停止事件 |

### 4. 并发执行 (`execute_handlers`)

```rust
pub(crate) async fn execute_handlers<T>(
    shell: &CommandShell,
    handlers: Vec<ConfiguredHandler>,
    input_json: String,
    cwd: &Path,
    turn_id: Option<String>,
    parse: fn(&ConfiguredHandler, CommandRunResult, Option<String>) -> ParsedHandler<T>,
) -> Vec<ParsedHandler<T>> {
    let results = join_all(
        handlers
            .iter()
            .map(|handler| run_command(shell, handler, &input_json, cwd)),
    )
    .await;

    handlers
        .into_iter()
        .zip(results)
        .map(|(handler, result)| parse(&handler, result, turn_id.clone()))
        .collect()
}
```

**并发模型**：
- 使用 `join_all` 实现真正的并行执行
- 所有 Handler 接收相同的 `input_json`
- 每个 Handler 独立解析结果（通过 `parse` 回调函数）

**函数指针设计**：
- 使用 `fn` 而非闭包，确保编译时确定调用目标
- 不同事件类型传入不同的解析函数

### 5. 完成状态构建 (`completed_summary`)

```rust
pub(crate) fn completed_summary(
    handler: &ConfiguredHandler,
    run_result: &CommandRunResult,
    status: HookRunStatus,
    entries: Vec<HookOutputEntry>,
) -> HookRunSummary {
    HookRunSummary {
        id: handler.run_id(),
        // ... 其他字段从 handler/run_result 复制
        status,
        completed_at: Some(run_result.completed_at),
        duration_ms: Some(run_result.duration_ms),
        entries,
    }
}
```

**时间计算**：
- `started_at` 来自 `command_runner`（进程启动时间）
- `completed_at` 和 `duration_ms` 来自 `CommandRunResult`
- 确保与底层执行的时间记录一致

## 具体技术实现

### Handler ID 生成

```rust
// ConfiguredHandler::run_id()
pub fn run_id(&self) -> String {
    format!(
        "{}:{}:{}",
        self.event_name_label(),
        self.display_order,
        self.source_path.display()
    )
}
```

**ID 格式**：`{event_name}:{display_order}:{source_path}`
- 确保全局唯一性
- 包含调试信息（来源文件）
- 人类可读

### 并发执行流程

```
输入: handlers[H1, H2, H3], input_json, cwd
    ↓
[并发执行]
├── run_command(shell, H1, input_json, cwd) → Result1
├── run_command(shell, H2, input_json, cwd) → Result2
└── run_command(shell, H3, input_json, cwd) → Result3
    ↓
[结果配对]
(H1, Result1) → parse(H1, Result1, turn_id) → ParsedHandler1
(H2, Result2) → parse(H2, Result2, turn_id) → ParsedHandler2
(H3, Result3) → parse(H3, Result3, turn_id) → ParsedHandler3
    ↓
输出: [ParsedHandler1, ParsedHandler2, ParsedHandler3]
```

### 错误隔离

```rust
// join_all 的行为：所有 future 都完成后才返回
// 即使某个 Handler 失败，其他 Handler 仍会执行
let results = join_all(...).await;

// 每个 Handler 的错误在 parse 函数中处理
// 不会导致整个执行流程中断
```

## 关键代码路径与文件引用

### 当前文件结构

```
codex-rs/hooks/src/engine/dispatcher.rs
├── ParsedHandler<T> (struct) - 结果封装
├── select_handlers (fn) - Handler 选择
├── running_summary (fn) - 运行中状态
├── execute_handlers (async fn) - 并发执行
├── completed_summary (fn) - 完成状态
└── scope_for_event (fn) - 作用域映射
```

### 调用方（上游）

```
codex-rs/hooks/src/events/session_start.rs
├── preview() → select_handlers() + running_summary()
└── run() → select_handlers() + execute_handlers()

codex-rs/hooks/src/events/user_prompt_submit.rs
├── preview() → select_handlers() + running_summary()
└── run() → select_handlers() + execute_handlers()

codex-rs/hooks/src/events/stop.rs
├── preview() → select_handlers() + running_summary()
└── run() → select_handlers() + execute_handlers()
```

### 被调用方（下游）

```
codex-rs/hooks/src/engine/command_runner.rs
└── run_command() - 实际执行命令

codex-rs/protocol/src/protocol.rs
├── HookCompletedEvent
├── HookRunSummary
├── HookRunStatus
├── HookHandlerType
├── HookExecutionMode
└── HookScope
```

## 依赖与外部交互

### 外部依赖

| Crate | 用途 |
|-------|------|
| `futures` | `join_all` 并发执行 |
| `chrono` | 时间戳生成 |
| `regex` | SessionStart 正则匹配 |
| `codex_protocol` | 协议类型定义 |

### 输入依赖

| 来源 | 类型 | 用途 |
|-----|------|------|
| `discovery` | `Vec<ConfiguredHandler>` | 可执行的 Handler 列表 |
| `events/*` | `SessionStartRequest` 等 | 事件上下文 |
| `mod.rs` | `CommandShell` | Shell 执行环境 |

### 输出消费

| 消费者 | 消费内容 |
|-------|---------|
| `session_start::run` | `Vec<ParsedHandler<SessionStartHandlerData>>` |
| `user_prompt_submit::run` | `Vec<ParsedHandler<UserPromptSubmitHandlerData>>` |
| `stop::run` | `Vec<ParsedHandler<StopHandlerData>>` |

## 风险、边界与改进建议

### 已知风险

1. **并发资源竞争**
   - 所有 Handler 共享相同的 `input_json` 和 `cwd`
   - 如果 Handler 修改工作目录或环境变量，可能影响其他 Handler
   - **建议**：考虑使用进程隔离或环境变量快照

2. **无并发限制**
   - `join_all` 会同时启动所有 Handler
   - 大量 Handler 时可能导致系统资源耗尽
   - **建议**：添加并发限制（如 `FuturesUnordered` + semaphore）

3. **正则重复编译**
   - `select_handlers` 中每次调用都重新编译正则
   - 虽然 `discovery` 已验证，但仍浪费 CPU
   - **建议**：在 `ConfiguredHandler` 中缓存编译后的正则

### 边界情况

| 场景 | 当前行为 | 评估 |
|-----|---------|------|
| Handler 列表为空 | `select_handlers` 返回空 Vec，上层处理 | ✅ 合理 |
| 所有 Handler 匹配失败 | 返回空 Vec，事件正常继续 | ✅ 合理 |
| 单个 Handler 超时 | 仅该 Handler 超时，其他继续 | ✅ 合理 |
| Handler 执行 panic | 可能导致整个 `join_all` 失败 | ⚠️ 需验证 |
| 相同 ID 的 Handler | 可能产生冲突 | ⚠️ 需确保唯一性 |

### 改进建议

1. **并发控制**
   ```rust
   use tokio::sync::Semaphore;
   
   let semaphore = Arc::new(Semaphore::new(10));  // 最多 10 个并发
   let futures = handlers.iter().map(|handler| {
       let permit = semaphore.clone().acquire_owned().await?;
       async move {
           let result = run_command(...).await;
           drop(permit);
           result
       }
   });
   ```

2. **正则缓存**
   ```rust
   pub(crate) struct ConfiguredHandler {
       // ... 现有字段
       cached_matcher: Option<Regex>,  // 预编译的正则
   }
   ```

3. **执行隔离**
   - 为每个 Handler 创建临时工作目录副本
   - 使用环境变量快照和恢复
   - 考虑使用容器/沙箱隔离

4. **可观测性增强**
   ```rust
   // 添加执行追踪
   pub struct ExecutionTrace {
       pub handler_id: String,
       pub started_at: Instant,
       pub completed_at: Instant,
       pub events: Vec<TraceEvent>,
   }
   ```

### 测试覆盖

当前测试：
- `select_handlers_keeps_duplicate_stop_handlers` - 验证重复 Handler 保留
- `select_handlers_keeps_overlapping_session_start_matchers` - 验证重叠匹配器
- `user_prompt_submit_ignores_matcher` - 验证 UserPromptSubmit 忽略匹配器
- `select_handlers_preserves_declaration_order` - 验证声明顺序保留

建议添加：
- 并发执行测试（验证真正的并行性）
- 错误隔离测试（单个失败不影响其他）
- 性能测试（大量 Handler 的吞吐量）

### 相关文件

- **命令执行**: `codex-rs/hooks/src/engine/command_runner.rs`
- **引擎核心**: `codex-rs/hooks/src/engine/mod.rs`
- **事件处理**: `codex-rs/hooks/src/events/*.rs`
- **协议定义**: `codex-rs/protocol/src/protocol.rs`
