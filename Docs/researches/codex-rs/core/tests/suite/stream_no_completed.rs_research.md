# stream_no_completed.rs 研究文档

## 场景与职责

`stream_no_completed.rs` 是 Codex Core 的集成测试套件，专注于验证 SSE 流在提前关闭（未发送 `response.completed` 事件）时的重试机制。该测试确保当 OpenAI API 的 SSE 流异常终止时，Codex 能够自动重试请求并最终成功完成对话。

### 核心职责
1. **不完整流重试验证**：验证 SSE 流提前关闭时的自动重试行为
2. **流完整性检测**：验证系统能够检测缺失 `response.completed` 事件的情况
3. **请求幂等性**：验证重试请求不会导致重复处理

## 功能点目的

### 提前关闭流重试 (`retries_on_early_close`)
- **目的**：确保当 SSE 流在发送 `response.completed` 之前关闭时，Codex 自动重试请求
- **验证点**：
  - 第一次请求返回不完整的 SSE 流（无 `completed` 事件）
  - 系统自动发起第二次请求
  - 第二次请求成功完成
  - 总共发送 2 个请求（1 个失败 + 1 个成功）

### 关键测试逻辑
```rust
// 1. 第一次：不完整的 SSE 流
let incomplete_sse = sse_incomplete(); // 只有 response.output_item.done，无 completed

// 2. 第二次：完整的 SSE 流
let completed_sse = responses::sse_completed("resp_ok");

// 3. 配置流式服务器返回两次响应
let (server, _) = start_streaming_sse_server(vec![
    vec![StreamingSseChunk { gate: None, body: incomplete_sse }],
    vec![StreamingSseChunk { gate: None, body: completed_sse }],
]).await;

// 4. 提交请求并等待完成
codex.submit(Op::UserInput { ... }).await?;
wait_for_event(&codex, |event| matches!(event, EventMsg::TurnComplete(_))).await;

// 5. 验证发送了 2 个请求
let requests = server.requests().await;
assert_eq!(requests.len(), 2, "expected retry after incomplete SSE stream");
```

## 具体技术实现

### 不完整 SSE 流构造
```rust
fn sse_incomplete() -> String {
    let fixture = find_resource!("tests/fixtures/incomplete_sse.json")
        .unwrap_or_else(|err| panic!("failed to resolve incomplete_sse fixture: {err}"));
    load_sse_fixture(fixture)
}
```

#### Fixture 内容 (`incomplete_sse.json`)
```json
[
  {"type": "response.output_item.done"}
]
```

### 流式 SSE 服务器配置
```rust
let (server, _) = start_streaming_sse_server(vec![
    // 第一次响应：不完整流
    vec![StreamingSseChunk {
        gate: None, // 无延迟，立即发送
        body: incomplete_sse,
    }],
    // 第二次响应：完整流
    vec![StreamingSseChunk {
        gate: None,
        body: completed_sse,
    }],
]).await;
```

### 模型提供商重试配置
```rust
let model_provider = ModelProviderInfo {
    name: "openai".into(),
    base_url: Some(format!("{}/v1", server.uri())),
    env_key: Some("PATH".into()), // 使用 PATH 作为占位符
    wire_api: WireApi::Responses,
    // 重试配置
    request_max_retries: Some(0),      // 请求级别不重试
    stream_max_retries: Some(1),       // 流级别允许 1 次重试
    stream_idle_timeout_ms: Some(2000), // 2 秒空闲超时
    ...
};
```

### 关键设计决策
1. **`request_max_retries: Some(0)`**: 禁用请求级别重试，确保重试由流处理逻辑触发
2. **`stream_max_retries: Some(1)`**: 启用流级别重试，允许在流异常时重试一次
3. **`stream_idle_timeout_ms: Some(2000)`**: 设置 2 秒超时，快速检测流异常

## 关键代码路径与文件引用

### 被测代码路径
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/src/client.rs` | HTTP 客户端，处理 SSE 流和重试逻辑 |
| `codex-rs/core/src/stream_processor.rs` | 流处理器，检测 `completed` 事件 |
| `codex-rs/core/src/retry.rs` | 重试策略实现 |

### 测试依赖路径
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/tests/common/streaming_sse.rs` | `start_streaming_sse_server` 和 `StreamingSseChunk` |
| `codex-rs/core/tests/common/responses.rs` | `sse_completed` 构造器 |
| `codex-rs/core/tests/common/lib.rs` | `load_sse_fixture` 和 `wait_for_event` |
| `codex-rs/core/tests/fixtures/incomplete_sse.json` | 不完整 SSE 流 fixture |

### 关键类型引用
```rust
// core_test_support::streaming_sse
pub struct StreamingSseChunk {
    pub gate: Option<oneshot::Receiver<()>>, // 可选的延迟信号
    pub body: String,                        // SSE 事件体
}

pub struct StreamingSseServer {
    uri: String,
    requests: Arc<TokioMutex<Vec<Vec<u8>>>>,
    shutdown: oneshot::Sender<()>,
    task: tokio::task::JoinHandle<()>,
}

impl StreamingSseServer {
    pub fn uri(&self) -> &str;
    pub async fn requests(&self) -> Vec<Vec<u8>>;
    pub async fn shutdown(self);
}

// codex_utils_cargo_bin
pub fn find_resource!(path: &str) -> Result<PathBuf, CargoBinError>;
```

## 依赖与外部交互

### 外部依赖
1. **tokio**: 异步运行时 (`multi_thread` flavor)
2. **serde_json**: JSON 处理
3. **wiremock**: 用于其他测试，本测试使用自定义流式服务器

### 内部依赖
1. **codex_utils_cargo_bin**: 资源文件定位
2. **core_test_support**: 测试支持库

### 关键特性
- `#[tokio::test(flavor = "multi_thread", worker_threads = 2)]`: 多线程运行时

### 环境要求
- 网络访问（通过 `skip_if_no_network!` 宏在沙箱中跳过）
- `tests/fixtures/incomplete_sse.json` 资源文件

## 风险、边界与改进建议

### 已知风险
1. **资源文件依赖**：测试依赖 `incomplete_sse.json` 文件，如果文件丢失测试会失败
2. **时序敏感**：流空闲超时 2 秒，在慢速 CI 环境可能导致不稳定
3. **竞态条件**：`server.requests()` 和事件完成之间可能有竞态

### 边界情况
1. **多次重试**：测试仅验证 1 次重试，未验证多次重试失败后的行为
2. **部分事件**：fixture 只包含 `output_item.done`，未测试其他部分事件组合
3. **网络中断**：测试使用本地服务器，未测试真实网络中断场景

### 改进建议
1. **参数化重试次数**：测试不同 `stream_max_retries` 值的行为
2. **部分事件矩阵**：使用参数化测试覆盖不同的事件组合（有/无 created，有/无 output 等）
3. **超时调整**：根据 CI 环境动态调整超时时间
4. **资源文件内联**：考虑将 fixture 内容内联到测试代码，减少文件依赖
5. **重试延迟验证**：验证重试之间是否有适当的退避延迟

### 潜在缺陷
1. **无重试原因验证**：未验证重试是因为缺少 `completed` 事件而非其他原因
2. **无事件内容验证**：未验证最终成功响应包含预期的事件
3. **硬编码 fixture 路径**：路径相对于 crate 根目录，如果测试执行目录改变会失败

### 相关测试
- `stream_error_allows_next_turn.rs`: 测试 HTTP 错误后的恢复
- `client_websockets.rs`: 测试 WebSocket 传输的错误处理
