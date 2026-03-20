# Research: codex-rs/core/tests/fixtures

## 概述

`codex-rs/core/tests/fixtures` 是 Codex Rust 核心测试框架的测试夹具（fixtures）目录，用于存储测试所需的静态数据文件。该目录目前包含一个关键的 SSE（Server-Sent Events）测试夹具文件，用于测试流式响应的边界情况。

---

## 场景与职责

### 核心职责

1. **提供静态测试数据**：为集成测试提供可复用的、版本控制的测试数据文件
2. **模拟异常场景**：存储用于测试错误处理和边界情况的特殊数据文件
3. **SSE 流测试支持**：专门支持 Server-Sent Events 流式响应的测试场景

### 使用场景

- **流式响应中断测试**：模拟 SSE 流在未发送 `response.completed` 事件时提前关闭的情况
- **重试逻辑验证**：验证客户端在遇到不完整 SSE 流时的自动重试行为
- **错误恢复测试**：测试客户端从异常流状态恢复的能力

---

## 功能点目的

### 1. `incomplete_sse.json` - 不完整 SSE 流夹具

**文件内容**：
```json
[
  {"type": "response.output_item.done"}
]
```

**设计目的**：
- 模拟一个"不完整"的 SSE 流，该流只发送了 `response.output_item.done` 事件，但没有发送 `response.completed` 事件
- 用于测试客户端的重试机制：当 SSE 流异常终止（没有正常结束事件）时，客户端应该能够检测并重新请求
- 验证 `stream_no_completed.rs` 测试用例中的重试逻辑

**技术意义**：
- 在正常的 OpenAI Responses API 流式响应中，`response.completed` 事件标志着响应的完整结束
- 缺少该事件通常表示连接中断或服务器异常
- 该夹具帮助测试客户端的健壮性和容错能力

---

## 具体技术实现

### SSE 夹具加载机制

#### 1. 夹具加载函数 (`common/lib.rs`)

```rust
/// Builds an SSE stream body from a JSON fixture.
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

**关键逻辑**：
- 读取 JSON 数组，每个元素代表一个 SSE 事件
- `type` 字段映射到 SSE 的 `event:` 行
- 如果对象只有一个字段（仅 `type`），则不生成 `data:` 部分
- 否则，将整个对象序列化为 `data:` 行

#### 2. 资源定位宏 (`codex_utils_cargo_bin::find_resource!`)

```rust
fn sse_incomplete() -> String {
    let fixture = find_resource!("tests/fixtures/incomplete_sse.json")
        .unwrap_or_else(|err| panic!("failed to resolve incomplete_sse fixture: {err}"));
    load_sse_fixture(fixture)
}
```

**功能**：
- 在运行时定位测试资源文件
- 支持 Cargo 和 Bazel 两种构建系统的资源路径解析
- 通过 `compile_data` 或 `build_script_data` 在 BUILD.bazel 中声明资源依赖

### 测试使用示例

#### `stream_no_completed.rs` - 流中断重试测试

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn retries_on_early_close() {
    skip_if_no_network!();

    let incomplete_sse = sse_incomplete();
    let completed_sse = responses::sse_completed("resp_ok");

    let (server, _) = start_streaming_sse_server(vec![
        vec![StreamingSseChunk {
            gate: None,
            body: incomplete_sse,
        }],
        vec![StreamingSseChunk {
            gate: None,
            body: completed_sse,
        }],
    ])
    .await;

    // Configure retry behavior...
    let model_provider = ModelProviderInfo {
        // ...
        stream_max_retries: Some(1),  // 允许 1 次重试
        stream_idle_timeout_ms: Some(2000),
        // ...
    };

    // 提交用户输入...
    codex.submit(Op::UserInput { ... }).await.unwrap();

    // 验证重试后成功完成
    wait_for_event(&codex, |event| matches!(event, EventMsg::TurnComplete(_))).await;

    // 验证发生了重试（2 个请求）
    let requests = server.requests().await;
    assert_eq!(requests.len(), 2, "expected retry after incomplete SSE stream");
}
```

**测试逻辑**：
1. 第一次响应发送不完整的 SSE 流（没有 `response.completed`）
2. 客户端检测到流异常终止，触发重试
3. 第二次响应发送完整的 SSE 流
4. 验证客户端成功完成回合，且总共发送了 2 个请求

---

## 关键代码路径与文件引用

### 目录结构

```
codex-rs/core/tests/fixtures/
└── incomplete_sse.json          # 不完整 SSE 流夹具
```

### 相关文件引用

