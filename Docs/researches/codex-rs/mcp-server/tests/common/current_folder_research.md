# DIR codex-rs/mcp-server/tests/common 研究文档

## 概述

`codex-rs/mcp-server/tests/common` 是 Codex MCP (Model Context Protocol) 服务器的集成测试支持库，crate 名为 `mcp_test_support`。它提供了测试 MCP 服务器所需的 Mock 服务器、进程管理和响应构造工具。

---

## 场景与职责

### 1. 测试基础设施支持

该目录作为 MCP 服务器集成测试的基础设施层，主要职责包括：

- **MCP 进程管理**：启动和控制 `codex-mcp-server` 二进制进程，处理 stdin/stdout 通信
- **Mock 模型服务器**：模拟 OpenAI Responses API 端点，提供可预测的 SSE 响应流
- **响应构造**：生成符合 OpenAI Responses API 格式的 SSE 事件流，用于模拟模型输出
- **测试工具复用**：复用 `core_test_support` 中的 shell 格式化等通用工具

### 2. 集成测试场景

支持的测试场景：
- Shell 命令执行审批流程测试（`exec-approval` elicitation）
- Patch 应用审批流程测试（`patch-approval` elicitation）
- Codex 工具调用参数传递测试（base instructions, developer instructions）
- MCP 协议初始化握手测试

---

## 功能点目的

### 1. `McpProcess` - MCP 进程管理器

**目的**：封装与 `codex-mcp-server` 子进程的 JSON-RPC 通信

**核心能力**：
- 进程生命周期管理（启动、环境变量注入、优雅终止）
- MCP 协议初始化握手（`initialize` → `notifications/initialized`）
- JSON-RPC 消息序列化/反序列化
- 请求-响应关联追踪（通过 `request_id`）
- 流式消息读取（支持 notification 过滤）

### 2. `create_mock_responses_server` - Mock 模型服务器

**目的**：创建模拟的 OpenAI Responses API 服务器

**核心能力**：
- 基于 `wiremock` 的 HTTP Mock 服务器
- 顺序响应模式（SeqResponder）：按顺序返回预定义的 SSE 响应
- 精确匹配 `/v1/responses` POST 端点
- 支持自定义响应头和状态码

### 3. 响应构造函数

**目的**：生成符合 OpenAI Responses API 格式的 SSE 事件流

| 函数 | 用途 |
|------|------|
| `create_shell_command_sse_response` | 模拟模型返回 shell 命令调用的响应 |
| `create_apply_patch_sse_response` | 模拟模型返回 apply_patch 命令的响应 |
| `create_final_assistant_message_sse_response` | 模拟模型返回最终文本回复的响应 |

---

## 具体技术实现

### 1. 关键流程

#### MCP 初始化握手流程

```
测试客户端                          MCP 服务器
    |                                   |
    |-- initialize (request_id=0) ---->|
    |                                   |
    |<-- InitializeResult -------------|
    |    (serverInfo, capabilities)     |
    |                                   |
    |-- notifications/initialized ---->|
    |                                   |
   [握手完成，可以发送工具调用]
```

**代码位置**：`mcp_process.rs:112-197`

#### Shell 命令审批测试流程

```
测试客户端                          MCP 服务器
    |                                   |
    |-- tools/call (codex) ----------->|
    |    prompt: "run `git init`"       |
    |                                   |
    |<-- elicitation/create -----------|
    |    (ExecApprovalElicitRequest)    |
    |                                   |
    |-- response (approval) ---------->|---> CodexThread
    |    decision: Approved             |     (submit Op::ExecApproval)
    |                                   |
    |<-- codex/event (task_complete) --|
    |                                   |
    |<-- tools/call response -----------|
    |    (CallToolResult with content)  |
```

**代码位置**：`tests/suite/codex_tool.rs:38-179`

### 2. 数据结构

#### `McpProcess` 结构

```rust
pub struct McpProcess {
    next_request_id: AtomicI64,     // 自增请求 ID 生成器
    process: Child,                  // 子进程句柄（保留至 Drop）
    stdin: ChildStdin,              // 标准输入（JSON-RPC 写入）
    stdout: BufReader<ChildStdout>, // 标准输出（JSON-RPC 读取）
}
```

**代码位置**：`mcp_process.rs:34-43`

#### `SeqResponder` - 顺序响应器

