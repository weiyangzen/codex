# DIR codex-rs/exec-server/src/server 深度研究

## 概述

`codex-rs/exec-server/src/server` 是 Codex 执行服务器的核心服务端实现目录，负责提供 JSON-RPC over WebSocket 的远程进程管理能力。该模块实现了基于 JSON-RPC 协议的通信层、请求处理器和生命周期管理，是 codex-exec-server 二进制服务的核心组件。

---

## 场景与职责

### 核心场景

1. **远程进程执行服务**：作为独立服务运行，为 Codex CLI 和其他客户端提供安全的远程进程管理能力
2. **JSON-RPC 协议网关**：将 WebSocket 连接转换为结构化的 JSON-RPC 消息处理
3. **生命周期管理**：处理客户端连接的初始化、握手和关闭流程
4. **进程管理代理**：代理客户端的进程启动、输入输出、终止等操作（当前为 stub 实现）

### 职责边界

| 职责 | 说明 |
|------|------|
| 协议解析 | 处理 JSON-RPC 消息的序列化/反序列化 |
| 连接管理 | 维护 WebSocket 连接的生命周期 |
| 请求分发 | 根据 method 字段路由到对应处理器 |
| 错误处理 | 返回标准 JSON-RPC 错误响应 |
| 初始化握手 | 实现 initialize/initialized 握手协议 |

---

## 功能点目的

### 1. 传输层 (`transport.rs`)

**目的**：提供 WebSocket 监听和连接接受能力

**关键功能**：
- 解析 `--listen` 参数（支持 `ws://IP:PORT` 格式）
- 创建 TCP 监听器并绑定到指定地址
- 接受 WebSocket 连接并为每个连接创建独立任务
- 默认监听地址：`ws://127.0.0.1:0`（随机端口）

### 2. 连接处理 (`processor.rs`)

**目的**：处理单个客户端连接的完整生命周期

**关键功能**：
- 消息循环：持续接收和处理客户端消息
- 请求分发：将 JSON-RPC 请求路由到对应处理器
- 通知处理：处理 `initialized` 等通知消息
- 错误恢复：对畸形消息返回错误但保持连接

### 3. 请求处理器 (`handler.rs`)

**目的**：实现具体的 JSON-RPC 方法逻辑

**关键功能**：
- `initialize`：处理客户端初始化请求，执行一次性握手
- `initialized`：确认客户端已收到初始化响应
- 状态管理：跟踪连接的初始化状态（原子布尔标志）

### 4. JSON-RPC 工具 (`jsonrpc.rs`)

**目的**：提供标准 JSON-RPC 错误构造和响应生成

**关键功能**：
- 标准错误码：`INVALID_REQUEST (-32600)`、`INVALID_PARAMS (-32602)`、`METHOD_NOT_FOUND (-32601)`
- 响应包装：将结果或错误包装为标准 JSON-RPC 响应格式

---

## 具体技术实现

### 关键流程

#### 1. 服务器启动流程

```
codex-exec-server --listen ws://127.0.0.1:0
    ↓
parse_listen_url("ws://127.0.0.1:0") → SocketAddr
    ↓
TcpListener::bind(bind_address)
    ↓
loop {
    listener.accept() → (stream, peer_addr)
    tokio::spawn(async move {
        accept_async(stream) → websocket
        run_connection(JsonRpcConnection::from_websocket(...))
    })
}
```

**代码路径**：`transport.rs:49-82`

#### 2. 连接处理流程

```
run_connection(connection)
    ↓
connection.into_parts() → (outgoing_tx, incoming_rx, _tasks)
    ↓
while let Some(event) = incoming_rx.recv().await {
    match event {
        Message(msg) → handle_connection_message(handler, msg)
        MalformedMessage → send invalid_request_message
        Disconnected → break
    }
}
    ↓
handler.shutdown().await
```

**代码路径**：`processor.rs:18-61`

#### 3. 消息处理流程

```
handle_connection_message(handler, message)
    ↓
match message {
    Request(req) → dispatch_request(handler, req) → Some(response)
    Notification(notif) → handle_notification(handler, notif) → None
    Response(resp) → Err("unexpected client response")
    Error(err) → Err("unexpected client error")
}
```

**代码路径**：`processor.rs:63-82`

#### 4. 请求分发流程

```
dispatch_request(handler, request)
    ↓
match method {
    "initialize" → {
        serde_json::from_value::<InitializeParams>(params)
        handler.initialize()
        serde_json::to_value(response)
        response_message(id, result)
    }
    other → response_message(id, Err(method_not_found(...)))
}
```

**代码路径**：`processor.rs:84-111`

#### 5. 初始化握手流程

```
客户端                              服务器
  |                                    |
  |--- JSONRPCRequest(initialize) --->|
  |                                    | handler.initialize()
  |<-- JSONRPCResponse(result: {}) ----|
  |                                    |
  |--- JSONRPCNotification(initialized) →|
  |                                    | handler.initialized()
  |                                    | (状态标记为已初始化)
  |                                    |
```

