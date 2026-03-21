# codex-rs/mcp-server/src 目录研究文档

## 目录信息

- **路径**: `codex-rs/mcp-server/src/`
- **研究日期**: 2026-03-21
- **用途**: Codex MCP (Model Context Protocol) 服务器实现

---

## 1. 场景与职责

### 1.1 整体定位

`codex-mcp-server` 是 Codex 项目的 **MCP (Model Context Protocol)** 服务器实现，作为 Codex 核心功能与 MCP 客户端之间的桥梁。它通过标准输入输出 (stdio) 与 MCP 客户端通信，使用 JSON-RPC 2.0 协议进行消息交换。

### 1.2 核心职责

1. **协议适配**: 将 MCP 协议的 JSON-RPC 消息转换为 Codex 内部协议
2. **工具暴露**: 向 MCP 客户端暴露 `codex` 和 `codex-reply` 两个核心工具
3. **会话管理**: 管理 Codex 线程生命周期，支持多会话并发
4. **审批代理**: 将执行审批 (exec approval) 和补丁审批 (patch approval) 请求转发给 MCP 客户端
5. **事件流**: 将 Codex 内部事件流式传输给 MCP 客户端

### 1.3 使用场景

- **IDE 集成**: VS Code、Cursor 等编辑器通过 MCP 协议调用 Codex
- **自动化工作流**: CI/CD 管道通过 MCP 调用 Codex 进行代码审查或生成
- **多客户端环境**: 单个 Codex 实例服务多个 MCP 客户端请求

---

## 2. 功能点目的

### 2.1 核心工具

#### `codex` 工具
- **用途**: 启动新的 Codex 会话
- **输入**: 初始提示词、模型配置、沙盒策略、审批策略等
- **输出**: 会话 ID (threadId) 和生成的内容
- **配置项**:
  - `prompt`: 初始用户提示（必需）
  - `model`: 模型名称覆盖
  - `profile`: 配置 profile
  - `cwd`: 工作目录
  - `approval-policy`: 审批策略 (untrusted/on-failure/on-request/never)
  - `sandbox`: 沙盒模式 (read-only/workspace-write/danger-full-access)
  - `config`: 额外的配置覆盖
  - `base-instructions`/`developer-instructions`: 自定义指令

#### `codex-reply` 工具
- **用途**: 继续已有的 Codex 会话
- **输入**: 会话 ID (threadId) 和后续提示词
- **输出**: 更新的内容和会话 ID
- **向后兼容**: 支持已废弃的 `conversationId` 字段

### 2.2 审批机制

#### 执行审批 (Exec Approval)
- **触发条件**: 模型生成需要执行的 shell 命令且未在信任列表中
- **处理流程**:
  1. Codex 生成 `ExecApprovalRequest` 事件
  2. MCP 服务器发送 `elicitation/create` 请求给客户端
  3. 客户端响应 `ReviewDecision` (Approved/Denied)
  4. MCP 服务器将决策提交回 Codex

#### 补丁审批 (Patch Approval)
- **触发条件**: 模型生成文件修改 (apply_patch) 操作
- **处理流程**: 类似执行审批，但针对文件变更

### 2.3 事件通知

MCP 服务器通过 `codex/event` 通知将 Codex 内部事件转发给客户端，包括:
- `SessionConfigured`: 会话配置完成
- `ExecApprovalRequest`: 需要执行审批
- `ApplyPatchApprovalRequest`: 需要补丁审批
- `TurnComplete`: 一轮对话完成
- `AgentMessage`: 代理消息
- `Error`: 错误事件

---

## 3. 具体技术实现

### 3.1 架构概览

```
┌─────────────────┐     JSON-RPC      ┌──────────────────┐
│   MCP Client    │ ◄───────────────► │  codex-mcp-server │
│  (IDE/Editor)   │    (stdio)        │                  │
└─────────────────┘                   └────────┬─────────┘
                                               │
                    ┌──────────────────────────┼──────────┐
                    │                          │          │
                    ▼                          ▼          ▼
            ┌──────────────┐          ┌──────────────┐  ┌──────────┐
            │   CodexTool  │          │  CodexThread │  │ ThreadManager│
            │   Runner     │          │              │  │              │
            └──────────────┘          └──────────────┘  └──────────┘
```

### 3.2 关键数据结构

#### 消息类型 (lib.rs)
```rust
type IncomingMessage = JsonRpcMessage<ClientRequest, Value, ClientNotification>;
```

