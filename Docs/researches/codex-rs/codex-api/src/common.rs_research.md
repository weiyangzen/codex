# common.rs 研究文档

## 场景与职责

`common.rs` 是 `codex-api` crate 的核心类型定义模块，承载了 Codex/OpenAI API 请求/响应的通用数据结构。该模块位于 API 层与协议层之间，负责：

1. **请求载荷定义**: 定义 Compaction、Memory Summarization、Responses API 的请求体结构
2. **响应事件抽象**: 定义 `ResponseEvent` 枚举，统一 SSE 和 WebSocket 的响应事件
3. **协议转换**: 实现从内部配置类型到 OpenAI API 类型的转换（如 Verbosity、Reasoning）
4. **流式响应支持**: 定义 `ResponseStream`，提供异步事件流接口

在架构中，该模块是连接 `codex-protocol`（内部协议）与 OpenAI API（外部协议）的桥梁。

## 功能点目的

### 1. Compaction API 类型
- `CompactionInput`: 上下文压缩请求的输入参数
  - `model`: 用于压缩的模型
  - `input`: 待压缩的历史消息
  - `instructions`: 压缩指令
  - `tools`/`parallel_tool_calls`: 工具配置
  - `reasoning`/`text`: 可选的推理和文本控制

### 2. Memory API 类型
- `MemorySummarizeInput`: 记忆总结请求
  - `model`: 使用的模型
  - `raw_memories` (序列化为 `traces`): 原始记忆数据
  - `reasoning`: 可选推理配置
- `MemorySummarizeOutput`: 记忆总结响应
  - `raw_memory`/`memory_summary`: 双重别名支持（`trace_summary`/`raw_memory`）
- `RawMemory`/`RawMemoryMetadata`: 原始记忆数据结构

### 3. ResponseEvent 枚举
统一所有可能的响应事件类型：
- **生命周期事件**: `Created`, `Completed`
- **内容事件**: `OutputItemDone`, `OutputItemAdded`, `OutputTextDelta`
- **推理事件**: `ReasoningSummaryDelta`, `ReasoningContentDelta`, `ReasoningSummaryPartAdded`
- **元数据事件**: `ServerModel`, `ServerReasoningIncluded`, `RateLimits`, `ModelsEtag`

### 4. 文本控制类型
- `TextControls`: Responses API 的 `text` 字段控制
  - `verbosity`: 输出详细程度（Low/Medium/High）
  - `format`: JSON Schema 输出格式
- `Reasoning`: 推理配置（effort + summary）

### 5. WebSocket 请求类型
- `ResponsesApiRequest`: HTTP API 请求体
- `ResponseCreateWsRequest`: WebSocket 请求体（扩展了 `generate` 和 `client_metadata`）
- `ResponsesWsRequest`: 带标签的 WebSocket 请求枚举

### 6. 客户端元数据
- `response_create_client_metadata`: 构建包含 W3C Trace Context 的客户端元数据
- 支持 `traceparent` 和 `tracestate` 的传递

## 具体技术实现

### 关键数据结构

```rust
/// 响应事件统一枚举
pub enum ResponseEvent {
    Created,
    OutputItemDone(ResponseItem),
    OutputItemAdded(ResponseItem),
    ServerModel(String),
    ServerReasoningIncluded(bool),
    Completed { response_id: String, token_usage: Option<TokenUsage> },
    OutputTextDelta(String),
    ReasoningSummaryDelta { delta: String, summary_index: i64 },
    ReasoningContentDelta { delta: String, content_index: i64 },
    ReasoningSummaryPartAdded { summary_index: i64 },
    RateLimits(RateLimitSnapshot),
    ModelsEtag(String),
}

/// 流式响应包装器
pub struct ResponseStream {
    pub rx_event: mpsc::Receiver<Result<ResponseEvent, ApiError>>,
}

/// 实现 Stream trait，支持异步迭代
impl Stream for ResponseStream {
    type Item = Result<ResponseEvent, ApiError>;
    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        self.rx_event.poll_recv(cx)
    }
}
```

### 类型转换实现

```rust
// VerbosityConfig (内部) -> OpenAiVerbosity (API)
impl From<VerbosityConfig> for OpenAiVerbosity {
    fn from(v: VerbosityConfig) -> Self {
        match v {
            VerbosityConfig::Low => OpenAiVerbosity::Low,
            VerbosityConfig::Medium => OpenAiVerbosity::Medium,
            VerbosityConfig::High => OpenAiVerbosity::High,
        }
    }
}

// ResponsesApiRequest -> ResponseCreateWsRequest
impl From<&ResponsesApiRequest> for ResponseCreateWsRequest {
    fn from(request: &ResponsesApiRequest) -> Self {
        Self { /* 字段克隆 */ }
    }
}
```

### 序列化策略

