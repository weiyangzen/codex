# parallel.rs 深度研究文档

## 场景与职责

`parallel.rs` 实现工具调用的并行执行管理，是 Codex 工具运行时系统的并发控制层。主要职责包括：

1. **并行执行控制**：管理多个工具调用的并发执行
2. **串行化保证**：对于不支持并行的工具，确保串行执行
3. **取消机制**：支持通过 CancellationToken 取消正在执行的工具调用
4. **结果转换**：将工具执行结果转换为协议层响应格式

该模块位于工具路由层 (`ToolRouter`) 和具体工具实现之间，是连接同步调用接口和异步执行模型的桥梁。

## 功能点目的

### 1. 工具调用运行时 (ToolCallRuntime)

```rust
pub(crate) struct ToolCallRuntime {
    router: Arc<ToolRouter>,
    session: Arc<Session>,
    turn_context: Arc<TurnContext>,
    tracker: SharedTurnDiffTracker,
    parallel_execution: Arc<RwLock<()>>,
}
```

- **router**: 工具路由，负责分发到具体工具处理器
- **session**: 会话状态，包含服务配置和状态
- **turn_context**: 当前回合上下文
- **tracker**: 回合差异跟踪器，用于追踪文件变更
- **parallel_execution**: 并行执行锁，控制并发访问

### 2. 并行 vs 串行执行

```rust
let _guard = if supports_parallel {
    Either::Left(lock.read().await)  // 共享读锁，允许多个并行
} else {
    Either::Right(lock.write().await) // 独占写锁，强制串行
};
```

- **并行工具**：获取读锁，多个工具可同时执行
- **非并行工具**：获取写锁，确保同一时间只有一个工具执行

### 3. 取消支持

```rust
tokio::select! {
    _ = cancellation_token.cancelled() => {
        // 返回取消响应
    },
    res = async { /* 实际执行 */ } => res,
}
```

使用 `tokio::select!` 同时监听取消信号和执行完成。

### 4. 结果处理

- **成功**：转换为 `ResponseInputItem`
- **致命错误**：转换为 `CodexErr::Fatal`
- **可恢复错误**：转换为失败响应返回给模型

## 具体技术实现

### 核心执行流程

```
┌─────────────────────────────────────────────────────────────────┐
│              ToolCallRuntime::handle_tool_call()                 │
├─────────────────────────────────────────────────────────────────┤
│ 1. 克隆调用信息 (error_call)                                     │
│ 2. 调用 handle_tool_call_with_source()                          │
│ 3. 转换结果：                                                    │
│    ├─ Ok(response) → Ok(response.into_response())              │
│    ├─ Err(Fatal) → Err(CodexErr::Fatal)                        │
│    └─ Err(other) → Ok(failure_response(error_call, other))     │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│           ToolCallRuntime::handle_tool_call_with_source()        │
├─────────────────────────────────────────────────────────────────┤
│ 1. 检查工具是否支持并行                                          │
│ 2. 创建 dispatch_span (用于 tracing)                           │
│ 3. 在 AbortOnDropHandle 中 spawn 异步任务                       │
│ 4. tokio::select! 监听取消或执行完成                            │
│ 5. 获取适当的锁 (读锁/写锁)                                     │
│ 6. 调用 router.dispatch_tool_call_with_code_mode_result()       │
│ 7. 返回结果                                                      │
└─────────────────────────────────────────────────────────────────┘
```

### 关键代码路径

#### 并行控制实现

```rust
// parallel.rs:99-123
let handle: AbortOnDropHandle<Result<AnyToolResult, FunctionCallError>> =
    AbortOnDropHandle::new(tokio::spawn(async move {
        tokio::select! {
            _ = cancellation_token.cancelled() => {
                let secs = started.elapsed().as_secs_f32().max(0.1);
                dispatch_span.record("aborted", true);
                Ok(Self::aborted_response(&call, secs))
            },
            res = async {
                let _guard = if supports_parallel {
                    Either::Left(lock.read().await)
                } else {
                    Either::Right(lock.write().await)
                };

                router
                    .dispatch_tool_call_with_code_mode_result(...)
                    .instrument(dispatch_span.clone())
                    .await
            } => res,
        }
    }));
```

#### 失败响应生成

```rust
// parallel.rs:136-161
fn failure_response(call: ToolCall, err: FunctionCallError) -> ResponseInputItem {
    let message = err.to_string();
    match call.payload {
        ToolPayload::ToolSearch { .. } => ResponseInputItem::ToolSearchOutput { ... },
        ToolPayload::Custom { .. } => ResponseInputItem::CustomToolCallOutput { ... },
        _ => ResponseInputItem::FunctionCallOutput { ... },
    }
}
```

#### 取消响应生成

