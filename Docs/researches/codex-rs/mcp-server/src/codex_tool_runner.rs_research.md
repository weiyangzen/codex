# codex_tool_runner.rs 研究文档

## 场景与职责

`codex_tool_runner.rs` 是 Codex MCP 服务器的核心执行引擎，负责在独立的 Tokio 任务中执行 Codex 工具调用。它将 MCP 的 `tools/call` 请求转换为 Codex 会话生命周期，管理事件流、用户审批交互和最终响应。

**核心职责：**
1. 启动新的 Codex 会话 (`run_codex_tool_session`)
2. 在现有会话中继续对话 (`run_codex_tool_session_reply`)
3. 处理 Codex 事件流，将内部事件转换为 MCP 通知
4. 协调执行审批和补丁审批的用户交互
5. 生成符合 MCP 规范的 `CallToolResult` 响应

## 功能点目的

### 1. 会话启动 (run_codex_tool_session)

处理 `codex` 工具的初始调用：

```rust
pub async fn run_codex_tool_session(
    id: RequestId,                    // MCP 请求 ID
    initial_prompt: String,           // 初始用户提示
    config: CodexConfig,              // 解析后的配置
    outgoing: Arc<OutgoingMessageSender>,  // 消息发送器
    thread_manager: Arc<ThreadManager>,    // 线程管理器
    running_requests_id_to_codex_uuid: Arc<Mutex<HashMap<RequestId, ThreadId>>>,
)
```

**执行流程：**
1. 调用 `thread_manager.start_thread(config)` 创建新线程
2. 发送 `SessionConfigured` 事件作为通知
3. 将 MCP 请求 ID 映射到 Codex 线程 ID（用于取消操作）
4. 提交初始用户输入
5. 进入事件处理循环 (`run_codex_tool_session_inner`)

### 2. 会话回复 (run_codex_tool_session_reply)

处理 `codex-reply` 工具的调用，在现有会话中继续：

```rust
pub async fn run_codex_tool_session_reply(
    thread_id: ThreadId,
    thread: Arc<CodexThread>,
    outgoing: Arc<OutgoingMessageSender>,
    request_id: RequestId,
    prompt: String,
    running_requests_id_to_codex_uuid: Arc<Mutex<HashMap<RequestId, ThreadId>>>,
)
```

### 3. 响应生成

创建符合 MCP 规范的 `CallToolResult`：

```rust
pub(crate) fn create_call_tool_result_with_thread_id(
    thread_id: ThreadId,
    text: String,
    is_error: Option<bool>,
) -> CallToolResult {
    let content = vec![Content::text(content_text.clone())];
    let structured_content = json!({
        "threadId": thread_id,
        "content": content_text,
    });
    CallToolResult {
        content,
        is_error,
        structured_content: Some(structured_content),
        meta: None,
    }
}
```

**设计要点：**
- `content`：标准 MCP 内容数组（文本类型）
- `structured_content`：包含 `threadId` 的 JSON 对象，供客户端关联会话
- 某些 MCP 客户端优先使用 `structuredContent` 而非 `content`，因此两者都包含文本

### 4. 事件处理循环

核心事件处理逻辑在 `run_codex_tool_session_inner` 中：

```rust
async fn run_codex_tool_session_inner(
    thread_id: ThreadId,
    thread: Arc<CodexThread>,
    outgoing: Arc<OutgoingMessageSender>,
    request_id: RequestId,
    running_requests_id_to_codex_uuid: Arc<Mutex<HashMap<RequestId, ThreadId>>>,
)
```

**事件分类处理：**

| 事件类型 | 处理行为 |
|---------|---------|
| `ExecApprovalRequest` | 调用 `handle_exec_approval_request`，暂停等待用户审批 |
| `ApplyPatchApprovalRequest` | 调用 `handle_patch_approval_request`，暂停等待用户审批 |
| `TurnComplete` | 提取最后一条代理消息，返回成功响应 |
| `Error` | 返回错误响应，包含错误信息 |
| `PlanDelta` | 忽略（继续循环） |
| `Warning` | 忽略（继续循环） |
| 其他事件 | 作为通知发送，不阻塞执行 |

## 具体技术实现

### 会话启动详细流程

