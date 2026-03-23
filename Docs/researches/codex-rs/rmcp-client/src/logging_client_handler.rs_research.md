# logging_client_handler.rs 研究文档

## 场景与职责

`logging_client_handler.rs` 实现了 MCP 客户端的日志处理器，作为 `rmcp` SDK 的 `ClientHandler` trait 的实现者。该模块负责处理从 MCP 服务器接收到的各类通知和请求，并将其转换为可追踪的日志输出。

核心职责：
1. **服务器通知处理**: 处理 MCP 服务器的各类通知（取消、进度、资源更新、列表变更等）
2. **交互请求处理**: 处理服务器发起的交互请求（elicitation）
3. **日志级别映射**: 将 MCP 日志级别映射到 tracing 日志级别
4. **客户端信息提供**: 向服务器提供客户端标识信息

## 功能点目的

### 1. ClientHandler Trait 实现

`rmcp` SDK 要求客户端实现 `ClientHandler` trait 来处理服务器端的通知和请求。本模块提供了默认的日志记录实现。

### 2. 通知类型处理

| 通知类型 | 处理行为 |
|----------|----------|
| `create_elicitation` | 转发到 UI 处理回调 |
| `on_cancelled` | 记录 info 级别日志 |
| `on_progress` | 记录 info 级别日志 |
| `on_resource_updated` | 记录 info 级别日志 |
| `on_resource_list_changed` | 记录 info 级别日志 |
| `on_tool_list_changed` | 记录 info 级别日志 |
| `on_prompt_list_changed` | 记录 info 级别日志 |
| `on_logging_message` | 按级别映射到对应 tracing 级别 |

### 3. 日志级别映射

MCP 日志级别到 tracing 级别的映射：
- `Emergency/Alert/Critical/Error` → `tracing::error`
- `Warning` → `tracing::warn`
- `Notice/Info` → `tracing::info`
- `Debug` → `tracing::debug`

## 具体技术实现

### 数据结构

```rust
#[derive(Clone)]
pub(crate) struct LoggingClientHandler {
    client_info: ClientInfo,
    send_elicitation: Arc<SendElicitation>,
}
```

**字段说明**：
- `client_info`: 客户端标识信息（名称、版本等）
- `send_elicitation`: 交互请求转发回调，通过 Arc 实现共享所有权

### 构造函数

```rust
impl LoggingClientHandler {
    pub(crate) fn new(client_info: ClientInfo, send_elicitation: SendElicitation) -> Self {
        Self {
            client_info,
            send_elicitation: Arc::new(send_elicitation),
        }
    }
}
```

### ClientHandler 实现

#### 交互请求处理

```rust
async fn create_elicitation(
    &self,
    request: CreateElicitationRequestParams,
    context: RequestContext<RoleClient>,
) -> Result<CreateElicitationResult, rmcp::ErrorData> {
    (self.send_elicitation)(context.id, request)
        .await
        .map(Into::into)
        .map_err(|err| rmcp::ErrorData::internal_error(err.to_string(), None))
}
```

**流程**：
1. 调用 `send_elicitation` 回调转发请求
2. 将结果转换为 `CreateElicitationResult`
3. 错误时转换为 MCP 内部错误

#### 取消通知

```rust
async fn on_cancelled(
    &self,
    params: CancelledNotificationParam,
    _context: NotificationContext<RoleClient>,
) {
    info!(
        "MCP server cancelled request (request_id: {}, reason: {:?})",
        params.request_id, params.reason
    );
}
```

#### 进度通知

```rust
async fn on_progress(
    &self,
    params: ProgressNotificationParam,
    _context: NotificationContext<RoleClient>,
) {
    info!(
        "MCP server progress notification (token: {:?}, progress: {}, total: {:?}, message: {:?})",
        params.progress_token, params.progress, params.total, params.message
    );
}
```

#### 日志消息处理