#### 请求 ID 到线程 ID 映射
```rust
running_requests_id_to_codex_uuid: Arc<Mutex<HashMap<RequestId, ThreadId>>>
```
用于跟踪哪个 MCP 请求对应哪个 Codex 线程，支持取消操作。

#### 工具配置结构 (codex_tool_config.rs)
```rust
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct CodexToolCallParam {
    pub prompt: String,
    pub model: Option<String>,
    pub profile: Option<String>,
    pub cwd: Option<String>,
    pub approval_policy: Option<CodexToolCallApprovalPolicy>,
    pub sandbox: Option<CodexToolCallSandboxMode>,
    pub config: Option<HashMap<String, serde_json::Value>>,
    pub base_instructions: Option<String>,
    pub developer_instructions: Option<String>,
    pub compact_prompt: Option<String>,
}
```

### 3.3 关键流程

#### 3.3.1 初始化流程 (lib.rs:run_main)

1. **配置加载**: 解析 CLI 覆盖并加载 Config
2. **OpenTelemetry 初始化**: 设置日志、追踪和指标导出
3. **通道创建**: 创建有界输入通道 (容量 128) 和无界输出通道
4. **启动三个并发任务**:
   - `stdin_reader`: 从 stdin 读取 JSON-RPC 消息，发送到 `incoming_tx`
   - `processor`: 处理输入消息，分发到对应处理器
   - `stdout_writer`: 从 `outgoing_rx` 接收消息，写入 stdout

#### 3.3.2 消息处理流程 (message_processor.rs)

**请求处理** (`process_request`):
```rust
match client_request {
    ClientRequest::InitializeRequest(params) => handle_initialize(...).await,
    ClientRequest::PingRequest(_) => handle_ping(...).await,
    ClientRequest::ListToolsRequest(params) => handle_list_tools(...).await,
    ClientRequest::CallToolRequest(params) => handle_call_tool(...).await,
    // ... 其他请求类型
}
```

**工具调用处理** (`handle_call_tool`):
1. 根据工具名 (`codex` 或 `codex-reply`) 分发到对应处理器
2. 解析参数并验证
3. 获取或创建 Codex 线程
4. 在独立 Tokio 任务中运行会话
5. 立即返回，后续通过事件通知和最终响应完成交互

#### 3.3.3 会话执行流程 (codex_tool_runner.rs)

**新会话** (`run_codex_tool_session`):
1. 调用 `thread_manager.start_thread(config)` 创建新线程
2. 发送 `SessionConfigured` 事件通知
3. 提交初始用户输入 (`Op::UserInput`)
4. 进入事件循环 (`run_codex_tool_session_inner`)

**继续会话** (`run_codex_tool_session_reply`):
1. 通过 `thread_manager.get_thread(thread_id)` 获取现有线程
2. 提交后续用户输入
3. 进入事件循环

**事件循环** (`run_codex_tool_session_inner`):
```rust
loop {
    match thread.next_event().await {
        Ok(event) => {
            // 发送事件作为通知
            outgoing.send_event_as_notification(&event, ...).await;
            
            match event.msg {
                EventMsg::ExecApprovalRequest(ev) => {
                    handle_exec_approval_request(...).await;
                    continue; // 等待用户响应
                }
                EventMsg::ApplyPatchApprovalRequest(ev) => {
                    handle_patch_approval_request(...).await;
                    continue;
                }
                EventMsg::TurnComplete(_) => {
                    // 发送最终响应，退出循环
                    outgoing.send_response(request_id, result).await;
                    break;
                }
                EventMsg::Error(err) => {
                    // 发送错误响应，退出循环
                    outgoing.send_response(request_id, error_result).await;
                    break;
                }
                // ... 其他事件类型
            }
        }
        Err(e) => { /* 处理错误 */ }
    }
}
```

#### 3.3.4 审批处理流程

**执行审批** (exec_approval.rs):
1. 构造 `ExecApprovalElicitRequestParams`，包含:
   - `message`: 用户可见的审批提示
   - `requested_schema`: 请求的响应格式
   - `codex_*` 字段: Codex 特定的上下文信息
2. 发送 `elicitation/create` 请求给 MCP 客户端
3. 在独立任务中等待响应 (`on_exec_approval_response`)
4. 解析响应为 `ExecApprovalResponse`，提取 `decision`
5. 提交 `Op::ExecApproval` 到 Codex 线程