```rust
pub async fn run_codex_tool_session(...) {
    // 1. 创建新线程
    let NewThread { thread_id, thread, session_configured } = 
        match thread_manager.start_thread(config).await {
            Ok(res) => res,
            Err(e) => {
                // 发送错误响应并返回
                let result = CallToolResult { ... };
                outgoing.send_response(id.clone(), result).await;
                return;
            }
        };

    // 2. 发送 SessionConfigured 通知
    let session_configured_event = Event {
        id: "".to_string(),
        msg: EventMsg::SessionConfigured(session_configured.clone()),
    };
    outgoing.send_event_as_notification(&session_configured_event, ...).await;

    // 3. 注册请求 ID 映射
    let sub_id = id.to_string();
    running_requests_id_to_codex_uuid.lock().await.insert(id.clone(), thread_id);

    // 4. 构建并提交初始输入
    let submission = Submission {
        id: sub_id.clone(),
        op: Op::UserInput { items: vec![...], final_output_json_schema: None },
        trace: None,
    };

    if let Err(e) = thread.submit_with_id(submission).await {
        // 发送错误响应，清理映射
        ...
        return;
    }

    // 5. 进入事件循环
    run_codex_tool_session_inner(...).await;
}
```

### 事件流处理

```rust
loop {
    match thread.next_event().await {
        Ok(event) => {
            // 发送事件作为通知
            outgoing.send_event_as_notification(&event, ...).await;

            match event.msg {
                EventMsg::ExecApprovalRequest(ev) => {
                    handle_exec_approval_request(...).await;
                    continue;  // 继续循环等待审批结果
                }
                EventMsg::TurnComplete(...) => {
                    // 返回成功响应，结束循环
                    let result = create_call_tool_result_with_thread_id(...);
                    outgoing.send_response(request_id.clone(), result).await;
                    running_requests_id_to_codex_uuid.lock().await.remove(&request_id);
                    break;
                }
                EventMsg::Error(err_event) => {
                    // 返回错误响应，结束循环
                    let result = create_call_tool_result_with_thread_id(..., Some(true));
                    outgoing.send_response(request_id.clone(), result).await;
                    break;
                }
                // 其他事件...
                _ => {}
            }
        }
        Err(e) => {
            // 运行时错误，返回错误响应
            let result = create_call_tool_result_with_thread_id(..., Some(true));
            outgoing.send_response(request_id.clone(), result).await;
            break;
        }
    }
}
```

### 审批处理集成

执行审批和补丁审批的处理委托给专门模块：

```rust
// 执行审批
EventMsg::ExecApprovalRequest(ev) => {
    let ExecApprovalRequestEvent { command, cwd, call_id, parsed_cmd, ... } = ev;
    handle_exec_approval_request(
        command, cwd, outgoing.clone(), thread.clone(),
        request_id.clone(), request_id_str.clone(),
        event.id.clone(), call_id, approval_id, parsed_cmd, thread_id,
    ).await;
    continue;
}

// 补丁审批
EventMsg::ApplyPatchApprovalRequest(ApplyPatchApprovalRequestEvent { 
    call_id, reason, grant_root, changes 
}) => {
    handle_patch_approval_request(
        call_id, reason, grant_root, changes,
        outgoing.clone(), thread.clone(),
        request_id.clone(), request_id_str.clone(),
        event.id.clone(), thread_id,
    ).await;
    continue;
}
```

## 关键代码路径与文件引用

### 内部依赖

| 依赖 | 路径 | 用途 |
|------|------|------|
| `handle_exec_approval_request` | `crate::exec_approval` | 执行审批处理 |
| `handle_patch_approval_request` | `crate::patch_approval` | 补丁审批处理 |
| `OutgoingMessageSender` | `crate::outgoing_message` | MCP 消息发送 |
| `CodexThread` | `codex_core` | Codex 线程操作 |
| `ThreadManager` | `codex_core` | 线程生命周期管理 |
| `ThreadId` | `codex_protocol` | 线程标识 |
| `Event`, `EventMsg` | `codex_protocol::protocol` | 事件类型定义 |
| `Op`, `Submission` | `codex_protocol::protocol` | 操作和提交类型 |
| `UserInput` | `codex_protocol::user_input` | 用户输入构造 |
| `CallToolResult`, `Content` | `rmcp::model` | MCP 响应类型 |

### 调用关系

