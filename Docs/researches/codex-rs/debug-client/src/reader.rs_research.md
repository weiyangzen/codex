# reader.rs 深度研究文档

## 场景与职责

`reader.rs` 是 debug-client 的后台读取线程实现，负责从 app-server 的 stdout 持续读取 JSON-RPC 消息，解析并分发到主线程。它是客户端架构中的关键并发组件，实现了真正的异步响应处理。

**核心定位**：
- 后台线程入口（`start_reader` 函数）
- JSON-RPC 消息解析和路由
- 服务端请求的自动响应（审批请求）
- 过滤输出模式支持（`--final-only`）

**使用场景**：
- 持续监听服务器通知（如 `ItemCompleted`）
- 自动处理审批请求（接受或拒绝）
- 异步接收线程操作结果（start/resume/list）
- 在过滤模式下仅显示最终消息

## 功能点目的

### 1. 读取线程启动

```rust
pub fn start_reader(
    mut stdout: BufReader<ChildStdout>,
    stdin: Arc<Mutex<Option<std::process::ChildStdin>>>,
    state: Arc<Mutex<State>>,
    events: Sender<ReaderEvent>,
    output: Output,
    auto_approve: bool,
    filtered_output: bool,
) -> JoinHandle<()>
```

**参数设计**：
- `stdout`：app-server 的标准输出，使用 `BufReader` 缓冲
- `stdin`：共享的 stdin 句柄，用于响应服务端请求
- `state`：共享状态，用于跟踪 pending 请求
- `events`：向主线程发送事件的通道
- `output`：输出处理器
- `auto_approve`：是否自动接受审批请求
- `filtered_output`：是否启用过滤模式

**线程创建**（行43-107）：
```rust
thread::spawn(move || {
    let command_decision = if auto_approve { Accept } else { Decline };
    let file_decision = if auto_approve { Accept } else { Decline };
    
    loop {
        buffer.clear();
        match stdout.read_line(&mut buffer) {
            Ok(0) => break,  // EOF，服务器关闭
            Ok(_) => { /* 处理行 */ }
            Err(err) => { /* 打印错误并退出 */ }
        }
    }
})
```

### 2. 消息路由

**主循环**（行77-105）：
```rust
match message {
    JSONRPCMessage::Request(request) => {
        handle_server_request(request, &command_decision, &file_decision, &stdin, &output)
    }
    JSONRPCMessage::Response(response) => {
        handle_response(response, &state, &events)
    }
    JSONRPCMessage::Notification(notification) => {
        if filtered_output {
            handle_filtered_notification(notification, &output)
        }
    }
    _ => {}
}
```

**路由策略**：
| 消息类型 | 处理方式 | 说明 |
|----------|----------|------|
| Request | 立即响应 | 主要是审批请求 |
| Response | 状态更新 + 事件 | 匹配 pending 请求 |
| Notification | 可选过滤 | 过滤模式下仅显示完成项 |

### 3. 服务端请求处理

**handle_server_request**（行109-142）：

支持的服务端请求：

| 请求类型 | 自动响应 | 日志输出 |
|----------|----------|----------|
| `CommandExecutionRequestApproval` | `command_decision` | 显示请求 ID 和决策 |
| `FileChangeRequestApproval` | `file_decision` | 显示请求 ID 和决策 |

**实现**（行122-139）：
```rust
ServerRequest::CommandExecutionRequestApproval { request_id, params } => {
    let response = CommandExecutionRequestApprovalResponse {
        decision: command_decision.clone(),
    };
    output.client_line(&format!(
        "auto-response for command approval {request_id:?}: {command_decision:?} ({params:?})"
    ))?;
    send_response(stdin, request_id, response)
}
```

**设计意图**：
- 审批请求需要立即响应，不能等待用户输入
- 默认拒绝策略保证安全
- `auto_approve` 模式用于自动化场景

### 4. 响应处理

**handle_response**（行144-207）：

**流程**：
1. 从 `state.pending` 中移除对应请求
2. 如果无 pending 记录，忽略响应
3. 根据 `PendingRequest` 类型解析响应
4. 更新 `state.thread_id` 和 `known_threads`
5. 发送 `ReaderEvent` 到主线程