**补丁审批** (patch_approval.rs):
流程类似，但针对文件变更，使用 `PatchApprovalElicitRequestParams`。

### 3.4 协议细节

#### JSON-RPC 消息格式

**请求示例** (initialize):
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2025-03-26",
    "capabilities": {
      "elicitation": {
        "form": {"schemaValidation": null}
      }
    },
    "clientInfo": {"name": "test-client", "version": "1.0.0"}
  }
}
```

**响应示例** (tools/list):
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "tools": [
      {
        "name": "codex",
        "description": "Run a Codex session...",
        "inputSchema": { /* JSON Schema */ },
        "outputSchema": {
          "type": "object",
          "properties": {
            "threadId": {"type": "string"},
            "content": {"type": "string"}
          },
          "required": ["threadId", "content"]
        }
      },
      {
        "name": "codex-reply",
        ...
      }
    ]
  }
}
```

**通知示例** (codex/event):
```json
{
  "jsonrpc": "2.0",
  "method": "codex/event",
  "params": {
    "_meta": {
      "requestId": 3,
      "threadId": "019bbed6-..."
    },
    "id": "event-123",
    "msg": {
      "type": "session_configured",
      "session_id": "019bbed6-...",
      "model": "gpt-4o",
      ...
    }
  }
}
```

#### 工具响应格式

```rust
pub(crate) fn create_call_tool_result_with_thread_id(
    thread_id: ThreadId,
    text: String,
    is_error: Option<bool>,
) -> CallToolResult {
    CallToolResult {
        content: vec![Content::text(text.clone())],
        structured_content: Some(json!({
            "threadId": thread_id,
            "content": text,
        })),
        is_error,
        meta: None,
    }
}
```

注意: `structured_content` 包含 `threadId`，方便客户端继续会话。

---

## 4. 关键代码路径与文件引用

### 4.1 源文件结构

| 文件 | 职责 | 关键类型/函数 |
|------|------|--------------|
| `lib.rs` | 入口点和主循环 | `run_main()`, `IncomingMessage`, `CHANNEL_CAPACITY` |
| `main.rs` | 二进制入口 | `main()` - 调用 `arg0_dispatch_or_else` |
| `message_processor.rs` | MCP 请求处理 | `MessageProcessor`, `process_request()`, `handle_call_tool()` |
| `codex_tool_runner.rs` | Codex 会话执行 | `run_codex_tool_session()`, `run_codex_tool_session_inner()` |
| `codex_tool_config.rs` | 工具配置结构 | `CodexToolCallParam`, `CodexToolCallReplyParam`, `create_tool_for_*()` |
| `exec_approval.rs` | 执行审批处理 | `handle_exec_approval_request()`, `ExecApprovalElicitRequestParams` |
| `patch_approval.rs` | 补丁审批处理 | `handle_patch_approval_request()`, `PatchApprovalElicitRequestParams` |
| `outgoing_message.rs` | 消息发送管理 | `OutgoingMessageSender`, `OutgoingMessage`, `OutgoingNotificationMeta` |
| `tool_handlers/mod.rs` | 工具处理器模块 | `create_conversation`, `send_message` (子模块) |

### 4.2 关键代码路径

#### 启动路径
```
main.rs:main()
  └── lib.rs:run_main()
      ├── Config::load_with_cli_overrides()
      ├── codex_core::otel_init::build_provider()
      ├── 启动 stdin_reader 任务
      ├── 启动 processor 任务
      │   └── MessageProcessor::new()
      │       └── ThreadManager::new()
      └── 启动 stdout_writer 任务
```

#### 工具调用路径
```
stdin_reader 读取消息
  └── incoming_tx.send(msg)
      └── processor 接收消息
          └── MessageProcessor::process_request()
              └── handle_call_tool()
                  ├── handle_tool_call_codex() / handle_tool_call_codex_session_reply()
                  │   └── 解析参数
                  │   └── task::spawn(async {
                  │       └── codex_tool_runner::run_codex_tool_session()
                  │           ├── thread_manager.start_thread()
                  │           └── run_codex_tool_session_inner()
                  │               └── thread.next_event() 循环
                  └── 立即返回 (异步完成)
```

