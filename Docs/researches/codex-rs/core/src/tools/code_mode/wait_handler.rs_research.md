# wait_handler.rs 研究文档

## 场景与职责

`wait_handler.rs` 是 Code Mode **`wait` 工具的核心处理器**，负责处理模型对长时间运行的 JavaScript 执行的轮询和终止请求。它与 `execute_handler.rs` 形成互补，共同完成 Code Mode 的完整执行生命周期。

**核心定位**：
- 实现 `ToolHandler` trait，作为 `wait` 工具的入口点
- 支持轮询运行中的 cell（获取新输出）
- 支持终止运行中的 cell
- 复用 `execute_handler` 的执行上下文和消息处理逻辑

## 功能点目的

### 1. 参数解析（ExecWaitArgs）
```rust
#[derive(Debug, Deserialize)]
struct ExecWaitArgs {
    cell_id: String,                    // 目标 cell ID
    #[serde(default = "default_wait_yield_time_ms")]
    yield_time_ms: u64,                 // 轮询等待时间（默认 10s）
    #[serde(default)]
    max_tokens: Option<usize>,          // 最大输出 token 数
    #[serde(default)]
    terminate: bool,                    // 是否终止而非等待
}
```

### 2. 轮询处理
当 `terminate: false`（默认）时：
1. 构建 `HostToNodeMessage::Poll` 消息
2. 发送到 Node.js 进程
3. 处理响应（`Yielded` 或 `Result`）
4. 返回新输出或最终结果

### 3. 终止处理
当 `terminate: true` 时：
1. 构建 `HostToNodeMessage::Terminate` 消息
2. 发送到 Node.js 进程
3. 处理响应（`Terminated` 或 `Result`）
4. 返回终止结果

### 4. 进程健康检查
```rust
if !matches!(process.has_exited(), Ok(false)) {
    return Err(FunctionCallError::RespondToModel(format!(
        "{PUBLIC_TOOL_NAME} runner failed to start"
    )));
}
```
- 在发送消息前验证进程是否存活
- 如果进程已退出，返回友好错误

## 具体技术实现

### 数据结构

**ExecWaitArgs**：
```rust
#[derive(Debug, Deserialize)]
struct ExecWaitArgs {
    cell_id: String,
    #[serde(default = "default_wait_yield_time_ms")]
    yield_time_ms: u64,
    #[serde(default)]
    max_tokens: Option<usize>,
    #[serde(default)]
    terminate: bool,
}

fn default_wait_yield_time_ms() -> u64 {
    DEFAULT_WAIT_YIELD_TIME_MS  // 10_000
}
```

**参数解析辅助函数**：
```rust
fn parse_arguments<T>(arguments: &str) -> Result<T, FunctionCallError>
where
    T: for<'de> Deserialize<'de>,
{
    serde_json::from_str(arguments).map_err(|err| {
        FunctionCallError::RespondToModel(format!("failed to parse function arguments: {err}"))
    })
}
```

### 关键流程详解

#### 完整处理流程
```
handle(invocation)
    │
    ├──> 解构 ToolInvocation
    │
    ├──> 匹配 payload
    │       │
    │       ├──> ToolPayload::Function { arguments } 且 tool_name == WAIT_TOOL_NAME
    │       │       │
    │       │       ├──> parse_arguments::<ExecWaitArgs>(&arguments)?
    │       │       │
    │       │       ├──> 构建 ExecContext { session, turn }
    │       │       │
    │       │       ├──> service.allocate_request_id().await
    │       │       │
    │       │       ├──> 构建消息
    │       │       │       ├──> terminate: true → HostToNodeMessage::Terminate
    │       │       │       └──> terminate: false → HostToNodeMessage::Poll
    │       │       │
    │       │       ├──> service.ensure_started().await
    │       │       │
    │       │       ├──> 验证进程存活
    │       │       │
    │       │       ├──> process.send(&request_id, &message).await
    │       │       │
    │       │       ├──> handle_node_message(&exec, args.cell_id, message, Some(args.max_tokens), started_at).await
    │       │       │
    │       │       └──> 匹配 CodeModeSessionProgress 返回结果
    │       │
    │       └──> 其他 → Err("wait expects JSON arguments")
    │
    └──> 返回 FunctionToolOutput 或 FunctionCallError
```

### 消息构建

**Poll 消息**（轮询）：
```rust
HostToNodeMessage::Poll {
    request_id: request_id.clone(),
    cell_id: args.cell_id.clone(),
    yield_time_ms: args.yield_time_ms,
}
```

**Terminate 消息**（终止）：
```rust
HostToNodeMessage::Terminate {
    request_id: request_id.clone(),
    cell_id: args.cell_id.clone(),
}
```

### 与 execute_handler 的差异

| 方面 | execute_handler | wait_handler |
|------|----------------|--------------|
| 输入格式 | 原始 JavaScript | JSON 参数 |
| 主要消息 | `HostToNodeMessage::Start` | `HostToNodeMessage::Poll` / `Terminate` |
| 参数解析 | `parse_freeform_args`（自定义 pragma 解析） | `parse_arguments`（标准 JSON 反序列化） |
| 构建源码 | 是（`build_source`） | 否 |
| 分配 cell_id | 是 | 否（使用传入的 cell_id） |
| 输出截断 | `poll_max_output_tokens: None` | `poll_max_output_tokens: Some(args.max_tokens)` |

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/wait_handler.rs`

### 调用方
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/mod.rs`
  - 第 5 行：`mod wait_handler;`
  - 第 58 行：`pub(crate) use wait_handler::CodeModeWaitHandler;`