**响应类型处理**：

| Pending 类型 | 响应类型 | 行为 |
|--------------|----------|------|
| `Start` | `ThreadStartResponse` | 更新线程 ID，发送 `ThreadReady` |
| `Resume` | `ThreadResumeResponse` | 同上 |
| `List` | `ThreadListResponse` | 更新已知线程，发送 `ThreadList` |

**代码示例**（行159-171）：
```rust
PendingRequest::Start => {
    let parsed = serde_json::from_value::<ThreadStartResponse>(response.result)?;
    let thread_id = parsed.thread.id;
    {
        let mut state = state.lock().expect("state lock poisoned");
        state.thread_id = Some(thread_id.clone());
        if !state.known_threads.iter().any(|id| id == &thread_id) {
            state.known_threads.push(thread_id.clone());
        }
    }
    events.send(ReaderEvent::ThreadReady { thread_id }).ok();
}
```

### 5. 过滤通知处理

**handle_filtered_notification**（行209-223）：

仅处理 `ItemCompleted` 通知：
```rust
match server_notification {
    ServerNotification::ItemCompleted(payload) => {
        emit_filtered_item(payload.item, &payload.thread_id, output)
    }
    _ => Ok(()),
}
```

**emit_filtered_item**（行225-301）：

根据 `ThreadItem` 类型格式化输出：

| Item 类型 | 输出格式 |
|-----------|----------|
| `AgentMessage` | `[thread] assistant: text` |
| `Plan` | `[thread] assistant: plan` + 多行内容 |
| `CommandExecution` | `[thread] tool: command (status)` + exit_code + output |
| `FileChange` | `[thread] tool: file change (status, N files)` |
| `McpToolCall` | `[thread] tool: server.tool (status)` + args/result/error |

**颜色标记**（使用 `output.format_label`）：
- `LabelColor::Thread`（蓝色）：线程 ID
- `LabelColor::Assistant`（绿色）：助手消息
- `LabelColor::Tool`（青色）：工具调用
- `LabelColor::ToolMeta`（黄色）：工具元信息

### 6. 辅助函数

**write_multiline**（行303-314）：
```rust
fn write_multiline(
    output: &Output,
    thread_label: &str,
    header: &str,
    text: &str,
) -> anyhow::Result<()>
```
- 为多行文本添加缩进前缀
- 保持视觉层次

**send_response**（行316-337）：
```rust
fn send_response<T: Serialize>(
    stdin: &Arc<Mutex<Option<std::process::ChildStdin>>>,
    request_id: RequestId,
    response: T,
) -> anyhow::Result<()>
```
- 序列化响应为 JSON-RPC
- 通过共享 stdin 发送

## 具体技术实现

### 关键流程

**读取循环**：
```
start_reader()
    ↓
thread::spawn
    ↓
loop:
    stdout.read_line()
        ↓
    trim_end_matches(['\n', '\r'])
        ↓
    if !filtered_output: output.server_line(raw_line)
        ↓
    serde_json::from_str::<JSONRPCMessage>()
        ↓
    match message type:
        Request → handle_server_request()
        Response → handle_response()
        Notification → handle_filtered_notification() [if filtered]
```

**响应处理流程**：
```
handle_response(response, state, events)
    ↓
state.pending.remove(&response.id)
    ↓
if let Some(pending):
    match pending:
        Start → parse ThreadStartResponse
        Resume → parse ThreadResumeResponse
        List → parse ThreadListResponse
    ↓
    update state.thread_id
    update state.known_threads
    ↓
    events.send(ReaderEvent::...)
```

### 数据结构关系

```
reader thread
    ├─ stdout: BufReader<ChildStdout>     // 输入源
    ├─ stdin: Arc<Mutex<Option<ChildStdin>>>  // 输出目标（共享）
    ├─ state: Arc<Mutex<State>>           // 共享状态
    │           ├─ pending: HashMap<RequestId, PendingRequest>
    │           ├─ thread_id: Option<String>
    │           └─ known_threads: Vec<String>
    ├─ events: Sender<ReaderEvent>        // 到主线程的通道
    ├─ output: Output                     // 输出处理器
    ├─ command_decision: CommandExecutionApprovalDecision
    └─ file_decision: FileChangeApprovalDecision
```