```rust
async fn on_logging_message(
    &self,
    params: LoggingMessageNotificationParam,
    _context: NotificationContext<RoleClient>,
) {
    let LoggingMessageNotificationParam { level, logger, data } = params;
    let logger = logger.as_deref();
    match level {
        LoggingLevel::Emergency | LoggingLevel::Alert | LoggingLevel::Critical | LoggingLevel::Error => {
            error!("MCP server log message (level: {:?}, logger: {:?}, data: {})", level, logger, data);
        }
        // ... 其他级别处理
    }
}
```

## 关键代码路径与文件引用

### 内部依赖

| 依赖项 | 路径 | 用途 |
|--------|------|------|
| `SendElicitation` | `crate::rmcp_client` | 交互请求回调类型 |

### 外部依赖 (rmcp)

| 依赖项 | 用途 |
|--------|------|
| `ClientHandler` | 必须实现的 trait |
| `RoleClient` | 客户端角色标记 |
| `RequestContext` | 请求上下文 |
| `NotificationContext` | 通知上下文 |
| `CreateElicitationRequestParams` | 交互请求参数 |
| `LoggingMessageNotificationParam` | 日志消息参数 |
| `LoggingLevel` | MCP 日志级别枚举 |

### 外部依赖 (tracing)

| 依赖项 | 用途 |
|--------|------|
| `debug` | Debug 级别日志 |
| `error` | Error 级别日志 |
| `info` | Info 级别日志 |
| `warn` | Warn 级别日志 |

### 调用关系

```
logging_client_handler.rs
├── 被 rmcp_client.rs 创建和使用
│   └── RmcpClient::initialize() 创建 handler
│   └── 传递给 service::serve_client()
├── 调用 rmcp_client.rs
│   └── SendElicitation 回调类型
└── 被 lib.rs 重导出
    └── Elicitation, ElicitationResponse, SendElicitation
```

## 依赖与外部交互

### 与 rmcp SDK 的交互

`LoggingClientHandler` 实现了 `rmcp::ClientHandler`，是客户端与 MCP 服务器通信的回调接口：

```
MCP Server → rmcp SDK → ClientHandler 方法 → 日志/回调
```

### 与 UI 的交互

通过 `SendElicitation` 回调将服务器的交互请求转发到 UI 层：

```rust
pub type SendElicitation = Box<
    dyn Fn(RequestId, Elicitation) -> BoxFuture<'static, Result<ElicitationResponse>> + Send + Sync,
>;
```

**参数**：
- `RequestId`: 请求标识，用于关联响应
- `Elicitation`: 交互请求参数（别名 `CreateElicitationRequestParams`）

**返回**：
- `ElicitationResponse`: 用户响应，包含动作和内容

## 风险、边界与改进建议

### 当前设计特点

1. **纯日志处理**: 除 elicitation 外，所有通知仅记录日志，不触发业务逻辑
2. **错误转换**: 将 anyhow 错误转换为 MCP 内部错误
3. **克隆开销**: `client_info` 每次 `get_info()` 调用时克隆

### 潜在风险

1. **日志洪水**: 高频率的进度通知可能导致日志输出过多
   - 建议：考虑添加采样或速率限制

2. **回调阻塞**: `send_elicitation` 是异步回调，但如果实现者阻塞，会影响 MCP 服务
   - 建议：文档中应说明回调需要及时返回

3. **错误信息丢失**: `create_elicitation` 仅传递错误字符串，丢失原始错误链
   ```rust
   .map_err(|err| rmcp::ErrorData::internal_error(err.to_string(), None))
   ```

### 改进建议

1. **结构化日志**: 使用 tracing 的结构化字段替代字符串格式化
   ```rust
   // 当前
   info!("MCP server progress (token: {:?}, ...)", params.progress_token);
   // 建议
   info!(token = ?params.progress_token, progress = params.progress, "MCP server progress");
   ```

2. **可配置日志级别**: 允许调用方配置哪些通知类型需要记录

3. **指标收集**: 除日志外，可考虑收集通知统计指标

4. **Elicitation 超时**: 当前实现依赖调用方处理超时，可考虑在 handler 层添加超时控制

### 测试建议

当前模块缺少单元测试，建议添加：
- 日志级别映射测试
- `create_elicitation` 错误转换测试
- `get_info` 返回值验证测试