### 依赖项
| 文件 | 用途 |
|------|------|
| `mod.rs` | `CodeModeSessionProgress`, `DEFAULT_WAIT_YIELD_TIME_MS`, `ExecContext`, `PUBLIC_TOOL_NAME`, `WAIT_TOOL_NAME`, `handle_node_message` |
| `protocol.rs` | `HostToNodeMessage` |
| `service.rs` | `CodeModeService::allocate_request_id()`, `ensure_started()` |
| `process.rs` | `CodeModeProcess::send()`, `has_exited()` |

### 外部依赖
| crate | 用途 |
|-------|------|
| `async_trait` | `#[async_trait]` 宏 |
| `serde::Deserialize` | 参数反序列化 |
| `crate::function_tool::FunctionCallError` | 错误类型 |
| `crate::tools::context::{FunctionToolOutput, ToolInvocation, ToolPayload}` | 工具调用上下文 |
| `crate::tools::registry::{ToolHandler, ToolKind}` | 工具处理器 trait |

## 依赖与外部交互

### Trait 实现
```rust
#[async_trait]
impl ToolHandler for CodeModeWaitHandler {
    type Output = FunctionToolOutput;

    fn kind(&self) -> ToolKind {
        ToolKind::Function
    }

    async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError> {
        // ... 实现
    }
}
```

### 与 CodeModeService 的交互
```rust
let request_id = exec
    .session
    .services
    .code_mode_service
    .allocate_request_id()
    .await;

let process_slot = exec
    .session
    .services
    .code_mode_service
    .ensure_started()
    .await
    .map_err(|err| FunctionCallError::RespondToModel(err.to_string()))?;
```

### 与 CodeModeProcess 的交互
```rust
let message = process
    .send(&request_id, &message)
    .await
    .map_err(|err| err.to_string());
```

### 与 handle_node_message 的交互
```rust
handle_node_message(
    &exec,
    args.cell_id,
    message,
    Some(args.max_tokens),  // 与 execute_handler 不同，传递 max_tokens
    started_at,
)
.await
```

## 风险、边界与改进建议

### 风险点

1. **cell_id 验证缺失**
   - 代码不验证传入的 `cell_id` 是否有效
   - 无效的 cell_id 会导致 Node.js 返回错误
   - 错误处理在 `runner.cjs` 中，不在 Rust 端

2. **重复终止**
   - 如果模型多次调用 `terminate: true`，第二次会失败
   - 因为 cell 已经在第一次调用后被移除

3. **进程状态竞争**
   ```rust
   if !matches!(process.has_exited(), Ok(false)) {
       return Err(...);
   }
   ```
   检查和发送之间进程可能退出

4. **max_tokens 处理不一致**
   - `execute_handler` 使用 `poll_max_output_tokens: None`
   - `wait_handler` 使用 `poll_max_output_tokens: Some(args.max_tokens)`
   - 这可能导致用户困惑

### 边界情况

1. **cell 已完成**
   - 如果 cell 在 `wait` 调用前已完成，`runner.cjs` 会返回错误
   - 错误消息：`"exec cell {cell_id} not found"`

2. **空 cell_id**
   - 代码不验证 `cell_id` 是否为空
   - 空字符串可能导致意外行为

3. **yield_time_ms = 0**
   - 允许 `yield_time_ms` 为 0
   - 这会立即让出，可能不是预期行为

4. **超大 max_tokens**
   - 没有上限检查
   - 可能导致内存问题

### 改进建议

1. **添加 cell_id 验证**
   ```rust
   if args.cell_id.trim().is_empty() {
       return Err(FunctionCallError::RespondToModel(
           "cell_id cannot be empty".to_string()
       ));
   }
   ```

2. **添加 yield_time_ms 范围检查**
   ```rust
   const MIN_YIELD_TIME_MS: u64 = 100;
   const MAX_YIELD_TIME_MS: u64 = 300_000; // 5 minutes
   
   if args.yield_time_ms < MIN_YIELD_TIME_MS || args.yield_time_ms > MAX_YIELD_TIME_MS {
       return Err(FunctionCallError::RespondToModel(format!(
           "yield_time_ms must be between {} and {}",
           MIN_YIELD_TIME_MS, MAX_YIELD_TIME_MS
       )));
   }
   ```

3. **统一 max_tokens 处理**
   - 考虑在 `execute_handler` 中也支持 `max_tokens` 参数
   - 或在文档中明确说明两者的差异

4. **更好的错误消息**
   - 区分 "cell not found" 和 "process not available"
   - 提供更具体的操作建议

5. **测试覆盖**
   - 当前无直接测试
   - 建议添加：
     - 正常轮询测试
     - 终止测试
     - 无效 cell_id 测试
     - 进程退出测试

6. **与 execute_handler 的代码复用**
   - 两个处理器有大量相似代码
   - 考虑提取公共函数：
     ```rust
     async fn send_to_process(
         service: &CodeModeService,
         message: HostToNodeMessage,
     ) -> Result<NodeToHostMessage, FunctionCallError> { ... }
     ```

7. **文档改进**
   - 在 `wait_description.md` 中添加错误场景说明
   - 说明 `terminate: true` 会忽略 `yield_time_ms` 和 `max_tokens`