#### 审批路径
```
run_codex_tool_session_inner() 收到 ExecApprovalRequest
  └── exec_approval::handle_exec_approval_request()
      ├── 构造 ExecApprovalElicitRequestParams
      ├── outgoing.send_request("elicitation/create", ...)
      │   └── 发送 JSON-RPC 请求给客户端
      └── tokio::spawn(async {
          └── on_exec_approval_response()
              ├── 等待 oneshot::Receiver
              ├── 解析 ExecApprovalResponse
              └── codex.submit(Op::ExecApproval { decision })
```

#### 取消路径
```
stdin_reader 收到 notifications/cancelled
  └── MessageProcessor::process_notification()
      └── handle_cancelled_notification()
          ├── 从 map 获取 thread_id
          ├── thread_manager.get_thread(thread_id)
          └── codex_arc.submit(Submission { op: Op::Interrupt })
```

### 4.3 测试文件

| 文件 | 测试内容 |
|------|----------|
| `tests/suite/codex_tool.rs` | 集成测试: shell 命令审批、补丁审批、基础指令传递 |
| `tests/common/mcp_process.rs` | 测试辅助: `McpProcess` 结构用于与 MCP 服务器进程交互 |
| `tests/common/mock_model_server.rs` | Mock OpenAI API 响应 |
| `tests/common/responses.rs` | SSE 响应构造辅助函数 |

---

## 5. 依赖与外部交互

### 5.1 内部依赖 (Workspace Crates)

| Crate | 用途 |
|-------|------|
| `codex-arg0` | 可执行文件路径解析 (`Arg0DispatchPaths`) |
| `codex-core` | 核心功能: `Config`, `ThreadManager`, `CodexThread`, `AuthManager` |
| `codex-protocol` | 协议类型: `ThreadId`, `Event`, `EventMsg`, `Op`, `ReviewDecision` |
| `codex-shell-command` | Shell 命令解析 (`parse_command::parse_command`) |
| `codex-utils-cli` | CLI 配置覆盖解析 |
| `codex-utils-json-to-toml` | JSON 到 TOML 转换 |

### 5.2 外部依赖

| Crate | 用途 |
|-------|------|
| `rmcp` | MCP 协议实现: `JsonRpcMessage`, `ClientRequest`, `CallToolResult` 等 |
| `tokio` | 异步运行时 |
| `serde`/`serde_json` | 序列化/反序列化 |
| `schemars` | JSON Schema 生成 |
| `shlex` | Shell 命令转义 |
| `tracing`/`tracing-subscriber` | 日志和追踪 |

### 5.3 外部交互

#### 与 MCP 客户端交互
- **输入**: 标准输入 (stdin) 接收 JSON-RPC 消息
- **输出**: 标准输出 (stdout) 发送 JSON-RPC 消息和通知
- **审批请求**: 通过 `elicitation/create` 方法向客户端请求用户确认

#### 与 Codex Core 交互
- **线程管理**: 通过 `ThreadManager` 创建和管理 `CodexThread`
- **事件订阅**: 通过 `thread.next_event()` 接收 Codex 事件
- **操作提交**: 通过 `thread.submit(Op::*)` 发送用户输入和审批决策

#### 与 OpenTelemetry 交互
- 日志、追踪和指标导出到配置的 OTLP 端点
- 服务名: `codex_mcp_server`

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 并发和状态管理
- **风险**: `running_requests_id_to_codex_uuid` 使用 `Mutex<HashMap>`，在高并发场景下可能成为瓶颈
- **位置**: `lib.rs:99`, `message_processor.rs:44`
- **缓解**: 当前容量限制 (128) 和交互式使用场景下风险较低

#### 6.1.2 内存泄漏风险
- **风险**: 如果客户端不发送取消通知或工具调用异常退出，`running_requests_id_to_codex_uuid` 中的条目可能残留
- **位置**: `codex_tool_runner.rs:130-131`, `307-310`
- **缓解**: 正常完成时会清理，但异常路径需要仔细审查

#### 6.1.3 审批响应格式不兼容
- **风险**: `ExecApprovalResponse` 不完全符合 MCP Elicitation 规范
- **位置**: `exec_approval.rs:41-48`
- **注释**: TODO 指出应使用 `action` 和 `content` 字段而非仅 `decision`

#### 6.1.4 序列化错误处理
- **风险**: 多处使用 `expect()` 进行序列化，可能导致 panic
- **位置**: `outgoing_message.rs:108`, `codex_tool_config.rs:265`
- **缓解**: 这些路径理论上不应失败，但生产环境应考虑更优雅的错误处理

