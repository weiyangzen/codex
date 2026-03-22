# session_startup_prewarm.rs 深度研究文档

## 场景与职责

`session_startup_prewarm.rs` 是 Codex 核心模块中负责会话启动预热的组件，位于 `codex-rs/core/src/` 目录下。其核心职责是在用户提交第一个请求之前，预先建立与模型提供商的 WebSocket 连接，以减少首次交互的延迟。

该模块解决的关键问题是：模型 API 的 WebSocket 连接建立通常需要数百毫秒到数秒的时间（包括 TLS 握手、认证、协议协商等），如果在用户发送第一条消息时才建立连接，会导致明显的响应延迟。通过预热机制，可以在会话初始化阶段异步建立连接，实现"零延迟"的首轮响应。

## 功能点目的

### 1. 异步预热管理
在会话启动时异步创建 WebSocket 连接，不阻塞主会话初始化流程。

### 2. 超时控制
为预热过程设置超时，避免无限期等待连接建立。

### 3. 取消支持
支持在预热完成前取消（如用户快速退出或会话被终止）。

### 4. 遥测记录
记录预热过程的性能指标，包括：
- 预热持续时间
- 首次使用时的预热年龄（age at first turn）
- 成功/失败/取消/超时状态

### 5. 连接复用
预热建立的连接和 `previous_response_id` 可以在首轮请求中复用。

## 具体技术实现

### 核心数据结构

#### `SessionStartupPrewarmHandle`
```rust
pub(crate) struct SessionStartupPrewarmHandle {
    task: JoinHandle<CodexResult<ModelClientSession>>,  // 预热异步任务
    started_at: Instant,                                 // 开始时间
    timeout: Duration,                                   // 超时时间
}
```

该结构封装了预热任务的状态，提供统一的解析接口。

#### `SessionStartupPrewarmResolution`
```rust
pub(crate) enum SessionStartupPrewarmResolution {
    Cancelled,                                           // 被取消
    Ready(Box<ModelClientSession>),                     // 成功，返回预热的会话
    Unavailable {
        status: &'static str,                            // 失败原因状态
        prewarm_duration: Option<Duration>,             // 预热持续时间（如果有）
    },
}
```

表示预热任务的最终解析结果。

### 关键流程

#### 1. 预热调度 (`Session::schedule_startup_prewarm`)
```rust
pub(crate) async fn schedule_startup_prewarm(self: &Arc<Self>, base_instructions: String) {
    let session_telemetry = self.services.session_telemetry.clone();
    let websocket_connect_timeout = self.provider().await.websocket_connect_timeout();
    let started_at = Instant::now();
    let startup_prewarm_session = Arc::clone(self);
    
    let startup_prewarm = tokio::spawn(async move {
        let result = schedule_startup_prewarm_inner(
            startup_prewarm_session, 
            base_instructions
        ).await;
        // 记录遥测...
        result
    });
    
    self.set_session_startup_prewarm(
        SessionStartupPrewarmHandle::new(startup_prewarm, started_at, websocket_connect_timeout)
    ).await;
}
```

**流程说明：**
1. 获取 WebSocket 连接超时配置
2. 记录开始时间
3. 在独立任务中执行预热逻辑
4. 将任务句柄存储在会话状态中

#### 2. 预热内部逻辑 (`schedule_startup_prewarm_inner`)
```rust
async fn schedule_startup_prewarm_inner(
    session: Arc<Session>,
    base_instructions: String,
) -> CodexResult<ModelClientSession> {
    // 1. 创建新的 turn 上下文
    let startup_turn_context = session
        .new_default_turn_with_sub_id(INITIAL_SUBMIT_ID.to_owned())
        .await;
    
    // 2. 构建工具路由
    let startup_cancellation_token = CancellationToken::new();
    let startup_router = built_tools(
        session.as_ref(),
        startup_turn_context.as_ref(),
        &[],
        &HashSet::new(),
        /*skills_outcome*/ None,
        &startup_cancellation_token,
    ).await?;
    
    // 3. 构建提示词
    let startup_prompt = build_prompt(
        Vec::new(),
        startup_router.as_ref(),
        startup_turn_context.as_ref(),
        BaseInstructions { text: base_instructions },
    );
    
    // 4. 获取 turn 元数据
    let startup_turn_metadata_header = startup_turn_context
        .turn_metadata_state
        .current_header_value();
    
    // 5. 创建并预热客户端会话
    let mut client_session = session.services.model_client.new_session();
    client_session
        .prewarm_websocket(
            &startup_prompt,
            &startup_turn_context.model_info,
            &startup_turn_context.session_telemetry,
            startup_turn_context.reasoning_effort,
            startup_turn_context.reasoning_summary,
            startup_turn_context.config.service_tier,
            startup_turn_metadata_header.as_deref(),
        )
        .await?;
    
    Ok(client_session)
}
```

**关键步骤：**
1. 使用 `INITIAL_SUBMIT_ID` 创建特殊的 turn 上下文
2. 构建工具路由（虽然预热可能不需要实际工具）
3. 构建完整的提示词，模拟真实请求
4. 调用 `prewarm_websocket` 建立 WebSocket 连接

