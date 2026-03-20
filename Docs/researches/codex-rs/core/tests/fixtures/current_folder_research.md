# Research: codex-rs/core/tests/fixtures

## 概述

`codex-rs/core/tests/fixtures` 是 Codex Rust 核心测试模块的测试夹具目录，用于存放测试所需的静态数据文件。该目录目前包含一个关键的 SSE（Server-Sent Events）测试夹具文件，用于测试流式响应的异常处理场景。

---

## 场景与职责

### 核心职责

1. **测试数据提供**: 为集成测试提供标准化的静态测试数据
2. **SSE 流模拟**: 提供不完整/异常的 SSE 流数据，用于测试系统的容错和重试机制
3. **边界条件测试**: 支持测试流式响应在异常终止情况下的行为

### 使用场景

| 场景 | 描述 |
|------|------|
| 流式响应异常测试 | 模拟 SSE 流在发送 `response.completed` 事件前意外终止的情况 |
| 重试机制验证 | 验证客户端在收到不完整响应后是否正确触发重试 |
| 错误恢复测试 | 测试系统从部分接收的 SSE 事件中恢复的能力 |

---

## 功能点目的

### 1. `incomplete_sse.json` - 不完整 SSE 流夹具

**文件内容**:
```json
[
  {"type": "response.output_item.done"}
]
```

**设计目的**:
- 模拟一个"不完整"的 SSE 流，该流只包含 `response.output_item.done` 事件
- 缺少正常的 `response.completed` 终止事件
- 用于测试客户端的重试逻辑：当 SSE 流意外关闭而没有发送完成事件时，系统应自动重试请求

**关键特性**:
- 格式：JSON 数组，每个元素代表一个 SSE 事件
- 事件类型：`response.output_item.done`（表示输出项完成）
- 缺失事件：`response.completed`（表示整个响应完成）

---

## 具体技术实现

### SSE 夹具加载机制

**加载函数**: `load_sse_fixture()` (位于 `codex-rs/core/tests/common/lib.rs`)

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

**转换逻辑**:
1. 读取 JSON 文件，解析为 `Vec<serde_json::Value>`
2. 每个 JSON 对象必须包含 `type` 字段，对应 SSE 的 `event:` 值
3. 如果对象只有 `type` 字段，生成无数据部分的 SSE 事件
4. 如果对象包含其他字段，将完整 JSON 作为 `data:` 行输出
5. 输出格式遵循 SSE 协议：`event: <type>\ndata: <json>\n\n`

### 资源定位机制

**宏**: `find_resource!` (位于 `codex-rs/utils/cargo-bin/src/lib.rs`)

```rust
#[macro_export]
macro_rules! find_resource {
    ($resource:expr) => {{
        let resource = std::path::Path::new(&$resource);
        if $crate::runfiles_available() {
            // Bazel 模式：通过 runfiles 解析
            $crate::resolve_bazel_runfile(option_env!("BAZEL_PACKAGE"), resource)
        } else {
            // Cargo 模式：基于 CARGO_MANIFEST_DIR 解析
            let manifest_dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
            Ok(manifest_dir.join(resource))
        }
    }};
}
```

**双构建系统支持**:
- **Cargo**: 使用 `CARGO_MANIFEST_DIR` 环境变量定位资源
- **Bazel**: 使用 `runfiles` 系统在沙盒环境中解析资源路径

### 测试用例实现

**测试文件**: `codex-rs/core/tests/suite/stream_no_completed.rs`

```rust
fn sse_incomplete() -> String {
    let fixture = find_resource!("tests/fixtures/incomplete_sse.json")
        .unwrap_or_else(|err| panic!("failed to resolve incomplete_sse fixture: {err}"));
    load_sse_fixture(fixture)
}

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
    
    // 配置 model_provider 允许 1 次流重试
    let model_provider = ModelProviderInfo {
        // ...
        stream_max_retries: Some(1),
        // ...
    };
    
    // 提交用户输入并等待 TurnComplete
    // 验证服务器收到 2 个请求（第一次失败，第二次成功）
    let requests = server.requests().await;
    assert_eq!(requests.len(), 2, "expected retry after incomplete SSE stream");
}
```

