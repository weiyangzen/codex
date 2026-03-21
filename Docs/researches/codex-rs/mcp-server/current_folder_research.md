# codex-rs/mcp-server 研究文档

## 概述

`codex-mcp-server` 是 Codex 项目的 MCP (Model Context Protocol) 服务器实现，它将 Codex AI 编程助手的能力通过标准化的 MCP 协议暴露给外部客户端。该服务器基于 JSON-RPC 2.0 协议，通过标准输入输出 (stdio) 进行通信。

---

## 场景与职责

### 核心场景

1. **MCP 协议适配**: 将 Codex 的核心功能包装为 MCP 兼容的工具调用接口
2. **AI 会话管理**: 管理 Codex 会话生命周期，包括创建、继续和中断会话
3. **审批流程代理**: 将 Codex 内部的执行审批和补丁审批转换为 MCP 的 elicitation 请求
4. **事件流转发**: 将 Codex 内部事件流转换为 MCP 通知发送给客户端

### 主要职责

| 职责 | 说明 |
|------|------|
| 协议转换 | 将 MCP JSON-RPC 请求转换为 Codex 内部操作 |
| 工具暴露 | 暴露 `codex` 和 `codex-reply` 两个 MCP 工具 |
| 会话管理 | 维护请求 ID 到线程 ID 的映射，支持多路复用 |
| 审批代理 | 将执行命令和补丁应用审批请求转发给 MCP 客户端 |
| 事件通知 | 通过 `codex/event` 通知发送 Codex 事件 |

---

## 功能点目的

### 1. 初始化与握手 (`initialize`)

- **目的**: 建立 MCP 连接，交换能力信息
- **关键行为**: 
  - 设置客户端 User-Agent 后缀
  - 返回服务器能力（仅支持工具列表变更通知）
  - 在 `serverInfo` 中附加 Codex 特有的 `user_agent` 字段

### 2. 工具列表 (`tools/list`)

- **目的**: 暴露可用的 Codex 工具
- **暴露工具**:
  - `codex`: 启动新的 Codex 会话
  - `codex-reply`: 继续现有会话

### 3. 工具调用 (`tools/call`)

#### 3.1 `codex` 工具

- **参数** (`CodexToolCallParam`):
  - `prompt`: 初始用户提示（必需）
  - `model`: 模型名称覆盖
  - `profile`: 配置 profile
  - `cwd`: 工作目录
  - `approval_policy`: 审批策略 (`untrusted`, `on-failure`, `on-request`, `never`)
  - `sandbox`: 沙箱模式 (`read-only`, `workspace-write`, `danger-full-access`)
  - `config`: 额外的配置覆盖
  - `base_instructions`: 基础指令覆盖
  - `developer_instructions`: 开发者指令
  - `compact_prompt`: 压缩提示

- **处理流程**:
  1. 解析参数并构建 `ConfigOverrides`
  2. 加载配置（支持 CLI 覆盖和 harness 覆盖）
  3. 创建新线程 (`ThreadManager::start_thread`)
  4. 提交初始用户输入
  5. 在后台任务中运行会话循环

#### 3.2 `codex-reply` 工具

- **参数** (`CodexToolCallReplyParam`):
  - `thread_id` / `conversation_id`: 会话 ID（支持向后兼容）
  - `prompt`: 后续用户提示（必需）

- **处理流程**:
  1. 解析 thread_id（优先使用新字段，兼容旧字段）
  2. 从 `ThreadManager` 获取现有线程
  3. 提交用户输入继续会话

### 4. 执行审批代理 (`exec_approval.rs`)

- **触发**: 当 Codex 需要执行非信任命令时
- **处理**:
  1. 构建 `ExecApprovalElicitRequestParams`
  2. 发送 `elicitation/create` 请求给 MCP 客户端
  3. 等待客户端响应
  4. 将决策（Approved/Denied）提交回 Codex

### 5. 补丁审批代理 (`patch_approval.rs`)

- **触发**: 当 Codex 需要应用代码补丁时
- **处理**:
  1. 构建 `PatchApprovalElicitRequestParams`（包含文件变更详情）
  2. 发送 `elicitation/create` 请求
  3. 等待客户端响应并提交决策

### 6. 取消通知处理 (`cancelled`)

- **目的**: 支持 MCP 客户端取消正在进行的工具调用
- **处理**: 通过 `running_requests_id_to_codex_uuid` 映射找到对应线程，提交 `Interrupt` 操作

---

## 具体技术实现

### 关键数据结构

#### 消息类型

```rust
// 入站消息 (来自客户端)
type IncomingMessage = JsonRpcMessage<ClientRequest, Value, ClientNotification>;

// 出站消息 (发往客户端)
pub(crate) enum OutgoingMessage {
    Request(OutgoingRequest),
    Notification(OutgoingNotification),
    Response(OutgoingResponse),
    Error(OutgoingError),
}
```

