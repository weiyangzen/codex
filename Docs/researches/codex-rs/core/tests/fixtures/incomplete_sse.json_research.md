# Research: incomplete_sse.json Fixture

## 文件基本信息

- **文件路径**: `codex-rs/core/tests/fixtures/incomplete_sse.json`
- **文件类型**: JSON 测试夹具（Test Fixture）
- **文件大小**: 3 行，约 50 字节
- **创建目的**: 用于测试 SSE（Server-Sent Events）流在异常终止时的重试机制

## 场景与职责

### 核心场景

`incomplete_sse.json` 是一个专门设计的测试夹具，用于模拟 **SSE 流在发送 `response.completed` 事件之前被异常关闭** 的场景。这是 Codex 核心库中流式响应处理的重要边界测试用例。

### 具体职责

1. **测试流完整性检测**: 验证 Codex 客户端能够检测到未正常完成的 SSE 流
2. **测试重试机制**: 验证当 SSE 流异常终止时，系统会触发重试逻辑
3. **测试错误恢复**: 验证系统能够从部分响应中恢复并重新发起请求

### 使用场景

该夹具在 `stream_no_completed.rs` 测试文件中被使用，测试以下场景：
- 第一个请求返回不完整的 SSE 流（仅包含 `response.output_item.done` 事件）
- 系统检测到流不完整后触发重试
- 第二个请求返回完整的 SSE 流（包含 `response.completed` 事件）
- 验证最终成功完成 Turn 执行

## 功能点目的

### 1. SSE 事件格式验证

SSE（Server-Sent Events）是 Codex 与 OpenAI Responses API 通信的核心协议。该夹具验证了系统对不完整 SSE 流的处理能力。

### 2. 流终止检测

Codex 客户端期望每个响应流都以 `response.completed` 事件结束。该夹具模拟了**缺少终止事件**的情况，测试系统是否能够：
- 检测到流异常终止
- 触发适当的错误处理
- 发起重试请求

### 3. 重试预算管理

该测试验证了 `stream_max_retries` 配置参数的工作机制：
- 当流异常终止时，系统会消耗重试预算
- 在预算允许范围内，系统会自动重试
- 重试成功后，Turn 能够正常完成

## 具体技术实现

### 数据结构

```json
[
  {"type": "response.output_item.done"}
]
```

该 JSON 数组包含单个 SSE 事件：
- **事件类型**: `response.output_item.done`
- **事件含义**: 表示一个输出项已完成
- **缺失事件**: `response.completed`（表示整个响应完成）

### SSE 格式转换

该 JSON 夹具通过 `load_sse_fixture` 函数（位于 `codex-rs/core/tests/common/lib.rs`）转换为 SSE 格式：

```rust
pub fn load_sse_fixture(path: impl AsRef<std::path::Path>) -> String {
    let events: Vec<serde_json::Value> =
        serde_json::from_reader(std::fs::File::open(path).expect("read fixture"))
            .expect("parse JSON fixture");
    events
        .into_iter()
        .map(|e| {
            let kind = e
                .get("type")
                .and_then(|v| v.as_str())
                .expect("fixture event missing type");
            if e.as_object().map(|o| o.len() == 1).unwrap_or(false) {
                format!("event: {kind}\n\n")
            } else {
                format!("event: {kind}\ndata: {e}\n\n")
            }
        })
        .collect()
}
```

转换后的 SSE 数据：
```
event: response.output_item.done

```

### 关键流程