```
message_processor.rs::handle_tool_call_codex()
    └─> task::spawn(async move {
            codex_tool_runner::run_codex_tool_session(...)
        })

message_processor.rs::handle_tool_call_codex_session_reply()
    └─> tokio::spawn(async move {
            codex_tool_runner::run_codex_tool_session_reply(...)
        })

codex_tool_runner.rs::run_codex_tool_session()
    ├─> thread_manager.start_thread()  [创建线程]
    ├─> outgoing.send_event_as_notification()  [发送 SessionConfigured]
    ├─> thread.submit_with_id()  [提交初始输入]
    └─> run_codex_tool_session_inner()  [事件循环]
        ├─> handle_exec_approval_request()  [执行审批]
        ├─> handle_patch_approval_request()  [补丁审批]
        └─> outgoing.send_response()  [最终响应]
```

## 依赖与外部交互

### MCP 协议交互

**作为服务器接收：**
- `tools/call` 请求（通过 `message_processor` 转发）

**作为服务器发送：**
- `codex/event` 通知（所有 Codex 事件）
- `elicitation/create` 请求（审批请求）
- `tools/call` 响应（最终结果）

### Codex 核心交互

**ThreadManager：**
- `start_thread(config)`：创建新会话
- `get_thread(thread_id)`：获取现有会话

**CodexThread：**
- `submit_with_id(submission)`：提交用户输入
- `next_event()`：获取下一个事件

### 并发模型

每个工具调用在独立的 Tokio 任务中执行：

```rust
// message_processor.rs
task::spawn(async move {
    crate::codex_tool_runner::run_codex_tool_session(...).await;
});
```

这确保：
- 消息处理器不被阻塞，可继续接收其他请求
- 多个 Codex 会话可并发执行
- 单个会话的错误不影响其他会话

## 风险、边界与改进建议

### 已知风险

1. **任务泄漏**：如果客户端断开连接而未发送取消通知， spawned 任务可能持续运行
   - 缓解：`running_requests_id_to_codex_uuid` 映射允许通过请求 ID 取消

2. **内存增长**：`running_requests_id_to_codex_uuid` 映射在以下情况清理：
   - 正常完成（`TurnComplete`）
   - 错误（`Error` 事件或运行时错误）
   - 取消通知（`handle_cancelled_notification`）
   但异常断开可能导致条目残留

3. **事件丢失**：如果 `send_event_as_notification` 失败，事件静默丢弃（仅日志警告）

### 边界情况

| 场景 | 行为 |
|------|------|
| 线程启动失败 | 立即返回错误响应，不进入事件循环 |
| 初始提交失败 | 返回错误响应，清理映射 |
| 审批响应超时 | 由 `exec_approval.rs` 处理（默认拒绝） |
| 事件流中断 | 返回运行时错误响应 |
| 重复 `SessionConfigured` | 记录错误日志（`tracing::error`）但不中断 |

### 待实现功能（TODO）

代码中标记的待实现项：

```rust
EventMsg::ElicitationRequest(_) => {
    // TODO: forward elicitation requests to the client?
    continue;
}
EventMsg::AgentMessageDelta(_) => {
    // TODO: think how we want to support this in the MCP
}
EventMsg::AgentReasoningDelta(_) => {
    // TODO: think how we want to support this in the MCP
}
```

### 改进建议

1. **会话超时**：添加整体会话超时机制，防止长时间运行的任务占用资源

2. **心跳检测**：实现客户端心跳检测，自动清理断连会话

3. **流式响应**：考虑支持 `AgentMessageDelta` 事件的流式传输，提供更好的实时反馈

4. **优雅关闭**：实现 graceful shutdown，等待进行中的会话完成或超时

5. **指标收集**：添加 Prometheus 风格的指标（会话数、事件数、延迟等）

6. **错误分类**：细化错误类型，区分可重试错误和永久错误

### 测试覆盖

包含一个单元测试：
- `call_tool_result_includes_thread_id_in_structured_content`：验证响应包含 `threadId`

集成测试在 `tests/suite/codex_tool.rs` 中：
- `test_shell_command_approval_triggers_elicitation`：执行审批流程
- `test_patch_approval_triggers_elicitation`：补丁审批流程
- `test_codex_tool_passes_base_instructions`：配置传递验证