**代码路径**：`handler.rs:24-39`

### 数据结构

#### 1. ExecServerHandler

```rust
pub(crate) struct ExecServerHandler {
    initialize_requested: AtomicBool,  // 是否已收到 initialize 请求
    initialized: AtomicBool,           // 是否已完成 initialized 通知
}
```

**用途**：跟踪单个连接的初始化状态，确保：
- `initialize` 只能调用一次
- `initialized` 通知只能在 `initialize` 之后发送

#### 2. JSON-RPC 消息类型（来自 codex-app-server-protocol）

```rust
pub enum JSONRPCMessage {
    Request(JSONRPCRequest),
    Notification(JSONRPCNotification),
    Response(JSONRPCResponse),
    Error(JSONRPCError),
}

pub struct JSONRPCRequest {
    pub id: RequestId,           // 请求标识（String 或 i64）
    pub method: String,          // 方法名
    pub params: Option<Value>,   // 参数
    pub trace: Option<W3cTraceContext>, // 分布式追踪
}

pub struct JSONRPCNotification {
    pub method: String,
    pub params: Option<Value>,
}

pub struct JSONRPCResponse {
    pub id: RequestId,
    pub result: Value,
}

pub struct JSONRPCError {
    pub id: RequestId,
    pub error: JSONRPCErrorError,
}

pub struct JSONRPCErrorError {
    pub code: i64,               // 错误码
    pub message: String,         // 错误消息
    pub data: Option<Value>,     // 附加数据
}
```

#### 3. 协议常量

```rust
pub const INITIALIZE_METHOD: &str = "initialize";
pub const INITIALIZED_METHOD: &str = "initialized";

pub const DEFAULT_LISTEN_URL: &str = "ws://127.0.0.1:0";
```

#### 4. 初始化参数/响应

```rust
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InitializeParams {
    pub client_name: String,     // 客户端标识名称
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InitializeResponse {}  // 当前为空对象
```

### 协议实现

#### JSON-RPC 错误码

| 错误码 | 常量 | 含义 |
|--------|------|------|
| -32600 | INVALID_REQUEST | 无效请求（如重复 initialize） |
| -32601 | METHOD_NOT_FOUND | 方法不存在（当前大部分方法返回此错误） |
| -32602 | INVALID_PARAMS | 参数无效（解析失败） |
| -32000 | - | 传输关闭（客户端内部使用） |

#### 支持的 Method

| Method | 类型 | 状态 | 说明 |
|--------|------|------|------|
| `initialize` | Request | ✅ 已实现 | 初始化握手 |
| `initialized` | Notification | ✅ 已实现 | 初始化确认 |
| `command/exec` | Request | ❌ Stub | 启动进程（文档中定义，未实现） |
| `command/exec/write` | Request | ❌ Stub | 写入进程输入 |
| `command/exec/terminate` | Request | ❌ Stub | 终止进程 |
| `process/start` | Request | ❌ Stub | 测试中使用的方法 |

### 命令行接口

```bash
# 启动执行服务器
codex-exec-server --listen ws://127.0.0.1:8080

# 使用默认配置（随机端口）
codex-exec-server
```

---

## 关键代码路径与文件引用

### 核心文件结构

```
codex-rs/exec-server/src/server/
├── handler.rs           # ExecServerHandler 实现
├── jsonrpc.rs           # JSON-RPC 工具函数
├── processor.rs         # 连接处理和请求分发
├── transport.rs         # WebSocket 传输层
└── transport_tests.rs   # 传输层单元测试
```

### 关键代码引用

| 功能 | 文件 | 行号范围 |
|------|------|----------|
| 服务器启动入口 | `server.rs` | 10-17 |
| WebSocket 监听 | `transport.rs` | 49-82 |
| URL 解析 | `transport.rs` | 35-47 |
| 连接处理循环 | `processor.rs` | 18-61 |
| 消息分发 | `processor.rs` | 63-121 |
| initialize 处理 | `handler.rs` | 24-31 |
| initialized 处理 | `handler.rs` | 33-39 |
| 错误构造 | `jsonrpc.rs` | 8-46 |

### 依赖模块

```
server/
    ├── 依赖: crate::connection::JsonRpcConnection
    ├── 依赖: crate::protocol::{InitializeParams, InitializeResponse, INITIALIZE_METHOD, INITIALIZED_METHOD}
    ├── 依赖: crate::server::jsonrpc::{invalid_params, invalid_request, method_not_found, response_message}
    └── 外部依赖: codex_app_server_protocol::{JSONRPCMessage, JSONRPCRequest, JSONRPCNotification, JSONRPCError, JSONRPCErrorError, JSONRPCResponse, RequestId}
```

---

## 依赖与外部交互

### 内部依赖

