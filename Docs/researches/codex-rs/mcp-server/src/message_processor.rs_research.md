# message_processor.rs 研究文档

## 场景与职责

`message_processor.rs` 是 Codex MCP 服务器的核心消息处理器，负责实现 MCP（Model Context Protocol）协议的服务器端逻辑。它处理所有传入的 JSON-RPC 消息，包括初始化、工具发现、工具调用和通知。

**核心职责：**
1. 处理 MCP 初始化握手（`initialize`）
2. 响应工具列表查询（`tools/list`）
3. 执行工具调用（`tools/call`）- `codex` 和 `codex-reply`
4. 处理取消通知（`notifications/cancelled`）
5. 管理 Codex 线程生命周期

## 功能点目的

### 1. MessageProcessor 结构

```rust
pub(crate) struct MessageProcessor {
    outgoing: Arc<OutgoingMessageSender>,
    initialized: bool,
    arg0_paths: Arg0DispatchPaths,
    thread_manager: Arc<ThreadManager>,
    running_requests_id_to_codex_uuid: Arc<Mutex<HashMap<RequestId, ThreadId>>>,
}
```

**字段说明：**
- `outgoing`：出站消息发送器，用于响应和通知
- `initialized`：跟踪初始化状态，防止重复初始化
- `arg0_paths`：辅助可执行文件路径
- `thread_manager`：Codex 线程管理器，创建和管理会话
- `running_requests_id_to_codex_uuid`：MCP 请求 ID 到 Codex 线程 ID 的映射（用于取消）

### 2. 构造函数

```rust
pub(crate) fn new(
    outgoing: OutgoingMessageSender,
    arg0_paths: Arg0DispatchPaths,
    config: Arc<Config>,
) -> Self
```

**初始化流程：**
1. 创建 `AuthManager`（共享实例）
2. 创建 `ThreadManager`，配置会话源为 `SessionSource::Mcp`
3. 初始化请求 ID 到线程 ID 的映射

### 3. 请求处理

```rust
pub(crate) async fn process_request(&mut self, request: JsonRpcRequest<ClientRequest>)
```

**支持的方法：**

| 方法 | 处理函数 | 说明 |
|------|---------|------|
| `initialize` | `handle_initialize` | 协议初始化 |
| `ping` | `handle_ping` | 保活检查 |
| `tools/list` | `handle_list_tools` | 列出可用工具 |
| `tools/call` | `handle_call_tool` | 调用工具 |
| `resources/list` | `handle_list_resources` | 列出资源（未实现） |
| `resources/read` | `handle_read_resource` | 读取资源（未实现） |
| `prompts/list` | `handle_list_prompts` | 列出提示（未实现） |
| `tasks/*` | `handle_unsupported_request` | 不支持的任务 API |

### 4. 工具调用处理

**codex 工具：**
```rust
async fn handle_tool_call_codex(&self, id: RequestId, arguments: Option<JsonObject>)
```

流程：
1. 解析参数为 `CodexToolCallParam`
2. 转换为 `Config` 配置对象
3. 在独立任务中启动 `run_codex_tool_session`

**codex-reply 工具：**
```rust
async fn handle_tool_call_codex_session_reply(&self, request_id: RequestId, arguments: Option<JsonObject>)
```

流程：
1. 解析参数为 `CodexToolCallReplyParam`
2. 提取 `thread_id`
3. 从 `thread_manager` 获取现有线程
4. 在独立任务中启动 `run_codex_tool_session_reply`

### 5. 取消处理

```rust
async fn handle_cancelled_notification(&self, params: CancelledNotificationParam)
```

流程：
1. 从映射中获取线程 ID
2. 从 `thread_manager` 获取线程
3. 提交 `Op::Interrupt` 操作
4. 从映射中移除请求 ID

## 具体技术实现

### 初始化处理

```rust
async fn handle_initialize(&mut self, id: RequestId, params: InitializeRequestParams) {
    // 1. 检查重复初始化
    if self.initialized {
        self.outgoing.send_error(id, ErrorData::invalid_request(...)).await;
        return;
    }

    // 2. 设置 User-Agent 后缀
    let user_agent_suffix = format!("{name}; {version}", 
        name = params.client_info.name, 
        version = params.client_info.version
    );
    if let Ok(mut suffix) = USER_AGENT_SUFFIX.lock() {
        *suffix = Some(user_agent_suffix);
    }

    // 3. 构建服务器信息
    let server_info = Implementation {
        name: "codex-mcp-server".to_string(),
        title: Some("Codex".to_string()),
        version: env!("CARGO_PKG_VERSION").to_string(),
        ...
    };

    // 4. 添加非标准 user_agent 字段
    let mut server_info_value = serde_json::to_value(&server_info).unwrap();
    if let serde_json::Value::Object(ref mut obj) = server_info_value {
        obj.insert("user_agent".to_string(), json!(get_codex_user_agent()));
    }

    // 5. 构建能力声明
    let result = InitializeResult {
        capabilities: ServerCapabilities {
            tools: Some(ToolsCapability { list_changed: Some(true) }),
            ..Default::default()
        },
        ...
    };

    self.initialized = true;
    self.outgoing.send_response(id, result_value).await;
}
```