#### 测试流程（stream_no_completed.rs）

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn retries_on_early_close() {
    skip_if_no_network!();

    // 1. 加载不完整 SSE 夹具
    let incomplete_sse = sse_incomplete();
    // 2. 准备完整 SSE 响应
    let completed_sse = responses::sse_completed("resp_ok");

    // 3. 启动流式 SSE 服务器，配置两个响应：
    //    - 第一个：不完整响应（会触发重试）
    //    - 第二个：完整响应（重试后成功）
    let (server, _) = start_streaming_sse_server(vec![
        vec![StreamingSseChunk { gate: None, body: incomplete_sse }],
        vec![StreamingSseChunk { gate: None, body: completed_sse }],
    ]).await;

    // 4. 配置 ModelProvider，允许 1 次流重试
    let model_provider = ModelProviderInfo {
        // ... 其他配置 ...
        request_max_retries: Some(0),    // HTTP 请求不重试
        stream_max_retries: Some(1),     // 流重试 1 次
        stream_idle_timeout_ms: Some(2000),
        // ...
    };

    // 5. 构建 TestCodex 并提交用户输入
    let TestCodex { codex, .. } = test_codex()
        .with_config(move |config| { config.model_provider = model_provider; })
        .build_with_streaming_server(&server)
        .await
        .unwrap();

    codex.submit(Op::UserInput { ... }).await.unwrap();

    // 6. 等待 TurnComplete 事件（验证重试成功）
    wait_for_event(&codex, |event| matches!(event, EventMsg::TurnComplete(_))).await;

    // 7. 验证发生了 2 次请求（原始请求 + 1 次重试）
    let requests = server.requests().await;
    assert_eq!(requests.len(), 2, "expected retry after incomplete SSE stream");
}
```

#### 流处理流程（codex-api/src/sse/responses.rs）

```rust
pub async fn process_sse(
    stream: ByteStream,
    tx_event: mpsc::Sender<Result<ResponseEvent, ApiError>>,
    idle_timeout: Duration,
    telemetry: Option<Arc<dyn SseTelemetry>>,
) {
    let mut stream = stream.eventsource();
    let mut response_error: Option<ApiError> = None;

    loop {
        let response = timeout(idle_timeout, stream.next()).await;
        let sse = match response {
            Ok(Some(Ok(sse))) => sse,
            Ok(Some(Err(e))) => { /* 处理 SSE 错误 */ }
            Ok(None) => {
                // 流正常关闭但未收到 response.completed
                let error = response_error.unwrap_or(ApiError::Stream(
                    "stream closed before response.completed".into(),
                ));
                let _ = tx_event.send(Err(error)).await;
                return;
            }
            Err(_) => { /* 处理超时 */ }
        };

        // 处理 SSE 事件...
        match process_responses_event(event) {
            Ok(Some(event)) => {
                let is_completed = matches!(event, ResponseEvent::Completed { .. });
                if tx_event.send(Ok(event)).await.is_err() { return; }
                if is_completed { return; }  // 正常完成，退出循环
            }
            // ...
        }
    }
}
```

#### 重试逻辑（codex-rs/core/src/codex.rs）

```rust
async fn run_sampling_loop(...) -> CodexResult<TurnOutput> {
    let mut retries = 0;
    loop {
        match try_run_sampling_request(...).await {
            Ok(output) => return Ok(output),
            Err(err) => {
                if !err.is_retryable() { return Err(err); }
                
                // 获取配置的重试次数上限
                let max_retries = turn_context.provider.stream_max_retries();
                
                if retries >= max_retries && client_session.try_switch_fallback_transport(...) {
                    // 切换传输层（WebSocket -> HTTP）并重试
                    retries = 0;
                    continue;
                }
                
                if retries < max_retries {
                    retries += 1;
                    let delay = backoff(retries);
                    warn!("stream disconnected - retrying sampling request ({retries}/{max_retries} in {delay:?})...");
                    tokio::time::sleep(delay).await;
                } else {
                    return Err(err);
                }
            }
        }
    }
}
```

### 协议细节

#### SSE 事件类型

| 事件类型 | 描述 | 是否必需 |
|---------|------|---------|
| `response.created` | 响应创建 | 否 |
| `response.output_item.added` | 输出项添加 | 否 |
| `response.output_item.done` | 输出项完成 | 否 |
| `response.output_text.delta` | 输出文本增量 | 否 |
| `response.completed` | 响应完成 | **是** |
| `response.failed` | 响应失败 | 否 |
| `response.incomplete` | 响应不完整 | 否 |

#### 重试配置参数

位于 `codex-rs/core/src/model_provider_info.rs`：

```rust
pub struct ModelProviderInfo {
    /// HTTP 请求最大重试次数
    pub request_max_retries: Option<u64>,
    
