# worker.rs 研究文档

## 场景与职责

`worker.rs` 是 Code Mode 的**后台工作器模块**，负责处理 JavaScript 执行过程中的异步消息（工具调用和通知）。它在独立的 Tokio 任务中运行，确保即使 JavaScript 执行让出控制权，工具调用仍能继续处理。

**核心定位**：
- 异步消息处理：处理来自 Node.js 的 `ToolCall` 和 `Notify` 消息
- 工具调用转发：将 JavaScript 的工具调用转发到 Rust 的工具系统
- 通知注入：将 JavaScript 的 `notify()` 调用注入到当前会话
- 生命周期管理：通过 `CodeModeWorker` 结构管理 Worker 生命周期

## 功能点目的

### 1. Worker 结构（CodeModeWorker）
```rust
pub(crate) struct CodeModeWorker {
    shutdown_tx: Option<oneshot::Sender<()>>,
}
```
- 包含一个可选的 shutdown 发送器
- 通过 `Drop` trait 实现自动清理

### 2. 自动清理（Drop 实现）
```rust
impl Drop for CodeModeWorker {
    fn drop(&mut self) {
        if let Some(shutdown_tx) = self.shutdown_tx.take() {
            let _ = shutdown_tx.send(());
        }
    }
}
```
- 当 `CodeModeWorker` 被 drop 时，发送 shutdown 信号
- 优雅地停止后台任务

### 3. Worker 创建（CodeModeProcess::worker）
```rust
impl CodeModeProcess {
    pub(super) fn worker(
        &self,
        exec: ExecContext,
        tool_runtime: ToolCallRuntime,
    ) -> CodeModeWorker {
        // 创建 shutdown channel
        // 启动异步任务循环
        // 返回 CodeModeWorker
    }
}
```

### 4. 消息处理循环
后台任务循环处理以下消息类型：
- `ToolCall`：调用嵌套工具并发送响应
- `Notify`：将通知注入到当前会话
- `Yielded` / `Terminated` / `Result`：意外错误（应在响应路径处理）

## 具体技术实现

### 消息处理流程

**ToolCall 处理**：
```rust
NodeToHostMessage::ToolCall { tool_call } => {
    let exec = exec.clone();
    let tool_runtime = tool_runtime.clone();
    let stdin = stdin.clone();
    tokio::spawn(async move {
        // 1. 调用嵌套工具
        let result = call_nested_tool(
            exec,
            tool_runtime,
            tool_call.name,
            tool_call.input,
            CancellationToken::new(),
        ).await;
        
        // 2. 处理结果
        let (code_mode_result, error_text) = match result {
            Ok(code_mode_result) => (code_mode_result, None),
            Err(error) => (serde_json::Value::Null, Some(error.to_string())),
        };
        
        // 3. 构建响应
        let response = HostToNodeMessage::Response {
            request_id: tool_call.request_id,
            id: tool_call.id,
            code_mode_result,
            error_text,
        };
        
        // 4. 发送响应
        if let Err(err) = write_message(&stdin, &response).await {
            warn!("failed to write {PUBLIC_TOOL_NAME} tool response: {err}");
        }
    });
}
```

**Notify 处理**：
```rust
NodeToHostMessage::Notify { notify } => {
    if notify.text.trim().is_empty() {
        continue;
    }
    if exec
        .session
        .inject_response_items(vec![ResponseInputItem::CustomToolCallOutput {
            call_id: notify.call_id.clone(),
            name: Some(PUBLIC_TOOL_NAME.to_string()),
            output: FunctionCallOutputPayload::from_text(notify.text),
        }])
        .await
        .is_err()
    {
        warn!("failed to inject {PUBLIC_TOOL_NAME} notify message for cell {}: no active turn",
              notify.cell_id);
    }
}
```

### 任务循环结构
```rust
tokio::spawn(async move {
    loop {
        let next_message = tokio::select! {
            // 1. 等待 shutdown 信号
            _ = &mut shutdown_rx => break,
            // 2. 等待下一条消息
            message = async {
                let mut message_rx = message_rx.lock().await;
                message_rx.recv().await
            } => message,
        };
        
        let Some(next_message) = next_message else {
            break;  // 通道关闭，退出循环
        };
        
        match next_message {
            // 处理各种消息类型...
        }
    }
});
```

### 并发处理策略

**ToolCall 并发**：
- 每个 `ToolCall` 在独立的 Tokio 任务中处理
- 允许同时处理多个工具调用
- 不阻塞消息接收循环

**Notify 串行**：
- `Notify` 在当前任务中处理
- 确保通知按顺序注入

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/worker.rs`

### 调用方
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/service.rs`
  - `start_turn_worker()` 调用 `process.worker(exec, tool_runtime)`

### 依赖项
| 文件 | 用途 |
|------|------|
| `mod.rs` | `ExecContext`, `PUBLIC_TOOL_NAME`, `call_nested_tool` |
| `process.rs` | `CodeModeProcess`, `write_message` |
| `protocol.rs` | `HostToNodeMessage`, `NodeToHostMessage` |
| `parallel.rs` | `ToolCallRuntime` |

### 外部依赖
| crate | 用途 |
|-------|------|
| `tokio::sync::oneshot` | shutdown 信号通道 |
| `tokio_util::sync::CancellationToken` | 工具调用取消令牌 |
| `tracing::{error, warn}` | 日志记录 |
| `codex_protocol::models::{FunctionCallOutputPayload, ResponseInputItem}` | 协议模型 |

## 依赖与外部交互