#### 3. 预热解析 (`SessionStartupPrewarmHandle::resolve`)
```rust
async fn resolve(
    self,
    session_telemetry: &SessionTelemetry,
    cancellation_token: &CancellationToken,
) -> SessionStartupPrewarmResolution {
    // 计算剩余超时时间
    let age_at_first_turn = started_at.elapsed();
    let remaining = timeout.saturating_sub(age_at_first_turn);
    
    // 根据任务状态选择处理路径
    let resolution = if task.is_finished() {
        // 任务已完成，直接获取结果
        Self::resolution_from_join_result(task.await, started_at)
    } else {
        // 任务仍在运行，等待完成或超时/取消
        match tokio::select! {
            _ = cancellation_token.cancelled() => None,
            result = tokio::time::timeout(remaining, &mut task) => Some(result),
        } {
            Some(Ok(result)) => Self::resolution_from_join_result(result, started_at),
            Some(Err(_elapsed)) => {
                // 超时处理
                task.abort();
                SessionStartupPrewarmResolution::Unavailable {
                    status: "timed_out",
                    prewarm_duration: Some(started_at.elapsed()),
                }
            }
            None => {
                // 取消处理
                task.abort();
                // 记录取消遥测...
                return SessionStartupPrewarmResolution::Cancelled;
            }
        }
    };
    
    // 记录遥测并返回结果
    // ...
}
```

### 遥测指标

| 指标名称 | 类型 | 描述 |
|---------|------|------|
| `STARTUP_PREWARM_DURATION_METRIC` | Duration | 预热过程总持续时间 |
| `STARTUP_PREWARM_AGE_AT_FIRST_TURN_METRIC` | Duration | 从预热开始到首次使用的时间 |

状态标签：
- `"ready"` - 预热成功完成
- `"failed"` - 预热失败
- `"join_failed"` - 任务 join 失败
- `"timed_out"` - 预热超时
- `"cancelled"` - 预热被取消
- `"consumed"` - 预热成功并被使用
- `"not_scheduled"` - 未调度预热

## 关键代码路径与文件引用

### 模块依赖图

```
session_startup_prewarm.rs
├── client.rs
│   └── ModelClientSession
│       └── prewarm_websocket()
├── codex.rs
│   └── Session
│       ├── schedule_startup_prewarm()
│       ├── consume_startup_prewarm_for_regular_turn()
│       ├── set_session_startup_prewarm()
│       └── take_session_startup_prewarm()
├── codex.rs (built_tools)
│   └── built_tools()
├── codex.rs (build_prompt)
│   └── build_prompt()
├── codex_otel
│   └── SessionTelemetry
│       ├── record_duration()
│       └── counter()
├── codex_protocol::models
│   └── BaseInstructions
└── tokio
    ├── task::JoinHandle
    ├── sync::CancellationToken
    └── time::timeout
```

### 调用关系

**调度路径：**
```
Session::new() or similar
└── Session::schedule_startup_prewarm()
    └── tokio::spawn(schedule_startup_prewarm_inner())
        ├── new_default_turn_with_sub_id()
        ├── built_tools()
        ├── build_prompt()
        └── ModelClientSession::prewarm_websocket()
```

**消费路径：**
```
Session::submit() or similar
└── Session::consume_startup_prewarm_for_regular_turn()
    └── SessionStartupPrewarmHandle::resolve()
        └── 返回 ModelClientSession 或失败状态
```

## 依赖与外部交互

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `tokio` | 异步运行时、任务管理、超时控制、取消令牌 |
| `tokio_util` | `CancellationToken` |
| `tracing` | 日志记录 (`info!`, `warn!`) |
| `codex_otel` | 遥测数据收集 |
| `codex_protocol` | 协议类型定义 |

### 内部模块依赖

| 模块 | 用途 |
|------|------|
| `client` | `ModelClientSession` 和 `prewarm_websocket` |
| `codex` | `Session` 和 `INITIAL_SUBMIT_ID` |
| `error` | `Result` 类型别名 |

## 风险、边界与改进建议

### 已知风险

1. **资源浪费**
   - 如果用户快速退出或会话立即结束，预热建立的连接会被浪费
   - 超时机制缓解此问题，但仍有一定资源开销

2. **竞争条件**
   - 预热和实际请求之间可能存在竞态
   - 连接可能在预热成功后、使用前断开

3. **配置复杂性**
   - 预热行为依赖于多个配置项（超时时间、服务层级等）
   - 配置不当可能导致预热失败或资源浪费

### 边界情况

1. **超时边界**
   ```rust
   let remaining = timeout.saturating_sub(age_at_first_turn);
   ```
   使用 `saturating_sub` 避免溢出，如果预热已经超时，剩余时间为 0。

2. **任务完成检查**
   ```rust
   if task.is_finished() {
       Self::resolution_from_join_result(task.await, started_at)
   }
   ```
   先检查 `is_finished()` 避免不必要的 `tokio::select!` 开销。

3. **取消与完成竞态**
   ```rust
   match tokio::select! {
       _ = cancellation_token.cancelled() => None,
       result = tokio::time::timeout(remaining, &mut task) => Some(result),
   }
   ```
   `select!` 确保取消信号和超时能够中断等待。

### 改进建议

1. **自适应预热**
   - 根据网络状况和历史数据动态调整超时时间
   - 对于已知慢速网络增加超时，快速网络减少超时

2. **预热策略配置**
   - 允许用户禁用预热（低带宽环境）
   - 支持自定义预热提示词

3. **连接健康检查**
   - 在 `consume` 时验证连接是否仍然有效
   - 如果连接断开，自动回退到新建连接

4. **批处理优化**
   - 考虑多个并发会话的预热批处理
   - 共享连接池（如果提供商支持）

5. **遥测增强**
   - 记录预热成功率与首次响应时间的关系
   - 添加网络类型（WiFi/蜂窝）标签

6. **错误恢复**
   - 预热失败时自动重试（有限次数）
   - 区分可恢复和不可恢复错误

### 测试建议

当前文件无内联测试，建议添加：
1. 模拟 `ModelClientSession` 测试超时逻辑
2. 测试取消信号处理
3. 测试遥测数据记录
4. 测试各种边界条件（0 超时、已完成任务等）