    /// 流重连最大重试次数
    pub stream_max_retries: Option<u64>,
    
    /// 流空闲超时（毫秒）
    pub stream_idle_timeout_ms: Option<u64>,
    
    // ... 其他字段
}

// 默认值
const DEFAULT_STREAM_MAX_RETRIES: u64 = 5;
const DEFAULT_REQUEST_MAX_RETRIES: u64 = 4;
const DEFAULT_STREAM_IDLE_TIMEOUT_MS: u64 = 300_000;  // 5 分钟
```

## 关键代码路径与文件引用

### 测试相关文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/tests/fixtures/incomplete_sse.json` | **本夹具文件**，定义不完整 SSE 事件 |
| `codex-rs/core/tests/suite/stream_no_completed.rs` | 主测试文件，使用本夹具测试重试逻辑 |
| `codex-rs/core/tests/common/streaming_sse.rs` | 流式 SSE 测试服务器实现 |
| `codex-rs/core/tests/common/lib.rs` | 测试工具库，包含 `load_sse_fixture` 函数 |
| `codex-rs/core/tests/common/responses.rs` | SSE 响应构建辅助函数 |

### 核心实现文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/codex-api/src/sse/responses.rs` | SSE 流处理核心逻辑，包含 `process_sse` 和 `process_responses_event` |
| `codex-rs/core/src/codex.rs` | Codex 主逻辑，包含重试循环 `run_sampling_loop` |
| `codex-rs/core/src/model_provider_info.rs` | 模型提供商配置，包含重试参数定义 |
| `codex-rs/core/src/client.rs` | ModelClient 实现，处理流传输和重试 |

### 关键函数调用链

```
测试入口
└── stream_no_completed::retries_on_early_close
    ├── load_sse_fixture("tests/fixtures/incomplete_sse.json")
    │   └── 读取并转换 JSON 为 SSE 格式
    ├── start_streaming_sse_server([incomplete_sse, completed_sse])
    │   └── 启动模拟服务器，按顺序返回两个响应
    ├── test_codex().build_with_streaming_server()
    │   └── 构建测试环境
    ├── codex.submit(Op::UserInput)
    │   └── 提交用户输入，触发 Turn 执行
    │       └── codex::run_sampling_loop
    │           ├── try_run_sampling_request (第 1 次)
    │           │   └── 接收 incomplete_sse，流异常关闭
    │           ├── 检测到错误，检查重试预算
    │           ├── try_run_sampling_request (第 2 次，重试)
    │           │   └── 接收 completed_sse，成功完成
    │           └── 返回 TurnOutput
    └── 验证请求次数 == 2（原始 + 重试）
```

## 依赖与外部交互

### 内部依赖

```
codex-rs/core/tests/fixtures/incomplete_sse.json
├── codex-rs/core/tests/suite/stream_no_completed.rs (直接使用者)
│   ├── codex-rs/core/tests/common/lib.rs (load_sse_fixture)
│   ├── codex-rs/core/tests/common/streaming_sse.rs (StreamingSseServer)
│   └── codex-rs/core/tests/common/responses.rs (sse_completed)
├── codex-rs/core/src/codex.rs (重试逻辑)
│   ├── codex-rs/core/src/model_provider_info.rs (配置)
│   └── codex-rs/core/src/client.rs (ModelClient)
└── codex-rs/codex-api/src/sse/responses.rs (SSE 处理)
```

### 外部依赖

