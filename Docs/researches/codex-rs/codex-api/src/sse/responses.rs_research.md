# SSE Responses 处理模块研究文档

## 文件信息
- **路径**: `codex-rs/codex-api/src/sse/responses.rs`
- **大小**: ~37,033 bytes (~1059 行)
- **作用**: OpenAI Responses API 的 SSE (Server-Sent Events) 流式响应解析与处理

---

## 场景与职责

本模块是 Codex 系统与 OpenAI Responses API 流式响应交互的核心组件，负责：

1. **SSE 流解析**: 将 HTTP SSE 字节流解析为结构化事件
2. **事件转换**: 将 OpenAI 特定的事件格式转换为内部 `ResponseEvent` 枚举
3. **错误处理**: 分类处理各种 API 错误（限流、上下文窗口超限、配额不足等）
4. **遥测支持**: 集成 `SseTelemetry` 进行性能监控
5. **测试支持**: 提供从固件文件加载 SSE 数据的能力

### 在系统架构中的位置
```
OpenAI Responses API (SSE Stream)
           ↓
    HTTP Transport (codex-client)
           ↓
    spawn_response_stream (本模块)
           ↓
    process_sse (本模块)
           ↓
    ResponseEvent → codex-core / TUI
```

---

## 功能点目的

### 1. 响应流创建 (`spawn_response_stream`)
从 HTTP 响应创建 SSE 事件流，提取关键 HTTP 头信息：
- `openai-model`: 实际使用的模型（可能与请求不同，因安全路由）
- `x-reasoning-included`: 服务器是否已包含推理 token
- `x-models-etag`: 模型列表的 ETag
- `x-codex-turn-state`: 回合状态
- 限流头信息（通过 `parse_all_rate_limits`）

### 2. SSE 事件处理 (`process_sse`)
核心事件循环，使用 `eventsource_stream` crate 解析 SSE 格式：
```
event: response.output_item.done
data: {"type": "response.output_item.done", "item": {...}}

event: response.completed
data: {"type": "response.completed", "response": {...}}
```

### 3. 事件解析 (`process_responses_event`)
支持的事件类型映射：

| OpenAI 事件 | 内部事件 | 说明 |
|-------------|----------|------|
| `response.created` | `ResponseEvent::Created` | 响应开始 |
| `response.output_item.done` | `ResponseEvent::OutputItemDone` | 输出项完成 |
| `response.output_item.added` | `ResponseEvent::OutputItemAdded` | 输出项添加 |
| `response.output_text.delta` | `ResponseEvent::OutputTextDelta` | 文本增量 |
| `response.reasoning_summary_text.delta` | `ResponseEvent::ReasoningSummaryDelta` | 推理摘要增量 |
| `response.reasoning_text.delta` | `ResponseEvent::ReasoningContentDelta` | 推理内容增量 |
| `response.reasoning_summary_part.added` | `ResponseEvent::ReasoningSummaryPartAdded` | 推理摘要部分添加 |
| `response.completed` | `ResponseEvent::Completed` | 响应完成 |
| `response.failed` | `ApiError` (多种) | 响应失败 |
| `response.incomplete` | `ApiError::Stream` | 响应不完整 |

### 4. 错误分类处理
- **上下文窗口超限** (`context_length_exceeded`) → `ApiError::ContextWindowExceeded`
- **配额不足** (`insufficient_quota`) → `ApiError::QuotaExceeded`
- **使用未包含** (`usage_not_included`) → `ApiError::UsageNotIncluded`
- **无效提示** (`invalid_prompt`) → `ApiError::InvalidRequest`
- **服务器过载** (`server_is_overloaded`/`slow_down`) → `ApiError::ServerOverloaded`
- **限流** (`rate_limit_exceeded`) → `ApiError::Retryable`（带重试延迟）

### 5. 测试固件支持 (`stream_from_fixture`)
从本地 JSONL 文件加载 SSE 事件，用于单元测试和集成测试。

---

## 具体技术实现

### 核心数据结构

#### `ResponsesStreamEvent` - SSE 事件原始结构
```rust
#[derive(Deserialize, Debug)]
pub struct ResponsesStreamEvent {
    #[serde(rename = "type")]
    pub(crate) kind: String,
    headers: Option<Value>,
    response: Option<Value>,
    item: Option<Value>,
    delta: Option<String>,
    summary_index: Option<i64>,
    content_index: Option<i64>,
}
```

#### 错误结构（OpenAI 格式）
```rust
#[derive(Debug, Deserialize)]
struct Error {
    r#type: Option<String>,
    code: Option<String>,
    message: Option<String>,
    plan_type: Option<String>,
    resets_at: Option<i64>,
}
```