### 工具列表

```rust
async fn handle_list_tools(&self, id: RequestId, params: Option<PaginatedRequestParams>) {
    let result = ListToolsResult {
        meta: None,
        tools: vec![
            create_tool_for_codex_tool_call_param(),       // codex 工具
            create_tool_for_codex_tool_call_reply_param(), // codex-reply 工具
        ],
        next_cursor: None,
    };
    self.outgoing.send_response(id, result).await;
}
```

### 工具调用分派

```rust
async fn handle_call_tool(&self, id: RequestId, params: CallToolRequestParams) {
    let CallToolRequestParams { name, arguments, .. } = params;

    match name.as_ref() {
        "codex" => self.handle_tool_call_codex(id, arguments).await,
        "codex-reply" => self.handle_tool_call_codex_session_reply(id, arguments).await,
        _ => {
            // 返回未知工具错误
            let result = CallToolResult {
                content: vec![Content::text(format!("Unknown tool '{name}'"))],
                is_error: Some(true),
                ...
            };
            self.outgoing.send_response(id, result).await;
        }
    }
}
```

### 异步任务启动

```rust
async fn handle_tool_call_codex(&self, id: RequestId, arguments: Option<JsonObject>) {
    // ... 参数解析和配置加载 ...

    // 克隆必要数据
    let outgoing = self.outgoing.clone();
    let thread_manager = self.thread_manager.clone();
    let running_requests_id_to_codex_uuid = self.running_requests_id_to_codex_uuid.clone();

    // 在独立任务中执行
    task::spawn(async move {
        crate::codex_tool_runner::run_codex_tool_session(
            id, initial_prompt, config, 
            outgoing, thread_manager, running_requests_id_to_codex_uuid
        ).await;
    });
}
```

### 取消通知处理

```rust
async fn handle_cancelled_notification(&self, params: CancelledNotificationParam) {
    let request_id = params.request_id;
    let request_id_string = request_id.to_string();

    // 1. 获取线程 ID
    let thread_id = {
        let map_guard = self.running_requests_id_to_codex_uuid.lock().await;
        match map_guard.get(&request_id) {
            Some(id) => *id,
            None => {
                tracing::warn!("Session not found for request_id: {request_id_string}");
                return;
            }
        }
    };

    // 2. 获取线程
    let codex_arc = match self.thread_manager.get_thread(thread_id).await {
        Ok(c) => c,
        Err(_) => {
            tracing::warn!("Session not found for thread_id: {thread_id}");
            return;
        }
    };

    // 3. 提交中断
    if let Err(e) = codex_arc
        .submit_with_id(Submission {
            id: request_id_string,
            op: Op::Interrupt,
            trace: None,
        })
        .await
    {
        tracing::error!("Failed to submit interrupt: {e}");
        return;
    }

    // 4. 清理映射
    self.running_requests_id_to_codex_uuid.lock().await.remove(&request_id);
}
```

## 关键代码路径与文件引用

### 内部依赖

| 依赖 | 路径 | 用途 |
|------|------|------|
| `CodexToolCallParam` | `crate::codex_tool_config` | codex 工具参数 |
| `CodexToolCallReplyParam` | `crate::codex_tool_config` | codex-reply 工具参数 |
| `create_tool_for_*` | `crate::codex_tool_config` | 工具定义创建 |
| `run_codex_tool_session` | `crate::codex_tool_runner` | 会话执行 |
| `run_codex_tool_session_reply` | `crate::codex_tool_runner` | 回复执行 |
| `OutgoingMessageSender` | `crate::outgoing_message` | 消息发送 |

### 外部依赖