- **tokio**: 异步运行时，用于测试服务器和流处理
- **serde_json**: JSON 解析
- **eventsource_stream**: SSE 流解析
- **wiremock**: HTTP 模拟服务器（其他测试使用）

### 配置依赖

测试依赖以下配置参数：

```rust
ModelProviderInfo {
    request_max_retries: Some(0),      // 禁用 HTTP 请求重试
    stream_max_retries: Some(1),       // 允许 1 次流重试
    stream_idle_timeout_ms: Some(2000), // 2 秒空闲超时
    // ...
}
```

## 风险、边界与改进建议

### 当前风险

1. **测试覆盖局限**
   - 当前仅测试了单个事件缺失 `response.completed` 的情况
   - 未覆盖网络中断、连接重置等更底层的错误场景
   - 未测试重试预算耗尽后的降级行为

2. **夹具单一性**
   - 仅包含 `response.output_item.done` 事件
   - 未测试其他事件类型缺失 `response.completed` 的情况
   - 未测试空事件数组（完全空响应）的情况

3. **时序敏感**
   - 测试使用 `stream_idle_timeout_ms: 2000`，可能在慢速环境（如 CI）中不稳定
   - 未测试超时与重试的交互

### 边界情况

| 边界情况 | 当前处理 | 建议 |
|---------|---------|------|
| 空 SSE 流（无任何事件） | 返回 "stream closed before response.completed" | 已正确处理，但需确保有测试覆盖 |
| 仅 `response.created` 无 `completed` | 同上空流处理 | 建议添加专门夹具测试 |
| 多个 `output_item.done` 后无 `completed` | 同上空流处理 | 建议添加专门夹具测试 |
| `response.failed` 后无 `completed` | 优先返回 failed 错误 | 已有测试覆盖 |
| 重试预算为 0 | 直接返回错误 | 建议添加测试验证 |

### 改进建议

#### 1. 扩展测试夹具

建议添加以下夹具文件：

```json
// empty_sse.json - 完全空响应
[]

// only_created_sse.json - 仅有 created 事件
[
  {"type": "response.created", "response": {"id": "resp-1"}}
]

// multiple_items_no_completed.json - 多个 items 但无 completed
[
  {"type": "response.output_item.done", "item": {...}},
  {"type": "response.output_item.done", "item": {...}}
]
```

#### 2. 增强测试场景

```rust
// 建议添加的测试用例

/// 测试空响应触发重试
#[tokio::test]
async fn retries_on_empty_stream() { ... }

/// 测试重试预算耗尽后失败
#[tokio::test]
async fn fails_when_retry_budget_exhausted() { ... }

/// 测试 WebSocket -> HTTP 降级
#[tokio::test]
async fn falls_back_to_http_after_websocket_failure() { ... }
```

#### 3. 配置优化

建议将测试超时配置为可环境变量覆盖：

```rust
let timeout_ms = std::env::var("TEST_STREAM_IDLE_TIMEOUT_MS")
    .ok()
    .and_then(|s| s.parse().ok())
    .unwrap_or(2000);
```

#### 4. 监控与可观测性

建议在重试逻辑中添加更详细的遥测：

```rust
// 在 codex.rs 的重试循环中
tracing::info!(
    retry_count = retries,
    max_retries = max_retries,
    error = %err,
    "sse_stream_retry_initiated"
);
```

#### 5. 文档完善

- 在夹具文件顶部添加注释说明用途
- 在测试文件中添加更详细的注释解释测试逻辑
- 在开发者文档中说明 SSE 流终止检测机制

### 相关 Issue/PR 参考

- 该夹具与流重试机制相关，可能涉及以下方面的变更：
  - SSE 协议版本升级
  - 重试策略调整
  - 错误处理改进
  - 传输层（WebSocket/HTTP）切换逻辑

---

**文档版本**: 2026-03-23  
**最后更新**: 基于 codex-rs 代码库当前状态