| 文件路径 | 用途 |
|---------|------|
| `codex-rs/core/tests/fixtures/incomplete_sse.json` | 测试夹具：不完整 SSE 流 |
| `codex-rs/core/tests/common/lib.rs` | 夹具加载函数 `load_sse_fixture` |
| `codex-rs/core/tests/common/streaming_sse.rs` | 流式 SSE 测试服务器 |
| `codex-rs/core/tests/suite/stream_no_completed.rs` | 使用夹具的测试用例 |
| `codex-rs/core/tests/suite/client.rs` | 使用 `load_sse_fixture` 的客户端测试 |
| `codex-rs/core/tests/suite/review.rs` | 使用 `load_sse_fixture` 的审查测试 |

### Bazel 构建配置

在 `codex-rs/core/BUILD.bazel` 中，测试夹具通过 `compile_data` 或 `build_script_data` 声明：

```bazel
# 测试目标需要包含 fixtures 目录作为编译时数据
rust_test(
    name = "core_tests",
    compile_data = [
        "tests/fixtures/incomplete_sse.json",
        # ... 其他夹具
    ],
)
```

---

## 依赖与外部交互

### 内部依赖

```
fixtures/incomplete_sse.json
    ├── load_sse_fixture() [common/lib.rs]
    │   ├── std::fs::File::open()
    │   └── serde_json::from_reader()
    ├── find_resource! [codex_utils_cargo_bin]
    │   └── 支持 Cargo & Bazel 资源路径解析
    └── start_streaming_sse_server() [streaming_sse.rs]
        ├── tokio::net::TcpListener
        └── SSE 流模拟服务器
```

### 外部交互

| 组件 | 交互方式 | 说明 |
|-----|---------|------|
| `codex_utils_cargo_bin` | 宏调用 `find_resource!` | 运行时资源定位 |
| `serde_json` | 反序列化 | JSON 夹具解析 |
| `tokio` | 异步运行时 | 流式服务器和测试执行 |
| OpenAI Responses API | 协议模拟 | SSE 事件格式遵循 OpenAI API |

### SSE 事件格式

夹具中的 JSON 对象映射到 SSE 协议：

```json
{"type": "response.output_item.done"}
```

转换为 SSE：
```
event: response.output_item.done

```

对比完整响应：
```
event: response.created
data: {"type":"response.created","response":{"id":"resp-1"}}

event: response.completed
data: {"type":"response.completed","response":{"id":"resp-1",...}}

```

---

## 风险、边界与改进建议

### 当前风险

1. **单一夹具覆盖有限**：目前只有一个 `incomplete_sse.json` 夹具，无法覆盖所有 SSE 异常场景
2. **硬编码路径**：测试代码中硬编码了夹具路径，如果文件移动会导致测试失败
3. **无版本控制说明**：夹具文件没有文档说明其对应的 API 版本或协议版本

### 边界情况

1. **空数组夹具**：JSON 空数组 `[]` 会产生空 SSE 流，可能导致客户端无限等待
2. **超大夹具**：如果夹具文件过大，可能影响测试加载速度
3. **特殊字符**：JSON 中的特殊字符需要正确转义以符合 SSE 格式

### 改进建议

#### 1. 扩展夹具覆盖范围

建议添加以下夹具文件：

```
fixtures/
├── incomplete_sse.json              # 已存在：缺少 completed 事件
├── empty_sse.json                   # 新增：完全空的 SSE 流
├── malformed_sse.json               # 新增：格式错误的 SSE 事件
├── timeout_sse.json                 # 新增：模拟超时场景
├── retry_exhausted_sse.json         # 新增：重试次数耗尽场景
└── websocket_fallback_sse.json      # 新增：WebSocket 降级场景
```

#### 2. 添加夹具元数据

为每个夹具添加注释说明：

```json
{
  "_description": "模拟 SSE 流在发送 output_item.done 后异常关闭，缺少 response.completed 事件",
  "_api_version": "v1",
  "_scenario": "retry_on_incomplete_stream",
  "events": [
    {"type": "response.output_item.done"}
  ]
}
```

#### 3. 动态夹具生成

考虑使用代码生成复杂夹具，而非静态文件：

```rust
pub fn generate_sse_fixture(events: Vec<SseEvent>) -> String {
    // 动态生成 SSE 内容，支持更灵活的测试场景
}
```

#### 4. 夹具验证测试

添加测试确保夹具文件本身有效：

```rust
#[test]
fn validate_fixtures() {
    let fixture = load_sse_fixture("tests/fixtures/incomplete_sse.json");
    assert!(!fixture.is_empty());
    assert!(fixture.contains("event:"));
}
```

#### 5. 文档自动化

生成夹具文档脚本：

```bash
# 自动生成 fixtures/README.md 描述所有夹具用途
just generate-fixture-docs
```

---

## 总结

`codex-rs/core/tests/fixtures` 目录虽然简单，但在测试框架中扮演关键角色。`incomplete_sse.json` 夹具专门用于测试 SSE 流异常场景，是验证客户端重试机制的重要组成部分。建议未来扩展更多夹具以覆盖完整的异常场景矩阵，并添加自动化文档和验证机制。