```rust
struct SeqResponder {
    num_calls: AtomicUsize,
    responses: Vec<String>,  // SSE 响应体列表
}

impl Respond for SeqResponder {
    fn respond(&self, _: &wiremock::Request) -> ResponseTemplate {
        let call_num = self.num_calls.fetch_add(1, Ordering::SeqCst);
        match self.responses.get(call_num) {
            Some(response) => ResponseTemplate::new(200)
                .insert_header("content-type", "text/event-stream")
                .set_body_raw(response.clone(), "text/event-stream"),
            None => panic!("no response for {call_num}"),
        }
    }
}
```

**代码位置**：`mock_model_server.rs:32-47`

### 3. 协议细节

#### JSON-RPC 2.0 消息格式

使用 `rmcp` crate 的类型系统：

```rust
// 请求
JsonRpcMessage::Request(JsonRpcRequest {
    jsonrpc: JsonRpcVersion2_0,
    id: RequestId::Number(request_id),
    request: CustomRequest::new(method, params),
})

// 响应
JsonRpcMessage::Response(JsonRpcResponse {
    jsonrpc: JsonRpcVersion2_0,
    id,
    result,
})

// Notification
JsonRpcMessage::Notification(JsonRpcNotification {
    jsonrpc: JsonRpcVersion2_0,
    notification: CustomNotification::new(method, params),
})
```

#### SSE 事件格式

```
event: response.created
data: {"type":"response.created","response":{"id":"resp-123"}}

event: response.output_item.done
data: {"type":"response.output_item.done","item":{"type":"function_call","call_id":"call-1","name":"shell_command","arguments":"{\"command\":\"...\"}"}}

event: response.completed
data: {"type":"response.completed","response":{"id":"resp-123",...}}
```

**构造代码位置**：`responses.rs`

---

## 关键代码路径与文件引用

### 目录结构

```
codex-rs/mcp-server/tests/common/
├── Cargo.toml              # crate 配置，依赖 core_test_support
├── BUILD.bazel             # Bazel 构建配置
├── lib.rs                  # 模块聚合与公共导出
├── mcp_process.rs          # MCP 进程管理（McpProcess）
├── mock_model_server.rs    # Mock Responses API 服务器
└── responses.rs            # SSE 响应构造工具
```

### 关键文件引用

| 文件 | 行数 | 核心内容 |
|------|------|----------|
| `lib.rs` | 22 | 模块声明、公共导出、`to_response` 辅助函数 |
| `mcp_process.rs` | 399 | `McpProcess` 完整实现，包含初始化、消息收发、Drop 清理 |
| `mock_model_server.rs` | 47 | `create_mock_responses_server` 和 `SeqResponder` |
| `responses.rs` | 47 | 三个 SSE 响应构造函数 |
| `Cargo.toml` | 28 | 依赖声明，包括 `core_test_support`, `rmcp`, `wiremock` |

### 被调用方（测试代码）

| 文件 | 用途 |
|------|------|
| `tests/all.rs` | 测试入口，聚合 suite 模块 |
| `tests/suite/codex_tool.rs` | 主要集成测试，测试 shell/patch 审批流程 |

### 依赖的外部库

| crate | 用途 |
|-------|------|
| `rmcp` | MCP 协议类型（JsonRpcMessage, RequestId 等） |
| `wiremock` | HTTP Mock 服务器 |
| `tokio` | 异步运行时、进程管理 |
| `serde_json` | JSON 序列化/反序列化 |
| `core_test_support` | 复用 core 测试库的响应构造工具 |
| `codex-mcp-server` | 被测 crate 的公共类型 |

---

## 依赖与外部交互

### 1. 与 `core_test_support` 的集成

```rust
// lib.rs
pub use core_test_support::format_with_current_shell;
pub use core_test_support::format_with_current_shell_display_non_login;
pub use core_test_support::format_with_current_shell_non_login;
```

复用核心测试库的 shell 格式化工具，确保测试环境与实际 shell 配置一致。

### 2. 与 `codex-mcp-server` 的集成

```rust
// mcp_process.rs
use codex_mcp_server::CodexToolCallParam;

// responses.rs
use core_test_support::responses;
```

使用被测 crate 的公共类型（如 `CodexToolCallParam`）构造工具调用请求。

### 3. 与 `codex_protocol` 的集成

通过 `core_test_support::responses` 间接使用：
- `responses::sse()` - 构建 SSE 流
- `responses::ev_response_created()` - response.created 事件
- `responses::ev_function_call()` - function_call 事件
- `responses::ev_completed()` - response.completed 事件

### 4. 进程间通信协议

```rust
// MCP 服务器启动命令
codex_utils_cargo_bin::cargo_bin("codex-mcp-server")

// 环境变量注入
CODEX_HOME=codex_home_path
RUST_LOG=debug
```