#### 响应完成结构
```rust
#[derive(Debug, Deserialize)]
struct ResponseCompleted {
    id: String,
    #[serde(default)]
    usage: Option<ResponseCompletedUsage>,
}

#[derive(Debug, Deserialize)]
struct ResponseCompletedUsage {
    input_tokens: i64,
    input_tokens_details: Option<ResponseCompletedInputTokensDetails>,
    output_tokens: i64,
    output_tokens_details: Option<ResponseCompletedOutputTokensDetails>,
    total_tokens: i64,
}
```

### 关键算法

#### 1. 限流重试延迟解析
使用正则表达式从错误消息中提取重试等待时间：
```rust
fn try_parse_retry_after(err: &Error) -> Option<Duration> {
    // 匹配 "try again in 11.054s" 或 "35 seconds"
    let re = regex_lite::Regex::new(r"(?i)try again in\s*(\d+(?:\.\d+)?)\s*(s|ms|seconds?)");
    // 支持秒和毫秒单位
}
```

#### 2. 模型头信息提取
支持两种来源的模型信息：
- `response.headers.openai-model` (标准 Responses 流事件)
- 顶层 `headers` (WebSocket 元数据事件，如 `codex.response.metadata`)

```rust
pub fn response_model(&self) -> Option<String> {
    // 优先级：response.headers > 顶层 headers
}
```

#### 3. SSE 事件循环
```rust
pub async fn process_sse(...) {
    let mut stream = stream.eventsource();
    let mut response_error: Option<ApiError> = None;
    let mut last_server_model: Option<String> = None;

    loop {
        // 1. 带超时等待 SSE 事件
        let response = timeout(idle_timeout, stream.next()).await;
        
        // 2. 遥测记录
        if let Some(t) = telemetry.as_ref() {
            t.on_sse_poll(&response, start.elapsed());
        }
        
        // 3. 解析事件
        let event: ResponsesStreamEvent = serde_json::from_str(&sse.data)?;
        
        // 4. 检测模型变更
        if let Some(model) = event.response_model() {
            // 发送 ServerModel 事件
        }
        
        // 5. 处理事件
        match process_responses_event(event) {
            Ok(Some(event)) => {
                tx_event.send(Ok(event)).await;
                if is_completed { return; }
            }
            Err(error) => { response_error = Some(error); }
            _ => {}
        }
    }
}
```

---

## 关键代码路径与文件引用

### 调用链

#### 正常请求流程
```
ResponsesClient::stream (endpoint/responses.rs:115)
    └── spawn_response_stream (line 57)
        ├── 提取 HTTP 头信息 (line 63-85)
        ├── 发送初始事件 (ServerModel, RateLimits, ModelsEtag, ServerReasoningIncluded)
        └── process_sse (line 102)
            └── 事件循环 (line 367-433)
```

#### 测试流程
```
test code
    └── stream_from_fixture (line 32)
        └── process_sse
```

### 依赖文件

#### 内部依赖
| 文件 | 用途 |
|------|------|
| `common.rs` | `ResponseEvent`, `ResponseStream` 定义 |
| `error.rs` | `ApiError` 错误类型 |
| `rate_limits.rs` | `parse_all_rate_limits` 限流头解析 |
| `telemetry.rs` | `SseTelemetry` trait |

#### 外部 Crate
| Crate | 用途 |
|-------|------|
| `codex-client` | `ByteStream`, `StreamResponse`, `TransportError` |
| `codex-protocol` | `ResponseItem`, `TokenUsage`, `RateLimitSnapshot` |
| `eventsource_stream` | SSE 协议解析 |
| `tokio::sync::mpsc` | 异步事件通道 |
| `tokio::time::timeout` | 空闲超时控制 |

---

## 依赖与外部交互

### HTTP 头交互

#### 读取的头信息
| 头名称 | 用途 | 代码位置 |
|--------|------|----------|
| `openai-model` | 实际使用的模型 | line 69-73, 186-213 |
| `x-reasoning-included` | 推理 token 是否已包含 | line 74-77 |
| `x-models-etag` | 模型列表缓存标签 | line 64-68 |
| `x-codex-turn-state` | 回合状态 | line 78-85 |
| `x-{limit}-primary-used-percent` | 限流信息 | via `parse_all_rate_limits` |

#### 常量定义
```rust
const X_REASONING_INCLUDED_HEADER: &str = "x-reasoning-included";
const OPENAI_MODEL_HEADER: &str = "openai-model";
```

### 事件通道
使用 `tokio::sync::mpsc` 通道进行异步事件传递：
```rust
let (tx_event, rx_event) = mpsc::channel::<Result<ResponseEvent, ApiError>>(1600);
```

通道容量为 1600，这是一个经验值，用于平衡内存使用和背压处理。