#### 消息处理器状态

```rust
pub(crate) struct MessageProcessor {
    outgoing: Arc<OutgoingMessageSender>,
    initialized: bool,
    arg0_paths: Arg0DispatchPaths,
    thread_manager: Arc<ThreadManager>,
    running_requests_id_to_codex_uuid: Arc<Mutex<HashMap<RequestId, ThreadId>>>,
}
```

### 关键流程

#### 1. 主事件循环 (`lib.rs::run_main`)

```
┌─────────────────┐
│   初始化配置     │
│  加载 OTel 配置  │
└────────┬────────┘
         ▼
┌─────────────────┐
│  创建消息通道    │
│ incoming/outgoing│
└────────┬────────┘
         ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  stdin 读取任务  │────▶│  消息处理任务    │────▶│ stdout 写入任务 │
│ (JSON-RPC 解析)  │     │ (MessageProcessor)│    │ (序列化输出)    │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

#### 2. 工具调用流程

```
MCP Client          MCP Server           ThreadManager        CodexThread
    │                    │                     │                    │
    │── tools/call ─────▶│                     │                    │
    │   (codex tool)     │                     │                    │
    │                    │── start_thread ────▶│                    │
    │                    │                     │── create thread ───▶│
    │                    │◄────────────────────│                    │
    │                    │                     │◄───────────────────│
    │                    │                     │                    │
    │                    │── spawn async task ─┼────────────────────▶│
    │                    │   (run_codex_tool_session)                 │
    │                    │                     │                    │
    │◄─ session_configured notification ──────│                    │
    │                    │                     │                    │
    │                    │                     │                    │
    │◄─ codex/event notifications ────────────┼────────────────────│
    │   (streaming)      │                     │                    │
    │                    │                     │                    │
    │◄─ tools/call response ──────────────────┼────────────────────│
    │   (with threadId)  │                     │                    │
```

#### 3. 审批流程

```
CodexThread         tool_runner          OutgoingMessageSender    MCP Client
    │                    │                     │                    │
    │── ExecApprovalRequest ─────────────────▶│                    │
    │                                         │── elicitation/create─▶│
    │                                         │   (with callback)    │
    │                                         │◄─────────────────────│
    │                                         │   (client response)  │
    │                                         │                    │
    │◄─ submit(Op::ExecApproval) ─────────────┼────────────────────│
    │   (with decision)                       │                    │