| 模块 | 路径 | 用途 |
|------|------|------|
| `connection` | `../connection.rs` | WebSocket/stdio 连接抽象 |
| `protocol` | `../protocol.rs` | 协议常量和数据结构 |
| `client` | `../client.rs` | 通过 LocalBackend 使用 handler |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `codex-app-server-protocol` | JSON-RPC 消息类型定义 |
| `tokio` | 异步运行时和 TCP/WebSocket |
| `tokio-tungstenite` | WebSocket 服务器实现 |
| `serde_json` | JSON 序列化/反序列化 |
| `tracing` | 日志和追踪 |

### 与客户端的交互

```
┌─────────────────┐      WebSocket       ┌─────────────────────────┐
│   ExecServer    │◄────────────────────►│      ExecServerClient   │
│   (server/)     │   JSON-RPC 消息      │      (client.rs)        │
└─────────────────┘                      └─────────────────────────┘
         │                                         │
         │  1. initialize 请求                      │
         │◄─────────────────────────────────────────│
         │  2. initialize 响应                      │
         │──────────────────────────────────────────►│
         │  3. initialized 通知                     │
         │◄─────────────────────────────────────────│
         │                                         │
         │  4. 后续 RPC 调用（当前返回错误）        │
         │◄─────────────────────────────────────────│
         │  5. 错误响应                             │
         │──────────────────────────────────────────►│
```

### 与 LocalBackend 的交互

```rust
// client/local_backend.rs
pub(super) struct LocalBackend {
    handler: Arc<ExecServerHandler>,
}

impl LocalBackend {
    pub(super) async fn initialize(&self) -> Result<InitializeResponse, ExecServerError> {
        self.handler.initialize().map_err(...)
    }
    
    pub(super) async fn initialized(&self) -> Result<(), ExecServerError> {
        self.handler.initialized().map_err(...)
    }
}
```

---

## 风险、边界与改进建议

### 当前风险

1. **功能不完整**：当前仅为 stub 实现，大部分方法返回 `METHOD_NOT_FOUND` 错误
   - 影响：无法实际执行进程管理功能
   - 缓解：README 明确说明这是 intentional，完整实现在后续 PR

2. **无认证机制**：WebSocket 连接无身份验证
   - 影响：任何能连接到端口的客户端都可使用服务
   - 建议：添加 token-based 认证或 TLS 客户端证书

3. **单连接状态管理**：`ExecServerHandler` 每个连接独立，无全局状态
   - 影响：无法跨连接共享进程状态
   - 注意：这可能是设计意图（隔离性）

4. **错误处理粒度**：畸形消息仅记录警告，可能掩盖问题
   - 代码：`processor.rs:41-49`

### 边界情况

1. **重复 initialize**：
   - 行为：返回 `INVALID_REQUEST` 错误
   - 代码：`handler.rs:25-28`

2. **initialized 在 initialize 之前**：
   - 行为：返回协议错误，关闭连接
   - 代码：`handler.rs:34-36`

3. **畸形 JSON**：
   - 行为：返回错误响应（id=-1），保持连接
   - 代码：`processor.rs:41-49`

4. **意外的客户端响应**：
   - 行为：协议错误，关闭连接
   - 代码：`processor.rs:73-80`

5. **WebSocket 关闭**：
   - 行为：断开事件触发，清理 handler
   - 代码：`processor.rs:51-56`, `handler.rs:22`

### 改进建议

1. **完善进程管理实现**：
   - 实现 `command/exec`、`command/exec/write`、`command/exec/terminate`
   - 集成 `codex-utils-pty` 进行 PTY 管理

2. **增强安全性**：
   - 添加连接认证（token 或 mTLS）
   - 实现访问控制列表（ACL）
   - 添加速率限制

3. **可观测性**：
   - 添加 metrics 导出（连接数、请求数、错误率）
   - 完善 tracing span 和上下文传播

4. **配置管理**：
   - 支持配置文件（TOML/YAML）
   - 可配置日志级别、监听地址、超时

5. **测试覆盖**：
   - 添加集成测试（当前仅有单元测试）
   - 测试并发连接场景
   - 测试错误恢复路径

6. **文档完善**：
   - API 文档（OpenAPI/JSON Schema）
   - 部署和运维指南

---

## 总结

`codex-rs/exec-server/src/server` 是一个设计清晰的 JSON-RPC 服务器框架，实现了：

1. **清晰的模块划分**：传输层、处理层、业务逻辑层分离
2. **标准的协议实现**：遵循 JSON-RPC 2.0 规范
3. **健壮的连接管理**：支持多客户端并发连接
4. **完善的错误处理**：标准错误码，连接保持策略

当前状态为**基础框架阶段**，核心进程管理功能待实现。代码质量高，遵循 Rust 最佳实践，具备良好的扩展性。

---

*研究日期：2026-03-21*
*研究范围：codex-rs/exec-server/src/server 目录及其直接依赖*