---

## 风险、边界与改进建议

### 1. 当前风险

#### 进程清理竞态条件

```rust
// mcp_process.rs:371-398
impl Drop for McpProcess {
    fn drop(&mut self) {
        let _ = self.process.start_kill();
        let start = std::time::Instant::now();
        let timeout = std::time::Duration::from_secs(5);
        while start.elapsed() < timeout {
            match self.process.try_wait() {
                Ok(Some(_)) => return,
                Ok(None) => std::thread::sleep(std::time::Duration::from_millis(10)),
                Err(_) => return,
            }
        }
    }
}
```

**风险**：同步 Drop 中的轮询等待可能阻塞异步运行时，5 秒超时在 CI 环境下可能不足。

#### Mock 服务器响应耗尽

```rust
// mock_model_server.rs:44
None => panic!("no response for {call_num}"),
```

**风险**：如果测试发送的请求数超过预定义的响应数，会 panic 而非优雅降级。

#### 硬编码超时

```rust
// tests/suite/codex_tool.rs:33
const DEFAULT_READ_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(20);
```

**风险**：20 秒超时在慢速 CI 环境或资源受限环境下可能导致 flaky 测试。

### 2. 边界情况

| 场景 | 当前行为 | 潜在问题 |
|------|----------|----------|
| 网络禁用环境 | 测试通过检查 `CODEX_SANDBOX_NETWORK_DISABLED` 跳过 | 测试覆盖率下降 |
| Windows 平台 | Patch 审批测试直接返回 Ok(()) | 平台特定功能未测试 |
| 并发请求 | `McpProcess` 使用 `&mut self` 确保串行访问 | 无法测试并发场景 |
| 大量 stderr 输出 | 通过 spawned task 转发到 eprintln | 可能淹没测试输出 |

### 3. 改进建议

#### 建议 1：使用异步 Drop 模式

考虑使用 `tokio::sync::mpsc` 或 `async-drop` 模式替代同步轮询：

```rust
// 可能的改进
async fn shutdown(mut self) -> anyhow::Result<()> {
    self.process.kill().await?;
    self.process.wait().await?;
    Ok(())
}
```

#### 建议 2：Mock 服务器循环响应模式

为 `SeqResponder` 添加循环模式选项，支持无限请求：

```rust
enum ResponseMode {
    Sequential,  // 当前行为：耗尽后 panic
    Cyclic,      // 循环使用响应列表
    LastRepeat,  // 耗尽后重复最后一个响应
}
```

#### 建议 3：可配置超时

通过环境变量或参数化允许测试自定义超时：

```rust
fn get_read_timeout() -> Duration {
    env::var("MCP_TEST_TIMEOUT_SECS")
        .ok()
        .and_then(|s| s.parse().ok())
        .map(Duration::from_secs)
        .unwrap_or(DEFAULT_READ_TIMEOUT)
}
```

#### 建议 4：增强错误上下文

在 `McpProcess` 方法中添加更多诊断信息：

```rust
pub async fn read_stream_until_response_message(
    &mut self,
    request_id: RequestId,
) -> anyhow::Result<JsonRpcResponse<serde_json::Value>> {
    let start = Instant::now();
    loop {
        if start.elapsed() > timeout {
            anyhow::bail!("Timeout waiting for response to request {request_id:?}")
        }
        // ...
    }
}
```

#### 建议 5：提取通用测试模式

将 `McpHandle` 和 `create_mcp_process` 模式提取到 common 库：

```rust
// 当前在 codex_tool.rs 中定义，可考虑上移
pub struct McpHandle {
    pub process: McpProcess,
    pub server: MockServer,
    pub dir: TempDir,
}
```

---

## 附录：类型对照表

| 本库类型 | 来源 | 用途 |
|----------|------|------|
| `McpProcess` | `mcp_process.rs` | MCP 服务器进程封装 |
| `SeqResponder` | `mock_model_server.rs` | 顺序 HTTP 响应 |
| `CodexToolCallParam` | `codex_mcp_server` | 工具调用参数 |
| `ExecApprovalElicitRequestParams` | `codex_mcp_server` | 执行审批请求参数 |
| `PatchApprovalElicitRequestParams` | `codex_mcp_server` | Patch 审批请求参数 |
| `JsonRpcMessage` | `rmcp` | JSON-RPC 消息枚举 |
| `RequestId` | `rmcp` | 请求标识符 |

---

*文档生成时间：2026-03-21*
*研究范围：codex-rs/mcp-server/tests/common 目录及其直接依赖*