使用 `serde` 的字段级控制：
- `#[serde(skip_serializing_if = "Option::is_none")]`: 省略空 Option
- `#[serde(rename = "...")]`: 字段名映射（如 `raw_memories` -> `traces`）
- `#[serde(rename_all = "snake_case")]`: 枚举变体命名风格

## 关键代码路径与文件引用

### 内部调用关系
```
common.rs
├── ResponseEvent (被 sse/responses.rs 和 responses_websocket.rs 使用)
├── ResponseStream (被 lib.rs 导出，被 core crate 使用)
├── CompactionInput (被 endpoint/compact.rs 使用)
├── MemorySummarizeInput/Output (被 endpoint/memories.rs 使用)
├── ResponsesApiRequest/ResponseCreateWsRequest (被 endpoint/responses.rs/responses_websocket.rs 使用)
└── create_text_param_for_request (辅助函数，构建 TextControls)
```

### 外部依赖类型
- `codex_protocol::models::ResponseItem`: 响应项模型
- `codex_protocol::protocol::RateLimitSnapshot`: 速率限制快照
- `codex_protocol::protocol::TokenUsage`: Token 使用量
- `codex_protocol::protocol::W3cTraceContext`: W3C 分布式追踪
- `codex_protocol::config_types::ReasoningSummary/Verbosity`: 内部配置类型
- `codex_protocol::openai_models::ReasoningEffort`: 推理努力程度

### 被调用方
- `codex-rs/codex-api/src/sse/responses.rs`: 解析 SSE 事件为 ResponseEvent
- `codex-rs/codex-api/src/endpoint/responses.rs`: 构建 HTTP 请求
- `codex-rs/codex-api/src/endpoint/responses_websocket.rs`: 构建 WebSocket 请求
- `codex-rs/codex-api/src/endpoint/compact.rs`: 压缩 API 调用
- `codex-rs/codex-api/src/endpoint/memories.rs`: 记忆总结 API 调用

## 依赖与外部交互

### 外部依赖
| Crate | 用途 |
|-------|------|
| `codex_protocol` | `ResponseItem`, `RateLimitSnapshot`, `TokenUsage`, `W3cTraceContext`, 配置类型 |
| `futures` | `Stream` trait 实现 |
| `serde` | 序列化/反序列化 |
| `tokio::sync::mpsc` | 异步通道，用于 ResponseStream |

### 协议规范
- **OpenAI Responses API**: 请求/响应格式遵循 OpenAI API 规范
- **W3C Trace Context**: 支持分布式追踪的 `traceparent`/`tracestate` 头
- **JSON Schema**: 文本格式的 schema 验证

## 风险、边界与改进建议

### 已知风险

1. **字段别名复杂性**
   - `MemorySummarizeOutput` 使用 `#[serde(rename = "trace_summary", alias = "raw_memory")]`
   - 风险：双别名可能导致反序列化歧义
   - 建议：统一字段名，或明确文档说明优先级

2. **通道缓冲区大小**
   - `ResponseStream` 使用 `mpsc::channel`（默认大小）
   - 在高吞吐量场景下可能阻塞发送方
   - 建议：评估是否需要无界通道或更大的缓冲区

3. **克隆开销**
   - `ResponsesApiRequest -> ResponseCreateWsRequest` 转换涉及大量字段克隆
   - 大 `input` 向量可能导致性能问题
   - 建议：考虑使用 `Arc<[ResponseItem]>` 或类似共享结构

### 边界条件

1. **空输入处理**: `input: &[ResponseItem]` 为空时，API 行为取决于服务器
2. **大模型名称**: `model` 字段无长度限制，极端情况可能影响序列化
3. **Token 使用量**: `TokenUsage` 中的负值未在类型层面禁止

### 改进建议

1. **类型安全增强**
   ```rust
   // 使用 newtype 模式避免字符串混淆
   pub struct ModelId(String);
   pub struct ResponseId(String);
   ```

2. **性能优化**
   ```rust
   // 考虑使用 Arc 减少克隆
   pub struct ResponsesApiRequest {
       pub input: Arc<[ResponseItem]>,
       // ...
   }
   ```

3. **文档完善**
   - 为 `ResponseEvent` 各变体添加更详细的文档注释
   - 说明 `ServerReasoningIncluded` 的业务含义（避免客户端重复计算）

4. **测试覆盖**
   - 当前无单元测试
   - 建议添加：序列化/反序列化测试、Stream 行为测试

5. **常量提取**
   ```rust
   // 将魔法字符串提取为常量
   pub const WS_REQUEST_HEADER_TRACEPARENT_CLIENT_METADATA_KEY: &str = "ws_request_header_traceparent";
   pub const WS_REQUEST_HEADER_TRACESTATE_CLIENT_METADATA_KEY: &str = "ws_request_header_tracestate";
   ```
