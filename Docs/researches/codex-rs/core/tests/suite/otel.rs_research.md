# otel.rs 研究文档

## 场景与职责

`otel.rs` 是 Codex 核心库的 OpenTelemetry (OTEL) 遥测系统集成测试套件。它负责验证 Codex 在与 OpenAI API 交互过程中产生的各类遥测事件是否正确记录，包括：

- API 请求/响应事件的记录
- SSE (Server-Sent Events) 流事件的追踪
- 工具调用结果 (tool_result) 的遥测
- 工具审批决策 (tool_decision) 的记录
- 会话生命周期事件 (conversation_starts) 的捕获

这些测试确保 Codex 的遥测系统能够准确地收集和报告运行时行为，用于监控、调试和分析。

## 功能点目的

### 1. API 请求遥测 (`responses_api_emits_api_request_event`)
验证当 Codex 向 OpenAI API 发送请求时，是否正确记录 `codex.api_request` 和 `codex.conversation_starts` 事件。

### 2. SSE 事件处理遥测
- **`process_sse_emits_tracing_for_output_item`**: 验证 SSE 流中的 `response.output_item.done` 事件被正确记录
- **`process_sse_emits_failed_event_on_parse_error`**: 验证 JSON 解析错误时的错误遥测
- **`process_sse_records_failed_event_when_stream_closes_without_completed`**: 验证流异常关闭时的错误处理
- **`process_sse_failed_event_records_response_error_message`**: 验证 `response.failed` 事件的错误消息捕获
- **`process_sse_emits_completed_telemetry`**: 验证 `response.completed` 事件的令牌使用统计

### 3. 响应项类型遥测 (`record_responses_sets_span_fields_for_response_events`)
验证不同类型的响应项（created, function_call, message, reasoning, text_delta 等）都被正确分类记录。

### 4. 工具结果遥测
- **`handle_response_item_records_tool_result_for_custom_tool_call`**: 自定义工具调用的结果记录
- **`handle_response_item_records_tool_result_for_function_call`**: 函数调用的结果记录
- **`handle_response_item_records_tool_result_for_local_shell_*`**: 本地 shell 调用的结果记录（包括 macOS 特定测试）

### 5. 工具决策遥测 (`handle_container_exec_*_records_tool_decision`)
验证不同来源的工具审批决策被正确记录：
- 配置自动批准 (config)
- 用户单次批准 (user approved)
- 用户会话级批准 (approved for session)
- 用户拒绝 (denied)
- 沙箱错误重试批准

## 具体技术实现

### 关键数据结构

```rust
// 日志字段提取辅助函数
fn extract_log_field(line: &str, key: &str) -> Option<String>
fn assert_empty_mcp_tool_fields(line: &str) -> Result<(), String>

// 工具决策断言辅助函数
fn tool_decision_assertion<'a>(
    call_id: &'a str,
    expected_decision: &'a str,
    expected_source: &'a str,
) -> impl Fn(&[&str]) -> Result<(), String> + 'a
```

### 测试框架集成

测试使用 `tracing_test::traced_test` 宏来捕获日志输出，并通过 `logs_assert` 宏验证特定日志事件的存在：

```rust
#[tokio::test]
#[traced_test]
async fn responses_api_emits_api_request_event() {
    // ... 测试逻辑
    logs_assert(|lines: &[&str]| {
        lines
            .iter()
            .find(|line| line.contains("codex.api_request"))
            .map(|_| Ok(()))
            .unwrap_or_else(|| Err("expected codex.api_request event".to_string()))
    });
}
```

### 手动订阅者测试

部分测试需要更精细的追踪控制，使用手动配置的 `tracing_subscriber`：

```rust
let buffer: &'static Mutex<Vec<u8>> = Box::leak(Box::new(Mutex::new(Vec::new())));
let subscriber = tracing_subscriber::fmt()
    .with_level(true)
    .with_ansi(false)
    .with_max_level(Level::TRACE)
    .with_span_events(FmtSpan::FULL)
    .with_writer(MockWriter::new(buffer))
    .finish();
let _guard = tracing::subscriber::set_default(subscriber);
```

### 遥测事件类型

根据 `codex-rs/otel/src/events/session_telemetry.rs` 的实现，主要遥测事件包括：