```rust
// parallel.rs:163-180
fn aborted_response(call: &ToolCall, secs: f32) -> AnyToolResult {
    AnyToolResult {
        call_id: call.call_id.clone(),
        payload: call.payload.clone(),
        result: Box::new(AbortedToolOutput {
            message: Self::abort_message(call, secs),
        }),
    }
}

fn abort_message(call: &ToolCall, secs: f32) -> String {
    match call.tool_name.as_str() {
        "shell" | "container.exec" | "local_shell" | "shell_command" | "unified_exec" => {
            format!("Wall time: {secs:.1} seconds\naborted by user")
        }
        _ => format!("aborted by user after {secs:.1}s"),
    }
}
```

### 数据结构详解

#### ToolCallRuntime

```rust
pub(crate) struct ToolCallRuntime {
    router: Arc<ToolRouter>,              // 工具路由（共享）
    session: Arc<Session>,                // 会话（共享）
    turn_context: Arc<TurnContext>,       // 回合上下文（共享）
    tracker: SharedTurnDiffTracker,       // 差异跟踪器（共享）
    parallel_execution: Arc<RwLock<()>>,  // 并行控制锁（共享）
}
```

所有字段都是 `Arc` 包装的共享状态，允许 `ToolCallRuntime` 被克隆并在多个异步任务间共享。

#### 锁的使用模式

```rust
// 读锁 - 并行执行
Either::Left(lock.read().await)

// 写锁 - 串行执行  
Either::Right(lock.write().await)
```

使用 `tokio_util::either::Either` 统一两种锁守卫的类型。

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::tools::router::ToolRouter` | 工具路由分发 |
| `crate::tools::context::*` | 工具调用上下文和结果类型 |
| `crate::tools::registry::AnyToolResult` | 通用工具结果 |
| `crate::codex::{Session, TurnContext}` | 会话和回合状态 |
| `crate::function_tool::FunctionCallError` | 函数调用错误 |

### 外部库依赖

| 库 | 用途 |
|----|----|
| `tokio::sync::RwLock` | 异步读写锁 |
| `tokio_util::sync::CancellationToken` | 取消信号 |
| `tokio_util::task::AbortOnDropHandle` | 自动中止句柄 |
| `tracing::Instrument` | 追踪上下文传播 |

### 调用关系

```
ToolCallRuntime::handle_tool_call()
    └── ToolCallRuntime::handle_tool_call_with_source()
        ├── router.tool_supports_parallel()           [检查并行支持]
        ├── tokio::spawn()                            [创建异步任务]
        │   ├── cancellation_token.cancelled()        [取消监听]
        │   └── router.dispatch_tool_call_with_code_mode_result()
        │       └── registry.dispatch_any()           [实际执行]
        └── handle.await                              [等待结果]
```

## 风险、边界与改进建议

### 已知风险

1. **锁饥饿风险**
   - 当前使用 `RwLock`，如果写锁频繁请求，读锁可能饥饿
   - 建议：考虑使用公平锁或队列机制

2. **取消传播延迟**
   - 取消信号通过 `CancellationToken` 传递
   - 如果工具实现不检查取消信号，可能无法及时响应
   - 建议：添加超时强制终止机制

3. **资源泄漏**
   - 使用 `AbortOnDropHandle` 确保任务在句柄丢弃时中止
   - 但如果任务在 `spawn` 和句柄创建之间 panic，可能泄漏

### 边界情况

1. **零超时取消**
   - 如果取消信号在 `spawn` 之前触发，任务仍会被创建但立即返回取消响应

2. **工具并行配置变更**
   - `supports_parallel` 在任务创建时确定
   - 如果工具配置在运行时变更，已创建的任务不受影响

3. **并发限制**
   - 当前没有全局并发限制，仅通过锁控制单个工具的串行化
   - 大量并行工具可能导致资源耗尽

### 改进建议

1. **并发限制**
   ```rust
   // 建议添加信号量限制全局并发
   parallel_execution: Arc<Semaphore>,
   ```

2. **公平调度**
   - 使用 `tokio::sync::RwLock::new(())` 的公平模式
   - 或实现自定义队列确保长时间等待的任务优先

3. **取消改进**
   - 添加取消原因追踪
   - 支持分级取消（优雅取消 → 强制终止）

4. **指标增强**
   - 记录等待锁的时间
   - 跟踪并行度指标
   - 监控取消率

5. **错误上下文**
   - 在失败响应中包含更多调试信息
   - 区分"工具失败"和"执行框架失败"

### 相关文件引用

| 文件 | 关系 |
|------|------|
| `codex-rs/core/src/tools/router.rs` | ToolRouter 定义和分发逻辑 |
| `codex-rs/core/src/tools/registry.rs` | 工具注册表和实际执行 |
| `codex-rs/core/src/tools/context.rs` | ToolPayload、ToolOutput 等类型 |
| `codex-rs/core/src/codex.rs` | Session 和 TurnContext 定义 |
| `codex-rs/core/src/function_tool.rs` | FunctionCallError 定义 |
