# codex-rs/codex-api/README.md 研究文档

## 场景与职责

`codex-api` crate 是 Codex 项目的 API 客户端层，构建在 `codex-client` 提供的通用传输层之上。它为 Codex/OpenAI API 提供类型化的客户端实现，包括 Responses API、Compaction API 和 Memory Summarization API。

该 crate 的定位是**线层（wire-level layer）**，负责：
- HTTP/WebSocket 通信细节封装
- 请求/响应模型的类型安全
- SSE 流解析和事件转换
- 认证头注入和重试策略
- 速率限制快照和错误映射

更高层（如 `codex-core`）负责认证刷新和业务逻辑。

## 功能点目的

### 1. Responses API 端点

#### 输入
- `ResponsesApiRequest`: 请求体，包含：
  - `model`: 模型标识
  - `instructions`: 系统指令
  - `input`: 输入消息序列
  - `tools`: 可用工具列表
  - `parallel_tool_calls`: 并行工具调用标志
  - `reasoning`/`text`: 推理和文本控制参数

- `ResponsesOptions`: 传输/头相关选项：
  - `conversation_id`: 会话标识
  - `session_source`: 会话来源（用于子代理追踪）
  - `extra_headers`: 额外 HTTP 头
  - `compression`: 压缩选项
  - `turn_state`: 回合状态追踪

#### 输出
- `ResponseStream`: SSE 事件流
- `ResponseEvent`: 流事件枚举，包括：
  - `Created`: 响应创建
  - `OutputItemDone`/`OutputItemAdded`: 输出项完成/添加
  - `ServerModel`: 服务器选择的模型
  - `Completed`: 响应完成（含 token 用量）
  - `OutputTextDelta`: 文本增量
  - `RateLimits`: 速率限制快照

### 2. Compaction API 端点

#### 输入
- `CompactionInput<'a>`:
  - `model`: 模型标识
  - `input`: 待压缩的历史记录（`&[ResponseItem]`）
  - `instructions`: 压缩指令

#### 输出
- `Vec<ResponseItem>`: 压缩后的响应项列表

#### 客户端
- `CompactClient::compact_input(&CompactionInput, extra_headers)`: 封装 JSON 编码、重试和遥测

### 3. Memory Summarize API 端点

#### 输入
- `MemorySummarizeInput`:
  - `model`: 模型标识
  - `raw_memories`: 原始记忆列表（序列化为 `traces` 字段）
    - `RawMemory`: 包含 `id`, `metadata.source_path`, `items`
  - `reasoning`: 可选推理配置

#### 输出
- `Vec<MemorySummarizeOutput>`: 记忆摘要输出列表

#### 客户端
- `MemoriesClient::summarize_input(&MemorySummarizeInput, extra_headers)`: 封装 JSON 编码、重试和遥测

## 具体技术实现

### 架构分层
```
┌─────────────────────────────────────┐
│  codex-core (业务逻辑层)            │
├─────────────────────────────────────┤
│  codex-api (线层/协议层)            │ ← 本文档描述
│  - ResponsesClient                  │
│  - CompactClient                    │
│  - MemoriesClient                   │
│  - RealtimeWebsocketClient          │
├─────────────────────────────────────┤
│  codex-client (传输抽象层)          │
│  - HttpTransport trait              │
│  - 重试逻辑                         │
│  - TLS 配置                         │
└─────────────────────────────────────┘
```

### 关键设计决策

1. **小且统一的公共接口**: 故意保持接口简洁，减少使用者的认知负担
2. **流式响应**: Responses API 返回 `ResponseStream`，支持实时处理 SSE 事件
3. **类型安全**: 所有请求/响应都有对应的 Rust 结构体，编译时检查
4. **遥测集成**: 通过 `with_telemetry()` 方法集成请求和 SSE 遥测

### 协议处理

#### SSE (Server-Sent Events) 处理
- 使用 `eventsource-stream` crate 解析 SSE 流
- 将原始 SSE 事件转换为 `ResponseEvent` 枚举
- 处理特殊头：
  - `OpenAI-Model`: 服务器实际使用的模型
  - `X-Reasoning-Included`: 推理 token 已计入标志
  - `X-Models-Etag`: 模型列表 ETag
  - `X-Codex-*`: Codex 特定的速率限制头