### 6.2 边界条件

#### 6.2.1 输入验证
- 工具参数通过 JSON Schema 验证 (由 MCP 客户端处理)
- 服务器端额外验证: `thread_id` 解析、配置加载

#### 6.2.2 超时处理
- 测试使用 20 秒超时 (`DEFAULT_READ_TIMEOUT`)
- 生产环境依赖 MCP 客户端的超时配置

#### 6.2.3 资源限制
- 通道容量: 128 (有界输入通道)
- 并发会话数: 理论上无限制，但受限于系统资源

### 6.3 改进建议

#### 6.3.1 架构改进

1. **状态清理机制**
   - 建议: 添加定期清理任务，移除过期的请求 ID 映射
   - 优先级: 中

2. **审批响应标准化**
   - 建议: 更新 `ExecApprovalResponse` 以符合 MCP 规范
   - 参考: TODO 注释中的规范链接
   - 优先级: 高

3. **错误处理增强**
   - 建议: 将 `expect()` 替换为可恢复的错误处理
   - 优先级: 中

#### 6.3.2 功能扩展

1. **更多事件类型支持**
   - 当前: 大量事件类型被忽略或标记为 TODO
   - 建议: 实现 `AgentMessageDelta`, `AgentReasoningDelta` 等事件的流式传输
   - 位置: `codex_tool_runner.rs:319-330`

2. **资源管理**
   - 建议: 实现 `resources/list`, `resources/read` 等 MCP 资源方法
   - 当前: 这些方法仅记录日志，无实际功能

3. **提示模板**
   - 建议: 实现 `prompts/list`, `prompts/get` 以暴露 Codex 提示模板

#### 6.3.3 可观测性

1. **指标增强**
   - 建议: 添加工具调用计数、审批请求计数、会话持续时间等指标
   - 当前: 仅基础 OpenTelemetry 配置

2. **结构化日志**
   - 建议: 为关键事件添加结构化日志字段，便于查询和分析

#### 6.3.4 测试覆盖

1. **边界条件测试**
   - 建议: 添加测试覆盖:
     - 并发工具调用
     - 取消操作
     - 配置加载失败
     - 无效参数处理

2. **集成测试扩展**
   - 建议: 添加与真实 MCP 客户端的集成测试

### 6.4 安全考虑

1. **命令注入**
   - 当前: 使用 `shlex::try_join` 转义命令
   - 建议: 定期审查命令解析逻辑

2. **配置验证**
   - 当前: 依赖 `Config::load_with_cli_overrides`
   - 建议: 在 MCP 层添加额外的配置验证

3. **敏感信息**
   - 注意: 确保 `ExecApprovalElicitRequestParams` 中不包含敏感信息
   - 建议: 审查所有发送到客户端的数据

---

## 7. 相关文档与参考

### 7.1 项目文档
- `codex-rs/docs/codex_mcp_interface.md`: MCP 接口文档
- `codex-rs/app-server/README.md`: App Server API 文档
- `codex-rs/app-server-protocol/src/protocol/v2.rs`: v2 协议定义

### 7.2 外部规范
- [Model Context Protocol Specification](https://modelcontextprotocol.io/specification)
- [JSON-RPC 2.0 Specification](https://www.jsonrpc.org/specification)

### 7.3 相关代码
- `codex-rs/core/src/mcp_tool_call.rs`: 核心 MCP 工具调用处理 (客户端侧)
- `codex-rs/cli/src/mcp_cmd.rs`: CLI 的 MCP 子命令 (管理 MCP 服务器配置)
- `codex-rs/tui_app_server/src/bottom_pane/mcp_server_elicitation.rs`: TUI 的 MCP 审批 UI

---

## 8. 总结

`codex-rs/mcp-server/src` 实现了 Codex 的 MCP 服务器功能，作为 Codex 核心与 MCP 客户端之间的桥梁。它通过标准化的 JSON-RPC 协议暴露 Codex 的 AI 编程能力，支持会话管理、执行审批和补丁审批等关键功能。

该实现采用异步架构，使用 Tokio 处理并发，通过通道进行任务间通信。主要技术亮点包括:
- 清晰的职责分离 (消息处理、工具执行、审批处理)
- 完整的事件流支持
- 灵活的审批机制

主要改进空间包括审批响应标准化、更多事件类型的支持以及增强的可观测性。