**测试流程**:
1. 加载 `incomplete_sse.json` 作为第一次响应（模拟异常）
2. 构造完整的 `completed_sse` 作为第二次响应（模拟重试成功）
3. 启动流式 SSE 服务器，配置两次响应
4. 配置 `ModelProviderInfo` 允许 1 次流重试 (`stream_max_retries: Some(1)`)
5. 提交用户输入，等待 `TurnComplete` 事件
6. 验证服务器收到 2 个请求，确认重试机制生效

---

## 关键代码路径与文件引用

### 文件结构

```
codex-rs/core/tests/fixtures/
└── incomplete_sse.json          # 不完整 SSE 流夹具
```

### 关键代码路径

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/tests/fixtures/incomplete_sse.json` | 测试夹具：不完整 SSE 流数据 |
| `codex-rs/core/tests/common/lib.rs` | 提供 `load_sse_fixture()` 加载函数 |
| `codex-rs/core/tests/common/streaming_sse.rs` | 流式 SSE 测试服务器实现 |
| `codex-rs/core/tests/suite/stream_no_completed.rs` | 使用夹具的测试用例 |
| `codex-rs/utils/cargo-bin/src/lib.rs` | 提供 `find_resource!` 宏 |

### 调用链

```
stream_no_completed.rs (测试)
    ├── find_resource!("tests/fixtures/incomplete_sse.json")
    │   └── codex-rs/utils/cargo-bin/src/lib.rs
    └── load_sse_fixture(fixture)
        └── codex-rs/core/tests/common/lib.rs
            └── 读取并解析 incomplete_sse.json
                └── 转换为 SSE 格式字符串
```

---

## 依赖与外部交互

### 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `codex_core::ModelProviderInfo` | 配置模型提供者和重试参数 |
| `codex_protocol::protocol::EventMsg` | 事件消息类型定义 |
| `core_test_support::load_sse_fixture` | SSE 夹具加载函数 |
| `core_test_support::streaming_sse` | 流式 SSE 测试服务器 |
| `codex_utils_cargo_bin::find_resource` | 资源定位宏 |

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `serde_json` | JSON 解析 |
| `tokio` | 异步运行时 |
| `wiremock` | HTTP 模拟服务器（其他测试用例） |

### 构建系统兼容性

该夹具目录支持两种构建系统：

1. **Cargo**: 通过 `CARGO_MANIFEST_DIR` 定位资源
2. **Bazel**: 通过 `runfiles` 系统在沙盒中解析资源路径

---

## 风险、边界与改进建议

### 当前风险

| 风险 | 描述 | 严重程度 |
|------|------|---------|
| 单一夹具 | 目录仅包含一个测试夹具，覆盖场景有限 | 低 |
| 硬编码路径 | 测试代码中硬编码夹具路径，移动文件需同步修改 | 低 |
| 无版本控制 | 夹具格式变更可能影响多个测试 | 低 |

### 边界条件

1. **SSE 格式兼容性**: 夹具格式必须与 `load_sse_fixture()` 函数的预期格式一致
2. **事件类型有效性**: `type` 字段必须是有效的 SSE 事件类型
3. **JSON 结构**: 必须是有效的 JSON 数组格式

### 改进建议

1. **扩展夹具覆盖**:
   - 添加更多异常场景夹具（如：无效 JSON、空数组、缺少 type 字段等）
   - 添加不同 SSE 事件类型的夹具

2. **文档化**:
   - 为每个夹具添加 README 说明其用途和格式规范
   - 添加夹具格式版本控制

3. **工具函数增强**:
   - 添加夹具验证工具，确保 JSON 格式符合 SSE 规范
   - 支持动态生成夹具，减少静态文件维护成本

4. **目录结构优化**:
   ```
   fixtures/
   ├── sse/
   │   ├── incomplete/
   │   │   └── output_item_done_only.json
   │   ├── errors/
   │   │   └── invalid_event_type.json
   │   └── complete/
   │       └── full_conversation.json
   └── README.md
   ```

### 相关测试覆盖

当前使用 `incomplete_sse.json` 的测试：
- `stream_no_completed::retries_on_early_close` - 验证 SSE 流异常终止时的重试机制

---

## 总结

`codex-rs/core/tests/fixtures` 是一个精简但关键的测试夹具目录，目前主要用于支持 SSE 流式响应的异常处理测试。`incomplete_sse.json` 夹具通过模拟不完整的 SSE 流（缺少 `response.completed` 事件），帮助验证系统的重试和容错机制。该目录的设计支持 Cargo 和 Bazel 双构建系统，通过 `find_resource!` 宏实现跨构建系统的资源定位。