### 并发模型

```
┌─────────────────┐         ┌─────────────────┐
│   主线程         │ ←───── │   reader 线程   │
│                 │  events │                 │
│  - 读取 stdin   │         │  - 读取 stdout  │
│  - 发送请求     │         │  - 解析 JSON    │
│  - 处理事件     │         │  - 自动响应     │
│                 │         │  - 发送事件     │
└─────────────────┘         └─────────────────┘
        ↓                           ↓
   stdin (写入)                stdout (读取)
        ↓                           ↓
        └───────────┬───────────────┘
                    ↓
              app-server 子进程
```

**同步机制**：
- `mpsc::channel`：reader → main 的事件流（单向）
- `Arc<Mutex<State>>`：共享状态（双向读写）
- `Arc<Mutex<Option<ChildStdin>>>`：共享输入（reader 写入）

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `output.rs` | `Output`, `LabelColor` |
| `state.rs` | `PendingRequest`, `ReaderEvent`, `State` |

### 外部依赖

| Crate | 类型 | 用途 |
|-------|------|------|
| `codex-app-server-protocol` | 协议 | JSON-RPC 类型、ServerRequest、ServerNotification、ThreadItem 等 |
| `anyhow` | 错误 | 错误处理 |
| `serde`/`serde_json` | 序列化 | JSON 解析 |

### 调用关系

**被调用方**（来自 client.rs）：
```rust
// client.rs:209-226
pub fn start_reader(
    &mut self,
    events: Sender<ReaderEvent>,
    auto_approve: bool,
    filtered_output: bool,
) -> Result<()> {
    let stdout = self.stdout.take().context("reader already started")?;
    start_reader(stdout, Arc::clone(&self.stdin), Arc::clone(&self.state), ...);
    Ok(())
}
```

**调用上游**（到 main.rs）：
```rust
// 通过 events 通道
events.send(ReaderEvent::ThreadReady { thread_id }).ok();
events.send(ReaderEvent::ThreadList { thread_ids, next_cursor }).ok();
```

## 依赖与外部交互

### 协议类型使用

| 类型 | 来源 | 用途 |
|------|------|------|
| `JSONRPCMessage` | `jsonrpc_lite.rs` | 消息枚举 |
| `ServerRequest` | `protocol/common.rs` | 服务端请求解析 |
| `ServerNotification` | `protocol/common.rs` | 通知解析 |
| `ThreadItem` | `protocol/v2.rs` | 过滤输出格式化 |
| `CommandExecutionApprovalDecision` | `protocol/v2.rs` | 审批决策 |
| `FileChangeApprovalDecision` | `protocol/v2.rs` | 审批决策 |

### ThreadItem 变体

```rust
pub enum ThreadItem {
    UserMessage { id: String, content: Vec<UserInput> },
    AgentMessage { id: String, text: String, phase: Option<MessagePhase>, memory_citation: Option<MemoryCitation> },
    Plan { id: String, text: String },
    Reasoning { id: String, summary: Vec<String>, content: Vec<String> },
    CommandExecution { command: Vec<String>, status: ExecCommandStatus, exit_code: Option<i32>, aggregated_output: Option<String>, ... },
    FileChange { changes: Vec<FileChangeDetail>, status: PatchApplyStatus, ... },
    McpToolCall { server: String, tool: String, status: McpToolCallStatus, arguments: Value, result: Option<Value>, error: Option<String>, ... },
    // ... 其他变体
}
```

当前 `emit_filtered_item` 处理：
- ✅ `AgentMessage`
- ✅ `Plan`
- ✅ `CommandExecution`
- ✅ `FileChange`
- ✅ `McpToolCall`
- ❌ `UserMessage`（不显示，因为是用户自己发送的）
- ❌ `Reasoning`（不显示，中间推理过程）

