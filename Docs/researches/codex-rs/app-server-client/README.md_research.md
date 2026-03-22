# README.md 研究文档

## 场景与职责

此 README.md 是 `codex-app-server-client` crate 的文档入口，面向**人类开发者**提供高层架构说明和使用指南。该 crate 是 Codex 项目中的**共享应用服务器客户端库**，主要服务于两个 CLI 界面：

- **`codex-tui`** - 终端用户界面（交互式 TUI）
- **`codex-exec`** - 命令行执行工具（批处理模式）

该 crate 的核心职责是**集中化管理应用服务器的启动和生命周期**，避免 CLI 界面重复实现相同的逻辑。

## 功能点目的

### 1. 统一客户端抽象
为 TUI 和 exec 提供统一的客户端接口，封装底层差异：
- 进程内（in-process）运行时 - 直接内存通信
- 远程（remote）运行时 - WebSocket 连接

### 2. 生命周期管理
集中处理应用服务器的完整生命周期：
- 启动（bootstrap）和初始化握手
- 请求/事件传输
- 优雅关闭（graceful shutdown）

### 3. 启动身份管理
允许调用方提供明确的启动身份，确保线程元数据与发起运行时一致：
- `SessionSource` - 会话来源（区分 TUI/exec）
- `client_info.name` - 客户端名称

## 具体技术实现

### 架构分层

```
┌─────────────────────────────────────────────────────────────┐
│  CLI Surfaces (codex-tui, codex-exec)                       │
│  - 提供启动身份 (SessionSource, client_name)                │
│  - 消费事件流                                               │
│  - 处理用户交互                                             │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  codex-app-server-client (本 crate)                         │
│  ┌───────────────────────────────────────────────────────┐ │
│  │  InProcessAppServerClient                             │ │
│  │  - 启动参数封装 (InProcessClientStartArgs)            │ │
│  │  - 工作线程管理                                       │ │
│  │  - 背压处理                                           │ │
│  └───────────────────────────────────────────────────────┘ │
│  ┌───────────────────────────────────────────────────────┐ │
│  │  RemoteAppServerClient (src/remote.rs)                │ │
│  │  - WebSocket 连接管理                                 │ │
│  │  - JSON-RPC 协议处理                                  │ │
│  └───────────────────────────────────────────────────────┘ │
└──────────────────────┬──────────────────────────────────────┘
                       │
         ┌─────────────┴─────────────┐
         ▼                           ▼
┌─────────────────────┐  ┌─────────────────────────────┐
│ codex-app-server    │  │  Remote App Server          │
│ (in_process)        │  │  (WebSocket)                │
└─────────────────────┘  └─────────────────────────────┘
```

### 传输模型

#### 进程内传输（Typed Channels）

使用类型化的异步通道进行通信：

```rust
// 客户端 -> 服务器
ClientRequest / ClientNotification

// 服务器 -> 客户端
InProcessServerEvent
  ├── ServerRequest      // 服务器请求（需响应）
  ├── ServerNotification // 服务器通知
  └── LegacyNotification // 遗留通知（兼容层）
```

**关键设计决策**：
- 进程内路径仍使用 JSON-RPC 结果信封（result envelope）
- 这是有意为之：保持与 app-server 行为一致，避免引入第二种响应契约

#### 通道容量与背压

```rust
pub use codex_app_server::in_process::DEFAULT_IN_PROCESS_CHANNEL_CAPACITY;
```

- 队列有界（bounded），使用 `DEFAULT_IN_PROCESS_CHANNEL_CAPACITY`
- 队列满时返回显式的过载行为，而非无限制增长
- 消费者落后时，工作线程发出 `InProcessServerEvent::Lagged`
- 可能拒绝待处理的服务器请求，避免审批流程无限期挂起

### 启动流程

```
┌──────────────┐
│   调用方     │
│  提供启动参数 │
└──────┬───────┘
       │
       ▼
┌─────────────────────────────────────┐
│ InProcessClientStartArgs            │
│ - arg0_paths                        │
│ - config                            │
│ - cli_overrides                     │
│ - session_source                    │
│ - client_name                       │
│ - ...                               │
└──────┬──────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────┐
│ InProcessAppServerClient::start()   │
│ 1. 创建共享核心管理器               │
│    - AuthManager                    │
│    - ThreadManager                  │
│ 2. 启动 app-server 运行时           │
│ 3. 创建命令/事件通道                │
│ 4. 启动工作线程                     │
└──────┬──────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────┐
│ 返回客户端句柄                      │
│ - request() / request_typed()       │
│ - notify()                          │
│ - next_event()                      │
│ - shutdown()                        │
└─────────────────────────────────────┘
```

### 启动身份（Startup Identity）

调用方显式传递两个关键身份标识：

1. **`SessionSource`** - 会话来源
   - `Exec` - 来自 codex-exec
   - `Cli` - 来自 codex-cli/TUI
   - 影响 `thread/list` 和 `thread/read` 中的线程元数据

2. **`client_info.name`** - 客户端名称
   - 在初始化时报告
   - 用于区分不同的 CLI 表面

**设计原则**：保持 TUI/exec 特定的策略不侵入共享客户端层

### 关闭行为

```rust
pub async fn shutdown(self) -> IoResult<()>
```

1. **优雅关闭阶段**：
   - 发送 `Shutdown` 命令到工作线程
   - 等待 `SHUTDOWN_TIMEOUT`（5秒）

2. **强制终止阶段**：
   - 如果超时，中止工作线程
   - 避免在嵌入调用方中泄漏后台任务

## 关键代码路径与文件引用

### 核心源文件