| 事件名称 | 触发时机 | 关键字段 |
|---------|---------|---------|
| `codex.api_request` | API 请求完成 | duration_ms, http.response.status_code, attempt, auth.* |
| `codex.conversation_starts` | 会话开始 | provider_name, auth.env_*, reasoning_effort, approval_policy |
| `codex.sse_event` | SSE 事件接收 | event.kind, duration_ms, error.message |
| `codex.tool_result` | 工具执行完成 | tool_name, call_id, arguments, duration_ms, success, output |
| `codex.tool_decision` | 工具审批决策 | tool_name, call_id, decision, source |

### 指标名称

根据 `codex-rs/otel/src/metrics/names.rs`：

```rust
pub const TOOL_CALL_COUNT_METRIC: &str = "codex.tool.call";
pub const TOOL_CALL_DURATION_METRIC: &str = "codex.tool.call.duration_ms";
pub const API_CALL_COUNT_METRIC: &str = "codex.api_request";
pub const API_CALL_DURATION_METRIC: &str = "codex.api_request.duration_ms";
pub const SSE_EVENT_COUNT_METRIC: &str = "codex.sse_event";
// ... 更多指标
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/core/tests/suite/otel.rs` - 本测试文件

### 被测试的源文件
- `codex-rs/otel/src/events/session_telemetry.rs` - 会话遥测核心实现
- `codex-rs/otel/src/metrics/names.rs` - 指标名称定义
- `codex-rs/core/src/otel_init.rs` - OTEL 提供者初始化

### 测试支持文件
- `codex-rs/core/tests/common/responses.rs` - Mock 服务器和 SSE 响应构建
- `codex-rs/core/tests/common/test_codex.rs` - TestCodex 测试工具
- `codex-rs/core/tests/common/lib.rs` - 通用测试工具

### 关键依赖
- `tracing` - 结构化日志记录
- `tracing_test` - 测试中的日志捕获
- `tracing_subscriber` - 日志订阅者配置
- `wiremock` - HTTP Mock 服务器

## 依赖与外部交互

### 内部依赖

```rust
// Codex 核心库
codex_core::config::Constrained
codex_core::features::Feature

// Codex 协议
codex_protocol::protocol::*
codex_protocol::user_input::UserInput

// 测试支持库
core_test_support::responses::*
core_test_support::test_codex::*
core_test_support::wait_for_event

// 追踪
tracing::Level
tracing_subscriber::fmt::format::FmtSpan
tracing_test::internal::MockWriter
```

### Mock 服务器交互

测试使用 `wiremock` 创建模拟的 OpenAI API 服务器：

```rust
let server = start_mock_server().await;
mount_sse_once(&server, sse(vec![ev_completed("done")])).await;
```

### 事件验证流程

1. 配置 Mock 服务器返回特定 SSE 事件序列
2. 创建 TestCodex 实例并提交用户输入
3. 等待特定事件（如 `TurnComplete`）
4. 使用 `logs_assert` 验证遥测日志内容

## 风险、边界与改进建议

### 当前风险

1. **平台限制**: `handle_response_item_records_tool_result_for_local_shell_call` 测试仅在 macOS 上运行（`#[cfg(target_os = "macos")]`），其他平台的本地 shell 遥测缺乏覆盖。

2. **日志解析脆弱性**: `extract_log_field` 函数使用简单的字符串匹配，如果日志格式改变可能导致测试失败。

3. **测试顺序依赖**: 部分测试依赖特定的 SSE 事件顺序，如果 OpenAI API 行为改变可能需要更新。

### 边界情况

1. **空 MCP 字段验证**: `assert_empty_mcp_tool_fields` 确保非 MCP 工具的 `mcp_server` 和 `mcp_server_origin` 字段为空。

2. **缺失 call_id 处理**: 测试验证当 `local_shell_call` 缺少 `call_id` 或 `id` 时的错误处理。

3. **SSE 流异常关闭**: 测试覆盖流在 `response.completed` 之前关闭的情况。

### 改进建议

1. **增加更多平台覆盖**: 为 Linux 和 Windows 添加本地 shell 遥测测试。

2. **结构化日志验证**: 考虑使用 JSON 结构化日志输出进行更可靠的验证，而非字符串匹配。

3. **性能测试**: 添加高并发场景下的遥测性能测试，确保遥测不会成为瓶颈。

4. **指标数值验证**: 当前测试主要验证事件存在性，可以增加对指标数值（如 duration_ms）的合理性验证。

5. **错误场景扩展**: 增加更多网络错误、超时、认证失败等场景下的遥测验证。

6. **文档化事件契约**: 在 `AGENTS.md` 或专门文档中明确遥测事件的字段契约，便于维护和消费者使用。