#### WebSocket 处理（Realtime API）
- 使用 `tokio-tungstenite` 进行 WebSocket 通信
- 支持 V1 和 V2 两种事件解析协议
- 处理音频帧、会话更新、对话项等实时事件

### 错误处理
- `ApiError` 枚举封装所有可能的错误：
  - `Transport`: 传输层错误
  - `Api`: HTTP API 错误（含状态码）
  - `Stream`: 流处理错误
  - `ContextWindowExceeded`: 上下文窗口超限
  - `QuotaExceeded`: 配额超限
  - `RateLimit`: 速率限制
  - `Retryable`: 可重试错误（含延迟建议）

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|----------|------|
| `src/lib.rs` | 公共接口导出 |
| `src/common.rs` | 共享类型（`ResponsesApiRequest`, `ResponseEvent`, `CompactionInput`, `MemorySummarizeInput`） |
| `src/endpoint/responses.rs` | Responses HTTP 客户端 |
| `src/endpoint/responses_websocket.rs` | Responses WebSocket 客户端 |
| `src/endpoint/compact.rs` | Compaction 客户端 |
| `src/endpoint/memories.rs` | Memory summarization 客户端 |
| `src/endpoint/realtime_websocket/` | Realtime API WebSocket 实现 |
| `src/endpoint/session.rs` | 端点会话管理（认证、重试、遥测） |
| `src/sse/responses.rs` | SSE 流解析和事件处理 |
| `src/rate_limits.rs` | 速率限制头解析 |
| `src/auth.rs` | 认证提供者 trait |
| `src/provider.rs` | Provider 配置（URL、头、重试策略） |
| `src/error.rs` | 错误类型定义 |

## 依赖与外部交互

### 上游依赖（输入）
| 组件 | 交互方式 |
|------|----------|
| `codex-client` | `HttpTransport` trait 实现 |
| `codex-protocol` | 共享模型类型（`ResponseItem`, `TokenUsage` 等） |
| `codex-core` | 调用者，提供 `AuthProvider` 实现 |

### 下游依赖（输出）
| 组件 | 用途 |
|------|------|
| OpenAI API | HTTP 请求目标 |
| Codex API | WebSocket 和 HTTP 请求目标 |

### 认证流程
```rust
// 高层提供 AuthProvider 实现
pub trait AuthProvider: Send + Sync {
    fn bearer_token(&self) -> Option<String>;
    fn account_id(&self) -> Option<String>;
}

// codex-api 在请求时注入认证头
fn add_auth_headers<A: AuthProvider>(auth: &A, mut req: Request) -> Request
```

## 风险、边界与改进建议

### 风险点

1. **Azure 兼容性**: 
   - `provider.rs` 中有特殊的 Azure 端点检测逻辑
   - Azure 需要特殊的 `attach_item_ids` 处理（`responses.rs:84-86`）
   - 风险：Azure API 变更可能导致兼容性问题

2. **SSE 流超时**:
   - `spawn_response_stream` 使用 `stream_idle_timeout` 检测空闲流
   - 风险：网络延迟或服务器缓慢可能导致误判为超时

3. **WebSocket 连接限制**:
   - 服务器有 60 分钟连接限制（`responses_websocket.rs:160`）
   - 需要正确处理 `websocket_connection_limit_reached` 错误

4. **模型路由**:
   - `ServerModel` 事件表示服务器可能选择了不同于请求的模型（安全路由）
   - 调用者需要处理这种情况

### 边界情况

1. **空响应**: SSE 流可能在 `response.completed` 前关闭，需要正确处理
2. **速率限制头**: 支持多组速率限制头（`x-codex-*`, `x-codex-secondary-*`）
3. **压缩**: 支持 Zstd 压缩，需要服务器支持

### 改进建议

1. **连接池**: 考虑为 HTTP 客户端实现连接池，减少连接开销
2. **背压处理**: SSE 通道大小固定为 1600，考虑动态调整或背压机制
3. **指标暴露**: 除了遥测 trait，考虑暴露 Prometheus 格式的指标
4. **协议版本协商**: Realtime API 的 V1/V2 解析器需要显式配置，考虑自动协商
5. **测试覆盖**: 增加集成测试，使用 `wiremock` 或类似工具模拟 API 响应
6. **文档完善**: 为公共 API 添加更多示例代码和用例说明