```

### 协议细节

#### MCP 协议版本
- 支持版本: `2025-03-26`
- 传输: stdio (行分隔 JSON-RPC)

#### 自定义通知

**`codex/event` 通知**:
```json
{
  "method": "codex/event",
  "params": {
    "_meta": {
      "requestId": 123,
      "threadId": "..."
    },
    "id": "event-id",
    "msg": { /* EventMsg */ }
  }
}
```

#### 工具响应格式

```json
{
  "content": [{ "type": "text", "text": "..." }],
  "structuredContent": {
    "threadId": "...",
    "content": "..."
  }
}
```

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 | 关键类型/函数 |
|------|------|--------------|
| `src/main.rs` | 程序入口 | `main()` - 调用 `arg0_dispatch_or_else` 和 `run_main` |
| `src/lib.rs` | 主库，事件循环 | `run_main()`, `IncomingMessage`, `CHANNEL_CAPACITY` |
| `src/message_processor.rs` | MCP 消息处理 | `MessageProcessor`, `process_request()`, `handle_call_tool()` |
| `src/codex_tool_runner.rs` | Codex 会话执行 | `run_codex_tool_session()`, `run_codex_tool_session_reply()` |
| `src/codex_tool_config.rs` | 工具参数配置 | `CodexToolCallParam`, `CodexToolCallReplyParam` |
| `src/exec_approval.rs` | 执行审批处理 | `ExecApprovalElicitRequestParams`, `handle_exec_approval_request()` |
| `src/patch_approval.rs` | 补丁审批处理 | `PatchApprovalElicitRequestParams`, `handle_patch_approval_request()` |
| `src/outgoing_message.rs` | 出站消息管理 | `OutgoingMessageSender`, `send_request()`, `send_event_as_notification()` |

### 测试文件

| 文件 | 测试内容 |
|------|----------|
| `tests/all.rs` | 测试入口 |
| `tests/suite/codex_tool.rs` | 集成测试：shell 命令审批、补丁审批、基础指令传递 |
| `tests/common/lib.rs` | 测试公共库导出 |
| `tests/common/mcp_process.rs` | MCP 进程管理测试工具 |
| `tests/common/mock_model_server.rs` | Mock 模型服务器 |
| `tests/common/responses.rs` | SSE 响应构造器 |

---

## 依赖与外部交互

### 内部依赖

```
codex-mcp-server
├── codex-arg0          # arg0 分发路径处理
├── codex-core          # 核心 Codex 功能 (ThreadManager, Config, AuthManager)
├── codex-protocol      # 协议类型 (ThreadId, Event, EventMsg, Op, Submission)
├── codex-shell-command # Shell 命令解析
├── codex-utils-cli     # CLI 配置覆盖
└── codex-utils-json-to-toml  # JSON 到 TOML 转换
```

### 外部依赖

| Crate | 用途 |
|-------|------|
| `rmcp` | MCP 协议实现 (JSON-RPC 类型、模型定义) |
| `tokio` | 异步运行时 |
| `serde`/`serde_json` | 序列化 |
| `schemars` | JSON Schema 生成 |
| `tracing` | 日志/追踪 |
| `shlex` | Shell 命令转义 |

### 调用方

1. **CLI**: `codex mcp-server` 命令通过 `codex-cli` 调用
2. **MCP 客户端**: 任何 MCP 兼容的客户端（如 Claude Desktop、MCP Inspector）

### 被调用方

1. **codex-core**: 
   - `ThreadManager::start_thread()` - 创建新会话
   - `ThreadManager::get_thread()` - 获取现有会话
   - `CodexThread::submit()` / `submit_with_id()` - 提交操作
   - `CodexThread::next_event()` - 获取事件

2. **codex-protocol**:
   - `Event`, `EventMsg` - 事件类型
   - `Op` - 操作类型
   - `Submission` - 提交结构
   - `ReviewDecision` - 审批决策

---

## 风险、边界与改进建议

### 已知风险

1. **并发安全**:
   - `running_requests_id_to_codex_uuid` 使用 `tokio::sync::Mutex` 保护
   - 在 `handle_cancelled_notification` 中先释放锁再获取线程，存在竞态条件窗口

2. **资源泄漏**:
   - 测试中使用 `kill_on_drop` 但文档说明这是 best-effort
   - `McpProcess::Drop` 实现了同步清理等待，但仍有 5 秒超时

3. **错误处理**:
   - 多处使用 `unwrap_or_default()` 可能导致静默失败
   - `process_error` 仅记录日志，不通知客户端

4. **协议兼容性**:
   - `ExecApprovalResponse` 不完全符合 MCP ElicitResult 规范（TODO 注释）
   - 自定义 `serverInfo.user_agent` 字段是非标准的

### 边界情况

1. **会话不存在**: `codex-reply` 工具调用时如果 thread_id 不存在，返回错误响应
2. **重复初始化**: 调用 `initialize` 多次会返回错误
3. **取消未知请求**: 如果取消通知对应的请求 ID 不存在，静默忽略
4. **空参数**: `codex` 工具调用缺少参数时返回明确的错误消息

### 改进建议

1. **代码结构**:
   - `message_processor.rs` 超过 600 行，建议按功能拆分为子模块
   - `handle_call_tool` 中的 `codex` 和 `codex-reply` 处理逻辑可以提取为独立函数

2. **错误处理**:
   - 统一错误响应格式，添加错误码分类
   - 在 `process_error` 中实现客户端通知机制

3. **测试覆盖**:
   - 当前集成测试依赖网络（有 `skip_if_no_network` 检查）
   - 建议添加更多单元测试，减少对集成测试的依赖
   - 添加并发场景测试（多线程同时调用）

4. **协议实现**:
   - 完成 `ExecApprovalResponse` 的 MCP 规范兼容
   - 考虑支持更多的 MCP 功能（如 resources、prompts）

5. **可观测性**:
   - 添加更多结构化日志字段（如 thread_id、request_id 的关联）
   - 考虑添加 metrics 暴露（当前只有 OTel 日志/追踪）

6. **配置管理**:
   - `CodexToolCallParam` 和 `ConfigOverrides` 的字段映射可以自动化（如使用宏）
   - 考虑支持热重载配置

---

## 附录：工具 JSON Schema

### `codex` 工具输入 Schema

```json
{
  "properties": {
    "approval-policy": {
      "enum": ["untrusted", "on-failure", "on-request", "never"],
      "type": "string"
    },
    "base-instructions": { "type": "string" },
    "compact-prompt": { "type": "string" },
    "config": { "additionalProperties": true, "type": "object" },
    "cwd": { "type": "string" },
    "developer-instructions": { "type": "string" },
    "model": { "type": "string" },
    "profile": { "type": "string" },
    "prompt": { "type": "string" },
    "sandbox": {
      "enum": ["read-only", "workspace-write", "danger-full-access"],
      "type": "string"
    }
  },
  "required": ["prompt"],
  "type": "object"
}
```

### `codex-reply` 工具输入 Schema

```json
{
  "properties": {
    "conversationId": { "type": "string" },
    "prompt": { "type": "string" },
    "threadId": { "type": "string" }
  },
  "required": ["prompt"],
  "type": "object"
}
```

---

*文档生成时间: 2026-03-21*
*基于代码版本: codex-rs/mcp-server 当前 HEAD*