## 风险、边界与改进建议

### 当前风险

**1. 错误静默处理**
```rust
let Ok(message) = serde_json::from_str::<JSONRPCMessage>(line) else {
    continue;  // 静默丢弃无法解析的行
};
```
- 无法解析的 JSON 被忽略
- 可能丢失重要错误信息

**2. 通道发送失败忽略**
```rust
events.send(ReaderEvent::ThreadReady { thread_id }).ok();
```
- 如果主线程已退出，事件丢失无感知

**3. 锁 Poison 风险**
```rust
let mut state = state.lock().expect("state lock poisoned");
```
- 使用 `expect` 可能导致 panic

**4. 响应类型不匹配**
```rust
let parsed = serde_json::from_value::<ThreadStartResponse>(response.result)?;
```
- 如果服务器返回错误格式，解析失败
- 错误信息可能不够具体

### 边界情况

**1. 大消息处理**
- `read_line` 读取整行到 `String`
- 极端大的 JSON 可能消耗大量内存
- 无大小限制或流式处理

**2. 消息顺序**
- 依赖 `mpsc` 通道保证事件顺序
- 但 `filtered_output` 模式可能改变输出顺序（原始行 vs 过滤后的格式化输出）

**3. EOF 处理**
```rust
Ok(0) => break,  // 服务器关闭 stdout
```
- 正常退出，但无通知到主线程
- 主线程可能在 `lines.next()` 阻塞，无法及时响应

**4. 线程 ID 重复**
```rust
if !state.known_threads.iter().any(|id| id == &thread_id) {
    state.known_threads.push(thread_id.clone());
}
```
- 线性查找，线程数量大时效率低
- 建议使用 `HashSet`

### 改进建议

**1. 错误日志**
```rust
// 建议：记录解析错误
let Ok(message) = serde_json::from_str::<JSONRPCMessage>(line) else {
    eprintln!("[reader] Failed to parse: {}", line);
    continue;
};
```

**2. 使用 parking_lot**
```rust
// 建议：parking_lot::Mutex 无 poison
use parking_lot::Mutex;
let mut state = state.lock();
```

**3. 响应超时检测**
```rust
// 建议：检测长期未响应的 pending 请求
struct PendingRequestInfo {
    kind: PendingRequest,
    sent_at: Instant,
}
// 定期检查并警告超时
```

**4. 批量事件处理**
```rust
// 建议：支持批量发送减少通道开销
let events: Vec<ReaderEvent> = ...;
for event in events {
    if events_tx.send(event).is_err() { break; }
}
```

**5. 更丰富的过滤选项**
```rust
// 建议：可配置的过滤级别
pub enum FilterLevel {
    None,       // 所有消息
    Final,      // 仅完成项（当前）
    Assistant,  // 仅助手消息
    Tool,       // 包含工具结果
}
```

**6. 进度指示**
```rust
// 建议：长时间操作时显示进度
ServerNotification::TurnInProgress(payload) => {
    if payload.processing_state == ProcessingState::Generating {
        output.client_line("Assistant is thinking...")?;
    }
}
```

### 代码质量

**优点**：
- 清晰的职责分离
- 完整的消息路由处理
- 过滤模式提供良好的用户体验

**可改进点**：
- 部分错误被静默忽略
- 无测试覆盖
- 硬编码的输出格式

### 与 AGENTS.md 规范符合度

检查项目规范：
- ✅ 使用 `format!` 内联变量（多处）
- ✅ 模块小于 500 LoC（实际 337 行，接近边界）
- ✅ 避免大型模块（符合要求）

无违规项。

### 潜在内存/性能问题

**1. String 分配**
```rust
let mut buffer = String::new();
loop {
    buffer.clear();
    stdout.read_line(&mut buffer)?;
    // buffer 容量只增不减
}
```
- 如果收到极大消息，缓冲区永久保持大容量
- 建议定期 `shrink_to_fit` 或使用固定容量缓冲区

**2. 线程堆栈**
- 默认线程堆栈大小（通常 2MB）
- 当前实现递归深度有限，无栈溢出风险