---

## 风险、边界与改进建议

### 风险点

#### 1. 超时处理
```rust
let response = timeout(idle_timeout, stream.next()).await;
```
- 空闲超时可能导致长时间运行的响应被中断
- 超时后通道关闭，未处理的事件丢失

#### 2. 错误累积
```rust
Err(error) => {
    response_error = Some(error.into_api_error());
}
```
- 非致命错误被累积，仅在流结束时报告
- 可能导致错误延迟暴露

#### 3. 正则表达式性能
```rust
fn rate_limit_regex() -> &'static regex_lite::Regex {
    static RE: std::sync::OnceLock<regex_lite::Regex> = std::sync::OnceLock::new();
    RE.get_or_init(|| regex_lite::Regex::new(r"...").unwrap())
}
```
- 使用 `OnceLock` 延迟初始化，但正则表达式在首次限流错误时编译

### 边界条件

#### 1. SSE 格式边界
- 事件数据必须是有效的 JSON
- 不支持多行 data 字段（符合 SSE 规范）

#### 2. 模型检测边界
```rust
fn json_value_as_string(value: &Value) -> Option<String> {
    match value {
        Value::String(value) => Some(value.clone()),
        Value::Array(items) => items.first().and_then(json_value_as_string),
        _ => None,
    }
}
```
- 支持字符串和数组（取首元素）格式的模型值

#### 3. 限流延迟解析边界
- 支持格式：`11.054s`, `35 seconds`, `28ms`
- 不支持其他时间单位（如分钟、小时）

### 改进建议

#### 1. 错误处理增强
```rust
// 建议：添加错误事件立即上报机制
Err(error) => {
    let api_error = error.into_api_error();
    if api_error.is_fatal() {
        let _ = tx_event.send(Err(api_error)).await;
        return;
    }
    response_error = Some(api_error);
}
```

#### 2. 遥测完善
- 当前仅记录轮询耗时，建议增加：
  - 事件处理耗时
  - 事件队列积压情况
  - 模型变更次数

#### 3. 配置化
- 通道容量 1600 可改为配置项
- 空闲超时可根据模型动态调整

#### 4. 测试覆盖
当前测试覆盖：
- ✅ 正常事件流解析
- ✅ 错误事件处理
- ✅ 限流延迟解析
- ✅ 上下文窗口错误
- ✅ 模型头提取

建议增加：
- 超大事件负载测试
- 网络中断恢复测试
- 并发流测试

---

## 测试分析

### 测试结构
模块包含 17 个单元测试，覆盖：

| 测试函数 | 测试内容 |
|----------|----------|
| `parses_items_and_completed` | 正常事件流解析 |
| `error_when_missing_completed` | 缺少 completed 事件错误 |
| `parses_tool_search_call_items` | 工具搜索调用解析 |
| `emits_completed_without_stream_end` | 流未结束但 completed 到达 |
| `error_when_error_event` | 错误事件处理 |
| `context_window_error_is_fatal` | 上下文窗口错误 |
| `context_window_error_with_newline_is_fatal` | 带换行符的错误消息 |
| `quota_exceeded_error_is_fatal` | 配额不足错误 |
| `invalid_prompt_without_type_is_invalid_request` | 无效提示错误 |
| `table_driven_event_kinds` | 表驱动事件类型测试 |
| `spawn_response_stream_emits_server_model_header` | 模型头发送 |
| `process_sse_ignores_response_model_field_in_payload` | 忽略 payload 中的 model 字段 |
| `process_sse_emits_server_model_from_response_headers_payload` | 从 headers 提取模型 |
| `responses_stream_event_response_model_reads_top_level_headers` | 顶层 headers 读取 |
| `responses_stream_event_response_model_prefers_response_headers` | headers 优先级测试 |
| `test_try_parse_retry_after` | 毫秒级限流延迟解析 |
| `test_try_parse_retry_after_no_delay` | 秒级限流延迟解析 |
| `test_try_parse_retry_after_azure` | Azure 格式限流消息 |

### 测试常量
```rust
const CYBER_RESTRICTED_MODEL_FOR_TESTS: &str = "gpt-5.3-codex";
```

---

## 总结

`responses.rs` 是 Codex 系统 SSE 流处理的核心模块，具有以下特点：

1. **职责清晰**: 专注于 OpenAI Responses API 的 SSE 协议解析
2. **错误分类完善**: 支持多种错误类型的识别和转换
3. **可观测性好**: 集成遥测接口，支持性能监控
4. **测试充分**: 覆盖正常流程和多种错误场景

该模块的设计体现了良好的分层架构：底层 SSE 解析、中层事件转换、上层流管理各司其职，通过通道解耦，支持背压和异步处理。