| 文件 | 职责 |
|------|------|
| `src/lib.rs` | 进程内客户端实现 (`InProcessAppServerClient`) |
| `src/remote.rs` | 远程 WebSocket 客户端实现 (`RemoteAppServerClient`) |

### 关键类型

| 类型 | 位置 | 用途 |
|------|------|------|
| `InProcessAppServerClient` | `src/lib.rs` | 进程内客户端主类型 |
| `RemoteAppServerClient` | `src/remote.rs` | 远程客户端主类型 |
| `AppServerClient` | `src/lib.rs` | 统一客户端枚举 |
| `AppServerEvent` | `src/lib.rs` | 事件类型 |
| `InProcessClientStartArgs` | `src/lib.rs` | 启动参数 |
| `TypedRequestError` | `src/lib.rs` | 类型化请求错误 |

### 依赖 crate 关键类型

| 类型 | 来源 Crate | 用途 |
|------|-----------|------|
| `InProcessServerEvent` | `codex-app-server` | 服务器事件 |
| `ClientRequest` / `ClientNotification` | `codex-app-server-protocol` | 客户端消息 |
| `ServerRequest` / `ServerNotification` | `codex-app-server-protocol` | 服务器消息 |
| `SessionSource` | `codex-protocol` | 会话来源 |

## 依赖与外部交互

### 与上游（CLI 表面）的交互

#### codex-tui
```rust
// 简化的使用模式
let client = InProcessAppServerClient::start(InProcessClientStartArgs {
    client_name: "codex-tui".to_string(),
    session_source: SessionSource::Cli,
    // ... 其他参数
}).await?;

// 事件循环
while let Some(event) = client.next_event().await {
    match event {
        AppServerEvent::ServerNotification(n) => { /* 处理通知 */ }
        AppServerEvent::ServerRequest(r) => { /* 处理请求 */ }
        // ...
    }
}
```

#### codex-exec
类似的使用模式，但使用 `SessionSource::Exec`

### 与下游（app-server）的交互

```rust
// 启动时
let handle = codex_app_server::in_process::start(args).await?;

// 请求发送
handle.sender().request(client_request).await

// 事件接收
handle.next_event().await
```

### 协议边界

```
┌─────────────────────────────────────────────────────────────┐
│  JSON-RPC 协议边界（外部传输：stdio/WebSocket）              │
│  ┌───────────────────────────────────────────────────────┐ │
│  │  JSON-RPC Request/Response/Notification/Error         │ │
│  │  - method: "thread/start", "config/read", etc.        │ │
│  │  - id: RequestId                                      │ │
│  └───────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ 序列化/反序列化
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  类型化 Rust 结构（进程内传输）                              │
│  ┌───────────────────────────────────────────────────────┐ │
│  │  ClientRequest::ThreadStart { params, ... }           │ │
│  │  ClientNotification::Initialized                      │ │
│  │  ServerNotification::TurnCompleted(...)               │ │
│  └───────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## 风险、边界与改进建议

### 风险

1. **事件队列饱和**:
   - 如果 CLI 表面消费事件不够快，事件会被丢弃
   - `Lagged` 事件会通知调用方，但调用方必须正确处理
   - 关键事件（如 `TurnCompleted`）会阻塞直到送达

2. **请求 ID 冲突**:
   - 调用方负责确保请求 ID 唯一
   - 重复的请求 ID 会导致 `INVALID_REQUEST` 错误

3. **线程管理器逃逸**:
   ```rust
   // 临时逃生舱口
   pub fn auth_manager(&self) -> Arc<AuthManager>
   pub fn thread_manager(&self) -> Arc<ThreadManager>
   ```
   - 这些访问器是临时方案，用于迁移期间的兼容性
   - 未来应移除，完全通过 RPC 交互

4. **远程与进程内行为差异**:
   - 虽然 API 统一，但错误处理可能有细微差别
   - 远程连接有额外的网络错误模式

### 边界

1. **单线程事件消费**:
   - `next_event()` 是顺序的，不支持并行消费
   - 事件处理阻塞会影响背压

2. **Tokio 运行时依赖**:
   - 必须在 Tokio 运行时上下文中使用
   - 不支持其他异步运行时

3. **初始化后配置固定**:
   - 启动后无法动态更改大多数配置
   - 需要重启客户端才能应用新配置

4. **WebSocket 仅支持**:
   - 远程客户端仅支持 WebSocket，不支持 HTTP/2 或其他传输

### 改进建议

1. **文档改进**:
   - 添加更多代码示例，展示完整的请求/响应流程
   - 添加错误处理最佳实践
   - 添加性能调优指南（通道容量选择）

2. **API 增强**:
   ```rust
   // 建议：添加批量请求支持
   pub async fn request_batch(
       &self,
       requests: Vec<ClientRequest>,
   ) -> Vec<IoResult<RequestResult>>
   
   // 建议：添加事件过滤
   pub async fn next_event_filtered(
       &mut self,
       filter: impl Fn(&AppServerEvent) -> bool,
   ) -> Option<AppServerEvent>
   ```

3. **可观测性**:
   - 添加指标暴露（请求延迟、队列深度、事件丢弃率）
   - 添加结构化日志上下文

4. **配置灵活性**:
   - 支持动态重新配置某些参数
   - 支持连接池（对于远程客户端）

5. **移除临时逃生舱口**:
   - 制定计划移除 `auth_manager()` 和 `thread_manager()`
   - 推动所有交互通过 RPC 进行

6. **测试工具**:
   - 提供 mock 客户端用于测试
   - 提供测试辅助函数

7. **背压策略配置**:
   - 允许调用方配置背压行为
   - 支持自定义队列满时的策略（阻塞 vs 丢弃）