| 依赖 | 路径 | 用途 |
|------|------|------|
| `Arg0DispatchPaths` | `codex_arg0` | 辅助可执行文件路径 |
| `AuthManager` | `codex_core` | 认证管理 |
| `ThreadManager` | `codex_core` | 线程生命周期管理 |
| `Config` | `codex_core::config` | 配置对象 |
| `SessionSource` | `codex_protocol::protocol` | 会话来源标记 |
| `CollaborationModesConfig` | `codex_core::models_manager` | 协作模式配置 |
| `ThreadId` | `codex_protocol` | 线程标识 |
| `Submission`, `Op` | `codex_protocol::protocol` | 提交和操作类型 |
| `ClientRequest`, `CallToolResult` | `rmcp::model` | MCP 协议类型 |

### 调用关系

```
lib.rs::processor task
    └─> MessageProcessor::process_request()
        ├─> handle_initialize()        [初始化]
        ├─> handle_ping()              [保活]
        ├─> handle_list_tools()        [工具列表]
        ├─> handle_call_tool()         [工具调用]
        │   ├─> handle_tool_call_codex()
        │   │   └─> task::spawn(run_codex_tool_session(...))
        │   └─> handle_tool_call_codex_session_reply()
        │       └─> tokio::spawn(run_codex_tool_session_reply(...))
        └─> process_notification()
            └─> handle_cancelled_notification()
                └─> thread.submit_with_id(Submission { op: Op::Interrupt, ... })
```

## 依赖与外部交互

### MCP 协议实现

**服务器能力声明：**
```json
{
    "capabilities": {
        "tools": {
            "listChanged": true
        }
    },
    "serverInfo": {
        "name": "codex-mcp-server",
        "title": "Codex",
        "version": "0.0.0",
        "user_agent": "..."
    },
    "protocolVersion": "2025-03-26"
}
```

**非标准扩展：**
- `serverInfo.user_agent`：Codex 特定的 User-Agent 字段

### ThreadManager 集成

**创建线程：**
```rust
let thread_manager = Arc::new(ThreadManager::new(
    config.as_ref(),
    auth_manager,
    SessionSource::Mcp,  // 标记会话来源为 MCP
    CollaborationModesConfig { ... },
));
```

**获取线程：**
```rust
let codex = match self.thread_manager.get_thread(thread_id).await {
    Ok(c) => c,
    Err(_) => {
        // 返回会话未找到错误
    }
};
```

### 并发模型

- 每个工具调用在独立的 Tokio 任务中执行
- `MessageProcessor` 本身不被阻塞，可继续处理其他请求
- 取消操作通过 `Op::Interrupt` 异步提交

## 风险、边界与改进建议

### 已知风险

1. **重复初始化**：检查 `self.initialized` 防止重复，但错误响应后状态可能不一致

2. **任务泄漏**：`task::spawn` 创建的任务没有句柄跟踪，如果客户端断开可能持续运行
   - 缓解：`running_requests_id_to_codex_uuid` 映射允许取消

3. **资源未实现**：`resources/*` 和 `prompts/*` 方法仅记录日志，返回空响应

4. **错误处理不一致**：某些错误发送 MCP 错误响应，某些仅记录日志

### 边界情况

| 场景 | 行为 |
|------|------|
| 未知工具名称 | 返回 `is_error: true` 的 `CallToolResult` |
| 会话未找到（reply） | 返回错误响应，包含 "Session not found" |
| 参数解析失败 | 返回错误响应，包含解析错误信息 |
| 取消未找到的请求 | 记录警告，静默返回 |
| 取消已完成的请求 | 提交中断（可能被忽略） |

### 改进建议

1. **资源实现**：实现 `resources/list` 和 `resources/read`，暴露 Codex 会话历史

2. **提示实现**：实现 `prompts/list` 和 `prompts/get`，提供常用提示模板

3. **任务追踪**：使用 `JoinSet` 或类似结构追踪 spawned 任务，支持优雅关闭
   ```rust
   let mut tasks: JoinSet<()> = JoinSet::new();
   tasks.spawn(async move { ... });
   ```

4. **限流**：添加并发工具调用限制，防止资源耗尽
   ```rust
   let semaphore = Arc::new(Semaphore::new(MAX_CONCURRENT_CALLS));
   ```

5. **健康检查**：实现 `health/check` 方法或定期发送 `ping`

6. **元数据增强**：在工具定义中添加更多元数据（图标、描述等）

7. **分页支持**：当前 `tools/list` 返回所有工具，大列表需要分页

### 测试覆盖

单元测试主要在 `tests/suite/codex_tool.rs`：
- `test_shell_command_approval_triggers_elicitation`：执行审批流程
- `test_patch_approval_triggers_elicitation`：补丁审批流程
- `test_codex_tool_passes_base_instructions`：配置传递

测试辅助在 `tests/common/mcp_process.rs`：
- `McpProcess`：MCP 进程管理和消息交换