### 与 CodeModeProcess 的交互
```rust
impl CodeModeProcess {
    pub(super) fn worker(&self, exec: ExecContext, tool_runtime: ToolCallRuntime) -> CodeModeWorker {
        let (shutdown_tx, mut shutdown_rx) = oneshot::channel();
        let stdin = self.stdin.clone();
        let message_rx = self.message_rx.clone();
        // 启动任务...
    }
}
```

### 与 call_nested_tool 的交互
```rust
let result = call_nested_tool(
    exec,
    tool_runtime,
    tool_call.name,
    tool_call.input,
    CancellationToken::new(),  // 创建新的取消令牌
).await;
```

### 与 Session 的交互
```rust
if exec
    .session
    .inject_response_items(vec![ResponseInputItem::CustomToolCallOutput { ... }])
    .await
    .is_err()
{
    // 没有活跃的 turn
}
```

### 生命周期管理
```
CodeModeWorker 创建
    │
    ├──> 后台任务启动
    │       ├──> 循环接收消息
    │       │       ├──> ToolCall → 异步处理
    │       │       └──> Notify → 同步处理
    │       │
    │       └──> 等待 shutdown_rx 或 message_rx 关闭
    │
    └──> 返回 CodeModeWorker { shutdown_tx }

CodeModeWorker drop
    │
    └──> shutdown_tx.send(())
            └──> 后台任务收到信号，退出循环
```

## 风险、边界与改进建议

### 风险点

1. **消息顺序问题**
   - `ToolCall` 在独立任务中处理，完成顺序可能与发送顺序不同
   - 如果 JavaScript 依赖工具调用的顺序，可能出现问题

2. **响应竞争**
   ```rust
   if session.completed {
       return;
   }
   session.worker.postMessage({ type: 'tool_response', ... });
   ```
   在 `runner.cjs` 中检查 `session.completed`，但检查和发送之间可能有竞争

3. **资源泄漏**
   - 如果 `ToolCall` 任务挂起（如等待网络），Worker 可能无法及时停止
   - `CancellationToken` 创建但未传递给工具调用（`call_nested_tool` 接收但不使用）

4. **错误静默**
   ```rust
   if let Err(err) = write_message(&stdin, &response).await {
       warn!("failed to write {PUBLIC_TOOL_NAME} tool response: {err}");
   }
   ```
   写入失败仅记录警告，JavaScript 端可能永远等待响应

### 边界情况

1. **空通知文本**
   ```rust
   if notify.text.trim().is_empty() {
       continue;
   }
   ```
   正确处理空通知

2. **无活跃 Turn**
   ```rust
   if exec.session.inject_response_items(...).await.is_err() {
       warn!("...no active turn");
   }
   ```
   如果 turn 已结束，无法注入通知

3. **意外消息类型**
   ```rust
   unexpected_message @ (NodeToHostMessage::Yielded { .. }
       | NodeToHostMessage::Terminated { .. }
       | NodeToHostMessage::Result { .. }) => {
       error!("received unexpected {PUBLIC_TOOL_NAME} message in worker loop: {unexpected_message:?}");
       break;
   }
   ```
   收到意外消息时记录错误并退出循环

4. **通道关闭**
   ```rust
   let Some(next_message) = next_message else {
       break;
   };
   ```
   `message_rx` 关闭时优雅退出

### 改进建议

1. **工具调用排序**
   ```rust
   use tokio::sync::mpsc;
   
   // 使用有序通道确保响应按请求顺序发送
   let (ordered_tx, mut ordered_rx) = mpsc::channel(100);
   
   tokio::spawn(async move {
       while let Some((id, result)) = ordered_rx.recv().await {
           // 按顺序发送响应
       }
   });
   ```

2. **改进取消机制**
   ```rust
   // 将 CancellationToken 传递给工具调用
   let result = call_nested_tool(
       exec,
       tool_runtime,
       tool_call.name,
       tool_call.input,
       cancellation_token.clone(),  // 共享的取消令牌
   ).await;
   
   // 在 shutdown 时取消所有进行中的调用
   tokio::select! {
       _ = &mut shutdown_rx => {
           cancellation_token.cancel();
           break;
       }
       // ...
   }
   ```

3. **响应超时**
   ```rust
   tokio::time::timeout(
       Duration::from_secs(60),
       call_nested_tool(...)
   ).await
   ```

4. **错误传播**
   ```rust
   // 写入失败时通知 JavaScript 端
   if let Err(err) = write_message(&stdin, &response).await {
       warn!("failed to write {PUBLIC_TOOL_NAME} tool response: {err}");
       // 发送错误响应
       let error_response = HostToNodeMessage::Response {
           request_id: tool_call.request_id,
           id: tool_call.id,
           code_mode_result: serde_json::Value::Null,
           error_text: Some(format!("Failed to send response: {err}")),
       };
       let _ = write_message(&stdin, &error_response).await;
   }
   ```

5. **指标收集**
   ```rust
   pub(crate) struct WorkerMetrics {
       pub tool_calls_total: AtomicU64,
       pub tool_calls_failed: AtomicU64,
       pub notifications_total: AtomicU64,
       pub avg_tool_call_duration_ms: AtomicU64,
   }
   ```

6. **测试覆盖**
   - 当前无直接测试
   - 建议添加：
     - ToolCall 处理测试
     - Notify 注入测试
     - Worker 生命周期测试
     - 并发 ToolCall 测试

7. **代码复用**
   - `CodeModeWorker` 的 Drop 实现可以提取为通用模式
   - 消息循环可以泛化为处理任意消息类型的通用循环
